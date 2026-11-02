"""Check the pinned source transition against all pre-update logical files."""
import hashlib
import json
from pathlib import Path
from dove_source import ROOT, SOURCE, verify
from dove_2106_compatibility import DELTA, before_current


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False,
                                    separators=(',', ':')).encode()).hexdigest()


def run():
    source = ROOT.parent / 'KingdomRushDove'
    verify(source)
    assert SOURCE == DELTA['source_after']
    hashes = {}
    for relative, expected in DELTA['baseline_sha256'].items():
        path = ROOT / relative
        current = json.loads(path.read_text(encoding='utf-8'))
        assert digest(before_current(path.parent.name, current, path.stem)) == expected, relative
        hashes[relative] = sha(path)
        if path.stem == 'definition':
            assert all(current['source'][k] == SOURCE[k] for k in SOURCE), relative
            for name, value in current['source']['inputs'].items():
                assert sha(source / name) == value, (relative, name)
    catalog = json.loads((ROOT / 'data/campaign_content.json').read_text(encoding='utf-8'))
    registered = ['data/heroes/definition.json', 'data/map_kr1/definition.json',
                  'data/upgrades/definition.json', 'data/save/definition.json']
    registered += ['data/' + row['folder'] + '/definition.json' for row in catalog['combat_heroes'].values()]
    for relative in registered:
        value = json.loads((ROOT / relative).read_text(encoding='utf-8'))
        assert value['source']['commit'] == SOURCE['commit']
        for name, expected in value['source']['inputs'].items():
            assert sha(source / name) == expected, (relative, name)
        hashes[relative] = sha(ROOT / relative)
    for relative in ['tools/verify_dove_update.py', 'tools/dove_2106_compatibility.py',
                     'tests/fixtures/dove_2106_delta.json']:
        hashes[relative] = sha(ROOT / relative)
    report = dict(passed=True, source=SOURCE, baseline=DELTA['source_before'],
                  logical_files=len(DELTA['baseline_sha256']),
                  scope='Exact declared source, scorch, animation alias, power enumeration and atlas coordinate changes; all other fields preserved',
                  source_hashes=hashes)
    (ROOT / 'reports/dove_2106_transition.json').write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print({'passed': True, 'logical_files': report['logical_files']})


if __name__ == '__main__':
    run()
