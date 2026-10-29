#!/usr/bin/env python3
"""Permanent offline compact-preset, parity, preservation and hook tests.

No real model, home-directory usage logs, cloud calls or new dependencies.
CLI regeneration is tested when Specify 1.2.4 is installed; otherwise explicit skip.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / 'agent/spec-kit'
PRESET = SOURCE / 'preset'
VERBS = ('specify', 'plan', 'tasks', 'analyze', 'implement', 'converge',
         'clarify', 'checklist', 'constitution', 'taskstoissues')
POSTHOOKS = ('specify', 'tasks', 'analyze', 'implement', 'converge')
HARNESSES = ('.claude', '.agents', '.devin', '.opencode')


def command_path(harness, verb):
    if harness == '.opencode':
        return ROOT / harness / 'commands' / f'speckit.{verb}.md'
    return ROOT / harness / 'skills' / f'speckit-{verb}' / 'SKILL.md'


def body(text):
    text = text.split('## Input and shared contract', 1)[1]
    text = re.sub(r'[/\$]speckit[-.]([a-z]+)', r'__SPECKIT_COMMAND_\1__', text)
    return text.strip().lower()


def run(*args, cwd=ROOT, **kwargs):
    return subprocess.run(args, cwd=cwd, text=True, capture_output=True, **kwargs)


def refresh_module():
    module_spec = importlib.util.spec_from_file_location('refresh', SOURCE / 'refresh.py')
    module = importlib.util.module_from_spec(module_spec)
    module_spec.loader.exec_module(module)
    return module


def hook_fixture(sandbox, story='001-fixture'):
    (sandbox / 'agent/spec-kit').mkdir(parents=True)
    for name in ('posthook.sh', 'posthook.py'):
        shutil.copy(SOURCE / name, sandbox / 'agent/spec-kit' / name)
    (sandbox / '.specify').mkdir()
    shutil.copy(ROOT / '.specify/extensions.yml', sandbox / '.specify/extensions.yml')
    (sandbox / 'specs' / story).mkdir(parents=True)
    (sandbox / 'specs' / story / 'cost.md').write_text('Not priced: fixture\nShrunk rows: fixture\n')
    (sandbox / 'makefile').write_text('story-cost:\n\t@echo ran >> calls\n\t@echo "Total fixture"\n')
    return dict(os.environ, STORY=story)


def script_fixture(sandbox):
    shutil.copytree(ROOT / '.specify/scripts', sandbox / '.specify/scripts')
    pointer = sandbox / '.specify/feature.json'
    pointer.write_text('{"feature_directory":"specs/001-original"}\n')
    feature = sandbox / 'specs/002-override'
    feature.mkdir(parents=True)
    environment = dict(os.environ, SPECIFY_INIT_DIR=str(sandbox),
                       SPECIFY_FEATURE_DIRECTORY='specs/002-override')
    return pointer, feature, environment


class CompactTests(unittest.TestCase):
    def test_versions_and_all_installed_harnesses(self):
        state = json.loads((ROOT / '.specify/integration.json').read_text())
        self.assertEqual(set(state['installed_integrations']), {'claude', 'codex', 'devin', 'opencode'})
        self.assertIn(state['default_integration'], state['installed_integrations'])
        self.assertEqual(state['version'], '1.2.4')
        self.assertEqual(json.loads((ROOT / '.specify/init-options.json').read_text())['speckit_version'], '1.2.4')
        for path in (ROOT / '.specify/integrations').glob('*.manifest.json'):
            with self.subTest(manifest=path.name):
                self.assertEqual(json.loads(path.read_text())['version'], '1.2.4')
        self.assertIn('SPEC_KIT_VERSION="v1.2.4"', (ROOT / 'infra/scripts/dev/install-deps.sh').read_text())

    def test_resolution_stack_registered_and_copied(self):
        registry = json.loads((ROOT / '.specify/presets/.registry').read_text())
        preset = registry['presets']['sre-compact']
        self.assertTrue(preset['enabled'])
        self.assertEqual(preset['priority'], 10)
        self.assertEqual(preset['manifest_hash'], 'sha256:' + hashlib.sha256((PRESET / 'preset.yml').read_bytes()).hexdigest())
        for path in PRESET.rglob('*'):
            if path.is_file():
                self.assertEqual(path.read_bytes(), (ROOT / '.specify/presets/sre-compact' / path.relative_to(PRESET)).read_bytes())
        for harness in ('claude', 'codex', 'devin', 'opencode'):
            self.assertEqual(set(preset['registered_commands'][harness]), {f'speckit.{v}' for v in VERBS})

    def test_all_ten_commands_have_identical_contract(self):
        for verb in VERBS:
            expected = body((PRESET / f'commands/{verb}.md').read_text())
            for harness in HARNESSES:
                with self.subTest(verb=verb, harness=harness):
                    text = command_path(harness, verb).read_text()
                    self.assertEqual(body(text), expected)
                    self.assertNotIn('__SPECKIT_COMMAND_', text)
                    for required in ('agent/spec-kit/rules.md', 'agent/spec-kit/story-cost.md',
                                     'constitution', 'AGENTS.md', 'mandatory', 'wait'):
                        self.assertIn(required, text)

    def test_native_invocations(self):
        for harness, prefix in (('.claude', '/speckit-'), ('.agents', '$speckit-'),
                                ('.devin', '/speckit-'), ('.opencode', '/speckit.')):
            self.assertIn(prefix + 'tasks', command_path(harness, 'plan').read_text())

    def test_rules_preserve_research_approval_convergence_and_accounting(self):
        rules = (SOURCE / 'rules.md').read_text()
        for required in ('real\ncluster', 'before any spec section', 'verbatim output',
                         'Missing access', 'requested\nand refused', 'Cheap read-only',
                         'one section at a time', 'STOP and wait', 'explicit\ndeveloper approval',
                         '400 words', '600 words', 'targets, not caps', 'Never truncate',
                         'actual paths', 'reviewer-facing', 'legacy identifiers',
                         'CRITICAL/HIGH', 'Edge\nCases list is closed', 'One round only',
                         'second round', 'coverage alone', 'independent', 'protected paths',
                         'existing tests', 'make story-cost', 'before reporting completion',
                         'Codex and Devin usage\nis unavailable', 'never report it as zero'):
            with self.subTest(rule=required):
                self.assertIn(required, rules)

    def test_templates_are_compact_and_keep_necessary_structure(self):
        spec = (PRESET / 'templates/spec-template.md').read_text()
        plan = (PRESET / 'templates/plan-template.md').read_text()
        tasks = (PRESET / 'templates/tasks-template.md').read_text()
        for text, target in ((spec, '400'), (plan, '600'), (tasks, '600')):
            self.assertIn(target, text)
            self.assertIn('one section', text.lower())
        for required in ('Given/When/Then', 'FR-001', 'SC-001', 'Edge Cases', 'must keep working'):
            self.assertIn(required, spec)
        for required in ('Constitution Check', 'reviewer-facing commands', 'Actual paths', 'make lint', 'departures'):
            self.assertIn(required.lower(), plan.lower())
        self.assertEqual(re.findall(r'^## (.*)', tasks, re.M)[0], 'Now')
        for field in ('Story', 'Phase', 'Completed', 'Current slice', 'Blocker', 'Next action'):
            self.assertIn(f'**{field}**:', tasks)
        for required in ('T001', 'T002', 'never renumber', 'dependencies', 'Convergence', 'One append'):
            self.assertIn(required, tasks)

    def test_five_mandatory_hooks_and_shared_direct_dispatch(self):
        config = (ROOT / '.specify/extensions.yml').read_text()
        self.assertEqual(re.findall(r'^  after_(\w+):', config, re.M), list(POSTHOOKS))
        self.assertEqual(config.count('optional: false'), 5)
        self.assertEqual(config.count('command: story-cost'), 5)
        for verb in POSTHOOKS:
            for harness in HARNESSES:
                with self.subTest(verb=verb, harness=harness):
                    text = command_path(harness, verb).read_text()
                    self.assertIn(f'bash agent/spec-kit/posthook.sh after_{verb}', text)
                    self.assertIn('including blocked/partial runs', text)
                    self.assertIn('runner exactly once', text)
                    self.assertIn('Do not also invoke story-cost through generic hook dispatch', text)

    def test_shared_runner_executes_make_and_surfaces_warnings_for_all_events(self):
        with tempfile.TemporaryDirectory() as directory:
            sandbox = Path(directory)
            environment = hook_fixture(sandbox)
            for verb in POSTHOOKS:
                result = run('bash', 'agent/spec-kit/posthook.sh', f'after_{verb}', cwd=sandbox, env=environment)
                self.assertEqual(result.returncode, 0, result.stderr)
                for warning in ('Total fixture', 'Not priced: fixture', 'Shrunk rows: fixture',
                                'Codex/Devin unavailable (not zero)'):
                    self.assertIn(warning, result.stdout)
            self.assertEqual((sandbox / 'calls').read_text().splitlines(), ['ran'] * 5)
            (sandbox / 'makefile').write_text('story-cost:\n\t@exit 7\n')
            failed = run('bash', 'agent/spec-kit/posthook.sh', 'after_specify', cwd=sandbox, env=environment)
            self.assertNotEqual(failed.returncode, 0)
            self.assertNotIn('Accounting:', failed.stdout)
            self.assertNotEqual(run('bash', 'agent/spec-kit/posthook.sh', 'after_fake', cwd=sandbox).returncode, 0)

    def test_implementation_defaults_to_bounded_slice_and_reports_next_ids(self):
        for harness in HARNESSES:
            text = command_path(harness, 'implement').read_text()
            for required in ('Default to one acceptance slice', 'user requests it',
                             'selected IDs', 'tasks.md Now', 'unfinished IDs',
                             'range and stop', 'only after all original', 'required checks'):
                self.assertIn(required, text)
        rules = (SOURCE / 'rules.md').read_text()
        self.assertIn('Honor larger batches explicitly requested by the user', rules)
        self.assertIn('Do not mark unverified work complete', rules)

    def test_manual_aliases_and_retention_from_one_source(self):
        result = run('python3', 'agent/spec-kit/generate-entrypoints.py', '--check')
        self.assertEqual(result.returncode, 0, result.stderr)
        for harness in HARNESSES:
            path = (ROOT / harness / 'commands/story-cost.md' if harness == '.opencode'
                    else ROOT / harness / 'skills/story-cost/SKILL.md')
            text = path.read_text()
            for required in ('make story-cost', 'Not priced', 'Shrunk', 'Codex and Devin',
                             'unavailable, not zero', '3650', 'Never suggest 0', 'Never edit usage.tsv'):
                self.assertIn(required, text)

    def test_required_rules_and_lint_not_replaced(self):
        constitution = (ROOT / '.specify/memory/constitution.md').read_text()
        for heading in ('VIII. Try It Before You Plan It', 'IX. Author In Steps, Developer in the Loop',
                        'X. Converge to the Agreed Scope, Then Stop'):
            self.assertIn(heading, constitution)
        makefile = (ROOT / 'makefile').read_text()
        for existing in ('check-hooks-enabled.sh', 'check-secrets.sh', 'check-protected-paths.sh',
                         'check-ratchets.sh', 'lint-changed.sh', 'helm lint', 'loom.sh --check',
                         'agent/tests/story-cost/run-tests.sh', 'check-speckit-version.sh'):
            self.assertIn(existing, makefile)
        self.assertIn('python3 agent/tests/spec-kit/test_compact.py', makefile)

    @unittest.skipUnless(shutil.which('specify'), 'Specify CLI absent; static parity still checked; run make speckit-check with 1.2.4')
    def test_cli_resolution_and_second_regeneration(self):
        for template in ('spec', 'plan', 'tasks'):
            result = run('specify', 'preset', 'resolve', f'{template}-template')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('sre-compact', result.stdout)
        result = run('python3', 'agent/spec-kit/refresh.py', '--check')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    @unittest.skipUnless(shutil.which('specify'), 'Specify CLI absent; preservation regeneration needs 1.2.4')
    def test_refresh_preserves_existing_story_evidence_ids_approval_and_pointer(self):
        module = refresh_module()
        with tempfile.TemporaryDirectory() as directory:
            sandbox = Path(directory)
            for surface in (*module.SURFACES, 'agent/spec-kit'):
                shutil.copytree(ROOT / surface, sandbox / surface, dirs_exist_ok=True)
            story = sandbox / 'specs/001-existing'
            story.mkdir(parents=True)
            fixtures = {'spec.md': 'FR-99 gate:spec-approved Alice\n',
                        'plan.md': 'gate:plan-approved Bob\n',
                        'tasks.md': '- [x] T019 preserved\n',
                        'evidence.txt': 'actual output\nfull output remains\n',
                        'usage.tsv': 'claude\tsession\tretained\n',
                        'cost.md': 'recorded evidence $1.23\n'}
            for path, text in fixtures.items():
                (story / path).write_text(text)
            (sandbox / '.specify/feature.json').write_text('{"feature_directory":"specs/001-existing"}\n')
            result = run('specify', 'integration', 'use', 'codex', cwd=sandbox)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            unrelated = {}
            for harness in HARNESSES:
                path = (sandbox / harness / 'commands/unrelated.md' if harness == '.opencode'
                        else sandbox / harness / 'skills/unrelated/SKILL.md')
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('unrelated skill must stay byte-identical\n')
                unrelated[path] = path.read_bytes()
            before = module.protected(sandbox)
            module.refresh(sandbox, upgrade=True)
            self.assertEqual({path: path.read_bytes() for path in unrelated}, unrelated)
            for path in (sandbox / '.specify/scripts/bash').glob('*.sh'):
                self.assertEqual(path.stat().st_mode & 0o111, 0o111)
                direct = run(str(path), '--help', cwd=sandbox)
                self.assertEqual(direct.returncode, 0, direct.stdout + direct.stderr)
            self.assertEqual(before, module.protected(sandbox))
            self.assertEqual(json.loads((sandbox / '.specify/integration.json').read_text())['default_integration'], 'codex')
            first = module.snapshot(sandbox)
            module.refresh(sandbox)
            self.assertEqual(first, module.snapshot(sandbox))
            self.assertEqual(before, module.protected(sandbox))
            self.assertEqual({path: path.read_bytes() for path in unrelated}, unrelated)
            for path in (sandbox / '.specify/scripts/bash').glob('*.sh'):
                self.assertEqual(run(str(path), '--help', cwd=sandbox).returncode, 0)


    def test_hook_configuration_states_and_exactly_once_dispatch(self):
        entries = {
            'removed': ('hooks: {}\n', 0, 'no automatic'),
            'disabled': ('enabled: false\n      optional: false', 0, 'disabled'),
            'optional': ('enabled: true\n      optional: true', 0, 'optional'),
            'conditional': ('optional: false\n      condition: "branch == main"', 0, 'deferred'),
            'empty-condition': ('optional: false\n      condition: ""', 1, 'Accounting:'),
            'null-condition': ('optional: false\n      condition: null', 1, 'Accounting:'),
            'duplicate': ('optional: false\n    - command: story-cost\n      optional: false', 1, 'Accounting:'),
            'missing-enabled': ('optional: false', 1, 'Accounting:'),
        }
        for case, (entry, count, message) in entries.items():
            with self.subTest(case=case), tempfile.TemporaryDirectory() as directory:
                sandbox = Path(directory)
                environment = hook_fixture(sandbox)
                config = entry if case == 'removed' else (
                    'hooks:\n  after_specify:\n    - command: story-cost\n      ' + entry + '\n')
                (sandbox / '.specify/extensions.yml').write_text(config)
                result = run('bash', 'agent/spec-kit/posthook.sh', 'after_specify', cwd=sandbox, env=environment)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(message, result.stdout)
                calls = (sandbox / 'calls').read_text().splitlines() if (sandbox / 'calls').exists() else []
                self.assertEqual(calls, ['ran'] * count)
        with tempfile.TemporaryDirectory() as directory:
            sandbox = Path(directory)
            environment = hook_fixture(sandbox)
            (sandbox / '.specify/extensions.yml').unlink()
            result = run('bash', 'agent/spec-kit/posthook.sh', 'after_specify', cwd=sandbox, env=environment)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('extensions.yml missing', result.stdout)
            self.assertFalse((sandbox / 'calls').exists())

    def test_malformed_and_unsafe_yaml_fail_without_collection(self):
        for config in ('hooks: [broken', 'hooks: []', 'hooks: {after_specify: {}}',
                       '!!python/object/apply:os.system ["echo unsafe > unsafe"]'):
            with self.subTest(config=config), tempfile.TemporaryDirectory() as directory:
                sandbox = Path(directory)
                environment = hook_fixture(sandbox)
                (sandbox / '.specify/extensions.yml').write_text(config)
                result = run('bash', 'agent/spec-kit/posthook.sh', 'after_specify', cwd=sandbox, env=environment)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('cannot read mandatory hook configuration', result.stderr)
                self.assertFalse((sandbox / 'calls').exists())
                self.assertFalse((sandbox / 'unsafe').exists())

    def test_unicode_warning_paths_and_branch_attribution(self):
        with tempfile.TemporaryDirectory() as directory:
            sandbox = Path(directory)
            environment = hook_fixture(sandbox, '010-café')
            result = run('bash', 'agent/spec-kit/posthook.sh', 'after_tasks', cwd=sandbox, env=environment)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('Shrunk rows: fixture', result.stdout)
            self.assertIn('Not priced: fixture', result.stdout)
            # A divergent feature pointer must not change branch-based warning attribution.
            (sandbox / '.specify/feature.json').write_text('{"feature_directory":"specs/099-other"}')
            initialized = run('git', 'init', '-q', '-b', '010-café', cwd=sandbox)
            self.assertEqual(initialized.returncode, 0, initialized.stderr)
            # Git has no HEAD until a commit; use symbolic-ref behavior via a fixture executable.
            bindir = sandbox / 'bin'
            bindir.mkdir()
            git = bindir / 'git'
            git.write_text('#!/bin/sh\nprintf "%s\\n" "010-café"\n')
            git.chmod(0o755)
            environment.pop('STORY', None)
            environment['PATH'] = str(bindir) + os.pathsep + os.environ['PATH']
            result = run('bash', 'agent/spec-kit/posthook.sh', 'after_tasks', cwd=sandbox, env=environment)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('Not priced: fixture', result.stdout)
            for invalid in ('', '.', '..', 'HEAD', 'wrong/path'):
                environment['STORY'] = invalid
                # Empty uses the branch, matching the existing collector; detached HEAD is invalid.
                git.write_text('#!/bin/sh\nprintf "%s\\n" "HEAD"\n')
                result = run('bash', 'agent/spec-kit/posthook.sh', 'after_tasks', cwd=sandbox, env=environment)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn('Not priced: fixture', result.stdout)

    @unittest.skipUnless(shutil.which('specify'), 'Specify runtime fallback requires the installed console script')
    def test_yaml_fallback_uses_existing_specify_console_script_runtime(self):
        with tempfile.TemporaryDirectory() as directory:
            sandbox = Path(directory)
            environment = hook_fixture(sandbox)
            bindir = sandbox / 'bin'
            bindir.mkdir()
            python = bindir / 'python3'
            python.write_text('#!/bin/sh\nexit 1\n')
            python.chmod(0o755)
            specify = bindir / 'specify'
            specify.write_text(Path(shutil.which('specify')).read_text().splitlines()[0] + '\n')
            specify.chmod(0o755)
            environment['PATH'] = str(bindir) + os.pathsep + os.environ['PATH']
            result = run('bash', 'agent/spec-kit/posthook.sh', 'after_analyze', cwd=sandbox, env=environment)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('Accounting:', result.stdout)
            self.assertEqual((sandbox / 'calls').read_text().splitlines(), ['ran'])

    def test_checklist_supports_preplan_and_reviewer_ownership(self):
        for harness in HARNESSES:
            text = command_path(harness, 'checklist').read_text()
            for contract in ('--json --paths-only', 'Explicitly check that FEATURE_SPEC exists',
                             'a plan is not required', 'unchecked `- [ ]` markers',
                             'belong to the reviewer', 'without an explicit reviewer request'):
                self.assertIn(contract, text)
        with tempfile.TemporaryDirectory() as directory:
            sandbox = Path(directory)
            pointer, feature, environment = script_fixture(sandbox)
            before = pointer.read_bytes()
            (feature / 'spec.md').write_text('existing specification\n')
            result = run(str(sandbox / '.specify/scripts/bash/check-prerequisites.sh'),
                         '--json', '--paths-only', cwd=sandbox, env=environment)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(Path(json.loads(result.stdout)['FEATURE_SPEC']).is_file())
            self.assertFalse((feature / 'plan.md').exists())
            self.assertEqual(pointer.read_bytes(), before)

    def test_specify_pointer_schema_and_analysis_readonly_required_spec(self):
        for harness in HARNESSES:
            text = command_path(harness, 'analyze').read_text()
            self.assertIn('SPECIFY_FEATURE_NO_PERSIST=1', text)
            self.assertIn('--require-spec', text)
            self.assertIn('cost ledger posthook is the intentional separate side effect', text)
            self.assertIn('{"feature_directory":"specs/010-example"}', command_path(harness, 'specify').read_text())
        with tempfile.TemporaryDirectory() as directory:
            sandbox = Path(directory)
            pointer, feature, environment = script_fixture(sandbox)
            environment['SPECIFY_FEATURE_NO_PERSIST'] = '1'
            before = pointer.read_bytes()
            (feature / 'plan.md').write_text('approved plan\n')
            (feature / 'tasks.md').write_text('- [ ] T001 work\n')
            args = (str(sandbox / '.specify/scripts/bash/check-prerequisites.sh'),
                    '--json', '--require-spec', '--require-tasks', '--include-tasks')
            result = run(*args, cwd=sandbox, env=environment)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('spec.md not found', result.stderr)
            self.assertEqual(pointer.read_bytes(), before)
            (feature / 'spec.md').write_text('approved spec\n')
            result = run(*args, cwd=sandbox, env=environment)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(Path(json.loads(result.stdout)['FEATURE_DIR']), feature)
            self.assertEqual(pointer.read_bytes(), before)

    def test_setup_plan_rejects_empty_and_missing_templates_without_plan(self):
        for state in ('empty', 'missing'):
            with self.subTest(state=state), tempfile.TemporaryDirectory() as directory:
                sandbox = Path(directory)
                _, feature, environment = script_fixture(sandbox)
                if state == 'empty':
                    templates = sandbox / '.specify/templates'
                    templates.mkdir()
                    (templates / 'plan-template.md').write_text('')
                result = run(str(sandbox / '.specify/scripts/bash/setup-plan.sh'), '--json',
                             cwd=sandbox, env=environment)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('no new plan.md was created', result.stderr)
                self.assertFalse((feature / 'plan.md').exists())

    def test_direct_script_entrypoints_and_snapshot_executable_bits(self):
        module = refresh_module()
        scripts = sorted((ROOT / '.specify/scripts/bash').glob('*.sh'))
        self.assertEqual(len(scripts), 6)
        for path in scripts:
            with self.subTest(path=path.name):
                self.assertEqual(path.stat().st_mode & 0o111, 0o111)
                result = run(str(path), '--help')
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        with tempfile.TemporaryDirectory() as directory:
            sandbox = Path(directory)
            path = sandbox / '.specify/scripts/bash/demo.sh'
            path.parent.mkdir(parents=True)
            path.write_text('#!/bin/sh\n')
            before = module.snapshot(sandbox)
            path.chmod(path.stat().st_mode | 0o111)
            self.assertNotEqual(before, module.snapshot(sandbox))

    def test_refresh_preservation_runs_even_if_default_restoration_fails(self):
        module = refresh_module()
        with tempfile.TemporaryDirectory() as directory:
            sandbox = Path(directory)
            (sandbox / '.specify').mkdir()
            shutil.copy(ROOT / '.specify/integration.json', sandbox / '.specify/integration.json')
            config = sandbox / '.specify/extensions.yml'
            config.write_text('hooks: {}\n')

            def fail_refresh(root, *args):
                if args[:2] == ('specify', 'preset'):
                    config.write_text('hooks: changed\n')
                    raise ValueError('initial regeneration failure')
                raise OSError('default restoration failure')

            with mock.patch.object(module, 'run', side_effect=fail_refresh):
                with self.assertRaisesRegex(RuntimeError, 'Refresh changed') as caught:
                    module.refresh(sandbox)
            self.assertIn('default restoration failure', str(caught.exception.__context__))
            self.assertIn('initial regeneration failure', str(caught.exception.__context__.__context__))

    def test_version_diagnostic_uses_supported_refresh_without_dropping_checks(self):
        with tempfile.TemporaryDirectory() as directory:
            sandbox = Path(directory)
            script = sandbox / 'agent/hooks/check-speckit-version.sh'
            script.parent.mkdir(parents=True)
            shutil.copy(ROOT / 'agent/hooks/check-speckit-version.sh', script)
            installer = sandbox / 'infra/scripts/dev/install-deps.sh'
            installer.parent.mkdir(parents=True)
            installer.write_text('SPEC_KIT_VERSION="v1.2.4"\n')
            (sandbox / '.specify/integrations').mkdir(parents=True)
            (sandbox / '.specify/integration.json').write_text('{"version":"wrong"}')
            (sandbox / '.specify/init-options.json').write_text('{"speckit_version":"wrong"}')
            (sandbox / '.specify/integrations/claude.manifest.json').write_text('{"version":"wrong"}')
            result = run('bash', str(script), cwd=sandbox)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('python3 agent/spec-kit/refresh.py --upgrade', result.stdout)
            self.assertIn('python3 agent/spec-kit/refresh.py --check', result.stdout)
            for path in ('integration.json', 'init-options.json', 'claude.manifest.json'):
                self.assertIn(path + ' was generated', result.stdout)


if __name__ == '__main__':
    unittest.main(verbosity=2)
