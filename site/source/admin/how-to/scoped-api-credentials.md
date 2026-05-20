---
title: Scope API credentials to a Publisher cluster set
date: 2026-05-20
---

Use this workflow when a Kubernetes deployment should manage only a
specific set of Netskope Private Access Publishers, not every Publisher
in the tenant. The result is a service account credential, either REST
API v2 token or OAuth2 client credentials, scoped to Publishers carrying
a dedicated label.

This is useful for delegated operations, shared tenants, and
multi-cluster environments where each cluster or cluster set owns its
own Publisher records.

## Outcome

By the end, the tenant contains:

- A label under `Netskope Private Access > Publishers`, such as
  `prod-eu-cluster-set`.
- Two or more Publisher records carrying that label.
- A custom role that can manage NPA Publishers and is scoped to that
  label.
- A service account bound to that role, with either an API key or
  OAuth2 client credentials.
- Helm values that consume the credential without embedding secrets in
  the release.

## How label scoping works

Netskope roles combine functional permissions with object scope.
Functional permissions define what the principal can do; object scope
defines which labeled objects the permission applies to.

Publisher management does not expose its own label-scope picker in all
tenant UIs. The practical pattern is to add one low-impact permission
that does expose object scoping, then apply the label there. Use:

| Permission area | Permission | Scope |
|---|---|---|
| `NPA > Publishers` | `Manage` | Inherits the role's object scope |
| `Skope IT > Network Events` | `View` | Label = your Publisher cluster-set label |
| Everything else | `None` | Not applicable |

The `Network Events` permission is only the carrier for the object
scope. Do not grant additional Skope IT, DLP, policy, or tenant-wide
administrator permissions unless that broader access is intentional.

## Prerequisites

- A Netskope tenant administrator account that can manage labels, roles,
  administrators, and NPA Publishers.
- A cluster-set label name. Use an environment or ownership name, for
  example `prod-eu-cluster-set`, not a role name.
- At least two Publisher records for production cluster sets. One
  Publisher is enough for a lab, but it leaves no redundancy during
  upgrades or node failures.
- A secure place to store the generated API token or OAuth2 client
  secret.

## 1. Create the Publisher label

1. Open `Settings > Administration > Labels`.
2. Create a new label under `Netskope Private Access > Publishers`.
3. Name it after the cluster set or owning environment, for example
   `prod-eu-cluster-set`.
4. Save the label.

Use labels to describe the Publishers, not the credential. The same
label is reused across Publisher records and role scopes, so it should
name the managed object set.

## 2. Create and label Publisher records

Scoped credentials can only see and manage Publishers in their label
scope. For that reason, pre-create the Publisher records that the chart
will enroll, then apply the label to those records.

For StatefulSet deployments, this chart appends the pod name to
`enrollment.commonName`. With release name
`kubernetes-netskope-publisher` and:

```yaml
workload:
  type: statefulset
  replicas: 3

enrollment:
  mode: api
  commonName: prod-eu-publisher
```

the chart will look for these Publisher identities:

```text
prod-eu-publisher-kubernetes-netskope-publisher-0
prod-eu-publisher-kubernetes-netskope-publisher-1
prod-eu-publisher-kubernetes-netskope-publisher-2
```

Create those Publisher records in `Settings > Security Cloud Platform >
Publishers`, then apply the cluster-set label to each record.

Keep `workload.replicas` equal to the number of labeled Publisher
records. To scale from three to four replicas, first create and label
`prod-eu-publisher-kubernetes-netskope-publisher-3`, then update the
Helm values and run `helm upgrade`.

## 3. Create the scoped role

1. Open `Settings > Administration > Administrators & Roles > Roles`.
2. Create a new role. Use a name such as
   `Publisher Management - prod-eu-cluster-set`.
3. Enable only the functional area needed for NPA Publisher management.
4. In the permission grid, set:

| Permission area | Permission |
|---|---|
| `NPA > Publishers` | `Manage` |
| `Skope IT > Network Events` | `View` |
| All other rows | `None` |

5. Open the `Scope` control for the `Network Events` row.
6. Leave data-scope fields empty.
7. Under object scope, choose the same scope for all permissions.
8. Set the object scope label to the Publisher cluster-set label.
9. Save the scope, then save the role.

The role should now have Publisher management access restricted to the
labeled Publisher set.

## 4. Create the service account

1. Open `Settings > Administration > Administrators & Roles >
   Administrators`.
2. Click `Service Account`.
3. Name it after the cluster set, for example
   `Publisher Management - prod-eu-cluster-set`.
4. Assign the custom role from the previous step.
5. Choose the credential type.

| Credential type | Best for | Operational notes |
|---|---|---|
| OAuth2 client credentials | Production deployments | Short-lived access tokens; rotate the client secret before expiry. |
| REST API v2 token / API key | Labs, PoCs, or tenants not using OAuth2 yet | Long-lived token; rotate before expiry and update the Kubernetes Secret. |

Capture the generated secret immediately. Netskope displays the client
secret or API token only once.

## 5. Create the Kubernetes Secret

For a static REST API v2 token:

```bash
kubectl create namespace npa-publisher

kubectl create secret generic npa-api-token \
  --namespace npa-publisher \
  --from-literal=api-token='PASTE_NETSKOPE_API_TOKEN_HERE'
```

For OAuth2 client credentials:

```bash
kubectl create namespace npa-publisher

kubectl create secret generic npa-api-oauth \
  --namespace npa-publisher \
  --from-literal=client-id='PASTE_CLIENT_ID_HERE' \
  --from-literal=client-secret='PASTE_CLIENT_SECRET_HERE'
```

Do not pass these values with `helm install --set`. Keep the credential
in a Kubernetes Secret and reference the Secret by name in values.

## 6. Configure the chart

Use StatefulSet mode when the cluster set has multiple Publisher
records. StatefulSet mode gives each pod a stable identity and lets the
chart append the pod name to `enrollment.commonName`.

### OAuth2 values

```yaml
workload:
  type: statefulset
  replicas: 3

networking:
  mode: pod
  disableIPv6: true

persistence:
  enabled: false

enrollment:
  mode: api
  commonName: prod-eu-publisher
  api:
    baseUrl: https://tenant.goskope.com
    authMode: oauth2
    oauth2:
      tokenUrl: https://tenant.goskope.com/oauth2/token
      existingSecret: npa-api-oauth
      clientIdKey: client-id
      clientSecretKey: client-secret
```

### Static API token values

```yaml
workload:
  type: statefulset
  replicas: 3

networking:
  mode: pod
  disableIPv6: true

persistence:
  enabled: false

enrollment:
  mode: api
  commonName: prod-eu-publisher
  api:
    baseUrl: https://tenant.goskope.com
    authMode: token
    existingSecret: npa-api-token
    tokenKey: api-token
```

Install or upgrade:

```bash
helm upgrade --install kubernetes-netskope-publisher npa/kubernetes-netskope-publisher \
  --namespace npa-publisher \
  -f my-values.yaml
```

Leave `enrollment.api.cleanupOnDelete` disabled for scoped cluster
sets unless you intentionally want pod termination to delete the
tenant-side Publisher record. Most scoped deployments should scale down
first, then unlabel or delete retired Publisher records manually.

## 7. Verify the scope

Verify both the chart behavior and the credential boundary:

1. In `Security Cloud Platform > Publishers`, confirm that every
   labeled Publisher reports the expected status after the pods enroll.
2. Use the issued credential to call
   `GET /api/v2/infrastructure/publishers` and confirm the response only
   includes Publishers in the labeled set.
3. Try to retrieve or modify a Publisher outside the labeled set. The
   request should fail with an authorization error.
4. Review the tenant audit log for the service-account principal. It
   should appear only against Publisher-related actions.

## 8. Rotate credentials

For OAuth2:

1. Reissue the client secret on the service account.
2. Update the Kubernetes Secret:

   ```bash
   kubectl create secret generic npa-api-oauth \
     --namespace npa-publisher \
     --from-literal=client-id='PASTE_CLIENT_ID_HERE' \
     --from-literal=client-secret='PASTE_NEW_CLIENT_SECRET_HERE' \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

3. Restart the StatefulSet:

   ```bash
   kubectl rollout restart statefulset/kubernetes-netskope-publisher \
     --namespace npa-publisher
   ```

For static API tokens, reissue the token, update `npa-api-token` with
the same `kubectl create secret ... --dry-run=client -o yaml | kubectl
apply -f -` pattern, then restart the workload.

## 9. Scale the cluster set

To add a Publisher:

1. Create the next Publisher record that matches the chart-generated
   name.
2. Apply the cluster-set label to the new Publisher.
3. Increase `workload.replicas`.
4. Run `helm upgrade`.

To retire a Publisher:

1. Reduce `workload.replicas` and run `helm upgrade` so the highest
   ordinal pod is removed first.
2. Confirm the retired Publisher no longer has an active pod.
3. Unlabel or delete the Publisher record in Netskope.

Never remove the label from a Publisher that still has an active pod
enrolled against it. The scoped credential may lose visibility before
the chart can complete the next startup or maintenance action.
