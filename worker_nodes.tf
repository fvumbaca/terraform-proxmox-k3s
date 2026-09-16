locals {
  # Number of worker IDs consumed by pools preceding each pool, so that
  # vm_id_start + 2 + masters + offset + index is unique across all workers.
  worker_pool_offsets = [
    for pi in range(length(var.node_pools)) :
    try(sum([for pool in slice(var.node_pools, 0, pi) : pool.size]), 0)
  ]

  listed_worker_nodes = flatten([
    for pi, pool in var.node_pools :
    [
      for i in range(pool.size) :
      merge(pool.node_pool_settings, {
        target_node = pool.target_node
        i           = i
        vm_id       = var.vm_id_start + 2 + length(var.master_nodes) + local.worker_pool_offsets[pi] + i
        ip          = cidrhost(pool.subnet, i + 1)
      })
    ]
  ])

  mapped_worker_nodes = {
    for node in local.listed_worker_nodes : "${node.name}-${node.i}" => node
  }

}

resource "proxmox_virtual_environment_vm" "k3s-worker" {
  depends_on = [
    proxmox_virtual_environment_vm.k3s-support,
    proxmox_virtual_environment_vm.k3s-master,
  ]

  for_each = local.mapped_worker_nodes

  node_name = each.value.target_node
  name      = "${var.cluster_name}-${each.key}"
  vm_id     = each.value.vm_id

  clone {
    vm_id = local.effective_template_vm_id[each.value.target_node]
  }

  pool_id    = var.proxmox_resource_pool != "" ? var.proxmox_resource_pool : null
  on_boot    = true
  protection = var.protection
  tags       = [var.cluster_name]

  # Boot last: support -> masters -> workers.
  startup {
    order      = "3"
    up_delay   = "30"
    down_delay = "30"
  }

  # The module installs qemu-guest-agent during provisioning; flip
  # vm_agent_enabled to true after the first apply.
  agent {
    enabled = var.vm_agent_enabled
  }

  stop_on_destroy = true

  cpu {
    cores   = each.value.cores
    sockets = each.value.sockets
    type    = var.cpu_type
  }

  memory {
    dedicated = each.value.memory
  }

  scsi_hardware = "virtio-scsi-pci"

  # Boot disk
  disk {
    datastore_id = each.value.storage_id
    interface    = "scsi0"
    size         = tonumber(replace(each.value.disk_size, "/[Gg]/", ""))
  }

  dynamic "disk" {
    for_each = each.value.additional_storage != null ? [each.value.additional_storage] : []
    content {
      datastore_id = disk.value.storage_id
      interface    = "scsi1"
      size         = tonumber(replace(disk.value.disk_size, "/[Gg]/", ""))
    }
  }

  initialization {
    datastore_id = each.value.storage_id

    ip_config {
      ipv4 {
        address = "${each.value.ip}/${local.lan_subnet_cidr_bitnum}"
        gateway = var.network_gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      username = each.value.user
      keys     = [trimspace(file(var.authorized_keys_file))]
    }
  }

  network_device {
    bridge   = each.value.network_bridge
    firewall = true
    model    = "virtio"
    vlan_id  = each.value.network_tag >= 0 ? each.value.network_tag : null
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes = [
      disk,
      network_device,
    ]
  }

  connection {
    type        = "ssh"
    user        = each.value.user
    host        = each.value.ip
    private_key = var.ssh_agent_auth ? null : file(var.authorized_private_key_file)
    agent       = var.ssh_agent_auth
  }

  # Install open-iscsi (Longhorn prerequisite) before k3s. No-op when
  # longhorn_enabled = false.
  provisioner "file" {
    destination = "/tmp/install-iscsi.sh"
    content = templatefile("${path.module}/scripts/install-iscsi.sh.tftpl", {
      iscsi_enabled = var.longhorn_enabled
      http_proxy    = var.http_proxy
      no_proxy      = local.effective_no_proxy
    })
  }

  provisioner "remote-exec" {
    inline = [
      "chmod u+x /tmp/install-iscsi.sh",
      "sh /tmp/install-iscsi.sh",
      "rm -f /tmp/install-iscsi.sh",
    ]
  }

  provisioner "remote-exec" {
    inline = ["sleep 5",
      templatefile("${path.module}/scripts/install-k3s.sh.tftpl", {
        mode                        = "agent"
        tokens                      = [random_password.k3s-server-token.result]
        alt_names                   = []
        disable                     = []
        server_hosts                = ["https://${local.api_endpoint}:6443"]
        node_taints                 = each.value.taints
        node_labels                 = each.value.node_labels
        datastores                  = []
        http_proxy                  = var.http_proxy
        no_proxy                    = local.effective_no_proxy
        k3s_version                 = var.k3s_version
        k3s_install_commit          = var.k3s_install_commit
        cluster_cidr                = var.cluster_cidr
        service_cidr                = var.service_cidr
        extra_args                  = var.k3s_extra_agent_args
        etcd_snapshot_schedule_cron = ""
        extra_storage_enable        = each.value.additional_storage != null ? true : false
        # This is when initializing etcd for the first time. It is always false on worker nodes.
        embedded_etcd_init = false
      })
    , "sleep 5"]
  }
}
