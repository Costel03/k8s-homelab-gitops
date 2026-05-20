# k8s-homelab-gitops

![Kubernetes](https://img.shields.io/badge/Kubernetes-1.35-326CE5?logo=kubernetes&logoColor=white)
![Ubuntu](https://img.shields.io/badge/Ubuntu-26.04_LTS-E95420?logo=ubuntu&logoColor=white)
![Vagrant](https://img.shields.io/badge/Vagrant-VirtualBox-1563FF?logo=vagrant&logoColor=white)
![ArgoCD](https://img.shields.io/badge/ArgoCD-App--of--Apps-EF7B4D?logo=argo&logoColor=white)
![Vault](https://img.shields.io/badge/HashiCorp_Vault-1.21.2-FFCF25?logo=vault&logoColor=black)
![GitOps](https://img.shields.io/badge/GitOps-automated-brightgreen)

Full GitOps homelab: a 3-node Kubernetes cluster running on VirtualBox VMs, fully automated from VM creation to running services. A single script rebuilds the entire stack from scratch.

---

## Table of Contents

- [ArgoCD Application Status](#argocd-application-status)
- [Architecture](#architecture)
- [Stack](#stack)
- [Resource Budget](#resource-budget)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [What `rebuild.sh` Does](#what-rebuildsh-does)
- [After Rebuild — Windows Setup](#after-rebuild--windows-setup)
- [Services](#services)
- [Repository Structure](#repository-structure)
- [Day-2 Operations](#day-2-operations)
- [Security Notes](#security-notes)

---

## ArgoCD Application Status

> **Live status** — requires access to https://argocd.local from the host machine.

| Application | Sync | Health |
|---|---|---|
| app-of-apps | [![Sync](https://argocd.local/api/badge?name=app-of-apps&revision=true)](https://argocd.local/applications/app-of-apps) | — |
| argocd | [![Sync](https://argocd.local/api/badge?name=argocd&revision=true)](https://argocd.local/applications/argocd) | — |
| hashicorp-vault | [![Sync](https://argocd.local/api/badge?name=hashicorp-vault&revision=true)](https://argocd.local/applications/hashicorp-vault) | — |
| ExternalSecretsOperator | [![Sync](https://argocd.local/api/badge?name=ExternalSecretsOperator&revision=true)](https://argocd.local/applications/ExternalSecretsOperator) | — |
| metallb | [![Sync](https://argocd.local/api/badge?name=metallb&revision=true)](https://argocd.local/applications/metallb) | — |
| nginx-ingress | [![Sync](https://argocd.local/api/badge?name=nginx-ingress&revision=true)](https://argocd.local/applications/nginx-ingress) | — |
| nfs | [![Sync](https://argocd.local/api/badge?name=nfs&revision=true)](https://argocd.local/applications/nfs) | — |
| grafana | [![Sync](https://argocd.local/api/badge?name=grafana&revision=true)](https://argocd.local/applications/grafana) | — |
| prometheus | [![Sync](https://argocd.local/api/badge?name=prometheus&revision=true)](https://argocd.local/applications/prometheus) | — |
| loki | [![Sync](https://argocd.local/api/badge?name=loki&revision=true)](https://argocd.local/applications/loki) | — |
| container-registry | [![Sync](https://argocd.local/api/badge?name=container-registry&revision=true)](https://argocd.local/applications/container-registry) | — |

```bash
# Check all apps from the terminal
kubectl get applications -n argocd
```

---

## Architecture

```
  Windows Host (VirtualBox + Vagrant)
  ┌──────────────────────────────────────────────────────────────┐
  │  Host-only network: 192.168.56.0/24                          │
  │                                                              │
  │  k8s-master   192.168.56.10   3 CPUs /  4 GB  control-plane  │
  │  k8s-worker1  192.168.56.11   6 CPUs /  8 GB  worker         │
  │  k8s-worker2  192.168.56.12   6 CPUs /  8 GB  worker         │
  │  50 GB disk per node (VirtualBox VDI, linked clones)         │
  │                                                              │
  │  MetalLB L2 pool: 192.168.56.20 – 192.168.56.40              │
  │    .20  ArgoCD          .22  nginx-ingress (vault)           │
  │    .21  Grafana         .23  nginx-ingress-zot (zot)         │
  └──────────────────────────────────────────────────────────────┘

  Git Repo (this repo)  ←─── ArgoCD watches, auto-syncs on commit
       │
       ▼
  ┌──────────────────────────────────────────────────────────────┐
  │  ArgoCD  https://argocd.local  (App-of-Apps pattern)         │
  │                                                              │
  │  ┌──────────┐ ┌─────┐ ┌───────┐ ┌──────────┐ ┌──────────┐    │
  │  │  Vault   │ │ ESO │ │MetalLB│ │  NGINX   │ │   NFS    │    │
  │  └──────────┘ └─────┘ └───────┘ └──────────┘ └──────────┘    │
  │  ┌─────────────────────────┐  ┌───────────────────────────┐  │
  │  │  Monitoring             │  │  Container Registry (Zot) │  │
  │  │  Prometheus+Loki+Grafana│  │  OCI — 192.168.56.23      │  │
  │  └─────────────────────────┘  └───────────────────────────┘  │
  └──────────────────────────────────────────────────────────────┘

  Secrets flow:
    generate-certs.sh ──▶ Vault (KV v2) ──▶ ESO ──▶ K8s Secrets
```

---

## Stack

| Component | Technology | Version |
|---|---|---|
| OS | Ubuntu 26.04 LTS (Resolute), no GUI | — |
| Container runtime | containerd.io | 2.2.x |
| Kubernetes | kubeadm / kubelet / kubectl | 1.35.5 |
| CNI | Calico | 3.29.1 |
| GitOps | ArgoCD | argo/argo-cd (latest) |
| Secrets store | HashiCorp Vault | 1.21.2 (chart 0.32.0) |
| Secrets bridge | External Secrets Operator | v2.4.1 (chart 2.4.1) |
| Load balancer | MetalLB | v0.15.3 |
| Ingress | NGINX Ingress Controller | 1.15.1 (chart 4.15.1) |
| Storage | NFS subdir provisioner | 4.0.2 |
| Metrics | Prometheus | v3.11.3 |
| Logs | Loki | 3.6.7 |
| Dashboards | Grafana | 12.3.1 |
| Registry | Zot (OCI) | v2.1.16 (chart 0.1.112) |

---

## Resource Budget

Minimum resource requests and limits set across all deployed components:

| Component | CPU Request | Mem Request | CPU Limit | Mem Limit |
|---|---|---|---|---|
| ArgoCD server | 50m | 128Mi | 200m | 256Mi |
| ArgoCD controller | 50m | 128Mi | 200m | 256Mi |
| ArgoCD repoServer | 50m | 64Mi | 100m | 128Mi |
| ArgoCD applicationSet | 25m | 64Mi | 100m | 128Mi |
| ArgoCD redis | 25m | 64Mi | 100m | 128Mi |
| HashiCorp Vault | 50m | 256Mi | 200m | 512Mi |
| External Secrets Operator | 50m | 64Mi | 100m | 128Mi |
| ESO webhook | 25m | 32Mi | 100m | 64Mi |
| ESO certController | 25m | 32Mi | 100m | 64Mi |
| MetalLB controller | 25m | 32Mi | 100m | 64Mi |
| MetalLB speaker | 25m | 32Mi | 100m | 64Mi |
| NGINX Ingress | 50m | 64Mi | 200m | 128Mi |
| NFS provisioner | 25m | 32Mi | 100m | 64Mi |
| Grafana | 50m | 128Mi | 200m | 256Mi |
| Prometheus | 50m | 256Mi | 200m | 512Mi |
| Loki | 50m | 128Mi | 200m | 256Mi |
| Zot Registry | 50m | 64Mi | 200m | 256Mi |

> Vault's 256Mi memory request is a hard minimum — the Go runtime alone allocates ~200Mi before accepting traffic.

---

## Prerequisites

| Tool | Where | Notes |
|---|---|---|
| VirtualBox | Windows | — |
| Vagrant | Windows | `vagrant.exe` must be on PATH |
| WSL2 + Ubuntu | Windows | All commands run from here |
| `kubectl` | WSL | — |
| `helm` | WSL | v3+ |
| `jq` | WSL | — |
| `openssl` | WSL | — |
| `ansible` | WSL | `pip install ansible` |

### Base box — build once

All VMs are linked clones of a local `k8s-base` Vagrant box that pre-bakes containerd, Kubernetes binaries, and pre-pulled `kubeadm` images. Build it once from **WSL**:

```bash
cd k8s-vagrant-ansible
bash build-base-box.sh
```

> The base box survives `vagrant.exe destroy`. Only rebuild it when you want fresher packages baked in.

---

## Quick Start

### Option A — Full rebuild from scratch

```bash
# VMs do not exist yet
./rebuild.sh

# Destroy any existing VMs first, then rebuild
./rebuild.sh --destroy
```

### Option B — Cluster already up, bootstrap apps only

Use this when VMs are already provisioned (e.g. via `up.sh` + Ansible) and you only need to install ArgoCD and sync all applications:

```bash
# Step 1 — Bring up VMs and provision with Ansible
cd k8s-vagrant-ansible
bash up.sh

# Step 2 — Bootstrap ArgoCD, Vault, certs, and all apps
cd ..
./rebuild.sh --skip-ansible
```

`--skip-ansible` jumps straight to ArgoCD installation, skipping the Vagrant/Ansible phase.

---

## What `rebuild.sh` Does

| Step | Description |
|---|---|
| 0 | *(if `--destroy`)* Destroys all VMs |
| 1 | *(skipped with `--skip-ansible`)* Runs `up.sh` — VMs, SSH keys, Ansible, kubeconfig |
| 2 | Creates `argocd` namespace, installs ArgoCD via Helm |
| 3 | Applies `bootstrap/app-of-apps.yaml` — ArgoCD auto-syncs all apps |
| 4 | Waits for the Vault pod to become Ready |
| 5 | Initializes Vault (1-of-1 Shamir), saves keys to `~/vault-init.json` |
| 6 | Unseals Vault |
| 7 | Creates `vault-token` (eso ns) and `vault-unseal-key` (hashicorp-vault ns) secrets |
| 8 | Port-forwards Vault, runs `generate-certs.sh` — CA + TLS certs → Vault KV |
| 9 | Trusts the homelab CA in WSL |
| 10 | Force-syncs all ExternalSecrets |
| 11 | Waits up to 20 min for all ArgoCD apps to reach `Healthy` |
| 12 | Prints a summary with hosts file entries and the CA trust command |

---

## After Rebuild — Windows Setup

**1. Add to hosts file** — open `C:\Windows\System32\drivers\etc\hosts` as Administrator:

```
192.168.56.20  argocd.local
192.168.56.21  grafana.local
192.168.56.22  vault.local
192.168.56.23  zot.local
```

**2. Trust the CA cert** — PowerShell as Administrator (path is also printed by `rebuild.sh`):

```powershell
Import-Certificate -FilePath 'C:\Users\iacob\homelab-ca.crt' `
  -CertStoreLocation 'Cert:\LocalMachine\Root'
```

---

## Services

| Service | URL | LoadBalancer IP | Credentials |
|---|---|---|---|
| ArgoCD | https://argocd.local | `192.168.56.20` | Vault → `argocd` engine, `admin` secret |
| Grafana | https://grafana.local | `192.168.56.21` | Vault → `argocd` engine, `admin` secret |
| Vault | https://vault.local | `192.168.56.22` | Root token in `~/vault-init.json` |
| Zot Registry | https://zot.local | `192.168.56.23` | Anonymous pull / push |
| Prometheus | ClusterIP only | — | `kubectl port-forward svc/prometheus 9090` |
| Loki | ClusterIP only | — | `kubectl port-forward svc/loki 3100` |

---

## Repository Structure

```
k8s-homelab-gitops/
│
├── rebuild.sh                          # Full cluster rebuild (all-in-one)
│
├── k8s-vagrant-ansible/                # VM provisioning layer
│   ├── up.sh                           # Bring up VMs + Ansible + fetch kubeconfig
│   ├── build-base-box.sh               # Build the k8s-base Vagrant box (once)
│   ├── Vagrantfile                     # 3-node cluster definition
│   ├── base-box/Vagrantfile            # Base image provisioning
│   └── ansible-ubuntu/
│       ├── inventory.ini
│       ├── playbook.yml
│       └── roles/
│           ├── common/                 # All nodes: packages, containerd, sysctl
│           ├── master/                 # kubeadm init, Calico, NFS server
│           └── worker/                 # kubeadm join
│
├── argocd/                             # ArgoCD bootstrap
│   ├── generate-certs.sh               # CA + TLS certs → Vault
│   ├── bootstrap/app-of-apps.yaml      # Root Application (App-of-Apps)
│   ├── external-secrets/               # ExternalSecrets: admin password + TLS
│   └── helm/argocd/values.yaml         # Helm values (LoadBalancer .20)
│
├── apps/                               # ArgoCD Application manifests
│   ├── argocd/
│   ├── container-registry/
│   ├── ExternalSecretsOperator/
│   ├── hashicorp-vault/
│   ├── metallb/
│   ├── monitoring/
│   ├── nfs/
│   └── nginx-ingress/
│
├── hashicorp-vault/                    # Vault Helm chart + auto-unseal Deployment
├── external-secrets-operator/          # ESO Helm chart + ClusterSecretStore
├── metallb/                            # MetalLB + IPAddressPool + L2Advertisement
├── nginx-ingress/                      # Two NGINX controllers (.22 main, .23 zot)
├── nfs/                                # nfs-subdir-external-provisioner
├── monitoring/                         # Prometheus + Loki + Grafana
└── container-registry/                 # Zot OCI registry (50Gi NFS PVC)
```

---

## Day-2 Operations

### Cluster suspend / resume

```bash
# Suspend all VMs (saves state)
vagrant.exe halt

# Resume (no re-provisioning needed)
vagrant.exe up
```

After resume, Vault wakes sealed. The `vault-auto-unseal` Deployment handles this automatically within ~10 seconds.

### Manual Vault unseal

```bash
kubectl exec -n hashicorp-vault hashicorp-vault-0 -- \
  vault operator unseal "$(jq -r '.unseal_keys_b64[0]' ~/vault-init.json)"
```

### Force ExternalSecrets re-sync

```bash
kubectl annotate externalsecret -A --all \
  force-sync="$(date +%s)" --overwrite
```

### Re-run Ansible only (no VM rebuild)

```bash
cd k8s-vagrant-ansible
ansible-playbook -i ansible-ubuntu/inventory.ini ansible-ubuntu/playbook.yml
```

### Target a single node

```bash
ansible-playbook -i ansible-ubuntu/inventory.ini ansible-ubuntu/playbook.yml \
  --limit k8s-worker2
```

### Check cluster health

```bash
kubectl get nodes
kubectl get applications -n argocd
kubectl get pods -A
```

---

## Security Notes

- `~/vault-init.json` contains the Vault root token and unseal key — **keep it safe and never commit it**.
- TLS certificates are self-signed by a homelab CA. The CA cert must be trusted on any machine accessing the services over HTTPS.
- All application passwords and TLS certs are stored exclusively in Vault. No secrets live in this Git repo.
