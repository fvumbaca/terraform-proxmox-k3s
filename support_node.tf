locals {
  support_node_settings = var.support_node_settings
  support_node_ip       = cidrhost(var.control_plane_subnet, 0)

  # Where the K3s API is reached: the floating VIP when set, otherwise the
  # first master directly (no proxy).
  api_endpoint = var.api_vip != null ? var.api_vip : local.listed_master_nodes[0].ip

  # Every concrete node IP the module assigns. Used to catch a VIP that would
  # collide with a real node address.
  all_assigned_node_ips = concat(
    [local.support_node_ip],
    [for m in local.listed_master_nodes : m.ip],
    [for w in local.listed_worker_nodes : w.ip]
  )

  # NO_PROXY actually exported to the nodes: the user's list plus everything
  # that must bypass the proxy (pod/service CIDRs, every node subnet, the VIP).
  # Harmless when http_proxy is unset; essential when it is set.
  effective_no_proxy = distinct(concat(
    var.no_proxy,
    [var.cluster_cidr, var.service_cidr, var.control_plane_subnet],
    [for pool in var.node_pools : pool.subnet],
    var.api_vip != null ? [var.api_vip] : []
  ))
}

# Plan-time guard: the floating VIP must not equal any assigned node IP. This is
# a warning (not a hard failure) so advanced layouts that keep the VIP inside a
# managed subnet at an unused index are still allowed.
check "api_vip_collision" {
  assert {
    condition     = var.api_vip == null ? true : !contains(local.all_assigned_node_ips, var.api_vip)
    error_message = "api_vip (${coalesce(var.api_vip, "unset")}) collides with an assigned node IP. Pick a free address outside the support/master/worker allocations."
  }
}

locals {
  lan_subnet_cidr_bitnum = split("/", var.lan_subnet)[1]
}

resource "proxmox_virtual_environment_vm" "k3s-support" {
  count = var.support_node_enabled ? 1 : 0

  node_name = local.support_node_settings.target_node
  name      = join("-", [var.cluster_name, "support"])
  vm_id     = var.vm_id_start + 1

  clone {
    vm_id = local.effective_template_vm_id[local.support_node_settings.target_node]
  }

  pool_id    = var.proxmox_resource_pool != "" ? var.proxmox_resource_pool : null
  on_boot    = true
  protection = var.protection
  tags       = [var.cluster_name]

  # Boot first after a host reboot: support -> masters -> workers.
  startup {
    order      = "1"
    up_delay   = "30"
    down_delay = "30"
  }

  # The module installs qemu-guest-agent during provisioning; flip
  # vm_agent_enabled to true after the first apply.
  agent {
    enabled = var.vm_agent_enabled
  }

  stop_on_destroy = true

  cpu {
    cores   = local.support_node_settings.cores
    sockets = local.support_node_settings.sockets
    type    = var.cpu_type
  }

  memory {
    dedicated = local.support_node_settings.memory
  }

  scsi_hardware = "virtio-scsi-pci"

  # Boot disk
  disk {
    datastore_id = local.support_node_settings.storage_id
    interface    = "scsi0"
    size         = tonumber(replace(local.support_node_settings.disk_size, "/[Gg]/", ""))
  }

  initialization {
    datastore_id = local.support_node_settings.storage_id

    ip_config {
      ipv4 {
        address = "${local.support_node_ip}/${local.lan_subnet_cidr_bitnum}"
        gateway = var.network_gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      username = local.support_node_settings.user
      keys     = [trimspace(file(var.authorized_keys_file))]
    }
  }

  network_device {
    bridge   = local.support_node_settings.network_bridge
    firewall = true
    model    = "virtio"
    vlan_id  = local.support_node_settings.network_tag >= 0 ? local.support_node_settings.network_tag : null
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    ignore_changes = [
      disk,
      network_device,
    ]
  }

  connection {
    type        = "ssh"
    user        = local.support_node_settings.user
    host        = local.support_node_ip
    private_key = var.ssh_agent_auth ? null : file(var.authorized_private_key_file)
    agent       = var.ssh_agent_auth
  }

  provisioner "file" {
    destination = "/tmp/install.sh"
    content = templatefile("${path.module}/scripts/install-support-apps.sh.tftpl", {
      root_password      = random_password.support-user-password.result
      k3s_database       = local.support_node_settings.db_name
      k3s_user           = local.support_node_settings.db_user
      k3s_password       = random_password.k3s-mariadb-password.result
      http_proxy         = var.http_proxy
      no_proxy           = local.effective_no_proxy
      bind_address       = local.support_node_ip
      db_backup_enabled  = var.cluster_enable_embedded_etcd == false
      db_backup_schedule = var.db_backup_schedule
      embedded_etcd_init = var.cluster_enable_embedded_etcd
    })
  }

  provisioner "remote-exec" {
    inline = [
      "chmod u+x /tmp/install.sh",
      "sh /tmp/install.sh",
      "rm -r /tmp/install.sh",
    ]
  }
}

resource "random_password" "support-user-password" {
  length           = 16
  special          = true
  override_special = "_%@"
}

resource "random_password" "k3s-mariadb-password" {
  length  = 16
  special = true
  # URL-safe only: this password is embedded in the k3s datastore DSN
  # (mysql://user:pass@tcp(host)/db), so reserved chars like @ : / ? # [ ] %
  # would corrupt the DSN / trip percent-decoding. Keep to unreserved-safe set.
  override_special = "_-+"
}

# Push keepalived config to each master when the API VIP is enabled. Each
# master serves the API directly; the VIP floats to the healthiest master.
resource "null_resource" "k3s_keepalived_config" {
  for_each = var.api_vip != null ? local.mapped_master_nodes : {}

  triggers = {
    vip        = var.api_vip
    router_id  = var.vrrp_router_id
    config_md5 = filemd5("${path.module}/config/keepalived.conf.tftpl")
  }

  connection {
    type        = "ssh"
    user        = each.value.user
    host        = each.value.ip
    private_key = var.ssh_agent_auth ? null : file(var.authorized_private_key_file)
    agent       = var.ssh_agent_auth
  }

  provisioner "file" {
    destination = "/tmp/keepalived.conf"
    content = templatefile("${path.module}/config/keepalived.conf.tftpl", {
      interface = var.keepalived_interface
      router_id = var.vrrp_router_id
      priority  = 100 + (length(var.master_nodes) - 1 - each.value.i)
      vip       = var.api_vip
      auth_pass = var.vrrp_auth_pass
    })
  }

  provisioner "remote-exec" {
    inline = [
      "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
      "dpkg -s keepalived >/dev/null 2>&1 || { echo 'ERROR: keepalived is not installed on this node; refusing to push config' >&2; exit 1; }",
      "sudo mkdir -p /etc/keepalived",
      "sudo mv /tmp/keepalived.conf /etc/keepalived/keepalived.conf",
      "sudo systemctl daemon-reload",
      "sudo systemctl restart keepalived.service",
      "sudo systemctl is-active --quiet keepalived.service || { echo 'ERROR: keepalived failed to start after config push' >&2; sudo journalctl -u keepalived --no-pager -n 20 >&2; exit 1; }",
    ]
  }

  depends_on = [proxmox_virtual_environment_vm.k3s-master]
}

# When the datastore is MariaDB (not embedded etcd), the masters must reach the
# support node on 3306. With the Proxmox firewall enabled this IN rule lets the
# control-plane subnet through; inert otherwise. Skipped when the support node is
# disabled or embedded etcd is used.
resource "proxmox_virtual_environment_firewall_rules" "k3s_support_mariadb" {
  count = (!var.cluster_enable_embedded_etcd && var.support_node_enabled) ? 1 : 0

  node_name = local.support_node_settings.target_node
  vm_id     = var.vm_id_start + 1

  rule {
    comment = "Allow k3s control plane to reach the MariaDB datastore"
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = "3306"
    source  = var.control_plane_subnet
    enabled = true
  }

  depends_on = [proxmox_virtual_environment_vm.k3s-support]
}
