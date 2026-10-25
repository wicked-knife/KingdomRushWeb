"""Small independent fixtures for format decoding and data-only Lua parsing."""
import importlib.util
from pathlib import Path
import struct
import unittest
import tempfile
import zlib

SPEC = importlib.util.spec_from_file_location("dove_importer", Path(__file__).resolve().parents[1] / "tools/import_dove_assets.py")
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


def text(value):
    data = value.encode("utf-8")
    return struct.pack("<H", len(data)) + data


class ConversionTests(unittest.TestCase):
    @staticmethod
    def vorbis_container(frames):
        # Minimal container metadata: the duration reader deliberately does not decode packets.
        identification = b"\x01vorbis" + struct.pack("<IBIiiiBB", 0, 2, 44100, 0, 0, 0, 0xB8, 1)
        def page(payload, flags, granule, sequence):
            return struct.pack("<4sBBQIIIB", b"OggS", 0, flags, granule, 7, sequence, 0, 1) + bytes([len(payload)]) + payload
        return page(identification, 2, 0, 0) + page(b"\x00", 4, frames, 1)

    def test_vorbis_duration_uses_final_granule(self):
        with tempfile.TemporaryDirectory() as directory:
            audio = Path(directory) / "audio.ogg"
            audio.write_bytes(self.vorbis_container(0))
            self.assertEqual(module.vorbis_info(audio), {"channels": 2, "sample_rate": 44100, "frames": 0})
            audio.write_bytes(self.vorbis_container(22050))
            self.assertEqual(module.vorbis_info(audio)["frames"], 22050)
            audio.write_bytes(b"OggS truncated")
            self.assertIsNone(module.vorbis_info(audio))

    def test_vorbis_truncated_identification_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            audio = Path(directory) / "audio.ogg"
            data = self.vorbis_container(0)
            identification = data.index(b"\x01vorbis")
            for length in range(7, 30):
                with self.subTest(identification_length=length):
                    audio.write_bytes(data[:identification + length])
                    self.assertIsNone(module.vorbis_info(audio))

    def test_empty_runtime_audio_is_silent_audited_and_reusable(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source"
            project = root / "project"
            (source / "_assets").mkdir(parents=True)
            (source / "_assets/assets_index.lua").write_text("return {}", encoding="utf-8")
            project.mkdir()
            (project / "project.godot").write_text("config_version=5", encoding="utf-8")
            audio = source / "_assets/empty.ogg"
            audio.write_bytes(self.vorbis_container(0))
            original_hash = module.digest(audio)
            destination = project / "assets/kingdom_rush/empty.ogg"
            migration = module.Migration(source, project, root / "reference")
            try:
                migration.copy(audio, destination, "copy_runtime_media")
                self.assertEqual(module.digest(audio), original_hash)
                self.assertEqual(migration.entries[0]["action"], module.AUDIO_SILENCE_ACTION)
                self.assertGreater(module.vorbis_info(destination)["frames"], 0)
                fixed_hash = module.digest(destination)
            finally:
                migration.journal.close()
            resumed = module.Migration(source, project, root / "reference")
            try:
                resumed.copy(audio, destination, "copy_runtime_media")
                self.assertEqual(resumed.reused, 1)
                self.assertEqual(module.digest(destination), fixed_hash)
            finally:
                resumed.journal.close()

    def test_atlas_scales_uvs_but_preserves_logical_size_and_alias(self):
        data = b"KRAB\x01" + struct.pack("<IH", 1, 1) + text("sheet.dds")
        data += text("soldier_0001") + struct.pack("<H8Hf2HH", 1, 2, 3, 4, 5, 16, 16, 1, 2, 0.5, 8, 9, 1) + text("idle")
        result, warnings = module.decode_atlas(data, {"sheet.png": {"width": 32, "height": 48}})
        frame = result["frames"]["soldier_0001"]
        self.assertEqual(frame["region"], [4, 9, 8, 15])
        self.assertEqual(frame["logical_size"], [4, 5])
        self.assertEqual(frame["original_size"], [8, 9])
        self.assertEqual(frame["trim"], [1, 2])
        self.assertEqual(result["aliases"], {"idle": "soldier_0001"})
        self.assertEqual(warnings, [])

    def test_atlas_truncation_is_rejected(self):
        with self.assertRaises(ValueError):
            module.decode_atlas(b"KRAB\x01\x01", {})

    def test_alias_collision_preserves_source_assignment_order(self):
        header = b"KRAB\x01" + struct.pack("<IH", 2, 1) + text("sheet.dds")
        def frame(name, aliases):
            return text(name) + struct.pack("<H8Hf2HH", 1, 0, 0, 4, 4, 16, 16, 0, 0, 1, 4, 4, len(aliases)) + b"".join(text(alias) for alias in aliases)
        result, _ = module.decode_atlas(header + frame("a", ["b"]) + frame("b", ["a"]), {"sheet.png": {"width": 16, "height": 16}})
        self.assertEqual(result["lookup"], {"a": "b", "b": "b"})

    def test_animation_preserves_reverse_repeated_and_zero_frame_numbers(self):
        data = struct.pack("<I", 1) + text("walk") + text("soldier") + struct.pack("<I4H", 4, 3, 2, 2, 0)
        result = module.decode_animations(data)
        self.assertEqual(result["fps"], 30)
        self.assertEqual(result["animations"]["walk"], {"prefix": "soldier", "frames": [3, 2, 2, 0]})

    def test_composition_preserves_shared_frames_and_float_values(self):
        payload = struct.pack("<HHHII", 1, 1, 1, 1, 1)
        payload += text("body") + struct.pack("<ff", 2.5, -3)
        payload += text("hand") + text("idle") + struct.pack("<I2I", 2, 1, 1)
        values = (1, 1, 0.5, 2, 3, 1, 1, 0, 0, 0)
        payload += struct.pack("<H10f", 1, *values)
        raw = struct.pack("<4sHBBI", b"EXO3", 1, 1, 0, len(payload)) + zlib.compress(payload)
        result = module.decode_exoskeleton(raw)
        self.assertEqual(result["animations"]["idle"], [0, 0])
        self.assertEqual(result["frames"], [[list(values)]])
        self.assertEqual(result["parts"][0]["offset"], [2.5, -3])
        self.assertEqual(result["entry_fields"][2:5], ["alpha", "x", "y"])
        with self.assertRaises(ValueError):
            module.decode_exoskeleton(raw[:8] + struct.pack("<I", len(payload) + 1) + raw[12:])

    def test_lua_local_tables_references_unicode_and_placeholders(self):
        result = module.StaticLua(r'''local DYN={label="伤害 %$T('tower').damage%$\n下一行"}
            return {description=DYN.label, files={"a.ogg","b.ogg"}, enabled=true, gain=-0.5, ["spaced key"]="a".."b"}''').parse()
        self.assertEqual(result["description"], "伤害 %$T('tower').damage%$\n下一行")
        self.assertEqual(result["files"], ["a.ogg", "b.ogg"])
        self.assertEqual(result["spaced key"], "ab")
        self.assertEqual(result["gain"], -0.5)

    def test_lua_never_executes_game_code(self):
        for source in ['return require("game")', 'return os.execute("bad")', 'return {callback=function() end}']:
            with self.assertRaises(ValueError):
                module.StaticLua(source).parse()


if __name__ == "__main__":
    unittest.main()
