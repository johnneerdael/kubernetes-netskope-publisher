---
title: Tear it down
date: 2026-05-18
---

When you're done experimenting:

## 1. Uninstall the chart

```bash
helm uninstall kubernetes-netskope-publisher -n npa-publisher
kubectl delete namespace npa-publisher
```

## 2. Delete the Publisher record in Netskope

Helm uninstall removes the pod, but the Publisher record in the
Netskope tenant remains (it's tenant-side state). Delete it from:

- **NG SASE → Steering → Publishers → ⋮ → Delete**, or
- The REST API:

  ```bash
  curl -X DELETE \
    -H "Netskope-Api-Token: $TOKEN" \
    "https://tenant.goskope.com/api/v2/infrastructure/publishers/<publisher-id>"
  ```

See [delete-publisher](/kubernetes-netskope-publisher/admin/how-to/delete-publisher/)
for a cleaner workflow that wraps both.

## 3. (Optional) Remove k3s

If this was a throwaway VM, snap it back to a snapshot. Otherwise:

```bash
/usr/local/bin/k3s-uninstall.sh
```

That stops the systemd unit, removes the binary, kubeconfig, and all
container state.
