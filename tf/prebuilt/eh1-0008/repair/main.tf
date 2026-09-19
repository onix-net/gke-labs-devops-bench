module "seed" {
  source = "../seed"
}

locals {
  overrides = {}
  objects = merge(module.seed.objects, jsondecode(<<-JSON
{
  "default/Service/workload": {
    "apiVersion": "v1",
    "kind": "Service",
    "metadata": {
      "name": "workload",
      "namespace": "default",
      "annotations": {
        "delivery.example.net/release-artifact": "configmap/workload-release-r2:release.json"
      }
    },
    "spec": {
      "type": "ClusterIP",
      "selector": {
        "app": "workload",
        "release": "2026.09-r2"
      },
      "ports": [
        {
          "name": "http",
          "port": 80,
          "targetPort": 80,
          "protocol": "TCP"
        }
      ]
    }
  }
}
JSON
  ))
}
