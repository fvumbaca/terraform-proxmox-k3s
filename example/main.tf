terraform{
  required_providers {
    proxmox = {
      source  = "Telmate/proxmox"
      version = "2.9.3"
    }

    macaddress = {
      source  = "ivoronin/macaddress"
      version = "0.3.0"
    }
  }
  experiments = [module_variable_optional_attrs]
}

provider "proxmox" {
  # make sure to export PM_API_TOKEN_ID and PM_API_TOKEN_SECRET
  pm_tls_insecure = true
  pm_log_enable = true
  pm_api_url      = "https://${var.proxmox_entry_point_ip}:8006/api2/json"
}

module "k3s" {
    source  = "git::github.com/dellathefella/terraform-proxmox-k3s-multinode"
    authorized_keys_file = var.authorized_keys_file  
    proxmox_node = "della1"

    #Support node if none specified installs onto entry point node
    proxmox_support_node = "della3"

    node_template = "ubuntu-2004-cloudinit-template"

    network_gateway = "10.0.120.1"
    lan_subnet = "10.0.120.0/22"
  
    
    support_node_settings = {
        cores = 2
        memory = 4096
    }

    # Disable default traefik and servicelb installs for metallb and traefik 2
    /*k3s_disable_components = [
        "traefik",
        "servicelb"
    ]
    */
    # 10.0.121.1 - 10.0.121.6	(6 available IPs for nodes)
    control_plane_subnet = "10.0.121.0/29"

    #This number must match the number of entries for master_nodes
    master_nodes_count = 3
    #distributes the masters upon these nodes in sequential order if not specified the entry point node
    master_node_target_nodes = ["della1","della2","della3"]
    master_node_settings = {
        cores = 2
        memory = 4096
    }

    # 192.168.0.200 -> 192.168.0.207 (6 available IPs for nodes)

    node_pools = [
        {
        name = "della1"
        target_node = "della1"
        size = 2
        # 110.0.121.1 - 10.0.121.6	 (6 available IPs for nodes)
        subnet = "10.0.121.8/29"
        },
        {
        name = "della2"
        target_node = "della2"
        size = 2
        # 10.0.121.17 - 10.0.121.22 (6 available IPs for nodes)
        subnet = "10.0.121.16/29"
        },
        #This is a support node so gets less nodes.
        {
        name = "della3"
        target_node = "della3"
        size = 1
        # 10.0.121.25 - 10.0.121.30 (6 available IPs for nodes)
        subnet = "10.0.121.24/29"
        },
        {
        name = "della4"
        target_node = "della4"
        size = 3
        # 10.0.121.33 - 10.0.121.38	 (14 available IPs for nodes)
        subnet = "10.0.121.32/29"
        },
        {
        name = "della5"
        target_node = "della5"
        size = 3
        # 10.0.121.41 - 10.0.121.46	 (14 available IPs for nodes)
        subnet = "10.0.121.40/29"
        }
    ]
}


output "kubeconfig" {
  # Update module name. Here we are using 'k3s'
  value = module.k3s.k3s_kubeconfig
  sensitive = true
}