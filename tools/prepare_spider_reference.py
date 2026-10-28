"""Run the pinned Dove spider scripts; no game startup or player save access."""
import json
import os
from pathlib import Path
import subprocess

from dove_source import provenance, verify
from import_dove_assets import decode_animations

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path("D:/projects/KingdomRushDove")
INPUTS = ["kr1/enemies.lua", "kr1/game_scripts.lua", "all/scripts.lua",
          "all/utils.lua", "kr1/data/game_animations.bin", "all/simulation.lua"]

if __name__ == "__main__":
    verify(SOURCE)
    data = json.loads((ROOT / "data/level05/definition.json").read_text(encoding="utf-8"))
    animations = decode_animations((SOURCE / "kr1/data/game_animations.bin").read_bytes())["animations"]
    payload = {"source": provenance(SOURCE, INPUTS),
               "templates": {name: data["templates"][name] for name in
                             ["enemy_spider_big", "enemy_spider_egg", "enemy_spider_tiny"]},
               "animations": {key: value for key, value in animations.items()
                              if key.startswith("enemy_spider_egg_")}}
    target = ROOT / "output/spider_reference_input.json"
    target.parent.mkdir(exist_ok=True)
    target.write_text(json.dumps(payload), encoding="utf-8")
    subprocess.run(["D:/王国保卫战Dove版/love.exe", str(ROOT / "tools/spider_reference")],
                   env=dict(os.environ, DOVE_SOURCE_DIR=str(SOURCE), DOVE_PROJECT=str(ROOT)), check=True, timeout=30)
    result = json.loads((ROOT / "tests/fixtures/dove_spider_source.json").read_text(encoding="utf-8"))
    print(json.dumps({"frames": len(result["frames"]), "spawns": result["spawns"],
                      "mother_spawns": result["mother_spawns"]}))
