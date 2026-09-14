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
