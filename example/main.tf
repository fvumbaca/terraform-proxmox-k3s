locals {
  node_pools = [
    merge(var.vm_defaults, {
      name = "node"
      size = 20
      subnet = "192.168.42.0/24"
      ip_offset = 205
      memory = 4096
      balloon = 4096
    })
  ]
} 

module "k3s" {
  #source  = "github.com/jan-tee/terraform-proxmox-k3s"
  source = "../"
  #version = ">= 0.0.0, < 1.0.0" # Get latest 0.X release

  cluster_name = var.cluster_name
  lan_subnet = var.lan_subnet
  ciuser = var.ciuser

  # uncommment this if you want to enable a local registry with an untrusted
  # certificate with this URL - you can only do this before you create the
  # cluster:
  #
  insecure_registries = var.insecure_registries

  support_node_settings = merge(var.vm_defaults, {
    memory = 2048
    balloon = 2048
    ip_offset = 200
  })

  # Disable default traefik and servicelb installs for metallb and traefik 2
  k3s_disable_components = [
    "traefik",
    "servicelb"
  ]

  master_nodes_count = 2
  master_node_settings = merge(var.vm_defaults, {
    memory = 4096
    balloon = 4096
    ip_offset = 201
  })

  control_plane_subnet = var.control_plane_subnet
  node_pools = local.node_pools 
}

output "kubeconfig" {
  # Update module name. Here we are using 'k3s'
  value = module.k3s.k3s_kubeconfig
  sensitive = true
}
