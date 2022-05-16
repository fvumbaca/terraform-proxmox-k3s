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
}

provider proxmox {
  pm_log_enable = true
  pm_log_file = "terraform-plugin-proxmox.log"
  pm_debug = true
  pm_log_levels = {
    _default = "debug"
    _capturelog = ""
  }

  ## TODO: Update these for your specific setup
  pm_api_url = "https://192.168.0.25:8006/api2/json"
}

module "k3s" {
  source  = "fvumbaca/k3s/proxmox"
  version = ">= 0.0.0, < 1" # Get latest 0.X release

  authorized_keys_file = "authorized_keys"

  proxmox_node = "my-proxmox-node"

  node_template = "ubuntu-template"
  proxmox_resource_pool = "my-k3s"

  network_gateway = "192.168.0.1"
  lan_subnet = "192.168.0.0/24"

  support_node_settings = {
    cores = 2
    memory = 4096
  }

  master_nodes_count = 2
  master_node_settings = {
    cores = 2
    memory = 4096
  }

  # 192.168.0.200 -> 192.168.0.207 (6 available IPs for nodes)
  control_plane_subnet = "192.168.0.200/29"

  node_pools = [
    {
      name = "default"
      size = 2
      # 192.168.0.208 -> 192.168.0.223 (14 available IPs for nodes)
      subnet = "192.168.0.208/28"
    }
  ]
}

output "kubeconfig" {
  value = module.k3s.k3s_kubeconfig
  sensitive = true
}

