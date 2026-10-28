"""Verify extraction boundaries and the prepared production resources."""
import hashlib
import io
import json
from pathlib import Path
import struct
import unittest
import wave
import zipfile
import prepare_sound_effects as tool
import prepare_cursors as cursors

class PresentationAssets(unittest.TestCase):
    def test_cursor_decoder_rejects_invalid_bounds(self):
        for data in (b"", b"\0" * 22,
                     struct.pack("<3H4B2H2I", 0, 2, 1, 32, 32, 0, 0, 4, 5, 40, 999)):
            with self.assertRaises(ValueError):
                cursors.decode(data)

    def test_cursor_sources_hotspots_alpha_and_exact_conversion(self):
        manifest = json.loads((cursors.OUTPUT / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(set(manifest), {"default", "attack", "magic", "blocked", "wait", "pan"})
        for kind, record in manifest.items():
            with zipfile.ZipFile(cursors.SOURCE / record["archive"]) as archive:
                data = archive.read(record["member"])
            self.assertEqual(hashlib.sha256(data).hexdigest(), record["sha256"])
            width, height, pixels, hotspot = cursors.decode(data)
            self.assertEqual((width, height), (32, 32))
            self.assertEqual(hotspot, record["hotspot"])
            self.assertTrue(0 <= hotspot[0] < width and 0 <= hotspot[1] < height)
            self.assertEqual(set(pixels[3::4]), {0, 255})
            self.assertEqual((cursors.OUTPUT / (kind + ".png")).read_bytes(), cursors.png(width, height, pixels))

    def test_res_rejects_bad_header(self):
        for data in (b"\0" * 24, b"&YA1" + b"\0" * 20):
            with self.assertRaises(ValueError):
                tool.extract(data)

    def test_res_rejects_outside_file_range(self):
        header = struct.pack("<6I", 0x31415926, 0, 1, 1, 24, 1)
        entry = struct.pack("<IIII16s", 0, 24, 1000, 0, b"bad.wav")
        with self.assertRaises(ValueError):
            tool.extract(header + entry)

    def test_res_rejects_parent_directory(self):
        header = struct.pack("<6I", 0x31415926, 0, 1, 1, 24, 1)
        entry = struct.pack("<IIII16s", 0, 0, 1, 1, b"..")
        with self.assertRaises(ValueError):
            tool.extract(header + entry)

    def test_res_rejects_directory_cycle(self):
        header = struct.pack("<6I", 0x31415926, 0, 1, 1, 24, 1)
        entry = struct.pack("<IIII16s", 0, 0, 1, 1, b"loop")
        with self.assertRaises(ValueError):
            tool.extract(header + entry)

    def test_all_selected_wavs_decode_and_match_manifest(self):
        manifest = json.loads((tool.OUTPUT / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(len(manifest["clips"]), 183)
        self.assertEqual(manifest["footsteps"], tool.FOOTSTEPS)
        for pair in manifest["footsteps"].values():
            self.assertEqual(len(pair), 2)
            for clip in pair:
                self.assertIn(clip, manifest["clips"])
                self.assertLess(manifest["clips"][clip]["seconds"], .1)
        self.assertEqual(manifest["source_wav_count"], 555)
        self.assertEqual(len(manifest["empty_source_clips"]), 5)
        for clip, record in manifest["clips"].items():
            data = (tool.OUTPUT / clip).read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(), record["sha256"], clip)
            with wave.open(io.BytesIO(data), "rb") as reader:
                self.assertEqual((reader.getnchannels(), reader.getsampwidth(), reader.getcomptype()), (1, 2, "NONE"))
                self.assertGreater(reader.getnframes(), 0)
                raw = reader.readframes(reader.getnframes())
                self.assertEqual(len(raw), reader.getnframes() * 2)
            samples = struct.unpack("<%dh" % (len(raw) // 2), raw)
            self.assertLessEqual(max(abs(v) for v in samples), 22000)
            self.assertEqual(samples[0], 0)
            self.assertEqual(samples[-1], 0)

    def test_hd_assets_keep_recorded_sources_and_crop_bounds(self):
        directory = tool.ROOT / "godot/data/hd/icons"
        manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(len(manifest["portraits"]), 24)
        self.assertEqual(len(manifest["spells"]), 16)
        for source in manifest["sources"]:
            data = (tool.ROOT / "godot/art/concepts/hd-icons-v1" / source["file"]).read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(), source["sha256"])
            width, height = struct.unpack_from(">II", data, 16)
            x, y, w, h = source["rect"]
            self.assertTrue(0 <= x < x + w <= width and 0 <= y < y + h <= height)
            output = tool.ROOT / "godot" / source["output"].removeprefix("res://")
            data = output.read_bytes()
            self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
            width, height = struct.unpack_from(">II", data, 16)
            if output.stem.startswith("portraits-"):
                image_id = int(output.stem.split("-")[1])
                legacy = (tool.ROOT / "godot/data/legacy/images" / ("%03d.png" % image_id)).read_bytes()
                original_w, original_h = struct.unpack_from(">II", legacy, 16)
                self.assertEqual((width, height), (original_w * 8, original_h * 8))
            else:
                self.assertEqual((width, height), (256, 256))

if __name__ == "__main__":
    unittest.main()
