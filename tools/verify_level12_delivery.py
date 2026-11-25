"""Current twelfth-stage acceptance; preserve all earlier content byte for byte."""
import copy
import hashlib
import json
from pathlib import Path
from campaign_content import combinations,export_spec,validate_definition
from verify_ending_assets import validate as validate_ending

ROOT=Path(__file__).resolve().parents[1]
def read(path):return json.loads((ROOT/path).read_text(encoding='utf-8'))
def sha(path):return hashlib.sha256((ROOT/path).read_bytes()).hexdigest()

def verify():
    baseline=read('tests/fixtures/level12_compatibility.json')
    for path,expected in baseline['sha256'].items():assert sha(path)==expected,('prior content changed',path)
    names=('level12_logic','level12_flow','level12_native_1280x720','level12_native_1024x768','level12_assets','kr1_end_assets','level11_shared_logic','level10_shared_logic','level11_upgrades','level11_ranged_shared','hero_combat_logic')
    reports={};hashes={};report_hashes={}
    for name in names:
        path=f'reports/{name}.json';report=read(path);assert report['passed'],path
        assert report.get('source_hashes') or name=='level12_assets',('missing freshness evidence',name)
        for file,expected in report.get('source_hashes',{}).items():
            assert sha(file)==expected,(name,'stale',file);hashes[file]=expected
        reports[name]={key:report[key] for key in ('passed','checks','independent_modes','timeline_waves','births','source_scenarios','source_patch_scenarios','frames','animations','layout_only','scope') if key in report}
        report_hashes[path]=sha(path)
    logic=read('reports/level12_logic.json')
    assert (logic['independent_modes'],logic['timeline_waves'],logic['births'])==(3,22,1110)
    assert logic['source_scenarios']>=12 and not logic['full_replays']
    for path in ('output/level12-logic.log','output/level12-flow.log','output/level12-native.log','output/level12-native-1024.log'):
        log=(ROOT/path).read_text(encoding='utf-8')
        assert 'SCRIPT ERROR:' not in log,('Godot script error',path)
        if 'native' in path:assert 'ERROR:' not in log,('native rendering/input error',path)
        hashes[path]=sha(path)
    assert len(combinations())==36
    for file,expected in read('reports/level12_assets.json')['sha256'].items():
        path='data/level12/'+file;assert sha(path)==expected,('stale asset',path);hashes[path]=expected
    definition=read('data/level12/definition.json');validate_definition(definition,export_spec(12))
    probes=[]
    def reject(label,fn):
        try:fn()
        except (AssertionError,ValueError,KeyError) as error:probes.append(dict(missing=label,rejected=True,reason=str(error)))
        else:raise AssertionError('Publication accepted missing '+label)
    for name in ('eb_veznan','veznan_soul','veznan_souls_aura','veznan_portal','mod_veznan_tower','decal_eb_veznan_white_circle','decal_s12_shoutbox'):
        broken=copy.deepcopy(definition);del broken['templates'][name]
        reject(name,lambda:validate_definition(broken,export_spec(12)))
    broken=copy.deepcopy(definition);broken['behaviors']['eb_veznan']='unsupported.missing'
    reject('boss behavior',lambda:validate_definition(broken,export_spec(12)))
    broken=copy.deepcopy(definition);broken['templates']['eb_veznan']['health'].pop('on_damage',None)
    reject('boss lethal callback',lambda:validate_definition(broken,export_spec(12)))
    from web_bootstrap import resource_paths,validate_runtime_resources
    resources,data=resource_paths()
    reject('boss runtime module',lambda:validate_runtime_resources([p for p in resources if not p.endswith('/dove_veznan.gd')]))
    end=read('data/kr1_end/definition.json');atlas=read('data/kr1_end/atlas.json');sounds=read('data/kr1_end/sounds.json');manifest=read('data/kr1_end/manifest.json')
    broken=copy.deepcopy(atlas);broken['lookup'].clear()
    reject('comic frames',lambda:validate_ending(end,broken,sounds,manifest))
    broken=copy.deepcopy(end);broken['comics'][0][0]['order']=[]
    reject('comic drawing order',lambda:validate_ending(broken,atlas,sounds,manifest))
    broken=copy.deepcopy(sounds);del broken['MusicSuspense']
    reject('epilogue audio',lambda:validate_ending(end,atlas,broken,manifest))
    states={row['state'] for row in read('reports/level12_native_1280x720.json')['captures']}
    assert {'twelfth_transform','twelfth_demon','twelfth_death','twelfth_white_expanded','twelfth_death_end','comic1_final','comic2_final','map_settlement','twelfth_mode2','twelfth_mode3'}<=states
    for path in resources+data:hashes[path.removeprefix('res://')]=sha(path.removeprefix('res://'))
    for path in ['tools/verify_level12_delivery.py','tools/web_bootstrap.py','tools/web_packs.py','tools/package_level01.py','tools/prepare_level12_reference.py','tests/verify_web_pack.gd','tests/fixtures/level12_compatibility.json']+[p.relative_to(ROOT).as_posix() for p in (ROOT/'tools/level12_reference').glob('*.lua')]:hashes[path]=sha(path)
    result=dict(passed=True,playable_combinations=36,reports=reports,failure_probes=probes,source_hashes=hashes,report_sha256=report_hashes,browser_tested=False,victory_replays_required=False,credits_data=False,compatibility=dict(base_commit=baseline['base_commit'],exact_files=len(baseline['sha256'])),historical_scope='Levels 1-11 and ranger arena data unchanged byte for byte; current representative JT, graveyard, technology, Malik and shared combat regressions.')
    (ROOT/'reports/level12_delivery.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(dict(passed=True,reports=len(reports),failure_probes=len(probes),playable_combinations=36));return result

if __name__=='__main__':verify()
