#!/bin/bash
#
# install.sh — Install ArgoCD and apply the App-of-Apps.
#
# Run this from WSL after the cluster is up and kubectl works:
#   cd /mnt/c/Users/iacob/Documents/repos/ArgoCD
#   ./install.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing ArgoCD..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo update

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --values "$SCRIPT_DIR/helm/argocd/values.yaml" \
  --wait --timeout 5m

echo "==> Waiting for ArgoCD Application CRD to be established..."
kubectl wait --for=condition=Established crd/applications.argoproj.io --timeout=60s

echo "==> Applying App-of-Apps..."
kubectl apply -f "$SCRIPT_DIR/bootstrap/app-of-apps.yaml"

echo ""
echo "Done. ArgoCD will now sync all applications automatically."
echo ""
echo "Next steps:"
echo "  1. Init + unseal Vault:"
echo "     kubectl exec -n hashicorp-vault hashicorp-vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json | tee ~/vault-init.json"
echo "     kubectl exec -n hashicorp-vault hashicorp-vault-0 -- vault operator unseal \$(jq -r '.unseal_keys_b64[0]' ~/vault-init.json)"
echo ""
echo "  2. Create ESO vault-token secret:"
echo "     kubectl create secret generic vault-token --namespace eso --from-literal=token=\$(jq -r '.root_token' ~/vault-init.json)"
echo ""
echo "  3. Populate Vault with certs + passwords (Vault is ClusterIP — use port-forward):"
echo "     kubectl port-forward -n hashicorp-vault svc/hashicorp-vault 8200:8200 &"
echo "     export VAULT_ADDR=http://127.0.0.1:8200"
echo "     export VAULT_TOKEN=\$(jq -r '.root_token' ~/vault-init.json)"
echo "     \$(dirname \$0)/generate-certs.sh"
echo ""
echo "  4. Force ExternalSecrets sync:"
echo "     kubectl annotate externalsecret -A --all force-sync=\$(date +%s) --overwrite"
echo ""
echo "ArgoCD initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" 2>/dev/null | base64 -d && echo || echo "  (secret already deleted — use the password you set in generate-certs.sh)"
