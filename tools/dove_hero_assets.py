"""Read resource declarations from the pinned hero registry, without game bootstrap."""
import re
from pathlib import Path


def declarations(source):
    source = Path(source)
    registry = source / "kr1/heroes/registry.lua"
    text = registry.read_text(encoding="utf-8")
    block = re.search(r"HEROES\.module_names\s*=\s*\{(.*?)\}", text, re.S)
    assert block, "Hero registry module list missing"
    rows = []
    for module in re.findall(r'"(heroes\.[^"]+)"', block[1]):
        path = source / "kr1" / module.replace(".", "/") / "init.lua"
        text = path.read_text(encoding="utf-8")
        fields = {}
        for field in ("animations", "sounds", "groups"):
            match = re.search(r"\b" + field + r"\s*=\s*\{([^{}]*)\}", text)
            fields[field] = re.findall(r'"([^"]+)"', match[1]) if match else []
        rows.append((path, fields))
    assert rows and len({str(p) for p, _ in rows}) == len(rows)
    return registry, rows


def resource_inputs(source):
    registry, rows = declarations(source)
    paths = [registry]
    for declaration, fields in rows:
        paths.append(declaration)
        for field, modules in fields.items():
            for module in modules:
                paths.append(Path(source) / "kr1" / (module.replace(".", "/") + (".bin" if field == "animations" else ".lua")))
    return paths


def animations(source):
    from import_dove_assets import decode_animations
    source = Path(source)
    base = source / "kr1/data/game_animations.bin"
    data = decode_animations(base.read_bytes())
    registry, rows = declarations(source)
    inputs = [base, registry]
    for declaration, fields in rows:
        inputs.append(declaration)
        for module in fields["animations"]:
            path = source / "kr1" / (module.replace(".", "/") + ".bin")
            for name, animation in decode_animations(path.read_bytes())["animations"].items():
                assert name not in data["animations"] or data["animations"][name] == animation, f"Conflicting animation: {name} ({path})"
                data["animations"][name] = animation
            inputs.append(path)
    return data, inputs
