---
title: Delete a Publisher cleanly
date: 2026-05-18
---

Since chart 1.3.0, **`helm uninstall` (and any pod termination)
automatically deletes the tenant-side Publisher record** via the pod's
preStop hook. The flow below is for cases where:

- You ran `enrollment.api.cleanupOnDelete: false`
- The preStop hook failed (network glitch, expired token, tenant outage)
- You're cleaning up records from before 1.3.0
- You're using `enrollment.mode: token` (preStop only applies in API mode)

If the automatic cleanup ran successfully, the record is already gone —
you can skip step 2.

## 1. Uninstall the Helm release

```bash
helm uninstall kubernetes-netskope-publisher -n npa-publisher
kubectl delete namespace npa-publisher
```

## 2. Delete the Publisher record via API

Find the publisher ID:

```bash
curl -s -H "Netskope-Api-Token: $TOKEN" \
  "https://tenant.goskope.com/api/v2/infrastructure/publishers" \
  | jq '.data.publishers[] | select(.common_name=="prod-eu-publisher") | .publisher_id'
```

Then delete:

```bash
curl -X DELETE \
  -H "Netskope-Api-Token: $TOKEN" \
  "https://tenant.goskope.com/api/v2/infrastructure/publishers/<publisher-id>"
```

## 3. (StatefulSet members) clean up suffixed names

If you ran a StatefulSet with replicas 2, you'll have:

```
prod-eu-publisher-0
prod-eu-publisher-1
```

Repeat step 2 for each. The Netskope console **Delete** action works
just as well; the API is just scriptable.

## What about associated Private Apps?

Deleting a Publisher record automatically detaches it from any Private
Apps it was assigned to. Apps with **zero remaining Publishers** become
unreachable to end users until you attach a replacement. To check
before deleting:

```bash
curl -s -H "Netskope-Api-Token: $TOKEN" \
  "https://tenant.goskope.com/api/v2/infrastructure/publishers/<id>/apps" | jq
```
