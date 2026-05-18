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
    │       body: { "name": <commonName>, ... }
    │     ↳ Tenant returns publisher_id + bootstrap config.
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
init container (npa-enroll)
    │
    └── Reads `registrationToken.value` (or existingSecret) → exit 0

publisher container
    └── Uses the one-time token on first start. Burns it.
```

### When to use
- Air-gapped tenants where the cluster cannot reach the management API.
- Strict change-management environments where token issuance is gated.

### Constraint
- Token is consumed on first use. A rescheduled pod **cannot re-enroll
  with the same token**. Pair `mode: token` with `persistence.enabled:
  true` so the registered identity survives restarts.
