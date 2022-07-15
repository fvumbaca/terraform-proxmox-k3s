pm_api_url = "https://...:8006/api2/json"
pm_api_token_id = "..."
pm_api_token_secret = "..."

ciuser = "terraform"

vm_defaults = {
  cores = 2
  nameserver = "10.41.0.1"
  searchdomain = "terraform.lab"
  target_node = "ve2"
  target_pool = "k8s"
  image_id = "template-cloudinit-ubuntu2104"
  full_clone = false
  firewall = false
  disk_size = "20G"
  memory = 2048
  balloon = 2048
  storage_id = "zfs"
  subnet = "10.41.0.0/16"
  gw = "10.41.0.1"
  network_bridge = "vmbr1"
  network_tag = 2000
  # put your authorized_keys content below this line, before the end-of-file marker
  authorized_keys = <<EOF
    ssh-rsa AAAA...LRf0= key1
    EOF
}
