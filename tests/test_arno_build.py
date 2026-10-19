"""The ARNO build changes only the Global script and SaveName, and every hook anchor matches."""
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import tts_build  # noqa: E402

BASE = ROOT / "mods" / "original" / "3812420704.json"


class ArnoBuildTest(unittest.TestCase):
    def test_only_global_and_name_change(self):
        lua = tts_build.arno_global(ROOT / "src", ROOT / "hooks" / "hooks.json")
        built = json.loads(tts_build.build(BASE, ROOT / "src", overrides={"Global.lua": lua},
                                           save_name=tts_build.ARNO_SAVE_NAME))
        original = json.loads(BASE.read_bytes())
        self.assertIn("-- BEGIN ARNO BUNDLE", built["LuaScript"])
        self.assertIn("ARNO.setup.add_bots(players)", built["LuaScript"])
        self.assertEqual(built["SaveName"], tts_build.ARNO_SAVE_NAME)
        built["LuaScript"], built["SaveName"] = original["LuaScript"], original["SaveName"]
        self.assertEqual(built, original)

    def test_hook_anchor_must_match_once(self):
        with self.assertRaises(SystemExit):
            tts_build.apply_hooks("no anchors here", ROOT / "hooks" / "hooks.json")


if __name__ == "__main__":
    unittest.main()
