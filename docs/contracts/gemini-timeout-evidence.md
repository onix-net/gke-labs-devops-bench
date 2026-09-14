# Preserve partial CLI evidence on timeout

A real0019solver attempt reached its900-second limit during a web-search request.
The subprocess captured partial stdout, but the Gemini adapter returned an empty
error result without parsing it. Stagehand therefore recorded an empty-trajectory
void. The operator retained22 tool invocations separately.

- [ ] Recover completed and pending tool calls from captured timeout stdout.
- [ ] Retain explicit timeout/error metadata and a bounded stderr tail.
- [ ] Prove partial-stream recovery with a real short subprocess timeout and
      replay the retained live stream; run unit suite and independent review.
- [ ] Publish as a small follow-up to the composed runtime; do not alter historical
      attempt evidence, task pins or gate results and do not launch another solver.

Reuse the existing Claude adapter's capture/parse pattern. No new parser, scoring
rule or automatic retry is introduced. Search endpoint reliability remains a
separate unresolved issue. Future attempts can expose partial trajectories to the
existing classifier; historical empty-trajectory voids remain unchanged.
