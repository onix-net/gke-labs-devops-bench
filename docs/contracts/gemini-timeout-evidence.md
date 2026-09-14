# Preserve partial CLI evidence on timeout

A real 0019 solver attempt reached its 900-second limit during a web-search request.
The subprocess captured partial stdout, but the Gemini adapter returned an empty
error result without parsing it. Stagehand therefore recorded an empty-trajectory
void. The operator retained 22 tool invocations separately.

- [x] Recover completed and pending tool calls from captured timeout stdout.
- [x] Retain explicit timeout/error metadata and a bounded stderr tail.
- [x] Prove partial-stream recovery with a real short subprocess timeout and
      replay the retained live stream; run unit suite and independent review.
- [x] Publish as a small follow-up to the composed runtime; do not alter historical
      attempt evidence, task pins or gate results and do not launch another solver.

Reuse the existing Claude adapter's capture/parse pattern. No new parser, scoring
rule or automatic retry is introduced. Search endpoint reliability remains a
separate unresolved issue. Future attempts can expose partial trajectories to the
existing classifier; historical empty-trajectory voids remain unchanged.

Validation: 1,877 unit tests passed; Ruff formatting and lint passed; independent
review found no actionable issues. The license check reports 52 existing files
without headers; none is changed by this patch. Historical attempt remains VOID.

## Native stream persistence

Every run now persists the agent's raw native stream alongside the parsed
trajectory, on both a successful completion and a timeout. `AgentResult`
carries the full, untruncated `raw_stdout` and `raw_stderr` the agent process
produced. The harness writes these under the run directory as
`agent-stream.jsonl` and `agent-stderr.log`, each only when non-empty, and
never re-parses or reformats them. This keeps the original stream-json events
and their native timestamps available even when the parsed trajectory is
partial or empty.

The `timed_out` and `returncode` values that were previously confined to
`AgentResult.metadata`, and so never reached `results.json`, now also appear
as top-level fields on every results row. A clean run records `timed_out:
false` and `returncode: null`.
