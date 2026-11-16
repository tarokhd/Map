#!/usr/bin/env python3
"""Reject stale mobile bundles or accidental edits to a shared packaged runtime."""
import argparse
import hashlib
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('bundles', nargs='+', type=Path)
args = parser.parse_args()
fingerprints = []
for bundle in args.bundles:
    manifest = json.loads((bundle / 'world-manifest.json').read_text())
    for source, hashes in manifest['files'].items():
        assert hashlib.sha256((ROOT / source).read_bytes()).hexdigest() == hashes['source'], f'{source} differs from current shared source'
        assert hashlib.sha256((bundle / Path(source).name).read_bytes()).hexdigest() == hashes['bundled'], f'{bundle}: packaged file changed'
    expected = {str(p.relative_to(ROOT)) for p in (ROOT / 'web').glob('*.mjs')}
    assert expected <= manifest['files'].keys(), 'New shared module was not packaged'
    fingerprints.append(manifest['files'])
assert all(f == fingerprints[0] for f in fingerprints), 'Mobile platforms package different World runtimes'
print(f'PASS: {len(args.bundles)} mobile bundle(s) match shared runtime source and each other.')
