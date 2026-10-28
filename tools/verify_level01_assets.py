"""Validate frozen input hashes, all runtime animation/audio references and repacked pixels."""
from pathlib import Path
import argparse, hashlib, json, math
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]

def read(path): return json.loads(path.read_text(encoding="utf-8"))
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def verify(level_id=1, ranger_arena=False):
    if ranger_arena: level_id=4
    level_name="ranger_arena" if ranger_arena else f"level{level_id:02d}"
    folder=ROOT/f"data/{level_name}"; manifest=read(folder/"manifest.json"); data=read(folder/"definition.json")
    source=Path("D:/projects/KingdomRushDove")
    for name,digest in data["source"]["inputs"].items(): assert sha(source/name)==digest, name
    for name,digest in manifest["source_texture_hashes"].items(): assert sha(ROOT/name)==digest, name
    for resource in manifest["data"]+manifest["resources"]: assert (ROOT/resource.removeprefix("res://")).is_file(),resource
    if not ranger_arena:
        assert set(data["modes"]) == {"2", "3"}
        for mode in (2, 3):
            selected=data["modes"][str(mode)]
            assert selected["waves"]["cash"] == {2:[230,310,400,750,1000,1200],3:[360,275,660,1500,1500,800]}[mode][level_id-1]
            assert selected["waves"]["lives"] == 1 and len(selected["waves"]["groups"]) == (6 if mode==2 else 1)
            assert all(e.get("editor.game_mode",0) in (0,mode) for e in selected["layout"]["entities_list"])
            assert f"kr1/data/waves/level{level_id:02d}_waves_{'heroic' if mode==2 else 'iron'}.lua" in data["source"]["inputs"]
            for e in selected["layout"]["entities_list"]:
                if "tower.holder_id" in e: assert e["template"] in data["templates"]
            for group in selected["waves"]["groups"]:
                for wave in group["waves"]:
                    assert 1 <= wave["path_index"] <= len(data["paths"]["paths"])
                    for spawn in wave["spawns"]:
                        for key in ("creep","creep_aux"):
                            if spawn.get(key): assert spawn[key] in data["templates"]
        if level_id==5:
            towers={str(e["tower.holder_id"]):e["template"] for e in data["modes"]["3"]["layout"]["entities_list"] if "tower.holder_id" in e}
            assert {site for site,t in towers.items() if t=="tower_archer_3"}=={"1","3","4"}
            assert {site for site,t in towers.items() if t=="tower_elf_holder"}=={"5","7"}
    atlas=read(folder/"atlas.json"); animations=read(folder/"animations.json")["animations"]
    # Every default sprite must resolve, including suffixes such as explosion_big
    # and explode_small. Merely validating already-selected animations misses them.
    for template_name,template in data["templates"].items():
        for sprite in template.get("render",{}).get("sprites",[]):
            name=sprite.get("name", "").replace("%04i","0001")
            key=sprite.get("prefix", "")+"_"+name if sprite.get("prefix") else name
            assert key in animations or name in atlas["lookup"], (template_name,key)
            if ranger_arena or level_id >= 5:
                for prefix in sprite.get("size_prefixes",[]):
                    for state in ("start","loop","end"): assert prefix+"_"+state in animations,(template_name,prefix,state)
                for state in sprite.get("size_names",[]):
                    states=[state+"_"+c for c in ("red","green","gray","orange","violet")] if sprite.get("use_blood_color") else [state]
                    for variant in states: assert sprite.get("prefix","")+"_"+variant in animations,(template_name,variant)
        info=template.get("info",{})
        if info.get("portrait"): assert info["portrait"] in atlas["lookup"],template_name
    for template_name,template in data["templates"].items():
        if "bullet" not in template: continue
        bullet=data["templates"][template_name]["bullet"]
        for key in ["hit_fx","hit_decal","hit_blood_fx"]:
            if bullet.get(key): assert bullet[key] in data["templates"],(template_name,key)
        if level_id >= 4 and bullet.get("hit_fx_water"): assert bullet["hit_fx_water"] in data["templates"],template_name
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
    from campaign_content import level_ids
    parser.add_argument("--level",type=int,choices=level_ids(),default=1)
    parser.add_argument("--ranger-arena",action="store_true")
    args=parser.parse_args()
    verify(args.level,args.ranger_arena)
