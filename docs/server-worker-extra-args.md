
###  Add the following to your main.tf and modify the extra arguements to your liking;   

####   Example arguements are commented out, these can either be removed, if they are not required, or uncommented if they are useful to you 


These additonal args are added to the server; 

   > For a complete list of all k3s server options, refer to the [k3s.io documentation](https://rancher.com/docs/k3s/latest/en/installation/install-options/server-config/).

```
// ....
  // These additonal args are added to the server -> [Server args ref]: (https://rancher.com/docs/k3s/latest/en/installation/install-options/agent-config/)
  
  k3s_extra_server_args = [
    #"--write-kubeconfig-mode 644",
    #"--kube-apiserver-arg default-not-ready-toleration-seconds=30",
    #"--kube-apiserver-arg default-unreachable-toleration-seconds=30",
    #"--kube-controller-arg node-monitor-period=20s",
    #"--kube-controller-arg node-monitor-grace-period=20s",
    #"--kubelet-arg node-status-update-frequency=5s",
    #"--debug",
    #"--oidc-issuer-url ",
    #"--oidc-client-id",
    #"--oidc-username-claim"
  ]
  
// ...
```

These additonal args are added to the worker;

   > For a complete list of all k3s worker/agent options, refer to the [k3s.io documentation](https://rancher.com/docs/k3s/latest/en/installation/install-options/agent-config/).

```
// ....
  k3s_extra_worker_args = [
    #"--kubelet-arg node-status-update-frequency=5s"
  ]

// ...
```
