# Proxmox/K3s Example

This is an example project for setting up your own K3s cluster at home.

## Requirements

This requires Terraform 1.30+.

## Summary

### VMs

This will spin up:

- 1 support vm with api loadbalancer and k3s database with 2 cores and 4Gb mem
- 2 master nodes with 2 cores and 4Gb mem
- 1 node pool with 20 worker nodes each having 2 cores and 4Gb mem

### Networking

- The support VM will be spun up on `192.168.42.200`
- The master VMs will be spun up on `192.168.42.201`, `192.168.42.202`
- The worker VMs will be spun up on `192.168.42.205...214`

> Note: To eliminate potential IP clashing with existing computers on your
network, it is **STRONGLY** recommended that  you take IPs
`192.168.42.200-214` out of your DHCP server's rotation. Otherwise
other computers in your network may already be using these IPs and
that will create conflicts!

Check your router's manual or google it for a step-by-step guide.

## Usage

To run this example, make sure you `cd` to this directory in your terminal,
then
1. Copy your public key to the `authorized_keys` variable in
   `terraform.tfvars`. In most cases, you
   should be able to get this key by running
   `cat ~/.ssh/id_rsa.pub > authorized_keys`.
2. Make sure SSH agent is running so that the key can be used to
   authenticate to your VMs:  
   ```bash
   eval `ssh-agent`
   ssh-add ~/.ssh/id_rsa
   ```
2. Find your Proxmox API. It should look something like
   `https://192.168.0.25:8006/api2/json`. Once you found it, set the
   values to the env vars: `PM_API_URL`, `PM_API_TOKEN_ID` and
   `PM_API_TOKEN_SECRET`.
3. Run `terraform init` (only needs to be done the first time)
4. Run `terraform apply`
5. Review the plan. Make sure it is doing what you expect!
6. Enter `yes` in the prompt and wait for your cluster to spin up.
7. Retrieve your kubecontext by running
   `terraform output -raw kubeconfig > config.yaml`
8. Make all your `kubectl` commands work with your cluster for your terminal
   session by running `export KUBECONFIG="config.yaml"`. If you want to add the
   context more perminantly globaly, [refer to the document on managing Kubernetes configs](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/#create-a-second-configuration-file).

