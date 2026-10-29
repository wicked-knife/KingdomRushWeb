"""Require current, source-backed feedback acceptance before publishing."""
import hashlib
import json
from pathlib import Path
from verify_feedback_assets import verify as verify_assets

ROOT=Path(__file__).resolve().parents[1]
def read(path):return json.loads((ROOT/path).read_text(encoding='utf-8'))
def sha(path):return hashlib.sha256((ROOT/path).read_bytes()).hexdigest()

def verify():
    verify_assets()
    names=['feedback_logic','feedback_native_1280x720','feedback_native_1024x768','feedback_assets','feedback_combat_audit','followup_logic','followup_native_1280x720','followup_native_1024x768']
    reports={};hashes={}
    for name in names:
        path=f'reports/{name}.json';report=read(path);assert report['passed'],path
        for file,expected in report.get('source_hashes',{}).items():assert sha(file)==expected,(name,'stale',file)
        reports[name]={key:report[key] for key in ['passed','checks','content_combinations','layout_only','independent_scenarios','ticks','source_power_rows','source_cannon_scenarios','source_bomb_scenarios','source_guard_scenarios'] if key in report}
        hashes[path]=sha(path)
    logic=read('reports/feedback_logic.json')
    assert logic['checks']>=473 and len(logic['comparisons'])==11 and all(row['first_difference']==-1 for row in logic['comparisons'])
    assert len(read('reports/feedback_native_1280x720.json')['guard_scenes'])==14
    assert read('reports/feedback_native_1024x768.json')['layout_only']
    followup=read('reports/followup_logic.json')
    assert followup['checks']>=45 and len(followup['comparisons'])==11 and all(row['first_difference']==-1 for row in followup['comparisons'])
    assert len(read('reports/followup_native_1280x720.json')['guard_scenes'])==14
    assert read('reports/followup_native_1280x720.json')['checks']>=171
    assert read('reports/followup_native_1024x768.json')['layout_only']
    adjustments=read('tests/fixtures/feedback_combat_adjustments.json');audit=read('reports/feedback_combat_audit.json')
    assert sha('tests/fixtures/content_combat_baseline.json')==adjustments['historical_fixture_sha256']==audit['historical_fixture_sha256']
    assert sha('tests/fixtures/feedback_source.json')==adjustments['source_fixture_sha256']==audit['source_fixture_sha256']
    assert sha('tests/fixtures/followup_source.json')==adjustments['followup_source_fixture_sha256']==audit['followup_source_fixture_sha256']
    assert read('reports/content_unification.json')['passed']
    for path in ['tools/verify_feedback_delivery.py','tools/feedback_reference/main.lua','tools/feedback_reference/conf.lua','tools/prepare_feedback_reference.py','tools/followup_reference/main.lua','tools/followup_reference/conf.lua','tools/prepare_followup_reference.py','tests/capture_feedback_combat.gd','tests/report_writer.gd','tests/fixtures/feedback_source.json','tests/fixtures/followup_source.json','tests/fixtures/feedback_combat_adjustments.json','docs/FEEDBACK_REPAIRS.md','tools/web_bootstrap.py','tools/package_level01.py']:
        hashes[path]=sha(path)
    result={'passed':True,'reports':reports,'source_hashes':hashes,'historical_baseline_preserved':True,'content_combinations':21,'browser_tested':False,'guard_scope':'14 isolated and 14 all-guards-present passing-enemy scenes on real placements/routes; original selection/movement functions; native render queue follows each live unit exactly once and removes all dead units; static layout duplicates fixed'}
    (ROOT/'reports/feedback_delivery.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print({'passed':True,'reports':len(reports),'hashed_files':len(hashes)})
    return result
if __name__=='__main__':verify()
