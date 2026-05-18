---
title: Rotate the API token
date: 2026-05-18
---

The API token in `enrollment.api.existingSecret` is the only persistent
secret in `mode: api`. Rotate it like any Kubernetes Secret — Helm
doesn't need to be re-rendered.

## 1. Mint a new token

In the Netskope admin console: **Settings → Tools → REST API v2 → New Token**.
Same scopes as the old one (`publishers` read+write).

## 2. Patch the Secret

```bash
kubectl create secret generic npa-api-token \
  --namespace npa-publisher \
  --from-literal=api-token='NEW_TOKEN' \
  --dry-run=client -o yaml | kubectl apply -f -
```

## 3. Restart pods so they pick up the new value

```bash
kubectl rollout restart -n npa-publisher \
  daemonset/kubernetes-netskope-publisher \
  || kubectl rollout restart -n npa-publisher statefulset/kubernetes-netskope-publisher
```

Each pod re-runs the init container, which calls the API with the new
token. The Publisher record itself is unchanged.

## 4. Revoke the old token

Same UI: **Settings → Tools → REST API v2 → Revoke**.

## Caveats

- **Don't rotate during a network outage.** If the pod can't reach the
  tenant API, the init container retries until it succeeds — but
  meanwhile new pods can't enroll. Schedule rotation during a known-good
  connectivity window.
- **No need to bump the Helm release.** Pods read the Secret at init time;
  a rollout-restart is sufficient.
