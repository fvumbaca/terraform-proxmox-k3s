resource "macaddress" "k3s-masters" {
  count = var.master_nodes_count
}

locals {
  master_node_subnet = coalesce(var.master_node_settings.subnet, var.default_node_settings.subnet)
  master_node_ips    = [for i in range(var.master_nodes_count) : cidrhost(local.master_node_subnet, i + var.master_node_settings.ip_offset)]
  master_node_ciuser = coalesce(var.master_node_settings.ciuser, var.default_node_settings.ciuser)
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

  count = var.master_nodes_count

  target_node = coalesce(var.master_node_settings.target_node, var.default_node_settings.target_node)
  name        = "${var.cluster_name}-master-${count.index}"
  clone       = coalesce(var.master_node_settings.image_id, var.default_node_settings.image_id)
  full_clone  = coalesce(var.master_node_settings.full_clone, var.default_node_settings.full_clone)
  pool        = coalesce(var.master_node_settings.target_pool, var.default_node_settings.target_pool)
  cores       = coalesce(var.master_node_settings.cores, var.default_node_settings.cores)
  sockets     = coalesce(var.master_node_settings.sockets, var.default_node_settings.sockets)
  memory      = coalesce(var.master_node_settings.memory, var.default_node_settings.memory)
  ciuser      = local.master_node_ciuser
  ipconfig0   = "ip=${local.master_node_ips[count.index]}/${split("/", local.master_node_subnet)[1]},gw=${local.gw}"
  sshkeys     = coalesce(var.master_node_settings.authorized_keys, var.default_node_settings.authorized_keys)
  nameserver  = coalesce(var.master_node_settings.nameserver, var.default_node_settings.nameserver)
  os_type     = "cloud-init"
  agent       = 1

  disk {
    type    = coalesce(var.master_node_settings.disk_type, var.default_node_settings.disk_type)
    storage = coalesce(var.master_node_settings.storage_id, var.default_node_settings.storage_id)
    size    = coalesce(var.master_node_settings.disk_size, var.default_node_settings.disk_size)
  }

  network {
    bridge    = coalesce(var.master_node_settings.network_bridge, var.default_node_settings.network_bridge)
    firewall  = coalesce(var.master_node_settings.firewall, var.default_node_settings.firewall)
    link_down = false
    macaddr   = upper(macaddress.k3s-masters[count.index].address)
    model     = "virtio"
    queues    = 0
    rate      = 0
    tag       = coalesce(var.master_node_settings.network_tag, var.default_node_settings.network_tag)
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
    user = local.master_node_ciuser
    host = local.master_node_ips[count.index]
  }

  provisioner "remote-exec" {
    inline = [
      templatefile("${path.module}/scripts/install-k3s-server.sh.tftpl", {
        mode                = "server"
        tokens              = [random_password.k3s-server-token.result]
        alt_names           = concat([local.support_node_ip], var.api_hostnames)
        server_hosts        = []
        node_taints         = ["CriticalAddonsOnly=true:NoExecute"]
        node_labels         = coalesce(var.node_labels, [])
        insecure_registries = var.insecure_registries
        disable             = var.k3s_disable_components
        datastores = [{
          host     = "${local.support_node_ip}:3306"
          name     = var.support_node_settings.db_name
          user     = var.support_node_settings.db_user
          password = random_password.k3s-master-db-password.result
        }]
        http_proxy = var.http_proxy
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
    "${local.master_node_ciuser}@${local.master_node_ips[0]}",
    "echo '{\"kubeconfig\":\"'$(sudo cat /etc/rancher/k3s/k3s.yaml | base64)'\"}'"
  ]
}
