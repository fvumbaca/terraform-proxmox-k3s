resource "macaddress" "k3s-workers" {
  for_each = local.mapped_worker_nodes
}

locals {
  listed_worker_nodes = flatten([
    for pool in var.node_pools :
    [
      for i in range(pool.size) :
      merge({
        i = i
      }, pool)
    ]
  ])

  mapped_worker_nodes = {
    for node in local.listed_worker_nodes : "${node.name}-${node.i}" =>
    merge(node, {
      ip      = cidrhost(node.subnet, node.i + node.ip_offset)
      ciuser  = coalesce(node.ciuser, var.default_node_settings.ciuser)
      gw      = coalesce(node.gw, var.default_node_settings.gw)
      sshkeys = coalesce(node.authorized_keys, var.default_node_settings.authorized_keys)
    })
  }

  worker_node_ips = [for node in local.mapped_worker_nodes : node.ip]
}

resource "proxmox_vm_qemu" "k3s-worker" {
  depends_on = [
    proxmox_vm_qemu.k3s-support,
    proxmox_vm_qemu.k3s-master,
  ]

  for_each = local.mapped_worker_nodes


  #
  target_node = coalesce(each.value.target_node, var.default_node_settings.target_node)
  name        = "${var.cluster_name}-${each.key}"
  clone       = coalesce(each.value.image_id, var.default_node_settings.image_id)
  full_clone  = coalesce(each.value.full_clone, var.default_node_settings.full_clone)
  pool        = coalesce(each.value.target_pool, var.default_node_settings.target_pool)
  cores       = coalesce(each.value.cores, var.default_node_settings.cores)
  sockets     = coalesce(each.value.sockets, var.default_node_settings.sockets)
  memory      = coalesce(each.value.memory, var.default_node_settings.memory)
  ciuser      = each.value.ciuser
  ipconfig0   = "ip=${each.value.ip}/${local.lan_subnet_cidr_bitnum},gw=${each.value.gw}"
  sshkeys     = coalesce(each.value.authorized_keys, var.default_node_settings.authorized_keys)
  nameserver  = coalesce(each.value.nameserver, var.default_node_settings.nameserver)
  os_type     = "cloud-init"
  agent       = 1

  disk {
    type    = coalesce(each.value.disk_type, var.default_node_settings.disk_type)
    storage = coalesce(each.value.storage_id, var.default_node_settings.storage_id)
    size    = coalesce(each.value.disk_size, var.default_node_settings.disk_size)
  }

  network {
    bridge    = coalesce(each.value.network_bridge, var.default_node_settings.network_bridge)
    firewall  = coalesce(each.value.firewall, var.default_node_settings.firewall)
    link_down = false
    macaddr   = upper(macaddress.k3s-workers[each.key].address)
    model     = "virtio"
    queues    = 0
    rate      = 0
    tag       = coalesce(each.value.network_tag, var.default_node_settings.network_tag)
  }

  lifecycle {
    ignore_changes = [
      ciuser,
      sshkeys,
      disk,
      network,
      desc,
      searchdomain,
      bootdisk
    ]
  }


  connection {
    type = "ssh"
    user = each.value.ciuser
    host = each.value.ip
  }

  provisioner "remote-exec" {
    inline = [
      templatefile("${path.module}/scripts/install-k3s-server.sh.tftpl", {
        mode                = "agent"
        tokens              = [random_password.k3s-server-token.result]
        alt_names           = []
        disable             = []
        server_hosts        = ["https://${local.support_node_ip}:6443"]
        node_taints         = coalesce(each.value.taints, [])
        node_labels         = []
        insecure_registries = var.insecure_registries
        datastores          = []
        http_proxy          = var.http_proxy
      })
    ]
  }
}
