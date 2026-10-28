"""Shared published-content catalog; gameplay rules still come from frozen Dove files."""
from pathlib import Path
import copy
import json

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "data/campaign_content.json"
REFERENCE_FIELDS = {"bullet", "mod", "hit_fx", "hit_decal", "hit_blood_fx", "soldier_type", "entity"}


def template_dependencies(value):
    found = set()
    def visit(node):
        if isinstance(node, dict):
            for key, child in node.items():
                if key in REFERENCE_FIELDS and isinstance(child, str) and child: found.add(child)
                visit(child)
        elif isinstance(node, list):
            for child in node: visit(child)
    visit(value)
    return sorted(found)


def read_catalog():
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    if catalog.get("schema_version") != 1:
        raise ValueError("Unsupported campaign content catalog")
    for key, entry in {**catalog["levels"], **catalog["arenas"]}.items():
        if (key in catalog["levels"] and int(key) != entry["id"]) or not entry["modes"] or not entry["difficulties"]:
            raise ValueError(f"Invalid campaign registration: {key}")
        if entry["difficulties"] != [2]:
            raise ValueError(f"{key}: current source adapter supports difficulty 2 only")
        for feature in entry["features"]:
            if feature not in catalog["features"]:
                raise ValueError(f"Unknown content feature: {key}/{feature}")
        if entry["controller"] not in catalog["controllers"]:
            raise ValueError(f"Unknown level controller: {key}/{entry['controller']}")
    return catalog


def level_ids():
    return sorted(int(key) for key in read_catalog()["levels"])


def combinations():
    return [{"level": row["id"], "mode": mode, "difficulty": difficulty}
            for row in sorted(read_catalog()["levels"].values(), key=lambda row: row["id"])
            for mode in row["modes"] for difficulty in row["difficulties"]]


def export_spec(level_id=1, ranger_arena=False):
    catalog = read_catalog()
    entry = copy.deepcopy(catalog["arenas"]["ranger_arena"] if ranger_arena else catalog["levels"][str(level_id)])
    merged = {}
    for feature in entry["features"]:
        for key, values in catalog["features"][feature].items():
            target = merged.setdefault(key, [])
            for value in values:
                if value not in target:
                    target.append(value)
    entry["export"] = merged
    entry["source"] = catalog["source"]
    return entry


def resolve_behavior(source_id, catalog=None):
    catalog = catalog or read_catalog()
    canonical = catalog["behavior_aliases"].get(source_id, source_id)
    if canonical not in catalog["behaviors"]:
        raise ValueError(f"Unsupported Dove behavior: {source_id}")
    return catalog["behaviors"][canonical]


def validate_definition(data, spec):
    """Check reachable references, including all modes, before publishing a definition."""
    templates = data["templates"]
    identity = spec["folder"]
    catalog = read_catalog()
    if data.get("level", {}).get("controller") != spec["controller"]:
        raise ValueError(f"{identity}: controller differs from content registration")
    for mode in spec["modes"]:
        if mode != 1 and not str(mode) in data.get("modes", {}):
            raise ValueError(f"{identity}: missing registered mode {mode}")
    for name, source_id in data.get("behaviors", {}).items():
        try:
            resolve_behavior(source_id, catalog)
        except ValueError as error:
            raise ValueError(f"{identity}: {name} -> {source_id}: {error}") from error
    for name, template in templates.items():
        active_tower = "tower" in template and not template.get("tower", {}).get("type", "").startswith("holder")
        if active_tower or any(key in template for key in ("enemy", "soldier", "bullet", "modifier", "aura", "spawner", "fireball_count")):
            source_id = data.get("behaviors", {}).get(name)
            if not source_id:
                raise ValueError(f"{identity}: missing behavior binding for {name}")
            try:
                resolve_behavior(source_id, catalog)
            except ValueError as error:
                raise ValueError(f"{identity}: {name} -> {source_id}: {error}") from error
            if "bullet" in template:
                actual = template.get("behavior", "")
                canonical = lambda value: catalog["behavior_aliases"].get(value, value)
                if canonical(actual) != canonical(source_id):
                    raise ValueError(f"{identity}: {name} -> projectile behavior {actual} differs from {source_id}")
    layouts = [data["layout"], *(row["layout"] for row in data.get("modes", {}).values())]
    waves = [data["waves"], *(row["waves"] for row in data.get("modes", {}).values())]
    for layout in layouts:
        for entity in layout["entities_list"]:
            if "tower.holder_id" in entity and entity["template"] not in templates:
                raise ValueError(f"{identity}: layout -> missing template {entity['template']}")
    for program in waves:
        for group in program["groups"]:
            for wave in group["waves"]:
                if not 1 <= wave["path_index"] <= len(data["paths"]["paths"]):
                    raise ValueError(f"Invalid wave path: {wave['path_index']}")
                for spawn in wave["spawns"]:
                    for key in ("creep", "creep_aux"):
                        if spawn.get(key) and spawn[key] not in templates:
                            raise ValueError(f"{identity}: wave/{key} -> missing template {spawn[key]}")
    # Explicitly supported reference fields; extending the exporter must extend
    # this list when a new behavior introduces another kind of child entity.
    for name, template in templates.items():
        for child in template_dependencies(template):
            if child not in templates:
                raise ValueError(f"{identity}: missing template dependency: {name} -> {child}")
    if data["level"]["id"] != spec["id"]:
        raise ValueError("Exported identity differs from content registration")
