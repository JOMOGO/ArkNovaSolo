#!/usr/bin/env python3
"""Extract every LuaScript and XmlUI from a Tabletop Simulator save/mod JSON.

Read-only with respect to the input: the save file is never written.

Output layout (under --out, default ``src``):
    Global.lua                       Global LuaScript
    Global.xml                       Global XmlUI
    objects/<Nickname>_<GUID>.lua    per-object LuaScript
    objects/<Nickname>_<GUID>.xml    per-object XmlUI
    manifest.json                    maps every file back to its JSON location

Objects nested in ``ContainedObjects`` (bags/decks) and ``States`` (multi-state
objects) are included; their manifest entry records the full path so a later
build tool can put the text back in exactly the same place.

Text is written byte-for-byte (UTF-8, line endings untouched) so that
re-inserting it reproduces the original string.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

FIELDS = (("LuaScript", ".lua"), ("XmlUI", ".xml"))


def safe_name(nickname: str, name: str) -> str:
    base = nickname.strip() or name.strip() or "Object"
    base = re.sub(r"[^A-Za-z0-9._-]+", "_", base).strip("._") or "Object"
    return base[:60]


def walk_objects(objs, path):
    """Yield (json_path, object) for every object, depth first."""
    for i, obj in enumerate(objs or []):
        p = path + [i]
        yield p, obj
        yield from walk_objects(obj.get("ContainedObjects"), p + ["ContainedObjects"])
        states = obj.get("States")
        if isinstance(states, dict):
            for key in sorted(states, key=lambda k: int(k) if str(k).isdigit() else str(k)):
                sp = p + ["States", key]
                yield sp, states[key]
                yield from walk_objects(states[key].get("ContainedObjects"), sp + ["ContainedObjects"])


def sha(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)


def extract(save_path: Path, out: Path) -> dict:
    with open(save_path, encoding="utf-8") as f:
        save = json.load(f)

    entries = []
    for field, ext in FIELDS:
        text = save.get(field) or ""
        rel = f"Global{ext}"
        write_text(out / rel, text)
        entries.append({"file": rel, "json_path": [field], "guid": None,
                        "nickname": None, "sha256": sha(text), "chars": len(text)})

    used: set[str] = set()
    for json_path, obj in walk_objects(save.get("ObjectStates"), ["ObjectStates"]):
        guid = obj.get("GUID", "")
        stem = f"{safe_name(obj.get('Nickname', ''), obj.get('Name', ''))}_{guid or 'noguid'}"
        if stem in used:  # GUIDs are not guaranteed unique inside containers/states
            n = 2
            while f"{stem}_{n}" in used:
                n += 1
            stem = f"{stem}_{n}"
        took = False
        for field, ext in FIELDS:
            text = obj.get(field) or ""
            if not text:
                continue
            rel = f"objects/{stem}{ext}"
            write_text(out / rel, text)
            entries.append({"file": rel, "json_path": json_path + [field], "guid": guid,
                            "nickname": obj.get("Nickname", ""), "name": obj.get("Name", ""),
                            "sha256": sha(text), "chars": len(text)})
            took = True
        if took:
            used.add(stem)

    with open(save_path, "rb") as f:
        source_sha = hashlib.sha256(f.read()).hexdigest()
    manifest = {
        "source": str(save_path.as_posix()),
        "source_sha256": source_sha,
        "save_name": save.get("SaveName"),
        "tts_version": save.get("VersionNumber"),
        "has_global_script_state": bool(save.get("LuaScriptState")),
        "files": entries,
    }
    write_text(out / "manifest.json", json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    return manifest


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("save", type=Path, help="TTS save / workshop JSON")
    ap.add_argument("--out", type=Path, default=Path("src"), help="output directory (default: src)")
    args = ap.parse_args(argv)
    if args.out.exists() and any(args.out.iterdir()):
        stale = [p for p in (args.out / "objects").glob("*")] if (args.out / "objects").exists() else []
        for p in stale:  # avoid leftovers from a previous extract of a different save
            p.unlink()
    m = extract(args.save, args.out)
    n_obj = sum(1 for e in m["files"] if e["guid"] is not None)
    print(f"{m['save_name']}: Global + {n_obj} object files -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
