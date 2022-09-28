#!/bin/bash
terraform output -raw kubeconfig > ~/.kube/config
