#!/bin/bash
KUBECONFIG=`mktemp`
terraform output -raw kubeconfig > ${KUBECONFIG}

KUBE_SERVER=`kubectl --kubeconfig ${KUBECONFIG} config view -o json --raw | jq -c -r '.clusters[0].cluster.server'`
KUBE_CLUSTER=${1-"NEW-CLUSTER"}
KUBE_CONTEXT=${2-"NEW-CONTEXT"}

KUBE_CA_DATA=`kubectl --kubeconfig ${KUBECONFIG} config view -o json --raw | jq -c -r '.clusters[0].cluster."certificate-authority-data"'`
CLIENT_CERT_DATA=`kubectl --kubeconfig ${KUBECONFIG} config view -o json --raw | jq -c -r '.users[0].user."client-certificate-data"'`
CLIENT_KEY_DATA=`kubectl --kubeconfig ${KUBECONFIG} config view -o json --raw | jq -c -r '.users[0].user."client-key-data"'`

cat <<EOM
# Use below outputs to connect to this cluster from your device. The output should work across platforms, just copy & paste into your shell.

kubectl config set-context ${KUBE_CONTEXT}
kubectl config set-context ${KUBE_CONTEXT} --user ${KUBE_CONTEXT}-admin --cluster ${KUBE_CLUSTER}
kubectl config set clusters.${KUBE_CLUSTER}.insecure-skip-tls-verify true
kubectl config set clusters.${KUBE_CLUSTER}.server ${KUBE_SERVER}
kubectl config set users.${KUBE_CONTEXT}-admin.client-certificate-data "${CLIENT_CERT_DATA}"
kubectl config set users.${KUBE_CONTEXT}-admin.client-key-data "${CLIENT_KEY_DATA}"
kubectl config use-context ${KUBE_CONTEXT}
EOM