#!/usr/bin/env bash
set -uo pipefail

SCRATCH="$(cd "$(dirname "$0")" && pwd)"
KEY_FILE="$HOME/.secrets/keep/fireworks.key"
URL="https://api.fireworks.ai/inference/v1/chat/completions"
MODEL="accounts/fireworks/models/glm-5p3-flash"
HDR="$SCRATCH/fw-auth.hdr"

umask 077
printf 'Authorization: Bearer %s\n' "$(cat "$KEY_FILE")" > "$HDR"
trap 'rm -f "$HDR"' EXIT

call() {
  local name="$1" body="$2" out="$SCRATCH/fw-$1.json"
  local code
  code=$(curl -sS -o "$out" -w '%{http_code}' -X POST "$URL" \
    -H @"$HDR" -H 'Content-Type: application/json' --data "$body")
  echo "== $name: HTTP $code"
  if [ "$code" = "200" ]; then
    jq -r '"model: \(.model)",
           "finish_reason: \(.choices[0].finish_reason)",
           "tokens in/out: \(.usage.prompt_tokens)/\(.usage.completion_tokens)",
           "tool_calls: \(.choices[0].message.tool_calls // "none" | tostring | .[0:400])",
           "content: \(.choices[0].message.content // "null" | tostring | .[0:400])"' "$out"
  else
    head -c 600 "$out"; echo
  fi
}

# 1. Plain chat: the litellm workflow provider and Keep's AI suggestions send this shape.
call plain "$(jq -n --arg m "$MODEL" '{
  model: $m, max_tokens: 200,
  messages: [{role: "user", content: "In one sentence: what does a Kubernetes OOMKilled status mean?"}]
}')"

# 2. Incident report shape (keep/api/bl/incident_reports.py:153-166): json_schema + seed + temperature.
call json_schema "$(jq -n --arg m "$MODEL" '{
  model: $m, seed: 1239, temperature: 0.2, max_tokens: 800,
  messages: [
    {role: "system", content: "Group the incidents into their most frequent reasons. Return JSON with property most_frequent_reasons: an object mapping a short reason to a list of incident ids."},
    {role: "user", content: "[{\"incident_id\":\"a1\",\"incident_name\":\"cart pod OOMKilled\",\"severity\":\"critical\",\"services\":[\"cart\"]},{\"incident_id\":\"b2\",\"incident_name\":\"cart container memory limit exceeded\",\"severity\":\"high\",\"services\":[\"cart\"]},{\"incident_id\":\"c3\",\"incident_name\":\"shipping slow MySQL queries\",\"severity\":\"warning\",\"services\":[\"shipping\",\"mysql\"]}]"}
  ],
  response_format: {type: "json_schema", json_schema: {name: "OpenAIReportPart", schema: {
    title: "OpenAIReportPart", type: "object",
    properties: {most_frequent_reasons: {title: "Most Frequent Reasons", type: "object",
      additionalProperties: {type: "array", items: {type: "string"}}}}
  }}}
}')"

# 3. Tool calling: CopilotKit's AI Summary button hands the summary back through a setGeneratedSummary action.
call tools "$(jq -n --arg m "$MODEL" '{
  model: $m, max_tokens: 600,
  messages: [
    {role: "system", content: "Generate a short concise summary of the incident based on the context of the alerts and the title of the incident. Don'\''t repeat prompt. Use the setGeneratedSummary tool to return it."},
    {role: "user", content: "Incident title: Checkout degradation. Alerts: cart pod OOMKilled (critical), cart restarts > 3 in 10m (high), checkout p95 latency 4.2s (warning)."}
  ],
  tools: [{type: "function", function: {name: "setGeneratedSummary", description: "Set the generated summary",
    parameters: {type: "object", properties: {summary: {type: "string", description: "The generated summary"}}, required: ["summary"]}}}],
  tool_choice: "auto"
}')"
