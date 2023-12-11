locals {

/*   listed_worker_nodes = flatten([
    for pool in var.node_pools :
    [
      for zone in pool.zones : [
        for i in range(pool.size) :
        merge(pool, {
          zone     = zone
          template = var.node_template
          i        = i
          ip       = cidrhost(pool.subnet, index(pool.zones, zone)+1)
        })
      ]
    ]
  ]) */

  listed_worker_nodes = flatten([
    for pool in var.node_pools : [
      for index, node in setproduct([pool], pool.zones) : [
        merge(node[0], {
          zone = node[1]
          ip = cidrhost(pool.subnet, index+1)
          i  = index
        })
      ]
    ]
  ])

  mapped_worker_nodes = {
    for node in local.listed_worker_nodes : "${node.name}-${node.zone}-${node.i}" => node
  }

}

output "test" {
  value = local.listed_worker_nodes
}

resource "proxmox_vm_qemu" "k3s-worker" {

  for_each = local.mapped_worker_nodes

  onboot = each.value.onboot

  target_node = each.value.zone
  name        = "${var.cluster_name}-${each.key}"

  clone = each.value.template

  pool = var.proxmox_resource_pool

  # cores = 2
  cores   = each.value.cores
  sockets = each.value.sockets
  memory  = each.value.memory

  agent = 1

  scsihw = "virtio-scsi-single"

  disk {
    type     = each.value.storage_type
    storage  = each.value.storage_id
    size     = each.value.disk_size
    iothread = each.value.iothread
  }

  network {
    bridge    = each.value.network_bridge
    firewall  = true
    link_down = false
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

}
