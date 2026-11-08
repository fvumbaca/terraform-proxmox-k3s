# Topology for the single Proxmox host "lagrange" (10.0.6.0).
# These values are consumed by the module block in main.tf.

network_gateway      = "10.0.0.1"
lan_subnet           = "10.0.0.1/8"
control_plane_subnet = "10.0.6.16/29"

# One master: a single Proxmox host is already a single point of failure, so
# extra master VMs add no real HA. The master runs the whole control plane
# (k3s server + embedded etcd), so it gets 8 cores / 16 GiB. It is tainted so
# only critical system pods schedule there. The 48G disk lives on local-lvm,
# keeping the fast-local ZFS pool free for worker/DB data.
master_nodes = [
  {
    target_node    = "lagrange"
    cores          = 8
    sockets        = 1
    memory         = 16384
    storage_id     = "local-lvm"
    disk_size      = "48G"
    user           = "k3s"
    network_bridge = "vmbr0"
    network_tag    = -1
  }
]

# 4 general-purpose workers. 64G boot disks are enough for images/ephemeral
# data and leave room in fast-local for the dedicated DB pool.
node_pools = [
  {
    subnet      = "10.0.6.24/29" # worker .25
    target_node = "lagrange"
    size        = 1
    node_pool_settings = {
      name           = "pool2"
      taints         = []
      cores          = 4
      sockets        = 1
      memory         = 24576
      storage_id     = "fast-local"
      disk_size      = "64G"
      user           = "k3s"
      network_bridge = "vmbr0"
      network_tag    = -1
    }
  },
  {
    subnet      = "10.0.6.32/29" # worker .33
    target_node = "lagrange"
    size        = 1
    node_pool_settings = {
      name           = "pool3"
      taints         = []
      cores          = 4
      sockets        = 1
      memory         = 24576
      storage_id     = "fast-local"
      disk_size      = "64G"
      user           = "k3s"
      network_bridge = "vmbr0"
      network_tag    = -1
    }
  },
  {
    subnet      = "10.0.6.40/29" # worker .41
    target_node = "lagrange"
    size        = 1
    node_pool_settings = {
      name           = "pool4"
      taints         = []
      cores          = 4
      sockets        = 1
      memory         = 24576
      storage_id     = "fast-local"
      disk_size      = "64G"
      user           = "k3s"
      network_bridge = "vmbr0"
      network_tag    = -1
    }
  },
  {
    subnet      = "10.0.6.48/29" # worker .49
    target_node = "lagrange"
    size        = 1
    node_pool_settings = {
      name           = "pool5"
      taints         = []
      cores          = 4
      sockets        = 1
      memory         = 24576
      storage_id     = "fast-local"
      disk_size      = "64G"
      user           = "k3s"
      network_bridge = "vmbr0"
      network_tag    = -1
    }
  },
  {
    # Dedicated CloudNativePG pool. The taint keeps non-DB workloads off these
    # nodes; CNPG pins its instances here via nodeSelector/tolerations (see
    # gitops/apps/postgres/cluster.yaml). Each node gets a 100G boot disk plus
    # a 100G data disk mounted at /mnt/sdb1 for Longhorn.
    #
    # IMPORTANT: Longhorn's longhorn-manager DaemonSet must tolerate
    # dedicated=db:NoSchedule on these nodes (add the toleration to the
    # Longhorn Helm values) and use /mnt/sdb1 as its data path. Without the
    # toleration, Longhorn cannot run here and CNPG volumes cannot be
    # provisioned on the DB nodes.
    subnet      = "10.0.6.64/29" # db .65/.66
    target_node = "lagrange"
    size        = 2
    node_pool_settings = {
      name           = "db"
      taints         = ["dedicated=db:NoSchedule"]
      cores          = 4
      sockets        = 1
      memory         = 32768
      storage_id     = "fast-local"
      disk_size      = "100G"
      user           = "k3s"
      network_bridge = "vmbr0"
      network_tag    = -1
      node_labels    = ["workload=cnpg"]
      additional_storage = {
        storage_id = "fast-local"
        disk_size  = "100G"
      }
    }
  }
]
