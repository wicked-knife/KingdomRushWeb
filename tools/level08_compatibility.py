"""Audit older content after removing the exact declared level-eight additions.

The manifest is anchored to 20f7188; existing gameplay and logical atlas metadata
must reproduce it exactly. Repacked PNG pixels are checked against Dove source.
"""
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'tests/fixtures/level08_additions.json'
PROJECTED_OUT = {'behaviors', 'dependencies', 'callbacks'}


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False,
                                     separators=(',', ':')).encode()).hexdigest()


def before_eighth(name, value, part='definition', gameplay=False):
    value = copy.deepcopy(value)
    spec = json.loads(MANIFEST.read_text(encoding='utf-8'))['contents'].get(name, {}).get(part)
    if not spec:
        return value
    for path in spec['added']:
        if gameplay and path[0] in PROJECTED_OUT:
            continue
        owner = value
        for key in path[:-1]:
            owner = owner[key]
        assert path[-1] in owner, (name, part, 'missing declared addition', path)
        del owner[path[-1]]
    for row in spec['converted']:
        owner = value
        for key in row['path'][:-1]:
            owner = owner[key]
        assert owner[row['path'][-1]] == row['after'], (name, part, row['path'])
        owner[row['path'][-1]] = row['before']
    logical = copy.deepcopy(value)
    if part == 'atlas':
        for frame in logical['frames'].values():
            frame.pop('sheet', None)
            frame.pop('region', None)
    expected = spec['baseline_gameplay_sha256' if gameplay else 'baseline_sha256']
    assert digest(logical) == expected, (name, part, 'pre-existing content changed')
    return value
