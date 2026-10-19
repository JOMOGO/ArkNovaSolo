#!/usr/bin/env python3
"""Run every test suite of this repo.

  1. Python tool tests (extract / build round trip / hooks)        tests/test_*.py
  2. the helper app's own unit tests (vitest, original TS)          --skip-node to skip
  3. the differential reference: original TS with seeded RNG        -> build/harness/ts_reference.json
  4. generated data is current (arno/core/cards_data.lua)
  5. Lua tests under MoonSharp (TTS's interpreter)                  tests/lua/test_*.lua

Node >= 20.19 is required for 2 and 3. It is taken from $ARNO_NODE, else from PATH, else
from the newest nvs install (%LOCALAPPDATA%/nvs/node/<version>/x64).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import lua_bundle  # noqa: E402

HELPER = ROOT / "vendor" / "ark-nova-solo-helper"
BUILD = ROOT / "build"
MOONRUN_DIR = ROOT / "tools" / "moonsharp"
MOONRUN = MOONRUN_DIR / "bin" / "out" / "moonrun.dll"
REF_JSON = BUILD / "harness" / "ts_reference.json"


def run(cmd, **kw) -> int:
    print("$", " ".join(str(c) for c in cmd), flush=True)
    return subprocess.call([str(c) for c in cmd], **kw)


def node_version(exe: str) -> tuple[int, ...] | None:
    try:
        out = subprocess.check_output([exe, "--version"], text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        return None
    m = re.match(r"v(\d+)\.(\d+)\.(\d+)", out)
    return tuple(int(x) for x in m.groups()) if m else None


def find_node() -> Path | None:
    candidates = []
    if os.environ.get("ARNO_NODE"):
        candidates.append(os.environ["ARNO_NODE"])
    if shutil.which("node"):
        candidates.append(shutil.which("node"))
    nvs = Path(os.environ.get("LOCALAPPDATA", "")) / "nvs" / "node"
    if nvs.is_dir():
        for d in sorted(nvs.iterdir(), key=lambda p: [int(x) for x in re.findall(r"\d+", p.name)], reverse=True):
            for exe in (d / "x64" / "node.exe", d / "node.exe"):
                if exe.exists():
                    candidates.append(str(exe))
    for exe in candidates:
        v = node_version(exe)
        if v and (v >= (22, 12, 0) or (v[0] == 20 and v >= (20, 19, 0))):
            return Path(exe)
    return None


def node_env(node: Path) -> dict:
    env = dict(os.environ)
    env["PATH"] = str(node.parent) + os.pathsep + env.get("PATH", "")
    return env


def ensure_harness_node_modules() -> None:
    link = ROOT / "tests" / "harness" / "node_modules"
    if not link.exists():
        target = HELPER / "node_modules"
        if os.name == "nt":
            subprocess.check_call(["cmd", "/c", "mklink", "/J", str(link), str(target)],
                                  stdout=subprocess.DEVNULL)
        else:
            link.symlink_to(target, target_is_directory=True)


def to_lua(v, indent: int = 0) -> str:
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, list):
        return "{" + ",".join(to_lua(x) for x in v) + "}"
    if isinstance(v, dict):
        items = []
        for k, x in v.items():
            if x is None:
                continue
            key = k if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", k) else "[" + json.dumps(k) + "]"
            items.append(f"{key}={to_lua(x)}")
        return "{" + ",".join(items) + "}"
    raise TypeError(type(v))


def lua_suite(test_file: Path, ref: dict | None) -> str:
    lib = (ROOT / "tests" / "lua" / "lib.lua").read_text(encoding="utf-8")
    extra = f'ARNO_MODULES["tests.lib"] = function(require)\n{lib}\nend\n'
    if ref is not None:
        # one constructor per top-level key keeps each function's constant table small
        parts = [f'R[{json.dumps(k)}] = (function() return {to_lua(v)} end)()' for k, v in ref.items()]
        extra += 'ARNO_MODULES["tests.ref"] = function(require)\nlocal R = {}\n' + "\n".join(parts) + "\nreturn R\nend\n"
    body = test_file.read_text(encoding="utf-8")
    return (lua_bundle.bundle(epilogue=extra)
            + "do\nlocal require = arno_require\n" + body + "\nend\n")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--skip-node", action="store_true", help="skip helper tests and reference regeneration")
    ap.add_argument("-k", help="only Lua tests whose file name contains this")
    args = ap.parse_args(argv)
    failures = []

    if run([sys.executable, "-I", "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py"], cwd=ROOT):
        failures.append("python")

    if not args.skip_node:
        node = find_node()
        if node is None:
            print("Node >= 20.19 not found (set ARNO_NODE)")
            failures.append("node")
        else:
            env = node_env(node)
            vitest = HELPER / "node_modules" / ".bin" / ("vitest.cmd" if os.name == "nt" else "vitest")
            if run([vitest, "run"], cwd=HELPER, env=env, shell=os.name == "nt"):
                failures.append("helper vitest")
            ensure_harness_node_modules()
            if run([vitest, "run", "--config", ROOT / "tests" / "harness" / "vitest.config.mjs"],
                   cwd=ROOT, env=env, shell=os.name == "nt"):
                failures.append("reference harness")

    if run([sys.executable, "-I", ROOT / "tools" / "gen_cards_data.py", "--check"]):
        failures.append("generated data")

    if not MOONRUN.exists():
        if run(["dotnet", "build", "-c", "Release", "-o", MOONRUN.parent], cwd=MOONRUN_DIR):
            failures.append("moonrun build")
            print("FAILED:", ", ".join(failures))
            return 1
    ref = json.loads(REF_JSON.read_text(encoding="utf-8")) if REF_JSON.exists() else None
    out_dir = BUILD / "lua"
    out_dir.mkdir(parents=True, exist_ok=True)
    for test_file in sorted((ROOT / "tests" / "lua").glob("test_*.lua")):
        if args.k and args.k not in test_file.name:
            continue
        needs_ref = "tests.ref" in test_file.read_text(encoding="utf-8")
        if needs_ref and ref is None:
            print(f"skip {test_file.name}: no {REF_JSON} (run without --skip-node once)")
            failures.append(test_file.name)
            continue
        suite = out_dir / test_file.name
        suite.write_text(lua_suite(test_file, ref if needs_ref else None), encoding="utf-8", newline="\n")
        if run(["dotnet", MOONRUN, suite]):
            failures.append(test_file.name)

    # integration tests: the BUILT Global.lua (mod + hooks + ARNO bundle) executed headless
    import tts_build
    built = tts_build.arno_global(ROOT / "src", ROOT / "hooks" / "hooks.json")
    stubs = (ROOT / "tests" / "lua" / "tts_stubs.lua").read_text(encoding="utf-8")
    sim = (ROOT / "tests" / "lua" / "sim_lib.lua").read_text(encoding="utf-8")
    lib = (ROOT / "tests" / "lua" / "lib.lua").read_text(encoding="utf-8")
    for test_file in sorted((ROOT / "tests" / "lua").glob("int_*.lua")):
        if args.k and args.k not in test_file.name:
            continue
        body = test_file.read_text(encoding="utf-8")
        suite = out_dir / test_file.name
        suite.write_text(stubs + "\n" + sim + "\n" + built + "\nsim.cnsts = cnsts\n"
                         + 'ARNO_MODULES["tests.lib"] = function(require)\n' + lib + "\nend\n"
                         + "do\nlocal require = arno_require\n" + body + "\nend\n",
                         encoding="utf-8", newline="\n")
        if run(["dotnet", MOONRUN, suite]):
            failures.append(test_file.name)

    print("FAILED: " + ", ".join(failures) if failures else "ALL TESTS PASSED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
