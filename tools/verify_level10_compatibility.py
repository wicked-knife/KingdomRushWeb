"""Verify prior logical content and independently checked repacked pixels."""
import copy
import hashlib
import json
from level10_compatibility import ROOT, MANIFEST, before_tenth, digest


def sha(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def verify():
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
    hashes, contents = {}, []
    for name, parts in manifest['contents'].items():
        for part, spec in parts.items():
            path = f'data/{name}/{part}.json'
            value = json.loads((ROOT / path).read_text(encoding='utf-8'))
            assert digest(before_tenth(name, value, part)) == spec['baseline_sha256'], (name, part)
            hashes[path] = sha(path)
        if name.startswith('level') and int(name[-2:]) >= 4:
            report = json.loads((ROOT / f'reports/{name}_assets.json').read_text(encoding='utf-8'))
            assert report['passed']
            for file, expected in report['sha256'].items():
                path = f'data/{name}/{file}'
                assert sha(path) == expected, path
                hashes[path] = expected
        contents.append({'content': name, 'parts': len(parts), 'prior_content_unchanged': True})
    probes = []
    for case in ('old_stat', 'missing_tesla', 'unknown_branch'):
        bad = json.loads((ROOT / 'data/level04/definition.json').read_text(encoding='utf-8'))
        if case == 'old_stat':
            bad['templates']['enemy_goblin']['health']['hp_max'] += 1
        elif case == 'missing_tesla':
            del bad['templates']['tower_tesla']
        else:
            bad['upgrade_targets']['tower_engineer_3'].append('unknown')
        try:
            assert digest(before_tenth('level04', bad)) == manifest['contents']['level04']['definition']['baseline_sha256']
        except (AssertionError, KeyError):
            probes.append({'case': case, 'rejected': True})
        else:
            raise AssertionError('Accepted ' + case)
    for path in ('tests/fixtures/level10_additions.json', 'tools/level10_compatibility.py', 'tools/verify_level10_compatibility.py'):
        hashes[path] = sha(path)
    result = dict(passed=True, baseline_commit=manifest['baseline_commit'], contents=contents,
                  failure_probes=probes, source_hashes=hashes, historical_baselines_preserved=True)
    (ROOT / 'reports/level10_compatibility.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print({'passed': True, 'contents': len(contents), 'failure_probes': len(probes)})
    return result


if __name__ == '__main__':
    verify()
