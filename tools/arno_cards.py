#!/usr/bin/env python3
"""ARNO 3.0 action-card images for TTS, cut from reference/ARNO_3.0_Cards_EN.pdf.

The PDF has two A4-landscape pages of 4x2 cards: page 1 is side I, page 2 is side II,
mirrored per row for duplex printing. Each page is one embedded JPEG, so only Pillow is
needed (no PDF library). The 8 physical cards: Animals, Build and Cards in a green
(levels 1-3) and a red (levels 4+) version, Association and Sponsors once.

The cards go into two 4x2 sheets, like the mod's deck sheets: arno_cards_1.jpg (all
side I faces) and arno_cards_2.jpg (all side II, the same position per card), in NAMES
order. A copy is kept in assets/arno_cards/ (`python tools/arno_cards.py`; not used by
the build).

URLs for the build, in this order:
1. tools/arno_card_urls.json, if present (hosted sheets, e.g. Steam Cloud, so other
   players see them too): {"face": "...", "back": "..."};
2. otherwise the sheets are cut from the PDF into a local folder and given as file:///
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
SHEET = (4, 2)
SHEETS = ("arno_cards_1.jpg", "arno_cards_2.jpg")


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


def cut(pdf: Path, out_dir: Path) -> dict[str, Path]:
    """Write the side I and side II sheets; returns {"face": path, "back": path}."""
    from PIL import Image
    pages = [Image.open(io.BytesIO(j)).convert("RGB") for j in page_jpegs(pdf)]
    if len(pages) != 2 or any(p.size != PAGE_SIZE for p in pages):
        raise SystemExit(f"{pdf.name}: unexpected page images {[p.size for p in pages]}")
    out_dir.mkdir(parents=True, exist_ok=True)
    w, h = CARD
    sheets = [Image.new("RGB", (SHEET[0] * w, SHEET[1] * h), "white") for _ in range(2)]
    for r, row in enumerate(LAYOUT):
        for c, name in enumerate(row):
            i = NAMES.index(name)
            at = ((i % SHEET[0]) * w, (i // SHEET[0]) * h)
            for sheet, page, col in ((sheets[0], pages[0], COLS[c]), (sheets[1], pages[1], COLS[3 - c])):
                sheet.paste(page.crop((col, ROWS[r], col + w, ROWS[r] + h)), at)
    files = {}
    for side, sheet, name in zip(("face", "back"), sheets, SHEETS):
        files[side] = out_dir / name
        sheet.save(files[side], quality=92)
    return files


def card_urls(local_dir: Path) -> dict[str, str] | None:
    if HOSTED.exists():
        urls = json.loads(HOSTED.read_text(encoding="utf-8"))
        if not (urls.get("face") and urls.get("back")):
            raise SystemExit(f'{HOSTED.name}: needs "face" and "back" sheet URLs')
        return urls
    if not PDF.exists():
        print(f"note: {PDF.relative_to(ROOT)} not found; ARNO keeps the mod's action cards")
        return None
    files = cut(PDF, local_dir)
    print(f"ARNO card sheets in {local_dir}")
    # plain path after file:/// (TTS does not decode %20)
    return {k: "file:///" + p.resolve().as_posix() for k, p in files.items()}


def lua_table(urls: dict[str, str]) -> str:
    order = ", ".join(f'"{n}"' for n in NAMES)
    return (f'ARNO_CARD_IMAGES = {{ face = "{urls["face"]}", back = "{urls["back"]}",\n'
            f'  width = {SHEET[0]}, height = {SHEET[1]}, order = {{ {order} }} }}\n')


if __name__ == "__main__":
    for path in cut(PDF, ROOT / "assets" / "arno_cards").values():
        print(path)
