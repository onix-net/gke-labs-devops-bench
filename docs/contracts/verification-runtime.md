# Composing verification contracts

This runtime combines the semantic JSON verifier at
`662d34f34890b416f04aaec72caa994110a1230e` with the existing task-owned solver RBAC
contract at `c964a2b6990fcd3625a0af1e0dc8ba5ba670f6f2`. It adds no second mechanism
for selecting solver permissions.

Set `agent_rbac: task` at the task card's top level. For a diagnostic using the
same bootstrap, call `provision_agent_credentials` with `agent_rbac="task"`,
`pod_security="baseline"`, a `NetworkPlan` with an explicit `kubectl_context`,
and a bounded `token_ttl_sec`. The helper verifies the existing live
`bench-system/bench-agent`, installs baseline pod security, and mints its token.
Do not call `ensure_agent_identity` first: that is the legacy benchmark-mode
helper and adds cluster-wide permissions.

Task mode adds no RBAC and never falls back to the administrator credential. It
refuses the known broad legacy bindings when their direct or standard-group
subjects include the solver. Migration is deliberately a refusal, not automatic
binding deletion. Start a clean task-provisioned cluster, or remove an owned old
grant through reviewed provisioning before retrying. Unknown custom grants remain
the task's responsibility.

This is not a complete effective-permission audit. The trusted task provisioner
must establish grants before bootstrap; no concurrent identity/grant mutation is
supported during that handoff. Inspect operator permissions and all credentials
reachable through allowed Secrets, workload changes, exec and ServiceAccount use.
Application namespace isolation only holds when those credentials cannot modify
protected infrastructure. Test the final policy with the actual solver token:
ordinary repair succeeds, while impersonation, privileged token requests,
cross-namespace writes and protected-policy mutation fail.

The independent semantic JSON contract uses `resource_property` with `json_path`
to parse and select within one JSON string. Expected values remain host-held;
structural equality tolerates formatting and key-order changes but rejects
malformed JSON, duplicate keys, nonfinite numbers and imprecise numeric matches.
Neither that comparison nor a protected observer can compensate for a solver
credential that can disable the platform's protection.
