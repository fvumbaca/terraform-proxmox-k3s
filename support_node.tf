resource "macaddress" "k3s-support" {}

locals {
  support_node_ip        = cidrhost(var.control_plane_subnet, var.support_node_settings.ip_offset)
  gw                     = coalesce(var.support_node_settings.gw, var.default_node_settings.gw)
  lan_subnet_cidr_bitnum = split("/", var.lan_subnet)[1]
  support_node_ciuser    = coalesce(var.support_node_settings.ciuser, var.default_node_settings.ciuser)
}

resource "proxmox_vm_qemu" "k3s-support" {
  target_node = coalesce(var.support_node_settings.target_node, var.default_node_settings.target_node)
  name        = join("-", [var.cluster_name, "support"])
  clone       = coalesce(var.support_node_settings.image_id, var.default_node_settings.image_id)
  full_clone  = coalesce(var.support_node_settings.full_clone, var.default_node_settings.full_clone)
  pool        = coalesce(var.support_node_settings.target_pool, var.default_node_settings.target_pool)
  cores       = coalesce(var.support_node_settings.cores, var.default_node_settings.cores)
  sockets     = coalesce(var.support_node_settings.sockets, var.default_node_settings.sockets)
  memory      = coalesce(var.support_node_settings.memory, var.default_node_settings.memory)
  ciuser      = local.support_node_ciuser
  ipconfig0   = "ip=${local.support_node_ip}/${local.lan_subnet_cidr_bitnum},gw=${local.gw}"
  sshkeys     = coalesce(var.support_node_settings.authorized_keys, var.default_node_settings.authorized_keys)
  nameserver  = coalesce(var.support_node_settings.nameserver, var.default_node_settings.nameserver)
  os_type     = "cloud-init"
  agent       = 1

  disk {
    type    = coalesce(var.support_node_settings.disk_type, var.default_node_settings.disk_type)
    storage = coalesce(var.support_node_settings.storage_id, var.default_node_settings.storage_id)
    size    = coalesce(var.support_node_settings.disk_size, var.default_node_settings.disk_size)
  }

  network {
    bridge    = coalesce(var.support_node_settings.network_bridge, var.default_node_settings.network_bridge)
    firewall  = coalesce(var.support_node_settings.firewall, var.default_node_settings.firewall)
    link_down = false
    macaddr   = upper(macaddress.k3s-support.address)
    model     = "virtio"
    queues    = 0
    rate      = 0
    tag       = coalesce(var.support_node_settings.network_tag, var.default_node_settings.network_tag)
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
    user = local.support_node_ciuser
    host = local.support_node_ip
  }

  provisioner "remote-exec" {
    inline = [
      templatefile("${path.module}/scripts/install-support.sh.tftpl", {
        root_password = random_password.support-db-password.result

        k3s_database = var.support_node_settings.db_name
        k3s_user     = var.support_node_settings.db_user
        k3s_password = random_password.k3s-master-db-password.result

        http_proxy = var.http_proxy
      })
    ]
  }
}

resource "random_password" "support-db-password" {
  length           = 16
  special          = false
  override_special = "_%@"
}

resource "random_password" "k3s-master-db-password" {
  length           = 16
  special          = false
  override_special = "_%@"
}

resource "null_resource" "k3s_nginx_config" {
  depends_on = [
    proxmox_vm_qemu.k3s-support
  ]

  triggers = {
    config_change = filemd5("${path.module}/config/nginx.conf.tftpl")
  }

  connection {
    type = "ssh"
    user = local.support_node_ciuser
    host = local.support_node_ip
  }

  provisioner "file" {
    destination = "/tmp/nginx.conf"
    content = templatefile("${path.module}/config/nginx.conf.tftpl", {
      k3s_server_hosts = [for ip in local.master_node_ips :
        "${ip}:6443"
      ]
      k3s_nodes = concat(local.master_node_ips, [
        for node in local.mapped_worker_nodes :
        node.ip
      ])
    })
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mv /tmp/nginx.conf /etc/nginx/nginx.conf",
      "sudo systemctl restart nginx.service",
    ]
  }
}
