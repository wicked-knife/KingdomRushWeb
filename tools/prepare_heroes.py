"""Export the frozen Dove hero room without running gameplay or accessing saves."""
from pathlib import Path
import argparse
import hashlib
import json
import math
import os
import subprocess
from PIL import Image, ImageChops, ImageDraw, ImageOps
from prepare_map import BASE, ROOT, write


def apply_approved_portraits(data, out, frames, lookup):
    """Add reviewed art without modifying any frozen Dove source pixels."""
    folder = ROOT / "assets/kingdom_rush/generated/heroes"
    config_path = folder / "portraits.json"
    if not config_path.is_file():
        return {}
    config = json.loads(config_path.read_text(encoding="utf-8"))
    assert config["schema_version"] == 1
    rows = {row["name"]: row for row in data["heroes"]}
    generated = {}
    for hero_id, entry in config["portraits"].items():
        assert entry["approved"] is True, f"Unapproved portrait: {hero_id}"
        row = rows[hero_id]
        source, prompt = [folder / entry[key] for key in ["file", "prompt"]]
        assert source.parent == prompt.parent == folder
        frame_id = f"generated_portrait_{hero_id}"
        filename = f"portrait_{hero_id}.png"
        with Image.open(source) as image:
            # Preserve the full approved composition, including helmet tips.
            card = ImageOps.pad(image.convert("RGBA"), (254, 371), Image.Resampling.LANCZOS, color=(0, 0, 0, 0))
        corners = Image.new("L", card.size)
        ImageDraw.Draw(corners).rounded_rectangle((0, 0, 253, 370), radius=4, fill=255)
        card.putalpha(ImageChops.multiply(card.getchannel("A"), corners))
        card.save(out / filename, compress_level=6)
        card.close(); corners.close()
        frames[frame_id] = {"sheet": filename, "region": [0, 0, 254, 371], "source_region": [0, 0, 254, 371],
                            "logical_size": [254, 371], "original_size": [274, 386], "trim": [10, 8],
                            "ref_scale": 1.0, "source_group": "generated_heroes", "source_file": source.relative_to(ROOT).as_posix()}
        lookup[frame_id] = frame_id
        row.update(portrait=frame_id, portrait_fallback=False)
        generated[hero_id] = {"frame": frame_id, "resource": f"res://data/heroes/{filename}",
                              "model": entry["model"], "approved_on": entry["approved_on"],
                              "source": source.relative_to(ROOT).as_posix(), "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                              "prompt": prompt.relative_to(ROOT).as_posix(), "prompt_sha256": hashlib.sha256(prompt.read_bytes()).hexdigest()}
    data["portrait_fallbacks"] = [row["name"] for row in data["heroes"] if row["portrait_fallback"]]
    return generated


def prepare(source, love):
    assert subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip() == BASE
    assert not subprocess.check_output(["git", "-C", str(source), "status", "--porcelain"], text=True).strip()
    evaluated = ROOT / "output/hero_evaluated.json"
    evaluated.parent.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, DOVE_SOURCE_DIR=str(source), DOVE_EXPORT_PATH=str(evaluated))
    result = subprocess.run([str(love), str(ROOT / "tools/hero_export")], env=env, capture_output=True, timeout=60)
    if result.returncode:
        raise RuntimeError(Path(str(evaluated) + ".error").read_text(encoding="utf-8", errors="replace"))
    data = json.loads(evaluated.read_text(encoding="utf-8"))
    inputs = set(data.pop("inputs")) | {"all-desktop/screen_map.lua", "kr1-desktop/data/kui_templates/hero_room_view.lua", "kr1/data/slot_template.lua"}
    data.update(schema_version=1, reference_size=[1920, 1080], max_selected=2)
    data["source"] = {"version": "2.1.0.2", "commit": BASE, "inputs": {p: hashlib.sha256((source / p).read_bytes()).hexdigest() for p in sorted(inputs)}}
    assets = ROOT / "assets/kingdom_rush"
    atlas = json.loads((assets / "data/atlases/hero_room.json").read_text(encoding="utf-8"))
    locale = json.loads((assets / "data/locale_zh-Hans.json").read_text(encoding="utf-8"))
    data["strings"] = {k: locale[k] for k in ["HERO ROOM", "Select hero", "MAP_HERO_ROOM_SELECT", "MAP_HERO_ROOM_DESELECT", "MAP_HERO_ROOM_UNLOCK", "MAP_HEROROOM_BIO", "Special abilities", "BUTTON_DONE", "TOGGLE"]}
    assert len(data["heroes"]) == 79
    data["portrait_fallbacks"] = []
    for row in data["heroes"]:
        prefix = f"kr{row['from_kr']}_" if row.get("from_kr") else ""
        row["thumbnail"] = f"{prefix}hero_room_thumbs_{row['thumb']:04d}"
        row["map_icon"] = f"{prefix}mapButtons_portrait_hero_{row['icon']:04d}"
        row["portrait"] = f"{prefix}portrait_notxt_{row['portrait']:04d}"
        row["portrait_fallback"] = row["portrait"] not in atlas["lookup"]
        if row["portrait_fallback"]:
            row["portrait"] = row["thumbnail"]
            data["portrait_fallbacks"].append(row["name"])
        row["details"] = [{"title": k, "text": v} for k, v in sorted(row["details"].items())]
        assert row["details"] and not row["title"].endswith("_NAME")
    out = ROOT / "data/heroes"
    out.mkdir(parents=True, exist_ok=True)
    wanted = {k for k in atlas["frames"] if "mapButtons_portrait_hero_" not in k}
    frames, pages = {}, []
    page = Image.new("RGBA", (2048, 2048))
    x = y = height = 0
    texture = ROOT / atlas["texture_directory"].removeprefix("res://") / "hero_room-1.png"
    with Image.open(texture) as original:
        for name in sorted(wanted):
            frame = dict(atlas["frames"][name])
            sx, sy, w, h = frame["region"]
            left, top = math.floor(sx), math.floor(sy)
            width, rows = math.ceil(sx + w) - left, math.ceil(sy + h) - top
            assert width <= 2044 and rows <= 2044
            if x + width + 4 > 2048:
                x = 0; y += height; height = 0
            if y + rows + 4 > 2048:
                pages.append(page); page = Image.new("RGBA", (2048, 2048)); x = y = height = 0
            tile = original.crop((left, top, left + width, top + rows))
            page.paste(tile, (x + 2, y + 2)); tile.close()
            frame.update(sheet=f"atlas_{len(pages)}.png", region=[x + 2 + sx - left, y + 2 + sy - top, w, h], source_frame=name, source_group="hero_room")
            frames[name] = frame
            x += width + 4; height = max(height, rows + 4)
    pages.append(page)
    for i, page in enumerate(pages):
        page.save(out / f"atlas_{i}.png", compress_level=6); page.close()
    lookup = {k: v for k, v in atlas["lookup"].items() if v in frames}
    generated = apply_approved_portraits(data, out, frames, lookup)
    write(out / "atlas.json", {"schema_version": 1, "group": "heroes", "texture_directory": "res://data/heroes/", "frames": frames, "lookup": lookup, "aliases": {k: v for k, v in lookup.items() if k != v}})
    all_sounds = json.loads((assets / "data/sounds.json").read_text(encoding="utf-8"))
    ids = {"GUIButtonCommon", "GUIQuickMenuOpen", "GUIBuyUpgrade"} | {row["sound"] for row in data["heroes"] if row.get("sound")}
    sounds = {k: all_sounds[k] for k in sorted(ids)}
    write(out / "sounds.json", sounds)
    write(out / "definition.json", data)
    write(out / "catalog.json", {"schema_version": 1, "groups": {"heroes": {"path": "res://data/heroes/atlas.json"}}, "static": {"sounds": "res://data/heroes/sounds.json"}, "audio_directory": "res://assets/kingdom_rush/kr1-desktop/sounds/files/"})
    resources = [f"res://data/heroes/atlas_{i}.png" for i in range(len(pages))]
    resources += [entry["resource"] for entry in generated.values()]
    resources += sorted({"res://assets/kingdom_rush/kr1-desktop/sounds/files/" + f for sound in sounds.values() for f in sound["files"]})
    resources += ["res://scripts/map/hero_room.gd", "res://scripts/services/hero_loader.gd"]
    write(out / "manifest.json", {"schema_version": 1, "source": data["source"], "resources": resources, "data": [f"res://data/heroes/{p}.json" for p in ["definition", "catalog", "atlas", "sounds"]], "source_texture_hashes": {texture.relative_to(ROOT).as_posix(): hashlib.sha256(texture.read_bytes()).hexdigest()}, "generated_portraits": generated})
    print(json.dumps({"heroes": 79, "skills": sum(len(h["details"]) for h in data["heroes"]), "pages": len(pages), "portrait_fallbacks": data["portrait_fallbacks"]}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("D:/projects/KingdomRushDove"))
    parser.add_argument("--love", type=Path, default=Path("D:/王国保卫战Dove版/love.exe"))
    args = parser.parse_args()
    prepare(args.source.resolve(), args.love.resolve())
