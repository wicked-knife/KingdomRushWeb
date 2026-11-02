"""Check exact pre-ninth logical content plus independent repacked source pixels."""
import copy
import hashlib
import json
from pathlib import Path
from level09_compatibility import before_ninth, digest, MANIFEST

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8'))


def verify():
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
    hashes = {}
    rows = []
    for name, parts in manifest['contents'].items():
        for part, spec in parts.items():
            path = f'data/{name}/{part}.json'
            old = before_ninth(name, read(path), part)
            if part == 'atlas':
                for frame in old['frames'].values():
                    frame.pop('sheet', None)
                    frame.pop('region', None)
            assert digest(old) == spec['baseline_sha256'], (name, part, 'old content changed')
            hashes[path] = hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
        assets = read(f'reports/{name}_assets.json')
        assert assets['passed']
        for path, expected in assets['sha256'].items():
            assert hashlib.sha256((ROOT / f'data/{name}/{path}').read_bytes()).hexdigest() == expected
        rows.append({'content': name, 'parts': len(parts), 'prior_content_unchanged': True, 'source_pixels_verified': True})
    probes = []
    for case in ('old_stat', 'missing_new_template', 'unlisted_upgrade'):
        bad = copy.deepcopy(read('data/level06/definition.json'))
        if case == 'old_stat':
            bad['templates']['enemy_goblin']['health']['hp_max'] += 1
        elif case == 'missing_new_template':
            del bad['templates']['tower_sorcerer']
        else:
            bad['upgrade_targets']['tower_mage_3'].append('unknown')
        try:
            old = before_ninth('level06', bad)
            assert digest(old) == manifest['contents']['level06']['definition']['baseline_sha256']
        except (AssertionError, KeyError):
            probes.append({'case': case, 'rejected': True})
        else:
            raise AssertionError('Accepted unapproved ' + case)
    for path in ('tests/fixtures/level09_additions.json', 'tools/level09_compatibility.py', 'tools/verify_level09_compatibility.py'):
        hashes[path] = hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
    result = dict(passed=True, baseline_commit=manifest['baseline_commit'], contents=rows, failure_probes=probes, source_hashes=hashes)
    (ROOT / 'reports/level09_compatibility.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print({'passed': True, 'contents': len(rows), 'failure_probes': len(probes)})
    return result


if __name__ == '__main__':
    verify()
