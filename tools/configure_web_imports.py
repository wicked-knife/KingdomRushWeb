"""Configure lossy WebP (Q=0.90) texture import settings and font compression for Web exports."""
from __future__ import annotations

import json
from pathlib import Path
import re
import subprocess
from web_bootstrap import ROOT, godot_path, resource_paths

WEBP_QUALITY = "0.9"


def target_textures_and_fonts() -> tuple[list[Path], list[Path]]:
    resources, _ = resource_paths()
    textures: list[Path] = []
    fonts: list[Path] = []
    for res in resources:
        local = ROOT / res.removeprefix("res://")
        if res.endswith(".png"):
            textures.append(local)
        elif res.endswith((".ttf", ".otf", ".ttc")):
            fonts.append(local)
    # Also ensure generated menu/map/hero/level atlases outside manifest edge cases are covered.
    for folder in (ROOT / "data").iterdir():
        if not folder.is_dir():
            continue
        for png in folder.glob("*.png"):
            if png not in textures:
                textures.append(png)
    return sorted(set(textures)), sorted(set(fonts))


def update_import_param(text: str, key: str, value: str) -> str:
    pattern = re.compile(rf"^{re.escape(key)}=.*$", re.MULTILINE)
    replacement = f"{key}={value}"
    if pattern.search(text):
        return pattern.sub(replacement, text, count=1)
    if "[params]" in text:
        return text.rstrip() + f"\n{replacement}\n"
    return text


def configure_texture_import(import_file: Path) -> bool:
    if not import_file.is_file():
        return False
    original = import_file.read_text(encoding="utf-8")
    updated = original
    updated = update_import_param(updated, "compress/mode", "1")
    updated = update_import_param(updated, "compress/high_quality", "false")
    updated = update_import_param(updated, "compress/lossy_quality", WEBP_QUALITY)
    updated = update_import_param(updated, "mipmaps/generate", "false")
    updated = update_import_param(updated, "process/fix_alpha_border", "true")
    updated = update_import_param(updated, "detect_3d/compress_to", "0")
    if updated != original:
        import_file.write_text(updated, encoding="utf-8")
        return True
    return False


def configure_font_import(import_file: Path) -> bool:
    if not import_file.is_file():
        return False
    original = import_file.read_text(encoding="utf-8")
    updated = original
    updated = update_import_param(updated, "allow_system_fallback", "false")
    updated = update_import_param(updated, "compress", "true")
    updated = update_import_param(updated, "generate_mipmaps", "false")
    updated = update_import_param(updated, "multichannel_signed_distance_field", "false")
    updated = update_import_param(updated, "hinting", "3")
    updated = update_import_param(updated, "subpixel_positioning", "4")
    if updated != original:
        import_file.write_text(updated, encoding="utf-8")
        return True
    return False


def run_godot_import(engine: str) -> None:
    subprocess.run([engine, "--headless", "--path", str(ROOT), "--import"], check=True)


def main() -> None:
    engine = godot_path()
    textures, fonts = target_textures_and_fonts()
    missing_imports = [p for p in [*textures, *fonts] if not p.with_name(p.name + ".import").is_file()]
    if missing_imports:
        print(f"Bootstrapping {len(missing_imports)} missing .import descriptors via Godot --import...")
        run_godot_import(engine)

    changed_tex = sum(configure_texture_import(p.with_name(p.name + ".import")) for p in textures)
    changed_fonts = sum(configure_font_import(p.with_name(p.name + ".import")) for p in fonts)
    if changed_tex or changed_fonts or missing_imports:
        print(f"Re-importing {changed_tex} texture(s) and {changed_fonts} font(s) via Godot --import...")
        run_godot_import(engine)

    print(
        json.dumps(
            {
                "textures_total": len(textures),
                "textures_updated": changed_tex,
                "fonts_total": len(fonts),
                "fonts_updated": changed_fonts,
                "webp_quality": WEBP_QUALITY,
            }
        )
    )


if __name__ == "__main__":
    main()
