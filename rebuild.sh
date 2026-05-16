#!/bin/bash
#
# rebuild.sh — Full homelab cluster rebuild from WSL.
#
# Runs entirely from WSL. Requires: vagrant.exe, kubectl, helm, jq, openssl.
#
# Usage:
#   ./rebuild.sh               # fresh build (VMs must not already exist)
#   ./rebuild.sh --destroy     # destroy existing VMs first, then full rebuild
#   ./rebuild.sh --skip-ansible  # skip VM/Ansible, go straight to ArgoCD bootstrap
#
# Optional env vars (skip interactive password prompts):
#   export ARGOCD_ADMIN_PASSWORD=yourpassword
#   export GRAFANA_ADMIN_PASSWORD=yourpassword
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESTROY=false
SKIP_ANSIBLE=false

for arg in "$@"; do
  [[ "$arg" == "--destroy" ]]      && DESTROY=true
  [[ "$arg" == "--skip-ansible" ]] && SKIP_ANSIBLE=true
done

# ── 0. Optionally destroy existing VMs ──────────────────────────────────────
if $DESTROY; then
  echo "==> Destroying existing VMs..."
  (cd "$SCRIPT_DIR/k8s-vagrant-ansible" && vagrant.exe destroy -f)
fi

# ── 1. Bring up cluster (VMs + Ansible + kubeconfig) ────────────────────────
if $SKIP_ANSIBLE; then
  echo "==> Skipping VM/Ansible (--skip-ansible passed)."
else
  bash "$SCRIPT_DIR/k8s-vagrant-ansible/up.sh"
fi

# ── 2. Install ArgoCD ────────────────────────────────────────────────────────
echo "==> Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo update

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --values "$SCRIPT_DIR/argocd/helm/argocd/values.yaml" \
  --wait --timeout 5m

kubectl wait --for=condition=Established \
  crd/applications.argoproj.io --timeout=60s

echo "==> Waiting for ArgoCD server to be ready..."
kubectl wait deployment/argocd-server \
  --namespace argocd \
  --for=condition=Available \
  --timeout=120s

echo "==> Waiting for ArgoCD application-controller to be ready..."
kubectl wait statefulset/argocd-application-controller \
  --namespace argocd \
  --for=jsonpath='{.status.readyReplicas}'=1 \
  --timeout=120s

# ── 3. Apply App-of-Apps ─────────────────────────────────────────────────────
# Clear the full kubectl cache (not just discovery) to force fresh REST mapper.
echo "==> Applying App-of-Apps..."
for i in $(seq 1 30); do
  rm -rf ~/.kube/cache/
  kubectl apply -f "$SCRIPT_DIR/argocd/bootstrap/app-of-apps.yaml" && break
  printf "  [%d/30] not ready yet, retrying in 10s...\n" "$i"
  sleep 10
done
echo "    ArgoCD is now syncing all applications automatically."

# ── 4. Wait for Vault pod ────────────────────────────────────────────────────
echo "==> Waiting for Vault pod to be created by ArgoCD..."
for i in $(seq 1 60); do
  kubectl get pod hashicorp-vault-0 -n hashicorp-vault &>/dev/null && break
  printf "  [%d/60] not yet — waiting 10s...\n" "$i"
  sleep 10
done
kubectl wait pod/hashicorp-vault-0 -n hashicorp-vault \
  --for=condition=Ready --timeout=300s
echo "    Vault pod is Ready."

# ── 5. Initialize Vault ──────────────────────────────────────────────────────
echo "==> Initializing Vault..."
INITIALIZED=$(kubectl exec -n hashicorp-vault hashicorp-vault-0 -- \
  vault status -format=json 2>/dev/null | jq -r '.initialized' || echo "false")

if [ "$INITIALIZED" != "true" ]; then
  kubectl exec -n hashicorp-vault hashicorp-vault-0 -- \
    vault operator init -key-shares=1 -key-threshold=1 -format=json \
    | tee ~/vault-init.json
  chmod 600 ~/vault-init.json
  echo "    Vault initialized — ~/vault-init.json saved."
else
  echo "    Vault already initialized."
  if [ ! -f ~/vault-init.json ]; then
    echo "ERROR: Vault is initialized but ~/vault-init.json is missing." >&2
    echo "       Recover root token + unseal key and save to ~/vault-init.json manually." >&2
    exit 1
  fi
fi

# ── 6. Unseal Vault ──────────────────────────────────────────────────────────
echo "==> Unsealing Vault..."
SEALED=$(kubectl exec -n hashicorp-vault hashicorp-vault-0 -- \
  vault status -format=json 2>/dev/null | jq -r '.sealed' || echo "true")
if [ "$SEALED" = "true" ]; then
  kubectl exec -n hashicorp-vault hashicorp-vault-0 -- \
    vault operator unseal "$(jq -r '.unseal_keys_b64[0]' ~/vault-init.json)"
  echo "    Vault unsealed."
else
  echo "    Vault already unsealed."
fi

# ── 7. Create vault-token + vault-unseal-key Kubernetes secrets ──────────────
echo "==> Creating Kubernetes secrets..."
ROOT_TOKEN=$(jq -r '.root_token'         ~/vault-init.json)
UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' ~/vault-init.json)

kubectl create namespace eso --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic vault-token \
  --namespace eso \
  --from-literal=token="$ROOT_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic vault-unseal-key \
  --namespace hashicorp-vault \
  --from-literal=key="$UNSEAL_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "    vault-token (eso) + vault-unseal-key (hashicorp-vault) created."

# ── 8. Generate certs + populate Vault ──────────────────────────────────────
echo "==> Generating certs and populating Vault (via port-forward)..."
kubectl port-forward -n hashicorp-vault svc/hashicorp-vault 8200:8200 &
PF_PID=$!
sleep 4

export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN="$ROOT_TOKEN"

bash "$SCRIPT_DIR/argocd/generate-certs.sh"

kill "$PF_PID" 2>/dev/null || true

# ── 9. Trust CA cert in WSL ─────────────────────────────────────────────────
if [ -f ~/homelab-ca.crt ]; then
  echo "==> Trusting CA cert in WSL..."
  sudo cp ~/homelab-ca.crt /usr/local/share/ca-certificates/homelab-ca.crt
  sudo update-ca-certificates
fi

# ── 10. Force ExternalSecrets sync ──────────────────────────────────────────
echo "==> Forcing ExternalSecrets sync..."
sleep 15
kubectl annotate externalsecret -A --all \
  force-sync="$(date +%s)" --overwrite 2>/dev/null || true
echo "    Done."

# ── 11. Wait for all ArgoCD apps to be Healthy ──────────────────────────────
echo "==> Waiting for all ArgoCD applications to be Healthy (up to 20 min)..."
for i in $(seq 1 80); do
  NOT_HEALTHY=$(kubectl get applications -n argocd \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.health.status}{"\n"}{end}' \
    | grep -v " Healthy" | grep -v "^$" || true)

  if [ -z "$NOT_HEALTHY" ]; then
    echo "    All applications are Healthy!"
    break
  fi

  if [ "$i" -eq 80 ]; then
    echo "WARNING: Timeout reached. Still unhealthy:"
    echo "$NOT_HEALTHY"
  else
    NAMES=$(echo "$NOT_HEALTHY" | awk '{print $1}' | tr '\n' ' ')
    printf "  [%d/80] waiting for: %s\n" "$i" "$NAMES"
    sleep 15
  fi
done

echo ""
kubectl get applications -n argocd

# ── Summary ──────────────────────────────────────────────────────────────────
WIN_CA=$(wslpath -w ~/homelab-ca.crt 2>/dev/null || echo "~/homelab-ca.crt")

echo ""
echo "════════════════════════════════════════════════════"
echo "  Cluster Rebuild Complete!"
echo "════════════════════════════════════════════════════"
echo ""
echo "  ArgoCD:  https://argocd.local   (192.168.56.20)"
echo "  Grafana: https://grafana.local  (192.168.56.21)"
echo "  Vault:   https://vault.local    (192.168.56.22)"
echo "  Zot:     https://zot.local      (192.168.56.23)"
echo ""
echo "  1. Add to C:\\Windows\\System32\\drivers\\etc\\hosts (notepad as Admin):"
echo "       192.168.56.20  argocd.local"
echo "       192.168.56.21  grafana.local"
echo "       192.168.56.22  vault.local"
echo "       192.168.56.23  zot.local"
echo ""
echo "  2. Trust CA cert — PowerShell as Administrator:"
echo "       Import-Certificate -FilePath '$WIN_CA' \\"
echo "         -CertStoreLocation 'Cert:\\LocalMachine\\Root'"
echo ""
echo "  Vault init data saved to: ~/vault-init.json  (keep this safe!)"
echo "════════════════════════════════════════════════════"
