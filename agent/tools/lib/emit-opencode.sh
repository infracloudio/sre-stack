#!/usr/bin/env bash
# opencode emitter (loom registry — see ../loom.sh header).
# Spec pack: agent/harness-specs/opencode.md

emit_opencode() {
  local ir="$1" out="$2"
  mkdir -p "${out}"

  # NOTE: opencode.json cannot carry a "_generated_by" marker — the config
  # schema rejects unknown keys (found by probe, 2026-09-03). The --check
  # drift gate is the marker here. See agent/harness-specs/opencode.md.
  jq -n \
    --slurpfile ir "${ir}" \
    '{ "$schema": "https://opencode.ai/config.json",
       mcp: [$ir[0].mcp[] | { (.name): { type: "remote", url: .url } }] | add }' \
    "${ir}" > "${out}/opencode.json"

  # permissions: opencode has no config-level allowlist — docs servers are
  # allowed by default. Non-MCP entries are a recorded gap.
  while IFS= read -r entry; do
    [[ -n "${entry}" ]] && gap_add opencode "permission allow: ${entry}" \
      "allowed by default in opencode for docs servers; manual otherwise"
  done < <(jq -r '.permissions.allow[] | select(startswith("mcp__") | not)' "${ir}")
}
