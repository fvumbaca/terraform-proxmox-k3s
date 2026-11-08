# Single large k3s node on the Proxmox host "lagrange" (10.0.6.0).
# This is an alternative to the multi-node example in ../example.

network_gateway      = "10.0.0.1"
lan_subnet           = "10.0.0.1/8"
control_plane_subnet = "10.0.6.8/29"

# One large node: control plane + workloads. 32 vCPUs / 200 GiB / 600G on
# fast-local. The host has 36 threads / 251 GiB, leaving 4 threads and ~35 GiB
# for Proxmox + the 16 GiB ZFS ARC.
master_nodes = [
  {
    target_node    = "lagrange"
    cores          = 32
    sockets        = 1
    memory         = 204800
    storage_id     = "fast-local"
    disk_size      = "600G"
    user           = "k3s"
    network_bridge = "vmbr0"
    network_tag    = -1
  }
]

# No separate workers or DB pool: the single node runs everything.
node_pools = []
