#!/usr/bin/env python3
"""Rebuild a Tabletop Simulator save from a base save plus extracted script files.

The inverse of ``tts_extract.py``: every file listed in ``<src>/manifest.json`` is
written back to its recorded JSON path in the base save, and the result goes to --out.
The base save is only read.

Serialisation mimics TTS (2-space indent, CRLF, non-ASCII kept, each float written
with its original text), so an unchanged extract rebuilds byte-identically.

Later phases add ARNO bundling and hooks on top of this; see docs/DESIGN.md.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

_FLOAT_TAG = "\x00F:"
_FLOAT_RE = re.compile(r'"\\u0000F:([^"]*)"')


def load_save(path: Path):
    """Parse a save, keeping each float's source text so it can be written back verbatim."""
    text = path.read_bytes().decode("utf-8-sig")
    return json.loads(text, parse_float=lambda s: _FLOAT_TAG + s)


def dump_save(doc, newline: str = "\r\n") -> bytes:
    text = json.dumps(doc, indent=2, ensure_ascii=False)
    text = _FLOAT_RE.sub(lambda m: m.group(1), text)
    return text.replace("\n", newline).encode("utf-8")


def set_path(doc, path, value) -> None:
    for key in path[:-1]:
        doc = doc[key]
    doc[path[-1]] = value


def build(base: Path, src: Path, overrides: dict[str, str] | None = None,
          save_name: str | None = None) -> bytes:
    """Return the rebuilt save bytes. ``overrides`` maps manifest file -> replacement text."""
    manifest = json.loads((src / "manifest.json").read_text(encoding="utf-8"))
    base_sha = hashlib.sha256(base.read_bytes()).hexdigest()
    if base_sha != manifest["source_sha256"]:
        raise SystemExit(f"base save {base} does not match the save {src} was extracted from "
                         f"({base_sha[:12]} != {manifest['source_sha256'][:12]}); re-extract first")
    raw = base.read_bytes()
    newline = "\r\n" if b"\r\n" in raw[:4096] else "\n"
    doc = load_save(base)
    overrides = overrides or {}
    for entry in manifest["files"]:
        rel = entry["file"]
        if rel in overrides:
            text = overrides[rel]
        else:
            with open(src / rel, encoding="utf-8", newline="") as f:
                text = f.read()
        set_path(doc, entry["json_path"], text)
    if save_name:
        doc["SaveName"] = save_name
    return dump_save(doc, newline)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("base", type=Path, help="base save JSON (the one src/ was extracted from)")
    ap.add_argument("--src", type=Path, default=Path("src"), help="extracted script dir (default: src)")
    ap.add_argument("--out", type=Path, required=True, help="output save JSON")
    ap.add_argument("--save-name", help="override SaveName")
    args = ap.parse_args(argv)
    if args.out.resolve() == args.base.resolve():
        raise SystemExit("refusing to overwrite the base save")
    data = build(args.base, args.src, save_name=args.save_name)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(data)
    print(f"wrote {args.out} ({len(data)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
