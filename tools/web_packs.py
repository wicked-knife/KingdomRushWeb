"""Split a Godot 4.7.2 PCK without changing resource paths or payloads.

Identical payloads share one physical offset, including when their original
imported resource names differ. Shared packs are grouped by their consumers.
"""
from __future__ import annotations

import collections
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[1]
LIMIT = 24 * 1024 * 1024
INDEX = "data/web_packs.json"
HEADER_SIZE = 112


def digest_file(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def encoded_json(value):
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()


def aligned(value, alignment=16):
    return (value + alignment - 1) // alignment * alignment


@dataclass
class Entry:
    name: str
    offset: int
    size: int
    md5: bytes
    sha256: str
    data: bytes | None = None


def read_pack(path):
    """Reject unsupported/encrypted/patch packs instead of silently corrupting them."""
    entries = []
    with Path(path).open("rb") as stream:
        header = stream.read(40)
        if len(header) != 40:
            raise ValueError("Truncated PCK header")
        magic, version, major, minor, patch, flags, base, directory = struct.unpack("<6I2Q", header)
        if (magic, version, major, minor, patch, flags) != (0x43504447, 4, 4, 7, 2, 2):
            raise ValueError("Expected an unencrypted Godot 4.7.2 PCK v4")
        length = Path(path).stat().st_size
        if not HEADER_SIZE <= base <= directory < length:
            raise ValueError("Invalid PCK bounds")
        stream.seek(directory)
        count = struct.unpack("<I", stream.read(4))[0]
        names = set()
        for _ in range(count):
            name_size = struct.unpack("<I", stream.read(4))[0]
            if not 0 < name_size <= 16384:
                raise ValueError("Invalid PCK path size")
            name = stream.read(name_size).rstrip(b"\0").decode("utf-8")
            offset, size = struct.unpack("<QQ", stream.read(16))
            md5 = stream.read(16)
            file_flags = struct.unpack("<I", stream.read(4))[0]
            if file_flags or name in names or name.startswith("/") or ".." in name.split("/") or offset + base + size > directory:
                raise ValueError("Unsupported or invalid PCK entry: " + name)
            names.add(name)
            entries.append(Entry(name, offset + base, size, md5, ""))
        for entry in entries:
            stream.seek(entry.offset)
            sha = hashlib.sha256()
            md5 = hashlib.md5()
            remaining = entry.size
            while remaining:
                block = stream.read(min(1024 * 1024, remaining))
                if not block:
                    raise ValueError("Truncated resource: " + entry.name)
                sha.update(block)
                md5.update(block)
                remaining -= len(block)
            if md5.digest() != entry.md5:
                raise ValueError("Resource checksum mismatch: " + entry.name)
            entry.sha256 = sha.hexdigest()
    return entries


def resource_owners():
    owners = collections.defaultdict(set)

    def add(path, bundle):
        owners[path.removeprefix("res://")].add(bundle)

    def manifest(folder, bundle):
        value = json.loads((ROOT / folder / "manifest.json").read_text(encoding="utf-8"))
        for path in value["resources"] + value["data"]:
            add(path, bundle)
        add("res://" + folder + "/manifest.json", bundle)

    menu = json.loads((ROOT / "data/menu_manifest.json").read_text(encoding="utf-8"))
    for key in ("scenes", "scripts", "fonts", "textures"):
        for path in menu.get(key, []):
            add(path, "boot")
    for path in [menu["font"], menu["background"], menu["catalog"], menu["locale"], menu["sounds"], menu["font_roles"], *menu["atlases"].values(), *menu["audio"].values()]:
        add(path, "boot")
    content = json.loads((ROOT / "data/campaign_content.json").read_text(encoding="utf-8"))
    manifest("data/map_kr1", "map")
    manifest("data/heroes", "heroes")
    for key, row in content["levels"].items():
        manifest("data/" + row["folder"], "level%02d" % int(key))
    for key, row in content.get("combat_heroes", {}).items():
        manifest("data/" + row["folder"], "hero:" + key)
    # Save-slot previews need these definitions before opening the map or room.
    for path in ("data/map_kr1/definition.json", "data/heroes/definition.json"):
        owners[path] = {"boot"}
    return owners, content


def classify(source, entries):
    owners, content = resource_owners()
    imported = collections.defaultdict(set)
    with Path(source).open("rb") as stream:
        for entry in entries:
            if not entry.name.endswith(".import"):
                continue
            stream.seek(entry.offset)
            descriptor = stream.read(entry.size).decode("utf-8")
            for target in re.findall(r'res://([^"\n]+)', descriptor):
                if target.startswith(".godot/imported/"):
                    imported[target].update(owners.get(entry.name[:-7], {"boot"}))
    blobs = {}
    for entry in entries:
        original = entry.name[:-7] if entry.name.endswith(".import") else entry.name
        consumers = imported.get(entry.name, owners.get(original, {"boot"}))
        blob = blobs.setdefault((entry.size, entry.sha256), {"entries": [], "consumers": set()})
        blob["entries"].append(entry)
        blob["consumers"].update(consumers)
    groups = collections.defaultdict(list)
    for blob in blobs.values():
        consumers = blob["consumers"]
        key = ("boot",) if "boot" in consumers else tuple(sorted(consumers))
        blob["entries"].sort(key=lambda e: e.name)
        groups[key].append(blob)
    for group in groups.values():
        group.sort(key=lambda b: b["entries"][0].name)
    return groups, content


def pack_size(blobs):
    return HEADER_SIZE + sum(aligned(b["entries"][0].size) for b in blobs) + 4 + sum(
        40 + aligned(len(e.name.encode("utf-8")), 4) for b in blobs for e in b["entries"])


def write_pack(source, target, blobs):
    with Path(source).open("rb") as original, Path(target).open("wb") as stream:
        stream.write(struct.pack("<6I2Q", 0x43504447, 4, 4, 7, 2, 2, HEADER_SIZE, 0))
        stream.write(bytes(HEADER_SIZE - stream.tell()))
        directory = []
        for blob in blobs:
            representative = blob["entries"][0]
            offset = stream.tell() - HEADER_SIZE
            if representative.data is not None:
                stream.write(representative.data)
            else:
                original.seek(representative.offset)
                remaining = representative.size
                while remaining:
                    block = original.read(min(remaining, 1024 * 1024))
                    if not block:
                        raise ValueError("Unexpected end of source PCK")
                    stream.write(block)
                    remaining -= len(block)
            stream.write(bytes(aligned(stream.tell()) - stream.tell()))
            directory.extend((e, offset) for e in blob["entries"])
        directory_offset = stream.tell()
        stream.write(struct.pack("<I", len(directory)))
        for entry, offset in sorted(directory, key=lambda pair: pair[0].name):
            name = entry.name.encode("utf-8")
            padded = aligned(len(name), 4)
            stream.write(struct.pack("<I", padded) + name + bytes(padded - len(name)))
            stream.write(struct.pack("<QQ", offset, entry.size) + entry.md5 + struct.pack("<I", 0))
        stream.seek(32)
        stream.write(struct.pack("<Q", directory_offset))
    if Path(target).stat().st_size != pack_size(blobs):
        raise ValueError("PCK size calculation mismatch")


def verify_split(source, output, index):
    expected = {e.name: e.sha256 for e in read_pack(source)}
    actual = {}
    physical = {}
    for path in [output / "index.pck", *(output / row["url"] for row in index["packs"].values())]:
        for entry in read_pack(path):
            if entry.name in actual:
                raise ValueError("Resource is owned by multiple packs: " + entry.name)
            actual[entry.name] = entry.sha256
            location = (path.name, entry.offset)
            if entry.sha256 in physical and physical[entry.sha256] != location:
                raise ValueError("Resource payload was not deduplicated: " + entry.name)
            physical[entry.sha256] = location
    actual.pop(INDEX)
    if actual != expected:
        raise ValueError("Split PCK resource union differs from original")
    return {"passed": True, "resource_paths": len(expected), "unique_payloads": len(physical) - 1}


def split_export(source, output):
    source, output = Path(source), Path(output)
    output.mkdir(parents=True, exist_ok=True)
    (output / "packs").mkdir(exist_ok=True)
    entries = read_pack(source)
    groups, content = classify(source, entries)
    bundles = {"map": [], "heroes": []}
    bundles.update({"level%02d" % int(key): [] for key in content["levels"]})
    bundles.update({"hero:" + key: [] for key in content.get("combat_heroes", {})})
    index = {"schema_version": 1, "engine_version": "4.7.2", "packs": {}, "bundles": bundles}
    ids = sorted(int(key) for key in content["levels"])
    index["next_levels"] = {"level%02d" % a: "level%02d" % b for a, b in zip(ids, ids[1:])}
    for consumers, group in sorted(groups.items()):
        if consumers == ("boot",):
            continue
        shards, shard = [], []
        for blob in group:
            if pack_size([blob]) > LIMIT:
                raise ValueError("Single resource exceeds deferred pack limit: " + blob["entries"][0].name)
            if shard and pack_size(shard + [blob]) > LIMIT:
                shards.append(shard)
                shard = []
            shard.append(blob)
        if shard:
            shards.append(shard)
        for shard in shards:
            temporary = output / "packs/.writing.pck"
            write_pack(source, temporary, shard)
            sha = digest_file(temporary)
            path = output / "packs" / (sha + ".pck")
            temporary.replace(path)
            index["packs"][sha] = {"url": "packs/" + path.name, "size": path.stat().st_size, "sha256": sha}
            for consumer in consumers:
                bundles[consumer].append(sha)
    index["build_id"] = hashlib.sha256(encoded_json({e.name: e.sha256 for e in entries})).hexdigest()
    raw = encoded_json(index)
    extra = Entry(INDEX, 0, len(raw), hashlib.md5(raw).digest(), hashlib.sha256(raw).hexdigest(), raw)
    boot = [*groups[("boot",)], {"entries": [extra], "consumers": {"boot"}}]
    temporary = output / "index.pck.tmp"
    write_pack(source, temporary, boot)
    temporary.replace(output / "index.pck")
    (output / "web_packs.json").write_bytes(raw)
    # Publish only referenced packs; old local builds must not inflate the upload.
    active = {sha + ".pck" for sha in index["packs"]}
    for old in (output / "packs").glob("*.pck"):
        if re.fullmatch(r"[0-9a-f]{64}\.pck", old.name) and old.name not in active:
            old.unlink()
    verification = verify_split(source, output, index)
    sizes = {key: sum(index["packs"][sha]["size"] for sha in values) for key, values in bundles.items()}
    seen = set(bundles["map"])
    incremental = {}
    for number in ids:
        key = "level%02d" % number
        incremental[key] = sum(index["packs"][sha]["size"] for sha in set(bundles[key]) - seen)
        seen.update(bundles[key])
    total = (output / "index.pck").stat().st_size + sum(row["size"] for row in index["packs"].values())
    report = {"schema_version": 1, "passed": True, "verification": verification,
              "original_bytes": source.stat().st_size, "total_bytes": total,
              "saved_bytes": source.stat().st_size - total, "boot_bytes": (output / "index.pck").stat().st_size,
              "deferred_pack_count": len(index["packs"]), "deferred_limit_bytes": LIMIT,
              "first_download_bytes": sizes, "sequential_campaign_incremental_bytes": incremental,
              "browser_tested": False}
    (output / "pack_report.json").write_bytes(encoded_json(report))
    html = output / "index.html"
    if html.exists():
        text = html.read_text(encoding="utf-8")
        text, count = re.subn(r'("index\.pck"\s*:\s*)\d+', lambda match: match[1] + str(report["boot_bytes"]), text)
        if count != 1:
            raise ValueError("Cannot update exported HTML PCK size")
        html.write_text(text, encoding="utf-8")
    return index, report


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    options = parser.parse_args()
    _, report = split_export(options.source, options.output)
    print(json.dumps(report, indent=2))
