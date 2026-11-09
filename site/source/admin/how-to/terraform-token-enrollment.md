---
title: Token enrollment with Terraform-issued tokens
date: 2026-11-09
---

Use this when the tenant is managed with the official
[`netskopeoss/netskope`](https://registry.terraform.io/providers/netskopeoss/netskope)
Terraform provider and the cluster must not hold a Netskope API credential.
Terraform creates the Publishers and their single-use registration tokens.
The chart only consumes the tokens (`enrollment.mode: token`).

For a full walkthrough with prerequisites, verification, scaling and
troubleshooting, see [Deploy Publisher replicas with the Netskope Terraform provider](/kubernetes-netskope-publisher/admin/how-to/terraform-replicas/).

Requires chart `>= 1.6.0`. It uses the provider's existing
`netskope_npa_publisher` and `netskope_npa_publisher_token` resources and
needs no provider change.

## How the pieces fit

| Terraform | Kubernetes |
|---|---|
| `netskope_npa_publisher` × N | — |
| `netskope_npa_publisher_token` × N | Secret, one key per pod |
| `helm_release` | StatefulSet (or DaemonSet) in token mode |

Each pod selects its key with `registrationToken.keyBy`:

| `keyBy` | Workload | Secret keys |
|---|---|---|
| `single` | DaemonSet pinned to one node | `token` (or `existingSecretKey`) |
| `ordinal` | StatefulSet | `"0"` .. `"N-1"` |
| `node` | DaemonSet | node names (`spec.nodeName`) |

## Terraform

```hcl
resource "netskope_npa_publisher" "this" {
  for_each       = toset([for i in range(var.replicas) : tostring(i)])
  publisher_name = "k8s-publisher-${each.key}"
}

resource "netskope_npa_publisher_token" "this" {
  for_each     = netskope_npa_publisher.this
  publisher_id = each.value.publisher_id
}

resource "kubernetes_secret_v1" "registration_tokens" {
  metadata {
    name      = "npa-publisher-registration-tokens"
    namespace = "npa-publisher"
  }
  data = { for k, t in netskope_npa_publisher_token.this : k => t.token }
}

resource "helm_release" "publisher" {
  name       = "npa-publisher"
  namespace  = "npa-publisher"
  repository = "oci://ghcr.io/johnneerdael/charts"
  chart      = "kubernetes-netskope-publisher"
  version    = "1.6.0"

  values = [yamlencode({
    workload          = { type = "statefulset", replicas = var.replicas }
    enrollment        = { mode = "token" }
    registrationToken = { keyBy = "ordinal", existingSecret = kubernetes_secret_v1.registration_tokens.metadata[0].name }
    persistence       = { enabled = true }
    podAnnotations = {
      # Roll pods when a token is added or rotated.
      "npa.netskope.io/registration-tokens-sha256" = nonsensitive(sha256(jsonencode(kubernetes_secret_v1.registration_tokens.data)))
    }
  })]
}
```

The complete example, with a DaemonSet variant, lives in the repository at
`examples/terraform-token-enrollment/`.

## What the chart does

- The `enroll` init container reads only its own key. A missing key fails
  with a clear message, so a replica never borrows another replica's token.
- After enrollment it stores a SHA-256 fingerprint of the token in the
  persisted state. Restarts with the same token skip enrollment.
- A different token triggers re-enrollment. The previous state is backed up
  and restored if the wizard fails.
- With `persistence.enabled: true` a StatefulSet gets one PVC per replica
  (`volumeClaimTemplates`). A DaemonSet can use `persistence.type: hostPath`
  for per-node state.

## Guard rails

The chart refuses to render:

- `workload.type: statefulset` + token mode unless `keyBy: ordinal`.
- `hpa.enabled` in token mode. An autoscaler cannot get new tokens, so
  scale with `workload.replicas` and the Terraform count together.
- Chart-managed `registrationToken.tokens` that lack a key for some replica.
- `persistence.type: hostPath` on a StatefulSet (replicas could share a
  node directory and so a Publisher identity).

## Day-2

- **Scale**: change `replicas` and apply. Terraform adds the Publisher and
  token, the Secret gains a key, and Helm scales the StatefulSet.
- **Re-enroll one replica**: disconnect it, then run
  `terraform apply -replace='netskope_npa_publisher_token.this["1"]'`.
  Only replica 1 sees a new fingerprint and re-enrolls.
- **State**: Terraform state contains the tokens. Protect the backend.
