"""Check UI-only regeneration against the committed level-six gameplay and source pixels."""
import hashlib
import json
from pathlib import Path
from verify_level01_assets import verify as verify_pixels
from prepare_level01 import gameplay_projection

ROOT = Path(__file__).resolve().parents[1]

def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()

def verify():
    baseline = json.loads((ROOT / "tests/fixtures/battle_ui_baseline.json").read_text(encoding="utf-8"))
    rows = {}
    for name, expected in baseline["definitions"].items():
        folder = ROOT / "data" / name
        definition = json.loads((folder / "definition.json").read_text(encoding="utf-8"))
        gameplay = gameplay_projection(definition)
        ui = gameplay.pop("ui")
        assert digest(gameplay) == expected["gameplay_sha256"], f"{name}: non-UI data changed"
        assert ui.pop("tower_menu_power_offset") == [{"x":7,"y":-16},{"x":25,"y":-9},{"x":31,"y":8}]
        markers = ui.pop("selection_markers")
        assert all(markers[size]["name"] == "selected_" + size and markers[size]["z"] == 1400 for size in ("small", "med", "big", "soldier_small"))
        assert markers["rally"]["name"] == "decal_rally_feedback"
        assert digest(ui) == expected["previous_ui_sha256"], f"{name}: existing UI data changed"
        atlas = json.loads((folder / "atlas.json").read_text(encoding="utf-8"))
        required = {"selected_small", "selected_med", "selected_big", "selected_soldier_small", "pointer_user_power_0001", "pointer_user_power_0002", "special_icons_0000", "power_rank_0001", "power_rank_0002", "button_continue_chains", "button_restart_chains"}
        for prefix, end in (("pointer_fireball",32),("pointer_point_orange",10),("pointer_set_rally",10),("rally_feedback",30),("effect_powerbuy",23)):
            required.update(f"{prefix}_{frame:04d}" for frame in range(1,end+1))
        assert required <= atlas["lookup"].keys(), f"{name}: missing UI frames {required - atlas['lookup'].keys()}"
        verify_pixels(int(definition["level"]["id"]), name == "ranger_arena")
        rows[name] = {"gameplay_unchanged":True,"previous_ui_unchanged":True,"required_ui_frames":len(required),"source_pixels_verified":True}
    for path, expected in baseline["resource_files"].items():
        file = ROOT / path
        actual = digest(json.loads(file.read_text(encoding="utf-8"))) if file.suffix == ".json" else hashlib.sha256(file.read_bytes()).hexdigest()
        assert actual == expected, f"{path}: UI resource baseline differs"
    result = {"passed":True,"baseline_commit":baseline["baseline_commit"],"definitions":rows,"resource_files":len(baseline["resource_files"]),"scope":"All seven regenerated contents; non-UI gameplay and existing UI unchanged; binding metadata excluded from gameplay projection; source pixels and complete new frame families checked"}
    (ROOT / "reports/battle_ui_assets.json").write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(result,ensure_ascii=False))

if __name__ == "__main__": verify()
