#!/bin/bash
terraform state rm module.k3s.data.external.kubeconfig
terraform destroy