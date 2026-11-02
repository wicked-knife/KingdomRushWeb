"""Reverse only the reviewed 2.1.0.6 delta before checking frozen baselines.

Every replacement requires its exact new value; unlisted changes remain visible
to the historical fingerprint checks. Source hashes are pinned in the delta.
"""
import copy
import json
from pathlib import Path
from level09_compatibility import before_ninth

DELTA = json.loads((Path(__file__).resolve().parents[1] /
                   'tests/fixtures/dove_2106_delta.json').read_text(encoding='utf-8'))


def before_current(name, value, part='definition'):
    value = before_ninth(name, value, part)
    for row in DELTA['contents'].get(name, {}).get(part, []):
        owner = value
        for key in row['path'][:-1]:
            owner = owner[key]
        key = row['path'][-1]
        assert owner[key] == row['after'], (name, part, 'unapproved current delta', row['path'])
        if row.get('added'):
            del owner[key]
        else:
            owner[key] = copy.deepcopy(row['before'])
    return value
