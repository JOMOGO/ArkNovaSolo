#!/usr/bin/env python3
"""Train the AI opponent's network from self-play (docs/AI_OPPONENT.md section 4a).

  python tools/ai_train.py play  --games 400 --seats heuristic:2,heuristic:2 --out build/ai/round0.txt
  python tools/ai_train.py train --data build/ai/round0.txt [--data ...] --out arno/ai/net_weights.lua
  python tools/ai_train.py match --games 100 --seats network:0,heuristic:0

play   runs headless games of the built mod on every core (tests/lua/selfplay.lua) and keeps
       the decision lines (D|seed|color|margin|inputs) and the end lines (E|...).
train  fits Q(inputs) = final margin - margin at the decision with a small MLP (numpy, Adam,
       ReLU, mean squared error) and writes the weights as a Lua module (ai.net_weights).
match  plays games and reports the average margin and win rate of each seat's policy.
Seats are policy:budget, policy = heuristic | network; they rotate with the seed.
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import os
import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import run_tests  # noqa: E402  (card names, MoonSharp runner)
import tts_build  # noqa: E402

BUILD = ROOT / "build" / "ai"
# input count -> features.lua version (M.SIZES there)
FEATURE_VERSIONS = {85: 1, 146: 2, 242: 3}


def lua_options(first: int, last: int, seats, mw_every: int, log: bool = True) -> str:
    def seat(p, b):
        if p in ("easy", "medium", "hard", "expert"):      # a shipped level (ai.levels)
            return f'{{ level = "{p}" }}'
        return f'{{ policy = "{p}", budget = {b} }}'
    seat_list = ", ".join(seat(p, b) for p, b in seats)
    return (f'ARNO_MODULES["tests.selfplay_options"] = function(require)\n'
            f"return {{ from = {first}, to = {last}, seats = {{ {seat_list} }}, mw_every = {mw_every}, "
            f"log = {'true' if log else 'false'} }}\nend\n")


def build_suite(weights: Path | None, weights_b: Path | None = None) -> str:
    built = tts_build.arno_global(ROOT / "src", strict=False)
    lua = ROOT / "tests" / "lua"
    stubs = (lua / "tts_stubs.lua").read_text(encoding="utf-8")
    sim = (lua / "sim_lib.lua").read_text(encoding="utf-8")
    lib = (lua / "lib.lua").read_text(encoding="utf-8")
    ai_game = (lua / "ai_game.lua").read_text(encoding="utf-8")
    body = (lua / "selfplay.lua").read_text(encoding="utf-8")
    extra = ""
    if weights is not None:
        # replaces the bundled ai.net_weights (if any) for this run
        extra = ('ARNO_MODULES["ai.net_weights"] = function(require)\n'
                 + weights.read_text(encoding="utf-8") + "\nend\n")
    return (stubs + "\n" + sim + "\n" + built + "\nsim.cnsts, sim.HexBoard = cnsts, HexBoard\n"
            + 'ARNO_MODULES["tests.lib"] = function(require)\n' + lib + "\nend\n"
            + run_tests.card_names_module()
            + 'ARNO_MODULES["tests.ai_game"] = function(require)\n' + ai_game + "\nend\n"
            + extra + ('ARNO_MODULES["ai.net_weights_b"] = function(require)\n' + weights_b.read_text(encoding="utf-8") + "\nend\n" if weights_b else "") + "@@OPTIONS@@" + "do\nlocal require = arno_require\n" + body + "\nend\n")


def run_chunk(template: str, idx: int, first: int, last: int, seats, mw_every: int, log: bool = True) -> str:
    BUILD.mkdir(parents=True, exist_ok=True)
    path = BUILD / f"selfplay_{os.getpid()}_{idx}.lua"    # own files per run: runs may overlap
    path.write_text(template.replace("@@OPTIONS@@", lua_options(first, last, seats, mw_every, log)),
                    encoding="utf-8", newline="\n")
    out = subprocess.run(["dotnet", str(run_tests.MOONRUN), str(path)], capture_output=True,
                         text=True, encoding="utf-8", errors="replace")
    lines = [l for l in out.stdout.splitlines() if l[:2] in ("D|", "E|", "X|")]
    if out.returncode != 0:
        lines.append(f"X|{first}|runner exit {out.returncode}: {out.stderr[-300:]}")
    return "\n".join(lines)


def parse_seats(text: str) -> list[tuple[str, float]]:
    seats = []
    for part in text.split(","):
        name, _, budget = part.partition(":")
        seats.append((name.strip(), float(budget or 0)))
    return seats


def play(games: int, seats, out: Path | None, weights: Path | None, first: int = 1,
         workers: int | None = None, mw_every: int = 3, log: bool = True,
         weights_b: Path | None = None) -> list[str]:
    template = build_suite(weights, weights_b)
    workers = workers or max(1, (os.cpu_count() or 2) - 2)
    # many small chunks: each runner's output stays small (memory), and the pool keeps busy
    per = max(1, min(25, (games + workers - 1) // workers))
    chunks = [(i, first + i * per, min(first + games - 1, first + (i + 1) * per - 1))
              for i in range((games + per - 1) // per)]
    lines: list[str] = []
    # each finished chunk is appended to `out` at once (a run that is stopped keeps what it
    # played; a new chat can follow the file), and `out`.done is written at the end
    if out is not None:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text("", encoding="utf-8")
        Path(str(out) + ".done").unlink(missing_ok=True)
    with cf.ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [pool.submit(run_chunk, template, i, a, b, seats, mw_every, log) for i, a, b in chunks]
        for n, f in enumerate(cf.as_completed(futures), 1):
            chunk = f.result().splitlines()
            lines.extend(chunk)
            if out is not None:
                with open(out, "a", encoding="utf-8") as fh:
                    fh.write("\n".join(chunk) + ("\n" if chunk else ""))
            print(f"  chunk {n}/{len(chunks)} done", flush=True)
    if out is not None:
        Path(str(out) + ".done").write_text(f"{games} games\n", encoding="utf-8")
    errors = [l for l in lines if l.startswith("X|")]
    for e in errors[:5]:
        print("  game failed:", e[:300])
    if errors:
        BUILD.mkdir(parents=True, exist_ok=True)
        with open(BUILD / "failures.txt", "a", encoding="utf-8") as f:
            for e in errors:
                f.write(e.replace(" / ", "\n    ") + "\n")
        print(f"  (full logs in {BUILD / 'failures.txt'})")
    print(f"played {games} games: {sum(1 for l in lines if l.startswith('D|'))} decisions, "
          f"{len(errors)} failed")
    return lines


def seat_specs(seats, seed: int, n: int) -> dict[str, tuple[str, float]]:
    colors = ["Red", "Blue", "Yellow", "White"]
    return {colors[i]: seats[(i + seed) % len(seats)] for i in range(n)}


def report(lines: list[str], seats) -> None:
    ends: dict[int, dict[str, int]] = {}
    for l in lines:
        if l.startswith("E|"):
            _, seed, color, margin, *_ = l.split("|")
            ends.setdefault(int(seed), {})[color] = int(margin)
    stats: dict[str, list[int]] = {}
    for seed, by_color in ends.items():
        for color, (name, budget) in seat_specs(seats, seed, len(by_color)).items():
            stats.setdefault(f"{name}:{budget:g}", []).append(by_color[color])
    for key, margins in sorted(stats.items()):
        m = np.array(margins)
        print(f"  {key:14s} games {len(m):4d}  average margin {m.mean():+6.1f}  "
              f"win {100 * np.mean(m > 0):5.1f}%")


def load(paths: list[Path], horizon: int = 0, target: str = "margin") -> tuple[np.ndarray, np.ndarray]:
    """Inputs and targets. Target: the player's margin (target "margin") or own score
    (target "score") `horizon` of its own decisions later (or at the end of the game) minus
    the same at the decision; horizon 0 = at the end. A short horizon ties a choice to what
    it caused, with far less noise; the own score leaves out what the others do meanwhile."""
    finals: dict[tuple[int, str], tuple[int, int]] = {}
    by_seat: dict[tuple[int, str], list[tuple[int, int, str]]] = {}
    for path in paths:
        for l in path.read_text(encoding="utf-8").splitlines():
            if l.startswith("E|"):
                parts = l.split("|")
                score = int(parts[5]) if len(parts) > 5 else 0
                finals[(int(parts[1]), parts[2])] = (int(parts[3]), score)
            elif l.startswith("D|"):
                parts = l.split("|")
                score = int(parts[5]) if len(parts) > 5 else 0
                by_seat.setdefault((int(parts[1]), parts[2]), []).append((int(parts[3]), score, parts[4]))
    k = 0 if target == "margin" else 1
    xs, ys = [], []
    for key, seq in by_seat.items():
        final = finals.get(key)
        if final is None:
            continue
        for i, entry in enumerate(seq):
            later = final[k] if horizon <= 0 or i + horizon >= len(seq) else seq[i + horizon][k]
            xs.append(np.array([float(v) for v in entry[2].split(",")], dtype=np.float32))
            ys.append(later - entry[k])
    return np.stack(xs), np.array(ys, dtype=np.float32)


def train(x: np.ndarray, y: np.ndarray, hidden=(64, 64), epochs=12, lr=1e-3, batch=512, seed=1):
    rng = np.random.default_rng(seed)
    mean, std = x.mean(0), x.std(0)
    std[std < 1e-6] = 1.0
    xn = (x - mean) / std
    sizes = [x.shape[1], *hidden, 1]
    params = []
    for a, b in zip(sizes[:-1], sizes[1:]):
        params.append([rng.normal(0, np.sqrt(2.0 / a), (a, b)).astype(np.float32), np.zeros(b, np.float32)])
    m = [[np.zeros_like(w), np.zeros_like(b)] for w, b in params]
    v = [[np.zeros_like(w), np.zeros_like(b)] for w, b in params]
    t = 0
    idx = np.arange(len(xn))
    val = idx[: len(idx) // 10]
    tr = idx[len(idx) // 10:]
    yscale = max(1.0, float(np.abs(y).mean()))
    best, best_mse, best_epoch = None, float("inf"), 0
    for epoch in range(epochs):
        rng.shuffle(tr)
        for start in range(0, len(tr), batch):
            bi = tr[start:start + batch]
            acts = [xn[bi]]
            for li, (w, b) in enumerate(params):
                z = acts[-1] @ w + b
                acts.append(np.maximum(z, 0) if li < len(params) - 1 else z)
            grad = 2 * (acts[-1][:, 0] - y[bi] / yscale)[:, None] / len(bi)
            t += 1
            for li in range(len(params) - 1, -1, -1):
                w, b = params[li]
                gw, gb = acts[li].T @ grad, grad.sum(0)
                if li > 0:
                    grad = (grad @ w.T) * (acts[li] > 0)
                for k, g in ((0, gw), (1, gb)):
                    m[li][k] = 0.9 * m[li][k] + 0.1 * g
                    v[li][k] = 0.999 * v[li][k] + 0.001 * g * g
                    mh, vh = m[li][k] / (1 - 0.9 ** t), v[li][k] / (1 - 0.999 ** t)
                    params[li][k] -= lr * mh / (np.sqrt(vh) + 1e-8)
        pred = predict(params, xn[val]) * yscale
        mse = float(np.mean((pred - y[val]) ** 2))
        base = float(np.mean((y[val] - y[tr].mean()) ** 2))
        print(f"  epoch {epoch + 1:2d}: validation error {mse:7.1f} (predicting the mean: {base:7.1f})")
        if mse < best_mse:       # early stop: keep the epoch that predicts held-out games best
            best, best_mse, best_epoch = [[w.copy(), b.copy()] for w, b in params], mse, epoch + 1
    params = best
    print(f"  kept epoch {best_epoch} (validation error {best_mse:.1f})")
    # fold the output scale into the last layer
    params[-1][0] = params[-1][0] * yscale
    params[-1][1] = params[-1][1] * yscale
    return params, mean, std


def predict(params, xn):
    a = xn
    for li, (w, b) in enumerate(params):
        a = a @ w + b
        if li < len(params) - 1:
            a = np.maximum(a, 0)
    return a[:, 0]


def lua_list(values) -> str:
    return "{" + ",".join(f"{float(v):.5g}" for v in values) + "}"


def export(params, mean, std, out: Path, note: str) -> None:
    layers = []
    for w, b in params:
        n_in, n_out = w.shape
        # row-major by output: w[(j - 1) * n_in + i]
        layers.append(f"    {{ n_in = {n_in}, n_out = {n_out}, b = {lua_list(b)},\n"
                      f"      w = {lua_list(w.T.reshape(-1))} }}")
    text = ("-- AI opponent network weights (docs/AI_OPPONENT.md section 4a).\n"
            "-- GENERATED by tools/ai_train.py; do not edit. " + note + "\n"
            f"return {{\n  version = 1,\n  inputs = {len(mean)},\n"
            f"  features = {FEATURE_VERSIONS.get(len(mean), 1)},\n"
            f"  mean = {lua_list(mean)},\n  std = {lua_list(std)},\n  layers = {{\n"
            + ",\n".join(layers) + "\n  },\n}\n")
    out.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {out} ({sum(w.size + b.size for w, b in params)} weights)")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("play")
    p.add_argument("--games", type=int, default=100)
    p.add_argument("--first", type=int, default=1)
    p.add_argument("--seats", default="heuristic:2,heuristic:2")
    p.add_argument("--weights", type=Path)
    p.add_argument("--out", type=Path)
    p.add_argument("--workers", type=int)
    t = sub.add_parser("train")
    t.add_argument("--data", type=Path, action="append", required=True)
    t.add_argument("--out", type=Path, default=ROOT / "arno" / "ai" / "net_weights.lua")
    t.add_argument("--hidden", default="64,64")
    t.add_argument("--epochs", type=int, default=12)
    t.add_argument("--lr", type=float, default=1e-3)
    t.add_argument("--horizon", type=int, default=0,
                   help="target = margin this many own decisions later (0: final margin)")
    t.add_argument("--target", choices=("margin", "score"), default="margin")
    m = sub.add_parser("match")
    m.add_argument("--games", type=int, default=100)
    m.add_argument("--first", type=int, default=100001)
    m.add_argument("--seats", default="network:0,heuristic:0")
    m.add_argument("--weights", type=Path)
    m.add_argument("--weights-b", type=Path, help="the network of network_b seats (new against current)")
    m.add_argument("--workers", type=int)
    args = ap.parse_args(argv)

    if args.cmd in ("play", "match"):
        seats = parse_seats(args.seats)
        lines = play(args.games, seats, getattr(args, "out", None), args.weights, args.first, args.workers,
                     log=args.cmd == "play", weights_b=getattr(args, "weights_b", None))
        report(lines, seats)
    elif args.cmd == "train":
        x, y = load(args.data, args.horizon, args.target)
        print(f"{len(y)} decisions, {x.shape[1]} inputs, target mean {y.mean():+.1f} sd {y.std():.1f}")
        hidden = tuple(int(h) for h in args.hidden.split(","))
        params, mean, std = train(x, y, hidden=hidden, epochs=args.epochs, lr=args.lr)
        export(params, mean, std, args.out, f"{len(y)} decisions from {', '.join(p.name for p in args.data)}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
