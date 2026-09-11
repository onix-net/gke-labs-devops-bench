# The five variables the bench's kind provider injects. An undeclared injected
# variable is dropped with a warning by the bench's tofu deployer.
variable "infra_provider" {
  type        = string
  description = "The target provider (kind)"
  default     = "kind"
}

variable "project_id" {
  type        = string
  description = "GCP project id, or local-kind"
  default     = "local-kind"
}

variable "location" {
  type        = string
  description = "Cluster location, or local"
  default     = "local"
}

variable "cluster_name" {
  type        = string
  description = "Name of the kind cluster to create; the bench sets it per run"
}

variable "kubeconfig_path" {
  type        = string
  description = "Path the kind module writes the kubeconfig to; the bench sandbox reads it"
  default     = "~/.kube/config"
}

# Stack-local variables.
variable "node_count" {
  type        = number
  description = "Nodes (1 control plane plus workers). The kind module's own default is 3."
  default     = 1
  nullable    = false
}

variable "disable_default_cni" {
  type        = bool
  description = "Disable kindnet and install Calico so NetworkPolicy is enforced"
  default     = true
}

variable "arm" {
  type        = string
  description = "Which arm to render: base (seed), oracle (seed plus repair), violator (seed plus violator)"
  default     = "base"

  validation {
    condition     = contains(["base", "oracle", "violator"], var.arm)
    error_message = "arm must be one of base, oracle, violator."
  }
}
