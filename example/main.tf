terraform {
  required_providers {
    proxmox = {
      source = "Telmate/proxmox"
      version = "2.9.3"
    }

    macaddress = {
      source = "ivoronin/macaddress"
      version = "0.3.0"
    }
  }

  experiments = [module_variable_optional_attrs]
}

provider "proxmox" {
  pm_tls_insecure = true
  pm_api_url = var.pm_api_url
  pm_api_token_id = var.pm_api_token_id
  pm_api_token_secret = var.pm_api_token_secret
  pm_log_enable = true
  pm_log_file = "plugin-proxmox.log"
  pm_debug = true
  pm_log_levels = {
    _default = "debug"
    _capturelog = ""
  }
}

locals {
  node_pools = [
    merge(var.vm_defaults, {
      name = "compute"
      size = 12
      subnet = "10.41.2.0/24"
      memory = 2048
    }),
    merge(var.vm_defaults, {
      name = "mem"
      size = 2
      subnet = "10.41.3.0/24"
      memory = 4096
    })
  ]
} 

module "k3s" {
  #source  = "github.com/jan-tee/terraform-proxmox-k3s"
  source = "./terraform-proxmox-k3s/"
  #version = ">= 0.0.0, < 1.0.0" # Get latest 0.X release

  cluster_name = "demo"
  lan_subnet = "10.41.0.0/16"
  ciuser = var.ciuser

  support_node_settings = merge(var.vm_defaults, {
    memory = 2048
  })

  # Disable default traefik and servicelb installs for metallb and traefik 2
  k3s_disable_components = [
    "traefik",
    "servicelb"
  ]

  master_nodes_count = 2
  master_node_settings = merge(var.vm_defaults, {
    memory = 4096
  })

  control_plane_subnet = "10.41.1.0/24"
  node_pools = local.node_pools 
}

output "kubeconfig" {
  # Update module name. Here we are using 'k3s'
  value = module.k3s.k3s_kubeconfig
  sensitive = true
}
