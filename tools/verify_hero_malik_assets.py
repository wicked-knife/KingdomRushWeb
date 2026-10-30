"""Check Malik source provenance, all dependencies, animation frames and pixels."""
import hashlib
import json
import math
from pathlib import Path
from PIL import Image
from dove_source import verify

ROOT=Path(__file__).resolve().parents[1]
FOLDER=ROOT/"data/hero_malik_combat"
def read(p):return json.loads(p.read_text(encoding="utf-8"))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def check():
    source=Path("D:/projects/KingdomRushDove");verify(source)
    data=read(FOLDER/"definition.json");manifest=read(FOLDER/"manifest.json")
    atlas=read(FOLDER/"atlas.json");animations=read(FOLDER/"animations.json")["animations"]
    for path,digest in data["source"]["inputs"].items():assert sha(source/path)==digest,path
    for path,digest in manifest["source_texture_hashes"].items():assert sha(ROOT/path)==digest,path
    for path in manifest["resources"]+manifest["data"]:assert (ROOT/path.removeprefix("res://")).is_file(),path
    for owner,children in data["dependencies"].items():
        for child in children:assert child in data["templates"],(owner,child)
    for name,animation in animations.items():
        for frame in animation["frames"]:assert f"{animation['prefix']}_{int(frame):04d}" in atlas["lookup"],name
    for name,template in data["templates"].items():
        for sprite in template.get("render",{}).get("sprites",[]):
            key=(sprite.get("prefix","")+"_" if sprite.get("prefix") else "")+sprite["name"]
            dynamic=all(f"{sprite.get('prefix','')}_{size}_{sprite['name']}" in animations for size in sprite.get("size_names",[])) if sprite.get("size_names") else False
            assert key in animations or sprite["name"] in atlas["lookup"] or dynamic,(name,key)
        for key in ["portrait","hero_portrait"]:
            image=template.get("info",{}).get(key)
            if image:assert image in atlas["lookup"],image
    images={};originals={};groups={}
    for name,frame in atlas["frames"].items():
        group=frame["source_group"]
        if group not in groups:groups[group]=read(ROOT/f"assets/kingdom_rush/data/atlases/{group}.json")
        old=groups[group]["frames"][frame["source_frame"]]
        for field in ["logical_size","original_size","trim","ref_scale"]:assert frame[field]==old[field],(name,field)
        path=ROOT/"assets/kingdom_rush/kr1-desktop/images/fullhd"/old["sheet"]
        if path not in originals:originals[path]=Image.open(path).convert("RGBA")
        if frame["sheet"] not in images:images[frame["sheet"]]=Image.open(FOLDER/frame["sheet"]).convert("RGBA")
        ox,oy,w,h=old["region"];x,y=frame["region"][:2]
        width=math.ceil(ox+w)-math.floor(ox);height=math.ceil(oy+h)-math.floor(oy)
        a=originals[path].crop((math.floor(ox),math.floor(oy),math.floor(ox)+width,math.floor(oy)+height))
        b=images[frame["sheet"]].crop((math.floor(x),math.floor(y),math.floor(x)+width,math.floor(y)+height))
        assert a.tobytes()==b.tobytes(),name;a.close();b.close()
    for im in [*images.values(),*originals.values()]:im.close()
    hashes={p.relative_to(ROOT).as_posix():sha(p) for p in FOLDER.iterdir() if p.suffix in [".json",".png"]}
    hashes["tools/verify_hero_malik_assets.py"]=sha(Path(__file__))
    report={"passed":True,"frames":len(atlas["lookup"]),"canonical_frames":len(atlas["frames"]),"animations":len(animations),"templates":len(data["templates"]),"source_hashes":hashes,"browser_tested":False}
    (ROOT/"reports/hero_malik_assets.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    print({k:v for k,v in report.items() if k!="source_hashes"})
if __name__=="__main__":check()
