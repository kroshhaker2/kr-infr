#!/bin/bash
set -e

echo "== kubeadm init =="
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo "== Allow scheduling on control-plane =="
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

echo "== Install Flannel =="
kubectl apply -f "$(dirname "$0")/flannel.yaml"

echo "== Waiting for node Ready =="
kubectl wait --for=condition=Ready node --all --timeout=120s

echo "== Install ArgoCD =="
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f "$(dirname "$0")/argocd-install.yaml"

echo "== Waiting for ArgoCD =="
kubectl wait --for=condition=Available deployment --all -n argocd --timeout=300s

echo "== Apply root-app =="
kubectl apply -f "$(dirname "$0")/root-app.yaml"

echo "== Done. Get ArgoCD admin password: =="
kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
echo