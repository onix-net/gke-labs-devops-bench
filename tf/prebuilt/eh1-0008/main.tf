# Stack template (spec 5.3). Every task starts from this skeleton.
#
# Provider pins are exact. helm and kubernetes stay on 2.x because every
# living-stacks scene pins hashicorp/helm "~> 2.15.0" and was written against
# kubernetes 2.x. kind and null match the bench's own prebuilt pins.
terraform {
  required_version = ">= 1.8.0"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "= 0.11.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "= 2.4.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "= 2.38.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "= 2.17.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "= 3.3.1"
    }
  }
}

provider "kind" {}

# The kind module is sourced from the bench fork by git at the pinned sha,
# never via the dispatch module tf/modules/cluster, whose GKE branch brings the
# google provider into every init.
module "cluster" {
  source = "../../modules/cluster/kind"

  cluster_name        = var.cluster_name
  project_id          = var.project_id
  location            = var.location
  kubeconfig_path     = var.kubeconfig_path
  node_count          = var.node_count
  disable_default_cni = var.disable_default_cni
}

# Providers are configured from the cluster module's outputs, never from a
# kubeconfig file, so they depend on the cluster and are configured after it
# exists during apply. lazy_load lets the kubectl provider plan while host and
# certs are still unknown; kubernetes and helm defer on their own.
provider "kubectl" {
  host                   = module.cluster.endpoint
  cluster_ca_certificate = module.cluster.cluster_ca_certificate
  client_certificate     = module.cluster.client_certificate
  client_key             = module.cluster.client_key
  load_config_file       = false
  lazy_load              = true
  apply_retry_count      = 5
}

provider "kubernetes" {
  host                   = module.cluster.endpoint
  cluster_ca_certificate = module.cluster.cluster_ca_certificate
  client_certificate     = module.cluster.client_certificate
  client_key             = module.cluster.client_key
}

provider "helm" {
  kubernetes {
    host                   = module.cluster.endpoint
    cluster_ca_certificate = module.cluster.cluster_ca_certificate
    client_certificate     = module.cluster.client_certificate
    client_key             = module.cluster.client_key
  }
}

# Arms. seed/, repair/, violator/ are modules with two outputs each. They are
# composed by precedence, not sequence: the same object exists once per arm
# with the content that arm calls for. merge() is shallow at the objects key,
# so a repair or violator entry must be the complete object, not a patch.
module "seed" {
  source = "./seed"
}

module "repair" {
  source = "./repair"
}

module "violator" {
  source = "./violator"
}

locals {
  overrides = merge(
    module.seed.overrides,
    var.arm == "oracle" ? module.repair.overrides : {},
    var.arm == "violator" ? module.violator.overrides : {},
  )

  # Every arm supplies the same current/retained release and Service keys. Select
  # the complete map: heterogeneous manifest objects cannot coerce to {} in
  # the conditional merge pattern used by a single-kind task.
  objects = var.arm == "oracle" ? module.repair.objects : (
    var.arm == "violator" ? module.violator.objects : module.seed.objects
  )

  # Namespaces the solver may edit. A task lists its scene namespaces and any
  # namespace its seed creates. RBAC changes are task edits.
  edit_namespaces = ["default"]
}

# Scenes are sourced from living-stacks by git at the pinned sha, each taking
# the scene's base profile plus local.overrides. Example:
#
# module "scene_streaming" {
#   source                = "git::https://github.com/geojaz/living-stacks.git//streaming/tf/scene?ref=5aaf2671b11e377d157220a8ac383553de06ebf1"
#   kubeconfig            = var.kubeconfig_path
#   profile_json_override = lookup(local.overrides, "profile_json_override", null)
#   depends_on            = [module.cluster]
# }

resource "kubectl_manifest" "objects" {
  depends_on = [kubernetes_labels.solver_pod_security]
  for_each   = local.objects

  yaml_body         = yamlencode(each.value)
  server_side_apply = true

  # Wait for both real release Deployments before capturing protected identities.
  # The fault is mixed routing membership; all application ports are correct.
  wait             = true
  wait_for_rollout = each.value.kind == "Deployment"
}

# Solver RBAC. Creates bench-system/bench-agent, the ServiceAccount the bench
# sandbox mints its token for. Applied after the scenes and the arm objects so
# the edit namespaces exist.
module "bench_agent" {
  source = "git::https://github.com/geojaz/living-stacks.git//platform/bench_agent?ref=5aaf2671b11e377d157220a8ac383553de06ebf1"

  edit_namespaces = local.edit_namespaces
  cluster_read    = true
  extra_rules     = []

  depends_on = [module.cluster, kubectl_manifest.objects]
}
