"""Verify all registered campaign and arena definitions, dependencies, and fail-closed probes."""
import copy
import json
from campaign_content import ROOT, read_catalog, export_spec, validate_definition, combinations, level_ids
from upgrades_contract import validate_technology_resources
from web_bootstrap import resource_paths, validate_runtime_resources


def verify():
    catalog = read_catalog()
    rows, failures = {}, []
    targets = [(level_id, False, f"level{level_id:02d}") for level_id in level_ids()]
    for arena_name, arena in catalog.get("arenas", {}).items():
        targets.append((arena["id"], True, arena["folder"]))
    for level_id, is_arena, name in targets:
        definition = json.loads((ROOT / f"data/{name}/definition.json").read_text(encoding="utf-8"))
        animations = json.loads((ROOT / f"data/{name}/animations.json").read_text(encoding="utf-8"))["animations"]
        atlas = json.loads((ROOT / f"data/{name}/atlas.json").read_text(encoding="utf-8"))
        sounds = json.loads((ROOT / f"data/{name}/sounds.json").read_text(encoding="utf-8"))
        spec = export_spec(level_id, is_arena)
        try:
            validate_definition(definition, spec)
            validate_technology_resources(definition, animations, atlas, sounds)
        except ValueError as error:
            failures.append(f"{name}: {error}")
        source = definition["source"]
        rows[name] = {
            "source_current": all(source.get(k) == catalog["source"][k] for k in ("version", "commit")),
            "controller": definition["level"]["controller"],
            "behaviors": len(definition["behaviors"]),
            "dependency_owners": len(definition["dependencies"]),
        }
        if not rows[name]["source_current"]:
            failures.append(f"{name}: source mismatch")
    # Fail-closed probes: reachable actor, child template, mode, controller, source, runtime script.
    base = json.loads((ROOT / "data/level05/definition.json").read_text(encoding="utf-8"))
    probes = []
    for label in ("unknown_behavior", "missing_dependency", "missing_mode", "wrong_controller", "stale_source"):
        bad = copy.deepcopy(base)
        if label == "unknown_behavior":
            bad["behaviors"]["enemy_goblin"] = "unknown.enemy.update"
        if label == "missing_dependency":
            del bad["templates"]["arrow_elf"]
        if label == "missing_mode":
            del bad["modes"]["3"]
        if label == "wrong_controller":
            bad["level"]["controller"] = "unknown"
        if label == "stale_source":
            bad["source"]["commit"] = "stale"
        try:
            validate_definition(bad, export_spec(5))
        except ValueError as error:
            probes.append({"case": label, "rejected": True, "reason": str(error)})
        else:
            failures.append(f"Publication accepted {label}")
    resources, data = resource_paths()
    try:
        validate_runtime_resources([path for path in resources if path != "res://scripts/battle/dove_bfg.gd"])
    except ValueError as error:
        probes.append({"case": "missing_runtime_script", "rejected": True, "reason": str(error)})
    else:
        failures.append("Publication accepted missing_runtime_script")
    result = {
        "passed": not failures,
        "content_combinations": len(combinations()),
        "definitions": rows,
        "failure_probes": probes,
        "publication_resources": len(resources),
        "publication_data": len(data),
        "failures": failures,
    }
    (ROOT / "reports/content_catalog.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False))
    return not failures


if __name__ == "__main__":
    raise SystemExit(0 if verify() else 1)
