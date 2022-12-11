# terraform-proxmox-k3s-multi-node

A module for spinning up an expandable and flexible K3s server for your HomeLab in a multinode Proxmox cluster.

## Features

- Fully automated. No need to remote into a VM; even for a kubeconfig
- Built in and automatically configured external loadbalancer (both K3s API and ingress)
- Static(ish) MAC addresses for reproducible DHCP reservations
- Node pools to easily scale and to handle many kinds of workloads
- Pure Terraform - no Ansible needed.

## Creating the template
```sh
export QMID=8001
cd /var/lib/vz/template/iso; wget https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img;
qm create $QMID --name "ubuntu-2004-cloudinit-template" --memory 4096 --cores 2 --net0 virtio,bridge=vmbr0;
qm importdisk $QMID focal-server-cloudimg-amd64.img local-lvm;
qm set $QMID --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-$QMID-disk-0;
qm set $QMID --ide2 local-lvm:cloudinit;
qm set $QMID --boot c --bootdisk scsi0;
qm set $QMID --serial0 socket --vga serial0;
qm template $QMID
```

## Prerequisites

- A Proxmox node with sufficient capacity for all nodes
- A cloneable or template VM that supports Cloud-init and is based on Debian
  (ideally ubuntu server)
- 2 cidr ranges for master and worker nodes NOT handed out by DHCP (nodes are
  configured with static IPs from these ranges)

## Usage and Example

```terraform
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
    #master_nodes_count = 3
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
```

### Retrieve Kubeconfig

To get the kubeconfig for your new K3s first make sure to forward the module
output in your project's output:

```terraform
output "kubeconfig" {
  # Update module name. Here we are using 'k3s'
  value = module.k3s.k3s_kubeconfig
  sensitive = true
}
```

Finally output the config file:

```sh
# Test out the config:
terraform output -raw kubeconfig > config.yaml && kubectl --kubeconfig config.yaml get nodes
kubectl --kubeconfig config.yaml get nodes
```


> Make sure your support node is routable from the computer you are running the
command on!

## Runbooks

- [How to roll (update) your nodes](docs/roll-node-pools.md)

## Why use nodepools and subnets?

This module is designed with nodepools and subnets to allow for changes to the
cluster composition in the future. If later on, you want to add another master
or worker node, you can do so without needing to teardown/modify existing
nodes. Nodepools are key if you plan to support nodes with different nodepool
capabilities in the future without impacting other nodes.

## Todo

- [ ] Add variable to allow workloads on master nodes
