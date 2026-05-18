---
title: Delete a Publisher cleanly
date: 2026-05-18
---

`helm uninstall` removes the pod but leaves the Publisher record in the
Netskope tenant. To delete both:

## 1. Uninstall the Helm release

```bash
helm uninstall npa-publisher -n npa-publisher
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
