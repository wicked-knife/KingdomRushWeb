"""Generate lightweight shared loading assets from existing Kingdom Rush art.

Outputs:
- data/loading/march_strip.png : 2-row sprite sheet (row 0 = soldier_lvl2 running, row 1 = goblin running)
- data/loading/march_meta.json : frame layout & animation sequences (preserves Dove timing/aliases)
- web/loading_march.png        : copy of march_strip.png for pre-engine Web shell
- web/loading_logo.png         : compact static logo derived from homeMenu_logo_0017
- web/loading_bg.jpg           : soft blurred vignette backdrop derived from data/menu/background.png
"""
from __future__ import annotations

import json
from pathlib import Path
from PIL import Image, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT_GODOT = ROOT / "data/loading"
OUT_WEB = ROOT / "web"

CELL_W = 64
CELL_H = 80
SOLDIER_FRAMES = [2, 3, 4, 5, 6]
# Original 22-frame Dove sequence has 12 unique frames (most are held 2 ticks at 30fps).
# We pack the 12 unique frames into row 1 and store the full 22-tick index sequence in JSON.
GOBLIN_TICKS = list(range(1, 23))


def load_atlas(path: Path) -> tuple[dict, dict[str, Image.Image]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    tex_dir = ROOT / str(data["texture_directory"]).removeprefix("res://")
    sheets: dict[str, Image.Image] = {}

    def get_sheet(name: str) -> Image.Image:
        if name not in sheets:
            sheets[name] = Image.open(tex_dir / name).convert("RGBA")
        return sheets[name]

    data["_get_sheet"] = get_sheet
    return data, sheets


def extract_frame(atlas: dict, frame_name: str) -> tuple[Image.Image, dict]:
    canonical = atlas.get("lookup", {}).get(frame_name, frame_name)
    meta = atlas["frames"][canonical]
    x, y, w, h = [int(round(v)) for v in meta["region"]]
    sheet: Image.Image = atlas["_get_sheet"](meta["sheet"])
    crop = sheet.crop((x, y, x + w, y + h))
    return crop, meta


def paste_bottom_aligned(canvas: Image.Image, crop: Image.Image, meta: dict, cell_x: int, cell_y: int, foot_y: int) -> None:
    """Align frames by their original foot baseline and horizontal center inside CELL_W x CELL_H."""
    orig_w, _orig_h = meta["original_size"]
    trim_x, trim_y = meta["trim"]
    w, h = crop.size
    # Preserve slight horizontal lean relative to original sprite center
    orig_center_x = orig_w * 0.5
    dx = int(round((trim_x + w * 0.5) - orig_center_x))
    px = cell_x + (CELL_W - w) // 2 + dx
    # Bottom-align relative to baseline foot_y in original coordinates
    dy = int(round((trim_y + h) - foot_y))
    py = cell_y + (CELL_H - 4) - h + dy
    px = max(cell_x, min(cell_x + CELL_W - w, px))
    py = max(cell_y, min(cell_y + CELL_H - h, py))
    canvas.alpha_composite(crop, (px, py))


def build_march_strip() -> dict:
    level01, _ = load_atlas(ROOT / "data/level01/atlas.json")
    lookup = level01.get("lookup", {})

    goblin_unique: list[str] = []
    goblin_sequence: list[int] = []
    for tick in GOBLIN_TICKS:
        name = f"goblin_{tick:04d}"
        canonical = lookup.get(name, name)
        if canonical not in goblin_unique:
            goblin_unique.append(canonical)
        goblin_sequence.append(goblin_unique.index(canonical))

    cols = max(len(SOLDIER_FRAMES), len(goblin_unique))
    strip = Image.new("RGBA", (cols * CELL_W, 2 * CELL_H), (0, 0, 0, 0))

    # Row 0: soldier_lvl2 running (baseline foot y=130 in 272x152)
    for idx, num in enumerate(SOLDIER_FRAMES):
        crop, meta = extract_frame(level01, f"soldier_lvl2_{num:04d}")
        paste_bottom_aligned(strip, crop, meta, idx * CELL_W, 0, foot_y=130)

    # Row 1: goblin walkingRightLeft (baseline foot y=80 in 136x96)
    for idx, canonical in enumerate(goblin_unique):
        crop, meta = extract_frame(level01, canonical)
        paste_bottom_aligned(strip, crop, meta, idx * CELL_W, CELL_H, foot_y=80)

    OUT_GODOT.mkdir(parents=True, exist_ok=True)
    OUT_WEB.mkdir(parents=True, exist_ok=True)

    # Quantize gently with alpha preserved for crisp small PNG (~25 KB)
    strip_q = strip.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    strip_godot = OUT_GODOT / "march_strip.png"
    strip_q.save(strip_godot, format="PNG", optimize=True)
    strip_web = OUT_WEB / "loading_march.png"
    strip_q.save(strip_web, format="PNG", optimize=True)

    meta_out = {
        "schema_version": 1,
        "texture": "res://data/loading/march_strip.png",
        "cell_size": [CELL_W, CELL_H],
        "sheet_size": [strip.width, strip.height],
        "soldier": {
            "row": 0,
            "fps": 12.0,
            "frames": list(range(len(SOLDIER_FRAMES))),
            "unique_count": len(SOLDIER_FRAMES),
        },
        "goblin": {
            "row": 1,
            "fps": 26.0,
            "frames": goblin_sequence,
            "unique_count": len(goblin_unique),
        },
    }
    (OUT_GODOT / "march_meta.json").write_text(json.dumps(meta_out, indent=2) + "\n", encoding="utf-8")
    return {
        "march_strip_bytes": strip_godot.stat().st_size,
        "march_strip_size": [strip.width, strip.height],
        "soldier_frames": len(SOLDIER_FRAMES),
        "goblin_unique": len(goblin_unique),
        "goblin_ticks": len(goblin_sequence),
    }


def build_web_logo() -> dict:
    slots, _ = load_atlas(ROOT / "data/menu/screen_slots.json")
    crop, _meta = extract_frame(slots, "homeMenu_logo_0017")
    # Scale cleanly to width ~360px for crisp Retina display in Web shell while staying tiny
    target_w = 360
    target_h = int(round(crop.height * (target_w / crop.width)))
    resized = crop.resize((target_w, target_h), Image.Resampling.LANCZOS)
    # Quantize RGBA with fast octree (256 colors) to keep Web logo ~25-35 KB
    quantized = resized.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG)
    out = OUT_WEB / "loading_logo.png"
    quantized.save(out, format="PNG", optimize=True)
    return {"web_logo_bytes": out.stat().st_size, "web_logo_size": [target_w, target_h]}


def build_web_backdrop() -> dict:
    bg = Image.open(ROOT / "data/menu/background.png").convert("RGB")
    small = bg.resize((768, 432), Image.Resampling.LANCZOS)
    blurred = small.filter(ImageFilter.GaussianBlur(radius=4.5))
    moody = ImageEnhance.Brightness(blurred).enhance(0.52)
    out = OUT_WEB / "loading_bg.jpg"
    moody.save(out, format="JPEG", quality=76, optimize=True, progressive=True)
    return {"web_bg_bytes": out.stat().st_size, "web_bg_size": [768, 432]}


def main() -> None:
    report = {}
    report.update(build_march_strip())
    report.update(build_web_logo())
    report.update(build_web_backdrop())
    total_web = report["march_strip_bytes"] + report["web_logo_bytes"] + report["web_bg_bytes"]
    report["total_web_bytes"] = total_web
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
