# =============================================================================
# Netskope Publishers on Kubernetes with Terraform-issued registration tokens
#
# Terraform (with the official netskopeoss/netskope provider) owns the tenant
# side: one netskope_npa_publisher + one netskope_npa_publisher_token per pod.
# The tokens are written to a Kubernetes Secret and the Helm chart runs in
# enrollment.mode=token, so the cluster never holds a Netskope API credential.
#
#   StatefulSet: Secret keys "0".."N-1"   -> registrationToken.keyBy=ordinal
#   DaemonSet:   Secret keys = node names -> registrationToken.keyBy=node
# =============================================================================

locals {
  per_node = var.workload_type == "daemonset"

  # One Publisher per StatefulSet ordinal, or per listed node.
  publisher_keys = local.per_node ? toset(var.node_names) : toset([for i in range(var.replicas) : tostring(i)])

  token_data = { for key, t in netskope_npa_publisher_token.this : key => t.token }

  base_values = {
    workload = {
      type     = var.workload_type
      replicas = var.replicas
    }
    enrollment = {
      mode = "token"
    }
    registrationToken = {
      keyBy          = local.per_node ? "node" : "ordinal"
      existingSecret = kubernetes_secret_v1.registration_tokens.metadata[0].name
    }
    # Tokens are single-use, so every pod keeps its enrollment state:
    # one PVC per replica (StatefulSet) or a per-node directory (DaemonSet).
    persistence = {
      enabled = true
      type    = local.per_node ? "hostPath" : "pvc"
      size    = var.storage_size
    }
    networking = {
      mode = var.networking_mode
    }
    # Roll the pods when a token is added or rotated. Pods whose own token is
    # unchanged skip enrollment; only the rotated replica/node re-enrolls.
    podAnnotations = {
      "npa.netskope.io/registration-tokens-sha256" = nonsensitive(sha256(jsonencode(local.token_data)))
    }
  }

  # DaemonSet: only schedule on nodes that have a token.
  node_affinity_values = {
    affinity = {
      nodeAffinity = {
        requiredDuringSchedulingIgnoredDuringExecution = {
          nodeSelectorTerms = [{
            matchFields = [{
              key      = "metadata.name"
              operator = "In"
              values   = var.node_names
            }]
          }]
        }
      }
    }
  }
}

check "daemonset_needs_nodes" {
  assert {
    condition     = !local.per_node || length(var.node_names) > 0
    error_message = "workload_type = \"daemonset\" needs at least one entry in node_names."
  }
}

resource "netskope_npa_publisher" "this" {
  for_each = local.publisher_keys

  publisher_name                = "${var.publisher_name_prefix}-${each.key}"
  label_ids                     = length(var.publisher_label_ids) > 0 ? var.publisher_label_ids : null
  publisher_upgrade_profiles_id = var.publisher_upgrade_profile_id
}

# Single-use registration token per Publisher. To re-enroll one pod, replace
# just its token, e.g.:
#   terraform apply -replace='netskope_npa_publisher_token.this["1"]'
resource "netskope_npa_publisher_token" "this" {
  for_each = netskope_npa_publisher.this

  publisher_id = each.value.publisher_id
}

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
  }
}

resource "kubernetes_secret_v1" "registration_tokens" {
  metadata {
    name      = "${var.release_name}-registration-tokens"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  type = "Opaque"
  data = local.token_data
}

resource "helm_release" "publisher" {
  name       = var.release_name
  namespace  = kubernetes_namespace_v1.this.metadata[0].name
  repository = "oci://ghcr.io/johnneerdael/charts"
  chart      = "kubernetes-netskope-publisher"
  version    = var.chart_version

  values = concat(
    [yamlencode(local.base_values)],
    local.per_node ? [yamlencode(local.node_affinity_values)] : [],
  )
}
