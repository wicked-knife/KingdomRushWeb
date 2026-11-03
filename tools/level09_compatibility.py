"""Reverse only exact reviewed ninth-stage additions; retain historical snapshots."""
import copy
import hashlib
import json
from pathlib import Path

MANIFEST = Path(__file__).resolve().parents[1] / 'tests/fixtures/level09_additions.json'


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False,
                                    separators=(',', ':')).encode()).hexdigest()


def before_ninth(name, value, part='definition'):
    from level10_compatibility import before_tenth
    value = before_tenth(name, value, part)
    spec = json.loads(MANIFEST.read_text(encoding='utf-8'))['contents'].get(name, {}).get(part)
    if not spec:
        return value
    for row in reversed(spec['delta']):
        path = row['path']
        if path[0] in ('behaviors', 'callbacks', 'dependencies') and path[0] not in value:
            continue  # gameplay_projection explicitly excludes these sections.
        owner = value
        for key in path[:-1]:
            owner = owner[key]
        actual = owner[path[-1]]
        if part == 'atlas' and path[0] == 'frames':
            actual = {k: v for k, v in actual.items() if k not in ('sheet', 'region')}
        assert actual == row['after'], (name, part, 'unapproved ninth delta', path)
        if row.get('added'):
            del owner[path[-1]]
        else:
            owner[path[-1]] = copy.deepcopy(row['before'])
    for name, sheet, region, after_sheet, after_region in spec.get('geometry', []):
        frame = value['frames'][name]
        assert (frame['sheet'], frame['region']) == (after_sheet, after_region), (part, name, 'unapproved atlas geometry')
        frame['sheet'], frame['region'] = sheet, copy.deepcopy(region)
    return value
