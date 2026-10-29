#!/usr/bin/env python3
"""Execute one configured mandatory story-cost hook, using PyYAML safely."""
from pathlib import Path
import os
import subprocess
import sys

import yaml

EVENTS = {'after_specify', 'after_tasks', 'after_analyze', 'after_implement', 'after_converge'}


def should_collect(event):
    config = Path('.specify/extensions.yml')
    if not config.exists():
        print(f'spec-kit: {event}: extensions.yml missing; no story-cost hook')
        return False
    data = yaml.safe_load(config.read_text())
    if data is None:
        data = {}
    if not isinstance(data, dict):
        raise ValueError('extensions.yml must be a mapping')
    hooks = data.get('hooks', {})
    if not isinstance(hooks, dict):
        raise ValueError('extensions.yml hooks must be a mapping')
    entries = hooks.get(event, [])
    if not isinstance(entries, list) or any(not isinstance(entry, dict) for entry in entries):
        raise ValueError(f'extensions.yml hooks.{event} must be a list of mappings')
    collect = False
    for entry in entries:
        if entry.get('command') != 'story-cost':
            continue  # Other commands remain the harness's generic dispatch responsibility.
        for flag in ('enabled', 'optional'):
            if flag in entry and not isinstance(entry[flag], bool):
                raise ValueError(f'{event} story-cost {flag} must be boolean')
        condition = entry.get('condition')
        if condition is not None and not isinstance(condition, str):
            raise ValueError(f'{event} story-cost condition must be a string or null')
        if entry.get('enabled', True) is False:
            print(f'spec-kit: {event}: disabled story-cost hook skipped')
        elif condition not in (None, ''):
            print(f'spec-kit: {event}: conditional story-cost hook deferred to HookExecutor')
        elif entry.get('optional', True):
            print(f'spec-kit: {event}: optional story-cost hook; run make story-cost only if requested')
        else:
            collect = True
    if not collect:
        print(f'spec-kit: {event}: no automatic story-cost hook to execute')
    return collect


def main():
    event = sys.argv[1] if len(sys.argv) == 2 else ''
    if event not in EVENTS:
        print('spec-kit: unsupported mandatory posthook event', file=sys.stderr)
        return 2
    try:
        collect = should_collect(event)
    except (OSError, ValueError, yaml.YAMLError) as error:
        print(f'spec-kit: cannot read mandatory hook configuration: {error}', file=sys.stderr)
        return 2
    if not collect:
        return 0
    result = subprocess.run(['make', 'story-cost'], check=False)
    if result.returncode:
        return result.returncode
    print('Accounting: Claude Code/OpenCode collected logs only; Codex/Devin unavailable (not zero).')
    # Match story-cost.sh's branch attribution and is_story_name validation (AD-014).
    story = os.environ.get('STORY')
    if not story:
        branch = subprocess.run(['git', 'rev-parse', '--abbrev-ref', 'HEAD'],
                                capture_output=True, text=True, check=False)
        story = branch.stdout.strip()
    if not story or story in {'.', '..', 'HEAD'} or '/' in story:
        return 0
    report = Path('specs') / story / 'cost.md'
    if report.is_file():
        for line in report.read_text().splitlines():
            if line.startswith(('Not priced', 'Shrunk')):
                print(line)
    return 0


if __name__ == '__main__':
    sys.exit(main())
