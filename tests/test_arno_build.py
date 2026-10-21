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
        self.assertIn('[471] = {type="animal", size=3, cost=22, icons={"reptile", "africa"}, enclosure={repthouse=2},', built["LuaScript"])
        self.assertEqual(built["SaveName"], tts_build.ARNO_SAVE_NAME)
        built["LuaScript"], built["SaveName"] = original["LuaScript"], original["SaveName"]
        self.assertEqual(built, original)

    def test_converted_wrappers_are_in_the_built_script(self):
        lua = tts_build.arno_global(ROOT / "src", ROOT / "hooks" / "hooks.json")
        # H19: action panel flush right, 22 px taller, undo hint inside its layout
        self.assertNotIn('offsetXY="-60 0"', lua)
        self.assertIn('<Panel id="actionSelectionPanel_%s" visibility="%s" rectAlignment="MiddleRight" offsetXY="0 0" ', lua)
        self.assertIn("local height = 392 + separator_height", lua)
        self.assertIn("press the rewind arrow twice.</Text>\n      </VerticalLayout>", lua)
        # H21: no red Cancel left in the mod's panels; the red Pass buttons are all still there
        self.assertNotIn('color="#C61715" textColor="#FFFFFF">Cancel</Button>', lua)
        self.assertNotIn('"Cancel", "#C61715"', lua)
        self.assertNotIn(r"Go back to\nbuilding selection", lua)
        self.assertIn(r'local go_back_label = "Back to\nbuilding selection"', lua)
        base = (ROOT / "src" / "Global.lua").read_text(encoding="utf-8")
        red_pass = 'color="#C61715" textColor="#FFFFFF">Pass</Button>'
        self.assertEqual(lua.count(red_pass), base.count(red_pass))
        # H6, H16: nil-safe deck removal, human hands only
        self.assertIn("if deck ~= nil then deck.destruct() end", lua)
        self.assertIn("ipairs((ARNO and ARNO.setup.humans(players)) or players)", lua)

    def test_hook_anchor_must_match_once(self):
        with self.assertRaises(SystemExit):
            tts_build.apply_hooks("no anchors here", ROOT / "hooks" / "hooks.json")


if __name__ == "__main__":
    unittest.main()
