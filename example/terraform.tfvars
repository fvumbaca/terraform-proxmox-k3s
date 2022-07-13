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
    ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDAQKzUKoLlnmONhr0X5Nd99r6M96VbKysVVrgKVlaADVWSTNJxoaZY4U1BIHXvXpWrTWQLzuKz1JOkroMI1xZCbjR2fv7wWbRqcALadINCRs5fE8oTA/ZQsar82NUzMGHxNtlrhaRhiHf4JLzAdBQoPQaIHPYROpqT2ygABoDhBtP7HzsAA5ul9hVkGz2eM/j5NguvgTMzU/mGwlnLXGDaihGmY0eQLvxpergvDeczxjb2yYBMVm9execfT8Y8TxitivQzZZxwM/hlF/y9ggfBb3XRMbdOog/fwQlLmCn0ffMXZapAIieLKgF6LLljvZz8c+8Wl2ybZcWnOMUN/r/1bn0coLVe6exUK9ygMyqKl2tFqY3ITuuV3Pkk0cBtzvypGYPhdiPdf5701zZMgyDtO3hzk5cjJXx10CfuvwTsPLkLqCzu7HJjW2s+1FL3stk7VYw4e9MGr+Z46mBH+lWGn4RNQmDvhR3ChdVNb1HgslM5dN9VWqtfyO4XVI+LRf0= key1
    ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDrjFvRQUJcdHCBvSdt9ZuuJLsexex4wgMjYpiMYYYD+wFOHutHAtHuUMk+Orl3cozscqjiZYU6u+RdR3eOkiYeoUBzZadTWs1Qn8ZgMe6IB02jv/nVkgO89JHhLtR1NXHisGg0DBsWKiHDNQAUm3/5IOzeU6T6/orNv7vpycnHeWB/yiRR042NjrW4fKWdF34tD8ENUaRGCjcsgqW2MbtsYGxgwlpfyyxJOD5dAqkBaABsuq8u4Lt6HsP2nxuf+WB9A6vcM9YXKMhNRn0zhv+pDhXwzZ86wYGhvUeezqP4eH96cJSHur4aRR0HpSOUlXFmitPGH6eTslDKVBvmkbNl key2
    ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQChCMq+YmCII9JQAt1fTzjSMnQk439UF/vua5QvpKakwdzLO5aqWTdyfbCUGzggpwW8NDyrSLQ1FVyLoa85h0xJO49jchLzSLInZESyGgdv0cBA2kI/65b8icGjcTMHfzCloXRl1gax9FEyRuNKX6MlPVuk0DjBTDYWNso4Nbztw1RxN/H/I5VZ0LLtWX8iFpQc2RGLrmmtsT6Nv/I0UG4hvRcleabcMmOagJ+pU+/EIJQPUTcXMRNhjP4Pv/G6pm/ACeMbOvDzQgcteLXrDh88iFAS9ZSpfyYfVKXp8creS+2MCEutPWdqrhjTHFqRTfzeBfuYBwJkC7ix/IVtfZKoNPeNwUVEkv5Fch4DOkN7NL3TgtiJWDuh+YrfFJOd6gSCUWRU/TEIFukiyzzm9t4sv9wxFtmPYHBGZ+GoqZ+uY+qTrz6KniCA874Nj2hxl1/hFonl+cfUrU4gAmTc6c7zhZqFWELI2zA09hgQIKMAeuvAbXZl8Myq9bBZbtLi/R8= root@admin
    EOF
}
