#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ────────────────────────────────────────────────────────────
# Вспомогательные функции
# ────────────────────────────────────────────────────────────

generate_password() {
    local length="${1:-32}"
    openssl rand -base64 "$((length * 2))" | tr -dc 'a-zA-Z0-9' | head -c "$length"
}

prompt_value() {
    local prompt_text="$1"
    local var_name="$2"
    local is_secret="${3:-true}"
    local value=""

    if [ "$is_secret" = true ]; then
        read -r -s -p "$prompt_text: " value
        echo
    else
        read -r -p "$prompt_text: " value
    fi

    printf -v "$var_name" '%s' "$value"
}

prompt_password_or_generate() {
    local label="$1"
    local length="$2"
    local var_name="$3"
    local choice

    echo
    echo "== $label =="
    echo "1) Ввести свой пароль"
    echo "2) Сгенерировать автоматически"
    read -r -p "Выбор [1/2]: " choice

    case "$choice" in
        1)
            prompt_value "Введите пароль для $label" "$var_name" true
            ;;
        2)
            printf -v "$var_name" '%s' "$(generate_password "$length")"
            echo "Сгенерирован пароль для $label (см. итоговый вывод в конце)."
            ;;
        *)
            echo "Неверный выбор, использую автогенерацию."
            printf -v "$var_name" '%s' "$(generate_password "$length")"
            ;;
    esac
}

create_namespace() {
    local ns="$1"
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
}

# ────────────────────────────────────────────────────────────
# 1. kubeadm init
# ────────────────────────────────────────────────────────────

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

# ────────────────────────────────────────────────────────────
# 2. Argo CD
# ────────────────────────────────────────────────────────────

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

# ────────────────────────────────────────────────────────────
# 3. Секреты (интерактивно)
# ────────────────────────────────────────────────────────────

echo
echo "==================================================="
echo " Настройка секретов кластера"
echo "==================================================="

# --- cert-manager / Cloudflare ---

create_namespace cert-manager

echo
echo "== Cloudflare API Token (для DNS-01 challenge) =="
prompt_value "Введите Cloudflare API Token" CLOUDFLARE_API_TOKEN true

kubectl create secret generic cloudflare-api-token \
    -n cert-manager \
    --from-literal=api-token="${CLOUDFLARE_API_TOKEN}" \
    --dry-run=client -o yaml | kubectl apply -f -

# --- monitoring / Grafana ---

create_namespace monitoring

prompt_password_or_generate "Grafana admin password" 128 GRAFANA_ADMIN_PASSWORD

kubectl create secret generic grafana-admin-credentials \
    -n monitoring \
    --from-literal=admin-user=kr-admin \
    --from-literal=admin-password="${GRAFANA_ADMIN_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -

# --- S3 storage / MinIO ---

create_namespace minio

prompt_password_or_generate "MinIO root password" 128 MINIO_ROOT_PASSWORD

kubectl create secret generic minio-credentials \
    -n minio \
    --from-literal=rootUser=kr-admin \
    --from-literal=rootPassword="${MINIO_ROOT_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -

# ────────────────────────────────────────────────────────────
# 4. Root App
# ────────────────────────────────────────────────────────────

echo "== Apply root-app =="

kubectl apply -f "$SCRIPT_DIR/root-app.yaml"

# ────────────────────────────────────────────────────────────
# 5. kr-server / MinIO app credentials
# ────────────────────────────────────────────────────────────

echo
echo "== Waiting for MinIO to be ready =="

kubectl wait --for=condition=Available deployment/minio -n minio --timeout=300s

MINIO_ROOT_USER=$(kubectl get secret minio-credentials -n minio -o jsonpath='{.data.rootUser}' | base64 -d)
MINIO_ROOT_PASSWORD=$(kubectl get secret minio-credentials -n minio -o jsonpath='{.data.rootPassword}' | base64 -d)

echo "== Creating kr-server MinIO app user =="

KR_SERVER_MINIO_PASSWORD=$(generate_password 64)

kubectl exec -n minio deploy/minio -- \
    mc alias set local http://localhost:9000 "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}"

kubectl exec -n minio deploy/minio -- \
    mc admin user add local kr-server-app "${KR_SERVER_MINIO_PASSWORD}"

kubectl exec -n minio deploy/minio -- \
    mc admin policy attach local readwrite --user kr-server-app

create_namespace kr

kubectl create secret generic minio-app-credentials \
    -n kr \
    --from-literal=endpoint=http://minio.minio.svc.cluster.local:9000 \
    --from-literal=access-key=kr-server-app \
    --from-literal=secret-key="${KR_SERVER_MINIO_PASSWORD}" \
    --from-literal=bucket=kr-uploads \
    --dry-run=client -o yaml | kubectl apply -f -

# ────────────────────────────────────────────────────────────
# Итог
# ────────────────────────────────────────────────────────────

ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
    -n argocd \
    -o jsonpath="{.data.password}" | base64 -d)

echo
echo "==================================================="
echo " Готово. Сохраните эти данные:"
echo "==================================================="
echo "ArgoCD admin password:      ${ARGOCD_PASSWORD}"
echo "Grafana kr-admin password:  ${GRAFANA_ADMIN_PASSWORD}"
echo "MinIO kr-admin password:    ${MINIO_ROOT_PASSWORD}"
echo "==================================================="