"""Generate lightweight Web-boot fonts, trimmed menu atlases, and minimal menu locale/sounds."""
from __future__ import annotations

import hashlib
import io
import json
import math
from pathlib import Path
import shutil
from PIL import Image
from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
MENU_OUT = ROOT / "data/menu"
FONTS_OUT = ROOT / "data/fonts_web"
MANIFEST_PATH = ROOT / "data/menu_manifest.json"
ASSETS = ROOT / "assets/kingdom_rush"
SOURCE_FONTS = ASSETS / "all-desktop/fonts"

MENU_LOCALE_KEYS = [
    "CREDITS",
    "QUIT",
    "OPTIONS",
    "SFX",
    "Music",
    "Done",
    "Yes",
    "No",
]
MENU_SOUND_KEYS = ["MusicMainMenu", "GUIButtonCommon"]
EXTRA_SAFE_CHARS = (
    "".join(chr(c) for c in range(32, 127))
    + "—–·…‘’“”•°±×÷→←↑↓≥≤≠≈%‰℃、。，；：？！（）【】《》「」『』〔〕～·"
    + "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    + "加载游戏请稍候失败重试返回正在点击任意按钮或按键开启声音版本较新存档损坏确定删除取消制作人员页面暂未开放退出"
)


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False) + "\n"
    if path.is_file() and path.read_text(encoding="utf-8") == text:
        return
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(path)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def collect_project_chars() -> set[str]:
    chars = set(EXTRA_SAFE_CHARS)
    patterns = [
        *ROOT.glob("data/**/*.json"),
        ASSETS / "data/locale_zh-Hans.json",
        *ROOT.glob("scripts/**/*.gd"),
        *ROOT.glob("scenes/**/*.tscn"),
    ]
    for path in patterns:
        if not path.is_file():
            continue
        if path.is_relative_to(MENU_OUT) or path.is_relative_to(FONTS_OUT):
            continue
        try:
            chars.update(path.read_text(encoding="utf-8"))
        except UnicodeDecodeError:
            pass
    return {ch for ch in chars if ord(ch) >= 32}


def subset_font(src: Path, dst: Path, text: str, font_number: int = -1) -> set[int]:
    dst.parent.mkdir(parents=True, exist_ok=True)
    tt = TTFont(src, fontNumber=font_number) if font_number >= 0 else TTFont(src)
    options = subset.Options(
        retain_gids=False,
        hinting=True,
        layout_features=["*"],
        name_IDs=["*"],
        glyph_names=False,
    )
    sub = subset.Subsetter(options=options)
    sub.populate(text=text)
    sub.subset(tt)
    buf = io.BytesIO()
    tt.save(buf)
    tt.close()
    raw = buf.getvalue()
    if not dst.is_file() or dst.read_bytes() != raw:
        tmp = dst.with_name(dst.name + ".tmp")
        tmp.write_bytes(raw)
        tmp.replace(dst)
    check_tt = TTFont(io.BytesIO(raw))
    covered = set(check_tt.getBestCmap().keys())
    check_tt.close()
    return covered


def build_fonts(chars: set[str]) -> list[str]:
    FONTS_OUT.mkdir(parents=True, exist_ok=True)
    text = "".join(sorted(chars))
    msyh_cps = subset_font(SOURCE_FONTS / "msyh.ttc", FONTS_OUT / "msyh.ttf", text, font_number=0)
    subset_font(SOURCE_FONTS / "msyhbd.ttc", FONTS_OUT / "msyhbd.ttf", text, font_number=0)
    subset_font(SOURCE_FONTS / "JIMOJW.ttf", FONTS_OUT / "JIMOJW.ttf", text)
    # NotoSansCJKkr-Regular is only used as fallback for glyphs missing from msyh.
    fallback_chars = {ch for ch in chars if ord(ch) not in msyh_cps}
    fallback_chars.update({" ", "?", "□"})
    subset_font(
        SOURCE_FONTS / "NotoSansCJKkr-Regular.otf",
        FONTS_OUT / "NotoSansCJKkr-Regular.otf",
        "".join(sorted(fallback_chars)),
    )
    # Keep Comic Book Italic and TOONISH full or lightly copied (they are tiny ~40-90 KB).
    for small_name in ("Comic Book Italic.ttf", "TOONISH.ttf"):
        src = SOURCE_FONTS / small_name
        dst = FONTS_OUT / small_name
        raw = src.read_bytes()
        if not dst.is_file() or dst.read_bytes() != raw:
            dst.write_bytes(raw)
    return [
        "res://data/fonts_web/msyh.ttf",
        "res://data/fonts_web/msyhbd.ttf",
        "res://data/fonts_web/JIMOJW.ttf",
        "res://data/fonts_web/Comic Book Italic.ttf",
        "res://data/fonts_web/TOONISH.ttf",
        "res://data/fonts_web/NotoSansCJKkr-Regular.otf",
    ]


def align_up(value: int, step: int = 16) -> int:
    return ((value + step - 1) // step) * step


def save_png_if_changed(image: Image.Image, target: Path) -> None:
    buf = io.BytesIO()
    image.save(buf, format="PNG", compress_level=6)
    content = buf.getvalue()
    buf.close()
    if not target.is_file() or target.read_bytes() != content:
        tmp = target.with_name(target.name + ".tmp")
        tmp.write_bytes(content)
        tmp.replace(target)


def build_menu_assets() -> dict:
    MENU_OUT.mkdir(parents=True, exist_ok=True)
    old_manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    frames_req: dict[str, list[str]] = old_manifest["frames"]

    # 1. Extract 1920x1080 background from screen_slots-1.png (homeMenu_bg at [6, 6, 1920, 1080])
    screen_slots_atlas = json.loads((ASSETS / "data/atlases/screen_slots.json").read_text(encoding="utf-8"))
    bg_def = screen_slots_atlas["frames"]["homeMenu_bg"]
    bg_src = ROOT / screen_slots_atlas["texture_directory"].removeprefix("res://") / bg_def["sheet"]
    bx, by, bw, bh = [int(round(v)) for v in bg_def["region"]]
    with Image.open(bg_src) as im:
        bg = im.convert("RGBA").crop((bx, by, bx + bw, by + bh))
        save_png_if_changed(bg, MENU_OUT / "background.png")
        bg.close()

    # 2. Gather required frames from screen_slots and view_options
    items = []
    source_atlases = {}
    for group_name, frame_names in frames_req.items():
        atlas_data = json.loads((ASSETS / f"data/atlases/{group_name}.json").read_text(encoding="utf-8"))
        source_atlases[group_name] = atlas_data
        seen_canon = {}
        for req_name in frame_names:
            canon = atlas_data.get("lookup", {}).get(req_name, req_name)
            if canon in seen_canon:
                continue
            seen_canon[canon] = req_name
            fdef = atlas_data["frames"][canon]
            sx, sy, w, h = fdef["region"]
            left, top = math.floor(sx), math.floor(sy)
            width, height = math.ceil(sx + w) - left, math.ceil(sy + h) - top
            items.append((group_name, canon, fdef, left, top, width, height))

    # Sort by height descending for tight shelf packing (minimizes wasted space -> fits in 1 page!).
    items.sort(key=lambda row: (-row[6], -row[5], row[0], row[1]))

    pages_rects = []
    page_items: list[tuple] = []
    x = y = row_h = max_x = 0
    for item in items:
        _, _, _, _, _, width, height = item
        if x + width + 4 > 2048:
            x = 0
            y += row_h
            row_h = 0
        if y + height + 4 > 2048:
            pages_rects.append((page_items, align_up(max(64, max_x)), align_up(max(64, y + row_h))))
            page_items = []
            x = y = row_h = max_x = 0
        page_items.append((item, x + 2, y + 2))
        x += width + 4
        max_x = max(max_x, x)
        row_h = max(row_h, height + 4)
    pages_rects.append((page_items, align_up(max(64, max_x)), align_up(max(64, y + row_h))))

    sheet_cache: dict[Path, Image.Image] = {}
    group_frames: dict[str, dict] = {g: {} for g in frames_req}
    textures = []
    try:
        for page_idx, (placed, pw, ph) in enumerate(pages_rects):
            canvas = Image.new("RGBA", (min(2048, pw), min(2048, ph)))
            sheet_name = f"atlas_{page_idx}.png"
            for (group_name, canon, fdef, left, top, width, height), px, py in placed:
                tex_dir = ROOT / source_atlases[group_name]["texture_directory"].removeprefix("res://")
                src_path = tex_dir / fdef["sheet"]
                if src_path not in sheet_cache:
                    sheet_cache[src_path] = Image.open(src_path).convert("RGBA")
                tile = sheet_cache[src_path].crop((left, top, left + width, top + height))
                canvas.paste(tile, (px, py))
                tile.close()
                sx, sy, w, h = fdef["region"]
                new_def = dict(fdef)
                new_def["sheet"] = sheet_name
                new_def["region"] = [px + sx - left, py + sy - top, w, h]
                group_frames[group_name][canon] = new_def
            save_png_if_changed(canvas, MENU_OUT / sheet_name)
            canvas.close()
            textures.append(f"res://data/menu/{sheet_name}")
    finally:
        for im in sheet_cache.values():
            im.close()

    for stale in MENU_OUT.glob("atlas_*.png"):
        idx = int(stale.stem.split("_")[1])
        if idx >= len(pages_rects):
            stale.unlink()
            stale.with_name(stale.name + ".import").unlink(missing_ok=True)

    atlases_out = {}
    catalog_groups = {}
    for group_name, frame_names in frames_req.items():
        atlas_data = source_atlases[group_name]
        lookup = {}
        aliases = {}
        for req_name in frame_names:
            canon = atlas_data.get("lookup", {}).get(req_name, req_name)
            lookup[req_name] = canon
            if req_name != canon:
                aliases[req_name] = canon
        for canon in group_frames[group_name]:
            lookup.setdefault(canon, canon)
        atlas_path = MENU_OUT / f"{group_name}.json"
        write_json(
            atlas_path,
            {
                "schema_version": 1,
                "group": group_name,
                "texture_directory": "res://data/menu/",
                "frames": group_frames[group_name],
                "lookup": lookup,
                "aliases": aliases,
            },
        )
        res_path = f"res://data/menu/{group_name}.json"
        atlases_out[group_name] = res_path
        catalog_groups[group_name] = {"path": res_path}

    write_json(
        MENU_OUT / "catalog.json",
        {
            "schema_version": 1,
            "groups": catalog_groups,
            "static": {"sounds": "res://data/menu/sounds.json"},
            "audio_directory": "res://assets/kingdom_rush/kr1-desktop/sounds/files/",
        },
    )

    full_locale = json.loads((ASSETS / "data/locale_zh-Hans.json").read_text(encoding="utf-8"))
    menu_locale = {k: full_locale[k] for k in MENU_LOCALE_KEYS}
    write_json(MENU_OUT / "locale_zh-Hans.json", menu_locale)

    full_sounds = json.loads((ASSETS / "data/sounds.json").read_text(encoding="utf-8"))
    menu_sounds = {k: full_sounds[k] for k in MENU_SOUND_KEYS}
    write_json(MENU_OUT / "sounds.json", menu_sounds)

    return {
        "background": "res://data/menu/background.png",
        "catalog": "res://data/menu/catalog.json",
        "locale": "res://data/menu/locale_zh-Hans.json",
        "sounds": "res://data/menu/sounds.json",
        "atlases": atlases_out,
        "textures": textures,
        "pages": [(pw, ph) for _, pw, ph in pages_rects],
    }


def main() -> None:
    chars = collect_project_chars()
    fonts = build_fonts(chars)
    menu_assets = build_menu_assets()
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    manifest["background"] = menu_assets["background"]
    manifest["catalog"] = menu_assets["catalog"]
    manifest["locale"] = menu_assets["locale"]
    manifest["sounds"] = menu_assets["sounds"]
    manifest["atlases"] = menu_assets["atlases"]
    manifest["textures"] = menu_assets["textures"]
    manifest["font"] = fonts[0]
    manifest["fonts"] = fonts
    manifest["font_source"] = {
        **manifest.get("font_source", {}),
        "subset_chars": len(chars),
        "web_resources": {path: sha256(ROOT / path.removeprefix("res://")) for path in fonts},
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    font_kb = sum((ROOT / p.removeprefix("res://")).stat().st_size for p in fonts) / 1024
    tex_kb = (
        (MENU_OUT / "background.png").stat().st_size
        + sum((ROOT / p.removeprefix("res://")).stat().st_size for p in menu_assets["textures"])
    ) / 1024
    print(
        json.dumps(
            {
                "subset_chars": len(chars),
                "fonts_total_kb": round(font_kb, 1),
                "menu_png_total_kb": round(tex_kb, 1),
                "menu_atlas_pages": menu_assets["pages"],
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
