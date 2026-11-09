output "publishers" {
  description = "Secret key (StatefulSet ordinal or node name) -> Netskope Publisher."
  value = {
    for key, p in netskope_npa_publisher.this : key => {
      publisher_id   = p.publisher_id
      publisher_name = p.publisher_name
    }
  }
}

output "registration_token_secret" {
  description = "Kubernetes Secret holding the Terraform-issued registration tokens."
  value       = "${kubernetes_secret_v1.registration_tokens.metadata[0].namespace}/${kubernetes_secret_v1.registration_tokens.metadata[0].name}"
}
