# kr-infr

Infrastructure for deploying **Kr** on Kubernetes using **~~Ansible~~, Argo CD and Helm**.

## Deployment

### 1. Fork the repository

It is highly recommended to make a fork of this repository before deployment.

Then replace the repository URL in Argo CD manifests:

```bash
sed -i 's|repoURL: https://github.com/kroshhaker2/kr-infr.git|repoURL: https://github.com/NEW-OWNER/kr-infr.git|' k8s-manifests/argocd-apps/*.yaml
```

Replace `NEW-OWNER` with your GitHub username or organization.

### 2. Configure your domain

Several `values.yaml` files contain the default domain `kr.kroshhaker.dev`. Replace it with your own domain before deployment.

For example:

```yaml
ingress:
  host: kr.example.com
  tlsSecretName: kr-web-tls
  clusterIssuer: letsencrypt-prod
```

Search for all occurrences of the default domain:

```bash
grep -R "kr.kroshhaker.dev" k8s-manifests/
```

Replace them with your domain, for example:

```bash
sed -i 's/kr\.kroshhaker\.dev/kr\.example\.com/g' k8s-manifests/*/values.yaml
```

Make sure the required DNS records point to your Kubernetes ingress before deploying, otherwise Let's Encrypt certificates and external access will not work.

### 3. Prepare a clean host

The current setup requires a clean Linux host with:

- SSH access
- `sudo` access
- Internet access

Before running the bootstrap script, manually install and configure:

- Kubernetes
- Helm
- `kubectl`

The bootstrap script handles the remaining deployment and configuration steps.

### 4. Run bootstrap

Clone your fork and run:

```bash
git clone https://github.com/NEW-OWNER/kr-infr.git
cd kr-infr

./bootstrap/bootstrap.sh
```

The bootstrap process installs and configures the required Kubernetes components and Argo CD.

### 5. Argo CD

After bootstrap, Argo CD synchronizes the applications from this repository.

The following components are deployed automatically:

- ingress-nginx
- cert-manager
- CloudNativePG
- PostgreSQL
- Headlamp
- Prometheus/Grafana monitoring
- Kr Server
- Kr Web

Application versions are managed through Git and updated by CI. Container images use explicit versions instead of `latest`.

### 6. Check the cluster

```bash
kubectl get pods -A
kubectl get applications -n argocd
```

For Headlamp access, use:

```bash
./scripts/headlamp-get-token.sh
```

## Repository structure

```text
bootstrap/          # Initial host/Kubernetes setup
k8s-manifests/
├── argocd/         # Argo CD configuration
├── argocd-apps/    # Argo CD Applications
├── cert-manager/
├── cnpg-operator/
├── headlamp/
├── ingress-nginx/
├── kr-postgres/
├── kr-server/      # Helm chart
├── kr-web/         # Helm chart
└── monitoring/
scripts/            # Utility scripts
```

## GitOps

After the initial bootstrap, Kubernetes resources are managed declaratively through **Argo CD**.

CI builds versioned container images and updates the corresponding Helm values. Argo CD detects the Git changes and deploys the new version automatically.
