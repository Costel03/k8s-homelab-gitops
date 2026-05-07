# Kubernetes Cluster with Vagrant & Ansible

Deploy a 3-node Kubernetes cluster on VirtualBox VMs using Vagrant for provisioning and Ansible for configuration. Designed for a **Windows + WSL** workflow.

## Cluster Overview

| Node | IP | Resources |
|---|---|---|
| k8s-master | 192.168.56.10 | 2 GB RAM, 2 CPUs |
| k8s-worker1 | 192.168.56.11 | 6 GB RAM, 4 CPUs |
| k8s-worker2 | 192.168.56.12 | 6 GB RAM, 4 CPUs |

**Stack:** Ubuntu 24.04 (Noble), Kubernetes v1.35.x, Containerd, Calico v3.29.1

## Prerequisites

- [VirtualBox](https://www.virtualbox.org/) installed on Windows
- [Vagrant](https://www.vagrantup.com/) installed on Windows
- WSL2 with Ubuntu
- Ansible installed in WSL (`pip install ansible` or `apt install ansible`)

## Base Box

All VMs are built from a custom `k8s-base` box (`base-box/Vagrantfile`) that pre-bakes:
- containerd.io + Docker/K8s apt repos
- kubelet, kubeadm, kubectl (v1.35)
- chrony, nfs-common, iptables-legacy
- Pre-pulled `kubeadm config images`

Build the base box once (PowerShell):
```powershell
cd C:\Users\iacob\Documents\repos\k8s-vagrant-ansible
vagrant.exe up --provision  # inside base-box/
vagrant.exe package --output k8s-base.box
vagrant.exe box add k8s-base k8s-base.box
```

## Quick Start

From **WSL**:
```bash
cd /mnt/c/Users/iacob/Documents/repos/k8s-vagrant-ansible
bash up.sh
```

`up.sh` will:
1. Start VMs with `vagrant.exe up` (from Windows)
2. Copy SSH keys to WSL home (correct permissions)
3. Run the Ansible playbook

When finished:
```bash
kubectl get nodes
```

## What Ansible Does

| Step | Scope | Description |
|---|---|---|
| 1 | All nodes | Disable swap + comment fstab entry |
| 2 | All nodes | Load kernel modules (`overlay`, `br_netfilter`) |
| 3 | All nodes | Apply sysctl networking parameters |
| 4 | All nodes | Wipe containerd state (clean linked-clone) |
| 5 | All nodes | Install nfs-common |
| 6 | Master | Install wait-for-eth1 systemd service |
| 7 | Master | Initialize control plane with `kubeadm init` |
| 8 | Master | Install Calico CNI |
| 9 | Master | Set up NFS server (`/share` → 192.168.56.0/24) |
| 10 | Workers | Join the cluster |

## After Cluster is Up — Bootstrap ArgoCD

```bash
cd /mnt/c/Users/iacob/Documents/repos/ArgoCD
bash install.sh
```

## After Every Restart — Unseal Vault

Vault keys are in-memory only and must be unsealed after each pod restart:
```bash
kubectl exec -n hashicorp-vault hashicorp-vault-0 -- \
  vault operator unseal $(jq -r '.unseal_keys_b64[0]' ~/vault-init.json)
```

ArgoCD will resync all ExternalSecrets automatically once Vault is unsealed.

Or install the auto-unseal Deployment (after creating the Secret):
```bash
kubectl create secret generic vault-unseal-key \
  --from-literal=key=$(jq -r '.unseal_keys_b64[0]' ~/vault-init.json) \
  -n hashicorp-vault
```

## Service Access

Add to `C:\Windows\System32\drivers\etc\hosts` (as Administrator):
```
192.168.56.20  argocd.local
192.168.56.21  grafana.local
192.168.56.22  vault.local
192.168.56.23  zot.local
```

| Service | URL | Notes |
|---|---|---|
| ArgoCD | https://argocd.local | admin / from Vault argocd/admin |
| Grafana | https://grafana.local | admin / from Vault argocd/grafana |
| Vault | https://vault.local | root token in ~/vault-init.json |
| Zot registry | https://zot.local | docker push/pull |

## Troubleshooting

### Swap re-enabled after VM stop/start
```bash
ssh k8s-master "sudo swapoff -a && sudo sed -i '/swap/s/^[^#]/#&/' /etc/fstab"
ssh k8s-worker1 "sudo swapoff -a && sudo sed -i '/swap/s/^[^#]/#&/' /etc/fstab"
ssh k8s-worker2 "sudo swapoff -a && sudo sed -i '/swap/s/^[^#]/#&/' /etc/fstab"
```

### etcd slow / API server timing out
Compact etcd from inside the running container:
```bash
ssh k8s-master "
  CTR=\$(sudo crictl ps | grep ' etcd ' | awk '{print \$1}')
  REV=\$(sudo crictl exec \$CTR etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    endpoint status --write-out=json | python3 -c 'import sys,json; print(json.load(sys.stdin)[0][\"Status\"][\"header\"][\"revision\"])')
  sudo crictl exec \$CTR etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    compact \$REV && defrag && alarm disarm
"
```

### Destroy and rebuild from scratch
```powershell
# PowerShell
cd C:\Users\iacob\Documents\repos\k8s-vagrant-ansible
vagrant.exe destroy -f
vagrant.exe up
```
```bash
# WSL
bash up.sh
```

## Project Structure

```
.
├── Vagrantfile                    # VM definitions
├── up.sh                          # Full deployment script (WSL)
├── base-box/
│   └── Vagrantfile                # Builds k8s-base box (packages pre-baked)
└── ansible-ubuntu/
    ├── inventory.ini
    ├── playbook.yml
    ├── group_vars/all.yml
    └── roles/
        ├── common/tasks/main.yml  # Swap, modules, containerd wipe, nfs-common
        ├── master/tasks/main.yml  # wait-for-eth1, kubeadm init, Calico, NFS server
        └── worker/tasks/main.yml  # kubeadm join
```


**Stack:** Ubuntu 22.04 (Jammy), Kubernetes v1.35.2, Containerd 1.7.23, Calico v3.29.1

## Prerequisites

- [VirtualBox](https://www.virtualbox.org/) installed on Windows
- [Vagrant](https://www.vagrantup.com/) installed on Windows
- WSL2 with Ubuntu (or similar)
- Ansible installed in WSL (`pip install ansible` or `apt install ansible`)

Install the required Vagrant plugin (once, from PowerShell):
```powershell
vagrant plugin install vagrant-hostmanager
```

## Quick Start (automated)

Run everything with a single script from **WSL**:

```bash
cd /mnt/c/Users/iacob/Documents/repos/k8s-vagrant-ansible
chmod +x start-cluster.sh setup-access.sh
bash start-cluster.sh
```

This script will:
1. Create the VMs with `vagrant up`
2. Copy SSH keys & configure SSH aliases (`setup-access.sh`)
3. Wait for all nodes to be reachable
4. Run the Ansible playbook to deploy Kubernetes
5. Fetch the kubeconfig to `~/.kube/config`

When it finishes you can immediately run:
```bash
kubectl get nodes
```

## Step-by-Step (manual)

### 1. Create the VMs (PowerShell)

```powershell
# PowerShell
cd C:\Users\iacob\Documents\repos\k8s-vagrant-ansible
vagrant up
```

Then unseal Vault (always required after restart):

```bash
kubectl exec -n hashicorp-vault vault-0 -- vault operator unseal <key-1>
kubectl exec -n hashicorp-vault vault-0 -- vault operator unseal <key-2>
kubectl exec -n hashicorp-vault vault-0 -- vault operator unseal <key-3>
```

ArgoCD will automatically resync all other apps once Vault is unsealed and ESO recovers.

### Destroy and recreate cluster from scratch

```powershell
# PowerShell
cd C:\Users\iacob\Documents\repos\k8s-vagrant-ansible
vagrant destroy -f
vagrant up
```

```bash
# WSL
./bootstrap-cluster.sh
# Then repeat Steps 3–4 (init/unseal Vault, recreate vault-token secret)
```

### Get ArgoCD admin password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

### Check all application health

```bash
kubectl get applications -n argocd
```

### View all LoadBalancer IPs

```bash
kubectl get svc -A | grep LoadBalancer
```

---

## What the Ansible Playbook Does

| Step | Scope | Description |
|---|---|---|
| 1 | All nodes | Disable swap |
| 2 | All nodes | Load kernel modules (`overlay`, `br_netfilter`) |
| 3 | All nodes | Apply sysctl networking parameters |
| 4 | All nodes | Install Containerd 1.7.23 with SystemdCgroup |
| 5 | All nodes | Add Kubernetes v1.35 apt repository |
| 6 | All nodes | Install kubelet, kubeadm, kubectl |
| 7 | Master | Initialize control plane with `kubeadm init` |
| 8 | Master | Install Calico CNI |
| 9 | Workers | Join the cluster using `kubeadm join` |

## Project Structure

```
.
├── Vagrantfile              # VM definitions (k8s-master, k8s-worker1, k8s-worker2)
├── start-cluster.sh         # One-command full deployment (WSL)
├── setup-access.sh          # Copy SSH keys, configure aliases, fetch kubeconfig
├── ansible-ubuntu/
│   ├── inventory.ini        # Ansible host inventory
│   ├── playbook.yml         # Main playbook
│   ├── group_vars/
│   │   └── all.yml          # Kubernetes version variable
│   └── roles/
│       ├── common/tasks/    # Shared setup (containerd, k8s packages)
│       ├── master/tasks/    # Control plane init, Calico, join token
│       └── worker/tasks/    # Join cluster, copy kubeconfig
```

## Troubleshooting

### Reset the cluster
SSH into the master and reset:
```bash
ssh k8s-master
sudo kubeadm reset -f
sudo rm -rf /etc/kubernetes/* /var/lib/etcd /var/lib/kubelet/* /root/.kube
sudo reboot
```
Then re-run the Ansible playbook.

### Destroy and rebuild from scratch
```powershell
# PowerShell
vagrant destroy -f
vagrant up
```
```bash
# WSL
bash start-cluster.sh
```

### Stale Vagrant state after renaming VMs
If you see errors about old machine names, remove leftover state:
```bash
rm -rf /mnt/c/Users/iacob/Documents/repos/k8s-vagrant-ansible/.vagrant/machines/<old-name>
```

### Label worker nodes
```bash
kubectl label node k8s-worker1 node-role.kubernetes.io/worker=worker
kubectl label node k8s-worker2 node-role.kubernetes.io/worker=worker
```