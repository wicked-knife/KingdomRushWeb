"""Require current source, logic, native, resource and old-content evidence for stage eight."""
import copy
import hashlib
import json
from pathlib import Path
from campaign_content import combinations, export_spec, validate_definition
from verify_level08_compatibility import verify as verify_compatibility

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8'))


def sha(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def validate_eighth(definition):
    validate_definition(definition, export_spec(8))


def verify():
    verify_compatibility()
    reports = {}
    hashes = {}
    names = ('level08_logic', 'level08_native_1280x720', 'level08_native_1024x768',
             'level08_assets', 'level08_compatibility', 'level07_logic',
             'content_catalog', 'content_unification', 'upgrades_logic')
    for name in names:
        path = f'reports/{name}.json'
        report = read(path)
        assert report['passed'], path
        for file, expected in report.get('source_hashes', {}).items():
            assert sha(file) == expected, (name, 'stale', file)
        reports[name] = {key: report[key] for key in ('passed', 'checks', 'independent_modes',
            'births', 'timeline_waves', 'source_scenarios', 'content_combinations', 'layout_only') if key in report}
        hashes[path] = sha(path)
    logic = read('reports/level08_logic.json')
    assert logic['independent_modes'] == 3 and logic['births'] == 1097
    assert logic['source_scenarios'] == 72 and not logic['full_replays']
    native = read('reports/level08_native_1280x720.json')
    assert not native['layout_only'] and native['checks'] >= 180
    captured = {row['state'] for row in native['captures']}
    assert {'eighth_opening', 'eighth_barbarian_twister', 'eighth_barbarian_corpse',
            'eighth_chieftain_rage', 'eighth_thawed_camp', 'eighth_sasquash_attack',
            'eighth_sasquash_corpse', 'eighth_sasquash_respawn', 'eighth_yeti_area',
            'eighth_axe_thrower_shoot', 'eighth_mode2', 'eighth_mode3'} <= captured
    assert read('reports/level08_native_1024x768.json')['layout_only']
    assert len(combinations()) == 24
    for file, expected in read('reports/level08_assets.json')['sha256'].items():
        path = f'data/level08/{file}'
        assert sha(path) == expected, (path, 'asset evidence stale')
        hashes[path] = expected
    definition = read('data/level08/definition.json')
    validate_eighth(definition)
    probes = []
    for name in ('tower_sasquash_holder', 'soldier_sasquash', 'missile_bfg',
                 'mod_bfg_stun', 'axe_barbarian_rude', 'enemy_troll_chieftain', 'missile_callback'):
        bad = copy.deepcopy(definition)
        if name == 'missile_callback':
            del bad['callbacks']['missile_bfg']['remove']
        else:
            del bad['templates'][name]
        try:
            validate_eighth(bad)
        except ValueError as error:
            probes.append({'missing': name, 'rejected': True, 'reason': str(error)})
        else:
            raise AssertionError('Publication accepted missing ' + name)
    for path in ('data/campaign_content.json', 'tools/verify_level08_delivery.py',
                 'tools/prepare_level08_reference.py', 'tools/level08_reference/main.lua',
                 'tools/level08_reference/behavior.lua', 'tests/fixtures/level08_source.json',
                 'tests/verify_web_pack.gd'):
        hashes[path] = sha(path)
    result = {'passed': True, 'playable_combinations': 24, 'reports': reports,
              'failure_probes': probes, 'source_hashes': hashes,
              'browser_tested': False, 'victory_replays_required': False}
    (ROOT / 'reports/level08_delivery.json').write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print({'passed': True, 'reports': len(reports), 'failure_probes': len(probes)})
    return result


if __name__ == '__main__':
    verify()
