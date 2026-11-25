"""Repack level01-12 atlases into cross-level consumer buckets with tight-cropped pages,
and tightly repack map_kr1 and heroes atlases without altering source pixels or definitions.
"""
from __future__ import annotations

import collections
import hashlib
import io
import json
import math
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets/kingdom_rush"


def align_up(value: int, step: int = 16) -> int:
    return ((value + step - 1) // step) * step


def write_json(path: Path, value: object) -> None:
    text = json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False) + "\n"
    if path.is_file() and path.read_text(encoding="utf-8") == text:
        return
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(path)


def save_png_bytes(image: Image.Image) -> bytes:
    buf = io.BytesIO()
    image.save(buf, format="PNG", compress_level=6)
    data = buf.getvalue()
    buf.close()
    return data


def write_bytes_if_changed(path: Path, content: bytes) -> None:
    if path.is_file() and path.read_bytes() == content:
        return
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_bytes(content)
    tmp.replace(path)


def pack_bucket(keys: list[tuple[str, str]], source_atlases: dict[str, dict]) -> list[tuple[bytes, dict]]:
    """Pack a deterministic set of (source_group, source_frame) into tightly cropped <=2048 PNG pages."""
    items = []
    for group, frame_key in keys:
        fdef = source_atlases[group]["frames"][frame_key]
        sx, sy, w, h = fdef["region"]
        left, top = math.floor(sx), math.floor(sy)
        width, height = math.ceil(sx + w) - left, math.ceil(sy + h) - top
        assert width <= 2044 and height <= 2044, (group, frame_key, width, height)
        items.append((group, frame_key, fdef, left, top, width, height))

    # Height-descending shelf packing eliminates wasted gaps and prevents empty pages.
    items.sort(key=lambda row: (-row[6], -row[5], row[0], row[1]))

    pages_layout: list[tuple[list[tuple], int, int]] = []
    current: list[tuple] = []
    x = y = row_h = max_x = 0
    for item in items:
        _, _, _, _, _, width, height = item
        if x + width + 4 > 2048:
            x = 0
            y += row_h
            row_h = 0
        if y + height + 4 > 2048:
            pages_layout.append((current, align_up(max(64, max_x)), align_up(max(64, y + row_h))))
            current = []
            x = y = row_h = max_x = 0
        current.append((item, x + 2, y + 2))
        x += width + 4
        max_x = max(max_x, x)
        row_h = max(row_h, height + 4)
    if current:
        pages_layout.append((current, align_up(max(64, max_x)), align_up(max(64, y + row_h))))

    sheet_cache: dict[Path, Image.Image] = {}
    rendered_pages: list[tuple[bytes, dict]] = []
    try:
        for placed, pw, ph in pages_layout:
            canvas = Image.new("RGBA", (min(2048, pw), min(2048, ph)))
            placements = {}
            for (group, frame_key, fdef, left, top, width, height), px, py in placed:
                tex_dir = ROOT / source_atlases[group]["texture_directory"].removeprefix("res://")
                src_path = tex_dir / fdef["sheet"]
                if src_path not in sheet_cache:
                    sheet_cache[src_path] = Image.open(src_path).convert("RGBA")
                tile = sheet_cache[src_path].crop((left, top, left + width, top + height))
                canvas.paste(tile, (px, py))
                tile.close()
                sx, sy, w, h = fdef["region"]
                placements[(group, frame_key)] = [px + sx - left, py + sy - top, w, h]
            png_bytes = save_png_bytes(canvas)
            canvas.close()
            rendered_pages.append((png_bytes, placements))
    finally:
        for im in sheet_cache.values():
            im.close()
    return rendered_pages


def load_source_atlases() -> dict[str, dict]:
    return {
        p.stem: json.loads(p.read_text(encoding="utf-8"))
        for p in sorted((ASSETS / "data/atlases").glob("*.json"))
    }


def repack_levels(source_atlases: dict[str, dict]) -> dict:
    content = json.loads((ROOT / "data/campaign_content.json").read_text(encoding="utf-8"))
    level_ids = sorted(int(k) for k in content["levels"])
    level_atlases = {}
    level_manifests = {}
    consumers: dict[tuple[str, str], set[int]] = collections.defaultdict(set)

    for lv in level_ids:
        folder = ROOT / f"data/level{lv:02d}"
        atlas = json.loads((folder / "atlas.json").read_text(encoding="utf-8"))
        manifest = json.loads((folder / "manifest.json").read_text(encoding="utf-8"))
        level_atlases[lv] = atlas
        level_manifests[lv] = manifest
        for fmeta in atlas["frames"].values():
            consumers[(fmeta["source_group"], fmeta["source_frame"])].add(lv)

    buckets: dict[tuple[int, ...], list[tuple[str, str]]] = collections.defaultdict(list)
    for key, lvs in consumers.items():
        buckets[tuple(sorted(lvs))].append(key)

    # Order shared buckets consistently across all levels (most shared first, then deterministic signature).
    ordered_sigs = sorted(buckets.keys(), key=lambda sig: (-len(sig), sig))
    packed_buckets = {}
    for sig in ordered_sigs:
        packed_buckets[sig] = pack_bucket(buckets[sig], source_atlases)

    total_pages_written = 0
    unique_page_hashes = set()
    for lv in level_ids:
        folder = ROOT / f"data/level{lv:02d}"
        atlas = level_atlases[lv]
        manifest = level_manifests[lv]

        # Build mapping from (source_group, source_frame) -> (new_sheet, new_region)
        frame_locations: dict[tuple[str, str], tuple[str, list[float]]] = {}
        page_index = 0
        new_media: list[str] = []
        for sig in ordered_sigs:
            if lv not in sig:
                continue
            for png_bytes, placements in packed_buckets[sig]:
                sheet_name = f"atlas_{page_index}.png"
                write_bytes_if_changed(folder / sheet_name, png_bytes)
                new_media.append(f"res://data/level{lv:02d}/{sheet_name}")
                unique_page_hashes.add(hashlib.sha256(png_bytes).hexdigest())
                for key, region in placements.items():
                    frame_locations[key] = (sheet_name, region)
                page_index += 1
        total_pages_written += page_index

        for stale in folder.glob("atlas_*.png"):
            idx = int(stale.stem.split("_")[1])
            if idx >= page_index:
                stale.unlink()
                stale.with_name(stale.name + ".import").unlink(missing_ok=True)

        for fmeta in atlas["frames"].values():
            key = (fmeta["source_group"], fmeta["source_frame"])
            sheet_name, region = frame_locations[key]
            fmeta["sheet"] = sheet_name
            fmeta["region"] = region
        write_json(folder / "atlas.json", atlas)

        audio_resources = [r for r in manifest["resources"] if not r.endswith(".png")]
        manifest["resources"] = new_media + audio_resources
        write_json(folder / "manifest.json", manifest)

    return {
        "levels": len(level_ids),
        "buckets": len(ordered_sigs),
        "total_level_pages": total_pages_written,
        "unique_level_pages": len(unique_page_hashes),
    }


def repack_standalone_atlas(folder_name: str, source_atlases: dict[str, dict]) -> dict:
    folder = ROOT / "data" / folder_name
    atlas = json.loads((folder / "atlas.json").read_text(encoding="utf-8"))
    manifest = json.loads((folder / "manifest.json").read_text(encoding="utf-8"))

    # Keep generated portraits or any non-atlas-sheet PNG separate (e.g. heroes/portrait_*.png).
    atlas_frames = [
        (name, meta) for name, meta in atlas["frames"].items()
        if meta.get("sheet", "").startswith("atlas_")
    ]
    keys = sorted({(meta["source_group"], meta["source_frame"]) for _, meta in atlas_frames})
    pages = pack_bucket(keys, source_atlases)

    locations = {}
    new_atlas_media = []
    for idx, (png_bytes, placements) in enumerate(pages):
        sheet_name = f"atlas_{idx}.png"
        write_bytes_if_changed(folder / sheet_name, png_bytes)
        new_atlas_media.append(f"res://data/{folder_name}/{sheet_name}")
        for key, region in placements.items():
            locations[key] = (sheet_name, region)

    for stale in folder.glob("atlas_*.png"):
        idx = int(stale.stem.split("_")[1])
        if idx >= len(pages):
            stale.unlink()
            stale.with_name(stale.name + ".import").unlink(missing_ok=True)

    for name, meta in atlas_frames:
        sheet_name, region = locations[(meta["source_group"], meta["source_frame"])]
        meta["sheet"] = sheet_name
        meta["region"] = region
    write_json(folder / "atlas.json", atlas)

    other_resources = [
        r for r in manifest["resources"]
        if not (r.startswith(f"res://data/{folder_name}/atlas_") and r.endswith(".png"))
    ]
    manifest["resources"] = new_atlas_media + other_resources
    write_json(folder / "manifest.json", manifest)
    total_kb = sum((folder / f"atlas_{i}.png").stat().st_size for i in range(len(pages))) / 1024
    return {"folder": folder_name, "pages": len(pages), "png_kb": round(total_kb, 1)}


def main() -> None:
    source_atlases = load_source_atlases()
    levels_summary = repack_levels(source_atlases)
    map_summary = repack_standalone_atlas("map_kr1", source_atlases)
    heroes_summary = repack_standalone_atlas("heroes", source_atlases)
    print(json.dumps({"levels": levels_summary, "map_kr1": map_summary, "heroes": heroes_summary}, indent=2))


if __name__ == "__main__":
    main()
