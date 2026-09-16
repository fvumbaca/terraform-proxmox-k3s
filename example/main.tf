terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.113.0"
    }
  }

  # Remote state on Backblaze B2 (S3-compatible). Backend blocks CANNOT use
  # variables/locals, so the non-sensitive settings live here and the
  # credentials are supplied at init time via a gitignored backend.hcl:
  #   terraform init -backend-config=backend.hcl
  # (see example/README.md for the local->remote migration step).
  backend "s3" {
    # B2 bucket name (must be globally unique on B2).
    bucket = "dellathefella-terraform-state"
    # Path/key of the state file inside the bucket.
    key = "opti-k3s/terraform.tfstate"
    # B2 region of the bucket. Must match the endpoint below.
    region = "us-east-005"
    # B2 S3-compatible endpoint for that region.
    endpoint = "https://s3.us-east-005.backblazeb2.com"

    # B2 quirks: it is not real AWS, so skip the AWS-specific checks.
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    force_path_style            = true

    # access_key / secret_key are NOT set here (no variables in backend blocks).
    # Provide them via backend.hcl (gitignored) or env vars:
    #   AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
  }
}

variable "pm_token_id" {
  description = "Proxmox API token ID (e.g. root@pam!k3s-deployer)."
  type        = string
}

variable "pm_token_secret" {
  description = "Proxmox API token secret."
  type        = string
  sensitive   = true
}

provider "proxmox" {
  endpoint  = "https://10.0.5.1:8006/"
  api_token = "${var.pm_token_id}=${var.pm_token_secret}"
  insecure  = true
}

# Topology for 9 identical nodes (4 cores / 16 GB each), one VM per node.
#
#   opti0 : master0 (4c/8G, control-plane only)
#   opti1 : master1 (4c/8G, control-plane only)
#   opti2 : master2 (4c/8G, control-plane only)
#   opti3 : worker pool0 (4c/13G)
#   opti4 : worker pool1 (4c/13G)
#   opti5 : worker pool2 (4c/13G)
#   opti6 : worker pool3 (4c/13G)
#   opti7 : worker pool4 (4c/13G)
#   opti8 : worker pool5 (4c/13G)
#
# 3 masters give an HA embedded-etcd control plane. Masters are tainted
# CriticalAddonsOnly:NoExecute so only critical system pods schedule there.
# The support node is disabled (embedded etcd makes its MariaDB role moot).
# Each VM leaves ~1.5-3 GB of host RAM for Proxmox itself.
#
# IP plan (LAN is 10.0.0.0/8, gateway 10.0.0.1, DHCP 10.0.0.86-10.0.4.254).
# All node IPs are in 10.0.5.x, outside DHCP and clear of the PVE hosts
# (10.0.5.1-9). The /8 prefix from lan_subnet is applied to every node.
module "k3s" {
  source                      = "../"
  authorized_keys_file        = "C:/Users/jaked/.ssh/id_ed25519.pub"
  authorized_private_key_file = "C:/Users/jaked/.ssh/id_ed25519"
  ssh_binary                  = "C:/Windows/System32/OpenSSH/ssh.exe"

  # Install open-iscsi on all nodes so Longhorn can attach volumes.
  longhorn_enabled       = true
  scp_binary             = "C:/Windows/System32/OpenSSH/scp.exe"
  ssh_null_device        = "NUL"
  kubeconfig_interpreter = ["powershell", "-NoProfile", "-Command"]

  # Module builds the Debian 13 cloud-init template itself (no manual steps).
  # The downloaded qcow2 lands on "local" (has the "import" content type); the
  # template disk + cloud-init are created on "local-lvm" (has "images").
  template_image = {
    node_name           = "opti0"
    datastore_id        = "local-lvm"
    import_datastore_id = "local"
    url                 = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
    file_name           = "debian-13-genericcloud-amd64.qcow2"
    disk_size           = 16
    user                = "debian"
  }

  # template = 900, support = 901 (disabled), masters = 902-904, workers = 905-910
  vm_id_start     = 900
  network_gateway = "10.0.0.1"
  lan_subnet      = "10.0.0.1/8"
  cluster_name    = "opti-k3s"

  dns_servers = ["10.0.0.1", "1.1.1.1"]

  # All 9 hosts are the same CPU, so host passthrough is safe and fastest.
  cpu_type = "host"

  # Floating API VIP (keepalived) across the masters. Free address in the
  # control-plane block (support=.16, masters=.17-.19, VIP=.23).
  api_vip        = "10.0.5.23"
  vrrp_router_id = 51
  vrrp_auth_pass = "optivip1" # max 8 chars (VRRPv2)

  # Guest agent left disabled at create time (module installs it during
  # provisioning; flip to true on a later apply if desired).
  vm_agent_enabled = false

  # Embedded etcd: HA control plane, no MariaDB single point of failure.
  cluster_enable_embedded_etcd = true

  # Support node has no role under embedded etcd -> don't create it.
  support_node_enabled = false

  # Disable only servicelb (MetalLB owns LoadBalancer IPs); keep Traefik enabled.
  k3s_disable_components = [
    "servicelb"
  ]

  # 10.0.5.16/29 -> support .16 (unused), masters .17-.19, VIP .23
  control_plane_subnet = "10.0.5.16/29"

  # Reserve the control plane: only critical system pods schedule on masters.
  master_taints = ["CriticalAddonsOnly=true:NoExecute"]

  # Control plane: 3 masters on opti0/1/2, control-plane only.
  master_nodes = [
    {
      target_node    = "opti0"
      cores          = 4
      sockets        = 1
      memory         = 8192
      storage_id     = "local-lvm"
      disk_size      = "48G"
      user           = "k3s"
      network_bridge = "vmbr0"
      network_tag    = -1
    },
    {
      target_node    = "opti1"
      cores          = 4
      sockets        = 1
      memory         = 8192
      storage_id     = "local-lvm"
      disk_size      = "48G"
      user           = "k3s"
      network_bridge = "vmbr0"
      network_tag    = -1
    },
    {
      target_node    = "opti2"
      cores          = 4
      sockets        = 1
      memory         = 8192
      storage_id     = "local-lvm"
      disk_size      = "48G"
      user           = "k3s"
      network_bridge = "vmbr0"
      network_tag    = -1
    }
  ]

  # Workers: one per remaining host (opti3..8), 4 cores / 13 GB each.
  node_pools = [
    {
      subnet      = "10.0.5.24/29" # worker .25
      target_node = "opti3"
      size        = 1
      node_pool_settings = {
        name           = "pool0"
        taints         = []
        cores          = 4
        sockets        = 1
        memory         = 13312
        storage_id     = "local-lvm"
        disk_size      = "128G"
        user           = "k3s"
        network_bridge = "vmbr0"
        network_tag    = -1
      }
    },
    {
      subnet      = "10.0.5.32/29" # worker .33
      target_node = "opti4"
      size        = 1
      node_pool_settings = {
        name           = "pool1"
        taints         = []
        cores          = 4
        sockets        = 1
        memory         = 13312
        storage_id     = "local-lvm"
        disk_size      = "128G"
        user           = "k3s"
        network_bridge = "vmbr0"
        network_tag    = -1
      }
    },
    {
      subnet      = "10.0.5.40/29" # worker .41
      target_node = "opti5"
      size        = 1
      node_pool_settings = {
        name           = "pool2"
        taints         = []
        cores          = 4
        sockets        = 1
        memory         = 13312
        storage_id     = "local-lvm"
        disk_size      = "128G"
        user           = "k3s"
        network_bridge = "vmbr0"
        network_tag    = -1
      }
    },
    {
      subnet      = "10.0.5.48/29" # worker .49
      target_node = "opti6"
      size        = 1
      node_pool_settings = {
        name           = "pool3"
        taints         = []
        cores          = 4
        sockets        = 1
        memory         = 13312
        storage_id     = "local-lvm"
        disk_size      = "128G"
        user           = "k3s"
        network_bridge = "vmbr0"
        network_tag    = -1
      }
    },
    {
      subnet      = "10.0.5.56/29" # worker .57
      target_node = "opti7"
      size        = 1
      node_pool_settings = {
        name           = "pool4"
        taints         = []
        cores          = 4
        sockets        = 1
        memory         = 13312
        storage_id     = "local-lvm"
        disk_size      = "128G"
        user           = "k3s"
        network_bridge = "vmbr0"
        network_tag    = -1
      }
    },
    {
      subnet      = "10.0.5.64/29" # worker .65
      target_node = "opti8"
      size        = 1
      node_pool_settings = {
        name           = "pool5"
        taints         = []
        cores          = 4
        sockets        = 1
        memory         = 13312
        storage_id     = "local-lvm"
        disk_size      = "128G"
        user           = "k3s"
        network_bridge = "vmbr0"
        network_tag    = -1
      }
    }
  ]
}

# Templates the MetalLB GitOps manifests from variables (pure file generation, no
# cluster interaction). Re-run `terraform apply` after changing the pool to
# regenerate gitops/infrastructure/**, which Flux then syncs.
module "metallb" {
  source         = "../metallb"
  pool_addresses = ["10.0.5.80-10.0.5.99"]
  interfaces     = ["eth0"]
  output_dir     = "${path.root}/../gitops/infrastructure"
}

output "kubeconfig_path" {
  value = module.k3s.k3s_kubeconfig_path
}

output "api_endpoint" {
  value = module.k3s.api_endpoint
}
