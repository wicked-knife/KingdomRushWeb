"""Export a separately loaded source-backed combat bundle for the first hero."""
from pathlib import Path
import argparse
import hashlib
import io
import json
import math
import os
import subprocess

from PIL import Image
from dove_source import BASE, VERSION
from prepare_level01 import write

ROOT = Path(__file__).resolve().parents[1]
FOLDER = "hero_malik_combat"


def prepare(source, love):
    assert subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip() == BASE
    assert not subprocess.check_output(["git", "-C", str(source), "status", "--porcelain"], text=True).strip()
    scratch = ROOT / "output" / FOLDER
    scratch.mkdir(parents=True, exist_ok=True)
    evaluated = scratch / "evaluated.json"
    env = dict(os.environ, DOVE_SOURCE_DIR=str(source), DOVE_EXPORT_PATH=str(evaluated))
    run = subprocess.run([str(love), str(ROOT / "tools/hero_combat_export")], env=env, capture_output=True, timeout=60)
    if run.returncode:
        error = Path(str(evaluated) + ".error")
        raise RuntimeError(error.read_text(encoding="utf-8", errors="replace") if error.exists() else run.stderr.decode("utf-8", errors="replace"))
    data = json.loads(evaluated.read_text(encoding="utf-8"))
    inputs = sorted(set(data.pop("inputs")) | {"lib/klua/table.lua", "lib/klua/vector.lua", "all/constants.lua"})
    data.update(schema_version=1, id="hero_malik", root=f"res://data/{FOLDER}/", group=FOLDER,
                source={"version": VERSION, "commit": BASE, "inputs": {
                    path: hashlib.sha256((source / path).read_bytes()).hexdigest() for path in inputs}})
    assets = ROOT / "assets/kingdom_rush"
    all_anims = json.loads((assets / "data/animations.json").read_text(encoding="utf-8"))["animations"]
    groups = {name: json.loads((assets / f"data/atlases/{name}.json").read_text(encoding="utf-8"))
              for name in ["go_hero_malik", "go_decals", "go_towers_group5", "go_towers_group6", "go_enemies_common", "gui_portraits", "gui_common", "gui_ico"]}
    animations = {}
    wanted = {"hero_portraits_0003","hero_portraits_0000","heroPortrait_selected","hero_portrait_bars_0001","hero_portrait_bars_0002"}
    wanted.update(f"heroPortrait_{index:04d}" for index in range(1,30))
    sound_ids = {"HeroLevelUp"}
    for template in data["templates"].values():
        for sprite in template.get("render", {}).get("sprites", []):
            prefix = sprite.get("prefix")
            name = sprite.get("name", "")
            if prefix:
                animations.update({key: value for key, value in all_anims.items() if key.startswith(prefix + "_")})
            elif name in all_anims:
                animations[name] = all_anims[name]
            elif name:
                wanted.add(name)
        portrait = template.get("info", {}).get("portrait")
        if portrait:
            wanted.add(portrait)
        sound_ids.update(v for v in template.get("sound_events", {}).values() if isinstance(v, str))
        for attack in template.get("melee", {}).get("attacks", []):
            sound_ids.update(attack[key] for key in ["sound", "sound_hit"] if attack.get(key))
    for animation in animations.values():
        wanted.update(f"{animation['prefix']}_{int(frame):04d}" for frame in animation["frames"])
    lookup = {}
    for name, atlas in groups.items():
        for key in [*atlas["frames"], *atlas.get("aliases", {})]:
            lookup.setdefault(key, name)
    assert not wanted - lookup.keys(), f"Missing actor frames: {sorted(wanted - lookup.keys())}"
    out = ROOT / "data" / FOLDER
    out.mkdir(parents=True, exist_ok=True)
    page = Image.new("RGBA", (2048, 2048))
    pages = []
    frames = {}
    aliases = {}
    canonical = {}
    source_hashes = {}
    textures = {}
    x = y = row = 0
    for name in sorted(wanted):
        group = lookup[name]
        atlas = groups[group]
        key = atlas.get("lookup", {}).get(name, atlas.get("aliases", {}).get(name, name))
        identity = (group, key)
        if identity in canonical:
            aliases[name] = canonical[identity]
            continue
        canonical[identity] = name
        aliases[name] = name
        definition = atlas["frames"][key]
        path = assets / "kr1-desktop/images/fullhd" / definition["sheet"]
        if path not in textures:
            source_hashes[path.relative_to(ROOT).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
            with Image.open(path) as original:
                textures[path] = original.convert("RGBA")
        sx, sy, w, h = definition["region"]
        left, top = math.floor(sx), math.floor(sy)
        width, height = math.ceil(sx+w)-left, math.ceil(sy+h)-top
        assert width <= 2044 and height <= 2044
        if x + width + 4 > 2048:
            x = 0; y += row; row = 0
        if y + height + 4 > 2048:
            pages.append(page); page = Image.new("RGBA", (2048,2048)); x = y = row = 0
        tile = textures[path].crop((left, top, left+width, top+height))
        page.paste(tile, (x+2,y+2)); tile.close()
        frames[name] = dict(definition, sheet=f"atlas_{len(pages)}.png",
                            region=[x+2+sx-left,y+2+sy-top,w,h], source_group=group, source_frame=key)
        x += width + 4; row = max(row, height+4)
    pages.append(page)
    for original in textures.values():
        original.close()
    for index, page in enumerate(pages):
        buffer = io.BytesIO(); page.save(buffer, format="PNG", compress_level=6); page.close()
        path = out / f"atlas_{index}.png"
        if not path.exists() or path.read_bytes() != buffer.getvalue():
            path.write_bytes(buffer.getvalue())
        buffer.close()
    write(out / "atlas.json", dict(schema_version=1, group=FOLDER, texture_directory=f"res://data/{FOLDER}/",
                                   frames=frames, lookup=aliases, aliases={k:v for k,v in aliases.items() if k!=v}))
    write(out / "animations.json", dict(schema_version=1, fps=30, animations=animations))
    all_sounds = json.loads((assets / "data/sounds.json").read_text(encoding="utf-8"))
    assert not sound_ids - all_sounds.keys(), f"Missing actor sounds: {sound_ids - all_sounds.keys()}"
    sounds = {key: all_sounds[key] for key in sorted(sound_ids)}
    write(out / "sounds.json", sounds)
    write(out / "definition.json", data)
    write(out / "catalog.json", dict(schema_version=1, groups={FOLDER:{"path":f"res://data/{FOLDER}/atlas.json"}},
                                     animations=f"res://data/{FOLDER}/animations.json", exoskeletons={},
                                     static={"sounds":f"res://data/{FOLDER}/sounds.json"},
                                     audio_directory="res://assets/kingdom_rush/kr1-desktop/sounds/files/"))
    audio = sorted({"res://assets/kingdom_rush/kr1-desktop/sounds/files/" + filename
                    for sound in sounds.values() for filename in sound.get("files", [])})
    assert all((ROOT / path.removeprefix("res://")).is_file() for path in audio)
    write(out / "manifest.json", dict(schema_version=1, source=data["source"],
        data=[f"res://data/{FOLDER}/{name}.json" for name in ["definition","atlas","animations","sounds","catalog"]],
        resources=[f"res://data/{FOLDER}/atlas_{index}.png" for index in range(len(pages))] + audio,
        frames=len(aliases), animations=len(animations), source_texture_hashes=source_hashes))
    print(json.dumps(dict(actor=data["id"], templates=len(data["templates"]), frames=len(aliases), animations=len(animations))))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("D:/projects/KingdomRushDove"))
    parser.add_argument("--love", type=Path, default=Path("D:/王国保卫战Dove版/love.exe"))
    args = parser.parse_args()
    prepare(args.source, args.love)
