#!/usr/bin/env python3
"""Regenerate the project preset through Specify 1.2.4, or check drift offline."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HARNESSES = ('claude', 'codex', 'opencode', 'devin')
SURFACES = ('.specify', '.claude/skills', '.agents/skills', '.devin/skills', '.opencode/commands')


def run(root, *args):
    subprocess.run(args, cwd=root, check=True)


def protected(root):
    """State refresh must never rewrite, including ignored per-checkout pointers."""
    paths = [root / '.specify/extensions.yml', root / '.specify/feature.json']
    paths += sorted((root / 'specs').rglob('*')) if (root / 'specs').exists() else []
    return {str(p.relative_to(root)): p.read_bytes() if p.exists() else None
            for p in paths if not p.is_dir()}


def snapshot(root):
    result = {}
    for surface in SURFACES:
        for path in sorted((root / surface).rglob('*')):
            if not path.is_file() or '__pycache__' in path.parts:
                continue
            rel = str(path.relative_to(root))
            if rel.startswith('.specify/integrations/packages'):
                continue
            data = path.read_bytes()
            if rel == '.specify/presets/.registry':
                obj = json.loads(data)
                for preset in obj.get('presets', {}).values():
                    preset.pop('installed_at', None)  # CLI records install time, not content.
                data = json.dumps(obj, sort_keys=True).encode()
            result[rel] = (data, path.stat().st_mode & 0o111)
    return result


def restore_script_modes(root):
    # Specify rewrites these scripts without executable bits during reconciliation.
    for path in (root / '.specify/scripts/bash').glob('*.sh'):
        path.chmod(path.stat().st_mode | 0o111)


def refresh(root, upgrade=False):
    before = protected(root)
    state = json.loads((root / '.specify/integration.json').read_text())
    if set(state['installed_integrations']) != set(HARNESSES):
        raise RuntimeError('Expected exactly claude, codex, opencode and devin integrations')
    original_default = state.get('default_integration', state.get('integration', 'claude'))
    if original_default not in HARNESSES:
        raise RuntimeError('Default integration is not installed')
    try:
        if upgrade:
            for harness in HARNESSES:
                run(root, 'specify', 'integration', 'upgrade', harness, '--force')
        registry = root / '.specify/presets/.registry'
        installed = registry.exists() and 'sre-compact' in json.loads(registry.read_text()).get('presets', {})
        args = ('update', 'sre-compact') if installed else ('add',)
        run(root, 'specify', 'preset', *args, '--dev', 'agent/spec-kit/preset')
        for harness in HARNESSES:
            run(root, 'specify', 'integration', 'use', harness)
        run(root, 'python3', 'agent/spec-kit/generate-entrypoints.py')
    finally:
        try:
            run(root, 'specify', 'integration', 'use', original_default)
        finally:
            try:
                restore_script_modes(root)
            finally:
                if protected(root) != before:
                    raise RuntimeError('Refresh changed a story, extensions.yml or feature pointer')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='regenerate a temporary copy and compare')
    parser.add_argument('--upgrade', action='store_true', help='refresh upstream integration artifacts too')
    args = parser.parse_args()
    if args.check and args.upgrade:
        parser.error('--check is offline; use --upgrade separately')
    if not shutil.which('specify'):
        parser.exit(1, 'Specify 1.2.4 is required; run make install first.\n')
    version = subprocess.check_output(['specify', '--version'], text=True).strip()
    if version.split()[-1] != '1.2.4':
        parser.exit(1, f'Expected Specify 1.2.4, got {version}\n')
    if args.check:
        with tempfile.TemporaryDirectory(prefix='sre-speckit-check-') as directory:
            sandbox = Path(directory)
            for surface in (*SURFACES, 'agent/spec-kit'):
                shutil.copytree(ROOT / surface, sandbox / surface, dirs_exist_ok=True)
            refresh(sandbox)
            before, after = snapshot(ROOT), snapshot(sandbox)
            drift = sorted(p for p in before.keys() | after.keys() if before.get(p) != after.get(p))
            if drift:
                parser.exit(1, 'Spec Kit regeneration drift:\n' + '\n'.join(drift) + '\n')
        print('spec-kit: regeneration consistent across all four harnesses')
    else:
        refresh(ROOT, args.upgrade)


if __name__ == '__main__':
    main()
