"""Execute original Dove casts, bomb integration, sale and hover functions."""
import json, os, subprocess
from pathlib import Path
from dove_source import verify, provenance
ROOT=Path(__file__).resolve().parents[1]
SOURCE=Path('D:/projects/KingdomRushDove')
if __name__=='__main__':
    verify(SOURCE)
    data=json.loads((ROOT/'output/level06_export/evaluated.json').read_text(encoding='utf-8'))
    data['animations']=json.loads((ROOT/'assets/kingdom_rush/data/animations.json').read_text(encoding='utf-8'))['animations']
    data['provenance']=provenance(SOURCE,['all/scripts.lua','all/script_utils.lua','all/utils.lua','all/main_utils.lua','all-desktop/game_gui.lua','kr1/tower_scripts.lua','kr1/data/game_animations.bin'])
    (ROOT/'output/followup_reference_input.json').write_text(json.dumps(data),encoding='utf-8')
    subprocess.run(['D:/王国保卫战Dove版/love.exe',str(ROOT/'tools/followup_reference')],env=dict(os.environ,DOVE_SOURCE_DIR=str(SOURCE),DOVE_PROJECT=str(ROOT)),check=True,timeout=45)
    result=json.loads((ROOT/'tests/fixtures/followup_source.json').read_text(encoding='utf-8'))
    print({k:len(result[k]) for k in ('bombs','casts','sale','hover')})
