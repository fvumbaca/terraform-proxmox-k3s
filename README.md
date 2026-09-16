# terraform-proxmox-k3s-multi-node

A module for spinning up an expandable and flexible K3s server for your HomeLab in a multinode Proxmox cluster.

## Features
- Fully automated. No need to remote into a VM; even for a kubeconfig
- Highly available K3s API via a keepalived VIP floating across the masters (each master serves the API directly - no proxy)
- Ingress handled in-cluster by [MetalLB](docs/metallb.md) (L2 mode) for `LoadBalancer` services
- Support for embedded etcd and MariaDB auto configuration [Example](example/README.md)
- Static(ish) MAC addresses for reproducible DHCP reservations
- Node pools to easily scale and to handle many kinds of workloads
- Master nodes with custom topology for your use cases.
- Pure Terraform - no Ansible needed.
- Support to add and automatically format additional storage for use with tools like Longhorn.

## Prerequisites
- Proxmox node(s) running 8.2 or higher
- Proxmox nodes with sufficient capacity for all nodes
- A cloneable or template VM that supports Cloud-init and is based on Debian (the module targets Debian cloud images). Guide outlined below on how to do that.
- At least 2 CIDR ranges for master and worker nodes NOT handed out by DHCP (All Nodes are configured with static IPs from these ranges)

## Creating the Debian 12 (bookworm) or 13 (trixie) template(s)

### Option A: Let the module build the template

Set `template_image` and the module downloads the cloud image and builds the template VM itself (no manual steps). The template takes `vm_id_start` and is named `<cluster_name>-template`:

```terraform
template_image = {
  node_name    = "pve-prd0"
  datastore_id = "local"
  # Debian 13 (trixie). For the LTS use bookworm:
  #   https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2
  url       = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
  file_name = "debian-13-genericcloud-amd64.qcow2"
  disk_size = 16 # GB
  # user defaults to "debian" (the Debian cloud image's default sudo user)
}
```

### Option B: Create the template(s) manually

Because of limitations of the way Proxmox uses templates we need to create a template on each node with an incrementing QMID. These templates will be identical but the QMID will be different. You can delete these when you are done if you don't plan on modifying the cluster.
```sh

# Debian 12 (bookworm)
export QMID=8002
cd /var/lib/vz/template/iso &&
wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2 &&
qm create $QMID --name "debian-12-cloudinit-template" --memory 4096 --cores 2 --net0 virtio,bridge=vmbr0 &&
qm importdisk $QMID debian-12-genericcloud-amd64.qcow2 local-lvm &&
qm set $QMID --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-$QMID-disk-0 &&
qm set $QMID --ide2 local-lvm:cloudinit &&
qm set $QMID --boot c --bootdisk scsi0 &&
qm template $QMID

# Debian 13 (trixie)
export QMID=8003
cd /var/lib/vz/template/iso &&
wget https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2 &&
qm create $QMID --name "debian-13-cloudinit-template" --memory 4096 --cores 2 --net0 virtio,bridge=vmbr0 &&
qm importdisk $QMID debian-13-genericcloud-amd64.qcow2 local-lvm &&
qm set $QMID --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-$QMID-disk-0 &&
qm set $QMID --ide2 local-lvm:cloudinit &&
qm set $QMID --boot c --bootdisk scsi0 &&
qm template $QMID
```

> The bpg provider clones by **numeric VM ID**, so pass the template's QMID (e.g. `8003`) as the module's `template_vm_id`. `template_vm_id` and `template_image` are mutually exclusive — exactly one must be set.



## Usage and Example

```terraform
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.113.0"
    }
  }
}

provider "proxmox" {
  # make sure to export PM_API_TOKEN_ID and PM_API_TOKEN_SECRET
  endpoint = "https://10.10.1.100:8006/"
  insecure = true
}

module "k3s" {
  source                      = "git::https://github.com/dellathefella/terraform-proxmox-k3s-multinode"
  authorized_keys_file        = "~/.ssh/id_rsa.pub"
  authorized_private_key_file = "~/.ssh/id_rsa"
  #Support node if none specified installs onto entry point node
  # Numeric VM ID (QMID) of the debian-13-cloudinit-template created above.
  # Mutually exclusive with template_image (see Option A).
  template_vm_id = 8003
  # ID allocation: auto-built template = 900, support = 901, masters = 902+, workers after
  vm_id_start     = 900
  network_gateway = "10.10.1.1"
  lan_subnet      = "10.10.1.1/16"
  cluster_name    = "jdella-com-prd"

  # DNS servers handed to nodes via cloud-init (nodes use static IPs)
  dns_servers = ["10.10.1.1", "1.1.1.1"]

  # CPU type for all nodes; "host" for max perf if all PVE nodes are compatible
  cpu_type = "x86-64-v2-AES"

  # Register masters as Proxmox HA resources (HA group must already exist)
  # ha_group = "k3s-ha"

  # Guard created VMs against accidental GUI changes
  protection = false

  # Floating API VIP (keepalived) across the masters. Clients reach the API at
  # <api_vip>:6443 directly; if a master's k3s goes unhealthy the VIP moves.
  # The VIP must be outside your DHCP range and not collide with any node IP.
  api_vip        = "10.10.2.7"
  vrrp_router_id = 51
  vrrp_auth_pass = "k3svip1" # max 8 chars (VRRPv2)

  # qemu-guest-agent is installed during provisioning; flip this to true
  # AFTER the first successful apply (enabling it during create makes the
  # provider wait for an agent that isn't installed yet).
  vm_agent_enabled = false

  # Enabling this setting disables the MariaDB support instance for the cluster.
  # The main advantage of enabling embedded etcd is the cluster no longer has a single point of failure. But can increase resource usage.
  # You must run terraform destroy before updating this value.
  cluster_enable_embedded_etcd = true

  # Optionally pin the k3s version (empty = current stable channel, e.g. v1.37.0+k3s1)
  # k3s_version = "v1.37.0+k3s1"

  # Support node settings
  support_node_settings = {
    target_node = "pve-prd0"
    # DB related settings are ignored when cluster_enable_embedded_etcd = true
    # If using embedded etcd the resources here should be dramatically reduced as Nginx is the main process running.
    # Conversely the storage and specs for the control plane nodes should be increased.
    cores          = 2
    sockets        = 1
    memory         = 1024
    storage_id     = "pve-ssd"
    disk_size      = "16G"
    user           = "support"
    network_tag    = -1
    db_name        = "k3s"
    db_user        = "k3s"
    network_bridge = "vmbr0"
  }

  # Disable default traefik and servicelb installs for metallb and traefik 2
  k3s_disable_components = [
    "traefik",
    "servicelb"
  ]
  # 10.10.2.1 - 10.10.2.6	(6 available IPs for nodes)
  control_plane_subnet = "10.10.2.0/29"

  # These are not rolled as a pool but individually.
  master_nodes = [
    {
      target_node    = "pve-prd0"
      cores          = 2
      sockets        = 1
      memory         = 2048
      storage_id     = "pve-ssd"
      # Set disk_size much higher if using embedded etcd
      disk_size      = "240G"
      user           = "k3s"
      network_bridge = "vmbr0"
      network_tag    = -1
    },
    {
      target_node    = "pve-prd1"
      cores          = 2
      sockets        = 1
      memory         = 2048
      storage_id     = "pve-ssd"
      # Set disk_size much higher if using embedded etcd
      disk_size      = "240G"
      user           = "k3s"
      network_bridge = "vmbr0"
      network_tag    = -1
    },
    {
      target_node    = "pve-prd2"
      cores          = 2
      sockets        = 1
      memory         = 2048
      storage_id     = "pve-ssd"
      # Set disk_size much higher if using embedded etcd
      disk_size      = "240G"
      user           = "k3s"
      network_bridge = "vmbr0"
      network_tag    = -1
    }
  ]
  node_pools = [
    {
      # 10.10.2.9 - 10.10.2.14 (6 available IPs for nodes)
      subnet = "10.10.2.8/29"

      target_node = "pve-prd0"
      size        = 1
      node_pool_settings = {
        name           = "pool0"
        taints         = []
        cores          = 8
        sockets        = 1
        memory         = 8192
        storage_id     = "pve-ssd"
        disk_size      = "1000G"
        user           = "k3s"
        network_bridge = "vmbr0"
        network_tag    = -1
        additional_storage = {
          storage_id = "pve-hdd"
          disk_size  = "3500G"
        }
      }
    },
    {
      # 10.10.2.17 - 10.10.2.22 (6 available IPs for nodes)
      subnet = "10.10.2.16/29"

      target_node = "pve-prd1"
      size        = 1
      node_pool_settings = {
        name           = "pool1"
        taints         = []
        cores          = 8
        sockets        = 1
        memory         = 10240
        storage_id     = "pve-ssd"
        disk_size      = "1000G"
        user           = "k3s"
        network_bridge = "vmbr0"
        network_tag    = -1
        additional_storage = {
          storage_id = "pve-hdd"
          disk_size  = "3500G"
        }
      }
    },
    {
      # 10.10.2.25 - 10.10.2.30 (6 available IPs for nodes)
      subnet = "10.10.2.24/29"

      target_node = "pve-prd2"
      size        = 1
      node_pool_settings = {
        name           = "pool2"
        taints         = []
        cores          = 8
        sockets        = 1
        memory         = 10240
        storage_id     = "pve-ssd"
        disk_size      = "1000G"
        user           = "k3s"
        network_bridge = "vmbr0"
        network_tag    = -1
        additional_storage = {
          storage_id = "pve-hdd"
          disk_size  = "3500G"
        }
      }
    }
  ]
}

output "kubeconfig" {
  # Update module name. Here we are using 'k3s'
  value     = module.k3s.k3s_kubeconfig_path
  sensitive = true
}
```

### Retrieve Kubeconfig

The kubeconfig is written to `kubeconfig_output_path` (default `kubeconfig.yaml` in the root module) **at apply time** - it is fetched once from the first master and the server address is already rewritten to the API endpoint (VIP when set). Forward the path from your project:

```terraform
output "kubeconfig_path" {
  # Update module name. Here we are using 'k3s'
  value = module.k3s.k3s_kubeconfig_path
}
```

Then use it:

```sh
kubectl --kubeconfig ./kubeconfig.yaml get nodes
```

> Make sure your API endpoint (VIP or first master) is routable from the computer you are running the command on!
>
> The file is only rewritten when the first master or the API endpoint changes. To force a refresh, taint `null_resource.kubeconfig` or delete the file and re-apply.

## Caveats and operational notes

### Disk resizing (`ignore_changes = [disk]`)

Every node VM declares `lifecycle { ignore_changes = [disk, network_device] }`.
This is deliberate: it stops Terraform from fighting manual disk operations and
from trying to "re-shrink" a disk that has already been grown. The consequence
is that **changing `disk_size` in your variables does nothing to an existing
VM** - Terraform will not grow, shrink, or replace the disk.

To resize a node's disk you must do it out-of-band:

1. Grow the underlying disk in Proxmox (`qm resize <vmid> scsi0 <newsize>`), then
   expand the partition/filesystem inside the guest (`growpart` + `resize2fs`).
2. Update `disk_size` in your variables to match so future clones/templates line
   up. Existing VMs keep ignoring the value.

If you genuinely need Terraform to manage the disk again, remove `disk` from
`ignore_changes` and run a plan - but expect a replacement/force-replace on any
mismatch, so do this knowingly.

### MariaDB is a single point of failure

When `cluster_enable_embedded_etcd = false`, the cluster stores its state in the
MariaDB instance on the **single** support node. That node is a SPOF: if it goes
down, the K3s API cannot read/write cluster state and the control plane becomes
unavailable (running workloads keep running, but you cannot schedule, update, or
join nodes until the DB returns). There is no DB failover in this module.

For a control plane that survives losing a database host, use **embedded etcd**
(`cluster_enable_embedded_etcd = true`) with an odd number of masters (3+). That
removes the support-node DB dependency entirely. See [Backups and restore](docs/backups.md)
for how to back up either backend.

## Runbooks

- [How to roll (update) your nodes](docs/roll-node-pools.md)
- [Setting up MetalLB for ingress](docs/metallb.md)
- [Backups and restore](docs/backups.md)

## Why use nodepools and subnets?

This module is designed with nodepools and subnets to allow for changes to the
cluster composition in the future. If later on, you want to add another master
or worker node, you can do so without needing to teardown/modify existing
nodes. Nodepools are key if you plan to support nodes with different nodepool
capabilities in the future without impacting other nodes.

## Versioned consumption

Pin a released tag instead of tracking the default branch:

```terraform
module "k3s" {
  source = "git::https://github.com/dellathefella/terraform-proxmox-k3s-multinode?ref=v1.0.0"
  # ...
}
```

## Reference

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->