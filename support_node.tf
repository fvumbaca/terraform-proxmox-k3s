
resource "macaddress" "k3s-support" {}

locals {
  support_node_settings = defaults(var.support_node_settings, {
    cores   = 2
    sockets = 1
    memory  = 4096
    balloon = 2048

    full_clone   = true

    storage_type = "scsi"
    storage_id   = "local-lvm"
    disk_size    = "10G"
    network_tag  = -1
    firewall     = true

    db_name = "k3s"
    db_user = "k3s"

    network_bridge = "vmbr0"
  })

  support_node_ip = cidrhost(var.control_plane_subnet, 0)
}

locals {
  lan_subnet_cidr_bitnum = split("/", var.lan_subnet)[1]
}

resource "proxmox_vm_qemu" "k3s-support" {
  target_node = var.support_node_settings.target_node
  name        = join("-", [var.cluster_name, "support"])

  clone = local.support_node_settings.image_id
  full_clone = local.support_node_settings.full_clone

  pool = var.support_node_settings.target_pool

  # cores = 2
  cores   = local.support_node_settings.cores
  sockets = local.support_node_settings.sockets
  memory  = local.support_node_settings.memory
  balloon = local.support_node_settings.balloon

  agent   = 1

  disk {
    type    = local.support_node_settings.storage_type
    storage = local.support_node_settings.storage_id
    size    = local.support_node_settings.disk_size
  }

  network {
    bridge    = local.support_node_settings.network_bridge
    firewall  = local.support_node_settings.firewall
    link_down = false
    macaddr   = upper(macaddress.k3s-support.address)
    model     = "virtio"
    queues    = 0
    rate      = 0
    tag       = local.support_node_settings.network_tag
  }

  lifecycle {
    ignore_changes = [
      ciuser,
      sshkeys,
      disk,
      network,
      desc
    ]
  }

  os_type = "cloud-init"
  ciuser = var.ciuser
  ipconfig0 = "ip=${local.support_node_ip}/${local.lan_subnet_cidr_bitnum},gw=${local.support_node_settings.gw}"
  sshkeys = local.support_node_settings.authorized_keys
  nameserver = local.support_node_settings.nameserver

  connection {
    type = "ssh"
    user = var.ciuser
    host = local.support_node_ip
  }

  provisioner "remote-exec" {
    inline = [
      templatefile("${path.module}/scripts/install-support.sh.tftpl", {
        root_password = random_password.support-db-password.result

        k3s_database = local.support_node_settings.db_name
        k3s_user     = local.support_node_settings.db_user
        k3s_password = random_password.k3s-master-db-password.result
      
        http_proxy  = var.http_proxy
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
    user = var.ciuser
    host = local.support_node_ip
  }

  provisioner "file" {
    destination = "/tmp/nginx.conf"
    content = templatefile("${path.module}/config/nginx.conf.tftpl", {
      k3s_server_hosts = [for ip in local.master_node_ips :
        "${ip}:6443"
      ]
      k3s_nodes = concat(local.master_node_ips, [
        for node in local.listed_worker_nodes :
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
