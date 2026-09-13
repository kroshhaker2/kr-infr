#!/bin/bash

set -euo pipefail

NAMESPACE="kube-system"
SA_NAME="headlamp-full-access"
SECRET_NAME="${SA_NAME}-token"

echo "== Creating ServiceAccount ${SA_NAME} =="

kubectl create serviceaccount "${SA_NAME}" -n "${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "== Creating ClusterRoleBinding (cluster-admin) =="

cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${SA_NAME}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: ${SA_NAME}
    namespace: ${NAMESPACE}
EOF

echo "== Creating long-lived token Secret =="

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/service-account.name: ${SA_NAME}
type: kubernetes.io/service-account-token
EOF

echo "== Waiting for token to populate =="

for i in $(seq 1 10); do
    TOKEN=$(kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || true)
    if [ -n "${TOKEN}" ]; then
        break
    fi
    sleep 1
done

if [ -z "${TOKEN}" ]; then
    echo "Не удалось получить токен — секрет ещё не заполнен. Попробуйте:"
    echo "  kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o jsonpath='{.data.token}' | base64 -d"
    exit 1
fi

echo
echo "==================================================="
echo " Headlamp full-access token (cluster-admin)"
echo "==================================================="
echo "${TOKEN}"
echo "==================================================="
echo
echo "Вставьте этот токен в форму входа Headlamp."