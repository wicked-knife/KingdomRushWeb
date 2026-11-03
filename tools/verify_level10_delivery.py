"""Current scoped acceptance for stage ten; historical reports remain historical."""
import copy
import hashlib
import json
from pathlib import Path
from campaign_content import combinations, export_spec, validate_definition
from verify_level10_compatibility import verify as compatibility

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8'))


def sha(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def verify():
    compatibility()
    reports, hashes, report_hashes = {}, {}, {}
    names = ('level10_logic', 'level10_upgrades', 'level10_native_1280x720',
             'level10_assets', 'level10_compatibility', 'level10_shared_logic',
             'sorcerer_trail_logic', 'tesla_animation_logic', 'tesla_animation_native', 'misc_presentation_logic', 'battle_details_logic', 'hero_combat_logic')
    for name in names:
        path = f'reports/{name}.json'
        report = read(path)
        assert report['passed'], path
        if name != 'level10_assets':
            assert report.get('source_hashes'), ('missing freshness evidence', name)
        for file, expected in report.get('source_hashes', {}).items():
            assert sha(file) == expected, (name, 'stale', file)
            hashes[file] = expected
        reports[name] = {key: report[key] for key in ('passed', 'checks', 'independent_modes',
                         'timeline_waves', 'births', 'source_patch_scenarios', 'behavior_scenarios',
                         'frames', 'animations', 'scope') if key in report}
        report_hashes[path] = sha(path)
    logic = read('reports/level10_logic.json')
    assert (logic['independent_modes'], logic['timeline_waves'], logic['births']) == (3, 26, 1160)
    assert not logic['full_replays']
    assert read('reports/level10_upgrades.json')['source_patch_scenarios'] == 16
    states = {row['state'] for row in read('reports/level10_native_1280x720.json')['captures']}
    assert {'tenth_tesla_chain', 'tenth_tesla_finished', 'tenth_tesla_ray_end',
            'tenth_skeleton_aura', 'tenth_skeleton_aura_end', 'tenth_sorcerer_trail',
            'tenth_mode2', 'tenth_mode3'} <= states
    assert len(combinations()) == 30
    for file, expected in read('reports/level10_assets.json')['sha256'].items():
        path = 'data/level10/' + file
        assert sha(path) == expected, ('asset stale', path)
        hashes[path] = expected
    definition = read('data/level10/definition.json')
    validate_definition(definition, export_spec(10))
    probes = []
    for name in ('tower_tesla', 'ray_tesla', 'mod_ray_tesla', 'ps_tesla_overcharge',
                 'aura_demon_death', 'mod_demon_shield', 'enemy_skeleton_big', 'graveyard'):
        broken = copy.deepcopy(definition)
        if name == 'graveyard':
            name = next(e['template'] for e in broken['layout']['entities_list'] if 'graveyard' in broken['templates'].get(e['template'], {}))
        del broken['templates'][name]
        try:
            validate_definition(broken, export_spec(10))
        except ValueError as error:
            probes.append({'missing': name, 'rejected': True, 'reason': str(error)})
        else:
            raise AssertionError('Publication accepted missing ' + name)
    # Include export inputs so modifying code/resources after export invalidates packaging.
    from web_bootstrap import resource_paths
    resources, data = resource_paths()
    for path in resources + data:
        relative = path.removeprefix('res://')
        hashes[relative] = sha(relative)
    for path in ('tools/verify_level10_delivery.py', 'tools/web_bootstrap.py', 'tools/package_level01.py',
                 'tools/prepare_level10_reference.py', 'tools/level10_reference/main.lua',
                 'tools/level10_reference/behavior.lua', 'tests/verify_web_pack.gd'):
        hashes[path] = sha(path)
    result = dict(passed=True, playable_combinations=30, reports=reports, failure_probes=probes,
                  source_hashes=hashes, report_sha256=report_hashes, browser_tested=False,
                  victory_replays_required=False, historical_reports_revalidated=False,
                  historical_scope='Prior configuration preserved by exact additive audit against 1775c0e; shared runtime checked with representative current scenarios. Previous native multi-resolution reports are historical evidence only.')
    (ROOT / 'reports/level10_delivery.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print({'passed': True, 'reports': len(reports), 'failure_probes': len(probes), 'playable_combinations': 30})
    return result


if __name__ == '__main__':
    verify()
