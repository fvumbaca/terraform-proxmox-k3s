# How to Roll Node Pools

## Spin up New Nodes

```terraform
// ....
    // This is the old node pool:
    {
      name = "original"
      size = 2
      subnet = "192.168.0.208/28" # 14 ips
    },
    // Add the new updated nodepool like below:
    {
      name = "new-pool"
      size = 2
      subnet = "192.168.0.224/28" # 14 ips
      // You probably want to set this to change the template from the old one
      // that is being used on the original node pool.
      template = "new-proxmox-node-template"
    },
// ...
```

Once you have made your changes, you will need to run `terraform apply`. Note
that this change should be purely additive.

> On a constrained system, you might only be able to spin up 1 node from the
new nodepool. This is OK, but you might need to revisit this step to shrink the
original pool and grow the new pool to fully roll all your workloads over.

If everything was applied correctly, you should now see the node(s) from the
new pool we just added available in the cluster:

```sh
kubectl get nodes
```

## Cordon Old Nodes

To begin moving workloads over, first cordon all of the nodes from the original
node pool.

```sh
# Note that you will need to change the regex to match nodes from your original node pool
kubectl get nodes | grep -o "k3s-original-." | xargs kubectl cordon
```

Just to validate, check that only the old nodes have the status of `SchedulingDisabled`.

```sh
kubectl get nodes
```

Now any restarted workloads will no longer start on the original node pool.

## Test New Nodes (Optional)

If it is important to minimize all possible downtime for the workloads on your
cluster, you may want to run a canary deployment to make sure workloads being
moved over will not instantly crash. For homelabs, this is not usually a
concern and this step can be skipped. It is always easy to revert the change
with a call to `kubectl uncordon`.

## Restart Workloads

At this point, we need to move workloads over to the new nodes. Depending on
your system, some may have already started moving over. The best way to
__drain__ nodes completely is to __evict__ workloads with `kubectl drain`:

> **NOTE:** This will delete all the data from workloads not configured with
persistent volumes. If you are not sure if your workloads are configured
correctly, do not continue.

```sh
# Don't forget to update the regex with your original pool name!
kubectl get nodes | grep -o "k3s-original-." | xargs \
  kubectl drain --ignore-errors --ignore-daemonsets --delete-emptydir-data
```

> At the time of writing this document, running the `kubectl drain` command
without `--ignore-errors` is a deprecated behaviour in favor of ignoring by
default. This will ensure that the command will not exit early if one of the
first nodes encounters an error when draining.

At this point, all your workloads (except for daemon sets since they by design
run on every node all the time) should be moved over to your new node pool. A
measure I like to take (on smaller clusters), just to be 100% sure is to list
all the pods and visually inspect to make sure we don't have any stragglers.

```sh
kubectl get pods -A -o wide
```

Note that its okay to have some pods still on the drained nodes - just make
sure they are the pods from a deamon set.

## Destroy Old Nodes

Once we are happy with the state of the rollover, we are finally able to
destroy the old node pool and the nodes that make it up. To do that, just
delete the node pool from the list in your terraform file and then run the good
old:

```sh
terraform apply
```

The deleted nodes might still be showing up in `kubectl` with a status of
`NotReady`. If this is the case, clean them up with:

```sh
# Don't forget to update the regex with your original pool name!
kubectl get nodes | grep -o "k3s-original-." | xargs kubectl delete node
# Sometimes this command hangs for a while waiting for the api to clean up.
# Skip the waiting with Ctrl + C once all the nodes have been logged as deleted
```

Congrats! You have now successfully rolled your cluster's nodes!

