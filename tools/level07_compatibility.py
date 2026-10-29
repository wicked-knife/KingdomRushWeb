"""Explicit level-seven additions over the unchanged six-level baseline.

The committed manifest lists additions and ordered upgrade-edge conversions.
It never authorizes changes to pre-existing unit stats, waves, layouts or pixels.
"""
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'tests/fixtures/level07_additions.json'

def before_seventh(name, value, part='definition'):
    value = copy.deepcopy(value)
    spec = json.loads(MANIFEST.read_text(encoding='utf-8')).get(name, {}).get(part)
    if not spec:
        return value
    for path in spec['added']:
        owner = value
        for key in path[:-1]:
            owner = owner.get(key, {})
        owner.pop(path[-1], None)
    for row in spec['converted']:
        owner = value
        for key in row['path'][:-1]: owner = owner[key]
        assert owner[row['path'][-1]] == row['after'], row
        owner[row['path'][-1]] = row['before']
    return value

def logical_atlas(value):
    value = copy.deepcopy(value)
    for frame in value['frames'].values():
        frame.pop('sheet', None); frame.pop('region', None)
    return value
