"""Task-owned observer. Immutable code and baseline live outside solver edit scope.

An observation prints PASS/FAIL and exits zero. API/auth/setup failures exit nonzero
so native pod_exec reports instrumentation error rather than an intended task fail.
"""

import json
import ssl
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

CURRENT = "2026.09-r2"
RETAINED = "2026.08-r1"
CURRENT_BODY = {"release": CURRENT, "api_version": 2, "currency": "USD", "price_minor": 1299}
RETAINED_BODY = {"release": RETAINED, "api_version": 1, "price": "$12.99"}
CAPACITY = 2
BASELINE = Path("/baseline/identity.json")


def api(path):
    token = Path("/var/run/secrets/kubernetes.io/serviceaccount/token").read_text()
    ca = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
    req = urllib.request.Request(
        "https://kubernetes.default.svc" + path, headers={"Authorization": "Bearer " + token}
    )
    try:
        with urllib.request.urlopen(
            req, context=ssl.create_default_context(cafile=ca), timeout=3
        ) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return None
        raise


def core(kind, name=None):
    return api("/api/v1/namespaces/default/" + kind + ("/" + name if name else ""))


def apps(kind, name=None):
    return api("/apis/apps/v1/namespaces/default/" + kind + ("/" + name if name else ""))


def owned(obj, uid):
    return any(
        o.get("uid") == uid and o.get("controller") is True
        for o in obj.get("metadata", {}).get("ownerReferences", [])
    )


def ready(pod):
    return not pod["metadata"].get("deletionTimestamp") and any(
        c.get("type") == "Ready" and c.get("status") == "True"
        for c in pod.get("status", {}).get("conditions", [])
    )


def response_ok(body):
    return body == CURRENT_BODY


def pool_identity_errors(members, expected_uids, expected_capacity):
    errors = []
    uids = [p["uid"] for p in members]
    if len(uids) != expected_capacity or len(set(uids)) != len(uids):
        errors.append("ready pool capacity or duplicate endpoint mismatch")
    if set(uids) != set(expected_uids):
        errors.append("ready pool is not the captured current-release Pod identity set")
    if any(p["release"] != CURRENT for p in members):
        errors.append("ready pool includes an incompatible release")
    return errors


def http(url):
    try:
        req = urllib.request.Request(url, headers={"Connection": "close"})
        # A new opener/request each time, without environment proxy routing.
        with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(
            req, timeout=2
        ) as response:
            return response.status == 200 and response_ok(json.loads(response.read(16384)))
    except (urllib.error.URLError, TimeoutError, ValueError, ConnectionError):
        return False


def capture():
    deployments = {
        name: apps("deployments", name) for name in ["workload-current", "workload-retained"]
    }
    service = core("services", "workload")
    pods = core("pods")["items"]
    replicasets = apps("replicasets")["items"]
    current = deployments["workload-current"]
    current_rs = {
        rs["metadata"]["uid"] for rs in replicasets if owned(rs, current["metadata"]["uid"])
    }
    current_pods = [p for p in pods if any(owned(p, uid) for uid in current_rs) and ready(p)]
    if len(current_pods) != CAPACITY or not service or any(not d for d in deployments.values()):
        raise RuntimeError("initial release rollout not ready for identity capture")
    data = {
        "service_uid": service["metadata"]["uid"],
        "current_pod_uids": [p["metadata"]["uid"] for p in current_pods],
        "deployment_uids": {name: d["metadata"]["uid"] for name, d in deployments.items()},
        "templates": {name: d["spec"]["template"] for name, d in deployments.items()},
        "config_data": {
            name: core("configmaps", name)["data"]
            for name in ["workload-release-r2", "workload-release-r1"]
        },
    }
    BASELINE.write_text(json.dumps(data))


def membership(baseline):
    service = core("services", "workload")
    if not service or service["metadata"]["uid"] != baseline["service_uid"]:
        return ["original Service identity was removed or replaced"], []
    if service["spec"].get("type", "ClusterIP") != "ClusterIP" or service["spec"].get(
        "externalName"
    ):
        return ["Service is no longer the original ClusterIP route"], []
    ports = service["spec"].get("ports", [])
    if (
        len(ports) != 1
        or ports[0].get("port") != 80
        or ports[0].get("targetPort") not in [80, "http"]
    ):
        return ["Service HTTP port contract changed"], []
    slices = api(
        "/apis/discovery.k8s.io/v1/namespaces/default/endpointslices?labelSelector=kubernetes.io%2Fservice-name%3Dworkload"
    )["items"]
    pods = {p["metadata"]["name"]: p for p in core("pods")["items"]}
    replica_sets = {r["metadata"]["uid"]: r for r in apps("replicasets")["items"]}
    errors, members, urls = [], [], []
    for endpoint_slice in slices:
        if not owned(endpoint_slice, baseline["service_uid"]):
            errors.append("EndpointSlice is not owned by the original Service")
        if endpoint_slice.get("addressType") != "IPv4":
            errors.append("unexpected endpoint address type")
        slice_ports = endpoint_slice.get("ports", [])
        if len(slice_ports) != 1 or slice_ports[0].get("port") != 80:
            errors.append("EndpointSlice does not route to HTTP port 80")
        for endpoint in endpoint_slice.get("endpoints", []):
            # nil readiness is usable by consumers; do not omit it. Terminating
            # endpoints may be used during drain, so reject instead of hiding them.
            conditions = endpoint.get("conditions", {})
            if conditions.get("ready") is False:
                continue
            if conditions.get("terminating"):
                errors.append("terminating endpoint remains in routable pool")
            ref = endpoint.get("targetRef", {})
            pod = pods.get(ref.get("name"))
            if (
                ref.get("kind") != "Pod"
                or ref.get("namespace") != "default"
                or not pod
                or pod["metadata"]["uid"] != ref.get("uid")
                or not ready(pod)
            ):
                errors.append("endpoint does not resolve to an actual Ready Pod identity")
                continue
            owner = next(
                (
                    o["uid"]
                    for o in pod["metadata"].get("ownerReferences", [])
                    if o.get("controller")
                ),
                None,
            )
            rs = replica_sets.get(owner)
            if not rs or not owned(rs, baseline["deployment_uids"]["workload-current"]):
                errors.append("endpoint ownership does not resolve to current Deployment")
            addresses = endpoint.get("addresses", [])
            if addresses != [pod.get("status", {}).get("podIP")]:
                errors.append("endpoint address does not match actual Pod IP")
            members.append(
                {
                    "uid": pod["metadata"]["uid"],
                    "release": pod["metadata"].get("labels", {}).get("release"),
                }
            )
            urls.extend("http://" + address + "/" for address in addresses)
    errors.extend(pool_identity_errors(members, baseline["current_pod_uids"], CAPACITY))
    current = apps("deployments", "workload-current")
    if (
        not current
        or current["metadata"]["uid"] != baseline["deployment_uids"]["workload-current"]
        or current["spec"]["template"] != baseline["templates"]["workload-current"]
    ):
        errors.append("current release workload identity or template changed")
    for name in ["workload-release-r2", "workload-release-r1"]:
        cm = core("configmaps", name)
        if not cm or cm.get("data") != baseline["config_data"][name]:
            errors.append("deployed release artifact content changed: " + name)
    return errors, urls


def pool():
    baseline = json.loads(BASELINE.read_text())
    errors, urls = membership(baseline)
    if errors:
        return errors
    # Pool enumeration is deterministic; HTTP sampling is additional behavioral
    # evidence, never a substitute. Fresh connections cover a six-second window.
    for sample in range(3):
        for url in urls + ["http://workload.default.svc.cluster.local/"]:
            if not http(url):
                return ["semantic HTTP response failed: " + url]
        if sample < 2:
            time.sleep(3)
    final_errors, final_urls = membership(baseline)
    if set(final_urls) != set(urls):
        final_errors.append("backend addresses changed during observation window")
    return final_errors


def preservation():
    baseline = json.loads(BASELINE.read_text())
    errors = []
    for name, replicas in [("workload-current", CAPACITY), ("workload-retained", 1)]:
        deployment = apps("deployments", name)
        if not deployment:
            errors.append(name + " removed")
            continue
        if deployment["metadata"]["uid"] != baseline["deployment_uids"][name]:
            errors.append(name + " replaced")
        if deployment["spec"].get("replicas") != replicas:
            errors.append(name + " capacity changed")
        if deployment["spec"]["template"] != baseline["templates"][name]:
            errors.append(name + " release template changed")
        if deployment.get("status", {}).get("readyReplicas", 0) != replicas:
            errors.append(name + " no longer ready at its release capacity")
    return errors


if __name__ == "__main__":
    if sys.argv[1] == "capture":
        capture()
    else:
        failures = pool() if sys.argv[1] == "pool" else preservation()
        print("FAIL " + "; ".join(failures) if failures else "PASS")
