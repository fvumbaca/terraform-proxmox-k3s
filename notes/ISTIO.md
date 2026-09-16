# terraform-proxmox-k3s-multi-node

Here is a guide for running Istio and MetalLB on a Proxmox Kubernetes Cluster

## VERY IMPORTANT TO NOT INSTALL TRAEFIK OR SERVICELB DURING BOOTSTRAP!!!!!
```terraform
# Disable default traefik and servicelb installs for metallb and traefik 2
    k3s_disable_components = [
      "traefik",
      "servicelb"
    ]
```
## Sequence
1. MetalLB
2. Istio
3. Anything Else

## Guide