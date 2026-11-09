variable "kubeconfig_path" {
  description = "Path to the kubeconfig used by the kubernetes and helm providers."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "kubeconfig context to use. Null uses the current context."
  type        = string
  default     = null
}

variable "namespace" {
  description = "Namespace for the Publisher release and its token Secret."
  type        = string
  default     = "npa-publisher"
}

variable "release_name" {
  description = "Helm release name."
  type        = string
  default     = "npa-publisher"
}

variable "chart_version" {
  description = "Version of the kubernetes-netskope-publisher chart (token-mode StatefulSet support needs >= 1.6.0)."
  type        = string
  default     = "1.6.0"
}

variable "publisher_name_prefix" {
  description = "Netskope Publisher names are \"<prefix>-<ordinal>\" (StatefulSet) or \"<prefix>-<node name>\" (DaemonSet)."
  type        = string
  default     = "k8s-publisher"
}

variable "workload_type" {
  description = "statefulset: var.replicas Publishers, one token per replica. daemonset: one Publisher per entry in var.node_names."
  type        = string
  default     = "statefulset"

  validation {
    condition     = contains(["statefulset", "daemonset"], var.workload_type)
    error_message = "workload_type must be \"statefulset\" or \"daemonset\"."
  }
}

variable "replicas" {
  description = "StatefulSet replica count. Terraform issues exactly this many Publishers and registration tokens."
  type        = number
  default     = 2

  validation {
    condition     = var.replicas >= 1 && floor(var.replicas) == var.replicas
    error_message = "replicas must be a positive whole number."
  }
}

variable "node_names" {
  description = "DaemonSet only: Kubernetes node names (kubectl get nodes) that each run one Publisher."
  type        = list(string)
  default     = []
}

variable "networking_mode" {
  description = "Chart networking.mode: pod, lwip, or host (host is DaemonSet-only)."
  type        = string
  default     = "pod"
}

variable "storage_size" {
  description = "Per-replica PVC size for StatefulSet persistence."
  type        = string
  default     = "1Gi"
}

variable "publisher_label_ids" {
  description = "Optional Netskope label IDs for each Publisher (some tenants require labels)."
  type        = list(string)
  default     = []
}

variable "publisher_upgrade_profile_id" {
  description = "Optional Netskope Publisher upgrade profile ID. Null keeps the tenant default."
  type        = number
  default     = null
}
