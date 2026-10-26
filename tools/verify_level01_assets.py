"""Validate frozen input hashes, all runtime animation/audio references and repacked pixels."""
from pathlib import Path
import argparse, hashlib, json, math
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]

def read(path): return json.loads(path.read_text(encoding="utf-8"))
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def verify(level_id=1):
    level_name=f"level{level_id:02d}"
    folder=ROOT/f"data/{level_name}"; manifest=read(folder/"manifest.json"); data=read(folder/"definition.json")
    source=Path("D:/projects/KingdomRushDove")
    for name,digest in data["source"]["inputs"].items(): assert sha(source/name)==digest, name
    for name,digest in manifest["source_texture_hashes"].items(): assert sha(ROOT/name)==digest, name
    for resource in manifest["data"]+manifest["resources"]: assert (ROOT/resource.removeprefix("res://")).is_file(),resource
    atlas=read(folder/"atlas.json"); animations=read(folder/"animations.json")["animations"]
    # Every default sprite must resolve, including suffixes such as explosion_big
    # and explode_small. Merely validating already-selected animations misses them.
    for template_name,template in data["templates"].items():
        for sprite in template.get("render",{}).get("sprites",[]):
            name=sprite.get("name", "").replace("%04i","0001")
            key=sprite.get("prefix", "")+"_"+name if sprite.get("prefix") else name
            assert key in animations or name in atlas["lookup"], (template_name,key)
        info=template.get("info",{})
        if info.get("portrait"): assert info["portrait"] in atlas["lookup"],template_name
    for template_name,template in data["templates"].items():
        if "bullet" not in template: continue
        bullet=data["templates"][template_name]["bullet"]
        for key in ["hit_fx","hit_decal","hit_blood_fx"]:
            if bullet.get(key): assert bullet[key] in data["templates"],(template_name,key)
        if level_id == 4 and bullet.get("hit_fx_water"): assert bullet["hit_fx_water"] in data["templates"],template_name
    for name,definition in animations.items():
        for number in definition["frames"]: assert f"{definition['prefix']}_{int(number):04d}" in atlas["lookup"],name
    images={}; originals={}; original_atlases={}
    for name,f in atlas["frames"].items():
        group=f["source_group"]
        if group not in original_atlases: original_atlases[group]=read(ROOT/f"assets/kingdom_rush/data/atlases/{group}.json")
        old=original_atlases[group]["frames"][f["source_frame"]]
        for field in ["logical_size","original_size","trim","ref_scale"]: assert f[field]==old[field],(name,field)
        original_path=ROOT/"assets/kingdom_rush/kr1-desktop/images/fullhd"/old["sheet"]
        if original_path not in originals: originals[original_path]=Image.open(original_path).convert("RGBA")
        if f["sheet"] not in images: images[f["sheet"]]=Image.open(folder/f["sheet"]).convert("RGBA")
        x,y,w,h=f["region"]; ox,oy,ow,oh=old["region"]
        width=math.ceil(ox+ow)-math.floor(ox); height=math.ceil(oy+oh)-math.floor(oy)
        a=originals[original_path].crop((math.floor(ox),math.floor(oy),math.floor(ox)+width,math.floor(oy)+height))
        b=images[f["sheet"]].crop((math.floor(x),math.floor(y),math.floor(x)+width,math.floor(y)+height))
        assert a.tobytes()==b.tobytes(),name
    for alias,canonical in atlas["lookup"].items(): assert canonical in atlas["frames"],alias
    for im in [*images.values(),*originals.values()]: im.close()
    report={"passed":True,"source_commit":data["source"]["commit"],"source_inputs":len(data["source"]["inputs"]),"frames":len(atlas["lookup"]),"canonical_frames":len(atlas["frames"]),"animations":len(animations),"resources":len(manifest["resources"]),"sha256":{p.name:sha(p) for p in sorted(folder.glob('*')) if p.suffix in ['.json','.png']}}
    (ROOT/f"reports/{level_name}_assets.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({k:v for k,v in report.items() if k!='sha256'}))

if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--level",type=int,choices=[1,2,3,4],default=1)
    verify(parser.parse_args().level)
