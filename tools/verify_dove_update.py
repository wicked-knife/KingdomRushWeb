"""Check the pinned Dove source commit and input hashes across all registered content."""
import hashlib
import json
from dove_source import ROOT, SOURCE, verify


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run():
    source = ROOT.parent / 'KingdomRushDove'
    verify(source)
    catalog = json.loads((ROOT / 'data/campaign_content.json').read_text(encoding='utf-8'))
    assert catalog['source'] == SOURCE, 'campaign_content.json source mismatch'
    registered = ['data/' + row['folder'] + '/definition.json' for row in catalog['levels'].values()]
    registered += ['data/' + row['folder'] + '/definition.json' for row in catalog.get('arenas', {}).values()]
    registered += ['data/heroes/definition.json', 'data/map_kr1/definition.json',
                   'data/upgrades/definition.json', 'data/save/definition.json']
    registered += ['data/' + row['folder'] + '/definition.json' for row in catalog.get('combat_heroes', {}).values()]
    hashes = {}
    for relative in registered:
        value = json.loads((ROOT / relative).read_text(encoding='utf-8'))
        assert all(value['source'].get(k) == SOURCE[k] for k in SOURCE), relative
        for name, expected in value['source'].get('inputs', {}).items():
            assert sha(source / name) == expected, (relative, name)
        hashes[relative] = sha(ROOT / relative)
    for relative in ['data/campaign_content.json', 'tools/verify_dove_update.py', 'tools/dove_source.py']:
        hashes[relative] = sha(ROOT / relative)
    report = dict(passed=True, source=SOURCE, registered_definitions=len(registered),
                  scope='Direct verification of current Dove commit and source input hashes across all registered definitions',
                  source_hashes=hashes)
    (ROOT / 'reports/dove_2106_transition.json').write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print({'passed': True, 'registered_definitions': len(registered)})


if __name__ == '__main__':
    run()
