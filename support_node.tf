
resource "macaddress" "k3s-support" {}

locals {
  support_node_settings = defaults(var.support_node_settings, {
    cores   = 2
    sockets = 1
    memory  = 4096


    storage_type = "scsi"
    storage_id   = "local-lvm"
    disk_size    = "10G"
    user         = "support"

    db_name = "k3s"
    db_user = "k3s"
  })

  support_node_ip = cidrhost(var.control_plane_subnet, 0)
}

locals {
  lan_subnet_cidr_bitnum = split("/", var.lan_subnet)[1]
}

resource "proxmox_vm_qemu" "k3s-support" {
  target_node = var.proxmox_node
  name        = join("-", [var.cluster_name, "support"])

  clone = var.node_template

  pool = var.proxmox_resource_pool

  # cores = 2
  cores   = local.support_node_settings.cores
  sockets = local.support_node_settings.sockets
  memory  = local.support_node_settings.memory

  disk {
    type    = local.support_node_settings.storage_type
    storage = local.support_node_settings.storage_id
    size    = local.support_node_settings.disk_size
  }

  network {
    bridge    = "vmbr0"
    firewall  = true
    link_down = false
    macaddr   = upper(macaddress.k3s-support.address)
    model     = "virtio"
    queues    = 0
    rate      = 0
    tag       = -1
  }


  os_type = "cloud-init"

  ciuser = local.support_node_settings.user

  ipconfig0 = "ip=${local.support_node_ip}/${local.lan_subnet_cidr_bitnum},gw=${var.network_gateway}"

  sshkeys = file(var.authorized_keys_file)

  connection {
    type = "ssh"
    user = local.support_node_settings.user
    host = local.support_node_ip
  }

  provisioner "file" {
    destination = "/tmp/install.sh"
    content = templatefile("${path.module}/scripts/install-support-apps.sh.tftpl", {
      root_password = random_password.support-db-password.result

      k3s_database = local.support_node_settings.db_name
      k3s_user     = local.support_node_settings.db_user
      k3s_password = random_password.k3s-master-db-password.result
    })
  }

  provisioner "remote-exec" {
    inline = [
      "chmod u+x /tmp/install.sh",
      "/tmp/install.sh",
      "rm -r /tmp/install.sh",
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
    user = local.support_node_settings.user
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
