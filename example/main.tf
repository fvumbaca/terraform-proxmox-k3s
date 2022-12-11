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
}



provider "proxmox" {
  # make sure to export PM_API_TOKEN_ID and PM_API_TOKEN_SECRET
  pm_tls_insecure = true
  pm_log_enable = true
  pm_api_url      = "https://titan.local.com:8006/api2/json"
}

module "k3s" {
    source  = "git::github.com/dellathefella/terraform-proxmox-k3s-multinode"
    authorized_keys_file = "~/.ssh/id_rsa.pub"
    authorized_private_key_file = "~/.ssh/id_rsa"
    proxmox_node = "titan"

    #Support node if none specified installs onto entry point node
    proxmox_support_node = "titan"
    node_template = "ubuntu-2004-cloudinit-template"
    network_gateway = "10.0.0.1"
    lan_subnet = "10.0.0.1/18"
    cluster_name = "dev"
    support_node_settings = {
        cores = 2
        sockets = 1
        memory = 8192
        storage_type = "scsi"
        storage_id   = "nytesolutions-fast-store"
        disk_size    = "10G"
        storage_type = "scsi"
        user         = "support"
        network_tag  = -1
        db_name = "k3s"
        db_user = "k3s"
        network_bridge = "vmbr0"
    }

    # Disable default traefik and servicelb installs for metallb and traefik 2
    k3s_disable_components = [
        "traefik",
        "servicelb"
    ]
    # 10.0.6.1 - 10.0.6.6	(6 available IPs for nodes)
    control_plane_subnet = "10.0.6.0/29"

    #This number must match the number of entries for master_nodes
    #distributes the masters upon these nodes in sequential order if not specified the entry point node
    master_node_target_nodes = ["titan"]
    master_node_settings = {
        cores          = 2
        sockets        = 1
        memory         = 8192
        storage_type   = "scsi"
        storage_id     = "local-lvm"
        user           = "k3s"
        disk_size      = "20G"
        user           = "k3s"
        network_bridge = "vmbr0"
        network_tag    = -1
        user           = "k3s"
    }

    # 192.168.0.200 -> 192.168.0.207 (6 available IPs for nodes)

    node_pools = [
        {
        # 10.0.6.1 - 10.0.6.6	 (6 available IPs for nodes)
        subnet = "10.0.6.8/29"

        target_node = "titan"
        size = 2
        node_pool_settings = {
          name           = "pool0",
          taints         = [""]
          cores          = 2
          sockets        = 1
          memory         = 8192
          storage_type   = "scsi"
          storage_id     = "nytesolutions-fast-store"
          disk_size      = "20G"
          user           = "k3s"
          network_bridge = "vmbr0"
          network_tag    = -1
        }
        },
        {
        # 10.0.6.16 - 10.0.6.23 (6 available IPs for nodes)
        subnet = "10.0.6.16/29"

        target_node = "titan"
        size = 2
        node_pool_settings = {
          name           = "pool1",
          taints         = [""]
          cores          = 2
          sockets        = 1
          memory         = 8192
          storage_type   = "scsi"
          storage_id     = "nytesolutions-fast-store"
          disk_size      = "20G"
          user           = "k3s"
          network_bridge = "vmbr0"
          network_tag    = -1
        }
        }
    ]
}


output "kubeconfig" {
  # Update module name. Here we are using 'k3s'
  value = module.k3s.k3s_kubeconfig
  sensitive = true
}