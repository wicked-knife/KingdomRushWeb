"""Audit the exact old-content baseline and reject unauthorized historical changes."""
import copy
import hashlib
import json
from pathlib import Path
from level08_compatibility import before_eighth, MANIFEST
from prepare_level01 import gameplay_projection

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8'))


def sha(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def verify():
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
    rows = []
    hashes = {}
    for name, parts in manifest['contents'].items():
        for part in parts:
            path = f'data/{name}/{part}.json'
            before_eighth(name, read(path), part)
            hashes[path] = sha(path)
        before_eighth(name, gameplay_projection(read(f'data/{name}/definition.json')), gameplay=True)
        assets = read(f'reports/{name}_assets.json')
        assert assets['passed'], name
        for file, expected in assets['sha256'].items():
            path = f'data/{name}/{file}'
            assert sha(path) == expected, (name, file, 'source pixel report stale')
            hashes[path] = expected
        rows.append({'content': name, 'parts': len(parts), 'prior_content_unchanged': True,
                     'source_pixels_verified': True})
    probes = []
    for case in ('old_stat', 'old_frame', 'unlisted_upgrade_edge', 'wrong_scorch', 'stale_current_source'):
        part = 'animations' if case == 'old_frame' else 'definition'
        bad = copy.deepcopy(read(f'data/level06/{part}.json'))
        if case == 'old_stat':
            bad['templates']['enemy_goblin']['health']['hp_max'] += 1
        elif case == 'old_frame':
            added = {path[1] for path in manifest['contents']['level06']['animations']['added']}
            key = next(k for k in bad['animations'] if k not in added)
            bad['animations'][key]['frames'][0] += 1
        elif case == 'unlisted_upgrade_edge':
            bad['upgrade_targets']['tower_barrack_3'].append('tower_unknown')
        elif case == 'wrong_scorch':
            bad['templates']['power_scorched_earth']['aura']['damage_min'] += 1
        else:
            bad['source']['commit'] = 'stale'
        try:
            before_eighth('level06', bad, part)
        except AssertionError:
            probes.append({'case': case, 'rejected': True})
        else:
            raise AssertionError('Historical audit accepted ' + case)
    for path in ('tests/fixtures/level08_additions.json', 'tools/level08_compatibility.py',
                 'tools/verify_level08_compatibility.py', 'tools/dove_2106_compatibility.py',
                 'tests/fixtures/dove_2106_delta.json'):
        hashes[path] = sha(path)
    result = {'passed': True, 'baseline_commit': manifest['baseline_commit'], 'contents': rows,
              'failure_probes': probes, 'source_hashes': hashes}
    (ROOT / 'reports/level08_compatibility.json').write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print({'passed': True, 'contents': len(rows), 'parts': sum(r['parts'] for r in rows),
           'failure_probes': len(probes)})


if __name__ == '__main__':
    verify()
