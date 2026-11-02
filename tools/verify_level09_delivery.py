"""Require source, logic, native, resource and compatibility evidence for stage nine."""
import copy
import hashlib
import json
from pathlib import Path
from campaign_content import combinations, export_spec, validate_definition
from verify_level09_compatibility import verify as verify_compatibility

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8'))


def sha(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def verify():
    verify_compatibility()
    reports, hashes = {}, {}
    for name in ('level09_logic', 'level09_native_1280x720', 'level09_native_1024x768',
                 'level09_assets', 'level09_compatibility', 'level09_upgrades'):
        path = f'reports/{name}.json'
        report = read(path)
        assert report['passed'], path
        for file, expected in report.get('source_hashes', {}).items():
            assert sha(file) == expected, (name, 'stale', file)
        reports[name] = {k: report[k] for k in ('passed', 'checks', 'independent_modes', 'births', 'timeline_waves', 'source_tower_scenarios', 'source_patch_scenarios', 'layout_only') if k in report}
        hashes[path] = sha(path)
    logic = read('reports/level09_logic.json')
    assert logic['births'] == 995 and logic['timeline_waves'] == 26 and logic['independent_modes'] == 3
    assert logic['source_tower_scenarios'] == 9 and not logic['full_replays']
    assert read('reports/level09_upgrades.json')['source_patch_scenarios'] == 16
    native = read('reports/level09_native_1280x720.json')
    assert not native['layout_only'] and native['checks'] >= 160
    assert {'ninth_elemental_raise', 'ninth_sheep_hidden', 'ninth_jt_wait_click', 'ninth_jt_death_end', 'ninth_frozen_tower', 'ninth_thaw_end', 'ninth_mode2', 'ninth_mode3'} <= {row['state'] for row in native['captures']}
    assert {'ninth_cave_node0', 'ninth_cave_node8', 'ninth_cave_node20'} <= {row['state'] for row in native['captures']}
    assert read('reports/level09_native_1024x768.json')['layout_only']
    assert len(combinations()) == 27
    for file, expected in read('reports/level09_assets.json')['sha256'].items():
        assert sha('data/level09/' + file) == expected, ('asset stale', file)
        hashes['data/level09/' + file] = expected
    definition = read('data/level09/definition.json')
    validate_definition(definition, export_spec(9))
    probes = []
    for name in ('mod_jt_tower', 'jt_spawner_aura', 'enemy_sheep_fly', 'soldier_elemental', 'fx_mod_polymorph_sorcerer_big', 'jt_damage_callback', 'slayer_callback'):
        bad = copy.deepcopy(definition)
        if name == 'jt_damage_callback':
            del bad['templates']['eb_jt']['health']['on_damage']
        elif name == 'slayer_callback':
            del bad['templates']['enemy_slayer']['melee']['attacks'][0]['side_effect']
        else:
            del bad['templates'][name]
        try:
            validate_definition(bad, export_spec(9))
        except ValueError as error:
            probes.append({'missing': name, 'rejected': True, 'reason': str(error)})
        else:
            raise AssertionError('Publication accepted missing ' + name)
    for path in ('data/campaign_content.json', 'tools/verify_level09_delivery.py', 'tools/prepare_level09_reference.py', 'tools/level09_reference/main.lua', 'tools/level09_reference/behavior.lua', 'tests/verify_web_pack.gd'):
        hashes[path] = sha(path)
    result = dict(passed=True, playable_combinations=27, reports=reports, failure_probes=probes,
                  source_hashes=hashes, browser_tested=False, victory_replays_required=False)
    (ROOT / 'reports/level09_delivery.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print({'passed': True, 'reports': len(reports), 'failure_probes': len(probes)})
    return result


if __name__ == '__main__':
    verify()
