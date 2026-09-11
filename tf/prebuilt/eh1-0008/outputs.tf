# The bench reads exactly these two names out of `tofu output -json` and
# raises ConfigError if either is missing. Do not rename them.
output "cluster_name" {
  value       = module.cluster.cluster_name
  description = "The name of the created cluster"
}

output "cluster_location" {
  value       = module.cluster.cluster_location
  description = "local for kind"
}

# Non-scalar output; not a placeholder candidate. The static gate reads it from
# the plan to validate override keys against the scene registry.
output "overrides" {
  value       = local.overrides
  description = "The merged scene override map this render passes to scenes"
}
