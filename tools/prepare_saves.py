"""Export Dove's shared slot template and generation rules without accessing saves."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess

ROOT = Path(__file__).resolve().parents[1]
from dove_source import BASE, VERSION
INPUTS = ["kr1/data/slot_template.lua", "kr1/game_settings.lua", "all/storage.lua",
          "all/utils.lua", "all/systems/level.lua", "all/systems/enemy.lua",
          "all/game.lua", "all-desktop/screen_map.lua"]


def prepare(source, love, check=False):
    assert subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip() == BASE
    assert not subprocess.check_output(["git", "-C", str(source), "status", "--porcelain"], text=True).strip()
    output = ROOT / "output/save_export/evaluated.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, DOVE_SOURCE_DIR=str(source), DOVE_EXPORT_PATH=str(output))
    run = subprocess.run([str(love), str(ROOT / "tools/save_export")], env=env, capture_output=True, timeout=60)
    if run.returncode:
        raise RuntimeError(Path(str(output) + ".error").read_text(encoding="utf-8"))
    data = json.loads(output.read_text(encoding="utf-8"))
    template = data["template"]
    # Lua's empty table has no array/object distinction. Give JSON explicit types.
    for key in ("seen", "upgrades", "heroes", "levels"):
        template[key] = template[key] or {}
    template["levels"] = {str(key): value or {} for key, value in template["levels"].items()}
    template["heroes"]["selected"] = []
    # Defaults added by storage:load_slot, rather than slot_template.lua.
    storage = (source / "all/storage.lua").read_text(encoding="utf-8")
    assert "gems = 0" in storage and "bag = {}" in storage
    template.update(schema_version=1, gems=0, bag={})
    data.update(schema_version=1, source={"version": VERSION, "commit": BASE,
        "inputs": {p: hashlib.sha256((source / p).read_bytes()).hexdigest() for p in INPUTS}})
    target = ROOT / "data/save/definition.json"
    if check:
        assert json.loads(target.read_text(encoding="utf-8")) == data, "Save definition differs from frozen source"
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(json.dumps({"generations": sorted(data["generations"]), "source_inputs": len(INPUTS),
                      "locked_towers": len(template["locked_towers"])}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("D:/projects/KingdomRushDove"))
    parser.add_argument("--love", type=Path, default=Path("D:/王国保卫战Dove版/love.exe"))
    parser.add_argument("--check", action="store_true", help="Compare with the frozen export without changing data/save")
    args = parser.parse_args()
    prepare(args.source.resolve(), args.love.resolve(), args.check)
