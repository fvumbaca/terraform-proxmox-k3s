cluster_name         = "bart"
insecure_registries = [ "registry.k8s.lab" ]

default_node_settings = {
  nameserver   = "192.168.42.1"
  searchdomain = "k8s.lab"
  target_node  = "pve"
  target_pool  = "k8s"
  image_id     = "template-cloudinit-ubuntu2204"
  disk_size    = "30G"
  memory       = 4096
  storage_id   = "vms-01"
  subnet       = "192.168.42.0/24"
  gw           = "192.168.42.1"
  ciuser       = "terraform"
  network_bridge = "vmbr0"
  network_tag  = 0
  # put your authorized_keys content below this line, before the end-of-file marker
  authorized_keys = <<EOF
    ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDAQKzUKoLlnmONhr0X5Nd99r6M96VbKysVVrgKVlaADVWSTNJxoaZY4U1BIHXvXpWrTWQLzuKz1JOkroMI1xZCbjR2fv7wWbRqcALadINCRs5fE8oTA/ZQsar82NUzMGHxNtlrhaRhiHf4JLzAdBQoPQaIHPYROpqT2ygABoDhBtP7HzsAA5ul9hVkGz2eM/j5NguvgTMzU/mGwlnLXGDaihGmY0eQLvxpergvDeczxjb2yYBMVm9execfT8Y8TxitivQzZZxwM/hlF/y9ggfBb3XRMbdOog/fwQlLmCn0ffMXZapAIieLKgF6LLljvZz8c+8Wl2ybZcWnOMUN/r/1bn0coLVe6exUK9ygMyqKl2tFqY3ITuuV3Pkk0cBtzvypGYPhdiPdf5701zZMgyDtO3hzk5cjJXx10CfuvwTsPLkLqCzu7HJjW2s+1FL3stk7VYw4e9MGr+Z46mBH+lWGn4RNQmDvhR3ChdVNb1HgslM5dN9VWqtfyO4XVI+LRf0= root@admin
    EOF
}

support_node_settings = {
  ip_offset = 206,
}

master_node_settings = {
  count     = 2
  ip_offset = 207
}


node_pools = [
  {
    name      = "mem"
    cores     = 2
    size      = 0
    ip_offset = 230
    memory    = 8192
  },
  {
    name      = "compute"
    cores     = 2
    size      = 16
    ip_offset = 210
    memory    = 4096
  }
]
