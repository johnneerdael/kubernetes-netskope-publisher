terraform {
  required_version = ">= 1.5"

  required_providers {
    netskope = {
      source  = "netskopeoss/netskope"
      version = ">= 0.4.13"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0"
    }
  }
}

# Netskope credentials live only in Terraform: NETSKOPE_SERVER_URL and
# NETSKOPE_API_KEY (or the arguments below). Nothing in the cluster needs them.
provider "netskope" {}

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}

provider "helm" {
  kubernetes = {
    config_path    = var.kubeconfig_path
    config_context = var.kube_context
  }
}
