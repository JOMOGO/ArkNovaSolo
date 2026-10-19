#!/usr/bin/env python3
"""Rebuild a Tabletop Simulator save from a base save plus extracted script files.

The inverse of ``tts_extract.py``: every file listed in ``<src>/manifest.json`` is
written back to its recorded JSON path in the base save, and the result goes to --out.
The base save is only read.

Serialisation mimics TTS (2-space indent, CRLF, non-ASCII kept, each float written
with its original text), so an unchanged extract rebuilds byte-identically.

With --arno, Global.lua additionally gets the anchored edits from hooks/hooks.json and
the bundled arno/ modules (inserted before the mod's on_* interaction wrapper), and the
result is compile-checked under MoonSharp. See docs/DESIGN.md §3-4.
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


ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ANCHOR = "\nlocal handler_names = {}\n"
ARNO_SAVE_NAME = "Ark Nova - Complete Scripted + ARNO 3.0"
# Owner preference: every ARNO build is also copied to the TTS Saves folder.
# Override with ARNO_TTS_SAVES; disable with --no-install.
DEFAULT_TTS_SAVES = Path.home() / "Documents" / "My Games" / "Tabletop Simulator" / "Saves"


def install_to_saves(built: Path, saves_dir: Path) -> Path | None:
    """Copy the build into the TTS Saves folder (only our own file name is written)."""
    if not saves_dir.is_dir():
        print(f"note: TTS Saves folder not found ({saves_dir}); not installed")
        return None
    target = saves_dir / built.name
    target.write_bytes(built.read_bytes())
    print(f"installed {target}")
    return target


def apply_hooks(text: str, hooks_file: Path) -> tuple[str, list[str]]:
    """Apply anchored edits; each `find` must occur exactly once."""
    spec = json.loads(hooks_file.read_text(encoding="utf-8"))
    applied = []
    for hook in spec["hooks"]:
        count = text.count(hook["find"])
        if count != 1:
            raise SystemExit(f"hook {hook['id']}: anchor found {count} times (expected 1); "
                             "the base mod changed - update hooks/hooks.json")
        text = text.replace(hook["find"], hook["replace"])
        applied.append(hook["id"])
    return text, applied


def arno_global(src: Path, hooks_file: Path) -> str:
    """Base Global.lua + hooks + ARNO bundle."""
    sys.path.insert(0, str(ROOT / "tools"))
    import lua_bundle
    with open(src / "Global.lua", encoding="utf-8", newline="") as f:
        text = f.read()
    text, _ = apply_hooks(text, hooks_file)
    if text.count(BUNDLE_ANCHOR) != 1:
        raise SystemExit("bundle anchor (local handler_names = {}) not found exactly once")
    bundle = lua_bundle.bundle(packages=("core", "adapter", "ui", "main"),
                               epilogue='ARNO = arno_require("main")\nARNO.install()\n')
    return text.replace(BUNDLE_ANCHOR, "\n" + bundle + BUNDLE_ANCHOR, 1)


def compile_check(lua_text: str) -> None:
    moonrun = ROOT / "tools" / "moonsharp" / "bin" / "out" / "moonrun.dll"
    if not moonrun.exists():
        print("note: MoonSharp runner not built; skipping compile check (python tools/run_tests.py builds it)")
        return
    out = ROOT / "build" / "Global.arno.lua"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(lua_text, encoding="utf-8", newline="")
    import subprocess
    if subprocess.call(["dotnet", str(moonrun), "--compile-only", str(out)]) != 0:
        raise SystemExit("generated Global.lua does not compile under MoonSharp")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("base", type=Path, help="base save JSON (the one src/ was extracted from)")
    ap.add_argument("--src", type=Path, default=Path("src"), help="extracted script dir (default: src)")
    ap.add_argument("--out", type=Path, required=True, help="output save JSON")
    ap.add_argument("--save-name", help="override SaveName")
    ap.add_argument("--arno", action="store_true", help="add ARNO (hooks + bundle) to Global.lua")
    ap.add_argument("--hooks", type=Path, default=ROOT / "hooks" / "hooks.json")
    ap.add_argument("--no-install", action="store_true",
                    help="with --arno: do not copy the result to the TTS Saves folder")
    args = ap.parse_args(argv)
    if args.out.resolve() == args.base.resolve():
        raise SystemExit("refusing to overwrite the base save")
    overrides, save_name = {}, args.save_name
    if args.arno:
        overrides["Global.lua"] = arno_global(args.src, args.hooks)
        compile_check(overrides["Global.lua"])
        save_name = save_name or ARNO_SAVE_NAME
    data = build(args.base, args.src, overrides=overrides, save_name=save_name)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(data)
    print(f"wrote {args.out} ({len(data)} bytes)")
    if args.arno and not args.no_install:
        import os
        install_to_saves(args.out, Path(os.environ.get("ARNO_TTS_SAVES", DEFAULT_TTS_SAVES)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
