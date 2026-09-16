# MetalLB for Ingress

This module no longer ships an nginx ingress load balancer. Ingress (HTTP/HTTPS) is
handled in-cluster by **MetalLB** in L2 mode, which announces its own VIP for
`LoadBalancer` services. This is independent of the keepalived API VIP.

## 1. Install MetalLB

```sh
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/manifests/metallb-native.yaml
```

Wait for the pods to be ready:

```sh
kubectl -n metallb-system wait --for=condition=Ready pod -l app=metallb --timeout=120s
```

## 2. Configure an L2 address pool

Pick a range of IPs **outside** your DHCP range and not used by any node. Create
`metallb-config.yaml`:

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: ingress
  namespace: metallb-system
spec:
  addresses:
    - 10.10.3.1-10.10.3.10   # your ingress VIP range
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: ingress
  namespace: metallb-system
spec:
  ipAddressPools:
    - ingress
```

```sh
kubectl apply -f metallb-config.yaml
```

## 3. Point your ingress controller at it

Install Traefik (or nginx ingress) with `service.type: LoadBalancer`. MetalLB will
assign an IP from the pool:

```sh
kubectl -n kube-system get svc traefik
# traefik   LoadBalancer   <cluster-ip>   10.10.3.1   80:...,443:...
```

Point your DNS wildcard (`*.apps.yourdomain.tld`) at `10.10.3.1`.

## Notes

- MetalLB L2 mode ties the VIP to a single node per service (failover on node
  loss). For multi-node ECMP you need BGP mode with a capable router.
- The module's `k3s_disable_components = ["traefik", "servicelb"]` is required so
  MetalLB and Traefik can be managed cleanly.
- MetalLB's VIP range must not overlap the control-plane, worker, or keepalived VIP
  ranges.
