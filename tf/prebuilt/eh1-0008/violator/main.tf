module "seed" {
  source = "../seed"
}

locals {
  overrides = {}
  objects = merge(module.seed.objects, jsondecode(<<-JSON
{
  "default/Deployment/workload-retained": {
    "apiVersion": "apps/v1",
    "kind": "Deployment",
    "metadata": {
      "name": "workload-retained",
      "namespace": "default",
      "labels": {
        "app": "workload",
        "release": "2026.08-r1"
      },
      "annotations": {
        "delivery.example.net/release-artifact": "configmap/workload-release-r1:release.json"
      }
    },
    "spec": {
      "replicas": 2,
      "selector": {
        "matchLabels": {
          "app": "workload",
          "release": "2026.08-r1"
        }
      },
      "template": {
        "metadata": {
          "labels": {
            "app": "workload",
            "release": "2026.08-r1"
          }
        },
        "spec": {
          "automountServiceAccountToken": false,
          "containers": [
            {
              "name": "nginx",
              "image": "nginx:1.27.4",
              "imagePullPolicy": "IfNotPresent",
              "ports": [
                {
                  "name": "http",
                  "containerPort": 80
                }
              ],
              "readinessProbe": {
                "httpGet": {
                  "path": "/",
                  "port": "http"
                },
                "periodSeconds": 2,
                "timeoutSeconds": 1
              },
              "volumeMounts": [
                {
                  "name": "release",
                  "mountPath": "/usr/share/nginx/html",
                  "readOnly": true
                }
              ]
            }
          ],
          "volumes": [
            {
              "name": "release",
              "configMap": {
                "name": "workload-release-r1"
              }
            }
          ]
        }
      }
    }
  }
}
JSON
  ))
}
