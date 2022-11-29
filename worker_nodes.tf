resource "macaddress" "k3s-workers" {
  for_each = local.mapped_worker_nodes
}

locals {

  listed_worker_nodes = flatten([
    for pool in var.node_pools :
    [
      for i in range(pool.size) :
      merge(pool, {
        i        = i
        ip       = cidrhost(pool.subnet, i)
        template = coalesce(pool.template, var.node_template)
      })
    ]
  ])

  mapped_worker_nodes = {
    for node in local.listed_worker_nodes : "${node.name}-${node.i}" => node
  }

}

resource "proxmox_vm_qemu" "k3s-worker" {
  depends_on = [
    proxmox_vm_qemu.k3s-support,
    proxmox_vm_qemu.k3s-master,
  ]

  for_each = local.mapped_worker_nodes

  target_node = var.proxmox_node
  name        = "${var.cluster_name}-${each.key}"

  clone = each.value.template

  pool = var.proxmox_resource_pool

  # cores = 2
  cores   = each.value.cores
  sockets = each.value.sockets
  memory  = each.value.memory

  agent = 1

  disk {
    type    = each.value.storage_type
    storage = each.value.storage_id
    size    = each.value.disk_size
  }

  network {
    bridge    = each.value.network_bridge
    firewall  = true
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
      network
    ]
  }

  os_type = "cloud-init"

  ciuser = each.value.user

  ipconfig0 = "ip=${each.value.ip}/${local.lan_subnet_cidr_bitnum},gw=${var.network_gateway}"

  sshkeys = file(var.authorized_keys_file)

  nameserver = var.nameserver

  connection {
    type = "ssh"
    user = each.value.user
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
        datastores   = []

        http_proxy = var.http_proxy
      })
    ]
  }

}
