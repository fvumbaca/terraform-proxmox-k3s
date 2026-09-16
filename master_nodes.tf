locals {
  listed_master_nodes = flatten([
    for i, master_node in var.master_nodes : merge(master_node, {
      name  = "${var.cluster_name}-master-${i}"
      i     = i
      vm_id = var.vm_id_start + 2 + i
      # Used to force replacement
    ip = cidrhost(var.control_plane_subnet, i + 1) })

  ])

  mapped_master_nodes = {
    for node in local.listed_master_nodes : "${node.name}" => node
  }

}

resource "random_password" "k3s-server-token" {
  length           = 32
  special          = true
  override_special = "_%@"
}

resource "proxmox_virtual_environment_vm" "k3s-master" {
  depends_on = [
    proxmox_virtual_environment_vm.k3s-support,
  ]

  for_each = local.mapped_master_nodes

  node_name = each.value.target_node
  name      = each.value.name
  vm_id     = each.value.vm_id

  clone {
    vm_id = local.effective_template_vm_id[each.value.target_node]
  }

  pool_id    = var.proxmox_resource_pool != "" ? var.proxmox_resource_pool : null
  on_boot    = true
  protection = var.protection
  tags       = [var.cluster_name]

  # Boot after the support node, before workers.
  startup {
    order      = "2"
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
    cores   = each.value.cores
    sockets = each.value.sockets
    type    = var.cpu_type
  }

  memory {
    dedicated = each.value.memory
  }

  scsi_hardware = "virtio-scsi-pci"

  # Boot disk
  disk {
    datastore_id = each.value.storage_id
    interface    = "scsi0"
    size         = tonumber(replace(each.value.disk_size, "/[Gg]/", ""))
  }

  initialization {
    datastore_id = each.value.storage_id

    ip_config {
      ipv4 {
        address = "${each.value.ip}/${local.lan_subnet_cidr_bitnum}"
        gateway = var.network_gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      username = each.value.user
      keys     = [trimspace(file(var.authorized_keys_file))]
    }
  }

  network_device {
    bridge   = each.value.network_bridge
    firewall = true
    model    = "virtio"
    vlan_id  = each.value.network_tag >= 0 ? each.value.network_tag : null
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
    user        = each.value.user
    host        = each.value.ip
    private_key = var.ssh_agent_auth ? null : file(var.authorized_private_key_file)
    agent       = var.ssh_agent_auth
  }

  # Install keepalived on masters so the API VIP can float here. No-op when
  # api_vip is unset.
  provisioner "file" {
    destination = "/tmp/install-keepalived.sh"
    content = templatefile("${path.module}/scripts/install-keepalived.sh.tftpl", {
      lb_enabled = var.api_vip != null
      http_proxy = var.http_proxy
      no_proxy   = local.effective_no_proxy
    })
  }

  provisioner "remote-exec" {
    inline = [
      "chmod u+x /tmp/install-keepalived.sh",
      "sh /tmp/install-keepalived.sh",
      "rm -f /tmp/install-keepalived.sh",
    ]
  }

  # Install open-iscsi (Longhorn prerequisite) before k3s. No-op when
  # longhorn_enabled = false.
  provisioner "file" {
    destination = "/tmp/install-iscsi.sh"
    content = templatefile("${path.module}/scripts/install-iscsi.sh.tftpl", {
      iscsi_enabled = var.longhorn_enabled
      http_proxy    = var.http_proxy
      no_proxy      = local.effective_no_proxy
    })
  }

  provisioner "remote-exec" {
    inline = [
      "chmod u+x /tmp/install-iscsi.sh",
      "sh /tmp/install-iscsi.sh",
      "rm -f /tmp/install-iscsi.sh",
    ]
  }

  provisioner "remote-exec" {
    # Any additional node past the first one sleeps for extra time to ensure etcd can be bootstrapped in time.
    inline = ["sleep ${(each.value.i + 1) * 10}",
      templatefile("${path.module}/scripts/install-k3s.sh.tftpl", {
        mode      = "server"
        tokens    = [random_password.k3s-server-token.result]
        alt_names = concat([local.api_endpoint], var.api_hostnames)
        # Skip first host for server hosts if embedded etcd is turned on
        server_hosts = var.cluster_enable_embedded_etcd == true && each.value.i != 0 ? ["https://${local.listed_master_nodes[0].ip}:6443"] : []
        node_taints  = var.master_taints
        node_labels  = each.value.node_labels
        disable      = var.k3s_disable_components
        # Datastores are not enabled if embedded etcd is enabled
        datastores = var.cluster_enable_embedded_etcd == false ? [{
          host     = "${local.support_node_ip}:3306"
          name     = local.support_node_settings.db_name
          user     = local.support_node_settings.db_user
          password = random_password.k3s-mariadb-password.result
        }] : []
        http_proxy                  = var.http_proxy
        no_proxy                    = local.effective_no_proxy
        k3s_version                 = var.k3s_version
        k3s_install_commit          = var.k3s_install_commit
        cluster_cidr                = var.cluster_cidr
        service_cidr                = var.service_cidr
        extra_args                  = var.k3s_extra_server_args
        etcd_snapshot_schedule_cron = var.etcd_snapshot_schedule_cron
        # Master nodes do not have extra storage
        extra_storage_enable = false
        # Embedded etcd init if first control plane node and embedded etcd is enable. 
        embedded_etcd_init = each.value.i == 0 && var.cluster_enable_embedded_etcd == true ? true : false
      })
    , "sleep 5"]
  }
}

# Fetch the kubeconfig ONCE at apply time and write it locally. Replaces the old
# data.external which re-SSH'd on every plan. The server address is rewritten to
# the VIP (when set) or the support node so the config works off-cluster.
resource "null_resource" "kubeconfig" {
  count = var.kubeconfig_output_path != "" ? 1 : 0

  triggers = {
    first_master_vm_id = local.listed_master_nodes[0].vm_id
    api_endpoint       = local.api_endpoint
  }

  depends_on = [
    proxmox_virtual_environment_vm.k3s-support,
    proxmox_virtual_environment_vm.k3s-master,
  ]

  # Platform-agnostic kubeconfig fetch. The sed rewrite and its `>` redirect run
  # on the REMOTE (Unix) node inside DOUBLE quotes (so the local shell does not
  # interpret the inner `>`/`&&`), then scp copies the file down. The two
  # commands are chained with `;` (works in both PowerShell and /bin/sh; note
  # PowerShell 5.1 lacks `&&`). The interpreter is set via kubeconfig_interpreter
  # because cmd.exe cannot nest double quotes. Only the null device and scp
  # binary vary per platform (ssh_null_device / scp_binary).
  provisioner "local-exec" {
    interpreter = var.kubeconfig_interpreter
    command     = <<-EOT
      ${var.ssh_binary} ${var.ssh_agent_auth ? "" : "-i ${var.authorized_private_key_file}"} -o StrictHostKeyChecking=no -o UserKnownHostsFile=${var.ssh_null_device} ${local.listed_master_nodes[0].user}@${local.listed_master_nodes[0].ip} "sudo sed 's|https://127.0.0.1:6443|https://${local.api_endpoint}:6443|g' /etc/rancher/k3s/k3s.yaml > /tmp/kubeconfig.fetch && sudo chmod 644 /tmp/kubeconfig.fetch" ; ${var.scp_binary} ${var.ssh_agent_auth ? "" : "-i ${var.authorized_private_key_file}"} -o StrictHostKeyChecking=no -o UserKnownHostsFile=${var.ssh_null_device} ${local.listed_master_nodes[0].user}@${local.listed_master_nodes[0].ip}:/tmp/kubeconfig.fetch "${abspath(var.kubeconfig_output_path)}"
    EOT
  }
}

resource "proxmox_haresource" "k3s_master" {
  count = var.ha_group != null ? length(var.master_nodes) : 0

  resource_id = "vm:${local.listed_master_nodes[count.index].vm_id}"
  group       = var.ha_group
  state       = "started"
  comment     = "k3s control plane node ${local.listed_master_nodes[count.index].name}"

  depends_on = [proxmox_virtual_environment_vm.k3s-master]
}

# When the API VIP is in use, allow VRRP (IP protocol 112) between the masters
# so keepalived advertisements are not dropped by the Proxmox firewall. The
# module already sets firewall=true on each NIC; this rule only takes effect
# where the firewall is actually enabled, and is inert otherwise.
resource "proxmox_virtual_environment_firewall_rules" "k3s_master_vrrp" {
  count = var.api_vip != null ? length(var.master_nodes) : 0

  node_name = local.listed_master_nodes[count.index].target_node
  vm_id     = local.listed_master_nodes[count.index].vm_id

  rule {
    comment = "Allow VRRP (keepalived) for the floating K3s API VIP"
    type    = "in"
    action  = "ACCEPT"
    proto   = "112"
    source  = var.control_plane_subnet
    enabled = true
  }

  depends_on = [proxmox_virtual_environment_vm.k3s-master]
}
