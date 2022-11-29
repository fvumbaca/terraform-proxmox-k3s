resource "macaddress" "k3s-masters" {
  count = var.master_nodes_count
}

locals {
  master_node_ips = [for i in range(var.master_nodes_count) : cidrhost(var.control_plane_subnet, i + 1)]
}

resource "random_password" "k3s-server-token" {
  length           = 32
  special          = false
  override_special = "_%@"
}

resource "proxmox_vm_qemu" "k3s-master" {
  depends_on = [
    proxmox_vm_qemu.k3s-support,
  ]

  count       = var.master_nodes_count
  target_node = var.proxmox_node
  name        = "${var.cluster_name}-master-${count.index}"

  clone = var.node_template

  pool = var.proxmox_resource_pool

  # cores = 2
  cores   = var.master_node_settings.cores
  sockets = var.master_node_settings.sockets
  memory  = var.master_node_settings.memory

  agent = 1

  disk {
    type    = var.master_node_settings.storage_type
    storage = var.master_node_settings.storage_id
    size    = var.master_node_settings.disk_size
  }

  network {
    bridge    = var.master_node_settings.network_bridge
    firewall  = true
    link_down = false
    macaddr   = upper(macaddress.k3s-masters[count.index].address)
    model     = "virtio"
    queues    = 0
    rate      = 0
    tag       = var.master_node_settings.network_tag
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

  ciuser = var.master_node_settings.user

  ipconfig0 = "ip=${local.master_node_ips[count.index]}/${local.lan_subnet_cidr_bitnum},gw=${var.network_gateway}"

  sshkeys = file(var.authorized_keys_file)

  nameserver = var.nameserver

  connection {
    type = "ssh"
    user = var.master_node_settings.user
    host = local.master_node_ips[count.index]
  }

  provisioner "remote-exec" {
    inline = [
      templatefile("${path.module}/scripts/install-k3s-server.sh.tftpl", {
        mode         = "server"
        tokens       = [random_password.k3s-server-token.result]
        alt_names    = concat([local.support_node_ip], var.api_hostnames)
        server_hosts = []
        node_taints  = ["CriticalAddonsOnly=true:NoExecute"]
        disable      = var.k3s_disable_components
        datastores = [{
          host     = "${local.support_node_ip}:3306"
          name     = "k3s"
          user     = "k3s"
          password = random_password.k3s-master-db-password.result
        }]

        http_proxy  = var.http_proxy
      })
    ]
  }
}

data "external" "kubeconfig" {
  depends_on = [
    proxmox_vm_qemu.k3s-support,
    proxmox_vm_qemu.k3s-master
  ]

  program = [
    "/usr/bin/ssh",
    "-o UserKnownHostsFile=/dev/null",
    "-o StrictHostKeyChecking=no",
    "${var.master_node_settings.user}@${local.master_node_ips[0]}",
    "echo '{\"kubeconfig\":\"'$(sudo cat /etc/rancher/k3s/k3s.yaml | base64)'\"}'"
  ]
}
