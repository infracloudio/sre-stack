#!/usr/bin/env bash
# Devin emitter (loom registry — see ../loom.sh header).
# Spec pack: agent/harness-specs/devin.md
#
# Three shapes: mcp_config.json (per-server transport overrides from
# loom.config.json — the mcp-remote bridge), config.json (permissions,
# mcp__<server>__* form), hooks.v1.json (canonical Claude hooks with
# env-var re-expansion, empty matcher, timeout).

emit_devin() {
  local ir="$1" out="$2"
  local dir="${out}/.devin"
  mkdir -p "${dir}"

  jq -n \
    --slurpfile ir "${ir}" \
    --arg src "source: .mcp.json + agent/tools/loom.config.json" \
    '
    { "_generated_by": ("loom — do not edit by hand; " + $src),
      mcpServers: ($ir[0].mcp | map(
        .url as $u | .overrides.devin[.name] as $ov |
        if $ov
        then { (.name): { command: $ov.command,
                          args: [$ov.args[] | gsub("\\{\\{url\\}\\}"; $u)] } }
        else { (.name): { url: .url, transport: "http" } }
        end
      ) | add) }' "${ir}" > "${dir}/mcp_config.json"

  jq -n \
    --slurpfile ir "${ir}" \
    --arg src "source: .claude/settings.json" \
    '{ "_generated_by": ("loom — do not edit by hand; " + $src),
       permissions: {
         allow: [$ir[0].permissions.allow[] | select(startswith("mcp__"))]
       } }' "${ir}" > "${dir}/config.json"

  while IFS= read -r entry; do
    [[ -n "${entry}" ]] && gap_add devin "permission allow: ${entry}" \
      "manual CLI approval inside Devin sessions"
  done < <(jq -r '.permissions.allow[] | select(startswith("mcp__") | not)' "${ir}")

  # Every canonical hook event Devin supports is carried over verbatim
  # (Devin: PreToolUse denies on exit 2, like Claude Code). Unsupported
  # events become GAPS rows rather than silent loss.
  local devin_events="PreToolUse PostToolUse PermissionRequest UserPromptSubmit Stop PostCompaction SessionStart SessionEnd"
  while IFS= read -r event; do
    [[ -n "${event}" ]] || continue
    if [[ " ${devin_events} " != *" ${event} "* ]]; then
      gap_add devin "hook event: ${event}" \
        "git pre-commit hooks + CI (same scripts, .githooks/ + .github/workflows/ci.yml)"
    fi
  done < <(jq -r '.hooks | keys[]' "${ir}")

  jq -n \
    --slurpfile ir "${ir}" \
    --arg src "source: .claude/settings.json" \
    --arg supported "${devin_events}" \
    '{ "_generated_by": ("loom — do not edit by hand; " + $src) }
     + ($ir[0].hooks
        | with_entries(select(.key as $k | ($supported | split(" ")) | index($k)))
        | with_entries(.value |= [ .[] | {
            matcher: "",
            hooks: [{ type: "command",
                      command: (.hooks[0].command | sub("\\$CLAUDE_PROJECT_DIR"; "$DEVIN_PROJECT_DIR")),
                      timeout: 30 }]
          } ]))' "${ir}" > "${dir}/hooks.v1.json"
}
