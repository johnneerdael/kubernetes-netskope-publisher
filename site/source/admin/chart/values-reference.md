---
title: Values reference
date: 2026-05-18
---

Every notable key in `values.yaml`, grouped by topic. Defaults are shown
in parentheses.

## Image

| Key | Default | Notes |
|---|---|---|
| `image.repository` | `netskopeprivateaccess/publisher_u22` | Ubuntu 22 Publisher image. |
| `image.tag` | `latest` | Pin a specific build for production. |
| `image.pullPolicy` | `IfNotPresent` | Use `Always` if you reuse the `latest` tag. |
| `imagePullSecrets` | `[]` | List of secret names for private registries. |

## Workload

| Key | Default | Notes |
|---|---|---|
| `workload.type` | `daemonset` | `daemonset` or `statefulset`. See [workload modes](/kubernetes-netskope-publisher/admin/concepts/workload-modes/). |
| `workload.replicas` | `1` | StatefulSet only. |

## Autoscaling

| Key | Default | Notes |
|---|---|---|
| `hpa.enabled` | `false` | Renders an `HorizontalPodAutoscaler` for the StatefulSet. Ignored for DaemonSets. |
| `hpa.minReplicas` | `2` |  |
| `hpa.maxReplicas` | `6` |  |
| `hpa.targetCPUUtilizationPercentage` | `70` | Scale up when average CPU exceeds this. |
| `hpa.behavior` | `{}` | Optional autoscaling/v2 `behavior` block (scale-up / scale-down policies). |

See [autoscaling](/kubernetes-netskope-publisher/admin/how-to/autoscaling/)
for the full setup.

## Enrollment

| Key | Default | Notes |
|---|---|---|
| `enrollment.mode` | `api` | `api` (recommended) or `token`. |
| `enrollment.commonName` | `npa-publisher` | Name shown in the Netskope console. |
| `enrollment.api.baseUrl` | `https://tenant.goskope.com` | Tenant URL, no trailing slash. |
| `enrollment.api.existingSecret` | `npa-api-token` | Secret containing the API token. |
| `enrollment.api.tokenKey` | `api-token` | Key within that secret. |
| `enrollment.api.cleanupOnDelete` | `true` | Delete the tenant-side Publisher record on pod termination via preStop hook. Best-effort. |
| `registrationToken.value` | `""` | `mode: token` only — pass via `--set`. |
| `registrationToken.existingSecret` | `""` | Alternative to inline value. |

## Networking

| Key | Default | Notes |
|---|---|---|
| `networking.mode` | `pod` | `pod` (default, recommended) or `host` (legacy). |
| `networking.disableIPv6` | `true` | Only when `mode: pod`. Disables IPv6 in the pod netns. |
| `tunDevice.enabled` | `true` | Mount `/dev/net/tun` from the node. |
| `tunDevice.hostPath` | `/dev/net/tun` |  |
| `tunDevice.mountPath` | `/dev/net/tun` |  |

`hostNetwork`, `dnsPolicy`, and the container `securityContext` are
**not configurable via values** — they're derived from `networking.mode`.
See the [pod vs host network](/kubernetes-netskope-publisher/admin/how-to/pod-vs-host-network/)
comparison table for what each mode renders.

## Persistence

| Key | Default | Notes |
|---|---|---|
| `persistence.enabled` | `false` | Set `true` for `mode: token` HA. |
| `persistence.storageClass` | `""` | Empty = cluster default. |
| `persistence.size` | `10Gi` |  |
| `persistence.existingClaim` | `""` | Reuse an existing PVC. |

## DNS forwarders

| Key | Default | Notes |
|---|---|---|
| `bind.forwarders` | `[]` | List of upstream resolvers for the in-pod BIND9. Auto-discovers from resolv.conf when empty. |

## Proxy

| Key | Default | Notes |
|---|---|---|
| `proxy.enabled` | `false` |  |
| `proxy.httpProxy` | `""` |  |
| `proxy.httpsProxy` | `""` |  |
| `proxy.noProxy` | `""` |  |

## Publisher behaviour

| Key | Default | Notes |
|---|---|---|
| `publisher.logLevel` | `3` | 0=trace, 1=debug, 2=info, 3=warn, 4=error, 5=critical. |
| `publisher.hostOsType` | `ubuntu` | Hint passed to the agent. |
| `publisher.discoveryRefresh` | `true` | Refresh app discovery periodically. |

## Resources, probes, pod plumbing

| Key | Default |
|---|---|
| `resources.requests.cpu` | `500m` |
| `resources.requests.memory` | `1024Mi` |
| `resources.limits.cpu` | `1000m` |
| `resources.limits.memory` | `1536Mi` |
| `terminationGracePeriodSeconds` | `30` |
| `nodeSelector` / `tolerations` / `affinity` | `{}` / `[]` / `{}` |
| `serviceAccount.create` | `false` (uses the namespace `default` SA) |

Health probes are hardcoded in the DaemonSet/StatefulSet template (exec
probes that verify the publisher process plus its on-disk state) and
are not parameterisable today.

## Custom settings

Provide a `settings.json` override via ConfigMap:

```yaml
customSettings:
  enabled: true
  configMapName: my-publisher-settings
```

The ConfigMap key `settings.json` is mounted over the image default.
