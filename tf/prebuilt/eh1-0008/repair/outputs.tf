output "overrides" {
  value       = local.overrides
  description = "Scene override keys to values"
}

output "objects" {
  value       = local.objects
  description = "namespace/kind/name => full manifest"
}
