# Trusted observation lives outside local.edit_namespaces. The solver can discover
# these objects through view but cannot mutate them, exec this Pod, or read tokens.
resource "kubernetes_namespace_v1" "observer" {
  metadata {
    name = "task-observer"
  }
}

resource "kubernetes_service_account_v1" "observer" {
  metadata {
    name      = "workload-observer"
    namespace = kubernetes_namespace_v1.observer.metadata[0].name
  }
}

resource "kubernetes_role_v1" "observer" {
  metadata {
    name      = "workload-observer"
    namespace = "default"
  }
  rule {
    api_groups = [""]
    resources  = ["pods", "services", "configmaps"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["discovery.k8s.io"]
    resources  = ["endpointslices"]
    verbs      = ["get", "list"]
  }
}

resource "kubernetes_role_binding_v1" "observer" {
  metadata {
    name      = "workload-observer"
    namespace = "default"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.observer.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.observer.metadata[0].name
    namespace = kubernetes_namespace_v1.observer.metadata[0].name
  }
}

resource "kubernetes_config_map_v1" "observer_code" {
  metadata {
    name      = "workload-observer-code"
    namespace = kubernetes_namespace_v1.observer.metadata[0].name
  }
  immutable = true
  data = {
    "probe.py" = file("${path.module}/observer/probe.py")
  }
}

resource "kubernetes_pod_v1" "observer" {
  metadata {
    name      = "workload-observer"
    namespace = kubernetes_namespace_v1.observer.metadata[0].name
  }
  spec {
    service_account_name = kubernetes_service_account_v1.observer.metadata[0].name
    init_container {
      name    = "capture-original-identities"
      image   = "python:3.13.7-alpine3.22"
      command = ["python", "/observer/probe.py", "capture"]
      volume_mount {
        name       = "code"
        mount_path = "/observer"
        read_only  = true
      }
      volume_mount {
        name       = "baseline"
        mount_path = "/baseline"
      }
    }
    container {
      name    = "observer"
      image   = "python:3.13.7-alpine3.22"
      command = ["python", "-c", "import time; time.sleep(2147483647)"]
      volume_mount {
        name       = "code"
        mount_path = "/observer"
        read_only  = true
      }
      volume_mount {
        name       = "baseline"
        mount_path = "/baseline"
        read_only  = true
      }
    }
    volume {
      name = "code"
      config_map {
        name = kubernetes_config_map_v1.observer_code.metadata[0].name
      }
    }
    volume {
      name = "baseline"
      empty_dir {}
    }
  }
  depends_on = [kubectl_manifest.objects, kubernetes_role_binding_v1.observer]
}

# RBAC namespace separation also needs to rule out host-level Pod escape routes.
# Own only these labels on the existing namespace; retain all unrelated labels.
resource "kubernetes_labels" "solver_pod_security" {
  api_version = "v1"
  kind        = "Namespace"
  metadata {
    name = "default"
  }
  labels = {
    "pod-security.kubernetes.io/enforce"         = "baseline"
    "pod-security.kubernetes.io/enforce-version" = "latest"
  }
}
