module "k3s" {
  #source  = "github.com/jan-tee/terraform-proxmox-k3s"
  source = "../"
  #version = ">= 0.0.0, < 1.0.0" # Get latest 0.X release

  cluster_name = var.cluster_name
  lan_subnet   = var.lan_subnet

  # uncommment this if you want to enable a local registry with an untrusted
  # certificate with this URL - you can only do this before you create the
  # cluster:
  #
  insecure_registries = var.insecure_registries

  default_node_settings = var.default_node_settings
  support_node_settings = var.support_node_settings

  # Disable default traefik and servicelb installs for metallb and traefik 2
  k3s_disable_components = [
    "traefik",
    "servicelb"
  ]

  master_nodes_count   = var.master_node_settings.count
  master_node_settings = var.master_node_settings

  control_plane_subnet = var.control_plane_subnet
  node_pools           = var.node_pools
}

output "kubeconfig" {
  # Update module name. Here we are using 'k3s'
  value     = module.k3s.k3s_kubeconfig
  sensitive = true
}
