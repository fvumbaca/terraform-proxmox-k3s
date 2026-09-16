locals {
  # Every node that will host a VM therefore needs a template present on that
  # node. The bpg provider clones by looking for the template on the target
  # node, so with node-local (non-shared) storage each node must have its own.
  template_target_nodes = distinct(concat(
    var.support_node_enabled ? [var.support_node_settings.target_node] : [],
    [for m in var.master_nodes : m.target_node],
    [for p in var.node_pools : p.target_node]
  ))

  # Stable per-node template VM IDs, kept in a range separate from the node
  # VMs (which start at vm_id_start) so the two never collide:
  # template_vm_id_base + index in the sorted node list.
  node_template_ids = {
    for idx, node in sort(local.template_target_nodes) :
    node => var.template_vm_id_base + idx
  }

  # Map each target node to the template VM ID to clone from. When a single
  # template_vm_id is supplied (shared-storage setups) every node clones it;
  # otherwise each node clones its own locally-built template.
  effective_template_vm_id = var.template_vm_id != null ? {
    for node in local.template_target_nodes : node => var.template_vm_id
    } : {
    for node in local.template_target_nodes :
    node => proxmox_virtual_environment_vm.k3s_template[node].vm_id
  }
}

resource "proxmox_download_file" "k3s_template_image" {
  for_each = var.template_image != null ? toset(local.template_target_nodes) : toset([])

  content_type = "import"
  # The downloaded image needs a datastore with the "import" content type, which
  # may differ from the datastore the template disk lives on (which needs the
  # "images" content type). Use import_datastore_id when they differ.
  datastore_id = coalesce(var.template_image.import_datastore_id, var.template_image.datastore_id)
  node_name    = each.value
  file_name    = var.template_image.file_name
  url          = var.template_image.url
}

resource "proxmox_virtual_environment_vm" "k3s_template" {
  for_each = var.template_image != null ? toset(local.template_target_nodes) : toset([])

  node_name = each.value
  name      = "${var.cluster_name}-template-${each.value}"
  vm_id     = local.node_template_ids[each.value]

  template        = true
  stop_on_destroy = true

  agent {
    enabled = false
  }

  cpu {
    cores = 2
    type  = var.cpu_type
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = var.template_image.datastore_id
    import_from  = proxmox_download_file.k3s_template_image[each.value].id
    interface    = "scsi0"
    size         = var.template_image.disk_size
  }

  initialization {
    datastore_id = var.template_image.datastore_id

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      username = var.template_image.user
      keys     = [trimspace(file(var.authorized_keys_file))]
    }
  }

  network_device {
    bridge = var.template_image.network_bridge
  }

  tags = [var.cluster_name]
}
