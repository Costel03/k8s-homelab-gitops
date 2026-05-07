# MetalLB

[![App Status](https://argocd.local/api/badge?name=metallb&revision=true)](https://argocd.local/applications/metallb)
![MetalLB](https://img.shields.io/badge/MetalLB-L2_Mode-0078D4?logo=kubernetes&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-1.35-326CE5?logo=kubernetes&logoColor=white)

Bare-metal LoadBalancer implementation for the homelab cluster. MetalLB assigns real IP addresses from a local pool to Kubernetes `LoadBalancer` services, enabling them to be reached directly from the Windows host without NodePort hacks.

---

## Architecture

```
  Windows Host (192.168.56.1)
         │
         │  host-only network (eth1)
         │
  ┌──────┴────────────────────────────────────────────────────┐
  │  MetalLB L2 Mode — announces IPs via ARP on eth1          │
  │                                                           │
  │  IP Pool: 192.168.56.20 – 192.168.56.40                  │
  │                                                           │
  │   .20  ArgoCD         .22  nginx-ingress                  │
  │   .21  Grafana        .23  nginx-ingress-zot              │
  └───────────────────────────────────────────────────────────┘
```

MetalLB runs in **L2 mode**: when a `LoadBalancer` service requests an IP, the MetalLB speaker on the node that owns that IP responds to ARP requests from the host network, making the IP reachable directly.

---

## Service Details

| Property | Value |
|---|---|
| Namespace | `metallb-system` |
| Mode | L2 (ARP) |
| Interface | `eth1` (VirtualBox host-only adapter) |
| IP Pool | `192.168.56.20` – `192.168.56.40` |
| Helm chart | `metallb/metallb 0.14.9` |

---

## IP Assignments

| IP | Service |
|---|---|
| `192.168.56.20` | ArgoCD (`argocd-server`) |
| `192.168.56.21` | Grafana |
| `192.168.56.22` | nginx-ingress (routes `vault.local`) |
| `192.168.56.23` | nginx-ingress-zot (routes `zot.local`) |

To assign a specific IP, add this annotation to the service:
```yaml
metallb.universe.tf/loadBalancerIPs: "192.168.56.XX"
```

---

## Directory Structure

```
metallb/
└── helm/
    └── metallb/
        ├── Chart.yaml                  # Umbrella chart (metallb/metallb)
        ├── values.yaml                 # Controller + speaker resource limits
        └── templates/
            ├── ipaddresspool.yaml      # IP range 192.168.56.20–.40
            └── l2advertisement.yaml    # L2 mode, bound to eth1
```

---

## Configuration

**IPAddressPool** (`templates/ipaddresspool.yaml`)
```yaml
addresses:
  - 192.168.56.20-192.168.56.40
```

**L2Advertisement** (`templates/l2advertisement.yaml`)
```yaml
interfaces:
  - eth1
```

Binding to `eth1` is critical — it prevents MetalLB from announcing IPs on the NAT interface (`eth0`) which would conflict with VirtualBox routing.

---

## Troubleshooting

**LoadBalancer service stuck in `<pending>`**
```bash
# Check MetalLB speaker logs
kubectl logs -n metallb-system -l component=speaker

# Verify IPAddressPool exists
kubectl get ipaddresspools -n metallb-system

# Verify L2Advertisement exists
kubectl get l2advertisements -n metallb-system
```

**IP reachable from WSL but not from Windows host**
```bash
# Verify eth1 has the right subnet
ip addr show eth1   # should be 192.168.56.x/24

# On Windows, check arp cache
arp -a | findstr "192.168.56"
```

**Wrong interface — IPs announced on eth0 (NAT)**
> Ensure `l2advertisement.yaml` has `interfaces: [eth1]`.
> After fixing, restart MetalLB speakers:
```bash
kubectl rollout restart daemonset -n metallb-system metallb-speaker
```
