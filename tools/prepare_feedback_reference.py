"""Execute frozen Dove tooltip, cannon, bomb and soldier functions in bounded scenes."""
import json
import os
import subprocess
from pathlib import Path
from dove_source import verify, provenance

ROOT=Path(__file__).resolve().parents[1]
SOURCE=Path('D:/projects/KingdomRushDove')
if __name__=='__main__':
    verify(SOURCE)
    # These are the raw Lua evaluator outputs, before Godot adaptations/technology.
    inputs={str(i):json.loads((ROOT/f'output/level{i:02}_export/evaluated.json').read_text(encoding='utf-8')) for i in (5,6)}
    inputs['provenance']=provenance(SOURCE,['all/scripts.lua','all/script_utils.lua','all/utils.lua','all/seek.lua','all/path_db.lua','dove_modules/gui/text_utils.lua','_assets/kr1-desktop/strings/zh-Hans.lua'])
    (ROOT/'output/feedback_reference_input.json').write_text(json.dumps(inputs),encoding='utf-8')
    subprocess.run(['D:/王国保卫战Dove版/love.exe',str(ROOT/'tools/feedback_reference')],env=dict(os.environ,DOVE_SOURCE_DIR=str(SOURCE),DOVE_PROJECT=str(ROOT)),check=True,timeout=45)
    (ROOT/'output/feedback_reference.error').unlink(missing_ok=True)
    result=json.loads((ROOT/'tests/fixtures/feedback_source.json').read_text(encoding='utf-8'))
    print({k:len(result[k]) for k in ('powers','cannons','bombs','guards','slots')})
