"""Combine current seventh-stage acceptance and fail-closed publication probes."""
import copy
import hashlib
import json
from pathlib import Path
from campaign_content import read_catalog, validate_definition, export_spec, combinations

ROOT = Path(__file__).resolve().parents[1]
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path): return json.loads((ROOT / path).read_text(encoding='utf-8'))

def verify():
    names = ['level07_logic','level07_native_1280x720','level07_native_1024x768',
             'level07_assets','content_catalog','content_unification']
    reports = {}
    hashes = {}
    for name in names:
        path = f'reports/{name}.json'; report = read(path)
        assert report['passed'], path
        for file, expected in report.get('source_hashes', {}).items():
            assert sha(ROOT / file) == expected, f'{name} stale: {file}'
        reports[name] = {k: report[k] for k in ('passed','checks','independent_modes','timeline_waves','births','content_combinations','source_scenarios','source_coroutines','layout_only','frames','animations','full_replays') if k in report}
        hashes[path] = sha(ROOT / path)
    for file, expected in read('reports/level07_assets.json')['sha256'].items():
        assert sha(ROOT / 'data/level07' / file) == expected, file
        hashes['data/level07/'+file] = expected
    definition=read('data/level07/definition.json'); probes=[]
    for name in ('pop_headshot','mod_van_helsing_crosshair','ps_shotgun_musketeer','aura_troll_regen','tunnel__101'):
        broken=copy.deepcopy(definition);del broken['templates'][name]
        try: validate_definition(broken,export_spec(7))
        except ValueError as error: probes.append({'missing':name,'rejected':True,'reason':str(error)})
        else: raise AssertionError('publication accepted '+name)
    for path in ['data/campaign_content.json','tools/verify_level07_delivery.py','tools/level07_reference/main.lua',
                 'tools/level07_reference/behavior.lua','tools/prepare_level07_reference.py','tests/fixtures/level07_source.json',
                 'tests/fixtures/level07_additions.json','scripts/battle/dove_musketeer.gd','scripts/battle/dove_snow.gd',
                 'scripts/battle/dove_targeting.gd','scripts/battle/dove_modifiers.gd','scripts/battle/dove_behaviors.gd',
                 'scripts/battle/level01_sim.gd','scripts/battle/battle_view.gd','scripts/battle/battle_ui.gd']:
        hashes[path]=sha(ROOT/path)
    assert len(combinations())==21
    result={'passed':True,'source':read_catalog()['source'],'playable_combinations':21,'reports':reports,
            'failure_probes':probes,'source_hashes':hashes,'browser_tested':False,'victory_replays_required':False,
            'additive_audit':'tests/fixtures/level07_additions.json; prior gameplay, UI metadata and source pixels retained'}
    (ROOT/'reports/level07_delivery.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print({'passed':True,'reports':len(reports),'failure_probes':len(probes),'hashed_files':len(hashes)})

if __name__=='__main__': verify()
