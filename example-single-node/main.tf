terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.113.0"
    }
  }

  # Remote state on Backblaze B2 (S3-compatible). Credentials are supplied at
  # init time via a gitignored backend.hcl:
  #   terraform init -backend-config=backend.hcl
  #
  # This example uses its own state key so it can coexist with the multi-node
  # example in ../example.
  backend "s3" {
    bucket = "dellathefella-terraform-state"
    key    = "lagrange-k3s-single/terraform.tfstate"
    region = "us-east-005"
    endpoints = {
      s3 = "https://s3.us-east-005.backblazeb2.com"
    }

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
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

variable "network_gateway" {
  description = "LAN gateway handed to every node via cloud-init."
  type        = string
}

variable "lan_subnet" {
  description = "LAN CIDR; only the prefix length is applied to each node."
  type        = string
}

variable "control_plane_subnet" {
  description = "CIDR used for the master address and the API VIP."
  type        = string
}

variable "master_nodes" {
  description = "Control-plane VM definitions."
  type        = any
}

variable "node_pools" {
  description = "Worker node pool definitions (empty for the single-node example)."
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
# VM layout (32 vCPUs / 200 GiB RAM / 600 GiB fast-local):
#   k3s node : 32c/200G, 600G on fast-local (control plane + workloads)
#
# One large node runs the control plane and all workloads. The Proxmox host is
# itself a single point of failure, so extra nodes would not add real HA. The
# node is untainted so workloads schedule there. The support node is disabled
# (embedded etcd makes its MariaDB role moot).
#
# The kubelet max-pods limit is raised from the default 110 to 250 via
# --kubelet-arg=max-pods=250. The default per-node /24 pod CIDR has ~254 IPs,
# so 250 fits without changing the node CIDR mask.
#
# IP plan (LAN is 10.0.0.0/8, gateway 10.0.0.1; Proxmox host is 10.0.6.0):
#   control plane 10.0.6.8/29 -> node .9, VIP .15
#   MetalLB       10.0.6.100-10.0.6.119
module "k3s" {
  source                      = "../"
  authorized_keys_file        = "~/.ssh/id_ed25519.pub"
  authorized_private_key_file = "~/.ssh/id_ed25519"
  ssh_binary                  = "/usr/bin/ssh"

  # Longhorn is disabled: this is a single-node layout, so distributed storage
  # adds overhead without real replication. CNPG uses the k3s local-path
  # provisioner instead.
  longhorn_enabled       = false
  scp_binary             = "/usr/bin/scp"
  ssh_null_device        = "/dev/null"
  kubeconfig_interpreter = ["/bin/sh", "-c"]

  # Module builds the Debian 13 cloud-init template itself (no manual steps).
  template_image = {
    node_name           = "lagrange"
    datastore_id        = "fast-local"
    import_datastore_id = "local"
    url                 = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
    file_name           = "debian-13-genericcloud-amd64.qcow2"
    disk_size           = 16
    user                = "debian"
  }

  # template = 8100, support = 921 (disabled), master = 922
  vm_id_start         = 920
  template_vm_id_base = 8100
  network_gateway     = var.network_gateway
  lan_subnet          = var.lan_subnet
  cluster_name        = "lagrange-k3s-single"

  dns_servers = ["10.0.0.1", "1.1.1.1"]

  # Single host, so host passthrough is safe and fastest.
  cpu_type = "host"

  # Floating API VIP (keepalived) held by the single node.
  api_vip        = "10.0.6.15"
  vrrp_router_id = 52
  vrrp_auth_pass = "lagrvip1" # max 8 chars (VRRPv2)

  vm_agent_enabled = false

  # Write the kubeconfig into the home directory instead of the example dir.
  kubeconfig_output_path = "~/.kube/lagrange-k3s-single.yaml"

  # Embedded etcd: removes the MariaDB dependency (single-node etcd here).
  cluster_enable_embedded_etcd = true

  support_node_enabled = false

  # Disable only servicelb (MetalLB owns LoadBalancer IPs); keep Traefik enabled.
  k3s_disable_components = [
    "servicelb"
  ]

  # 10.0.6.8/29 -> support .8 (unused), node .9, VIP .15
  control_plane_subnet = var.control_plane_subnet

  # Do NOT reserve the node: workloads schedule on the single node.
  master_taints = []

  master_nodes = var.master_nodes
  node_pools   = var.node_pools

  # Raise the per-node pod limit from the default 110 to 250.
  k3s_extra_server_args = ["--kubelet-arg=max-pods=250"]
}

# Templates the MetalLB GitOps manifests from variables.
module "metallb" {
  source         = "../metallb"
  pool_addresses = ["10.0.6.100-10.0.6.119"]
  interfaces     = ["eth0"]
  output_dir     = "${path.root}/../gitops/infrastructure"
}

output "kubeconfig_path" {
  value = module.k3s.k3s_kubeconfig_path
}

output "api_endpoint" {
  value = module.k3s.api_endpoint
}
