locals {
  overrides = {}
  objects = jsondecode(<<-JSON
{
  "default/ConfigMap/workload-release-r2": {
    "apiVersion": "v1",
    "kind": "ConfigMap",
    "metadata": {
      "name": "workload-release-r2",
      "namespace": "default",
      "labels": {
        "app": "workload",
        "release": "2026.09-r2"
      }
    },
    "data": {
      "index.html": "{\"release\": \"2026.09-r2\", \"api_version\": 2, \"currency\": \"USD\", \"price_minor\": 1299}\n",
      "release.json": "{\n  \"release\": \"2026.09-r2\",\n  \"deployment\": \"workload-current\",\n  \"image\": \"nginx:1.27.4\",\n  \"readyReplicas\": 2,\n  \"responseContract\": {\n    \"release\": \"2026.09-r2\",\n    \"api_version\": 2,\n    \"currency\": \"USD\",\n    \"price_minor\": 1299\n  },\n  \"delivery\": {\n    \"phase\": \"awaiting-service-cutover\",\n    \"service\": \"workload\",\n    \"operation\": \"traffic-selection-only; existing release Pods remain in place\",\n    \"rollbackRelease\": \"2026.08-r1\",\n    \"rollbackReadyReplicas\": 1\n  }\n}\n"
    }
  },
  "default/Deployment/workload-current": {
    "apiVersion": "apps/v1",
    "kind": "Deployment",
    "metadata": {
      "name": "workload-current",
      "namespace": "default",
      "labels": {
        "app": "workload",
        "release": "2026.09-r2"
      },
      "annotations": {
        "delivery.example.net/release-artifact": "configmap/workload-release-r2:release.json"
      }
    },
    "spec": {
      "replicas": 2,
      "selector": {
        "matchLabels": {
          "app": "workload",
          "release": "2026.09-r2"
        }
      },
      "template": {
        "metadata": {
          "labels": {
            "app": "workload",
            "release": "2026.09-r2"
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
                "name": "workload-release-r2"
              }
            }
          ]
        }
      }
    }
  },
  "default/ConfigMap/workload-release-r1": {
    "apiVersion": "v1",
    "kind": "ConfigMap",
    "metadata": {
      "name": "workload-release-r1",
      "namespace": "default",
      "labels": {
        "app": "workload",
        "release": "2026.08-r1"
      }
    },
    "data": {
      "index.html": "{\"release\": \"2026.08-r1\", \"api_version\": 1, \"price\": \"$12.99\"}\n",
      "release.json": "{\n  \"release\": \"2026.08-r1\",\n  \"deployment\": \"workload-retained\",\n  \"image\": \"nginx:1.27.4\",\n  \"readyReplicas\": 1,\n  \"responseContract\": {\n    \"release\": \"2026.08-r1\",\n    \"api_version\": 1,\n    \"price\": \"$12.99\"\n  },\n  \"delivery\": {\n    \"phase\": \"retained-rollback\",\n    \"service\": \"workload\",\n    \"operation\": \"traffic-selection-only; existing release Pods remain in place\",\n    \"rollbackRelease\": \"2026.08-r1\",\n    \"rollbackReadyReplicas\": 1\n  }\n}\n"
    }
  },
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
      "replicas": 1,
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
  },
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
        "app": "workload"
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
  )
}
