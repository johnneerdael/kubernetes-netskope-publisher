---
title: Pod vs host network
date: 2026-05-18
---

The chart can run the Publisher in two networking modes. **`pod` is
the default since chart v1.1.0**. `host` is still available for
clusters that rely on the legacy host-networking layout.

## Mode comparison

|  | `networking.mode: host` | `networking.mode: pod` |
|---|---|---|
| `hostNetwork` | `true` | `false` |
| Owns | host's network namespace | pod's network namespace |
| `dnsPolicy` | `ClusterFirstWithHostNet` | `ClusterFirst` |
| Iptables modifications | on the host | inside the pod |
| Reach cluster services | via host network | via cluster DNS / kube-proxy |
| Survives node reboot | yes | yes |
| Works with PSA `restricted` | no — `hostNetwork: true` blocked | partial — still needs `privileged: true` |
| Multi-replica per node | no (single host netns) | yes |

## Pod mode values

```yaml
networking:
  mode: pod
  disableIPv6: true       # disable v6 in the pod netns before tun0 setup

tunDevice:
  enabled: true
  hostPath: /dev/net/tun
  mountPath: /dev/net/tun

hostNetwork: false
dnsPolicy: ClusterFirst
```

The `tunDevice` mount is critical — the pod's tun0 interface needs the
host's `/dev/net/tun` exposed as a hostPath. Without it the Publisher
fails on startup with `cannot open /dev/net/tun`.

## Host mode values

```yaml
networking:
  mode: host

hostNetwork: true
dnsPolicy: ClusterFirstWithHostNet
```

Use this when the cluster is k3s/single-node and host networking is
acceptable, or when you have legacy installs to maintain.

## Picking

- New EKS/AKS/GKE/OpenShift deployment → **pod**
- k3s, kind, bare-metal single-node → **either; host is simplest**
- Cluster with strict PSA enforcement → **pod** (still need `privileged`
  exemption — see [distributions](/kubernetes-netskope-publisher/admin/chart/distributions/))
