"""Current stage-twelve acceptance with exact preservation of earlier content."""
import copy
import hashlib
import json
from pathlib import Path
from campaign_content import combinations, export_spec, validate_definition

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8'))


def sha(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def verify():
    baseline = read('tests/fixtures/level12_compatibility.json')
    for path, expected in baseline['sha256'].items():
        assert sha(path) == expected, ('prior content changed', path)
    reports, hashes, report_hashes = {}, {}, {}
    names = (
        'level12_logic', 'level12_upgrades', 'level12_native_1280x720', 'level12_assets',
        'level09_logic', 'level10_logic', 'hero_combat_logic', 'tesla_animation_logic',
    )
    for name in names:
        path = f'reports/{name}.json'
        report = read(path)
        assert report['passed'], path
        if name in ('level12_logic', 'level12_upgrades', 'level12_native_1280x720'):
            assert report.get('source_hashes'), ('missing freshness evidence', name)
            for file, expected in report.get('source_hashes', {}).items():
                assert sha(file) == expected, (name, 'stale', file)
                hashes[file] = expected
        reports[name] = {
            key: report[key]
            for key in ('passed', 'checks', 'independent_modes', 'timeline_waves', 'births',
                        'source_patch_scenarios', 'source_scenarios', 'frames', 'animations', 'scope')
            if key in report
        }
        report_hashes[path] = sha(path)
    logic = read('reports/level12_logic.json')
    assert (logic['independent_modes'], logic['timeline_waves'], logic['births']) == (3, 22, 1110)
    assert not logic['full_replays']
    assert read('reports/level12_upgrades.json')['source_patch_scenarios'] == 16
    states = {row['state'] for row in read('reports/level12_native_1280x720.json')['captures']}
    assert {
        'twelfth_opening', 'twelfth_castle_taunt', 'twelfth_tower_lock',
        'twelfth_portal_active', 'twelfth_soul_drain', 'twelfth_demon_fire',
        'twelfth_death_souls', 'twelfth_white_circle', 'twelfth_victory_natural',
        'twelfth_mode2', 'twelfth_mode3', 'twelfth_defeat_mode3',
    } <= states
    assert len(combinations()) == 36
    for file, expected in read('reports/level12_assets.json')['sha256'].items():
        path = 'data/level12/' + file
        assert sha(path) == expected, ('asset stale', path)
        hashes[path] = expected
    definition = read('data/level12/definition.json')
    validate_definition(definition, export_spec(12))
    probes = []
    for name in (
        'eb_veznan', 'mod_veznan_tower', 'veznan_portal', 'veznan_souls_aura',
        'veznan_soul', 'ps_veznan_soul', 'decal_s12_shoutbox', 'decal_eb_veznan_white_circle',
    ):
        broken = copy.deepcopy(definition)
        del broken['templates'][name]
        try:
            validate_definition(broken, export_spec(12))
        except ValueError as error:
            probes.append({'missing': name, 'rejected': True, 'reason': str(error)})
        else:
            raise AssertionError('Publication accepted missing ' + name)
    from web_bootstrap import resource_paths, validate_runtime_resources
    resources, data = resource_paths()
    broken = copy.deepcopy(definition)
    broken['behaviors']['eb_veznan'] = 'unsupported.missing'
    try:
        validate_definition(broken, export_spec(12))
    except ValueError as error:
        probes.append({'missing': 'veznan behavior', 'rejected': True, 'reason': str(error)})
    else:
        raise AssertionError('Publication accepted unsupported veznan behavior')
    try:
        validate_runtime_resources([p for p in resources if not p.endswith('/dove_veznan.gd')])
    except ValueError as error:
        probes.append({'missing': 'veznan runtime resource', 'rejected': True, 'reason': str(error)})
    else:
        raise AssertionError('Publication accepted missing veznan runtime resource')
    for path in resources + data:
        relative = path.removeprefix('res://')
        hashes[relative] = sha(relative)
    paths = [
        'tools/verify_level12_delivery.py', 'tools/web_bootstrap.py', 'tools/package_level01.py',
        'tools/prepare_level12_reference.py', 'tests/verify_web_pack.gd',
        'tests/fixtures/level12_compatibility.json',
    ]
    paths += [p.relative_to(ROOT).as_posix() for p in (ROOT / 'tools/level12_reference').glob('*') if p.suffix in ('.lua', '.gd')]
    for path in paths:
        hashes[path] = sha(path)
    result = dict(
        passed=True, playable_combinations=36, reports=reports, failure_probes=probes,
        source_hashes=hashes, report_sha256=report_hashes, browser_tested=False,
        victory_replays_required=False, historical_reports_revalidated=False,
        compatibility=dict(base_commit=baseline['base_commit'], exact_files=len(baseline['sha256'])),
        historical_scope='Levels 1-11 and ranger arena data unchanged byte for byte; representative shared runtime regressions run on current code.',
    )
    (ROOT / 'reports/level12_delivery.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print({'passed': True, 'reports': len(reports), 'failure_probes': len(probes), 'playable_combinations': 36})
    return result


if __name__ == '__main__':
    verify()
