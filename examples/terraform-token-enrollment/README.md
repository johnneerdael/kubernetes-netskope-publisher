# Terraform-issued registration tokens (token mode)

Run the Publisher Helm chart with registration tokens issued by the official
[`netskopeoss/netskope`](https://registry.terraform.io/providers/netskopeoss/netskope)
Terraform provider. Terraform holds the Netskope API credential. The cluster
receives only single-use registration tokens, so there is no API token or
OAuth2 client in Kubernetes and the chart makes no Netskope API calls.

```
Terraform                                   Kubernetes
─────────                                   ──────────
netskope_npa_publisher["0".."N-1"]
netskope_npa_publisher_token["0".."N-1"] ─► Secret <release>-registration-tokens
                                              keys "0" .. "N-1"
helm_release (enrollment.mode=token,      ─► StatefulSet, N replicas
  registrationToken.keyBy=ordinal)            pod-N reads key "N", PVC-N keeps its state
```

| `workload_type` | Publishers | Secret keys | Chart values |
|---|---|---|---|
| `statefulset` (default) | `var.replicas` | `"0"`..`"N-1"` | `keyBy=ordinal`, one PVC per replica |
| `daemonset` | one per `var.node_names` entry | node names | `keyBy=node`, hostPath state, node affinity |

Step-by-step customer guide: [Deploy Publisher replicas with the Netskope Terraform provider](https://johnneerdael.github.io/kubernetes-netskope-publisher/admin/how-to/terraform-replicas/).

## Usage

```bash
export NETSKOPE_SERVER_URL="https://<tenant>.goskope.com/api/v2"
export NETSKOPE_API_KEY="<api-v2-token>"   # needs Publisher read/write

terraform init
terraform apply -var replicas=3
```

Check the pods:

```bash
kubectl -n npa-publisher get pods
kubectl -n npa-publisher logs npa-publisher-kubernetes-netskope-publisher-0 -c enroll
```

## Day-2 operations

- **Scale**: change `replicas` and apply. Terraform creates (or destroys) the
  matching Publisher and token, updates the Secret, and Helm changes the
  StatefulSet replica count. The chart refuses `hpa.enabled` in token mode
  because an autoscaler cannot get new tokens from Terraform.
- **Re-enroll one replica** (lost certificates, moving tenants): replace only
  that token. The publisher must be disconnected first, because the tenant
  will not issue a token for a connected Publisher.

  ```bash
  terraform apply -replace='netskope_npa_publisher_token.this["1"]'
  ```

  The Secret changes, the pod annotation rolls the pods, and only replica 1
  sees a new token fingerprint and re-enrolls. The other replicas skip
  enrollment. If enrollment with the new token fails, the previous state is
  restored and the `enroll` init container exits with an error.
- **Scale down**: pods above the new count are removed. Their PVCs are kept
  (StatefulSet default). A later scale-up re-enrolls with the new token,
  because the fingerprint differs. Netskope refuses to delete a Publisher that
  still has Private Apps attached, so detach apps before you reduce `replicas`.

## Tests

`tests/example.tftest.hcl` runs offline with mocked providers. It checks the
StatefulSet and DaemonSet layouts and confirms that tokens never reach the
Helm values:

```bash
terraform init && terraform test
```

## Security notes

- `netskope_npa_publisher_token.token` is stored in Terraform state, so
  protect the state backend. Tokens are single-use and are spent on first
  enrollment.
- The Helm release values contain only the Secret name and a SHA-256
  fingerprint, never the tokens.
