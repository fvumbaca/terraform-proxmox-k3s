variable "authorized_keys_file" {
  description = "Path to file containing public SSH keys for remoting into nodes. Prefer ed25519 keys (ssh-keygen -t ed25519); RSA+SHA-1 is distrusted by modern OpenSSH."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}
variable "authorized_private_key_file" {
  description = "Path to file containing private SSH keys for remoting into nodes. Ignored when ssh_agent_auth = true."
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "ssh_agent_auth" {
  description = "Use the local ssh-agent for provisioning instead of authorized_private_key_file."
  type        = bool
  default     = false
}

variable "longhorn_enabled" {
  description = "Install open-iscsi on every node (Longhorn CSI prerequisite: iscsiadm + iscsid + iscsi_tcp). Set true when deploying Longhorn; the install script is a no-op when false."
  type        = bool
  default     = false
}

variable "network_gateway" {
  description = "IP address of the network gateway."
  type        = string
  validation {
    condition     = can(cidrhost("${var.network_gateway}/32", 0))
    error_message = "The network_gateway value must be a valid ip."
  }
}

variable "lan_subnet" {
  description = <<EOF
Subnet used by the LAN network. Only the prefix length (bit count after the "/")
is actually used - it is applied to every node's static address. The network
portion of the value is ignored; all nodes are addressed within the control
plane / pool subnets using this prefix.
EOF
  type        = string
  validation {
    condition     = can(cidrhost(var.lan_subnet, 0))
    error_message = "The lan_subnet value must be a valid cidr range."
  }
}

variable "control_plane_subnet" {
  description = "CIDR range used to assign static IPs to the support and master (control plane) nodes."
  type        = string
  validation {
    condition     = can(cidrhost(var.control_plane_subnet, 0))
    error_message = "The control_plane_subnet value must be a valid cidr range."
  }

  validation {
    condition     = try(length(var.master_nodes) <= pow(2, 32 - tonumber(split("/", var.control_plane_subnet)[1])) - 1, true)
    error_message = "control_plane_subnet is too small to hold the support node plus all masters (support uses host 0, masters use hosts 1..N)."
  }
}

variable "cluster_name" {
  default     = "k3s"
  type        = string
  description = "Name of the cluster used for prefixing cluster components (ie nodes)."
}

variable "cluster_enable_embedded_etcd" {
  default     = false
  type        = bool
  description = "Determines whether or not embedded etcd will be used."

  validation {
    condition     = !var.cluster_enable_embedded_etcd || length(var.master_nodes) % 2 == 1
    error_message = "Embedded etcd needs an odd number of masters (1, 3, 5) for quorum; an even count risks split-brain."
  }
}

variable "template_vm_id" {
  type        = number
  default     = null
  description = <<EOF
Proxmox VM ID of the base template for all nodes. Must be a template or
another vm that supports cloud-init. The bpg provider clones by numeric
VM ID (not by name), so the template's QMID is required.
Mutually exclusive with template_image.
EOF

  validation {
    condition     = (var.template_vm_id != null) != (var.template_image != null)
    error_message = "Exactly one of template_vm_id or template_image must be set."
  }
}

variable "template_image" {
  type = object({
    node_name      = string,
    datastore_id   = string,
    url            = string,
    file_name      = string,
    disk_size      = number,
    user           = optional(string, "debian"),
    network_bridge = optional(string, "vmbr0"),
    import_datastore_id = optional(string),
  })
  default     = null
  description = <<EOF
When set, the module downloads this cloud image and builds the base template
itself (proxmox_download_file + a template VM), instead of
cloning a pre-existing template_vm_id. Mutually exclusive with template_vm_id.
disk_size is in GB. url must point at an uncompressed cloud image.
EOF
}

variable "vm_id_start" {
  type        = number
  default     = 900
  description = <<EOF
Starting VM ID used to allocate IDs to created nodes:
auto-built template (if template_image is used) = vm_id_start,
support node = vm_id_start + 1,
master nodes = vm_id_start + 2 .. vm_id_start + 1 + number_of_masters,
worker nodes = the IDs after that, in pool order.
EOF
}

variable "template_vm_id_base" {
  type        = number
  default     = 8000
  description = <<EOF
Starting VM ID for the auto-built per-node templates (template_image mode).
Each unique target node gets a template at template_vm_id_base + index (sorted),
kept in a range separate from vm_id_start so template IDs never collide with
the node VMs. Ignored when template_vm_id is set (single shared template).
EOF
}

variable "proxmox_resource_pool" {
  description = "Resource pool name to use in proxmox to better organize nodes."
  type        = string
  default     = ""
}

variable "support_node_settings" {
  description = "Default settings values for support nodes"
  type = object({
    target_node    = string,
    cores          = number,
    sockets        = number,
    memory         = number,
    storage_id     = string,
    disk_size      = string,
    user           = string,
    db_user        = string,
    db_name        = string,
    network_bridge = string,
    network_tag    = optional(number, -1),
  })
  default = {
    target_node    = "pve"
    cores          = 2
    sockets        = 1
    memory         = 4096
    storage_id     = "local-lvm"
    disk_size      = "10G"
    user           = "support"
    network_tag    = -1
    db_name        = "k3s"
    db_user        = "k3s"
    network_bridge = "vmbr0"
  }
}
variable "master_nodes" {
  description = "Default settings values for master nodes"
  type = list(object({
    target_node    = string,
    cores          = number,
    sockets        = number,
    memory         = number,
    storage_id     = string,
    disk_size      = string,
    user           = string,
    network_bridge = string,
    network_tag    = optional(number, -1),
    node_labels    = optional(list(string), []),
  }))
}

variable "master_taints" {
  description = <<-EOF
  Taints applied to every master node. The default reserves the control plane for
  critical system pods only (regular workloads won't schedule there). Set to []
  to let normal workloads run on the masters too - better hardware utilization,
  but watch etcd CPU/IO contention (use resource requests/limits on workloads so
  they can't starve the API server / etcd).
  EOF
  type        = list(string)
  default     = ["CriticalAddonsOnly=true:NoExecute"]
}


variable "node_pools" {
  description = "Node pool definitions for the cluster."
  type = list(object({
    size        = number,
    subnet      = string,
    target_node = string,
    node_pool_settings = object({
      name           = string,
      taints         = list(string),
      cores          = number,
      sockets        = number,
      memory         = number,
      storage_id     = string,
      disk_size      = string,
      user           = string,
      network_bridge = string,
      network_tag    = optional(number, -1),
      node_labels    = optional(list(string), []),
      additional_storage = optional(object({
        storage_id = string,
        disk_size  = string,
      }), null)
    })
  }))

  validation {
    condition = try(alltrue([
      for pool in var.node_pools : pool.size <= pow(2, 32 - tonumber(split("/", pool.subnet)[1])) - 1
    ]), true)
    error_message = "Each worker pool size must fit within its subnet's usable host range (workers use hosts 1..size)."
  }
}

variable "api_hostnames" {
  description = "Alternative hostnames for the API server."
  type        = list(string)
  default     = []
}

variable "k3s_disable_components" {
  description = "List of components to disable. Ref: https://rancher.com/docs/k3s/latest/en/installation/install-options/server-config/#kubernetes-components"
  type        = list(string)
  default     = []
}

variable "k3s_extra_server_args" {
  description = "Extra raw arguments appended to the k3s SERVER install command (e.g. [\"--disable-apiserver=false\", \"--kube-apiserver-arg=some-flag=1\"]). Escape hatch for flags the module doesn't model; values are inserted verbatim."
  type        = list(string)
  default     = []
}

variable "k3s_extra_agent_args" {
  description = "Extra raw arguments appended to the k3s AGENT install command. Escape hatch for flags the module doesn't model; values are inserted verbatim."
  type        = list(string)
  default     = []
}

variable "support_node_enabled" {
  description = "Create the support node. With embedded etcd the support VM has no database role and is near-idle, so you can set this to false to free a whole box. Must remain true when cluster_enable_embedded_etcd = false (the support node hosts MariaDB)."
  type        = bool
  default     = true

  validation {
    condition     = var.support_node_enabled || var.cluster_enable_embedded_etcd
    error_message = "support_node_enabled cannot be false unless cluster_enable_embedded_etcd is true (the support node hosts the MariaDB datastore)."
  }
}

variable "k3s_version" {
  description = "K3s version to install (maps to INSTALL_K3S_VERSION). Empty means the current stable channel from get.k3s.io (e.g. v1.37.0+k3s1)."
  type        = string
  default     = ""
}

variable "dns_servers" {
  description = "DNS servers handed to nodes via cloud-init. Required since nodes use static IPs; without them DNS resolution depends on the template."
  type        = list(string)
  default     = []
}

variable "cpu_type" {
  description = "Emulated CPU type for all nodes. The provider default (qemu64) is slow; x86-64-v2-AES is a safe modern baseline, use \"host\" for max performance if all PVE nodes have compatible CPUs."
  type        = string
  default     = "x86-64-v2-AES"
}

variable "ha_group" {
  description = "Proxmox HA group name. When set, master nodes are registered as HA resources (requires a pre-created HA group)."
  type        = string
  default     = null
}

variable "protection" {
  description = "Enable the Proxmox protection flag on created VMs to prevent accidental deletion/modification from the GUI."
  type        = bool
  default     = false
}

variable "ssh_binary" {
  description = "Path to the ssh binary used to fetch the kubeconfig from the first master at apply time."
  type        = string
  default     = "/usr/bin/ssh"
}

variable "ssh_null_device" {
  description = "Null device for the kubeconfig fetch's UserKnownHostsFile. Use NUL on Windows, /dev/null on Unix."
  type        = string
  default     = "/dev/null"
}

variable "scp_binary" {
  description = "Path to the scp binary used to copy the kubeconfig down from the first master at apply time."
  type        = string
  default     = "scp"
}

variable "kubeconfig_interpreter" {
  description = <<-EOF
  Interpreter for the kubeconfig-fetch local-exec. The command chains ssh and scp
  with `;` and double-quotes the remote command, which works in both PowerShell
  and /bin/sh. Use ["/bin/sh", "-c"] on Unix or ["powershell", "-NoProfile",
  "-Command"] on Windows. Do NOT use cmd.exe - it cannot nest double quotes.
  EOF
  type        = list(string)
  default     = ["/bin/sh", "-c"]
}

variable "vm_agent_enabled" {
  description = <<-EOF
  Tell Proxmox that qemu-guest-agent is running in the guests. The module installs
  qemu-guest-agent during provisioning, so set this to true AFTER the first
  successful apply; enabling it during the initial create makes the provider
  wait for an agent that is not installed yet.
  EOF
  type        = bool
  default     = false
}

variable "http_proxy" {
  default     = ""
  type        = string
  description = "http_proxy"
}

variable "no_proxy" {
  description = "Hosts/CIDRs excluded from proxying (exported as NO_PROXY). The module automatically appends the pod/service CIDRs, every node subnet and the API VIP, so you only need to list extra entries here."
  type        = list(string)
  default     = []
}

variable "cluster_cidr" {
  description = "K3s pod CIDR. Passed to the server as --cluster-cidr AND appended to NO_PROXY so pod traffic never goes through http_proxy. Keep the default unless you set a custom pod CIDR."
  type        = string
  default     = "10.42.0.0/16"

  validation {
    condition     = can(cidrhost(var.cluster_cidr, 0))
    error_message = "cluster_cidr must be a valid cidr range."
  }
}

variable "service_cidr" {
  description = "K3s service CIDR. Passed to the server as --service-cidr AND appended to NO_PROXY so service traffic never goes through http_proxy. Keep the default unless you set a custom service CIDR."
  type        = string
  default     = "10.43.0.0/16"

  validation {
    condition     = can(cidrhost(var.service_cidr, 0))
    error_message = "service_cidr must be a valid cidr range."
  }
}

variable "k3s_install_commit" {
  description = "Pin the k3s install script to a specific git commit (maps to INSTALL_K3S_COMMIT). Combine with k3s_version for a fully reproducible install; empty uses whatever get.k3s.io resolves."
  type        = string
  default     = ""
}

variable "api_vip" {
  description = "Virtual IP address (floating via keepalived) for the K3s API. When set, keepalived runs on the masters and the VIP is added to the API TLS SAN; clients reach the API at VIP:6443 directly (no proxy). Ingress (80/443) is handled in-cluster by MetalLB - see docs/metallb.md. Leave null to reach the API via the first master's IP."
  type        = string
  default     = null

  validation {
    condition     = var.api_vip == null || can(cidrhost("${var.api_vip}/32", 0))
    error_message = "api_vip must be a valid IPv4 address."
  }

  validation {
    condition     = var.api_vip == null || var.vrrp_auth_pass != null
    error_message = "vrrp_auth_pass must be set when api_vip is set."
  }
}

variable "vrrp_router_id" {
  description = "VRRP virtual router ID for keepalived (1-255). Must be unique per L2 segment across all keepalived clusters."
  type        = number
  default     = 51

  validation {
    condition     = var.vrrp_router_id >= 1 && var.vrrp_router_id <= 255
    error_message = "vrrp_router_id must be between 1 and 255."
  }
}

variable "keepalived_interface" {
  description = "Guest-side network interface name inside the master VMs that keepalived binds the VIP to. This is the VM's own NIC (e.g. eth0/ens18), NOT the Proxmox host bridge (vmbr0)."
  type        = string
  default     = "eth0"
}

variable "vrrp_auth_pass" {
  description = "VRRP authentication password (max 8 chars, VRRPv2 limit). Required when api_vip is set."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.vrrp_auth_pass == null || try(length(var.vrrp_auth_pass), 0) <= 8
    error_message = "vrrp_auth_pass must be at most 8 characters (VRRPv2 limitation)."
  }
}

variable "etcd_snapshot_schedule_cron" {
  description = "Cron schedule for automatic k3s embedded-etcd snapshots (maps to --etcd-snapshot-schedule-cron). Empty disables. Snapshots land in /var/lib/rancher/k3s/server/db/snapshots on each master."
  type        = string
  default     = ""
}

variable "db_backup_schedule" {
  description = "Cron schedule for MariaDB backups on the support node (ignored when embedded etcd is used). Backups are written to /var/backups/k3s with 7-day retention."
  type        = string
  default     = "0 2 * * *"
}

variable "kubeconfig_output_path" {
  description = "Path (relative to the root module) where the kubeconfig is written at apply time. The file is fetched once from the first master; it is NOT refreshed on every plan. Set to \"\" to disable."
  type        = string
  default     = "kubeconfig.yaml"
}
