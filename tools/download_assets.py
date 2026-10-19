#!/usr/bin/env python3
"""Download every asset (images, models, PDFs, asset bundles) the base saves link to.

Owner request: a backup of the mods' Steam Cloud files. Not used by the build. Files go
to assets/mod_assets/<ugc id>_<hash>.<ext>; manifest.json maps each URL found in the
saves (both Steam host names) to its file. Already downloaded files are skipped.

    python tools/download_assets.py [save.json ...]   (default: mods/original/*.json)
"""
from __future__ import annotations

import http.client
import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "mod_assets"
URL_RE = re.compile(r"https?://[^\s\"']+")
UGC_RE = re.compile(r"/ugc/(\d+)/([0-9A-Fa-f]+)/?")
CDN = "https://steamusercontent-a.akamaihd.net/ugc/{}/{}/"

MAGIC = [(b"\xff\xd8\xff", ".jpg"), (b"\x89PNG", ".png"), (b"%PDF", ".pdf"),
         (b"UnityFS", ".unity3d"), (b"GIF8", ".gif"), (b"RIFF", ".webp"), (b"ID3", ".mp3")]


def fetch(url: str, tries: int = 40) -> bytes:
    """Steam's CDN often cuts large files off; resume with a Range request."""
    data = b""
    for _ in range(tries):
        headers = {"User-Agent": "Mozilla/5.0"}
        if data:
            headers["Range"] = f"bytes={len(data)}-"
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=120) as r:
                if data and r.status != 206:
                    data = b""
                data += r.read()
                return data
        except http.client.IncompleteRead as e:
            data += e.partial
        except OSError:
            pass
    raise OSError(f"incomplete after {tries} tries ({len(data)} bytes)")


def urls_in(save: Path) -> set[str]:
    found = set()

    def walk(o):
        if isinstance(o, dict):
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)
        elif isinstance(o, str) and "/ugc/" in o:
            found.update(URL_RE.findall(o))
    walk(json.loads(save.read_text(encoding="utf-8-sig")))
    return found


def extension(head: bytes) -> str:
    for magic, ext in MAGIC:
        if head.startswith(magic):
            return ext
    text = head.lstrip()[:200].lower()
    if text.startswith(b"v ") or b"\nv " in text or text.startswith(b"#") or text.startswith(b"o "):
        return ".obj"
    return ".bin"


def main(argv: list[str]) -> int:
    saves = [Path(a) for a in argv] or sorted((ROOT / "mods" / "original").glob("*.json"))
    OUT.mkdir(parents=True, exist_ok=True)
    manifest_path = OUT / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {}
    by_id: dict[tuple[str, str], list[str]] = {}
    for save in saves:
        for url in urls_in(save):
            m = UGC_RE.search(url)
            if m:
                by_id.setdefault((m.group(1), m.group(2).upper()), []).append(url)
    existing = {p.stem: p.name for p in OUT.iterdir() if p.name != "manifest.json"}
    failed = 0
    for i, ((ugc, digest), urls) in enumerate(sorted(by_id.items()), 1):
        stem = f"{ugc}_{digest}"
        name = existing.get(stem)
        if name is None:
            try:
                data = fetch(CDN.format(ugc, digest))
            except OSError as e:  # keep going; report at the end
                print(f"[{i}/{len(by_id)}] FAILED {stem}: {e}")
                failed += 1
                continue
            name = stem + extension(data[:512])
            (OUT / name).write_bytes(data)
            print(f"[{i}/{len(by_id)}] {name} ({len(data) // 1024} KB)")
        for url in urls:
            manifest[url] = name
    manifest_path.write_text(json.dumps(dict(sorted(manifest.items())), indent=1), encoding="utf-8")
    total = sum(p.stat().st_size for p in OUT.iterdir())
    print(f"{len(by_id)} files, {failed} failed, {total / 2**20:.0f} MB in {OUT}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
