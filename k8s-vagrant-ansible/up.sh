#!/bin/bash
#
# up.sh — Run entirely from WSL.
#         Creates VMs, configures SSH, runs Ansible, fetches kubeconfig.
#
# Usage:
#   ./up.sh            # bring up cluster
#   vagrant.exe halt   # suspend VMs
#   vagrant.exe up     # resume (no re-provisioning)
#   vagrant.exe destroy -f && ./up.sh   # full rebuild

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAGRANT_MACHINES="$SCRIPT_DIR/.vagrant/machines"
SSH_DIR="$HOME/.ssh"
KUBE_DIR="$HOME/.kube"

NODES=("k8s-master" "k8s-worker1" "k8s-worker2")
IPS=("192.168.56.10" "192.168.56.11" "192.168.56.12")

mkdir -p "$SSH_DIR" "$KUBE_DIR"

# ── 1. Bring up VMs via Windows Vagrant ──────────────────────────────
echo "==> Bringing up VMs..."
cd "$SCRIPT_DIR"
vagrant.exe up

# ── 2. Copy Vagrant SSH private keys to WSL ──────────────────────────
echo "==> Copying SSH keys..."
for vm in "${NODES[@]}"; do
    KEY_SRC="$VAGRANT_MACHINES/$vm/virtualbox/private_key"
    if [[ -f "$KEY_SRC" ]]; then
        # Copy to WSL home (not /mnt/c) so chmod 600 works on ext4, not NTFS
        install -m 600 "$KEY_SRC" "$SSH_DIR/$vm"
        echo "    $vm ✔"
    else
        echo "ERROR: key not found at $KEY_SRC"
        exit 1
    fi
done

# ── 3. Configure ~/.ssh/config ────────────────────────────────────────
echo "==> Configuring SSH aliases..."
MARKER_BEGIN="# --- k8s-vagrant-ansible BEGIN ---"
MARKER_END="# --- k8s-vagrant-ansible END ---"
touch "$SSH_DIR/config"
sed -i "/$MARKER_BEGIN/,/$MARKER_END/d" "$SSH_DIR/config"

{
    echo "$MARKER_BEGIN"
    for i in "${!NODES[@]}"; do
        cat <<EOF
Host ${NODES[$i]}
    HostName ${IPS[$i]}
    User vagrant
    IdentityFile ${SSH_DIR}/${NODES[$i]}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR

EOF
    done
    echo "$MARKER_END"
} >> "$SSH_DIR/config"

chmod 600 "$SSH_DIR/config"

# Clean stale host fingerprints
for ip in "${IPS[@]}"; do
    ssh-keygen -f "$SSH_DIR/known_hosts" -R "$ip" 2>/dev/null || true
done

# ── 4. Wait for SSH on all nodes ──────────────────────────────────────
echo "==> Waiting for SSH to be ready..."
for i in "${!NODES[@]}"; do
    ip="${IPS[$i]}"
    printf "    %s (%s) " "${NODES[$i]}" "$ip"
    for _ in {1..30}; do
        if nc -z "$ip" 22 2>/dev/null; then
            echo "✔"
            break
        fi
        sleep 3
    done
done

# ── 5. Run Ansible playbook ───────────────────────────────────────────
echo "==> Running Ansible playbook..."
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook \
    -i "$SCRIPT_DIR/ansible-ubuntu/inventory.ini" \
    "$SCRIPT_DIR/ansible-ubuntu/playbook.yml"

echo ""
echo "==> Cluster is ready!"
echo "    kubectl get nodes"
