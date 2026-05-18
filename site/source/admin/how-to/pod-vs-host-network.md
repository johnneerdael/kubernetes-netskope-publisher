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

> Since chart 1.2.0, `hostNetwork`, `dnsPolicy`, and the container
> `securityContext` are derived from `networking.mode` and are no
> longer settable in values. Flipping the mode is the only knob.

## Pod mode values

```yaml
networking:
  mode: pod              # (default — can be omitted)
  disableIPv6: true      # disable v6 in the pod netns before tun0 setup

tunDevice:
  enabled: true
  hostPath: /dev/net/tun
  mountPath: /dev/net/tun
```

The `tunDevice` mount is critical — the pod's tun0 interface needs the
host's `/dev/net/tun` exposed as a hostPath. Without it the Publisher
fails on startup with `cannot open /dev/net/tun`.

The chart automatically renders `hostNetwork: false`, `dnsPolicy:
ClusterFirst`, and a minimal `securityContext` (`privileged: false`,
`NET_ADMIN`, `NET_RAW`, `runAsUser: 0`).

## Host mode values

```yaml
networking:
  mode: host
```

Use this on k3s/single-node clusters where host networking is
acceptable, or for legacy installs you're maintaining.

The chart automatically renders `hostNetwork: true`, `dnsPolicy:
ClusterFirstWithHostNet`, and a privileged `securityContext`
(`privileged: true`, `allowPrivilegeEscalation: true`, `NET_ADMIN`,
`NET_RAW`, `runAsUser: 0`).

## Picking

- New EKS/AKS/GKE/OpenShift deployment → **pod**
- k3s, kind, bare-metal single-node → **either; host is simplest**
- Cluster with strict PSA enforcement → **pod** (still need `privileged`
  exemption — see [distributions](/kubernetes-netskope-publisher/admin/chart/distributions/))
