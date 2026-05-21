# Rootless lwIP Setup

> Internal note: this file is intentionally stored outside `site/source/`.
> Hexo builds GitHub Pages content from `site/source/`, so this document is not published unless it is moved or linked into that tree.

## Scope

Use rootless lwIP mode when the Publisher must run without a kernel TUN device and without Linux network capabilities such as `NET_ADMIN` and `NET_RAW`.

This mode uses the lwIP userspace data plane and the test Publisher image:

```yaml
networking:
  mode: lwip

lwipImage:
  repository: netskopeprivateaccess/publisher_u22_test
  tag: "10827"
  pullPolicy: IfNotPresent
```

Rootless lwIP mode is intended for SNAT-style publishing. L3 no-NAT mode still depends on kernel networking behavior and should use the normal pod or host networking modes.

## What The Chart Changes

When `networking.mode=lwip` is selected, the chart should render the Publisher without privileged network requirements:

- Uses `netskopeprivateaccess/publisher_u22_test:10827` by default.
- Sets `DATA_PLANE=lwip`.
- Runs as non-root UID/GID `65532`.
- Drops all Linux capabilities.
- Does not request `NET_ADMIN` or `NET_RAW`.
- Does not mount `/dev/net/tun`.
- Does not add the local DNS sidecar used by pod networking mode.
- Skips TUN namespace setup, interface cleanup, iptables discovery, and network sysctls in the bootstrap script.

## Example Values

```yaml
networking:
  mode: lwip

lwipImage:
  repository: netskopeprivateaccess/publisher_u22_test
  tag: "10827"
  pullPolicy: IfNotPresent

workload:
  type: statefulset
  replicas: 2

enrollment:
  mode: api

api:
  secretName: netskope-api-credentials
  tenantHost: example.goskope.com
  orgKey: example-org-key
```

For DaemonSet installs, keep the same `networking` and `lwipImage` settings, then set the existing `workload.type` values required by the deployment.

## Install Or Upgrade

```bash
helm upgrade --install kubernetes-netskope-publisher ./chart \
  -n npa-publisher \
  --create-namespace \
  -f rootless-lwip-values.yaml
```

For repository-based installs, replace `./chart` with the configured chart reference.

## Render Checks

Before applying to a cluster, render the manifests and confirm the security-sensitive fields:

```bash
helm template kubernetes-netskope-publisher ./chart \
  -n npa-publisher \
  -f rootless-lwip-values.yaml
```

The rendered manifests should contain:

- `DATA_PLANE` set to `lwip`.
- Image `netskopeprivateaccess/publisher_u22_test:10827`.
- `runAsNonRoot: true`.
- `runAsUser: 65532`.
- `runAsGroup: 65532`.
- `fsGroup: 65532`.
- `capabilities.drop: ["ALL"]`.

The rendered manifests should not contain:

- `NET_ADMIN`.
- `NET_RAW`.
- `privileged: true`.
- `/dev/net/tun`.
- The `local-dns` sidecar.

## Runtime Validation

After rollout, check pod status and logs:

```bash
kubectl get pods -n npa-publisher
kubectl logs -n npa-publisher -l app.kubernetes.io/name=kubernetes-netskope-publisher
```

Expected signs:

- Pods start without privileged security policy exceptions.
- Bootstrap logs skip TUN and iptables setup paths.
- Publisher starts with the lwIP data plane.
- Enrollment completes and the Publisher comes online in the Netskope tenant.

## Rollback

To return to the normal pod networking mode, change the values back to the standard image and networking mode:

```yaml
networking:
  mode: pod

image:
  repository: netskopeprivateaccess/publisher_u22
```

Pod networking mode requires the normal TUN and network capability settings. Do not keep the rootless security context if switching back to a TUN-based mode.
