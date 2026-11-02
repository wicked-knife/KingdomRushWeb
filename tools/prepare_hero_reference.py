"""Generate the independent Malik oracle by executing the pinned Dove source."""
import json
import os
import subprocess
from pathlib import Path
from dove_source import verify, provenance
from dove_hero_assets import animations as load_animations

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path("D:/projects/KingdomRushDove")

if __name__ == "__main__":
    verify(SOURCE)
    output = ROOT / "output/hero_reference.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    animation_data, animation_inputs = load_animations(SOURCE)
    animations = animation_data["animations"]
    animation_path = ROOT / "output/hero_reference_animations.json"
    animation_path.write_text(json.dumps({key:value for key,value in animations.items() if key.startswith("hero_malik_")}), encoding="utf-8")
    result = subprocess.run(["D:/王国保卫战Dove版/love.exe", str(ROOT / "tools/hero_combat_export")],
        env=dict(os.environ, DOVE_SOURCE_DIR=str(SOURCE), DOVE_EXPORT_PATH=str(output),
                 DOVE_HERO_REFERENCE=str(ROOT / "tools/hero_combat_export/reference.lua"),
                 DOVE_HERO_ANIMATIONS=str(animation_path)), capture_output=True, timeout=45)
    if result.returncode:
        raise RuntimeError(Path(str(output)+".error").read_text(encoding="utf-8"))
    data = json.loads(output.read_text(encoding="utf-8"))
    inputs = ["kr1/heroes.lua", "kr1/hero_scripts.lua", "kr1/hero_utils.lua", "all/script_utils.lua",
              "all/utils.lua", "all/grid_a_star.lua", "all/grid_db.lua", "all/path_db.lua", "kr1/game_settings.lua", "kr1/data/game_animations.bin",
              *[f"kr1/data/levels/level{level:02d}_{kind}.lua" for level in (3,7) for kind in ("paths","grid")]]
    inputs += [p.relative_to(SOURCE).as_posix() for p in animation_inputs]
    inputs += ["kr1/heroes/hero_malik/templates.lua", "kr1/heroes/hero_malik/init.lua"]
    data["source"] = provenance(SOURCE, inputs)
    (ROOT / "tests/fixtures/hero_malik_source.json").write_text(json.dumps(data, ensure_ascii=False, separators=(",",":"))+"\n", encoding="utf-8")
    print({key:len(value) for key,value in data.items() if isinstance(value,list)})
