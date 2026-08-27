# Copyright 2026 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This dispatch module instantiates only one concrete cluster sub-module and
# declares no concrete-provider requirements of its own: each sub-module owns
# its provider (google in ./gke, tehcyx/kind in ./kind), so a KinD-only run does
# not pull in the GCP provider plugin.

module "gke" {
  source                   = "./gke"
  count                    = var.infra_provider == "gcp" ? 1 : 0
  project_id               = var.project_id
  location                 = var.location != "" ? var.location : "us-central1-a"
  cluster_name             = var.cluster_name
  node_count               = var.node_count
  machine_type             = var.machine_type != "" ? var.machine_type : "e2-standard-2"
  kubernetes_version       = var.kubernetes_version
  enable_workload_identity = var.enable_workload_identity
  agent_service_account    = var.agent_service_account
  enable_iap_ssh           = var.enable_iap_ssh
  gpu_type                 = var.gpu_type
  gpu_count                = var.gpu_count
}

module "kind" {
  source              = "./kind"
  count               = var.infra_provider == "kind" ? 1 : 0
  cluster_name        = var.cluster_name
  kubeconfig_path     = var.kubeconfig_path
  node_image          = var.node_image
  project_id          = var.project_id
  location            = var.location != "" ? var.location : "local"
  node_count          = var.node_count
  disable_default_cni = var.disable_default_cni
  pod_subnet          = var.pod_subnet
}


module "vcluster" {
  source = "./vcluster"
  count  = var.infra_provider == "vcluster" ? 1 : 0

  cluster_name = var.cluster_name
  location     = var.location != "" ? var.location : "local"
  # Unique host namespace per virtual cluster; the module's static default
  # collides when two vclusters share one host.
  namespace = "vcluster-${var.cluster_name}"

  host_kubecontext     = var.host_kubecontext
  host_kubeconfig_path = var.host_kubeconfig_path
  service_cidr         = var.vcluster_service_cidr
}


# vcluster delivers its kubeconfig only as the vc-<name> Secret on the host.
# File-based consumers (the factory's controls scripts pass
# -var kubeconfig_path=<tmp> and read that file) keep the same contract the
# kind module provides: extract the secret to var.kubeconfig_path once the
# module's own API-stability wait has passed.
resource "terraform_data" "vcluster_kubeconfig_file" {
  count      = var.infra_provider == "vcluster" ? 1 : 0
  depends_on = [module.vcluster]

  triggers_replace = {
    cluster = var.cluster_name
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      ctx_flag=""
      if [ -n "${var.host_kubecontext}" ]; then
        ctx_flag="--context=${var.host_kubecontext}"
      fi
      out_path="${pathexpand(var.kubeconfig_path)}"
      mkdir -p "$(dirname "$out_path")"
      kubectl --kubeconfig="${pathexpand(var.host_kubeconfig_path)}" $ctx_flag \
        -n "vcluster-${var.cluster_name}" get secret "vc-${var.cluster_name}" \
        --template='{{.data.config}}' | base64 -d > "$out_path"
      chmod 600 "$out_path"
    EOT
  }
}
