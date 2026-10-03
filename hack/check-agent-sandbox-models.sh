#!/usr/bin/env bash
# Check that the agent-sandbox image's gemini CLI calls the model it is asked for.
#
# gemini-cli rewrites model ids before calling the backend (see the settings step
# in hack/agent-sandbox.Dockerfile), and its stream-json `init` event reports the
# requested id either way. The only reliable signal is the per-model token count
# in the `result` event. This runs one tiny prompt per model with the same argv
# and env the gemini_cli harness uses and fails if any run bills another model.
#
#   hack/check-agent-sandbox-models.sh IMAGE PROJECT [MODEL...]
#
# Needs docker, python3 and Vertex credentials reachable from the container
# (on a GCE VM the metadata server via --network host). Defaults to the Gemini
# models used in the live matrix and the neighbouring flash ids.
set -euo pipefail

image=${1:?usage: $0 IMAGE PROJECT [MODEL...]}
project=${2:?usage: $0 IMAGE PROJECT [MODEL...]}
shift 2
models=("$@")
if [ ${#models[@]} -eq 0 ]; then
  models=(gemini-3.5-flash gemini-3.7-flash gemini-3.8-flash gemini-3.5-flash-lite)
fi

status=0
for model in "${models[@]}"; do
  out=$(timeout 600 docker run --rm --network host -e HOME=/workspace \
    -e OTEL_TRACES_EXPORTER=none -e OTEL_METRICS_EXPORTER=none -e OTEL_LOGS_EXPORTER=none -e OTEL_SDK_DISABLED=true \
    -e GOOGLE_GENAI_USE_VERTEXAI=true -e GOOGLE_CLOUD_PROJECT="$project" -e GOOGLE_CLOUD_LOCATION=global \
    -e GEMINI_MODEL="$model" --entrypoint gemini "$image" \
    --output-format stream-json --skip-trust --approval-mode yolo --extensions= \
    -p "Reply with the single word ok" 2>/dev/null) || true
  line=$(printf '%s\n' "$out" | python3 -c '
import json, sys
model = sys.argv[1]
init = billed = None
for raw in sys.stdin:
    try:
        event = json.loads(raw)
    except ValueError:
        continue
    if event.get("type") == "init":
        init = event.get("model")
    if event.get("type") == "result":
        billed = sorted((event.get("stats", {}).get("models") or {}))
ok = billed == [model]
print(("ok  " if ok else "FAIL") + f" requested={model} init={init} billed={billed}")
sys.exit(0 if ok else 1)
' "$model") && echo "$line" || { echo "$line"; status=1; }
done
exit $status
