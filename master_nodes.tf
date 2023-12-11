locals {
  master_nodes_count   = length(var.proxmox_nodes)
  master_node_settings = var.master_node_settings
  master_node_ips      = [for i in range(local.master_nodes_count) : cidrhost(var.control_plane_subnet, i + 1)]

  lan_subnet_cidr_bitnum = split("/", var.lan_subnet)[1]
}

resource "proxmox_vm_qemu" "k3s-master" {

  count       = local.master_nodes_count

  onboot = local.master_node_settings.onboot 
  target_node = var.proxmox_nodes[count.index]
  name        = "${var.cluster_name}-master-${count.index}"

  clone = var.node_template

  pool = var.proxmox_resource_pool

  # cores = 2
  cores   = local.master_node_settings.cores
  sockets = local.master_node_settings.sockets
  memory  = local.master_node_settings.memory

  agent = 1

  scsihw = "virtio-scsi-single"

  disk {
    type     = local.master_node_settings.storage_type
    storage  = local.master_node_settings.storage_id
    size     = local.master_node_settings.disk_size
    iothread = local.master_node_settings.iothread
  }

  network {
    bridge    = local.master_node_settings.network_bridge
    firewall  = true
    link_down = false
    model     = "virtio"
    queues    = 0
    rate      = 0
    tag       = local.master_node_settings.network_tag
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

  ciuser = local.master_node_settings.user

  ipconfig0 = "ip=${local.master_node_ips[count.index]}/${local.lan_subnet_cidr_bitnum},gw=${var.network_gateway}"

  sshkeys = file(var.authorized_keys_file)

  nameserver = var.nameserver

}

