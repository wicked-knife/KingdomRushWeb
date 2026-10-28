"""Export the default Dove technology tree, with source parameters and UI strings."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
from dove_source import BASE, VERSION
from upgrades_contract import technology_contracts

ROOT = Path(__file__).resolve().parents[1]
INPUTS = ["kr1/upgrades.lua", "kr1/upgrades/line1.lua", "kr1/upgrades/line2.lua",
          "kr1/upgrades/line3.lua", "kr1/upgrades/line4.lua", "kr1/upgrades/upgrade_utils.lua",
          "kr1/game_settings.lua", "all/constants.lua", "all-desktop/screen_map.lua",
          "all/systems/level.lua", "all/systems/tower.lua", "all/systems/health.lua",
          "all/scripts.lua", "kr1/game_scripts.lua", "kr1/tower_scripts.lua", "all/utils.lua", "all/path_db.lua", "all/grid_db.lua", "kr1/game_templates.lua", "all/templates.lua", "lib/klua/table.lua"]


def prepare(source, love, check=False):
    assert subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip() == BASE
    assert not subprocess.check_output(["git", "-C", str(source), "status", "--porcelain"], text=True).strip()
    output = ROOT / "output/upgrade_export/evaluated.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run([str(love), str(ROOT / "tools/upgrade_export")],
                            env=dict(os.environ, DOVE_SOURCE_DIR=str(source), DOVE_EXPORT_PATH=str(output)), capture_output=True, timeout=60)
    if result.returncode:
        raise RuntimeError(Path(str(output) + ".error").read_text(encoding="utf-8"))
    data = json.loads(output.read_text(encoding="utf-8"))
    locale = json.loads((ROOT / "assets/kingdom_rush/data/locale_zh-Hans.json").read_text(encoding="utf-8"))
    assert len(data["techs"]) == 36
    for name, tech in data["techs"].items():
        key = "UPGRADE_1_" + name
        tech["title"] = locale[key + "_NAME"]
        tech["description"] = locale[key + "_DESCRIPTION"]
        prefix = f"kr{tech['from_kr']}_" if tech.get("from_kr") else ""
        tech["image"] = f"{prefix}Upgrades_Icons_{tech['icon']:04d}"
    data["dependencies"] = technology_contracts(data)
    data["title"] = locale["UPGRADES_1"]
    data["strings"] = {k: locale[k] for k in ["BUTTON_RESET", "BUTTON_UNDO", "BUTTON_DONE"]}
    data.update(schema_version=1, source={"version": VERSION, "commit": BASE,
                "inputs": {p: hashlib.sha256((source / p).read_bytes()).hexdigest() for p in INPUTS}})
    target = ROOT / "data/upgrades/definition.json"
    if check:
        assert json.loads(target.read_text(encoding="utf-8")) == data
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(json.dumps({"techs": len(data["techs"]), "classes": data["classes"], "title": data["title"]}, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("D:/projects/KingdomRushDove"))
    parser.add_argument("--love", type=Path, default=Path("D:/王国保卫战Dove版/love.exe"))
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--reference", action="store_true", help="Run actual Dove patch functions and behavior coroutines to regenerate the independent reference")
    args = parser.parse_args()
    prepare(args.source, args.love, args.check)
    if args.reference:
        result = subprocess.run([str(args.love), str(ROOT / "tools/upgrade_reference")],
            env=dict(os.environ, DOVE_SOURCE_DIR=str(args.source), DOVE_PROJECT=str(ROOT)), capture_output=True, timeout=60)
        error = ROOT / "output/upgrade_reference.error"
        if result.returncode: raise RuntimeError(error.read_text(encoding="utf-8") if error.exists() else result.stderr.decode("utf-8", errors="replace"))
        error.unlink(missing_ok=True)
