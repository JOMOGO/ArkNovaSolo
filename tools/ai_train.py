#!/usr/bin/env python3
"""Train the AI opponent's network from self-play (docs/AI_OPPONENT.md section 4a).

  python tools/ai_train.py play  --games 400 --seats heuristic:2,heuristic:2 --out build/ai/round0.txt
  python tools/ai_train.py train --data build/ai/round0.txt [--data ...] --out arno/ai/net_weights.lua
  python tools/ai_train.py match --games 100 --seats network:0,heuristic:0

play   runs headless games of the built mod on every core (tests/lua/selfplay.lua) and keeps
       the decision lines (D|seed|color|margin|inputs) and the end lines (E|...).
train  fits Q(inputs) = final margin - margin at the decision with a small MLP (numpy, Adam,
       ReLU, mean squared error) and writes the weights as a Lua module (ai.net_weights).
       train --cards adds card-identity inputs (a one-hot of the card the move is about).
match  plays games and reports the average margin and win rate of each seat's policy.
search values the top candidates of sampled decisions by replaying the game from its seed
       (tests/lua/search.lua; S lines, docs/AI_OPPONENT.md §10); train --search uses them.
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
# (state, choice) inputs per version, as features.lua M.SIZES; a later version only appends
# to both blocks, so an earlier version's inputs are a column subset of a later one's
FEATURE_SIZES = {1: (39, 46), 2: (97, 49), 3: (193, 49)}
# card-identity inputs (train --cards): a one-hot of the number of the card a choice is about
# (1..N_CARDS; 0 = none, all zeros), after the base inputs; never standardised (mean 0, std 1)
N_CARDS = 560


def project(row: np.ndarray, version: int) -> np.ndarray:
    """The inputs of `version` taken out of a row logged with the same or a later version."""
    s_from, _ = FEATURE_SIZES[FEATURE_VERSIONS[len(row)]]
    s_to, c_to = FEATURE_SIZES[version]
    return np.concatenate([row[:s_to], row[s_from:s_from + c_to]])


def lua_options(first: int, last: int, seats, mw_every: int, log: bool = True,
                extra: dict | None = None, module: str = "tests.selfplay_options") -> str:
    def seat(p, b):
        if p in ("easy", "medium", "hard", "expert"):      # a shipped level (ai.levels)
            return f'{{ level = "{p}" }}'
        if p == "arno":                                    # ARNO 3.0 at this level (1-10)
            return f'{{ arno = {int(b)} }}'
        return f'{{ policy = "{p}", budget = {b} }}'
    def lua(v):
        if isinstance(v, bool):
            return "true" if v else "false"
        if isinstance(v, str):
            return f'"{v}"'
        return f"{v:g}" if isinstance(v, float) else str(v)
    seat_list = ", ".join(seat(p, b) for p, b in seats)
    more = "".join(f", {k} = {lua(v)}" for k, v in (extra or {}).items() if v is not None)
    return (f'ARNO_MODULES["{module}"] = function(require)\n'
            f"return {{ from = {first}, to = {last}, seats = {{ {seat_list} }}, mw_every = {mw_every}, "
            f"log = {'true' if log else 'false'}{more} }}\nend\n")


def build_suite(weights: Path | None, weights_b: Path | None = None, runner: str = "selfplay.lua") -> str:
    built = tts_build.arno_global(ROOT / "src", strict=False)
    lua = ROOT / "tests" / "lua"
    stubs = (lua / "tts_stubs.lua").read_text(encoding="utf-8")
    sim = (lua / "sim_lib.lua").read_text(encoding="utf-8")
    lib = (lua / "lib.lua").read_text(encoding="utf-8")
    ai_game = (lua / "ai_game.lua").read_text(encoding="utf-8")
    body = (lua / runner).read_text(encoding="utf-8")
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


def run_chunk(template: str, idx: int, first: int, last: int, seats, mw_every: int, log: bool = True,
              search: dict | None = None, extra: dict | None = None) -> str:
    """search: the options of tests/lua/search.lua (the template is then that runner)."""
    BUILD.mkdir(parents=True, exist_ok=True)
    kind = "search" if search is not None else "selfplay"
    path = BUILD / f"{kind}_{os.getpid()}_{idx}.lua"    # own files per run: runs may overlap
    options = (lua_options(first, last, seats, mw_every, log, search, "tests.search_options")
               if search is not None else lua_options(first, last, seats, mw_every, log, extra))
    path.write_text(template.replace("@@OPTIONS@@", options), encoding="utf-8", newline="\n")
    out = subprocess.run(["dotnet", str(run_tests.MOONRUN), str(path)], capture_output=True,
                         text=True, encoding="utf-8", errors="replace")
    keep = ("S|", "V|", "T|", "C|", "E|", "X|") if search is not None else ("D|", "E|", "X|")
    lines = [l for l in out.stdout.splitlines() if l[:2] in keep]
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
         weights_b: Path | None = None, search: dict | None = None,
         assist: dict | None = None) -> list[str]:
    template = build_suite(weights, weights_b, "search.lua" if search is not None else "selfplay.lua")
    workers = workers or max(1, (os.cpu_count() or 2) - 2)
    # many small chunks: each runner's output stays small (memory), and the pool keeps busy
    # (a searched game takes minutes: one game per chunk)
    per = 1 if search is not None else max(1, min(25, (games + workers - 1) // workers))
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
        futures = [pool.submit(run_chunk, template, i, a, b, seats, mw_every, log, search, assist)
                   for i, a, b in chunks]
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
    if search is not None:
        search_report(lines)
    else:
        print(f"played {games} games: {sum(1 for l in lines if l.startswith('D|'))} decisions, "
              f"{len(errors)} failed")
    return lines


def search_report(lines: list[str]) -> None:
    """Points searched, time per point, how often search's best differs from the base choice,
    the value gap best - base and the noise of a candidate's value (sd / sqrt(samples))."""
    points: dict[tuple, list[tuple[float, float, int]]] = {}
    times = []
    checks = [l for l in lines if l.startswith("C|")]
    for l in lines:
        parts = l.split("|")
        if l.startswith("S|"):
            points.setdefault((parts[1], parts[2], parts[3]), []).append(
                (float(parts[5]), float(parts[6]), int(parts[7])))
        elif l.startswith("T|"):
            times.append((float(parts[4]), int(parts[5])))
    errors = sum(1 for l in lines if l.startswith("X|"))
    bad = [c for c in checks if c.split("|")[2] != "ok"]
    if checks:
        print(f"determinism check: {len(checks) - len(bad)} of {len(checks)} games replay exactly")
        for c in bad[:5]:
            print("  ", c)
    if not points or not times:
        print(f"searched {len(points)} points, {errors} failed")
        return
    differs, gaps, noise, spread, pairs = 0, [], [], [], []
    for cands in points.values():
        best = max(cands, key=lambda c: c[0])
        base = [c for c in cands if c[2] == 1]
        if base:
            differs += best[2] == 0
            gaps.append(best[0] - base[0][0])
        values = [c[0] for c in cands]
        spread.append(max(values) - min(values))
        pairs.extend(abs(a - b) for i, a in enumerate(values) for b in values[i + 1:])
        noise.extend(c[1] for c in cands)
    secs = np.array([t for t, _ in times])
    rollouts = float(np.mean([r for _, r in times]))
    labels = sum(len(c) for c in points.values())
    samples = max(1, round(rollouts / np.mean([len(c) for c in points.values()])))
    sd = float(np.sqrt(np.mean(np.square(noise))))        # pooled over the candidates
    print(f"searched {len(points)} points ({labels} labels), {errors} failed; "
          f"{secs.mean():.1f} s per point on one worker ({rollouts:.1f} rollouts), "
          f"{3600 * labels / secs.sum():.0f} labels per hour per worker")
    print(f"  search's best is not the base choice at {100 * differs / max(1, len(gaps)):.0f}% of the points; "
          f"gap best - base: mean {np.mean(gaps):+.2f}, median {np.median(gaps):+.2f}")
    print(f"  between two candidates of a point: median gap {np.median(pairs):.2f}; best - worst mean "
          f"{np.mean(spread):.2f}; sample sd (pooled) {sd:.2f}, noise of a value (sd / sqrt({samples})) "
          f"{sd / np.sqrt(samples):.2f}")
    # V lines (every sample's value): the noise of a difference of two candidates (the samples
    # share their random streams and deck) and a split-half check: the best on the odd samples,
    # measured against the base choice on the even ones (an unbiased gap)
    per: dict[tuple, dict[int, tuple[list[float], int]]] = {}
    base_rank = {}
    for l in lines:
        parts = l.split("|")
        if l.startswith("V|"):
            per.setdefault((parts[1], parts[2], parts[3]), {})[int(parts[4])] = [float(v) for v in parts[5].split(",")]
        elif l.startswith("S|") and parts[7] == "1":
            base_rank[(parts[1], parts[2], parts[3])] = int(parts[4])
    one, diff, agree, held, held_n = [], [], 0, [], 0
    for key, cands in per.items():
        m = min(len(v) for v in cands.values())
        if m < 2:
            continue
        vals = np.array([v[:m] for _, v in sorted(cands.items())])
        ranks = sorted(cands)
        one.extend(np.var(vals, axis=1, ddof=1))
        for i in range(len(vals)):
            for j in range(i + 1, len(vals)):
                diff.append(np.var(vals[i] - vals[j], ddof=1))
        if m >= 4 and key in base_rank:
            a, b = vals[:, 0::2].mean(1), vals[:, 1::2].mean(1)
            agree += int(np.argmax(a) == np.argmax(b))
            held.append(b[int(np.argmax(a))] - b[ranks.index(base_rank[key])])
            held_n += 1
    if one:
        s1, sd_ = float(np.sqrt(np.mean(one))), float(np.sqrt(np.mean(diff))) if diff else 0.0
        print(f"  per sample: sd of a value {s1:.2f}, sd of a difference of two candidates {sd_:.2f} "
              f"(noise of a mean of m samples: {s1:.2f} / sqrt(m))")
    if held_n:
        print(f"  split half ({held_n} points): the best candidate on the odd samples is also best on the even "
              f"ones at {100 * agree / held_n:.0f}%; its gap to the base choice there (unbiased) "
              f"mean {np.mean(held):+.2f}, median {np.median(held):+.2f}")


def seat_specs(seats, seed: int, n: int) -> dict[str, tuple[str, float]]:
    colors = ["Red", "Blue", "Yellow", "White"]
    if any(name == "arno" for name, _ in seats):   # against ARNO the seats stay: a player starts
        return {colors[i]: seats[i] for i in range(n)}
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


def load(paths: list[Path], horizon: int = 0, target: str = "margin",
         inputs: int | None = None, final_weight: float = 0.0):
    """Inputs, targets, games, the row `horizon` on (-1: none) and the card number of every
    row (0: none). Target: the player's margin (target "margin") or own score
    (target "score") `horizon` of its own decisions later (or at the end of the game) minus
    the same at the decision; horizon 0 = at the end. A short horizon ties a choice to what
    it caused, with far less noise; the own score leaves out what the others do meanwhile."""
    finals: dict[tuple[int, str], tuple[int, int]] = {}
    by_seat: dict[tuple[int, str], list[tuple[int, int, np.ndarray, int]]] = {}
    for path in paths:
        with path.open(encoding="utf-8") as f:        # streamed: the text is never all held
            for l in f:
                if l.startswith("E|"):
                    parts = l.rstrip(chr(10)).split("|")
                    score = int(parts[5]) if len(parts) > 5 else 0
                    finals[(int(parts[1]), parts[2])] = (int(parts[3]), score)
                elif l.startswith("D|"):
                    parts = l.rstrip(chr(10)).split("|")
                    score = int(parts[5]) if len(parts) > 5 else 0
                    row = np.array(parts[4].split(","), dtype=np.float32)
                    if len(row) not in FEATURE_VERSIONS:
                        continue        # a line cut short (a file still being written)
                    if inputs:
                        row = project(row, inputs)
                    # field 7: the card the chosen move is about (from round 7 on; else 0)
                    card = int(parts[6]) if len(parts) > 6 and parts[6].strip().isdigit() else 0
                    by_seat.setdefault((int(parts[1]), parts[2]), []).append(
                        (int(parts[3]), score, row, card if card <= N_CARDS else 0))
    k = 0 if target == "margin" else 1
    xs, ys, games, nxt, cards = [], [], [], [], []
    for key, seq in by_seat.items():
        final = finals.get(key)
        if final is None:
            continue
        start = len(xs)
        for i, entry in enumerate(seq):
            ahead = horizon > 0 and i + horizon < len(seq)
            later = seq[i + horizon][k] if ahead else final[k]
            xs.append(entry[2])
            ys.append((1 - final_weight) * (later - entry[k]) + final_weight * (final[k] - entry[k]))
            games.append(key[0])
            nxt.append(start + i + horizon if ahead else -1)   # the row `horizon` decisions on
            cards.append(entry[3])
    return (np.stack(xs), np.array(ys, dtype=np.float32), np.array(games), np.array(nxt),
            np.array(cards, dtype=np.int16))


def load_search(paths: list[Path], inputs: int | None = None, target: str | None = None):
    """S lines (ai_train search): inputs, the searched value of the candidate, the game (seed).
    S|seed|color|point|rank|value|sd|base|inputs|card|target; and the card number of every row.
    target (field 11, "margin" or "score"; files without it: margin) is what the value
    measures; given `target`, rows of the other one are refused (train --target)."""
    xs, ys, games, cards = [], [], [], []
    for path in paths:
        with path.open(encoding="utf-8") as f:
            for l in f:
                if not l.startswith("S|"):
                    continue
                parts = l.rstrip("\n").split("|")
                if len(parts) < 9:
                    continue
                row = np.array(parts[8].split(","), dtype=np.float32)
                if len(row) not in FEATURE_VERSIONS:
                    continue        # a line cut short (a file still being written)
                xs.append(project(row, inputs) if inputs else row)
                ys.append(float(parts[5]))
                games.append(int(parts[1]))
                card = int(parts[9]) if len(parts) > 9 and parts[9].strip().isdigit() else 0
                cards.append(card if card <= N_CARDS else 0)
                found = parts[10].strip() if len(parts) > 10 and parts[10].strip() else "margin"
                if target is not None and found != target:
                    raise SystemExit(f"{path}: search labels with target {found}, but train --target {target} "
                                     f"(run search with --target {target}, or train with --target {found})")
    if not xs:
        raise SystemExit(f"no S lines in {', '.join(map(str, paths))}")
    return np.stack(xs), np.array(ys, dtype=np.float32), np.array(games), np.array(cards, dtype=np.int16)


def train(x: np.ndarray, y: np.ndarray, hidden=(64, 64), epochs=12, lr=1e-3, batch=512, seed=1,
          games: np.ndarray | None = None, snapshot=None, cards: np.ndarray | None = None,
          n_cards: int = N_CARDS):
    """games: the game (seed) of every row; every 10th game is held out for validation (from
    every round, not only the first file). snapshot(epoch, params): called after each epoch
    with the output scale folded in (to export several epochs).
    cards (train --cards): the card number of every row (0: none). The one-hot of it is kept
    sparse: the first layer gets a third array wc (n_cards + 1 rows; row 0 stays 0) whose row
    of the card is added to its pre-activation; export() writes it as dense input columns."""
    rng = np.random.default_rng(seed)
    mean, std = x.mean(0), x.std(0)
    std[std < 1e-6] = 1.0
    xn = (x - mean) / std
    sizes = [x.shape[1], *hidden, 1]
    params = []
    for a, b in zip(sizes[:-1], sizes[1:]):
        params.append([rng.normal(0, np.sqrt(2.0 / a), (a, b)).astype(np.float32), np.zeros(b, np.float32)])
    if cards is not None:
        cards = np.asarray(cards, dtype=np.int64)
        params[0].append(np.zeros((n_cards + 1, sizes[1]), np.float32))
    m = [[np.zeros_like(p) for p in layer] for layer in params]
    v = [[np.zeros_like(p) for p in layer] for layer in params]
    t = 0
    idx = np.arange(len(xn))
    if games is not None and (games % 10 == 0).any() and not (games % 10 == 0).all():
        held = games % 10 == 0
        val, tr = idx[held], idx[~held]
    else:
        val = idx[: len(idx) // 10]
        tr = idx[len(idx) // 10:]
    yscale = max(1.0, float(np.abs(y).mean()))
    best, best_mse, best_epoch = None, float("inf"), 0
    for epoch in range(epochs):
        rng.shuffle(tr)
        for start in range(0, len(tr), batch):
            bi = tr[start:start + batch]
            acts = [xn[bi]]
            for li, layer in enumerate(params):
                z = acts[-1] @ layer[0] + layer[1]
                if li == 0 and cards is not None:
                    z = z + layer[2][cards[bi]]
                acts.append(np.maximum(z, 0) if li < len(params) - 1 else z)
            grad = 2 * (acts[-1][:, 0] - y[bi] / yscale)[:, None] / len(bi)
            t += 1
            for li in range(len(params) - 1, -1, -1):
                w = params[li][0]
                grads = [acts[li].T @ grad, grad.sum(0)]
                if li == 0 and cards is not None:
                    gc = np.zeros_like(params[0][2])
                    np.add.at(gc, cards[bi], grad)
                    gc[0] = 0                     # no card: no input
                    grads.append(gc)
                if li > 0:
                    grad = (grad @ w.T) * (acts[li] > 0)
                for k, g in enumerate(grads):
                    m[li][k] = 0.9 * m[li][k] + 0.1 * g
                    v[li][k] = 0.999 * v[li][k] + 0.001 * g * g
                    mh, vh = m[li][k] / (1 - 0.9 ** t), v[li][k] / (1 - 0.999 ** t)
                    params[li][k] -= lr * mh / (np.sqrt(vh) + 1e-8)
        pred = predict(params, xn[val], None if cards is None else cards[val]) * yscale
        mse = float(np.mean((pred - y[val]) ** 2))
        base = float(np.mean((y[val] - y[tr].mean()) ** 2))
        print(f"  epoch {epoch + 1:2d}: validation error {mse:7.1f} (predicting the mean: {base:7.1f})")
        if snapshot is not None:
            snapshot(epoch + 1, [[p.copy() for p in layer] for layer in params[:-1]]
                     + [[params[-1][0] * yscale, params[-1][1] * yscale]])
        if mse < best_mse:       # early stop: keep the epoch that predicts held-out games best
            best, best_mse, best_epoch = [[p.copy() for p in layer] for layer in params], mse, epoch + 1
    params = best
    print(f"  kept epoch {best_epoch} (validation error {best_mse:.1f})")
    # fold the output scale into the last layer
    params[-1][0] = params[-1][0] * yscale
    params[-1][1] = params[-1][1] * yscale
    return params, mean, std


def predict(params, xn, cards=None):
    """cards: the card number of every row, for a network with card inputs (params[0][2])."""
    a = xn
    for li, layer in enumerate(params):
        a = a @ layer[0] + layer[1]
        if li == 0 and len(layer) > 2 and cards is not None:
            a = a + layer[2][np.asarray(cards, dtype=np.int64)]
        if li < len(params) - 1:
            a = np.maximum(a, 0)
    return a[:, 0]


def read_weights(path: Path):
    """The layers, mean and std of an exported network (export() below). A network with card
    inputs (cards = N) comes back as train() makes it: the base mean and std, the first layer
    [w, b, wc] with wc's row 0 (no card) zero."""
    import re
    text = path.read_text(encoding="utf-8")
    if "members = {" in text:
        raise SystemExit(f"{path}: an ensemble (give its members)")
    nums = lambda body: np.array([float(v) for v in body.split(",") if v.strip()], dtype=np.float64)
    mean = nums(re.search(r"mean = \{([^}]*)\}", text).group(1))
    std = nums(re.search(r"std = \{([^}]*)\}", text).group(1))
    found = re.search(r"\bcards = (\d+)", text)
    n_cards = int(found.group(1)) if found else 0
    params = []
    for n_in, n_out, b, w in re.findall(
            r"n_in = (\d+), n_out = (\d+), b = \{([^}]*)\},\s*w = \{([^}]*)\}", text):
        params.append([nums(w).reshape(int(n_out), int(n_in)).T, nums(b)])
    if n_cards:
        n_base = len(mean) - n_cards
        w = params[0][0]
        params[0] = [w[:n_base], params[0][1], np.vstack([np.zeros((1, w.shape[1])), w[n_base:]])]
        mean, std = mean[:n_base], std[:n_base]
    return params, mean, std


def card_count(params) -> int:
    """The card inputs of a network (0: none)."""
    return params[0][2].shape[0] - 1 if len(params[0]) > 2 else 0


def lua_list(values) -> str:
    return "{" + ",".join(f"{float(v):.5g}" for v in values) + "}"


def export(params, mean, std, out: Path, note: str) -> None:
    """mean, std: of the base inputs. A network with card inputs gets them as dense columns
    after the base inputs (mean 0, std 1: a zero stays 0 in Lua) and `cards = N`."""
    n_cards = card_count(params)
    layers = []
    for li, layer in enumerate(params):
        w, b = layer[0], layer[1]
        if li == 0 and n_cards:
            w = np.vstack([w, layer[2][1:]])
        n_in, n_out = w.shape
        # row-major by output: w[(j - 1) * n_in + i]
        layers.append(f"    {{ n_in = {n_in}, n_out = {n_out}, b = {lua_list(b)},\n"
                      f"      w = {lua_list(w.T.reshape(-1))} }}")
    full_mean = np.concatenate([mean, np.zeros(n_cards)])
    full_std = np.concatenate([std, np.ones(n_cards)])
    text = ("-- AI opponent network weights (docs/AI_OPPONENT.md section 4a).\n"
            "-- GENERATED by tools/ai_train.py; do not edit. " + note + "\n"
            f"return {{\n  version = 1,\n  inputs = {len(full_mean)},\n"
            f"  features = {FEATURE_VERSIONS.get(len(mean), 1)},\n"
            + (f"  cards = {n_cards},\n" if n_cards else "")
            + f"  mean = {lua_list(full_mean)},\n  std = {lua_list(full_std)},\n  layers = {{\n"
            + ",\n".join(layers) + "\n  },\n}\n")
    out.write_text(text, encoding="utf-8", newline="\n")
    n_weights = sum(p.size for layer in params for p in layer[:2]) + n_cards * params[0][1].size
    print(f"wrote {out} ({n_weights} weights)")


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
    t.add_argument("--data", type=Path, action="append", default=[])
    t.add_argument("--search", type=Path, action="append", default=[],
                   help="search labels (ai_train search, S lines): each candidate a row, its searched value "
                        "the target (counterfactual and low-noise; not bootstrapped)")
    t.add_argument("--search-weight", type=int, default=3, help="every S row is repeated this many times")
    t.add_argument("--out", type=Path, default=ROOT / "arno" / "ai" / "net_weights.lua")
    t.add_argument("--hidden", default="64,64")
    t.add_argument("--epochs", type=int, default=12)
    t.add_argument("--lr", type=float, default=1e-3)
    t.add_argument("--bootstrap", type=Path, action="append",
                   help="a network (same inputs) whose Q at the row --horizon decisions on is added to the "
                        "target; given several times, their Q is averaged (an ensemble's members)")
    t.add_argument("--gamma", type=float, default=1.0, help="the weight of that Q")
    t.add_argument("--seed", type=int, default=1, help="the start weights and the order of the rows")
    t.add_argument("--final-weight", type=float, default=0.0,
                   help="mix the change up to the end of the game into the target with this weight")
    t.add_argument("--snapshots", default="",
                   help="also write these epochs (e.g. 10,13,16) next to --out as <out>_e<N>.lua")
    t.add_argument("--baseline", action="store_true",
                   help="first fit the state alone (V), then train on what the choice adds (y - V)")
    t.add_argument("--inputs", type=int, choices=(1, 2, 3),
                   help="train on this input version (older rows cannot be widened, newer ones are cut)")
    t.add_argument("--horizon", type=int, default=0,
                   help="target = margin this many own decisions later (0: final margin)")
    t.add_argument("--target", choices=("margin", "score"), default="margin")
    t.add_argument("--cards", action="store_true",
                   help=f"card-identity inputs: a one-hot of the card the move is about (1..{N_CARDS}; D field 7, "
                        "S field 10; rows without it: none) after the base inputs, not standardised")
    e = sub.add_parser("ensemble", help="bundle networks: Q is the average of theirs")
    e.add_argument("--weights", type=Path, action="append", required=True)
    e.add_argument("--out", type=Path, required=True)
    a = sub.add_parser("average", help="average the weights of networks from one training run")
    a.add_argument("--weights", type=Path, action="append", required=True)
    a.add_argument("--out", type=Path, required=True)
    s = sub.add_parser("search", help="search labels (tests/lua/search.lua): S lines per candidate")
    s.add_argument("--games", type=int, default=10)
    s.add_argument("--first", type=int, default=40000001)
    s.add_argument("--seats", default="network:1,network:1")
    s.add_argument("--weights", type=Path)
    s.add_argument("--weights-b", type=Path, help="the network of network_b seats")
    s.add_argument("--out", type=Path)
    s.add_argument("--workers", type=int)
    s.add_argument("--points", type=int, default=8, help="decision points per searched seat and game")
    s.add_argument("--k", type=int, default=5, help="candidates per point (top k by Q, plus the base choice)")
    s.add_argument("--samples", type=int, default=3, help="rollouts per candidate")
    s.add_argument("--horizon", type=int, default=20, help="own decisions played on after the point")
    s.add_argument("--target", choices=("margin", "score"), default="margin",
                   help="a rollout's value: the change of the margin or of the own score (then --weights "
                        "must be trained with train --target score: its Q at the horizon is added)")
    s.add_argument("--searched", default="ai", help="the searched seat's colour, or 'ai' (every policy seat)")
    s.add_argument("--rollout-budget", type=float, default=0.0,
                   help="the policies' budget after the point (0: their best choice; the samples then differ "
                        "by the reshuffled deck, with less noise than budget 1); < 0: the seats' own")
    s.add_argument("--check", action="store_true",
                   help="also replay each game with every choice forced and compare the final scores")
    s.add_argument("--no-reshuffle", action="store_true",
                   help="keep the seed's zoo deck after the point (rollouts then know the next cards)")
    s.add_argument("--report", type=Path, action="append",
                   help="play nothing: report on these search files (timing, best vs base, noise)")
    m = sub.add_parser("match")
    m.add_argument("--games", type=int, default=100)
    m.add_argument("--first", type=int, default=100001)
    m.add_argument("--seats", default="network:0,heuristic:0")
    m.add_argument("--weights", type=Path)
    m.add_argument("--weights-b", type=Path, help="the network of network_b seats (new against current)")
    m.add_argument("--workers", type=int)
    for q in (p, m):      # network_a seats: the network with the assists (ai.policy ASSIST)
        q.add_argument("--assist-build", type=float, help="network_a: points per animal a build would house")
        q.add_argument("--assist-cp", type=float, help="network_a: points for supporting a conservation project")
        q.add_argument("--assist-final", type=float, help="network_a: points per CP a card play adds to the final scoring card")
        q.add_argument("--assist-end", type=float, help="network_a: most points off an action that ends a game it would lose")
        q.add_argument("--assist-unlock", type=float, help="network_a: points per hand card whose conditions a choice meets")
        q.add_argument("--assist-upgrade", type=float, help="network_a: points on upgrading the ANIMALS action card")
        q.add_argument("--assist-x", type=float, help="network_a: points per unit an X-token lifts an action card to")
        q.add_argument("--assist-snap", type=float, help="network_a: points per unit the best display card gives on a CARDS snap")
        q.add_argument("--assist-rep", type=float, help="network_a: points per unit of reputation worth (track rewards ahead)")
        q.add_argument("--assist-slot", type=float, help="network_a: points per point a conservation project slot gives")
        q.add_argument("--assist-discard", type=float, help="network_a: at the final scoring discard, minus the card's award (points)")
        q.add_argument("--assist-partner", type=float, help="network_a: per point a partner zoo saves on the hand's animals")
        q.add_argument("--assist-flip", type=float, help="network_a: the upgrade order after ANIMALS (policy.FLIP_ORDER)")
        q.add_argument("--assist-uni", type=float, help="network_a: the Hand Size University first (policy.UNI_ORDER)")
        q.add_argument("--assist-enc", type=float, help="network_a: a Size-5 enclosure over Size-4 (policy.ENC_ORDER)")
        q.add_argument("--assist-sponsor", type=float, help="network_a: points on SPONSORS when a hand sponsor is playable at its strength")
        q.add_argument("--assist-clever", type=float, help="network_a: the clever card order (policy.CLEVER_ORDER)")
        q.add_argument("--assist-kp", type=float, help="network_a: a Pavilion over a Kiosk (policy.KP_ORDER)")
        q.add_argument("--assist-tile", type=float, help="network_a: tile spots by their reputation / card draw bonuses")
        q.add_argument("--assist-donate", type=float, help="network_a: points off a donation per money above 2")
        q.add_argument("--assist-last", type=float, help="network_a: on the final turn, points per point a choice brings at once")
    args = ap.parse_args(argv)

    if args.cmd in ("play", "match"):
        seats = parse_seats(args.seats)
        lines = play(args.games, seats, getattr(args, "out", None), args.weights, args.first, args.workers,
                     log=args.cmd == "play", weights_b=getattr(args, "weights_b", None),
                     assist={"assist_build": args.assist_build, "assist_cp": args.assist_cp,
                             "assist_final": args.assist_final, "assist_end": args.assist_end,
                             "assist_unlock": args.assist_unlock, "assist_upgrade": args.assist_upgrade,
                             "assist_x": args.assist_x, "assist_snap": args.assist_snap,
                             "assist_rep": args.assist_rep, "assist_slot": args.assist_slot,
                             "assist_discard": args.assist_discard, "assist_partner": args.assist_partner,
                             "assist_flip": args.assist_flip, "assist_uni": args.assist_uni,
                             "assist_enc": args.assist_enc, "assist_sponsor": args.assist_sponsor,
                             "assist_clever": args.assist_clever, "assist_kp": args.assist_kp, "assist_tile": args.assist_tile, "assist_donate": args.assist_donate,
                             "assist_last": args.assist_last})
        report(lines, seats)
    elif args.cmd == "search" and args.report:
        lines = [l.rstrip("\n") for path in args.report for l in path.open(encoding="utf-8")]
        search_report(lines)
    elif args.cmd == "search":
        seats = parse_seats(args.seats)
        opts = {"points": args.points, "k": args.k, "samples": args.samples, "horizon": args.horizon,
                "searched": args.searched, "check": args.check, "target": args.target, "reshuffle": not args.no_reshuffle,
                "rollout_budget": args.rollout_budget if args.rollout_budget >= 0 else None}
        lines = play(args.games, seats, args.out, args.weights, args.first, args.workers,
                     weights_b=args.weights_b, search=opts)
        report(lines, seats)
    elif args.cmd == "ensemble":
        import re
        NL = "\n"
        # members may differ in card inputs (cards = N): they share the base inputs; the
        # ensemble's inputs and features are those, its cards the most any member reads
        members, inputs, features, cards = [], set(), set(), [0]
        for w in args.weights:
            text = w.read_text(encoding="utf-8")
            if "members = {" in text:
                raise SystemExit(f"{w}: already an ensemble")
            found = re.search(r"\bcards = (\d+)", text)
            n_cards = int(found.group(1)) if found else 0
            cards.append(n_cards)
            inputs.add(int(re.search(r"inputs = (\d+)", text).group(1)) - n_cards)
            features.add(int(re.search(r"features = (\d+)", text).group(1)))
            members.append(text[text.index("return {") + len("return "):].strip())
        if len(inputs) != 1 or len(features) != 1:
            raise SystemExit("the members read different inputs")
        n, f = inputs.pop(), features.pop()
        card_line = f"  cards = {max(cards)},{NL}" if max(cards) else ""
        head = ("-- AI opponent network weights (docs/AI_OPPONENT.md section 4a)." + NL
                + "-- GENERATED by tools/ai_train.py; do not edit. Ensemble of "
                + ", ".join(w.name for w in args.weights) + "." + NL)
        body = (f"return {{{NL}  version = 1,{NL}  inputs = {n},{NL}  features = {f},{NL}{card_line}  members = {{{NL}"
                + ("," + NL).join(members) + NL + "  }," + NL + "}" + NL)
        args.out.write_text(head + body, encoding="utf-8", newline=NL)
        print(f"wrote {args.out} ({len(members)} members)")
    elif args.cmd == "average":
        # snapshots of one run share the input scaling and start, so their weights can be
        # averaged (a smoother network: the choice swings less between neighbouring epochs)
        nets = [read_weights(w) for w in args.weights]
        mean, std = nets[0][1], nets[0][2]
        for _, m2, s2 in nets[1:]:
            if not (np.allclose(m2, mean, rtol=1e-3, atol=1e-6) and np.allclose(s2, std, rtol=1e-3, atol=1e-6)):
                raise SystemExit("not one run: the input scaling differs")
        if len({card_count(n[0]) for n in nets}) != 1:
            raise SystemExit("not one run: the card inputs differ")
        params = [[np.mean([n[0][li][k] for n in nets], axis=0) for k in range(len(nets[0][0][li]))]
                  for li in range(len(nets[0][0]))]
        export(params, mean, std, args.out, "Average of " + ", ".join(w.name for w in args.weights) + ".")
    elif args.cmd == "train":
        if not args.data and not args.search:
            raise SystemExit("train: give --data and/or --search")
        if args.data:
            x, y, games, nxt, cards = load(args.data, args.horizon, args.target, args.inputs, args.final_weight)
        else:
            x, y, games, nxt = None, np.zeros(0, np.float32), np.zeros(0, int), np.zeros(0, int)
            cards = np.zeros(0, np.int16)
        if args.bootstrap is not None and x is not None:
            # temporal difference: the change over the horizon plus what a trained network
            # expects from the position reached then (its own Q there, the choice then made),
            # instead of only the horizon (blind beyond it) or the end of the game (noisy)
            # several networks (the members of an ensemble): their Q averaged
            q = np.zeros(len(y), dtype=np.float32)
            for path in args.bootstrap:
                bp, bmean, bstd = read_weights(path)
                if len(bmean) != x.shape[1]:
                    raise SystemExit(f"--bootstrap: {path} reads other inputs")
                # a network with card inputs: each row's own card (q[nxt]: the next row's)
                for a in range(0, len(y), 200000):
                    q[a:a + 200000] += predict(bp, (x[a:a + 200000] - bmean) / bstd,
                                               cards[a:a + 200000]) / len(args.bootstrap)
            ahead = nxt >= 0
            print(f"bootstrap from {', '.join(p.name for p in args.bootstrap)}: {ahead.mean():.0%} of the rows, "
                  f"Q there mean {q[nxt[ahead]].mean():+.1f} sd {q[nxt[ahead]].std():.1f}")
            y = y.copy()
            y[ahead] = y[ahead] + args.gamma * q[nxt[ahead]]
        if args.search:
            # appended after the bootstrap (their value already holds the network's Q at the
            # horizon, and nxt indexes the D rows); game = seed, so the hold-out split holds
            sx, sy, sg, sc = load_search(args.search, args.inputs, args.target)
            if x is not None and sx.shape[1] != x.shape[1]:
                raise SystemExit(f"--search rows have {sx.shape[1]} inputs, --data rows {x.shape[1]} (use --inputs)")
            w = max(1, args.search_weight)
            print(f"search labels: {len(sy)} rows x {w}, value mean {sy.mean():+.1f} sd {sy.std():.1f}")
            sx, sy, sg, sc = np.repeat(sx, w, axis=0), np.repeat(sy, w), np.repeat(sg, w), np.repeat(sc, w)
            x = sx if x is None else np.concatenate([x, sx])
            cards = np.concatenate([cards, sc])
            y = np.concatenate([y, sy]).astype(np.float32)
            games = np.concatenate([games, sg])
        print(f"{len(y)} decisions, {x.shape[1]} inputs, target mean {y.mean():+.1f} sd {y.std():.1f}"
              + (f"; card inputs {N_CARDS}, {np.mean(cards > 0):.0%} of the rows about a card" if args.cards else ""))
        hidden = tuple(int(h) for h in args.hidden.split(","))
        if args.baseline:
            # the state explains most of the target and is the same for every choice of a
            # decision; taking it out leaves the network what tells the choices apart
            n_state = FEATURE_SIZES[FEATURE_VERSIONS[x.shape[1]]][0]
            print(f"baseline: the state alone ({n_state} inputs)")
            vp, vmean, vstd = train(x[:, :n_state], y, hidden=hidden, epochs=args.epochs, lr=args.lr, games=games)
            y = y - predict(vp, (x[:, :n_state] - vmean) / vstd)
            print(f"residual target sd {y.std():.1f}")
        note = f"{len(y)} decisions from {', '.join(p.name for p in args.data + args.search)}."
        wanted = {int(e) for e in args.snapshots.split(",") if e.strip()}
        smean, sstd = x.mean(0), x.std(0)          # as train() normalises
        sstd[sstd < 1e-6] = 1.0

        def snapshot(epoch, ps):
            if epoch in wanted:
                export(ps, smean, sstd, args.out.with_name(f"{args.out.stem}_e{epoch}{args.out.suffix}"),
                       note + f" Epoch {epoch}.")
        params, mean, std = train(x, y, hidden=hidden, epochs=args.epochs, lr=args.lr, games=games, seed=args.seed,
                                  snapshot=snapshot if wanted else None, cards=cards if args.cards else None)
        export(params, mean, std, args.out, note)
    return 0


if __name__ == "__main__":
    sys.exit(main())
