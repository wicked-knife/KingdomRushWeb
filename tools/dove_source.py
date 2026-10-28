"""The published content catalog is the single current Dove source baseline."""
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = json.loads((ROOT / 'data/campaign_content.json').read_text(encoding='utf-8'))['source']
BASE = SOURCE['commit']
VERSION = SOURCE['version']


def verify(source):
    actual = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    assert actual == BASE, f'Dove source {actual} differs from content catalog {BASE}'
    assert not subprocess.check_output(['git', '-C', str(source), 'status', '--porcelain'], text=True).strip(), 'Dove source must be clean'


def provenance(source, inputs):
    return dict(SOURCE, inputs={p: hashlib.sha256((source / p).read_bytes()).hexdigest() for p in sorted(inputs)})
