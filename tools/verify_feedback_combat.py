"""Recheck frozen source-backed combat adjustments against a current Godot run.

The historical snapshots and the explicit before/after adjustments are inputs;
this verifier never records new expected combat hashes.
"""
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8'))


def sha(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def compare(current, historical, adjustments):
    summary = {}
    if not current.get('passed') or not current.get('historical_baseline_preserved'):
        raise ValueError('Current Godot historical-combat check must pass')
    if current.get('combat_scenarios') != 3 or current.get('combat_ticks') != 3600:
        raise ValueError('Current check must cover all three bounded combat scenarios')
    for level in ('1', '3', '5'):
        before = historical['samples'][level]
        expected = before.copy()
        for row in adjustments['adjustments'][level]:
            index = row['sample']
            if expected[index] != row['before']:
                raise ValueError(f'{level}/{index}: adjustment does not match historical input')
            expected[index] = row['after']
        actual = current['samples'][level]
        if len(actual) != 12 or actual != expected:
            first = next((i for i, (a, b) in enumerate(zip(actual, expected)) if a != b),
                         min(len(actual), len(expected)))
            raise ValueError(f'{level}: current combat differs at sample {first}')
        summary[level] = {'samples': len(actual), 'historical': before,
                          'expected_after_source_repairs': expected, 'actual': actual,
                          'first_difference': -1}
    return summary


def verify():
    current = read('reports/content_unification.json')
    historical = read('tests/fixtures/content_combat_baseline.json')
    adjustments = read('tests/fixtures/feedback_combat_adjustments.json')
    for path, expected in current['source_hashes'].items():
        assert sha(path) == expected, ('historical combat evidence stale', path)
    for path, field in (
        ('tests/fixtures/content_combat_baseline.json', 'historical_fixture_sha256'),
        ('tests/fixtures/feedback_source.json', 'source_fixture_sha256'),
        ('tests/fixtures/followup_source.json', 'followup_source_fixture_sha256'),
    ):
        assert sha(path) == adjustments[field], ('frozen fixture changed', path)
    summary = compare(current, historical, adjustments)
    probes = []
    bad = copy.deepcopy(current)
    bad['samples']['1'][0] = 'unapproved combat change'
    wrong = copy.deepcopy(adjustments)
    wrong['adjustments']['1'][0]['before'] = 'different historical input'
    for name, report, rules in (('unapproved_current_state', bad, adjustments),
                                ('wrong_historical_input', current, wrong)):
        try:
            compare(report, historical, rules)
        except ValueError as error:
            probes.append({'case': name, 'rejected': True, 'reason': str(error)})
        else:
            raise AssertionError('Combat audit accepted ' + name)
    inputs = ('reports/content_unification.json', 'tests/fixtures/content_combat_baseline.json',
              'tests/fixtures/feedback_combat_adjustments.json', 'tests/fixtures/feedback_source.json',
              'tests/fixtures/followup_source.json', 'tools/verify_feedback_combat.py',
              'scripts/battle/level01_sim.gd', 'scripts/battle/dove_projectile.gd')
    result = {'passed': True, 'historical_baseline_preserved': True,
              'independent_scenarios': 3, 'ticks': 3600, 'samples': 36,
              'historical_fixture_sha256': adjustments['historical_fixture_sha256'],
              'source_fixture_sha256': adjustments['source_fixture_sha256'],
              'followup_source_fixture_sha256': adjustments['followup_source_fixture_sha256'],
              'published_pck_sha256': adjustments['published_pck_sha256'],
              'published_pck_rerun': False, 'basis': adjustments['basis'],
              'summary': summary, 'failure_probes': probes,
              'source_hashes': {path: sha(path) for path in inputs}}
    (ROOT / 'reports/feedback_combat_audit.json').write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print({'passed': True, 'combat_scenarios': 3, 'samples': 36, 'failure_probes': len(probes)})
    return result


if __name__ == '__main__':
    verify()
