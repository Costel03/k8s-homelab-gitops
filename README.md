# k8s-homelab-gitops

![Kubernetes](https://img.shields.io/badge/Kubernetes-1.35-326CE5?logo=kubernetes&logoColor=white)
![ArgoCD](https://img.shields.io/badge/ArgoCD-App--of--Apps-EF7B4D?logo=argo&logoColor=white)
![Vault](https://img.shields.io/badge/HashiCorp_Vault-1.16-FFCF25?logo=vault&logoColor=black)
![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04_LTS-E95420?logo=ubuntu&logoColor=white)
![Vagrant](https://img.shields.io/badge/Vagrant-VirtualBox-1563FF?logo=vagrant&logoColor=white)

Full GitOps homelab: 3-node Kubernetes cluster on VirtualBox VMs, fully automated from VM creation to running services. One script rebuilds everything from scratch.

---

## Architecture

```
  Windows Host (VirtualBox + Vagrant)
  ┌──────────────────────────────────────────────────────────────┐
  │  Host-only network: 192.168.56.0/24                          │
  │                                                              │
  │  k8s-master   192.168.56.10   2 CPUs  /  2 GB               │
  │  k8s-worker1  192.168.56.11   8 CPUs  / 12 GB               │
  │  k8s-worker2  192.168.56.12   8 CPUs  / 12 GB               │
  │                                                              │
  │  MetalLB L2 pool: 192.168.56.20 – 192.168.56.40             │
  │    .20  ArgoCD          .22  nginx-ingress (vault)           │
  │    .21  Grafana         .23  nginx-ingress-zot (zot)         │
  └──────────────────────────────────────────────────────────────┘

  Git Repo (this repo)
       │  watches
       ▼
  ┌──────────────────────────────────────────────────────────────┐
  │  ArgoCD — App-of-Apps                                        │
  │                                                              │
  │  ┌─────────┐  ┌─────┐  ┌───────┐  ┌──────────┐  ┌──────┐  │
  │  │  Vault  │  │ ESO │  │MetalLB│  │  nginx   │  │ NFS  │  │
  │  └─────────┘  └─────┘  └───────┘  └──────────┘  └──────┘  │
  │  ┌──────────────────┐   ┌──────────────────────────────────┐ │
  │  │  Monitoring      │   │  Container Registry (Zot)        │ │
  │  │  Prometheus+Loki │   │  OCI — 192.168.56.23             │ │
  │  │  +Grafana        │   └──────────────────────────────────┘ │
  │  └──────────────────┘                                        │
  └──────────────────────────────────────────────────────────────┘

  Secrets flow:
    generate-certs.sh  →  Vault (KV v2)  →  ESO  →  K8s Secrets
```

---

## Stack

| Component | Technology | Version |
|---|---|---|
| OS | Ubuntu 24.04 LTS (Noble) | — |
| Container runtime | containerd.io | latest |
| Kubernetes | kubeadm / kubelet / kubectl | 1.35.x |
| CNI | Calico | 3.29.1 |
| GitOps | ArgoCD | latest helm |
| Secrets store | HashiCorp Vault | 0.29.1 chart |
| Secrets bridge | External Secrets Operator | latest |
| Load balancer | MetalLB | L2 mode |
| Ingress | NGINX Ingress Controller | 4.12.1 |
| Storage | NFS subdir provisioner | nfs-client SC |
| Monitoring | Prometheus + Loki + Grafana | latest |
| Registry | Zot (OCI) | latest |

---

## Prerequisites

| Tool | Where |
|---|---|
| VirtualBox | Windows |
| Vagrant | Windows (`vagrant.exe` on PATH) |
| WSL2 + Ubuntu | Windows |
| `kubectl`, `helm`, `jq`, `openssl` | WSL |
| Ansible | WSL (`pip install ansible`) |

### Base box (one-time setup)

All VMs are cloned from a custom `k8s-base` box that pre-bakes containerd, Kubernetes binaries, and pre-pulled `kubeadm` images. Build it once from PowerShell:

```powershell
cd C:\Users\iacob\Documents\repos\k8s-homelab-gitops\k8s-vagrant-ansible\base-box
vagrant.exe up --provision
vagrant.exe package --output k8s-base.box
vagrant.exe box add k8s-base k8s-base.box
vagrant.exe destroy -f
```

---

## Quick Start — Full Rebuild

From **WSL**, at the repo root:

```bash
# Fresh build (VMs do not exist yet)
./rebuild.sh

# Destroy existing VMs and rebuild from scratch
./rebuild.sh --destroy
```

`rebuild.sh` runs everything end-to-end:

| Step | What happens |
|---|---|
| 1 | `vagrant.exe up` — creates 3 VMs from the base box |
| 2 | SSH keys copied to WSL; `~/.ssh/config` configured |
| 3 | Ansible provisions the cluster (kubeadm init, Calico, NFS server, worker join) |
| 4 | `kubeconfig` fetched to `~/.kube/config` |
| 5 | ArgoCD installed via Helm |
| 6 | App-of-Apps applied — ArgoCD deploys all services |
| 7 | Vault initialized and unsealed; `~/vault-init.json` saved |
| 8 | `vault-token` + `vault-unseal-key` K8s secrets created |
| 9 | `generate-certs.sh` creates CA + TLS certs and stores them in Vault |
| 10 | CA cert trusted in WSL |
| 11 | ExternalSecrets force-synced |
| 12 | Waits up to 20 min for all ArgoCD apps to reach `Healthy` |

### After rebuild — Windows setup

**1. Hosts file** — add to `C:\Windows\System32\drivers\etc\hosts` (Notepad as Administrator):

```
192.168.56.20  argocd.local
192.168.56.21  grafana.local
192.168.56.22  vault.local
192.168.56.23  zot.local
```

**2. Trust the CA cert** — PowerShell as Administrator (path printed by `rebuild.sh`):

```powershell
Import-Certificate -FilePath 'C:\Users\iacob\homelab-ca.crt' `
  -CertStoreLocation 'Cert:\LocalMachine\Root'
```

---

## Services

| Service | URL | LoadBalancer IP | Credentials |
|---|---|---|---|
| ArgoCD | https://argocd.local | `192.168.56.20` | Vault: `argocd` engine, `admin` secret |
| Grafana | https://grafana.local | `192.168.56.21` | Vault: `argocd` engine, `admin` secret |
| Vault | https://vault.local | `192.168.56.22` | root token in `~/vault-init.json` |
| Zot Registry | https://zot.local | `192.168.56.23` | anonymous pull / push |

---

## Repository Structure

```
k8s-homelab-gitops/
│
├── rebuild.sh                        # One-shot full cluster rebuild
│
├── k8s-vagrant-ansible/              # VM provisioning
│   ├── up.sh                         # VMs + SSH + Ansible + kubeconfig
│   ├── Vagrantfile                   # 3-node cluster definition
│   ├── base-box/Vagrantfile          # Base image builder
│   └── ansible-ubuntu/               # Ansible roles: common / master / worker
│
├── argocd/                           # ArgoCD Helm values + bootstrap
│   ├── generate-certs.sh             # CA + TLS cert generation → Vault
│   ├── bootstrap/app-of-apps.yaml    # Root ArgoCD Application
│   ├── external-secrets/             # ExternalSecrets for ArgoCD
│   └── helm/argocd/values.yaml
│
├── apps/                             # ArgoCD Application manifests (app-of-apps)
│   ├── argocd/application.yaml
│   ├── container-registry/
│   ├── ExternalSecretsOperator/
│   ├── hashicorp-vault/
│   ├── metallb/
│   ├── monitoring/
│   ├── nfs/
│   └── nginx-ingress/
│
├── hashicorp-vault/                  # Vault Helm chart + auto-unseal Deployment
├── external-secrets-operator/        # ESO Helm chart + ClusterSecretStore
├── metallb/                          # MetalLB Helm chart + IPAddressPool
├── nginx-ingress/                    # Two NGINX controllers (main + zot)
├── nfs/                              # NFS provisioner (nfs-client StorageClass)
├── monitoring/                       # Prometheus + Loki + Grafana
└── container-registry/               # Zot OCI registry
```

---

## Day-2 Operations

### Cluster suspend / resume

```bash
# Suspend (saves VM state)
vagrant.exe halt

# Resume (no re-provisioning)
vagrant.exe up
```

After resume, Vault wakes sealed. The `vault-auto-unseal` Deployment handles this automatically within ~10 seconds.

### Manual Vault unseal (if needed)

```bash
kubectl exec -n hashicorp-vault hashicorp-vault-0 -- \
  vault operator unseal "$(jq -r '.unseal_keys_b64[0]' ~/vault-init.json)"
```

### Force ExternalSecrets re-sync

```bash
kubectl annotate externalsecret -A --all \
  force-sync="$(date +%s)" --overwrite
```

### Check ArgoCD app status

```bash
kubectl get applications -n argocd
```

---

## Security Notes

- `~/vault-init.json` contains the Vault root token and unseal key — **keep it safe and never commit it**.
- TLS certs are self-signed by a homelab CA. The CA cert must be trusted on any machine that accesses the services over HTTPS.
- All application passwords and TLS certs are stored exclusively in Vault; no secrets live in this Git repo.
