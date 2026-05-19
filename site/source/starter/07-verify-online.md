---
title: Verify it's online
date: 2026-05-18
---

## 1. Pod is Running

```bash
kubectl get pods -n npa-publisher -w
```

Wait for `2/2 Running` in the default pod-networking mode. The
Publisher container may take 30–60 seconds while it enrolls and
connects.

## 2. Follow the Publisher logs

```bash
kubectl logs -l app.kubernetes.io/name=kubernetes-netskope-publisher \
  -n npa-publisher \
  -c publisher \
  -f
```

You're looking for this sequence:

```text
[npa-api-enrollment] API enrollment mode active
[npa-api-enrollment] Selected publisher_id=...
[npa-api-enrollment] Enrollment complete; starting publisher
k8s-bootstrap: Preparing pod network namespace
k8s-bootstrap: Starting NPA Publisher
NPACONNECTED
```

`NPACONNECTED` (or `ConnectedResolvedByGSLB`) means the Publisher has a
healthy tunnel up to the Netskope stitchers.

## 3. Check in the admin console

**NG SASE → Steering → Publishers** — your Publisher should appear with:

- **Status:** Online (green dot)
- **Common name:** the `enrollment.commonName` from your values file
- **Version:** the appVersion of the chart

## Common first-run failures

| Symptom | Cause | Where to look |
|---|---|---|
| `Resolving` repeats forever | Pod can't resolve `*.goskope.com` | [troubleshooting](/kubernetes-netskope-publisher/admin/operations/troubleshooting/) — fix cluster DNS in pod mode |
| `Permission denied` on `/dev/net/tun` | tunDevice not mounted, or PSA blocks the mount | [pod-vs-host network](/kubernetes-netskope-publisher/admin/how-to/pod-vs-host-network/) |
| `401 Unauthorized` from enrollment | API token scope wrong | [Netskope tenant prep](/kubernetes-netskope-publisher/starter/04-netskope-tenant-prep/) — re-mint with publishers write |
| `commonName` already in use | Existing publisher record with that name | Change `enrollment.commonName` or delete the stale record |
