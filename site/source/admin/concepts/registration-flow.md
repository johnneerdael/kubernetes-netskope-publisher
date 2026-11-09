---
title: Registration flow
date: 2026-05-18
---

There are two enrollment paths. Both are implemented as bash scripts
shipped inside the Publisher image; the chart picks one via
`enrollment.mode`.

## `mode: api` (default, recommended)

```text
init container (npa-bootstrap)
    │
    ├── GET  /api/v2/infrastructure/publishers?fields=common_name,publisher_name
    │     ↳ Match `enrollment.commonName` against common_name OR publisher_name.
    │
    ├── If no match:
    │     POST /api/v2/infrastructure/publishers
    │       body: { "name": <commonName>, "labels": <publisherLabels> }
    │     ↳ Tenant returns publisher_id + bootstrap config.
    │       `labels` defaults to [] and is always sent — some tenants
    │       reject creation without it ("Labels are not present in the
    │       request"). Override via enrollment.api.publisherLabels.
    │
    ├── POST /api/v2/infrastructure/publishers/<id>/registration_token
    │     ↳ Tenant returns a short-lived registration token.
    │
    └── Write /etc/npa/{registration-config,token} → exit 0
```

Then the **publisher container** starts, reads `/etc/npa`, and connects
to the tenant.

### Properties
- **Idempotent** — re-running the init container on the same
  `commonName` re-uses the existing Publisher record.
- **Self-healing** — if a node dies, the new pod re-enrolls automatically.
- **No persistent state required** — the API token is the only persistent
  secret. Everything else is regenerated per pod start.

## `mode: token`

```text
init container (enroll)
    │
    ├── Picks its token from the Secret (registrationToken.keyBy):
    │     single → key "token" · ordinal → key "<N>" · node → key "<node>"
    ├── State present + same token fingerprint → skip, exit 0
    ├── State present + new token → back up state, re-enroll (restore on failure)
    └── No state → npa_publisher_wizard -token … (burns the token) → exit 0

publisher container
    └── Starts from the persisted enrollment artifacts.
```

### When to use
- Tenant objects and tokens are managed by Terraform (`netskope_npa_publisher`
  + `netskope_npa_publisher_token`) and the cluster must not hold an API
  credential. See [Terraform-issued tokens](/kubernetes-netskope-publisher/admin/how-to/terraform-token-enrollment/).
- Strict change-management environments where token issuance is gated.

### Constraint
- Token is consumed on first use. A rescheduled pod **cannot re-enroll
  with the same token**. Pair `mode: token` with `persistence.enabled:
  true` so the registered identity survives restarts.
