"""Every extracted file must equal the JSON string at its manifest path."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import tts_extract  # noqa: E402

SAVES = sorted((ROOT / "mods" / "original").glob("*.json"))


def get_path(doc, path):
    for key in path:
        doc = doc[key]
    return doc


class ExtractTest(unittest.TestCase):
    def test_files_match_json(self):
        self.assertTrue(SAVES)
        for save in SAVES:
            with self.subTest(save=save.name), tempfile.TemporaryDirectory() as tmp:
                manifest = tts_extract.extract(save, Path(tmp))
                doc = json.loads(save.read_text(encoding="utf-8"))
                files = manifest["files"]
                self.assertEqual(len({e["file"] for e in files}), len(files))
                for e in files:
                    text = (Path(tmp) / e["file"]).read_bytes().decode("utf-8")
                    self.assertEqual(text, get_path(doc, e["json_path"]) or "", e["file"])


if __name__ == "__main__":
    unittest.main()
