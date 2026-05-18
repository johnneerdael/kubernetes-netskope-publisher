---
title: Secret handling
date: 2026-05-18
---

The chart never embeds secrets in templated objects — it always
references a **Secret resource by name**.

## What's secret

| Value | Where | Sensitivity |
|---|---|---|
| Netskope API token | Secret `npa-api-token` key `api-token` | High — full publisher admin scope |
| Registration token (`mode: token`) | Secret you create, or `--set` value | Medium — single-use, short-lived |
| Image pull credentials | Secret of type `kubernetes.io/dockerconfigjson` | Medium |

## Creating secrets safely

```bash
kubectl create secret generic npa-api-token \
  --namespace npa-publisher \
  --from-literal=api-token='paste-here'
```

> ⚠️ Do **not** pass secrets to `helm install --set ...`. Helm logs the
> rendered manifest with values visible to anyone with release-history
> access. Use `existingSecret` instead.

## GitOps with sealed/encrypted secrets

The chart references existing secrets by name, so anything that
produces a regular `Secret` resource works:

- **Sealed Secrets (bitnami):** seal a Secret, commit the `SealedSecret`,
  controller decrypts it in-cluster.
- **External Secrets Operator (ESO):** create an `ExternalSecret`
  pointing at Vault / AWS Secrets Manager / Azure Key Vault.
- **SOPS + helmfile:** sops-encrypt the values file, helmfile decrypts
  at deploy time — but **store only the `existingSecret: <name>`
  reference in values**, never the token itself.

## Rotation

See [rotate-token](/kubernetes-netskope-publisher/admin/how-to/rotate-token/).

## Auditing

- The chart's ServiceAccount doesn't have permission to read the API-token
  Secret. The kubelet injects it as a volume into the init container only.
- Audit logs (`audit.k8s.io/v1`) will record any human/manual `get`
  against the Secret. Watch for those if you have access control concerns.
