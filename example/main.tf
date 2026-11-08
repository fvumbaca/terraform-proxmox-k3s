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
  #
  # NOTE: the key is intentionally different from the old opti-k3s state. The
  # old cluster lived on the (now unreachable) opti0-8 hosts; starting a fresh
  # state key avoids Terraform trying to destroy those orphaned resources.
  backend "s3" {
    # B2 bucket name (must be globally unique on B2).
    bucket = "dellathefella-terraform-state"
    # Path/key of the state file inside the bucket.
    key = "lagrange-k3s/terraform.tfstate"
    # B2 region of the bucket. Must match the endpoint below.
    region = "us-east-005"
    # B2 S3-compatible endpoint for that region.
    endpoints = {
      s3 = "https://s3.us-east-005.backblazeb2.com"
    }

    # B2 quirks: it is not real AWS, so skip the AWS-specific checks.
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true

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

# Topology inputs. Kept as root variables so terraform.tfvars is the single
# place to edit node sizing / IP ranges.
variable "network_gateway" {
  description = "LAN gateway handed to every node via cloud-init."
  type        = string
}

variable "lan_subnet" {
  description = "LAN CIDR; only the prefix length is applied to each node."
  type        = string
}

variable "control_plane_subnet" {
  description = "CIDR used for the support/master addresses and the API VIP."
  type        = string
}

variable "master_nodes" {
  description = "Control-plane VM definitions."
  type        = any
}

variable "node_pools" {
  description = "Worker/DB node pool definitions."
  type        = any
}

provider "proxmox" {
  endpoint  = "https://10.0.6.0:8006/"
  api_token = "${var.pm_token_id}=${var.pm_token_secret}"
  insecure  = true
}

# Single Proxmox host "lagrange" (10.0.6.0):
#   Intel Xeon E5-2699 v3 (18 cores / 36 threads), 251 GiB RAM,
#   ZFS ARC capped at 16 GiB, fast-local ZFS pool (~955 GiB),
#   local-lvm (~365 GiB), local dir (~89 GiB) for ISO/import.
#
# VM layout (32 vCPUs / 176 GiB RAM / ~672 GiB fast-local + 48 GiB local-lvm):
#   master0   : 8c/16G, 48G on local-lvm   (control-plane only)
#   pool2-5   : 4c/24G, 64G on fast-local  (general workloads)
#   db0-1     : 4c/32G, 100G boot + 100G Longhorn data disk on fast-local (CNPG)
#
# One master runs the whole control plane. The Proxmox host is itself a single
# point of failure, so extra master VMs would not add real HA. The master is
# tainted CriticalAddonsOnly:NoExecute so only critical system pods schedule
# there. The support node is disabled (embedded etcd makes its MariaDB role moot).
#
# IP plan (LAN is 10.0.0.0/8, gateway 10.0.0.1; Proxmox host is 10.0.6.0):
#   control plane 10.0.6.16/29 -> master .17, VIP .23
#   workers       10.0.6.24/29, .32/29, .40/29, .48/29 -> .25/.33/.41/.49
#   CNPG DB pool  10.0.6.64/29 -> .65/.66
#   MetalLB       10.0.6.80-10.0.6.99
module "k3s" {
  source                      = "../"
  authorized_keys_file        = "~/.ssh/id_ed25519.pub"
  authorized_private_key_file = "~/.ssh/id_ed25519"
  ssh_binary                  = "/usr/bin/ssh"

  # Install open-iscsi on all nodes so Longhorn can attach volumes.
  longhorn_enabled       = true
  scp_binary             = "/usr/bin/scp"
  ssh_null_device        = "/dev/null"
  kubeconfig_interpreter = ["/bin/sh", "-c"]

  # Module builds the Debian 13 cloud-init template itself (no manual steps).
  # The downloaded qcow2 lands on "local" (has the "import" content type); the
  # template disk + cloud-init are created on "fast-local" (has "images").
  template_image = {
    node_name           = "lagrange"
    datastore_id        = "fast-local"
    import_datastore_id = "local"
    url                 = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
    file_name           = "debian-13-genericcloud-amd64.qcow2"
    disk_size           = 16
    user                = "debian"
  }

  # template = 8000, support = 901 (disabled), master = 902, workers = 903-908
  vm_id_start     = 900
  network_gateway = var.network_gateway
  lan_subnet      = var.lan_subnet
  cluster_name    = "lagrange-k3s"

  dns_servers = ["10.0.0.1", "1.1.1.1"]

  # Single host, so host passthrough is safe and fastest.
  cpu_type = "host"

  # Floating API VIP (keepalived) held by the master. Free address in the
  # control-plane block (support=.16, master=.17, VIP=.23).
  api_vip        = "10.0.6.23"
  vrrp_router_id = 51
  vrrp_auth_pass = "optivip1" # max 8 chars (VRRPv2)

  # Guest agent left disabled at create time (module installs it during
  # provisioning; flip to true on a later apply if desired).
  vm_agent_enabled = false

  # Embedded etcd: removes the MariaDB dependency (single-node etcd here, since
  # the Proxmox host itself is the single point of failure).
  cluster_enable_embedded_etcd = true

  # Support node has no role under embedded etcd -> don't create it.
  support_node_enabled = false

  # Disable only servicelb (MetalLB owns LoadBalancer IPs); keep Traefik enabled.
  k3s_disable_components = [
    "servicelb"
  ]

  # 10.0.6.16/29 -> support .16 (unused), master .17, VIP .23
  control_plane_subnet = var.control_plane_subnet

  # Reserve the control plane: only critical system pods schedule on masters.
  master_taints = ["CriticalAddonsOnly=true:NoExecute"]

  # Control plane: one master on lagrange, control-plane only.
  master_nodes = var.master_nodes

  # General workers + a dedicated, tainted CNPG DB pool. See terraform.tfvars.
  node_pools = var.node_pools
}

# Templates the MetalLB GitOps manifests from variables (pure file generation, no
# cluster interaction). Re-run `terraform apply` after changing the pool to
# regenerate gitops/infrastructure/**, which Flux then syncs.
module "metallb" {
  source         = "../metallb"
  pool_addresses = ["10.0.6.80-10.0.6.99"]
  interfaces     = ["eth0"]
  output_dir     = "${path.root}/../gitops/infrastructure"
}

output "kubeconfig_path" {
  value = module.k3s.k3s_kubeconfig_path
}

output "api_endpoint" {
  value = module.k3s.api_endpoint
}
