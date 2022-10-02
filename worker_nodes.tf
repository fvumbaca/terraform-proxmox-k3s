resource "macaddress" "k3s-workers" {
  for_each = local.mapped_worker_nodes
}

locals {
  listed_worker_nodes = flatten([
    for pool in var.node_pools :
    [
      for i in range(pool.size) :
        merge({
          i              = i
        }, pool)
    ]
  ])

  mapped_worker_nodes = {
    for node in local.listed_worker_nodes : "${node.name}-${node.i}" =>
      merge(node, {
        ip               = cidrhost(node.subnet, node.i + node.ip_offset)
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

  target_node = each.value.target_node
  name        = "${var.cluster_name}-${each.key}"

  clone = each.value.image_id
  full_clone = each.value.full_clone

  pool = each.value.target_pool

  cores   = each.value.cores
  sockets = each.value.sockets
  memory  = each.value.memory
  balloon = each.value.balloon

  agent = 1

  disk {
    type    = each.value.storage_type
    storage = each.value.storage_id
    size    = each.value.disk_size
  }

  network {
    bridge    = each.value.network_bridge
    firewall  = each.value.firewall
    link_down = false
    macaddr   = upper(macaddress.k3s-workers[each.key].address)
    model     = "virtio"
    queues    = 0
    rate      = 0
    tag       = each.value.network_tag
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

  os_type = "cloud-init"
  ciuser = var.ciuser
  ipconfig0 = "ip=${each.value.ip}/${local.lan_subnet_cidr_bitnum},gw=${each.value.gw}"
  sshkeys = each.value.authorized_keys
  nameserver = each.value.nameserver

  connection {
    type = "ssh"
    user = var.ciuser
    host = each.value.ip
  }

  provisioner "remote-exec" {
    inline = [
      templatefile("${path.module}/scripts/install-k3s-server.sh.tftpl", {
        mode         = "agent"
        tokens       = [random_password.k3s-server-token.result]
        alt_names    = []
        disable      = []
        server_hosts = ["https://${local.support_node_ip}:6443"]
        node_taints  = each.value.taints
        node_labels  = []
        insecure_registries = var.insecure_registries
        datastores   = []

        http_proxy  = var.http_proxy
      })
    ]
  }
}
