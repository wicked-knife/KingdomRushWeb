"""Check the full roster, computed text, dependency closure and repacked pixels."""
from pathlib import Path
import hashlib
import json
import math
import re
from PIL import Image, ImageChops, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parent / "KingdomRushDove"


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def verify():
    folder = ROOT / "data/heroes"
    definition, manifest, atlas = [read(folder / f"{name}.json") for name in ["definition", "manifest", "atlas"]]
    for name, digest in definition["source"]["inputs"].items():
        assert hashlib.sha256((SOURCE / name).read_bytes()).hexdigest() == digest, name
    for name, digest in manifest["source_texture_hashes"].items():
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, name
    for path in manifest["resources"] + manifest["data"]:
        assert (ROOT / path.removeprefix("res://")).is_file(), path
    rows = definition["heroes"]
    assert len(rows) == len({h["name"] for h in rows}) == 79
    assert definition["portrait_fallbacks"] == []
    generated = manifest.get("generated_portraits", {})
    approved = read(ROOT / "assets/kingdom_rush/generated/heroes/portraits.json")["portraits"]
    assert set(generated) == set(approved) == {"hero_dwarf", "hero_vampiress", "hero_bolverk"}
    assert all(entry["approved"] is True for entry in approved.values())
    for hero_id, entry in generated.items():
        source, prompt = ROOT / entry["source"], ROOT / entry["prompt"]
        assert hashlib.sha256(source.read_bytes()).hexdigest() == entry["source_sha256"]
        assert hashlib.sha256(prompt.read_bytes()).hexdigest() == entry["prompt_sha256"]
        assert entry["resource"] in manifest["resources"]
        assert entry["model"] == approved[hero_id]["model"]
        row = next(row for row in rows if row["name"] == hero_id)
        assert row["portrait"] == entry["frame"] and not row["portrait_fallback"]
        assert row["portrait"] != row["thumbnail"]
    map_atlas = read(ROOT / "data/map_kr1/atlas.json")
    sounds = read(folder / "sounds.json")
    for hero in rows:
        assert hero["thumbnail"] in atlas["lookup"] and hero["portrait"] in atlas["lookup"], hero["name"]
        assert hero["map_icon"] in map_atlas["lookup"], hero["name"]
        assert len(hero["stats"]) == 4 and 1 <= hero["available_level"] <= 116
        assert hero["title"] and hero["bio"] and hero["special"] and hero["details"]
        assert hero.get("sound") in sounds
        for text in [hero["title"], hero["bio"], hero["special"], *[v for entry in hero["details"] for v in entry.values()]]:
            assert not re.search(r"%(?:s|d|[.\d]+f)|HERO_\w+_(?:DESC|NAME|SPECIAL)", text), (hero["name"], text)
    original_atlas = read(ROOT / "assets/kingdom_rush/data/atlases/hero_room.json")
    original_path = ROOT / original_atlas["texture_directory"].removeprefix("res://") / "hero_room-1.png"
    pages = {}
    with Image.open(original_path) as original:
        for frame in atlas["frames"].values():
            if frame.get("source_group") == "generated_heroes":
                assert frame["source_file"] in {entry["source"] for entry in generated.values()}
                assert frame["logical_size"] == [254, 371] and frame["original_size"] == [274, 386]
                assert frame["trim"] == [10, 8] and frame["ref_scale"] == 1.0
                with Image.open(ROOT / frame["source_file"]) as source, Image.open(folder / frame["sheet"]) as actual:
                    assert actual.size == (254, 371) and actual.mode == "RGBA"
                    expected = ImageOps.pad(source.convert("RGBA"), actual.size, Image.Resampling.LANCZOS, color=(0, 0, 0, 0))
                    corners = Image.new("L", actual.size)
                    ImageDraw.Draw(corners).rounded_rectangle((0, 0, 253, 370), radius=4, fill=255)
                    expected.putalpha(ImageChops.multiply(expected.getchannel("A"), corners))
                    assert not any(channel.getbbox() for channel in ImageChops.difference(expected, actual).split()), frame["sheet"]
                    expected.close(); corners.close()
                continue
            source_frame = original_atlas["frames"][frame["source_frame"]]
            for key in ["logical_size", "original_size", "trim", "ref_scale"]:
                assert frame[key] == source_frame[key]
            if frame["sheet"] not in pages:
                pages[frame["sheet"]] = Image.open(folder / frame["sheet"])
            page = pages[frame["sheet"]]
            sx, sy, w, h = source_frame["region"]
            dx, dy, dw, dh = frame["region"]
            assert (w, h) == (dw, dh)
            expected = original.crop((math.floor(sx), math.floor(sy), math.ceil(sx + w), math.ceil(sy + h))).convert("RGBA")
            actual = page.crop((math.floor(dx), math.floor(dy), math.ceil(dx + w), math.ceil(dy + h))).convert("RGBA")
            assert ImageChops.difference(expected, actual).getbbox() is None, frame["source_frame"]
            expected.close(); actual.close()
    for page in pages.values():
        assert page.size == (2048, 2048)
        page.close()
    report = {"passed": True, "heroes": 79, "skills": sum(len(h["details"]) for h in rows), "frames_pixel_verified": len(atlas["frames"]), "pages": len(pages), "generated_portraits": list(generated), "portrait_fallbacks": definition["portrait_fallbacks"], "commit": definition["source"]["commit"]}
    (ROOT / "reports/heroes_assets.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report))


if __name__ == "__main__":
    verify()
