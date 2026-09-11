#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "== kubeadm init =="

sudo kubeadm init --pod-network-cidr=10.244.0.0/16

mkdir -p "$HOME/.kube"

sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

export KUBECONFIG="$HOME/.kube/config"

echo "== Allow scheduling on control-plane =="

kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

echo "== Install Flannel =="

kubectl apply -f "$SCRIPT_DIR/flannel.yaml"

echo "== Waiting for node Ready =="

kubectl wait --for=condition=Ready node --all --timeout=120s

echo "== Add Argo CD Helm repository =="

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

echo "== Install Argo CD =="

helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --create-namespace \
    --values "$SCRIPT_DIR/../k8s-manifests/argocd/values.yaml" \
    --wait \
    --timeout 10m

echo "== Waiting for ArgoCD =="

kubectl wait \
    --for=condition=Available \
    deployment \
    --all \
    -n argocd \
    --timeout=300s

echo "== Apply root-app =="

kubectl apply -f "$SCRIPT_DIR/root-app.yaml"

echo "== Done. Get ArgoCD admin password: =="

kubectl get secret argocd-initial-admin-secret \
    -n argocd \
    -o jsonpath="{.data.password}" | base64 -d

echo