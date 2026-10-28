"""Project explicit additive technology data onto the unchanged historical baseline."""
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADDITIONS = json.loads((ROOT / "tests/fixtures/upgrades_additions.json").read_text(encoding="utf-8"))


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()


def previous_gameplay(name, gameplay):
    value = copy.deepcopy(gameplay)
    additions = ADDITIONS["definitions"][name]
    for key in additions["templates"]:
        del value["templates"][key]
    assert value["templates"]["power_fireball_control"].pop("cataclysm_count") == 0
    assert value["templates"]["power_fireball"].pop("scorch_earth") is False
    for group in ("strings", "unit_names"):
        for key in additions[group]: del value["ui"][group][key]
    if name == "ranger_arena":
        value["seen_notifications"] = [key for key in value["seen_notifications"] if key not in additions["templates"]]
    return value


def previous_resource_digest(path):
    relative = path.relative_to(ROOT).as_posix()
    if not path.is_file(): return None
    if relative not in ADDITIONS["resources"]:
        return digest(json.loads(path.read_text(encoding="utf-8"))) if path.suffix == ".json" else hashlib.sha256(path.read_bytes()).hexdigest()
    value = json.loads(path.read_text(encoding="utf-8"))
    for group, keys in ADDITIONS["resources"][relative].items():
        if group == "logical_sha256": continue
        owner = value if group == "root" else value[group]
        for key in keys: del owner[key]
    if path.name == "atlas.json":
        for frame in value["frames"].values():
            for key in ("sheet", "region"): del frame[key]
        assert digest(value) == ADDITIONS["resources"][relative]["logical_sha256"], relative + ": pre-existing atlas frames changed"
        return None  # Repacking is verified against source pixels, not old PNG coordinates.
    return digest(value)


def repacked(path):
    return path.parent.name in ADDITIONS["definitions"] and (path.name == "atlas.json" or path.name.startswith("atlas_") and path.suffix == ".png")
