"""Check source hashes, CSV layers, repacked ending pixels and media closure."""
import hashlib
import json
import math
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
SOURCE=Path('D:/projects/KingdomRushDove')
def read(path):return json.loads(path.read_text(encoding='utf-8'))
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def validate(definition,atlas,sounds,manifest):
    assert len(definition['comics'])==2 and 'credits' not in definition
    for comic in definition['comics']:
        assert comic
        for page in comic:
            assert set(page['order'])==set(page['sprites']) and page['order']
            for sprite in page['sprites'].values():
                assert sprite['image'] in atlas['lookup'],sprite['image']
                assert sprite['keys'] and all(a[0]<=b[0] for a,b in zip(sprite['keys'],sprite['keys'][1:]))
            for label in page['labels']:assert label['sprite'] in page['sprites'] and label['text']
    assert set(sounds)=={'MusicEndCredits','MusicSuspense','GUINotificationPaperOver'}
    for path in manifest['resources']+manifest['data']:assert (ROOT/path.removeprefix('res://')).is_file(),path

def verify():
    folder=ROOT/'data/kr1_end';definition=read(folder/'definition.json');atlas=read(folder/'atlas.json');sounds=read(folder/'sounds.json');manifest=read(folder/'manifest.json')
    validate(definition,atlas,sounds,manifest)
    for name,digest in definition['source']['inputs'].items():assert sha(SOURCE/name)==digest,name
    for name,digest in manifest['source_texture_hashes'].items():assert sha(ROOT/name)==digest,name
    groups={};images={}
    for name,f in atlas['frames'].items():
        group=f['source_group']
        if group not in groups:groups[group]=read(ROOT/f'assets/kingdom_rush/data/atlases/{group}.json')
        original=groups[group]['frames'][f['source_frame']]
        for key in ('logical_size','original_size','trim','ref_scale'):assert original[key]==f[key],(name,key)
        path=ROOT/groups[group]['texture_directory'].removeprefix('res://')/original['sheet']
        for image in (path,folder/f['sheet']):
            if image not in images:images[image]=Image.open(image).convert('RGBA')
        x,y,w,h=f['region'];a,b,c,d=original['region'];width,height=math.ceil(a+c)-math.floor(a),math.ceil(b+d)-math.floor(b)
        assert images[path].crop((math.floor(a),math.floor(b),math.floor(a)+width,math.floor(b)+height)).tobytes()==images[folder/f['sheet']].crop((math.floor(x),math.floor(y),math.floor(x)+width,math.floor(y)+height)).tobytes(),name
    for image in images.values():image.close()
    paths=list(folder.glob('*.json'))+list(folder.glob('*.png'))+[ROOT/'tools/prepare_ending.py',ROOT/'tools/verify_ending_assets.py',ROOT/'tools/ending_export/main.lua']
    result=dict(passed=True,comic_pages=[len(c) for c in definition['comics']],frames=len(atlas['frames']),credits_data=False,source_hashes={p.relative_to(ROOT).as_posix():sha(p) for p in paths})
    (ROOT/'reports/kr1_end_assets.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print({k:v for k,v in result.items() if k!='source_hashes'})
    return result

if __name__=='__main__':verify()
