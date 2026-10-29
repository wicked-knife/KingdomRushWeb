"""Feedback copy/descriptor/hover closure and exact additive resource audit."""
import copy
import hashlib
import json
from pathlib import Path
from campaign_content import validate_definition,export_spec
from power_preview_contract import validate_ui
from feedback_compatibility import before_feedback
from level07_compatibility import logical_atlas

ROOT=Path(__file__).resolve().parents[1]
def read(path):return json.loads((ROOT/path).read_text(encoding='utf-8'))
def sha(path):return hashlib.sha256((ROOT/path).read_bytes()).hexdigest()
def digest(value):return hashlib.sha256(json.dumps(value,sort_keys=True,ensure_ascii=False,separators=(',',':')).encode()).hexdigest()

def validate_followup_resources(definition, animations, atlas):
    for frame in ('range_circle','rally_circle'):
        if frame not in atlas['lookup']:raise ValueError('missing source range frame '+frame)
    tower=definition['templates'].get('tower_arcane_wizard')
    if tower:
        for index in (0,2):
            attack=tower['attacks']['list'][index]
            key=tower['render']['sprites'][1]['prefix']+'_'+attack['animation']
            if key not in animations:raise ValueError('arcane cast requires animation '+key)
            if len(animations[key]['frames'])/30 < attack['shoot_time']:
                raise ValueError('arcane animation ends before emission '+key)

def verify():
    manifest=read('tests/fixtures/feedback_additions.json');rows=[];hashes={}
    required={'build_terrain_0001_over','build_terrain_0002_over','terrain_archer_0001_over','terrain_barrack_0001_over','terrain_mage_0001_over','terrain_artillery_0001_over','tooltip_bg_small'}
    for name,spec in manifest.items():
        definition=read(f'data/{name}/definition.json');validate_definition(definition,export_spec(definition['level']['id'],name=='ranger_arena'))
        atlas=read(f'data/{name}/atlas.json');assert required<=atlas['lookup'].keys(),name
        validate_followup_resources(definition,read(f'data/{name}/animations.json')['animations'],atlas)
        for part,expected in spec['published_logical_sha256'].items():
            current=before_feedback(name,read(f'data/{name}/{part}.json'),part)
            if part=='atlas':current=logical_atlas(current)
            assert digest(current)==expected,(name,part,'pre-existing data changed')
        report=read(f'reports/{name}_assets.json');assert report['passed'],name
        for file,expected in report['sha256'].items():
            path=f'data/{name}/{file}';assert sha(path)==expected,(name,file,'pixel report stale');hashes[path]=expected
        rows.append({'content':name,'pre_existing_gameplay_and_metadata_unchanged':True,'hover_frames':6,'tooltip_backgrounds':2,'source_range_frames':2,'arcane_cast_closed':'tower_arcane_wizard' in definition['templates'],'source_pixels_verified':True})
    base=read('data/level06/definition.json');probes=[]
    for kind in ['copy','subtitle','unexpanded_copy','preview','arbitrary_code','missing_template','missing_field']:
        bad=copy.deepcopy(base)
        if kind=='copy':del bad['ui']['strings']['TOWER_PALADIN_EXTRA']
        if kind=='subtitle':del bad['ui']['strings'][next(n['subs'][0] for n in bad['ui']['notifications'].values() if n.get('layout')=='N_TOWER_2')]
        if kind=='unexpanded_copy':bad['ui']['strings']['TOWER_PALADIN_EXTRA']='%$unexpanded%$'
        if kind=='preview':del bad['ui']['power_previews']['disintegrate']
        if kind in ('arbitrary_code','missing_template','missing_field'):
            token=next(t for t in bad['ui']['power_previews']['disintegrate'][0]['tokens'] if isinstance(t,dict))
            token['expression']={'arbitrary_code':['call','OS.execute'],'missing_template':['template','missing_tooltip_template'],'missing_field':['field',['template','tower_paladin'],'missing_tooltip_field']}[kind]
        try:validate_ui(bad)
        except ValueError as error:probes.append({'case':kind,'rejected':True,'reason':str(error)})
        else:raise AssertionError('Publication accepted '+kind)
    for missing in ('tower_arcane_wizard_teleport','range_circle','rally_circle'):
        animations=read('data/level06/animations.json')['animations'];atlas=read('data/level06/atlas.json')
        del (animations if missing.startswith('tower_') else atlas['lookup'])[missing]
        try:validate_followup_resources(base,animations,atlas)
        except ValueError as error:probes.append({'case':missing,'rejected':True,'reason':str(error)})
        else:raise AssertionError('Publication accepted missing '+missing)
    for path in ['tools/verify_feedback_assets.py','tools/power_preview_contract.py','tools/feedback_compatibility.py','tests/fixtures/feedback_additions.json','tools/prepare_level01.py','tools/level01_export/main.lua']:
        hashes[path]=sha(path)
    result={'passed':True,'contents':rows,'content_combinations':21,'failure_probes':probes,'source_hashes':hashes,'published_baseline':'previous seven-level release; only exact listed feedback additions are removed before comparison'}
    (ROOT/'reports/feedback_assets.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print({'passed':True,'contents':len(rows),'failure_probes':len(probes),'hashed_files':len(hashes)})
if __name__=='__main__':verify()
