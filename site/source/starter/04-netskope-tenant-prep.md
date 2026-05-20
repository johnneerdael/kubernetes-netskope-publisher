---
title: Netskope tenant prep
date: 2026-05-18
---

The Publisher needs to authenticate to your tenant. The chart supports
two flows:

| Flow | When to use |
|---|---|
| **API enrollment** (`enrollment.mode: api`) | **Default. Recommended.** Chart looks up or creates the Publisher record and enrolls itself. Needs either a static API token or OAuth2 client credentials. |
| **Token enrollment** (`enrollment.mode: token`) | One-time registration token created in the UI. Token is consumed on first start. |

This guide uses the API flow. It survives pod restarts, scaling, and
re-deploys without manual token rotation.

## 1. Find your tenant URL

It's the URL you sign into the admin console with, e.g.
`https://tenant.goskope.com`. **Do not include a trailing slash** when
you later set `enrollment.api.baseUrl`.

## 2. Choose API credentials

The quickest starter path uses a static REST API v2 token. If your
tenant uses OAuth2 client credentials instead, keep the client ID,
client secret, and token endpoint URL handy for the install step.

### Static API token

1. Admin console → **Settings → Tools → REST API v2**.
2. **New Token**.
3. **Scopes** — grant *read + write* on:
   - `/api/v2/infrastructure/publishers`
   - `/api/v2/infrastructure/publisherupgradeprofiles` (optional, only
     if you'll manage upgrade profiles from this chart later).
4. Copy the token. It's shown once.

### OAuth2 client credentials

Use the OAuth2 client ID and client secret from your tenant or identity
provider. The chart also needs the full OAuth2 token endpoint URL for
the `client_credentials` grant.

## 3. Stage credentials as a Kubernetes secret

We'll do this on the cluster in the next step. For now, paste the API
token or OAuth2 client credentials into a private password manager —
you'll need them once.

> ⚠️ Never commit API credentials to git. The chart references them by
> Secret name, not by value. See
> [secret handling](/kubernetes-netskope-publisher/admin/operations/secret-handling/).
