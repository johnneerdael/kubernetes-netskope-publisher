mock_provider "netskope" {
  mock_resource "netskope_npa_publisher" {
    defaults = { publisher_id = 101 }
  }
  mock_resource "netskope_npa_publisher_token" {
    defaults = { token = "mock-registration-token" }
  }
}
mock_provider "kubernetes" {}
mock_provider "helm" {}

run "statefulset_one_token_per_replica" {
  command = apply
  variables {
    replicas = 3
  }
  assert {
    condition     = join(",", sort(keys(netskope_npa_publisher.this))) == "0,1,2"
    error_message = "expected one publisher per ordinal"
  }
  assert {
    condition     = netskope_npa_publisher.this["2"].publisher_name == "k8s-publisher-2"
    error_message = "publisher name should be <prefix>-<ordinal>"
  }
  assert {
    condition     = nonsensitive(join(",", sort(keys(kubernetes_secret_v1.registration_tokens.data)))) == "0,1,2"
    error_message = "token Secret needs keys 0..N-1"
  }
  assert {
    condition     = length(helm_release.publisher.values) == 1
    error_message = "statefulset should not add node affinity values"
  }
  assert {
    condition = (
      yamldecode(helm_release.publisher.values[0]).registrationToken.keyBy == "ordinal" &&
      yamldecode(helm_release.publisher.values[0]).registrationToken.existingSecret == "npa-publisher-registration-tokens" &&
      yamldecode(helm_release.publisher.values[0]).workload.type == "statefulset" &&
      yamldecode(helm_release.publisher.values[0]).workload.replicas == 3 &&
      yamldecode(helm_release.publisher.values[0]).enrollment.mode == "token" &&
      yamldecode(helm_release.publisher.values[0]).persistence.type == "pvc"
    )
    error_message = "unexpected helm values for statefulset token mode"
  }
  assert {
    condition     = !strcontains(helm_release.publisher.values[0], "mock-registration-token")
    error_message = "tokens must not leak into helm values"
  }
}

run "daemonset_one_token_per_node" {
  command = apply
  variables {
    workload_type = "daemonset"
    node_names    = ["worker-a", "worker-b"]
  }
  assert {
    condition     = nonsensitive(join(",", sort(keys(kubernetes_secret_v1.registration_tokens.data)))) == "worker-a,worker-b"
    error_message = "token Secret needs one key per node"
  }
  assert {
    condition = (
      yamldecode(helm_release.publisher.values[0]).registrationToken.keyBy == "node" &&
      yamldecode(helm_release.publisher.values[0]).persistence.type == "hostPath" &&
      join(",", yamldecode(helm_release.publisher.values[1]).affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchFields[0].values) == "worker-a,worker-b"
    )
    error_message = "unexpected helm values for daemonset token mode"
  }
}

run "daemonset_without_nodes_is_flagged" {
  command = plan
  variables {
    workload_type = "daemonset"
    node_names    = []
  }
  expect_failures = [check.daemonset_needs_nodes]
}
