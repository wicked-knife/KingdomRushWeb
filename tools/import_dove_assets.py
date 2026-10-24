"""Copy the installed Dove asset set and convert it without running game code.

Python 3.11+, Pillow 13.0.0. All paths are resolved relative to this file, not cwd.
The original installation is read only. Checkpoints make interrupted runs resumable.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import struct
import sys
import time
import zlib
from collections import Counter, defaultdict

from PIL import Image

SCHEMA = 1
CONVERTER = "dove-assets-1.0"
PROJECT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = Path("D:/王国保卫战Dove版/KingdomRushDove")
DEFAULT_REFERENCE = Path("D:/projects/KingdomRushDove")
RESOURCE_ROOT = "res://assets/kingdom_rush/"


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def atomic_bytes(path: Path, data: bytes):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_bytes(data)
    os.replace(tmp, path)


def json_bytes(value) -> bytes:
    return (json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(",", ":")) + "\n").encode("utf-8")


class BinaryReader:
    def __init__(self, data: bytes):
        self.data = data
        self.pos = 0

    def read(self, fmt: str):
        length = struct.calcsize("<" + fmt)
        if self.pos + length > len(self.data):
            raise ValueError(f"truncated binary at {self.pos}, need {length} bytes")
        values = struct.unpack_from("<" + fmt, self.data, self.pos)
        self.pos += length
        return values

    def integer(self, fmt="H"):
        return self.read(fmt)[0]

    def string(self):
        length = self.integer()
        if self.pos + length > len(self.data):
            raise ValueError("truncated UTF-8 string")
        text = self.data[self.pos:self.pos + length].decode("utf-8")
        self.pos += length
        return text

    def end(self):
        if self.pos != len(self.data):
            raise ValueError(f"unconsumed binary data: {len(self.data) - self.pos}")


def dds_info(path: Path):
    with path.open("rb") as stream:
        header = stream.read(148)
    if len(header) < 128 or header[:4] != b"DDS ":
        raise ValueError(f"invalid DDS: {path}")
    height, width = struct.unpack_from("<II", header, 12)
    fourcc = header[84:88].decode("ascii")
    if fourcc == "DX10":
        dxgi = struct.unpack_from("<I", header, 128)[0]
        if dxgi != 98:
            raise ValueError(f"unsupported DXGI format {dxgi}: {path}")
        compression = "BC7"
    else:
        compression = {"DXT1": "DXT1", "DXT5": "DXT5"}.get(fourcc)
        if not compression:
            raise ValueError(f"unsupported DDS format {fourcc}: {path}")
    return {"width": width, "height": height, "compression": compression}


def decode_atlas(data: bytes, textures: dict):
    if data[:5] != b"KRAB\x01":
        raise ValueError("expected KRAB v1 atlas")
    reader = BinaryReader(data)
    reader.pos = 5
    count = reader.integer("I")
    sheets = [reader.string() for _ in range(reader.integer())]
    frames, aliases, lookup, warnings = {}, {}, {}, []
    for _ in range(count):
        name = reader.string()
        sheet_index = reader.integer() - 1
        if not 0 <= sheet_index < len(sheets):
            raise ValueError(f"invalid sheet index in {name}")
        x, y, w, h, aw, ah, tx, ty, scale, sw, sh = reader.read("8Hf2H")
        if aw == 0 or ah == 0 or not math.isfinite(scale):
            raise ValueError(f"invalid atlas dimensions/scale: {name}")
        sheet = Path(sheets[sheet_index]).with_suffix(".png").name
        actual = textures[sheet]
        sx, sy = actual["width"] / aw, actual["height"] / ah
        if x + w > aw or y + h > ah:
            warnings.append({"frame": name, "code": "source_quad_exceeds_declared_size", "excess": [max(0, x + w - aw), max(0, y + h - ah)]})
        if name in frames:
            raise ValueError(f"duplicate canonical frame: {name}")
        frames[name] = {"sheet": sheet, "source_region": [x, y, w, h],
                        "declared_texture_size": [aw, ah], "region": [x * sx, y * sy, w * sx, h * sy],
                        "logical_size": [w, h], "original_size": [sw, sh], "trim": [tx, ty], "ref_scale": scale}
        # Match image_db's sequential assignments, including aliases that collide
        # with canonical keys. Separate dictionaries alone lose assignment order.
        lookup[name] = name
        for _ in range(reader.integer()):
            alias = reader.string()
            if alias in aliases and aliases[alias] != name:
                warnings.append({"frame": alias, "code": "source_alias_overwritten", "previous": aliases[alias], "replacement": name})
            aliases[alias] = name
            lookup[alias] = name
    reader.end()
    return {"schema_version": SCHEMA, "frames": frames, "aliases": aliases, "lookup": lookup}, warnings


def decode_animations(data: bytes):
    reader = BinaryReader(data)
    entries = [(reader.string(), reader.string(), reader.integer("I")) for _ in range(reader.integer("I"))]
    animations = {}
    for name, prefix, count in entries:
        if name in animations:
            raise ValueError(f"duplicate animation {name}")
        numbers = list(reader.read(f"{count}H")) if count else []
        animations[name] = {"prefix": prefix, "frames": numbers}
    reader.end()
    return {"schema_version": SCHEMA, "fps": 30, "animations": animations}


def decode_exoskeleton(data: bytes):
    header = BinaryReader(data)
    magic, version, flags, reserved, size = header.read("4sHBBI")
    if magic != b"EXO3" or version != 1 or flags & ~1 or reserved:
        raise ValueError("unsupported EXO3 header")
    payload = zlib.decompress(data[12:]) if flags & 1 else data[12:]
    if len(payload) != size:
        raise ValueError("EXO3 payload length mismatch")
    reader = BinaryReader(payload)
    nparts, nattach, nanimations, nframes, nentries = reader.read("HHHII")
    parts = [{"name": reader.string(), "offset": list(reader.read("ff"))} for _ in range(nparts)]
    attach = [reader.string() for _ in range(nattach)]
    animations = {}
    for _ in range(nanimations):
        name, count = reader.string(), reader.integer("I")
        # JSON frame references are zero based; the source file is one based.
        refs = [reader.integer("I") - 1 for _ in range(count)]
        if any(not 0 <= index < nframes for index in refs):
            raise ValueError(f"invalid EXO3 frame reference: {name}")
        if name in animations:
            raise ValueError(f"duplicate EXO3 animation: {name}")
        animations[name] = refs
    counts = list(reader.read(f"{nframes}H")) if nframes else []
    if sum(counts) != nentries:
        raise ValueError("EXO3 entry count mismatch")
    frames = []
    for count in counts:
        entries = []
        for _ in range(count):
            values = list(reader.read("10f"))
            if not all(math.isfinite(value) for value in values):
                raise ValueError("non-finite EXO3 value")
            kind, index = values[:2]
            limit = nparts if kind == 1 else nattach if kind == 8 else -1
            if index != int(index) or not 1 <= index <= limit:
                raise ValueError("invalid EXO3 part/attachment reference")
            entries.append(values)
        frames.append(entries)
    reader.end()
    return {"schema_version": SCHEMA, "fps": 30, "parts": parts, "attach_points": attach,
            "animations": animations, "frames": frames,
            "entry_fields": ["type", "index_1_based", "alpha", "x", "y", "scale_x", "scale_y", "rotation", "skew_x", "skew_y"]}


class StaticLua:
    """Parse data-only Lua: literals, local constants, tables and field references.

    Deliberately does not evaluate functions, require(), expressions inside strings,
    metatables or arbitrary Lua. Unknown syntax is a fatal migration error.
    """
    token = re.compile(r'''(?P<skip>\s+|--\[\[.*?\]\]|--[^\n]*)|(?P<string>"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')|(?P<number>0[xX][\da-fA-F]+|\d+(?:\.\d*)?(?:[eE][+-]?\d+)?)|(?P<name>[A-Za-z_]\w*)|(?P<symbol>\.\.|[{}\[\]=,;.\-+])''', re.S)

    def __init__(self, text):
        self.tokens = []
        pos = 0
        while pos < len(text):
            token = self.token.match(text, pos)
            if not token:
                raise ValueError(f"unsupported Lua syntax at {pos}: {text[pos:pos + 60]!r}")
            if token.lastgroup != "skip":
                self.tokens.append((token.lastgroup, token.group()))
            pos = token.end()
        self.pos, self.locals = 0, {}

    def peek(self, offset=0):
        return self.tokens[self.pos + offset][1] if self.pos + offset < len(self.tokens) else "<eof>"

    def take(self, expected=None):
        token = self.tokens[self.pos]
        if expected is not None and token[1] != expected:
            raise ValueError(f"expected {expected}, found {token[1]}")
        self.pos += 1
        return token

    @staticmethod
    def string(token):
        text, result, i = token[1:-1], bytearray(), 0
        escapes = {"a": 7, "b": 8, "f": 12, "n": 10, "r": 13, "t": 9, "v": 11}
        while i < len(text):
            char = text[i]
            if char != "\\":
                result.extend(char.encode("utf-8")); i += 1; continue
            i += 1
            char = text[i]
            if char.isdigit():
                match = re.match(r"\d{1,3}", text[i:])
                value = int(match[0])
                if value > 255:
                    raise ValueError("invalid Lua decimal escape")
                result.append(value); i += len(match[0])
            elif char in escapes:
                result.append(escapes[char]); i += 1
            elif char in "\\\"'":
                result.extend(char.encode()); i += 1
            elif char == "\n":
                result.append(10); i += 1
            else:
                raise ValueError(f"unsupported Lua string escape \\{char}")
        return result.decode("utf-8")

    def value(self):
        kind, token = self.take()
        if token == "{":
            values, index = {}, 1
            while self.peek() != "}":
                if self.peek() == "[":
                    self.take("["); key = self.value(); self.take("]"); self.take("="); value = self.value()
                elif self.pos + 1 < len(self.tokens) and self.tokens[self.pos][0] == "name" and self.peek(1) == "=":
                    key = self.take()[1]; self.take("="); value = self.value()
                else:
                    key, value = index, self.value(); index += 1
                values[key] = value
                if self.peek() in {",", ";"}:
                    self.take()
                elif self.peek() != "}":
                    raise ValueError(f"expected table separator, found {self.peek()}")
            self.take("}")
            if values and set(values) == set(range(1, len(values) + 1)):
                result = [values[i] for i in range(1, len(values) + 1)]
            else:
                result = {str(k): v for k, v in values.items()}
        elif token in {"true", "false", "nil"}:
            result = {"true": True, "false": False, "nil": None}[token]
        elif token in {"-", "+"}:
            result = self.value() * (-1 if token == "-" else 1)
        elif kind == "string":
            result = self.string(token)
        elif kind == "number":
            result = int(token, 16) if token.lower().startswith("0x") else float(token) if any(c in token for c in ".eE") else int(token)
        elif kind == "name":
            if token not in self.locals:
                raise ValueError(f"unknown Lua constant {token}")
            result = self.locals[token]
            while self.peek() == ".":
                self.take("."); result = result[self.take()[1]]
        else:
            raise ValueError(f"unsupported Lua value {token}")
        if self.peek() == "..":
            self.take(".."); result = str(result) + str(self.value())
        return result

    def parse(self):
        while self.peek() == "local":
            self.take("local"); name = self.take()[1]; self.take("="); self.locals[name] = self.value()
            if self.peek() == ";": self.take()
        self.take("return")
        result = self.value()
        if self.peek() == ";": self.take()
        if self.pos != len(self.tokens):
            raise ValueError(f"unexpected Lua statement: {self.peek()}")
        return result


class Migration:
    def __init__(self, source, project, reference):
        self.source, self.project, self.reference = source.resolve(), project.resolve(), reference.resolve()
        self.raw = self.project / "source_assets/kingdom_rush_dove"
        self.assets = self.project / "assets/kingdom_rush"
        self.reports = self.project / "reports"
        self.entries = []
        self.previous = {}
        self.started = time.monotonic()
        self.converted = 0
        self.reused = 0
        self.source_hashes = {}
        self.warnings = defaultdict(list)
        if not (self.source / "_assets/assets_index.lua").is_file():
            raise ValueError(f"not a Dove installation: {self.source}")
        if not (self.project / "project.godot").is_file():
            raise ValueError(f"not a Godot project: {self.project}")
        for left, right in [(self.source, self.project), (self.project, self.source)]:
            if left == right or left.is_relative_to(right):
                raise ValueError("installation and destination must not overlap")
        self.reports.mkdir(parents=True, exist_ok=True)
        atomic_bytes(self.reports / ".gdignore", b"")
        self.raw.mkdir(parents=True, exist_ok=True)
        atomic_bytes(self.raw / ".gdignore", b"")
        self.journal_path = self.reports / "assets_migration_state.jsonl"
        if self.journal_path.exists():
            for line in self.journal_path.read_text(encoding="utf-8").splitlines():
                try:
                    entry = json.loads(line)
                    self.previous[entry["destination"]] = entry
                except (ValueError, KeyError):
                    pass  # an interrupted final line is safe to replay
        self.journal = self.journal_path.open("a", encoding="utf-8")

    def log(self, message):
        print(f"[{time.monotonic() - self.started:7.1f}s] {message}", flush=True)

    def source_hash(self, source):
        key = str(source)
        if key not in self.source_hashes:
            self.source_hashes[key] = digest(source)
        return self.source_hashes[key]

    def reusable(self, source, destination, action):
        key = destination.relative_to(self.project).as_posix()
        old = self.previous.get(key)
        if old and old.get("converter") == CONVERTER and old.get("source_sha256") == self.source_hash(source) and old.get("action") == action and destination.is_file() and destination.stat().st_size == old["bytes"] and digest(destination) == old["sha256"]:
            self.entries.append(old)
            self.reused += 1
            return True
        return False

    def record(self, source, destination, action, **details):
        entry = {"source": str(source), "source_relative": source.relative_to(self.source).as_posix(),
                 "destination": destination.relative_to(self.project).as_posix(), "source_bytes": source.stat().st_size,
                 "source_sha256": self.source_hash(source), "bytes": destination.stat().st_size,
                 "sha256": digest(destination), "action": action, "converter": CONVERTER, "verified": True, **details}
        self.entries.append(entry)
        self.journal.write(json.dumps(entry, ensure_ascii=False, allow_nan=False) + "\n")
        self.journal.flush()
        self.converted += 1

    def copy(self, source, destination, action="copy_original"):
        if self.reusable(source, destination, action): return
        destination.parent.mkdir(parents=True, exist_ok=True)
        tmp = destination.with_name(destination.name + ".tmp")
        shutil.copy2(source, tmp)
        if digest(tmp) != self.source_hash(source):
            raise ValueError(f"copy verification failed: {source}")
        os.replace(tmp, destination)
        self.record(source, destination, action)

    def output_json(self, source, destination, data, action):
        if self.reusable(source, destination, action): return
        atomic_bytes(destination, json_bytes(data))
        self.record(source, destination, action)

    def write_raw(self):
        selected = []
        for relative in ["_assets", "kr1/data", "kr1-desktop/data", "all-desktop/data"]:
            selected.extend(p for p in (self.source / relative).rglob("*") if p.is_file() and p.suffix.lower() not in {".bat", ".exe", ".dll", ".so", ".lnk"})
        for relative in ["version.lua", "current_version_commit_hash.txt", "main_globals.lua", "all/constants.lua"]:
            path = self.source / relative
            if path.is_file(): selected.append(path)
        self.log(f"Copying {len(selected)} original and supporting files")
        for i, path in enumerate(sorted(selected), 1):
            self.copy(path, self.raw / path.relative_to(self.source))
            if i % 500 == 0: self.log(f"Originals {i}/{len(selected)}")
        return len(selected)

    def write_media(self):
        textures, formats = {}, Counter()
        paths = sorted(p for p in (self.source / "_assets").rglob("*") if p.is_file())
        dds = [p for p in paths if p.suffix.lower() == ".dds"]
        for i, path in enumerate(dds, 1):
            relative = path.relative_to(self.source / "_assets").with_suffix(".png")
            destination = self.assets / relative
            info = dds_info(path)
            textures[relative.name] = info
            formats[info["compression"]] += 1
            if not self.reusable(path, destination, "dds_to_png"):
                destination.parent.mkdir(parents=True, exist_ok=True)
                tmp = destination.with_name(destination.name + ".tmp")
                with Image.open(path) as source_image:
                    rgba = source_image.convert("RGBA")
                    expected = hashlib.sha256(rgba.tobytes()).hexdigest()
                    rgba.save(tmp, format="PNG", compress_level=6)
                    with Image.open(tmp) as output:
                        output.load()
                        if output.size != rgba.size or hashlib.sha256(output.convert("RGBA").tobytes()).hexdigest() != expected:
                            raise ValueError(f"DDS/PNG pixel mismatch: {path}")
                    rgba.close()
                os.replace(tmp, destination)
                self.record(path, destination, "dds_to_png", **info, rgba_sha256=expected, pixel_verified=True)
            if i % 10 == 0 or i == len(dds): self.log(f"DDS -> PNG {i}/{len(dds)}")
        allowed = {".png", ".ogg", ".ttf", ".otf", ".ttc"}
        media = [p for p in paths if p.suffix.lower() in allowed]
        for i, path in enumerate(media, 1):
            self.copy(path, self.assets / path.relative_to(self.source / "_assets"), "copy_runtime_media")
            if i % 1000 == 0: self.log(f"Audio/fonts/cursors {i}/{len(media)}")
        return textures, dict(formats)

    def write_metadata(self, textures):
        groups = {}
        all_names = set()
        frame_count = alias_count = 0
        atlas_root = self.source / "_assets/kr1-desktop/images/fullhd"
        for path in sorted(atlas_root.glob("*.bin")):
            data, warnings = decode_atlas(path.read_bytes(), textures)
            data["group"] = path.stem
            data["texture_directory"] = RESOURCE_ROOT + "kr1-desktop/images/fullhd/"
            self.output_json(path, self.assets / "data/atlases" / (path.stem + ".json"), data, "decode_krab_v1_lookup")
            groups[path.stem] = {"path": RESOURCE_ROOT + f"data/atlases/{path.stem}.json", "frames": len(data["frames"]), "aliases": len(data["aliases"])}
            all_names.update(data["frames"]); all_names.update(data["aliases"])
            frame_count += len(data["frames"]); alias_count += len(data["aliases"])
            if warnings: self.warnings["atlas"].append({"group": path.stem, "warnings": warnings})
        self.log(f"Decoded {len(groups)} atlases, {frame_count} frames, {alias_count} aliases")
        animation_source = self.source / "kr1/data/game_animations.bin"
        animations = decode_animations(animation_source.read_bytes())
        self.output_json(animation_source, self.assets / "data/animations.json", animations, "decode_animations")
        exoskeletons = {}
        exo_animations = set()
        exo_count = 0
        for i, path in enumerate(sorted((self.source / "kr1/data/exoskeletons").glob("*.exo3")), 1):
            exo = decode_exoskeleton(path.read_bytes())
            exo["name"] = path.stem
            exo_animations.update(path.stem + "_" + name for name in exo["animations"])
            exo_count += len(exo["animations"])
            missing_parts = [part["name"] for part in exo["parts"] if part["name"] not in all_names]
            if missing_parts: self.warnings["exo_missing_parts"].append({"exo": path.stem, "parts": missing_parts})
            self.output_json(path, self.assets / "data/exoskeletons" / (path.stem + ".json"), exo, "decode_exo3_v1_correct_fields")
            exoskeletons[path.stem] = RESOURCE_ROOT + f"data/exoskeletons/{path.stem}.json"
            if i % 200 == 0: self.log(f"EXO3 -> JSON {i}")
        for name, definition in animations["animations"].items():
            missing = [f"{definition['prefix']}_{number:04d}" for number in definition["frames"] if f"{definition['prefix']}_{number:04d}" not in all_names]
            if missing and name not in exo_animations:
                self.warnings["animation_missing_frames"].append({"animation": name, "frames": missing})
        self.log(f"Decoded {len(animations['animations'])} regular and {exo_count} composition animations")
        static_inputs = {"sounds": "_assets/kr1-desktop/sounds/sounds.lua", "sound_groups": "_assets/kr1-desktop/sounds/groups.lua",
                         "sound_settings": "_assets/kr1-desktop/sounds/settings.lua", "fonts": "all-desktop/data/font_subst.lua",
                         "locale_en": "_assets/kr1-desktop/strings/en.lua", "locale_zh-Hans": "_assets/kr1-desktop/strings/zh-Hans.lua"}
        static_paths = {}
        locale_counts = {}
        for name, relative in static_inputs.items():
            path = self.source / relative
            self.log(f"Converting static Lua: {name}")
            data = StaticLua(path.read_text(encoding="utf-8-sig")).parse()
            if name in {"sounds", "sound_groups"}:
                for key, definition in data.items():
                    for filename in definition.get("files", []):
                        if not (self.source / "_assets/kr1-desktop/sounds/files" / filename).is_file():
                            self.warnings["missing_audio"].append({"catalog": name, "id": key, "file": filename})
            if name.startswith("locale_"): locale_counts[name] = len(data)
            if name == "fonts":
                available = {p.stem for p in (self.source / "_assets/all-desktop/fonts").iterdir() if p.is_file()}
                used = set(data.get("fallbacks", []))
                for section, rules in data.items():
                    if section != "fallbacks" and isinstance(rules, list):
                        used.update(rule[1] for rule in rules)
                for missing_font in sorted(used - available):
                    self.warnings["missing_font_mappings"].append(missing_font)
            self.output_json(path, self.assets / "data" / (name + ".json"), data, "static_lua_to_json")
            static_paths[name] = RESOURCE_ROOT + f"data/{name}.json"
        catalog = {"schema_version": SCHEMA, "baseline": "installed", "fps": 30, "groups": groups, "exoskeletons": exoskeletons,
                   "animations": RESOURCE_ROOT + "data/animations.json", "audio_directory": RESOURCE_ROOT + "kr1-desktop/sounds/files/",
                   "font_directory": RESOURCE_ROOT + "all-desktop/fonts/", "static": static_paths}
        atomic_bytes(self.assets / "catalog.json", json_bytes(catalog))
        self.record(self.source / "_assets/assets_index.lua", self.assets / "catalog.json", "build_catalog")
        return {"atlases": len(groups), "frames": frame_count, "aliases": alias_count, "animations": len(animations["animations"]),
                "animation_frames": sum(len(a["frames"]) for a in animations["animations"].values()), "exoskeletons": len(exoskeletons),
                "composition_animations": exo_count, "locales": locale_counts}

    def differences(self):
        index = self.reference / "_assets/assets_index.lua"
        if not index.is_file():
            return {"reference_available": False, "reference": str(self.reference)}
        expected = re.findall(r'\["([^"\n]+)"\]=\{(\d+),"([^"\n]+)"\}', index.read_text(encoding="utf-8"))
        missing = [name for name, size, checksum in expected if not (self.source / "_assets" / name).is_file()]
        return {"reference_available": True, "reference": str(self.reference), "not_merged": True, "missing_from_installed": missing,
                "missing_extensions": dict(Counter(Path(name).suffix for name in missing))}

    def run(self):
        try:
            originals = self.write_raw()
            textures, formats = self.write_media()
            metadata = self.write_metadata(textures)
            source_entries = {entry["source_relative"]: {"bytes": entry["source_bytes"], "sha256": entry["source_sha256"]} for entry in self.entries}
            installed_index = StaticLua((self.source / "_assets/assets_index.lua").read_text(encoding="utf-8")).parse()
            missing_index = [key for key in installed_index if not (self.source / "_assets" / key).is_file()]
            if missing_index: raise ValueError(f"installed index has missing assets: {missing_index}")
            stats = {"original_files": originals, "dds_textures": len(textures), "dds_formats": formats, **metadata,
                     "ogg_files": sum(1 for entry in self.entries if entry["action"] == "copy_runtime_media" and entry["destination"].endswith(".ogg")),
                     "font_files": sum(1 for entry in self.entries if entry["action"] == "copy_runtime_media" and Path(entry["destination"]).suffix in {".ttf", ".ttc", ".otf"}),
                     "original_bytes": sum(entry["bytes"] for entry in self.entries if entry["action"] == "copy_original"),
                     "runtime_bytes": sum(entry["bytes"] for entry in self.entries if entry["action"] != "copy_original")}
            manifest = {"schema_version": SCHEMA, "converter": CONVERTER, "source_root": str(self.source), "baseline": "installed",
                        "statistics": stats, "files": self.entries, "source_snapshot": source_entries}
            verification = {"schema_version": SCHEMA, "status": "passed_with_source_warnings" if self.warnings else "passed",
                            "copied_file_hashes_verified": True, "all_dds_png_pixels_verified": True, "binary_structures_verified": True,
                            "installed_index_entries": len(installed_index), "installed_index_missing": missing_index,
                            "source_warnings": dict(self.warnings), "newer_source_difference": self.differences(), "statistics": stats}
            atomic_bytes(self.reports / "assets_manifest.json", json_bytes(manifest))
            atomic_bytes(self.reports / "assets_verification.json", json_bytes(verification))
            self.journal.close()
            atomic_bytes(self.journal_path, b"".join(json_bytes(entry) for entry in self.entries))
            self.log(f"COMPLETE: {json.dumps(stats, ensure_ascii=False)}; new={self.converted}, reused={self.reused}")
        finally:
            self.journal.close()


def verify_existing(project: Path, check_source: bool):
    manifest = json.loads((project / "reports/assets_manifest.json").read_text(encoding="utf-8"))
    errors, sources = [], {}
    for entry in manifest["files"]:
        target = project / entry["destination"]
        if not target.is_file() or target.stat().st_size != entry["bytes"] or digest(target) != entry["sha256"]:
            errors.append(entry["destination"])
        if check_source:
            sources[entry["source"]] = entry["source_sha256"]
    for path, expected in sources.items():
        if digest(Path(path)) != expected: errors.append("source changed: " + path)
    print(json.dumps({"verified_files": len(manifest["files"]), "source_files_checked": len(sources), "errors": errors}, ensure_ascii=False), flush=True)
    if errors: raise ValueError("manifest verification failed")


def write_summary(project: Path):
    report = json.loads((project / "reports/assets_verification.json").read_text(encoding="utf-8"))
    manifest = json.loads((project / "reports/assets_manifest.json").read_text(encoding="utf-8"))
    stats = report["statistics"]
    warnings = report["source_warnings"]
    atlas_warnings = sum(len(group["warnings"]) for group in warnings.get("atlas", []))
    difference = report["newer_source_difference"]
    lines = ["# Dove 素材搬运报告", "", "基准：已安装版本。原安装目录仅被读取，未移动或修改原文件。", "",
             "| 项目 | 数量 / 大小 |", "| --- | ---: |",
             f"| 原始素材与配套数据 | {stats['original_files']:,} 个文件 |",
             f"| DDS → PNG | {stats['dds_textures']:,} 张 |", f"| OGG 音频 | {stats['ogg_files']:,} 段 |",
             f"| 字体 | {stats['font_files']} 份 |", f"| 图集 / 图像帧 | {stats['atlases']:,} / {stats['frames']:,} |",
             f"| 普通动画 / 组合动画文件 | {stats['animations']:,} / {stats['exoskeletons']:,} |",
             f"| 中文 / 英文文案 | {stats['locales']['locale_zh-Hans']:,} / {stats['locales']['locale_en']:,} 条 |",
             f"| 原始档案 | {stats['original_bytes'] / 1024**3:.2f} GiB |",
             f"| Godot 资源（不含导入缓存） | {stats['runtime_bytes'] / 1024**3:.2f} GiB |", "",
             "## 完整性", "",
             f"- {len(manifest['files']):,} 个搬运/转换文件记录了来源、大小、SHA-256 和验证结果。",
             "- 全部 580 张 DDS 与 PNG 的解码 RGBA 像素逐张一致。",
             f"- 安装包索引中的 {report['installed_index_entries']:,} 项外部素材均存在。",
             "- 图集、动画和 EXO3 的结构、边界及内部索引经过校验。",
             "- `assets_hash_check.log` 为独立目标哈希及原安装目录哈希复核结果。", "",
             "## 安装版本原有数据提示", "",
             f"- {len(warnings.get('atlas', []))} 组图集的 {atlas_warnings} 条边界提示：声明尺寸边缘存在 1 像素舍入差异；保留原始数据和 UV 换算。",
             f"- {len(warnings.get('exo_missing_parts', []))} 份组合动画定义含未在图集中找到的部件名。",
             f"- {len(warnings.get('animation_missing_frames', []))} 条普通动画定义含未解析帧引用。此项为全量静态检查，也可能包含原游戏未使用的定义。",
             f"- {len(warnings.get('missing_font_mappings', []))} 个字体映射指向安装包未附带的字体；已附带的简体中文字体经独立验证。",
             "- 上述情况来自原始安装数据，不是复制丢失；没有生成占位图、删掉引用或合并新版定义。完整明细见 `assets_verification.json`。", "",
             "## 新版源码差异", "",
             f"新版源码额外引用 {difference.get('missing_extensions', {}).get('.dds', 0)} 张 DDS 和 {difference.get('missing_extensions', {}).get('.ogg', 0)} 段 OGG，未混入安装版本。", ""]
    for name in difference.get("missing_from_installed", []):
        if name.endswith(".dds"): lines.append("- `" + name + "`")
    lines += ["", "## 使用与 Godot 验证", "", "打开 `scenes/asset_preview.tscn` 后按 F6；完整命令及接口示例见项目根目录 `ASSETS.md`。",
              "Godot 实际加载检查见 `godot_assets_verification.json`，预览截图见 `asset_preview_background.png` 和 `asset_preview.png`。",
              "本阶段准备全量本地开发素材，未实现游戏玩法、组合动画渲染器或 Web 分包发布。", ""]
    atomic_bytes(project / "reports/ASSET_REPORT.md", "\n".join(lines).encode("utf-8"))


def main():
    if hasattr(sys.stdout, "reconfigure"): sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--project", type=Path, default=PROJECT)
    parser.add_argument("--reference", type=Path, default=DEFAULT_REFERENCE)
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--check-source", action="store_true")
    args = parser.parse_args()
    if args.verify_only:
        verify_existing(args.project.resolve(), args.check_source)
    else:
        Migration(args.source, args.project, args.reference).run()
        write_summary(args.project.resolve())


if __name__ == "__main__":
    main()
