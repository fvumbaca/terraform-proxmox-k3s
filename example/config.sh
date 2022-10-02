#!/bin/bash
mkdir -p ~/.kube
chmod go-rwx ~/.kube
terraform output -raw kubeconfig > ~/.kube/config
chmod go-rwx ~/.kube/config
