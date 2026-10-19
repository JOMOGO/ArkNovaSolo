#!/usr/bin/env python3
"""ARNO 3.0 action-card images for TTS, cut from reference/ARNO_3.0_Cards_EN.pdf.

The PDF has two A4-landscape pages of 4x2 cards: page 1 is side I, page 2 is side II,
mirrored per row for duplex printing. Each page is one embedded JPEG, so only Pillow is
needed (no PDF library). The 8 physical cards: Animals, Build and Cards in a green
(levels 1-3) and a red (levels 4+) version, Association and Sponsors once.

URLs for the build, in this order:
1. tools/arno_card_urls.json, if present (hosted images, e.g. Steam Cloud, so other
   players see them too): {"animals_g": {"face": "...", "back": "..."}, ...};
2. otherwise the images are cut from the PDF into a local folder and given as file:///
   URLs (only this PC can load them);
3. otherwise (no PDF): None, and ARNO keeps the mod's own action cards.
"""
from __future__ import annotations

import io
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PDF = ROOT / "reference" / "ARNO_3.0_Cards_EN.pdf"
HOSTED = ROOT / "tools" / "arno_card_urls.json"

PAGE_SIZE = (3505, 2478)
COLS = (175, 978, 1782, 2585)
ROWS = (170, 1269)
CARD = (745, 1039)
# side-I page layout; side II is the same per row, mirrored
LAYOUT = (("animals_g", "animals_r", "association", "build_g"),
          ("sponsors", "cards_g", "cards_r", "build_r"))
NAMES = tuple(n for row in LAYOUT for n in row)


def page_jpegs(pdf: Path) -> list[bytes]:
    """The raw DCTDecode image streams, in file order."""
    data = pdf.read_bytes()
    out = []
    for m in re.finditer(rb"/Filter\s*/DCTDecode", data):
        start = data.rfind(b"<<\n/HSamples", 0, m.start())
        head = data[start if start >= 0 else m.start() - 2000:m.end() + 400]
        length = int(re.search(rb"/Length (\d+)", head).group(1))
        s = data.index(b"stream", m.end())
        s += len(b"stream")
        while data[s:s + 1] in (b"\r", b"\n"):
            s += 1
        out.append(data[s:s + length])
    return out


def cut(pdf: Path, out_dir: Path) -> dict[str, dict[str, Path]]:
    from PIL import Image
    pages = [Image.open(io.BytesIO(j)).convert("RGB") for j in page_jpegs(pdf)]
    if len(pages) != 2 or any(p.size != PAGE_SIZE for p in pages):
        raise SystemExit(f"{pdf.name}: unexpected page images {[p.size for p in pages]}")
    out_dir.mkdir(parents=True, exist_ok=True)
    files = {}
    w, h = CARD
    for r, row in enumerate(LAYOUT):
        for c, name in enumerate(row):
            sides = {}
            for side, page, col in (("face", pages[0], COLS[c]), ("back", pages[1], COLS[3 - c])):
                path = out_dir / f"arno_{name}_{'1' if side == 'face' else '2'}.jpg"
                page.crop((col, ROWS[r], col + w, ROWS[r] + h)).save(path, quality=92)
                sides[side] = path
            files[name] = sides
    return files


def card_urls(local_dir: Path) -> dict[str, dict[str, str]] | None:
    if HOSTED.exists():
        urls = json.loads(HOSTED.read_text(encoding="utf-8"))
        missing = [n for n in NAMES if n not in urls]
        if missing:
            raise SystemExit(f"{HOSTED.name}: missing {missing}")
        return urls
    if not PDF.exists():
        print(f"note: {PDF.relative_to(ROOT)} not found; ARNO keeps the mod's action cards")
        return None
    files = cut(PDF, local_dir)
    print(f"ARNO card images in {local_dir}")
    # plain path after file:/// (TTS does not decode %20)
    return {n: {k: "file:///" + p.resolve().as_posix() for k, p in sides.items()}
            for n, sides in files.items()}


def lua_table(urls: dict[str, dict[str, str]]) -> str:
    rows = [f'  {n} = {{ face = "{urls[n]["face"]}", back = "{urls[n]["back"]}" }},' for n in NAMES]
    return "ARNO_CARD_IMAGES = {\n" + "\n".join(rows) + "\n}\n"
