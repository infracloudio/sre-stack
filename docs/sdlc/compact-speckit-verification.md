# Compact Spec Kit verification — 2026-10-29

Worktree: `/tmp/sre-stack-compact-20261029`; baseline commit
`9b7da95ca6b27db4106d80f59ab0f88b97774d88`.
Baseline `make lint` passed with the existing 43 story-cost checks before implementation.

Initial implementation checks (before the review fixes below):

- `make lint`: exit 0; 13 compact tests, 43 story-cost checks, 11 existing
  observability checks and 20 existing route checks pass. Loom reports no drift
  and Spec Kit metadata matches installer pin 1.2.4.
- `python3 agent/tests/spec-kit/test_compact.py`: exit 0; 13 tests pass after
  the final default-integration compatibility assertion correction.
- `make speckit-check`: exit 0; CLI regeneration consistent across four harnesses.
- `shellcheck -S warning agent/spec-kit/posthook.sh` and
  `yamllint -c .yamllint.yaml agent/spec-kit/preset/preset.yml`: exit 0, no output.
- `git diff --check`: exit 0, no output.
- `git diff --name-only -- specs .specify/extensions.yml agent/tools/story-cost.sh
  agent/tests/story-cost`: exit 0, no output. Existing stories, evidence, hooks,
  parser, ledger logic and 43 original collector checks remain unchanged.
- Feature pointer `.specify/feature.json` was absent and remains absent.
  Fixture tests preserve a populated pointer and story evidence, task IDs,
  approvals and usage through two refreshes, including a Codex default.
- Graph built before changes and updated afterward without reported errors.

Existing warnings remain: three YAML comment-indentation warnings in the Azure
OTel chart values, Helm's icon recommendation and four Loom spec packs reported
as 56 days old. No checks or allowlists were weakened. `make lint` checks tracked
shell/YAML files; the new runner and preset received the explicit checks above.

No deployment, paid harness, issue creation, commit, push or global CLI change
was performed. Offline checks prove generated content parity and direct hook
execution, not identical model choices or model compliance. Codex/Devin usage
collection remains unavailable and is explicitly reported as unavailable, not
zero. Only Claude Code/OpenCode collection is supported. CI without Specify
skips the two CLI-dependent tests explicitly while still checking static parity;
`make speckit-check` requires Specify 1.2.4. The CLI's installation timestamp is
excluded from drift comparison; generated content and registry semantics are checked.

Initial command output follows; no terminal output has been shortened. The final review verification is recorded below.

## make lint

```text
check-hooks-enabled: .githooks active
check-secrets: clean (510 files)
check-protected-paths: clean (0 files)
check-ratchets: clean (0 changed files)
infra/azure/chart-values/otel-collector.yaml
  95:5      warning  comment not indented like content  (comments-indentation)
  483:7     warning  comment not indented like content  (comments-indentation)
  495:7     warning  comment not indented like content  (comments-indentation)

==> Linting /tmp/sre-stack-compact-20261029/app/robot-shop/helm
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
lint-changed: clean (sh:96 yaml:116 charts:46)
==> Linting app/robot-shop/helm
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
PASS infra/azure/chart-values/loki.yaml
PASS infra/azure/chart-values/alloy.yaml
PASS infra/azure/chart-values/otel-collector.yaml
PASS monitoring/chart-values/prometheus-values.yaml
PASS infra/azure/kiali/kiali.yaml
placement check: all files select and tolerate the o11y pool correctly
case ok:
  PASS ok:exit-0
  PASS ok:0 failures
case misplaced:
  PASS misplaced:exit-nonzero
  PASS misplaced:names the pod
  PASS misplaced:1 failure
case helper-gap:
  PASS helper-gap:exit-nonzero
  PASS helper-gap:names the pool
case helper-absent:
  PASS helper-absent:exit-nonzero
  PASS helper-absent:names the helper
case beyla-gap:
  PASS beyla-gap:exit-nonzero
  PASS beyla-gap:names the pool

verify-observability offline tests: 11 checks, 0 failed
case no-crd:
  PASS no-crd:exit-0
  PASS no-crd:skip message
  PASS no-crd:0 applies
case no-ns:
  PASS no-ns:exit-0
  PASS no-ns:names the namespace
  PASS no-ns:0 applies
case mesh:
  PASS mesh:exit-0
  PASS mesh:4 applies
  PASS mesh:applies grafana-vs.yaml
  PASS mesh:applies prometheus-vs.yaml
  PASS mesh:applies istio-podmonitor.yaml
  PASS mesh:applies istio-servicemonitor.yaml
  PASS mesh:no skip message
case kube-err:
  PASS kube-err:exit-1
  PASS kube-err:says kubectl failed
  PASS kube-err:no skip message
  PASS kube-err:0 applies
case dry-run:
  PASS dry-run:exit-0
  PASS dry-run:4 applies
  PASS dry-run:every apply is client-side

o11y-routes offline tests: 20 checks, 0 failed
speckit-version: artifacts match installer pin v1.2.4
loom: WARNING: spec pack claude.md is 56 days old — run the loom skill to refresh
loom: WARNING: spec pack codex.md is 56 days old — run the loom skill to refresh
loom: WARNING: spec pack devin.md is 56 days old — run the loom skill to refresh
loom: WARNING: spec pack opencode.md is 56 days old — run the loom skill to refresh
loom: check clean — adapters match regeneration
test_all_ten_commands_have_identical_contract (__main__.CompactTests.test_all_ten_commands_have_identical_contract) ... ok
test_cli_resolution_and_second_regeneration (__main__.CompactTests.test_cli_resolution_and_second_regeneration) ... ok
test_five_mandatory_hooks_and_shared_direct_dispatch (__main__.CompactTests.test_five_mandatory_hooks_and_shared_direct_dispatch) ... ok
test_implementation_defaults_to_bounded_slice_and_reports_next_ids (__main__.CompactTests.test_implementation_defaults_to_bounded_slice_and_reports_next_ids) ... ok
test_manual_aliases_and_retention_from_one_source (__main__.CompactTests.test_manual_aliases_and_retention_from_one_source) ... ok
test_native_invocations (__main__.CompactTests.test_native_invocations) ... ok
test_refresh_preserves_existing_story_evidence_ids_approval_and_pointer (__main__.CompactTests.test_refresh_preserves_existing_story_evidence_ids_approval_and_pointer) ... ✓ Preset 'sre-compact' removed successfully
Installing preset from /tmp/tmpdtw1sya6/agent/spec-kit/preset...
✓ Preset 'SRE compact workflow' v1.0.0 installed (priority 10)
✓ Default integration set to claude.
✓ Default integration set to codex.
✓ Default integration set to opencode.
✓ Default integration set to devin.
story-cost entrypoints: consistent
✓ Default integration set to codex.
✓ Preset 'sre-compact' removed successfully
Installing preset from /tmp/tmpdtw1sya6/agent/spec-kit/preset...
✓ Preset 'SRE compact workflow' v1.0.0 installed (priority 10)
✓ Default integration set to claude.
✓ Default integration set to codex.
✓ Default integration set to opencode.
✓ Default integration set to devin.
story-cost entrypoints: consistent
✓ Default integration set to codex.
ok
test_required_rules_and_lint_not_replaced (__main__.CompactTests.test_required_rules_and_lint_not_replaced) ... ok
test_resolution_stack_registered_and_copied (__main__.CompactTests.test_resolution_stack_registered_and_copied) ... ok
test_rules_preserve_research_approval_convergence_and_accounting (__main__.CompactTests.test_rules_preserve_research_approval_convergence_and_accounting) ... ok
test_shared_runner_executes_make_and_surfaces_warnings_for_all_events (__main__.CompactTests.test_shared_runner_executes_make_and_surfaces_warnings_for_all_events) ... ok
test_templates_are_compact_and_keep_necessary_structure (__main__.CompactTests.test_templates_are_compact_and_keep_necessary_structure) ... ok
test_versions_and_all_installed_harnesses (__main__.CompactTests.test_versions_and_all_installed_harnesses) ... ok

----------------------------------------------------------------------
Ran 13 tests in 10.430s

OK
  PASS check-warns --check warns when usage.tsv is missing
  PASS check-exit-0 --check always exits 0
  PASS run1-exit first run exits 0
  PASS ledger-written usage.tsv and cost.md exist
  PASS dedupe-input duplicate lines counted once (100 + fast reply 10)
  PASS dedupe-output largest output of the duplicates kept (50 + 10)
  PASS cache-1h-split 1-hour cache writes recorded
  PASS price-cache-split 5m and 1h writes and fast reply priced to six places
  PASS subagent-rollup subagent reply lands under the parent session, own model row
  PASS subagent-usd subagent reply priced
  PASS synthetic-skipped <synthetic> model is not recorded
  PASS haiku-over100k Haiku reply over 100k tokens priced at the higher tier
  PASS branch-split-kept only the story-branch part of sess-b is recorded
  PASS branch-split-input main-branch reply not counted
  PASS unknown-flag unknown model is flagged unpriced
  PASS unknown-usd-empty unknown model has an empty usd, not 0
  PASS unknown-warns stderr names the unknown model
  PASS unknown-in-cost-md cost.md says not priced
  PASS skipped-line dropped usage is only counted
  PASS oc-input input tokens mapped
  PASS oc-output output tokens mapped
  PASS oc-reasoning reasoning kept in its own column
  PASS oc-cache-read cache read mapped
  PASS oc-usd stored cost used when non-zero; the zero-cost message is list-priced with reasoning billed once
  PASS oc-source-cost harness-reported cost kept
  PASS oc-subagent-own-row subagent session is its own row
  PASS oc-session-totals-ignored session total columns ignored; later branch window only
  PASS oc-other-dir-ignored sessions outside the repo ignored
  PASS oc-branch-from-reflog branch decided by the reflog at message time
  PASS idempotent-ledger usage.tsv byte-identical on re-run
  PASS idempotent-cost-md cost.md byte-identical on re-run
  PASS idempotent-message second run reports no change
  PASS check-quiet --check silent when usage.tsv exists
  PASS survive-deletion row stays after its log is deleted
  PASS shrink-kept stored row with more tokens is kept
  PASS shrink-flag stored row flagged shrunk
  PASS shrink-warns a warning is printed
  PASS no-opencode-exit missing OpenCode database exits 0
  PASS no-opencode-msg prints the skipped line
  PASS story-missing --story with no folder exits 2
  PASS off-branch-exit non-story branch exits 0
  PASS off-branch-msg says nothing was written
  PASS off-branch-check --check says n/a
story-cost tests: 43 checks, 0 failed
story-cost: n/a (not a story branch)
```

## python3 agent/tests/spec-kit/test_compact.py

```text
test_all_ten_commands_have_identical_contract (__main__.CompactTests.test_all_ten_commands_have_identical_contract) ... ok
test_cli_resolution_and_second_regeneration (__main__.CompactTests.test_cli_resolution_and_second_regeneration) ... ok
test_five_mandatory_hooks_and_shared_direct_dispatch (__main__.CompactTests.test_five_mandatory_hooks_and_shared_direct_dispatch) ... ok
test_implementation_defaults_to_bounded_slice_and_reports_next_ids (__main__.CompactTests.test_implementation_defaults_to_bounded_slice_and_reports_next_ids) ... ok
test_manual_aliases_and_retention_from_one_source (__main__.CompactTests.test_manual_aliases_and_retention_from_one_source) ... ok
test_native_invocations (__main__.CompactTests.test_native_invocations) ... ok
test_refresh_preserves_existing_story_evidence_ids_approval_and_pointer (__main__.CompactTests.test_refresh_preserves_existing_story_evidence_ids_approval_and_pointer) ... ✓ Preset 'sre-compact' removed successfully
Installing preset from /tmp/tmp5fkrzrs3/agent/spec-kit/preset...
✓ Preset 'SRE compact workflow' v1.0.0 installed (priority 10)
✓ Default integration set to claude.
✓ Default integration set to codex.
✓ Default integration set to opencode.
✓ Default integration set to devin.
story-cost entrypoints: consistent
✓ Default integration set to codex.
✓ Preset 'sre-compact' removed successfully
Installing preset from /tmp/tmp5fkrzrs3/agent/spec-kit/preset...
✓ Preset 'SRE compact workflow' v1.0.0 installed (priority 10)
✓ Default integration set to claude.
✓ Default integration set to codex.
✓ Default integration set to opencode.
✓ Default integration set to devin.
story-cost entrypoints: consistent
✓ Default integration set to codex.
ok
test_required_rules_and_lint_not_replaced (__main__.CompactTests.test_required_rules_and_lint_not_replaced) ... ok
test_resolution_stack_registered_and_copied (__main__.CompactTests.test_resolution_stack_registered_and_copied) ... ok
test_rules_preserve_research_approval_convergence_and_accounting (__main__.CompactTests.test_rules_preserve_research_approval_convergence_and_accounting) ... ok
test_shared_runner_executes_make_and_surfaces_warnings_for_all_events (__main__.CompactTests.test_shared_runner_executes_make_and_surfaces_warnings_for_all_events) ... ok
test_templates_are_compact_and_keep_necessary_structure (__main__.CompactTests.test_templates_are_compact_and_keep_necessary_structure) ... ok
test_versions_and_all_installed_harnesses (__main__.CompactTests.test_versions_and_all_installed_harnesses) ... ok

----------------------------------------------------------------------
Ran 13 tests in 8.148s

OK
```

## make speckit-check

```text
✓ Preset 'sre-compact' removed successfully
Installing preset from /tmp/sre-speckit-check-3j7849zs/agent/spec-kit/preset...
✓ Preset 'SRE compact workflow' v1.0.0 installed (priority 10)
✓ Default integration set to claude.
✓ Default integration set to codex.
✓ Default integration set to opencode.
✓ Default integration set to devin.
story-cost entrypoints: consistent
✓ Default integration set to claude.
spec-kit: regeneration consistent across all four harnesses
```

## Final verification after independent review

The review fixes preserve executable modes, honor hook configuration, preserve reviewer-owned checklists, validate analysis prerequisites without changing its pointer, and test forced upgrades. All 16 review findings are triaged in compact-speckit-upgrade.md. The branch-based accounting design in AD-014 remains unchanged.

Final `make lint` exits 0: 23 compact tests, 43 original story-cost checks, 11 observability checks and 20 route checks pass. Generated script modes are executable and included in drift comparisons. Secret and shell/YAML/Helm scans include all 550 tracked and new files. Existing YAML comment, Helm icon and Loom age warnings remain. An independent reviewer confirms the executable-mode and setup-plan failure-test findings are resolved.

The last template-only change expands Now to story, phase, completed count, current slice, blocker and next action. Its template, registry-copy, all-ten-command parity and CLI-regeneration checks pass (4 tests).

No new package was installed. Hook configuration uses existing PyYAML in system Python or the installed Specify console-script runtime. Existing stories, .env, extension configuration, collector, original cost tests, workload manifests and provisioning logic have no diff. The main checkout has its own ignored pointer to specs/009-robot-shop-alert-rules; application leaves that pointer untouched. No paid harness or deployment probes were run. Content parity does not guarantee identical model choices; Codex/Devin usage remains explicitly unavailable.

### Final make lint

```text
check-hooks-enabled: .githooks active
check-secrets: clean (510 files)
check-protected-paths: clean (0 files)
check-ratchets: clean (0 changed files)
infra/azure/chart-values/otel-collector.yaml
  95:5      warning  comment not indented like content  (comments-indentation)
  483:7     warning  comment not indented like content  (comments-indentation)
  495:7     warning  comment not indented like content  (comments-indentation)

==> Linting /tmp/sre-stack-compact-20261029/app/robot-shop/helm
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
lint-changed: clean (sh:96 yaml:116 charts:46)
==> Linting app/robot-shop/helm
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
PASS infra/azure/chart-values/loki.yaml
PASS infra/azure/chart-values/alloy.yaml
PASS infra/azure/chart-values/otel-collector.yaml
PASS monitoring/chart-values/prometheus-values.yaml
PASS infra/azure/kiali/kiali.yaml
placement check: all files select and tolerate the o11y pool correctly
case ok:
  PASS ok:exit-0
  PASS ok:0 failures
case misplaced:
  PASS misplaced:exit-nonzero
  PASS misplaced:names the pod
  PASS misplaced:1 failure
case helper-gap:
  PASS helper-gap:exit-nonzero
  PASS helper-gap:names the pool
case helper-absent:
  PASS helper-absent:exit-nonzero
  PASS helper-absent:names the helper
case beyla-gap:
  PASS beyla-gap:exit-nonzero
  PASS beyla-gap:names the pool

verify-observability offline tests: 11 checks, 0 failed
case no-crd:
  PASS no-crd:exit-0
  PASS no-crd:skip message
  PASS no-crd:0 applies
case no-ns:
  PASS no-ns:exit-0
  PASS no-ns:names the namespace
  PASS no-ns:0 applies
case mesh:
  PASS mesh:exit-0
  PASS mesh:4 applies
  PASS mesh:applies grafana-vs.yaml
  PASS mesh:applies prometheus-vs.yaml
  PASS mesh:applies istio-podmonitor.yaml
  PASS mesh:applies istio-servicemonitor.yaml
  PASS mesh:no skip message
case kube-err:
  PASS kube-err:exit-1
  PASS kube-err:says kubectl failed
  PASS kube-err:no skip message
  PASS kube-err:0 applies
case dry-run:
  PASS dry-run:exit-0
  PASS dry-run:4 applies
  PASS dry-run:every apply is client-side

o11y-routes offline tests: 20 checks, 0 failed
speckit-version: artifacts match installer pin v1.2.4
loom: WARNING: spec pack claude.md is 56 days old — run the loom skill to refresh
loom: WARNING: spec pack codex.md is 56 days old — run the loom skill to refresh
loom: WARNING: spec pack devin.md is 56 days old — run the loom skill to refresh
loom: WARNING: spec pack opencode.md is 56 days old — run the loom skill to refresh
loom: check clean — adapters match regeneration
test_all_ten_commands_have_identical_contract (__main__.CompactTests.test_all_ten_commands_have_identical_contract) ... ok
test_checklist_supports_preplan_and_reviewer_ownership (__main__.CompactTests.test_checklist_supports_preplan_and_reviewer_ownership) ... ok
test_cli_resolution_and_second_regeneration (__main__.CompactTests.test_cli_resolution_and_second_regeneration) ... ok
test_direct_script_entrypoints_and_snapshot_executable_bits (__main__.CompactTests.test_direct_script_entrypoints_and_snapshot_executable_bits) ... ok
test_five_mandatory_hooks_and_shared_direct_dispatch (__main__.CompactTests.test_five_mandatory_hooks_and_shared_direct_dispatch) ... ok
test_hook_configuration_states_and_exactly_once_dispatch (__main__.CompactTests.test_hook_configuration_states_and_exactly_once_dispatch) ... ok
test_implementation_defaults_to_bounded_slice_and_reports_next_ids (__main__.CompactTests.test_implementation_defaults_to_bounded_slice_and_reports_next_ids) ... ok
test_malformed_and_unsafe_yaml_fail_without_collection (__main__.CompactTests.test_malformed_and_unsafe_yaml_fail_without_collection) ... ok
test_manual_aliases_and_retention_from_one_source (__main__.CompactTests.test_manual_aliases_and_retention_from_one_source) ... ok
test_native_invocations (__main__.CompactTests.test_native_invocations) ... ok
test_refresh_preservation_runs_even_if_default_restoration_fails (__main__.CompactTests.test_refresh_preservation_runs_even_if_default_restoration_fails) ... ok
test_refresh_preserves_existing_story_evidence_ids_approval_and_pointer (__main__.CompactTests.test_refresh_preserves_existing_story_evidence_ids_approval_and_pointer) ... Updated execute permissions on 6 script(s) recursively
Upgrading integration: claude

✓ Integration 'Claude Code' upgraded successfully
Updated execute permissions on 6 script(s) recursively
Upgrading integration: codex
Updated execute permissions on 6 script(s) recursively

✓ Integration 'Codex CLI' upgraded successfully
Updated execute permissions on 6 script(s) recursively
Upgrading integration: opencode

✓ Integration 'opencode' upgraded successfully
Updated execute permissions on 6 script(s) recursively
Upgrading integration: devin

✓ Integration 'Devin for Terminal' upgraded successfully
✓ Preset 'sre-compact' removed successfully
Installing preset from /tmp/tmpva50ps05/agent/spec-kit/preset...
✓ Preset 'SRE compact workflow' v1.0.0 installed (priority 10)
✓ Default integration set to claude.
✓ Default integration set to codex.
✓ Default integration set to opencode.
✓ Default integration set to devin.
story-cost entrypoints: consistent
✓ Default integration set to codex.
✓ Preset 'sre-compact' removed successfully
Installing preset from /tmp/tmpva50ps05/agent/spec-kit/preset...
✓ Preset 'SRE compact workflow' v1.0.0 installed (priority 10)
✓ Default integration set to claude.
✓ Default integration set to codex.
✓ Default integration set to opencode.
✓ Default integration set to devin.
story-cost entrypoints: consistent
✓ Default integration set to codex.
ok
test_required_rules_and_lint_not_replaced (__main__.CompactTests.test_required_rules_and_lint_not_replaced) ... ok
test_resolution_stack_registered_and_copied (__main__.CompactTests.test_resolution_stack_registered_and_copied) ... ok
test_rules_preserve_research_approval_convergence_and_accounting (__main__.CompactTests.test_rules_preserve_research_approval_convergence_and_accounting) ... ok
test_setup_plan_rejects_empty_and_missing_templates_without_plan (__main__.CompactTests.test_setup_plan_rejects_empty_and_missing_templates_without_plan) ... ok
test_shared_runner_executes_make_and_surfaces_warnings_for_all_events (__main__.CompactTests.test_shared_runner_executes_make_and_surfaces_warnings_for_all_events) ... ok
test_specify_pointer_schema_and_analysis_readonly_required_spec (__main__.CompactTests.test_specify_pointer_schema_and_analysis_readonly_required_spec) ... ok
test_templates_are_compact_and_keep_necessary_structure (__main__.CompactTests.test_templates_are_compact_and_keep_necessary_structure) ... ok
test_unicode_warning_paths_and_branch_attribution (__main__.CompactTests.test_unicode_warning_paths_and_branch_attribution) ... ok
test_version_diagnostic_uses_supported_refresh_without_dropping_checks (__main__.CompactTests.test_version_diagnostic_uses_supported_refresh_without_dropping_checks) ... ok
test_versions_and_all_installed_harnesses (__main__.CompactTests.test_versions_and_all_installed_harnesses) ... ok
test_yaml_fallback_uses_existing_specify_console_script_runtime (__main__.CompactTests.test_yaml_fallback_uses_existing_specify_console_script_runtime) ... ok

----------------------------------------------------------------------
Ran 23 tests in 17.745s

OK
  PASS check-warns --check warns when usage.tsv is missing
  PASS check-exit-0 --check always exits 0
  PASS run1-exit first run exits 0
  PASS ledger-written usage.tsv and cost.md exist
  PASS dedupe-input duplicate lines counted once (100 + fast reply 10)
  PASS dedupe-output largest output of the duplicates kept (50 + 10)
  PASS cache-1h-split 1-hour cache writes recorded
  PASS price-cache-split 5m and 1h writes and fast reply priced to six places
  PASS subagent-rollup subagent reply lands under the parent session, own model row
  PASS subagent-usd subagent reply priced
  PASS synthetic-skipped <synthetic> model is not recorded
  PASS haiku-over100k Haiku reply over 100k tokens priced at the higher tier
  PASS branch-split-kept only the story-branch part of sess-b is recorded
  PASS branch-split-input main-branch reply not counted
  PASS unknown-flag unknown model is flagged unpriced
  PASS unknown-usd-empty unknown model has an empty usd, not 0
  PASS unknown-warns stderr names the unknown model
  PASS unknown-in-cost-md cost.md says not priced
  PASS skipped-line dropped usage is only counted
  PASS oc-input input tokens mapped
  PASS oc-output output tokens mapped
  PASS oc-reasoning reasoning kept in its own column
  PASS oc-cache-read cache read mapped
  PASS oc-usd stored cost used when non-zero; the zero-cost message is list-priced with reasoning billed once
  PASS oc-source-cost harness-reported cost kept
  PASS oc-subagent-own-row subagent session is its own row
  PASS oc-session-totals-ignored session total columns ignored; later branch window only
  PASS oc-other-dir-ignored sessions outside the repo ignored
  PASS oc-branch-from-reflog branch decided by the reflog at message time
  PASS idempotent-ledger usage.tsv byte-identical on re-run
  PASS idempotent-cost-md cost.md byte-identical on re-run
  PASS idempotent-message second run reports no change
  PASS check-quiet --check silent when usage.tsv exists
  PASS survive-deletion row stays after its log is deleted
  PASS shrink-kept stored row with more tokens is kept
  PASS shrink-flag stored row flagged shrunk
  PASS shrink-warns a warning is printed
  PASS no-opencode-exit missing OpenCode database exits 0
  PASS no-opencode-msg prints the skipped line
  PASS story-missing --story with no folder exits 2
  PASS off-branch-exit non-story branch exits 0
  PASS off-branch-msg says nothing was written
  PASS off-branch-check --check says n/a
story-cost tests: 43 checks, 0 failed
story-cost: n/a (not a story branch)
```

### Final template and regeneration checks

```text
test_templates_are_compact_and_keep_necessary_structure (__main__.CompactTests.test_templates_are_compact_and_keep_necessary_structure) ... ok
test_resolution_stack_registered_and_copied (__main__.CompactTests.test_resolution_stack_registered_and_copied) ... ok
test_all_ten_commands_have_identical_contract (__main__.CompactTests.test_all_ten_commands_have_identical_contract) ... ok
test_cli_resolution_and_second_regeneration (__main__.CompactTests.test_cli_resolution_and_second_regeneration) ... ok

----------------------------------------------------------------------
Ran 4 tests in 6.454s

OK
```

