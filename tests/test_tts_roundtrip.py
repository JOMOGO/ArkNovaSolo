"""extract -> build with no changes must reproduce the save (semantically and byte-for-byte)."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import tts_build  # noqa: E402
import tts_extract  # noqa: E402

SAVES = sorted((ROOT / "mods" / "original").glob("*.json"))


class RoundTripTest(unittest.TestCase):
    def test_unchanged_build_is_identical(self):
        self.assertTrue(SAVES)
        for save in SAVES:
            with self.subTest(save=save.name), tempfile.TemporaryDirectory() as tmp:
                tts_extract.extract(save, Path(tmp))
                rebuilt = tts_build.build(save, Path(tmp))
                original = save.read_bytes()
                self.assertEqual(json.loads(rebuilt), json.loads(original), "semantic difference")
                self.assertEqual(rebuilt, original, "byte difference")

    def test_edit_lands_at_manifest_path(self):
        save = ROOT / "mods" / "original" / "3812420704.json"
        with tempfile.TemporaryDirectory() as tmp:
            tts_extract.extract(save, Path(tmp))
            rebuilt = json.loads(tts_build.build(save, Path(tmp),
                                                 overrides={"Global.lua": "-- marker\n"},
                                                 save_name="X"))
            original = json.loads(save.read_bytes())
            self.assertEqual(rebuilt["LuaScript"], "-- marker\n")
            self.assertEqual(rebuilt["SaveName"], "X")
            rebuilt["LuaScript"], rebuilt["SaveName"] = original["LuaScript"], original["SaveName"]
            self.assertEqual(rebuilt, original)

    def test_rejects_mismatched_base(self):
        a, b = SAVES[0], SAVES[1]
        with tempfile.TemporaryDirectory() as tmp:
            tts_extract.extract(a, Path(tmp))
            with self.assertRaises(SystemExit):
                tts_build.build(b, Path(tmp))


if __name__ == "__main__":
    unittest.main()
