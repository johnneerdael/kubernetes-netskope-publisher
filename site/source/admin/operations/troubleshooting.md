---
title: Troubleshooting
date: 2026-05-18
---

Start here when a Publisher won't go Online.

## Quick triage

```bash
# Are pods running?
kubectl get pods -n npa-publisher -o wide

# Init container exit reason
kubectl describe pod -n npa-publisher <pod>

# Publisher container logs
kubectl logs -n npa-publisher <pod> -c publisher --tail=200
```

## Failure: pod stuck in `Init:0/1`

Likely the **init container is retrying** the API enrollment.

```bash
kubectl logs -n npa-publisher <pod> -c npa-bootstrap
```

Common causes:

| Log line | Cause | Fix |
|---|---|---|
| `Cannot resolve tenant.goskope.com` | DNS broken inside the pod | Set `bind.forwarders` or fix cluster DNS |
| `401 Unauthorized` | Wrong/expired API token | [Rotate the token](/kubernetes-netskope-publisher/admin/how-to/rotate-token/) |
| `403 Forbidden` | Token lacks `publishers` scope | Re-mint with correct scope |
| `Connection refused` / `i/o timeout` | Egress blocked | Open outbound 443 to `*.goskope.com` |

## Failure: Publisher logs repeat `Connect to stitcher status: Resolving`

The agent can't resolve `gateway-*.gw.npa.goskope.com`. The most common
fix is providing explicit DNS forwarders:

```yaml
bind:
  forwarders:
    - "8.8.8.8"
    - "8.8.4.4"
```

If your cluster uses internal-only DNS (forwarders that can't reach
public), you must allow the in-pod BIND9 to bypass them for
`*.goskope.com`. Forwarders above replace the auto-discovered list.

## Failure: `cannot open /dev/net/tun`

The `tunDevice` mount isn't reaching the pod.

- In `mode: pod`: confirm `tunDevice.enabled: true` and the node has
  `/dev/net/tun` present (`ls -la /dev/net/tun` on the node).
- In `mode: host`: this shouldn't happen — the pod uses the host's
  device directly via `hostNetwork`.
- On kind: confirm the kind config mounts `/dev/net/tun`. See
  [kind distribution](/kubernetes-netskope-publisher/admin/chart/distributions/kind/).
- On EKS Bottlerocket / GKE Autopilot: see distribution-specific notes.

## Failure: `NET_ADMIN` operation not permitted

PSA / SCC is blocking the capability.

```bash
kubectl describe pod -n npa-publisher <pod> | grep -i security
```

Fix: label namespace `pod-security.kubernetes.io/enforce=privileged`,
or bind `privileged` SCC on OpenShift. See
[distributions](/kubernetes-netskope-publisher/admin/chart/distributions/).

## Failure: Publisher appears Offline after working

```bash
# Check that the pod is still running and tunnels are up
kubectl logs -n npa-publisher <pod> -c publisher --tail=50 | grep -E "NPACONNECTED|stitcher"
```

If the log shows recent `NPACONNECTED` but the console says Offline:

- Tenant-side outage (rare). Check Netskope status page.
- Egress IP changed (NAT gateway was recreated). Re-attest in the console.
- API token revoked. Re-rotate.

## Collecting diagnostics

```bash
kubectl logs -n npa-publisher <pod> -c npa-bootstrap > bootstrap.log
kubectl logs -n npa-publisher <pod> -c publisher > publisher.log
kubectl describe pod -n npa-publisher <pod> > describe.log
kubectl get events -n npa-publisher --sort-by=.lastTimestamp > events.log
```

Bundle these when opening a Netskope support case.
