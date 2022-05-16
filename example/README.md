# Proxmox/K3s Example

This is an example project for setting up your own K3s cluster at home.

## Summary

### VMs

This will spin up:

- 1 support vm with api loadbalancer and k3s database with 2 cores and 4Gb mem
- 2 master nodes with 2 cores and 4Gb mem
- 1 node pool with 2 worker nodes each having 2 cores and 4Gb mem

### Networking

- The support VM will be spun up on `192.168.0.200`
- The master VMs will be spun up on `192.168.0.201` and `192.168.0.202`
- The worker VMs will be spun up on `192.168.0.208` and `192.168.0.209`

> Note: To eliminate potential IP clashing with existing computers on your
network, it is **STRONGLY** recommended that  you take IPs `192.168.0.200` -
`192.168.0.254` out of your DHCP server's rotation. Otherwise other computers
in your network may already be using these IPs and that will create conflicts!
Check your router's manual or google it for a step-by-step guide.

## Usage

To run this example, make sure you `cd` to this directory in your terminal,
then
1. Copy your public key to the `authorized_keys` file. In most cases, you
   should be able to do this by running
   `cat ~/.ssh/id_rsa.pub > authorized_keys`.
2. Find your Proxmox API. It should look something like
   `https://192.168.0.25:8006/api2/json`. Once you found it, update the value
   in the `main.tf` file marked as `TODO` in the `provider proxmox` section.
3. Authenticate to the proxmox API **for the current terminal session** by setting the two variables:
  ```
  # Update these to be your proxmox user/password.
  # Note that you usually need to keep the @pam at the end of the user.
  export PM_USER="terraform-prov@pve"
  export PM_PASS="password"
  ```

  > Find other ways to auth to proxmox by reading [the providor's docs](https://github.com/Telmate/terraform-provider-proxmox/blob/master/docs/index.md).
4. Run `terraform init` (only needs to be done the first time)
5. Run `terraform apply`
6. Review the plan. Make sure it is doing what you expect!
7. Enter `yes` in the prompt and wait for your cluster to spin up.
8. Retrieve your kubecontext by running
   `terraform output -raw kubeconfig > config.yaml`
9. Make all your `kubectl` commands work with your cluster for your terminal
   session by running `export KUBECONFIG="config.yaml"`. If you want to add the
   context more perminantly globaly, [refer to the document on managing Kubernetes configs](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/#create-a-second-configuration-file).

