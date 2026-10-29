"""Exact feedback additions over the previously published seven-level package.

Only listed copy corrections and added UI data/frames are projected away.
Pre-existing gameplay, animation metadata and pixels remain audited separately.
"""
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'tests/fixtures/feedback_additions.json'

def before_feedback(name, value, part='definition'):
    value=copy.deepcopy(value)
    spec=json.loads(MANIFEST.read_text(encoding='utf-8')).get(name,{}).get(part)
    if not spec:return value
    for path in spec['added']:
        owner=value
        for key in path[:-1]:owner=owner[key]
        assert path[-1] in owner, (name,part,path)
        del owner[path[-1]]
    for row in spec['converted']:
        owner=value
        for key in row['path'][:-1]:owner=owner[key]
        assert owner[row['path'][-1]]==row['after'],(name,part,row['path'])
        owner[row['path'][-1]]=row['before']
    return value
