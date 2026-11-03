"""Reverse exact tenth-stage additions without rewriting historical fixtures."""
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'tests/fixtures/level10_additions.json'


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False,
                                    separators=(',', ':')).encode()).hexdigest()


def before_tenth(name, value, part='definition'):
    value = copy.deepcopy(value)
    spec = json.loads(MANIFEST.read_text(encoding='utf-8'))['contents'].get(name, {}).get(part)
    if not spec:
        return value
    for row in reversed(spec['delta']):
        path = row['path']
        if path[0] in ('behaviors', 'callbacks', 'dependencies') and path[0] not in value:
            continue
        owner = value
        for key in path[:-1]:
            owner = owner[key]
        assert owner[path[-1]] == row['after'], (name, part, 'unapproved tenth delta', path)
        if row.get('added'):
            del owner[path[-1]]
        else:
            owner[path[-1]] = copy.deepcopy(row['before'])
    return value
