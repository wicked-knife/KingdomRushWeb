"""Packaging contracts: byte preservation, aliases, limits and deterministic output."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import web_packs as packs


def memory_blob(paths, data):
    return {"entries": [packs.Entry(name, 0, len(data), hashlib.md5(data).digest(), hashlib.sha256(data).hexdigest(), data) for name in paths], "consumers": set()}


class PackContracts(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.raw = self.root / "empty"
        self.raw.touch()

    def tearDown(self):
        self.temporary.cleanup()

    def test_alias_offsets_and_checksum_failure(self):
        output = self.root / "test.pck"
        packs.write_pack(self.raw, output, [memory_blob(["a.txt", "b.txt"], b"same payload")])
        entries = packs.read_pack(output)
        self.assertEqual(entries[0].offset, entries[1].offset)
        with output.open("r+b") as stream:
            stream.seek(entries[0].offset)
            stream.write(b"X")
        with self.assertRaisesRegex(ValueError, "checksum"):
            packs.read_pack(output)

    def test_split_union_shared_ownership_limits_and_determinism(self):
        source = self.root / "source.pck"
        packs.write_pack(self.raw, source, [memory_blob(["boot.txt"], b"bootstrap"),
            memory_blob(["one.txt"], b"shared" * 40), memory_blob(["two.txt"], b"shared" * 40),
            memory_blob(["private.txt"], b"private" * 28), memory_blob(["extra.txt"], b"extra" * 35)])
        owners = {"boot.txt": {"boot"}, "one.txt": {"level01"}, "two.txt": {"level02"},
                  "private.txt": {"level01"}, "extra.txt": {"level01"}}
        content = {"levels": {"1": {}, "2": {}}, "combat_heroes": {}}
        with patch.object(packs, "resource_owners", return_value=(owners, content)), patch.object(packs, "LIMIT", 480):
            index, report = packs.split_export(source, self.root / "first")
            second, _ = packs.split_export(source, self.root / "second")
        self.assertEqual(index, second)
        self.assertTrue(report["verification"]["passed"])
        self.assertEqual(len(index["bundles"]["level02"]), 1)
        self.assertGreater(len(index["bundles"]["level01"]), 1)
        self.assertTrue(set(index["bundles"]["level02"]) <= set(index["bundles"]["level01"]))
        for row in index["packs"].values(): self.assertLessEqual(row["size"], 480)
        with (self.root / "first/index.pck").open("rb") as stream:
            entry = next(e for e in packs.read_pack(self.root / "first/index.pck") if e.name == packs.INDEX)
            stream.seek(entry.offset)
            self.assertEqual(json.loads(stream.read(entry.size)), index)

    def test_rejects_unsupported_pck(self):
        output = self.root / "test.pck"
        packs.write_pack(self.raw, output, [memory_blob(["a"], b"payload")])
        with output.open("r+b") as stream:
            stream.seek(20)
            stream.write((3).to_bytes(4, "little"))
        with self.assertRaisesRegex(ValueError, "unencrypted"):
            packs.read_pack(output)


if __name__ == "__main__": unittest.main()
