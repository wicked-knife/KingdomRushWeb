"""Check frozen gameplay fingerprints separately from new content metadata."""
import copy
import hashlib
import json
from campaign_content import ROOT, read_catalog, export_spec, validate_definition, combinations
from prepare_level01 import gameplay_projection
from web_bootstrap import resource_paths
from upgrades_compatibility import previous_gameplay, previous_resource_digest, repacked


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()


def resource_digest(path):
    if not path.is_file(): return None
    return digest(json.loads(path.read_text(encoding="utf-8"))) if path.suffix == ".json" else hashlib.sha256(path.read_bytes()).hexdigest()


def verify():
    baseline = json.loads((ROOT / "tests/fixtures/campaign_content_baseline.json").read_text(encoding="utf-8"))
    catalog = read_catalog()
    ui_baseline = json.loads((ROOT / "tests/fixtures/battle_ui_baseline.json").read_text(encoding="utf-8"))
    rows, failures = {}, []
    for name, expected in baseline["definitions"].items():
        definition = json.loads((ROOT / f"data/{name}/definition.json").read_text(encoding="utf-8"))
        spec = export_spec(definition["level"]["id"], name == "ranger_arena")
        validate_definition(definition, spec)
        gameplay = previous_gameplay(name, gameplay_projection(definition))
        # The UI revision adds source presentation metadata, without altering
        # any frozen gameplay or previous UI fields.
        for field in ("selection_markers", "tower_menu_power_offset"):
            gameplay["ui"].pop(field, None)
        source = gameplay.pop("source")
        changed = [key for key, value in gameplay.items() if digest(value) != baseline["sections"][name].get(key)]
        rows[name] = {"gameplay_unchanged": digest(gameplay) == expected, "changed_sections": changed,
                      "source_current": all(source[k] == catalog["source"][k] for k in ("version", "commit")),
                      "controller": definition["level"]["controller"], "behaviors": len(definition["behaviors"]),
                      "dependency_owners": len(definition["dependencies"])}
        if changed or not rows[name]["gameplay_unchanged"] or not rows[name]["source_current"]:
            failures.append(f"{name}: frozen gameplay/source mismatch; first section {next(iter(changed), 'source')}")
    # Meaningful fail-closed probes: a reachable actor, its child template, and
    # a registered mode must not disappear silently from the publication path.
    base = json.loads((ROOT / "data/level05/definition.json").read_text(encoding="utf-8"))
    probes = []
    for label in ("unknown_behavior", "missing_dependency", "missing_mode", "wrong_controller", "stale_source"):
        bad = copy.deepcopy(base)
        if label == "unknown_behavior": bad["behaviors"]["enemy_goblin"] = "unknown.enemy.update"
        if label == "missing_dependency": del bad["templates"]["arrow_elf"]
        if label == "missing_mode": del bad["modes"]["3"]
        if label == "wrong_controller": bad["level"]["controller"] = "unknown"
        if label == "stale_source": bad["source"]["commit"] = "stale"
        try:
            validate_definition(bad, export_spec(5))
        except ValueError as error:
            probes.append({"case": label, "rejected": True, "reason": str(error)})
        else:
            failures.append(f"Publication accepted {label}")
    resources, data = resource_paths()
    # Definitions are checked field by field above; their source metadata and
    # manifests necessarily change when advancing the current source baseline.
    expected_resources = {p: h for p, h in (baseline["resource_files"] | ui_baseline["resource_files"]).items()
                          if not p.endswith(("/definition.json", "/manifest.json"))}
    # Preserve every old logical atlas entry; source pixel checks cover repacked PNGs.
    for name in ui_baseline["definitions"]: previous_resource_digest(ROOT / f"data/{name}/atlas.json")
    changed_resources = [path for path, expected in expected_resources.items()
                         if not repacked(ROOT / path) and previous_resource_digest(ROOT / path) != expected]
    if changed_resources: failures.append(f"Unnecessary resource changes: {changed_resources}")
    result = {"passed": not failures, "content_combinations": len(combinations()), "definitions": rows,
              "failure_probes": probes, "publication_resources": len(resources), "publication_data": len(data),
              "resource_baseline": "battle_ui_baseline.json (source pixel verification in battle_ui_assets.json)",
              "verified_resource_files": len(expected_resources),
              "unchanged_resource_files": sum(previous_resource_digest(ROOT / path) == expected for path, expected in expected_resources.items() if not repacked(ROOT / path)),
              "repacked_files_source_pixel_check": "reports/battle_ui_assets.json",
              "changed_resource_files": changed_resources, "failures": failures}
    (ROOT / "reports/content_catalog.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False))
    return not failures


if __name__ == "__main__":
    raise SystemExit(0 if verify() else 1)
