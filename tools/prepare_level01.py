"""Evaluate frozen Dove data offline and build a small, source-traceable first-level atlas."""
from pathlib import Path
import argparse, hashlib, json, math, os, re, subprocess
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BASE = "e29ece82939fd73fb69bfc4b469d484a72e4dfd2"

def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False)+"\n", encoding="utf-8")

def prepare(source, love):
    assert subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip() == BASE
    assert not subprocess.check_output(["git", "-C", str(source), "status", "--porcelain"], text=True).strip(), "Reference must be clean"
    folder=ROOT/"output/level01_export";folder.mkdir(parents=True,exist_ok=True)
    evaluated=folder/"evaluated.json"
    env=os.environ.copy();env.update(DOVE_SOURCE_DIR=str(source),DOVE_EXPORT_PATH=str(evaluated))
    run=subprocess.run([str(love),str(ROOT/"tools/level01_export")],env=env,capture_output=True,timeout=60)
    if run.returncode: raise RuntimeError(evaluated.with_suffix(".json.error").read_text(encoding="utf-8"))
    data=json.loads(evaluated.read_text(encoding="utf-8"))
    inputs=set(data.pop("inputs"))|{"all-desktop/game_gui.lua","all-desktop/gg_views_custom.lua","kr1/data/tower_menus_data_scripts.lua","all/constants.lua","lib/klua/table.lua","lib/klua/vector.lua","all/entity_db.lua","all/utils.lua","all/script_utils.lua","all/wave_utils.lua","all/systems/wave_spawn.lua","all/systems/enemy.lua","kr1/game_settings.lua","all/difficulty.lua","all/scripts.lua","kr1/tower_scripts.lua","kr1/data/levels/level01.lua"}
    inputs.add("all/tower_utils.lua")
    inputs.add("all/systems/health.lua")
    data["source"]={"version":"2.1.0.2","commit":BASE,"difficulty":2,"inputs":{p:hashlib.sha256((source/p).read_bytes()).hexdigest() for p in sorted(inputs)}}
    # GGTextLabel slide and TutorialBalloon class defaults are part of the source layout.
    for slide_id, labels in data["ui"]["slides"].items():
        for label in labels:
            label.setdefault("font_name", "body" if slide_id.startswith("TB_") else "body_slides")
    data["schema_version"]=1
    settings=(source/"kr1/game_settings.lua").read_text(encoding="utf-8")
    def scalar(key): return float(re.search(r"GS\."+key+r"\s*=\s*([\d.]+)",settings)[1])
    def normal(key): return float(re.search(r"GS\."+key+r"\s*=\s*\{([^}]+)",settings)[1].split(",")[1])
    data["rules"]={"enemy_hp_factor":normal("difficulty_enemy_hp_max_factor"),"enemy_speed_factor":normal("difficulty_enemy_speed_factor"),"enemy_gold_factor":normal("difficulty_enemy_gold_factor"),"early_wave_reward_per_second":scalar("early_wave_reward_per_second"),"soldier_regen_factor":scalar("soldier_regen_factor")}
    assert data["waves"]["lives"]==20 and data["waves"]["cash"]==270 and len(data["waves"]["groups"])==7
    counts={}
    for group in data["waves"]["groups"]:
        for wave in group["waves"]:
            for spawn in wave["spawns"]: counts[spawn["creep"]]=counts.get(spawn["creep"],0)+spawn["max"]
    assert counts=={"enemy_goblin":48,"enemy_fat_orc":8}
    # Runtime insert chooses one of these three visual variants; numbers remain source values.
    data["templates"]["re_farmer"]["render"]["sprites"][0]["prefix"]="re_farmer_1"
    assets=ROOT/"assets/kingdom_rush"
    all_anims=json.loads((assets/"data/animations.json").read_text(encoding="utf-8"))["animations"]
    wanted={"stage_1"};animations={}
    states=["idle","idleUp","idleDown","shoot","shootingUp","shootingDown","walkingRightLeft","walkingUp","walkingDown","running","attack","death","open","close","play","flying"]
    for template in data["templates"].values():
        for sprite in template.get("render",{}).get("sprites",[]):
            name=sprite.get("name","");prefix=sprite.get("prefix","")
            if prefix:
                for suffix in set(states + [name]):
                    key=prefix+"_"+suffix
                    if key in all_anims: animations[key]=all_anims[key]
            elif name:
                name=name.replace("%04i","0001")
                if name in all_anims: animations[name]=all_anims[name]
                else: wanted.add(name)
    for prefix in ["re_farmer_2","re_farmer_3"]:
        for suffix in states:
            key=prefix+"_"+suffix
            if key in all_anims: animations[key]=all_anims[key]
    for definition in animations.values(): wanted.update(f"{definition['prefix']}_{int(n):04d}" for n in definition["frames"])
    groups={p.stem:json.loads(p.read_text(encoding="utf-8")) for p in (assets/"data/atlases").glob("*.json")}
    ui_groups=["gui_portraits","gui_common","gui_ico","gui_tutorial","gui_notifications_bg","gui_notifications","view_options","ballon"]
    wanted.update({"top_left","gui_ring","base_powers_bg","bg_bottom_nextwave","pause_base","tutorial_but_gotcha_bg_0001","tutorial_slide1_notxt","tutorial_slide2_notxt","tutorial_slide3_notxt","tutorial_powers_polaroids_0001","tutorial_powers_polaroids_0002","notifications_tips_slides_notxt_0001","notifications_tips_slides_notxt_0003","notifications_newenemy","defeat_bg_notxt","victoryBadges_notxt_0001","victory_star","pointer_set_rally_0001","pointer_power_reinforcements","pointer_power_rain_of_fire","in_game_icon_power_rain_of_fire","in_game_icon_power_reinforcements"})
    # UI uses the exact source layers, not substitutes stretched into arbitrary boxes.
    ui_prefixes=["fire_","fire_ready_","reinforcements_","reinforcement_ready_","power_nbrs_","pause_btn_","victoryStars_","options_","tutorial_but_gotcha_bg_long_","notifications_but_","balloon_"]
    ui_names={"main_icons_0000","main_icons_0001","main_icons_0002","main_icons_0003","main_icons_0004","main_icons_0014","ico_sell_0001","sub_icons_0001","glow_ico_main","glow_ico_sell","glow_ico_sub","price_tag","bg_bottom_bar","bg_bottom_left","tutorial_tit_instructions_bg","notifications_tit_generics_bg_0001","notifications_tit_newpower_bg","notifications_polaroid_overlay","victoryBadges_notxt_0002","button_border_0001","button_border_0002","button_border_large_0001","button_border_large_0002","button_continue_chains","button_restart_chains","tooltip_bg_standard"}
    ui_names.update({"main_icons_0005","base","base_info_bar","base_info_bar_bg","info_portraits_0000"})
    ui_prefixes += ["base_info_icons_"]
    for template in data["templates"].values():
        if template.get("info",{}).get("portrait"):
            ui_names.add(template["info"]["portrait"])
            for idx in template["info"].get("portrait_idxs",[]): ui_names.add(f"info_portraits_soldiers_{idx:04d}")
    for group in ui_groups:
        names=groups[group].get("lookup",groups[group]["frames"])
        wanted.update(n for n in names if n in ui_names or any(n.startswith(p) for p in ui_prefixes))
    order=["tower_holders","go_stage01_bg","go_stage01","go_stages_grass","go_towers_group1","go_towers_group2","go_towers_group3","go_towers_group4","go_towers_group6","go_enemies_grass","go_power_reinforcements","go_decals","go_enemies_common",*ui_groups]
    lookup={}
    for group in order:
        atlas=groups[group]
        for name in [*atlas["frames"],*atlas["aliases"]]: lookup.setdefault(name,group)
    missing=sorted(wanted-lookup.keys())
    if missing: raise ValueError(f"Unresolved first-level frames: {missing}")
    out=ROOT/"data/level01";out.mkdir(parents=True,exist_ok=True)
    canonical={};aliases={};source_hashes={}
    for name in sorted(wanted):
        group=lookup[name];atlas=groups[group];key=atlas.get("lookup",{}).get(name,name)
        if key not in atlas["frames"]: key=atlas["aliases"].get(name,key)
        identity=(group,key)
        if identity not in canonical: canonical[identity]=(name,atlas["frames"][key])
        aliases[name]=canonical[identity][0]
    pages=[];page=Image.new("RGBA",(2048,2048));x=y=row=0;frames={};last_path=None;original=None
    for (group,key),(name,definition) in sorted(canonical.items(),key=lambda item:(item[0][0],item[1][1]["sheet"],item[0][1])):
        path=assets/"kr1-desktop/images/fullhd"/definition["sheet"]
        if path!=last_path:
            if original: original.close()
            original=Image.open(path).convert("RGBA");last_path=path
            source_hashes[path.relative_to(ROOT).as_posix()]=hashlib.sha256(path.read_bytes()).hexdigest()
        sx,sy,w,h=definition["region"];left,top=math.floor(sx),math.floor(sy);width,height=math.ceil(sx+w)-left,math.ceil(sy+h)-top
        assert width<=2044 and height<=2044,(name,width,height)
        if x+width+4>2048:x=0;y+=row;row=0
        if y+height+4>2048: pages.append(page);page=Image.new("RGBA",(2048,2048));x=y=row=0
        tile=original.crop((left,top,left+width,top+height));page.paste(tile,(x+2,y+2));tile.close()
        f=dict(definition);f.update(sheet=f"atlas_{len(pages)}.png",region=[x+2+sx-left,y+2+sy-top,w,h],source_group=group,source_frame=key)
        frames[name]=f;x+=width+4;row=max(row,height+4)
    if original:original.close()
    pages.append(page)
    for i,page in enumerate(pages):
        temporary=out/f"atlas_{i}.png.tmp"
        page.save(temporary,format="PNG",compress_level=6);page.close()
        temporary.replace(out/f"atlas_{i}.png")
    for stale in out.glob("atlas_*.png"):
        if int(stale.stem.split("_")[1]) >= len(pages): stale.unlink()
    write(out/"atlas.json",{"schema_version":1,"group":"level01","texture_directory":"res://data/level01/","frames":frames,"lookup":aliases,"aliases":{k:v for k,v in aliases.items() if k!=v}})
    write(out/"animations.json",{"schema_version":1,"fps":30,"animations":animations})
    sound_data=json.loads((assets/"data/sounds.json").read_text(encoding="utf-8"))
    sound_ids={"MusicMainMenu","GUITowerBuilding","GUITowerSell","GUIQuickMenuOpen","GUIQuickMenuOver","GUINextWaveReady","GUINextWaveIncoming","GUIWinStars","GUILooseLife","GUIButtonCommon","Sheep","DeathEplosion","BombExplosionSound","GUITowerOpenDoor","ReinforcementTaunt","MeleeSword"}
    for t in data["templates"].values():
        sound_ids.update(v for v in t.get("sound_events",{}).values() if isinstance(v,str))
    sound_ids.update(k for k in sound_data if k.lower() in {"musicbattle","musicstage01","music_stage01","musicvictory","musicdefeat"})
    sounds={k:sound_data[k] for k in sorted(sound_ids) if k in sound_data}
    # The stage bundle names its battle music as a group, not a sound ID.
    sound_groups=json.loads((assets/"data/sound_groups.json").read_text(encoding="utf-8"))
    stage_music=sound_groups.get("music_stage01",{})
    if stage_music.get("files"):sounds["Level01Music"]=stage_music
    if "Level01Music" not in sounds:
        music="MusicBattle_01" if "MusicBattle_01" in sound_data else None
        assert music,"Stage music unavailable";sounds["Level01Music"]=sound_data[music]
    sounds["Level01PrepMusic"]=sound_data["MusicBattlePrep_01"]
    write(out/"sounds.json",sounds)
    write(out/"catalog.json",{"schema_version":1,"groups":{"level01":{"path":"res://data/level01/atlas.json"}},"animations":"res://data/level01/animations.json","exoskeletons":{},"static":{"sounds":"res://data/level01/sounds.json"},"audio_directory":"res://assets/kingdom_rush/kr1-desktop/sounds/files/"})
    write(out/"definition.json",data)
    media=["res://data/level01/atlas_%d.png"%i for i in range(len(pages))]
    audio=sorted({"res://assets/kingdom_rush/kr1-desktop/sounds/files/"+f for s in sounds.values() for f in s.get("files",[])})
    assert all((ROOT/p.removeprefix("res://")).is_file() for p in audio)
    data_files=["res://data/level01/"+name+".json" for name in ["definition","atlas","animations","sounds","catalog"]]
    write(out/"manifest.json",{"schema_version":1,"source":data["source"],"resources":media+audio,"data":data_files,"frames":len(aliases),"animations":len(animations),"source_texture_hashes":source_hashes})
    print(json.dumps({"templates":len(data["templates"]),"frames":len(aliases),"animations":len(animations),"atlas_pages":len(pages),"audio":len(audio),"enemies":counts},ensure_ascii=False))

if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--source",type=Path,default=Path("D:/projects/KingdomRushDove"));parser.add_argument("--love",type=Path,default=Path("D:/王国保卫战Dove版/love.exe"));args=parser.parse_args();prepare(args.source,args.love)
