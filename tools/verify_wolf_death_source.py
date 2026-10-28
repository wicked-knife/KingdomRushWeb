"""Verify source death sequences and packed pixels for units hidden after death."""
import json
import math
from pathlib import Path

from PIL import Image
from dove_source import provenance, verify
from import_dove_assets import decode_animations

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path("D:/projects/KingdomRushDove")
NAMES = ["enemy_wolf", "enemy_wolf_small", "enemy_gargoyle", "enemy_golem_head"]


def run():
    verify(SOURCE)
    folder = ROOT / "data/level06"
    read = lambda p: json.loads(p.read_text(encoding="utf-8"))
    templates = read(folder / "definition.json")["templates"]
    animations = decode_animations((SOURCE / "kr1/data/game_animations.bin").read_bytes())["animations"]
    exported = read(folder / "animations.json")["animations"]
    atlas = read(folder / "atlas.json")
    images = {}
    rows = {}
    pixels = 0
    try:
        for name in NAMES:
            template = templates[name]
            assert template["unit"]["hide_after_death"] is True
            assert not template["unit"]["show_blood_pool"]
            key = template["render"]["sprites"][0]["prefix"] + "_death"
            animation = animations[key]
            assert animation == exported[key]
            for number in animation["frames"]:
                frame = f"{animation['prefix']}_{number:04d}"
                item = atlas["frames"][atlas["lookup"][frame]]
                original = read(ROOT / f"assets/kingdom_rush/data/atlases/{item['source_group']}.json")["frames"][item["source_frame"]]
                def crop(path, region):
                    if path not in images:
                        images[path] = Image.open(path).convert("RGBA")
                    x, y, width, height = region
                    return images[path].crop((math.floor(x), math.floor(y), math.ceil(x+width), math.ceil(y+height)))
                actual = crop(folder / item["sheet"], item["region"])
                expected = crop(ROOT / "assets/kingdom_rush/kr1-desktop/images/fullhd" / original["sheet"], original["region"])
                assert actual.tobytes() == expected.tobytes(), frame
                pixels += 1
            rows[name] = {"animation": animation, "hide_after_death": True,
                          "dead_lifetime": template["health"]["dead_lifetime"],
                          "death_sound": template["sound_events"]["death"]}
        output = {"source": provenance(SOURCE, ["kr1/enemies.lua", "all/script_utils.lua", "kr1/data/game_animations.bin"]),
                  "units": rows, "verified_pixel_frames": pixels}
        (ROOT / "tests/fixtures/dove_death_source.json").write_text(json.dumps(output, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
        print(f"DEATH_SOURCE: {len(rows)} units, {pixels} source frames/pixels verified")
    finally:
        for image in images.values():
            image.close()


if __name__ == "__main__":
    run()
