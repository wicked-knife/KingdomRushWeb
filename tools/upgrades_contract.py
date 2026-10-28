"""Explicit reachable additions made by the default technology adapters."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def technology_contracts(data):
    contracts = {name: [] for name in data["techs"]}
    def need(tech, owners, children):
        contracts[tech] += [{"owner": owner, "template": child} for owner in owners for child in children]
    need("archer_precision", data["groups"]["archer_towers"], ["pop_crit"])
    need("archer_el_bloodletting_shoot", data["groups"]["arrows"], ["mod_blood_elves"])
    need("mage_arcane_shatter", data["groups"]["bolts"], ["mod_arcane_shatter", "mod_arcane_shatter_little"])
    need("mage_slow_curse", data["groups"]["bolts"], ["mod_slow_curse"])
    need("rain_scorched_earth", ["power_fireball"], ["power_scorched_earth", "power_scorched_water"])
    for name, tech in data["techs"].items():
        if name.startswith("reinforcement_level_") and "template_name" in tech:
            need(name, ["power_reinforcements_control"], [tech["template_name"]])
    return contracts


def validate_technology_dependencies(definition):
    tech = json.loads((ROOT / "data/upgrades/definition.json").read_text(encoding="utf-8"))
    if definition["source"]["commit"] != tech["source"]["commit"]:
        raise ValueError("technology source differs from current Dove catalog")
    if len(tech["techs"]) != 36 or set(tech["dependencies"]) != set(tech["techs"]):
        raise ValueError("technology registry is incomplete")
    templates = definition["templates"]
    def visit(name, chain, visited):
        if name in visited: return
        visited.add(name)
        if name not in templates: raise ValueError(f"{chain} -> missing template {name}")
        for child in definition.get("dependencies", {}).get(name, []): visit(child, f"{chain} -> {name}", visited)
    for name, rows in tech["dependencies"].items():
        for row in rows:
            if row["owner"] in templates: visit(row["template"], f"technology {name} -> {row['owner']}", set())


def validate_technology_resources(definition, animations, atlas, sounds):
    """Walk each technology's live roots, preserving the technology/owner chain."""
    tech = json.loads((ROOT / "data/upgrades/definition.json").read_text(encoding="utf-8"))
    templates = definition["templates"]
    def check_animation(key, technology, owner):
        if key not in animations: raise ValueError(f"technology {technology} -> {owner} -> missing animation {key}")
        animation = animations[key]
        for number in animation["frames"]:
            frame = f"{animation['prefix']}_{int(number):04d}"
            if frame not in atlas["lookup"]: raise ValueError(f"technology {technology} -> {owner} -> {key} -> missing frame {frame}")
    def visit(name, technology, visited):
        if name in visited: return
        visited.add(name)
        if name not in templates: raise ValueError(f"technology {technology} -> missing template {name}")
        template = templates[name]
        if name == "spear_legionnaire" and template["bullet"]["miss_decal"] not in atlas["lookup"]:
            raise ValueError(f"technology {technology} -> {name} -> missing frame {template['bullet']['miss_decal']}")
        for sound in template.get("sound_events", {}).values():
            for value in sound if isinstance(sound, list) else [sound]:
                if isinstance(value, str) and value and value not in sounds:
                    raise ValueError(f"technology {technology} -> {name} -> missing sound {value}")
        variants = [f"{name}_{v}" for v in range(1, 4)] if "reinforcement" in template else []
        for prefix in variants:
            states = ["idle", "running", "attack", "death"]
            if "ranged" in template: states.append("ranged_attack")
            for state in states:
                key = f"{prefix}_{state}"
                check_animation(key, technology, name)
        for child in definition.get("dependencies", {}).get(name, []): visit(child, technology, visited)
        for sprite in template.get("render", {}).get("sprites", []):
            key = sprite.get("name", "")
            prefix = sprite.get("prefix", "")
            if prefix: key = prefix + "_" + key
            if sprite.get("use_blood_color"):
                for target in templates.values():
                    unit = target.get("unit", {})
                    if unit.get("blood_color"):
                        size = "small" if unit["size"] == 1 else "big"
                        check_animation(f"{prefix}_{size}_{unit['blood_color']}", technology, name)
            if key in animations:
                check_animation(key, technology, name)
                animation = animations[key]
                frames = [f"{animation['prefix']}_{int(frame):04d}" for frame in animation["frames"]]
            else: frames = [] if variants else [key]
            for frame in frames:
                if frame and frame not in atlas["lookup"]:
                    raise ValueError(f"technology {technology} -> {name} -> missing frame {frame}")
    for name, rows in tech["dependencies"].items():
        for row in rows:
            if row["owner"] in templates: visit(row["template"], name, set())
