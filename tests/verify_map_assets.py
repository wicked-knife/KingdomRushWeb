"""Verify source provenance, map closure and every repacked pixel against its source."""
from pathlib import Path
import hashlib
import json
import math
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parent / "KingdomRushDove"


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def verify():
    bundle = ROOT / "data/map_kr1"
    manifest, definition, atlas = [read(bundle / (name + ".json")) for name in ["manifest", "definition", "atlas"]]
    for path, digest in definition["source"]["inputs"].items():
        assert hashlib.sha256((SOURCE / path).read_bytes()).hexdigest() == digest, path
    for path, digest in manifest["source_texture_hashes"].items():
        assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == digest, path
    for path in manifest["resources"] + manifest["data"]:
        assert (ROOT / path.removeprefix("res://")).is_file(), path
    assert [v["id"] for v in definition["levels"]] == list(range(1, 27)) + [1000]
    assert len(definition["animations"]) == 124 and definition["max_stars"] == 135
    names = set(atlas["lookup"])
    def walk(value):
        if isinstance(value, dict):
            assert "template" not in value
            if {"prefix", "from", "to"} <= value.keys():
                for n in range(value["from"], value["to"] + 1):
                    assert f"{value['prefix']}_{n:04d}" in names
            if "image" in value:
                assert value["image"] in names
            for v in value.values():
                walk(v)
        elif isinstance(value, list):
            for v in value:
                walk(v)
    walk(definition)
    for stage in definition["levels"]:
        assert stage["title"] and stage["history"] and stage["thumbnail"] in names
    originals = {}
    source_image = page = None
    source_path = page_path = None
    for frame in atlas["frames"].values():
        group = frame["source_group"]
        if group not in originals:
            originals[group] = read(ROOT / f"assets/kingdom_rush/data/atlases/{group}.json")
        original_atlas = originals[group]
        original = original_atlas["frames"][frame["source_frame"]]
        for key in ["logical_size", "original_size", "trim", "ref_scale"]:
            assert frame[key] == original[key]
        path = ROOT / original_atlas["texture_directory"].removeprefix("res://") / original["sheet"]
        if path != source_path:
            if source_image: source_image.close()
            source_image = Image.open(path).convert("RGBA"); source_path = path
        path = bundle / frame["sheet"]
        if path != page_path:
            if page: page.close()
            page = Image.open(path).convert("RGBA"); page_path = path
        def box(region):
            x, y, w, h = region
            return math.floor(x), math.floor(y), math.ceil(x + w), math.ceil(y + h)
        a, b = source_image.crop(box(original["region"])), page.crop(box(frame["region"]))
        assert a.size == b.size and ImageChops.difference(a, b).getbbox(alpha_only=False) is None, frame["source_frame"]
        a.close(); b.close()
    if source_image: source_image.close()
    if page: page.close()
    report = {"passed": True, "nodes": 27, "animation_instances": 124, "frames": len(names), "canonical_frames_pixel_verified": len(atlas["frames"]), "pages": len(list(bundle.glob("atlas_*.png"))), "commit": definition["source"]["commit"]}
    (ROOT / "reports/map_kr1_assets.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report))


if __name__ == "__main__":
    verify()
