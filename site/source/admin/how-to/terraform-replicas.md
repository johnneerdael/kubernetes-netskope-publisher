---
title: Deploy Publisher replicas with the Netskope Terraform provider
date: 2026-11-09
---

This guide is for teams that already manage their Netskope tenant with the
official [`netskopeoss/netskope`](https://registry.terraform.io/providers/netskopeoss/netskope)
Terraform provider and want to run several NPA Publishers on Kubernetes with
this Helm chart.

Terraform creates the Publishers and their registration tokens. Kubernetes
runs the Publishers. The cluster never receives a Netskope API token or OAuth2
client: each pod gets only its own single-use registration token.

By the end you will have:

- N Publishers in your tenant, named `<prefix>-0` .. `<prefix>-N-1`.
- A StatefulSet with N replicas. Each replica enrolls with its own token and
  keeps its identity on its own PersistentVolumeClaim.
- One Terraform workflow for scaling, re-enrolling and attaching private apps.

Requirements: chart `1.6.0` or later, Netskope provider `0.4.13` or later.

## How it works

```text
            Terraform (holds the Netskope API key)
 ┌───────────────────────────────────────────────────────────────┐
 │ netskope_npa_publisher["0"] ─► netskope_npa_publisher_token["0"]│
 │ netskope_npa_publisher["1"] ─► netskope_npa_publisher_token["1"]│
 │ netskope_npa_publisher["2"] ─► netskope_npa_publisher_token["2"]│
 │                         │                                     │
 │ kubernetes_secret_v1 ◄──┘  data = { "0" = tok0, "1" = tok1, … }│
 │ helm_release  (enrollment.mode=token, keyBy=ordinal)          │
 └───────────────────────────────────────────────────────────────┘
                              │
            Kubernetes        ▼
 ┌───────────────────────────────────────────────────────────────┐
 │ StatefulSet  npa-publisher-kubernetes-netskope-publisher      │
 │   pod -0 ── reads Secret key "0" ── PVC resources-…-0         │
 │   pod -1 ── reads Secret key "1" ── PVC resources-…-1         │
 │   pod -2 ── reads Secret key "2" ── PVC resources-…-2         │
 └───────────────────────────────────────────────────────────────┘
```

Each replica is tied to one Publisher, one token and one volume:

| StatefulSet pod | Secret key | Terraform address | Tenant Publisher | Volume |
|---|---|---|---|---|
| `…-0` | `"0"` | `netskope_npa_publisher.this["0"]` | `k8s-publisher-0` | `resources-…-0` |
| `…-1` | `"1"` | `netskope_npa_publisher.this["1"]` | `k8s-publisher-1` | `resources-…-1` |
| `…-N` | `"N"` | `netskope_npa_publisher.this["N"]` | `k8s-publisher-N` | `resources-…-N` |

A StatefulSet is used rather than a Deployment because Deployment pods
(ReplicaSet pods) have random names and shared templates, so a pod cannot know
which token belongs to it. StatefulSet pods have stable ordinals, and the
chart uses the ordinal as the Secret key.

### What happens when a pod starts

The `enroll` init container runs before the Publisher starts:

1. It reads the Secret key that matches its ordinal. If the key is missing it
   stops with an error and never uses another replica's token.
2. If the volume already holds an enrollment made with **this** token (the
   chart records a SHA-256 fingerprint), it skips enrollment. Restarts,
   reschedules and `helm upgrade` rollouts don't spend the token again.
3. If the volume holds an enrollment made with a **different** token, a new
   token has been delivered. It backs up the old state, enrolls with the new
   token, and restores the old state if enrollment fails.
4. If the volume is empty, it enrolls with the token.

The main container then starts the Publisher from the enrolled state.

## Prerequisites

### Tools

| Tool | Version |
|---|---|
| Terraform | `>= 1.5` |
| `kubectl` | Matching your cluster |
| Helm CLI | Optional. Terraform's `helm` provider installs the chart. |

### Terraform providers

| Provider | Version | Purpose |
|---|---|---|
| `netskopeoss/netskope` | `>= 0.4.13` | Publishers and registration tokens |
| `hashicorp/kubernetes` | `>= 2.30` | Namespace and token Secret |
| `hashicorp/helm` | `>= 3.0` | Chart installation |

### Kubernetes cluster

- Kubernetes `>= 1.27`.
- A StorageClass that can provision `ReadWriteOnce` volumes. Run
  `kubectl get storageclass` and check for one marked `(default)`, or set
  `persistence.storageClass`.
- Pod networking requirements of the chart (`networking.mode`):
  - `pod` (default): pods need the `NET_ADMIN` and `NET_RAW` capabilities and
    access to `/dev/net/tun`. Under Pod Security Admission the namespace must
    allow this (`privileged` level, or a policy exception).
  - `lwip`: rootless and needs no extra capabilities. See
    [pod vs host network](/kubernetes-netskope-publisher/admin/how-to/pod-vs-host-network/).
  - `host` cannot be used with a StatefulSet.
- Outbound HTTPS from the pods to your Netskope tenant and stitcher PoPs,
  directly or through `proxy.*`.

### Netskope tenant

- A REST API v2 token for **Terraform only**, with read/write access to NPA
  Publishers. This credential stays on the machine or CI runner that runs
  Terraform.
- Optional: label IDs, if your tenant requires labels on new Publishers.
- Optional: an upgrade profile ID, if you don't want the tenant default.

## Step 1 — Get the example

The repository ships a working module at
[`examples/terraform-token-enrollment`](https://github.com/johnneerdael/kubernetes-netskope-publisher/tree/main/examples/terraform-token-enrollment):

```bash
git clone https://github.com/johnneerdael/kubernetes-netskope-publisher.git
cp -r kubernetes-netskope-publisher/examples/terraform-token-enrollment ./npa-publishers
cd npa-publishers
```

| File | Contents |
|---|---|
| `versions.tf` | Provider requirements and provider configuration |
| `variables.tf` | Inputs: replicas, names, namespace, chart version, … |
| `main.tf` | Publishers, tokens, Secret and Helm release |
| `outputs.tf` | Publisher IDs and the Secret name |
| `tests/` | Offline `terraform test` suite with mocked providers |

## Step 2 — Configure credentials

The Netskope provider reads its credentials from the environment:

```bash
export NETSKOPE_SERVER_URL="https://<tenant>.goskope.com/api/v2"
export NETSKOPE_API_KEY="<rest-api-v2-token>"
```

The `kubernetes` and `helm` providers use your kubeconfig. Set
`kubeconfig_path` and `kube_context` if you don't want the defaults
(`~/.kube/config`, current context).

In CI, store `NETSKOPE_API_KEY` as a masked secret of the pipeline, not in
`.tfvars` files.

## Step 3 — Choose your settings

Create `terraform.tfvars`:

```hcl
namespace             = "npa-publisher"
release_name          = "npa-publisher"
chart_version         = "1.6.0"

workload_type         = "statefulset"
replicas              = 3
publisher_name_prefix = "prod-k8s-publisher"   # tenant names: prod-k8s-publisher-0..2

networking_mode       = "pod"                  # or "lwip" for rootless
storage_size          = "1Gi"

# Optional
# publisher_label_ids          = ["<label-id>"]
# publisher_upgrade_profile_id = 2
# kube_context                 = "prod-cluster"
```

| Variable | Default | Notes |
|---|---|---|
| `replicas` | `2` | Number of Publishers, tokens and pods. Change this to scale. |
| `publisher_name_prefix` | `k8s-publisher` | Publisher names in the tenant are `<prefix>-<ordinal>`. Keep it unique per cluster. |
| `namespace` | `npa-publisher` | Created by Terraform. |
| `release_name` | `npa-publisher` | Helm release name; the Secret is `<release_name>-registration-tokens`. |
| `chart_version` | `1.6.0` | Chart from `oci://ghcr.io/johnneerdael/charts`. |
| `networking_mode` | `pod` | `pod` or `lwip` for StatefulSets. |
| `storage_size` | `1Gi` | Size of each replica's PVC. The enrollment state is small. |
| `publisher_label_ids` | `[]` | Labels on each new Publisher. |
| `publisher_upgrade_profile_id` | `null` | Tenant upgrade profile for each Publisher. |

### More chart settings

`main.tf` builds the Helm values in `local.base_values`. Add any other chart
value there, for example:

```hcl
  base_values = {
    # ... existing keys ...
    resources = {
      requests = { cpu = "500m", memory = "1024Mi" }
      limits   = { cpu = "1000m", memory = "1536Mi" }
    }
    nodeSelector = { "node-role.kubernetes.io/worker" = "true" }
    proxy = {
      enabled    = true
      httpsProxy = "http://proxy.example.com:8080"
      noProxy    = "localhost,127.0.0.1,.cluster.local"
    }
  }
```

To spread replicas across nodes, add a pod anti-affinity (`affinity`) or
`topologySpreadConstraints` through the same map. See the
[values reference](/kubernetes-netskope-publisher/admin/chart/values-reference/).

Leave these keys alone. They are what tie each pod to its token:
`enrollment.mode`, `registrationToken.*`, `workload.*` and `persistence.enabled`.

## Step 4 — Deploy

```bash
terraform init
terraform plan
terraform apply
```

The plan creates, in order:

1. `netskope_npa_publisher.this["0".."N-1"]` — the Publisher records.
2. `netskope_npa_publisher_token.this["0".."N-1"]` — one token each.
3. `kubernetes_namespace_v1.this` and `kubernetes_secret_v1.registration_tokens`.
4. `helm_release.publisher` — the StatefulSet, its headless Service and
   ConfigMap.

The plan shows tokens as `(sensitive value)`. The Helm release values contain
only the Secret name and a SHA-256 fingerprint of the tokens.

After apply:

```bash
terraform output publishers
# {
#   "0" = { publisher_id = 1234, publisher_name = "prod-k8s-publisher-0" }
#   "1" = { publisher_id = 1235, publisher_name = "prod-k8s-publisher-1" }
#   "2" = { publisher_id = 1236, publisher_name = "prod-k8s-publisher-2" }
# }
```

## Step 5 — Verify

### Pods and volumes

```bash
kubectl -n npa-publisher get statefulset,pods,pvc
```

Expect `READY 3/3`, three pods `…-0`, `…-1`, `…-2` in `Running`, and three
`Bound` PVCs named `resources-<statefulset>-<ordinal>`. The first start takes
a minute or two while each pod enrolls.

### Enrollment logs

```bash
kubectl -n npa-publisher logs npa-publisher-kubernetes-netskope-publisher-0 -c enroll
```

First start:

```text
[npa-token-enrollment] Running Publisher enrollment wizard (Secret key '0' (replica 0))
[npa-token-enrollment] Enrollment complete
```

Any later restart:

```text
[npa-token-enrollment] Already enrolled with the current registration token; skipping enrollment
```

### Publisher logs

```bash
kubectl -n npa-publisher logs npa-publisher-kubernetes-netskope-publisher-0 -c publisher
```

### Tenant

In the Netskope console (**Settings → Security Cloud Platform → Publishers**)
the Publishers `prod-k8s-publisher-0..2` should show as connected. To check
from Terraform:

```hcl
data "netskope_npa_publisher" "check" {
  for_each     = netskope_npa_publisher.this
  publisher_id = each.value.publisher_id
}

output "publisher_status" {
  value = { for k, p in data.netskope_npa_publisher.check : k => p.status }
}
```

## Step 6 — Attach private apps

Reference the Publishers directly from `netskope_npa_private_app`, so every
replica serves the app:

```hcl
resource "netskope_npa_private_app" "intranet" {
  private_app_name     = "intranet"
  private_app_hostname = "intranet.corp.internal"
  private_app_protocol = "tcp"
  real_host            = "intranet.corp.internal"

  protocols = [
    { port = "443", protocol = "tcp" }
  ]

  publishers = [
    for p in netskope_npa_publisher.this : {
      publisher_id   = tostring(p.publisher_id)
      publisher_name = p.publisher_name
    }
  ]
}
```

When you change `replicas`, the publisher list changes with it, so new
replicas serve the app straight away. Before scaling down, read the
scale-down notes below.

## Day-2 operations

### Scale up

```bash
terraform apply -var replicas=5
```

Terraform creates Publishers and tokens `"3"` and `"4"`, adds the keys to the
Secret, and raises the StatefulSet replica count. The changed fingerprint
annotation rolls the existing pods. Their own tokens haven't changed, so they
skip enrollment and come back with their existing identities.

A StatefulSet rolling update restarts the existing pods one at a time, highest
ordinal first. Each replica is briefly offline while the others keep serving.
If you want new replicas without restarting the existing ones, see the FAQ.

### Scale down

Pods with the highest ordinals are removed first. Before you lower `replicas`:

1. Make sure no private app still references the Publishers you are
   retiring. Netskope refuses to delete a Publisher that has private apps
   attached. With the `for` expression above, apps managed in the same
   configuration are updated in the same apply, before Terraform deletes the
   Publishers they depended on. Detach apps managed elsewhere (console, other
   workspaces) first.
2. Apply the lower count:

   ```bash
   terraform apply -var replicas=3
   ```

Terraform deletes the retired Publisher records and drops their Secret keys,
and Helm lowers the replica count. The PVCs of removed replicas are kept,
because a StatefulSet never deletes PVCs by default. If you scale up again
later, the old volume holds a fingerprint of an old token, so the replica
re-enrolls with its new token automatically. To free the storage:

```bash
kubectl -n npa-publisher delete pvc resources-npa-publisher-kubernetes-netskope-publisher-4
```

> HPA is not supported in token mode, and the chart refuses `hpa.enabled`.
> An autoscaler can add pods but cannot create Publishers or tokens. Scale
> through Terraform as shown above.

### Re-enroll one replica

Use this after certificate problems, after a volume is lost, or when moving
a Publisher. Tokens are single-use, and the tenant won't issue a new token
for a Publisher that is connected, so:

1. Stop the replica, or wait for it to show as disconnected.
2. Replace only its token:

   ```bash
   terraform apply -replace='netskope_npa_publisher_token.this["1"]'
   ```

The Secret's key `"1"` changes, the pods roll, and only replica 1 sees a new
fingerprint and re-enrolls. All other replicas skip enrollment. If enrollment
fails, replica 1 restores its previous state and its `enroll` container exits
with the reason in its log.

### Lost or deleted volume

A replica whose PVC was deleted starts with an empty volume. Its token in the
Secret has already been spent, so enrollment fails with:

```text
Publisher enrollment failed (wizard exit …). Registration tokens are single-use …
```

Replace that replica's token as in the previous section.

### Upgrade the chart

Raise `chart_version` and apply. Pods restart and skip enrollment, because
their tokens haven't changed.

> **Upgrading from chart < 1.6.0 with StatefulSet persistence:** chart 1.6.0
> switches StatefulSets to per-replica `volumeClaimTemplates`, which Kubernetes
> does not allow to change on an existing StatefulSet. Delete the StatefulSet
> without deleting its pods first:
> `kubectl -n npa-publisher delete statefulset <name> --cascade=orphan`.

### Upgrade the Publisher software

The Publisher image comes from `image.repository` and `image.tag`
(`lwipImage.*` in `lwip` mode). Pin a tag in `local.base_values` and apply to
roll out a new version. Enrollment state
is kept across image upgrades.

### Remove everything

```bash
terraform destroy
```

This uninstalls the chart, deletes the Secret and namespace, and deletes the
Publisher records. Detach private apps first. Terraform does this in the same
run when the apps are managed in the same configuration, because the apps
depend on the Publishers. Deleting the namespace also removes the PVCs.

## Variations

### Install the chart with Helm or GitOps instead

Terraform can manage only the tenant objects and the Secret, while Helm,
Argo CD or Flux installs the chart. Drop `helm_release.publisher` and use
these values:

```yaml
workload:
  type: statefulset
  replicas: 3                 # must equal the Terraform count
enrollment:
  mode: token
registrationToken:
  keyBy: ordinal
  existingSecret: npa-publisher-registration-tokens
persistence:
  enabled: true
  size: 1Gi
```

```bash
helm upgrade --install npa-publisher \
  oci://ghcr.io/johnneerdael/charts/kubernetes-netskope-publisher \
  --version 1.6.0 -n npa-publisher -f values.yaml
```

Keep `workload.replicas` equal to the Terraform count. A replica without a
Secret key stops with `No registration token found for replica N`.

### One Publisher per node (DaemonSet)

Set `workload_type = "daemonset"` and list the nodes in `node_names`. Secret
keys become node names, the chart uses `keyBy=node` with per-node hostPath
storage, and node affinity keeps pods on listed nodes. See
[Token enrollment with Terraform-issued tokens](/kubernetes-netskope-publisher/admin/how-to/terraform-token-enrollment/).

## Security

- **No API credential in the cluster.** Pods receive only their registration
  token. In token mode the chart renders no `NPA_API_*` settings.
- **Terraform state holds the tokens.** `netskope_npa_publisher_token.token`
  is sensitive but stored in state. Use an encrypted remote backend with
  restricted access.
- **Tokens are single-use.** A token from state or the Secret can't enroll a
  second Publisher once it has been used.
- **Restrict the Secret.** Limit `get` on Secrets in the Publisher namespace
  with Kubernetes RBAC.
- **Helm values are clean.** The release stores the Secret name and a
  fingerprint, never a token.

## Troubleshooting

| Symptom (`enroll` log or pod state) | Cause | Fix |
|---|---|---|
| `No registration token found for replica N` | `workload.replicas` is larger than the number of Secret keys | Make the Terraform count and `replicas` equal |
| `Publisher enrollment failed … single-use` | The token was already spent (lost volume, manual reuse) | `terraform apply -replace='netskope_npa_publisher_token.this["N"]'` |
| `Cannot derive a StatefulSet ordinal from pod name` | `keyBy=ordinal` used outside a StatefulSet | Use `workload.type=statefulset` |
| Terraform: token creation error for a connected Publisher | The tenant won't issue tokens for connected Publishers | Stop the replica first, then replace the token |
| Terraform: Publisher delete fails | Private apps are still attached | Remove the Publisher from the apps' `publishers` lists first |
| Pod `Pending`, PVC `Pending` | No default StorageClass | Set `persistence.storageClass` |
| Pod rejected by admission | The namespace disallows `NET_ADMIN`/`NET_RAW` or `/dev/net/tun` | Allow it, or use `networking_mode = "lwip"` |
| `helm install` error: `hpa.enabled is not supported with enrollment.mode=token` | HPA enabled | Remove `hpa.enabled`; scale with Terraform |

Useful commands:

```bash
kubectl -n npa-publisher describe pod <pod>
kubectl -n npa-publisher logs <pod> -c enroll
kubectl -n npa-publisher logs <pod> -c publisher
kubectl -n npa-publisher get secret npa-publisher-registration-tokens \
  -o jsonpath='{.data}' | jq 'keys'          # key names only
```

## FAQ

**Do I need to change the Terraform provider?** No. The provider's
`netskope_npa_publisher` and `netskope_npa_publisher_token` resources already
do everything this setup needs.

**Why not a Deployment?** Deployment pods are interchangeable and have random
names, so a pod can't pick its own token. StatefulSet ordinals give each pod
a stable key.

**Can I add replicas without restarting the existing ones?** Yes, if you
remove the `npa.netskope.io/registration-tokens-sha256` pod annotation from
`main.tf`. New replicas still start correctly, because they read the Secret
at start-up. You then have to restart a replica yourself after replacing its
token.

**What happens if I run `terraform apply` twice?** Nothing. Tokens are
created once and stay in state. The token resource doesn't refresh from the
API.

**Can several clusters share one Terraform configuration?** Yes. Give each
cluster its own `publisher_name_prefix` and module instance, so Publisher
names and Secrets don't collide.

## Reference

- Example module: [`examples/terraform-token-enrollment`](https://github.com/johnneerdael/kubernetes-netskope-publisher/tree/main/examples/terraform-token-enrollment)
- [Token enrollment with Terraform-issued tokens](/kubernetes-netskope-publisher/admin/how-to/terraform-token-enrollment/) (short version, DaemonSet variant)
- [Workload modes](/kubernetes-netskope-publisher/admin/concepts/workload-modes/)
- [Registration flow](/kubernetes-netskope-publisher/admin/concepts/registration-flow/)
- [Values reference](/kubernetes-netskope-publisher/admin/chart/values-reference/)
- Provider docs: [`netskope_npa_publisher`](https://registry.terraform.io/providers/netskopeoss/netskope/latest/docs/resources/npa_publisher),
  [`netskope_npa_publisher_token`](https://registry.terraform.io/providers/netskopeoss/netskope/latest/docs/resources/npa_publisher_token),
  [`netskope_npa_private_app`](https://registry.terraform.io/providers/netskopeoss/netskope/latest/docs/resources/npa_private_app)
