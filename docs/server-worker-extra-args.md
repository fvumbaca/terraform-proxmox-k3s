
#  Add the following to you main.tf and modify the extra arguements to your liking;   

## args are added to the k3s server and worker nodes

```additional args
// ....
  // These additonal args are added to the server:
  k3s_extra_server_args = [
    "--write-kubeconfig-mode 644",
    "--kube-apiserver-arg default-not-ready-toleration-seconds=30",
    "--kube-apiserver-arg default-unreachable-toleration-seconds=30",
    "--kube-controller-arg node-monitor-period=20s",
    "--kube-controller-arg node-monitor-grace-period=20s",
    "--kubelet-arg node-status-update-frequency=5s",
    #"--debug",
    #"--oidc-issuer-url ",
    #"--oidc-client-id",
    #"--oidc-username-claim"
  ]

  // These additonal args are added to the worker:
  k3s_extra_worker_args = [
    "--kubelet-arg node-status-update-frequency=5s"
  ]
// ...
```
