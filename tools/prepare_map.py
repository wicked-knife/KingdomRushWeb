"""Build the generation-one map bundle from the frozen Dove snapshot."""
from pathlib import Path
import argparse
import hashlib
import json
import math
import os
import re
import subprocess
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BASE = "e29ece82939fd73fb69bfc4b469d484a72e4dfd2"


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False) + "\n", encoding="utf-8")


def prepare(source, love):
    assert subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip() == BASE
    assert not subprocess.check_output(["git", "-C", str(source), "status", "--porcelain"], text=True).strip()
    evaluated = ROOT / "output/map_export/evaluated.json"
    evaluated.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(DOVE_SOURCE_DIR=str(source), DOVE_EXPORT_PATH=str(evaluated))
    result = subprocess.run([str(love), str(ROOT / "tools/map_export")], env=env, capture_output=True, timeout=60)
    if result.returncode:
        raise RuntimeError(Path(str(evaluated) + ".error").read_text(encoding="utf-8"))
    data = json.loads(evaluated.read_text(encoding="utf-8"))
    inputs = set(data.pop("inputs")) | {"all-desktop/screen_map.lua", "kr1-desktop/map_decos_functions.lua", "kr1/game_settings.lua", "all/systems/level.lua", "all/utils.lua"}
    data.update(schema_version=1, generation=1, reference_size=[1920, 1080])
    data["source"] = {"version": "2.1.0.2", "commit": BASE, "inputs": {p: hashlib.sha256((source / p).read_bytes()).hexdigest() for p in sorted(inputs)}}
    gs = (source / "kr1/game_settings.lua").read_text(encoding="utf-8")
    ranges = re.search(r"GS\.level_ranges1\s*=\s*(\{[^\n]+)", gs)[1]
    data["level_ranges"] = [list(map(int, re.findall(r"\d+", r))) for r in re.findall(r"\{([^{}]+)\}", ranges)]
    data["main_campaign_last"] = int(re.search(r"GS\.main_campaign_levels1\s*=\s*(\d+)", gs)[1])
    data["max_stars"] = sum((r[-1] - r[0] + 1) * 5 for r in data["level_ranges"])
    assert len(data["animations"]) == 124 and len(data["levels"]) == 27 and data["max_stars"] == 135
    assets = ROOT / "assets/kingdom_rush"
    locale = json.loads((assets / "data/locale_zh-Hans.json").read_text(encoding="utf-8"))
    data["strings"] = {key: locale[key] for key in ["Campaign", "Heroic", "Iron", "Challenge Rules", "LEVEL_MODE_HEROIC_DESCRIPTION", "LEVEL_MODE_IRON_DESCRIPTION", "LEVEL_MODE_LOCKED_DESCRIPTION", "BUTTON_TO_BATTLE_1", "BUTTON_TO_BATTLE_2"]}
    wanted = {"map_background_kr1", "map_vignette_small", "mapBalloon_starthere_notxt"}
    for level in data["levels"]:
        number = level["id"]
        level.update(title=locale[f"LEVEL_{number}_TITLE"], history=locale[f"LEVEL_{number}_HISTORY"], thumbnail=f"stage_thumbs_{number:04d}")
        wanted.add(level["thumbnail"])
    def collect(value):
        if isinstance(value, dict):
            if "prefix" in value and "from" in value and "to" in value:
                wanted.update(f"{value['prefix']}_{i:04d}" for i in range(value["from"], value["to"] + 1))
            if "image" in value:
                wanted.add(value["image"])
            for child in value.values():
                collect(child)
        elif isinstance(value, list):
            for child in value:
                collect(child)
    collect(data)
    groups = ["screen_map_backgrond", "screen_map_animations", "screen_map_flags", "screen_map_buttons", "stars_container", "level_select", "ballon", "view_options", "hero_room"]
    atlases = {g: json.loads((assets / f"data/atlases/{g}.json").read_text(encoding="utf-8")) for g in groups}
    for group in ["screen_map_flags", "screen_map_buttons", "stars_container"]:
        wanted.update(atlases[group]["frames"])
    wanted.update(k for k in atlases["hero_room"]["frames"] if "mapButtons_portrait_hero_" in k)
    wanted.update(k for k in atlases["level_select"]["frames"] if k.startswith("levelSelect_"))
    wanted.update(k for k in atlases["view_options"]["frames"] if k.startswith("options_") and not k.startswith("options_lang"))
    lookup = {}
    for group, atlas in atlases.items():
        for name in {*atlas["frames"], *atlas["aliases"]}:
            lookup.setdefault(name, group)
    assert not wanted - lookup.keys(), sorted(wanted - lookup.keys())
    out = ROOT / "data/map_kr1"
    out.mkdir(parents=True, exist_ok=True)
    canonical, aliases = {}, {}
    for name in sorted(wanted):
        group = lookup[name]
        key = atlases[group].get("lookup", {}).get(name, name)
        identity = (group, key)
        canonical.setdefault(identity, (name, atlases[group]["frames"][key]))
        aliases[name] = canonical[identity][0]
    frames, pages, hashes = {}, [], {}
    page = Image.new("RGBA", (2048, 2048))
    x = y = row = 0
    original = None
    previous = None
    for (group, key), (name, definition) in sorted(canonical.items(), key=lambda pair: (pair[0][0], pair[1][1]["sheet"], pair[0][1])):
        path = ROOT / atlases[group]["texture_directory"].removeprefix("res://") / definition["sheet"]
        if path != previous:
            if original:
                original.close()
            original = Image.open(path).convert("RGBA")
            previous = path
            hashes[path.relative_to(ROOT).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
        sx, sy, w, h = definition["region"]
        left, top = math.floor(sx), math.floor(sy)
        width, height = math.ceil(sx + w) - left, math.ceil(sy + h) - top
        assert width <= 2044 and height <= 2044
        if x + width + 4 > 2048:
            x = 0; y += row; row = 0
        if y + height + 4 > 2048:
            pages.append(page); page = Image.new("RGBA", (2048, 2048)); x = y = row = 0
        tile = original.crop((left, top, left + width, top + height))
        page.paste(tile, (x + 2, y + 2)); tile.close()
        frame = dict(definition)
        frame.update(sheet=f"atlas_{len(pages)}.png", region=[x + 2 + sx - left, y + 2 + sy - top, w, h], source_group=group, source_frame=key)
        frames[name] = frame
        x += width + 4; row = max(row, height + 4)
    if original:
        original.close()
    pages.append(page)
    for index, page in enumerate(pages):
        page.save(out / f"atlas_{index}.png", compress_level=6); page.close()
    for stale in out.glob("atlas_*.png"):
        if int(stale.stem.split("_")[1]) >= len(pages):
            stale.unlink()
    write(out / "atlas.json", {"schema_version": 1, "group": "map_kr1", "texture_directory": "res://data/map_kr1/", "frames": frames, "lookup": aliases, "aliases": {k: v for k, v in aliases.items() if k != v}})
    sound_ids = ["MusicMap1", "GUIButtonCommon", "GUIQuickMenuOver", "GUIWinStars", "GuimapNewRoad", "GUIMapNewFlah"]
    all_sounds = json.loads((assets / "data/sounds.json").read_text(encoding="utf-8"))
    sounds = {k: all_sounds[k] for k in sound_ids}
    write(out / "sounds.json", sounds)
    write(out / "definition.json", data)
    write(out / "catalog.json", {"schema_version": 1, "groups": {"map_kr1": {"path": "res://data/map_kr1/atlas.json"}}, "static": {"sounds": "res://data/map_kr1/sounds.json"}, "audio_directory": "res://assets/kingdom_rush/kr1-desktop/sounds/files/"})
    resources = [f"res://data/map_kr1/atlas_{i}.png" for i in range(len(pages))]
    resources += sorted({"res://assets/kingdom_rush/kr1-desktop/sounds/files/" + f for s in sounds.values() for f in s["files"]})
    scripts = ["scripts/map/map_screen.gd", "scripts/map/map_animations.gd", "scripts/map/map_interface.gd", "scripts/services/map_loader.gd", "scripts/services/campaign_progress.gd"]
    resources += ["res://" + p for p in scripts]
    write(out / "manifest.json", {"schema_version": 1, "source": data["source"], "resources": resources, "data": [f"res://data/map_kr1/{f}.json" for f in ["atlas", "definition", "catalog", "sounds"]], "frames": len(aliases), "source_texture_hashes": hashes})
    print(json.dumps({"nodes": len(data["levels"]), "instances": len(data["animations"]), "frames": len(aliases), "pages": len(pages), "max_stars": data["max_stars"]}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("D:/projects/KingdomRushDove"))
    parser.add_argument("--love", type=Path, default=Path("D:/王国保卫战Dove版/love.exe"))
    args = parser.parse_args()
    prepare(args.source.resolve(), args.love.resolve())
