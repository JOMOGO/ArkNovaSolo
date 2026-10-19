# Decision study: where should automated ARNO live?

Inputs: `docs/MOD_ARCHITECTURE.md` (the scripted mod), `docs/ARNO_LOGIC.md` (the helper
app; IN-xx/OUT-xx IDs come from there), and TTS scripting documentation research (§2).

## 1. Facts that drive the decision

1. **The helper's executable ARNO logic is small.** `src/services/*`, `NavigationState`
   and the dice in five components add up to about 300 lines of TypeScript. It covers the
   card-slot rotation, a d4 for slot 2–5, the action tables, the ≥ 6 token rule, the
   upgrade cap, the project-module tracker, the conservation-project pick, and the
   zoo/university/display/bonus-tile dice. Everything else ARNO does is **prose** for the
   human (worker collision, break draws, card handling, bonus usage) or **absent** from the
   app (action order, reputation overflow, game end). See `ARNO_LOGIC.md` §0.
2. **Any option that removes bookkeeping must apply ARNO's outputs to the table.** The
   outputs are OUT-02..OUT-15: tracks, break token, display snap and refill, zoo and
   university tiles, workers, project tokens and rewards, bonus tiles, break draws. In
   TTS, this adapter is the bulk of the work, and it must be written in Lua inside the
   mod. **That holds for both A and B.**
3. **The mod is a single hand-written 18k-line `Global.lua`.** It has no hook system
   (`MOD_ARCHITECTURE.md` §15). It builds `players` only from seated humans and destroys
   the unseated colours' boards (`Global.lua:4036–4082`). Solo mode is `#players == 1`
   (`:7427`), with a 27-turn cube timer. It has no bot code.
4. **Rules are enforced by which buttons the UI shows, not by the state mutators.**
   `apply_cp`, `update_rep`, `take_partner_zoo`, `take_university`, `break_x`,
   `refill_display` and the others do not check legality (§14). Legality checks will
   **not** block ARNO's moves. The real constraint is different: those functions expect a
   full `players` entry with a board, map and counters, and some of them queue
   choice-prompts for that player.
5. **Persistence is checkpoint-based.** `onSave` returns real state only while a
   checkpoint is being stored (at turn start, income, or end of turn with prompts pending).
   Otherwise it writes an `in-turn:N` marker (`:3104`). Rewind reloads the script, so
   `Wait` timers and in-flight callbacks are lost. Play resumes only through
   `CHECKPOINT_RESUMES`.
6. **The mod is actively maintained** (save dated 2026-10-12). Any patch has to be
   re-applied when it updates.

## 2. TTS WebRequest and bridge facts (for option B)

| Question | Answer | Status |
|---|---|---|
| API | `WebRequest.get/post/put/delete/head/custom(url, method, download, data, headers, cb)`, async callback, `is_error`/`response_code`/`text`. 4xx/5xx do **not** set `is_error`. [docs](https://api.tabletopsimulator.com/webrequest/manager/) | documented |
| Runs where | "From the game host's computer only." Solo means your PC. | documented |
| `http://127.0.0.1:port` | Not mentioned in the docs. One mod (Assisted Frosthaven) talks to a local HTTP server; users report it works, with some firewall and hosts-file trouble ([thread](https://steamcommunity.com/workshop/filedetails/discussion/2973518625/3826415117583524358)). | community-reported, **before v14** |
| TTS v14 (Unity 6) | Unity 6 can block insecure HTTP depending on a player setting. The v14 patch notes say nothing about it. | **unknown: needs a 5-minute in-TTS probe** |
| Timeouts, size limits | Not documented. | unknown |
| Rewind | `onLoad` runs on rewind. Pending callbacks are lost (not documented; inferred from the script reload). | inferred |
| Alternative channel | External Editor API: TCP `localhost:39999`. Message id 3 runs Lua in Global; id 2 calls `onExternalMessage`. TTS sends replies to `39998`. [docs](https://api.tabletopsimulator.com/externaleditorapi/) | documented |
| MoonSharp | Lua 5.2 subset with bit32, coroutine, math, string, os.time. **No `require`.** All numbers are doubles. | documented / inferred |

## 3. Options

### A. Port ARNO to Lua inside the scripted mod (automated seat)

The ARNO core (§1.1) becomes pure Lua functions: state and RNG in, decisions out. A Lua
adapter applies the decisions through the mod's own functions. ARNO joins `players` as a
non-human Yellow entry, so the mod's normal 2-player rules apply (break track, display,
blockers, score-based game end). Human-only prompts are skipped for the bot.

- **Effort (rough):**
  - build tool and round-trip proof: S
  - core port, headless Lua tests and the Node differential harness: M (~500 Lua + ~400 test lines)
  - **adapter and hooks: L** (~1,500–2,500 Lua lines and about 15–30 hook points): bot
    seat in setup; skipping the setup discard, draft, break income/discard and
    final-scoring discard for the bot; track moves; association, zoo, university and
    workers; conservation projects; display snap and animal hooks; break draws; bonus
    tiles; scoring; ARNO panel and log; checkpoint integration
  - your in-TTS testing: M, iterative
  - Overall **L–XL**, built in stages (§6).
- **Faithfulness:** the `[code]` part can be proven equal to the TypeScript with a seeded
  differential harness. The `[prose]` part is carried over by hand from the app's text.
  The `[absent]` part needs your decisions (`ARNO_LOGIC.md` §9). Both of those apply to
  B as well.
- **Your remaining bookkeeping:** almost none for the automated stages. Before full
  automation, you'd click a manual "ARNO turn" button and handle any `[absent]` cases the
  panel flags.
- **Rewind/undo:** ARNO state and RNG state go into `checkpoint_state()`. A new
  `CHECKPOINT_RESUMES.arno_turn` entry takes a checkpoint at the start of ARNO's turn.
  Resuming from it replays the turn with the same seed, so you get the same decisions.
  Nothing is in flight outside TTS. Caveat: every `storeRewindState` call blocks TTS's own
  automatic stores (`Global.lua:3136–3203`, argument `true`). But the mod also stores
  "spacer" and "heartbeat" states that carry only the `in-turn:` marker, so a rewind can
  land on a state the mod already marks as unresumable, and you then step back further to
  a checkpoint. Mid-turn rewinds behave this way for human turns today. Phase 2 must decide
  whether ARNO's turn emits spacer states at all; the simplest choice is none, so his turn
  is atomic.
- **Fragility:** a mod update means re-extracting and re-applying the hooks, which should
  be kept small and listed in `CHANGES.md`. Helper updates are rare. The port is pinned to
  helper commit `f4cda53`, and re-running the harness against a newer helper detects
  drift.
- **Offline:** yes. Nothing to start besides TTS.
- **Licensing:** the ported logic keeps Apache-2.0 attribution (NOTICE, Lua file
  headers, credits to Andre K and Stefan Seifert). The modified mod is **personal use
  only**: the mod's Lua has no stated licence, and the save references Feuerland/Capstone
  card art by URL. **Do not republish it to the Workshop** without the mod author's
  permission. No card content is added.
- **Risks:**
  1. The mod assumes every `players` entry is a seated human with a hand. You'd need a
     probe of `Player.Yellow` hand calls while nobody is seated, or code paths that never
     touch the bot's hand (ARNO keeps cards on his mat, so the bot needs no hand).
  2. Interleaving with the mod's `Wait`-driven animations and prompt queue.
  3. Breaks or game end triggered in the middle of ARNO's turn.
  4. "Whenever any player…" sponsor hooks must be fired explicitly for ARNO's animals
     (`apply_hooks`).
  5. MoonSharp doubles mean the PRNG must be written to be integer-safe.
  6. The mod's update cadence.

### B. TTS hybrid: ARNO in TypeScript as a local service

Same Lua adapter as A. TTS sends ARNO's state to `http://127.0.0.1:PORT`, and a small
Node service runs the helper's services unchanged and returns decisions.

- **Effort:** the adapter is the same (L). Service wrapper: S. Bridge with async, retry
  and rewind handling: M. It saves only the core port (M) but adds a Node runtime and
  process management. Net effort is **the same or slightly more than A**.
- **Faithfulness:** the same as A in practice. The `[code]` part runs as the original
  TypeScript, but the helper calls unseeded `Math.random` and rolls inside Vue
  components, so the service needs a seeded wrapper and copied component logic anyway.
  `[prose]`/`[absent]` still live in Lua.
- **Your bookkeeping:** the same as A, **plus you start the service every session**.
- **Rewind:** the service must be stateless, with state kept in the TTS checkpoint.
  Requests in flight during a rewind are lost and must be re-issued from `onLoad`. This
  works, but there are more ways to fail.
- **Fragility:** the mod-update cost is the same as A, plus the TTS HTTP behaviour (not
  verified on v14), Node versions, ports, firewall.
- **Offline:** yes, but the service has to be running.
- **Licensing:** the same as A. The TypeScript is reused as-is under Apache-2.0.
- **Risks:** **it is unverified whether TTS v14 lets WebRequest reach plain-HTTP
  localhost.** A probe is needed before choosing B. Async callbacks could arrive across a
  checkpoint or rewind.
- **Verdict:** B only makes sense if you specifically want zero ported rule code. The
  TypeScript it protects is the smallest, best-tested part of the system.

### C1. Fork of the helper app with less manual input

The app stays a separate screen. It reads ARNO-relevant state from a TTS save (the
checkpoint JSON in `Saves/` or `TS_AutoSave.json`) to answer IN-03..IN-11. It could also
run as a local service polled by TTS.

- **Effort:** S–M (save parser, seeded RNG, persistence of the rolls).
- **Faithfulness:** high, because it is the original app.
- **Your bookkeeping:** **most of it remains.** You still carry out OUT-02..OUT-15 by hand
  in TTS: tracks, tiles, workers, display, breaks. The auto-save only reflects the last
  checkpoint, so the imported state can be stale. Only the input side gets lighter.
- **Rewind:** the app's Back/Revert and TTS rewind are independent, so they can drift
  apart.
- **Fragility:** it depends on the mod's private checkpoint JSON format, which can change
  with any mod update.
- **Offline:** yes (it is already a PWA). **Licensing:** clean (Apache-2.0 fork, no card
  content).
- **Verdict:** cheap, but it misses the goal.

### C2. Standalone digital Ark Nova vs ARNO

- **Effort: XXL.** It needs a full rules engine for about 255 zoo cards, more than 100
  sponsor effects, maps, buildings, breaks, and a UI.
- **Licensing: blocks publishing, not building.** The card text, data, art and the
  "Ark Nova" name belong to Feuerland/Capstone. Copyright and trademark apply whether or
  not the app is free, so a public app or website needs their permission. They already
  have an official digital licensee, so a free public clone is less likely to be
  tolerated than a Workshop mod. Kept **strictly private**, C2 is in the same position as
  using the TTS mod. The card data would still have to be typed in by you, or taken from
  the mod, whose Lua has no licence: fine privately, never publishable. Not legal advice.
- **For personal use, the real objection is effort.** C2 rebuilds the rules engine that
  the scripted mod already contains (18k lines). Option A reuses it and adds only ARNO.
- **It already exists:** *Ark Nova Digital* (Dire Wolf) is in Steam Early Access, with AI
  opponents and solo challenges ([announcement](https://news.direwolfdigital.com/ark-nova-digital-is-now-available-on-early-access),
  [Steam](https://store.steampowered.com/app/2438990)). The unofficial ARNO bot is not
  part of it.
- **Verdict:** not recommended.

## 4. Comparison

| | A: Lua port in mod | B: TS service + mod | C1: helper fork | C2: standalone |
|---|---|---|---|---|
| Effort | L–XL | L–XL (≥ A) | S–M | XXL |
| ARNO faithfulness | high (`[code]` proven by harness) | high | highest | n/a |
| Your bookkeeping left | ~none | ~none + start service | most outputs | none |
| Rewind/undo | checkpoint + seed replay | same + lost requests | separate undo, drifts | own |
| Mod update fragility | re-apply hooks | same + HTTP | save-format coupling | n/a |
| Helper update fragility | low (harness detects drift) | lowest | lowest | n/a |
| Offline | yes | yes (service) | yes | yes |
| Licensing | personal use only (mod and art) | same | clean | personal use only; publishing needs publisher permission |
| Main risk | bot inside a humans-only `players` model | unverified v14 localhost HTTP | goal not met | scope, IP |

## 5. Where every ARNO input and output would live

`P` = ARNO pure core (Lua in A, TypeScript in B/C), `Ad` = Lua adapter reading/writing the
mod, `Svc` = Node service, `UI` = TTS panel, `Hm` = you.

| ID | What | A | B | C1 | C2 |
|---|---|---|---|---|---|
| IN-01 | setup sponsor discards | Ad (counted at setup) | Ad → Svc | Hm / save import | engine |
| IN-02 | snapped card is a sponsor | Ad (card type) | Ad → Svc | Hm | engine |
| IN-03/04 | zoo/university reroll | Ad: availability → P rerolls | Ad → Svc | Hm / import | engine |
| IN-05 | worker collision | P+Ad (higher-then-lower rule) | Ad | Hm | engine |
| IN-06 | "missing most" | P (rule TBD, §9 Q6) | Svc | Hm | engine |
| IN-07..09 | project counts | Ad (projects and tokens) | Ad → Svc | Hm / import | engine |
| IN-10 | break sponsor discards | Ad | Ad → Svc | Hm | engine |
| IN-11 | upgrade earned | Ad (mat/track bonus) → P | Ad → Svc | Hm | engine |
| IN-12 | revert upgrade | not needed (rewind) | not needed | Hm | n/a |
| IN-13 | bonus tile earned | Ad → P | Ad → Svc | Hm | engine |
| IN-14 | game end | mod end check | mod | Hm | engine |
| IN-15 | final CP/appeal | mod scoring + P bot CP | mod + Svc | Hm / import | engine |
| IN-16 | next turn | mod turn hook (+ manual button) | same | Hm | engine |
| OUT-01 | card and slot shown | UI panel/log | UI | app | UI |
| OUT-02..04 | appeal/rep/CP | Ad → `apply_appeal`/`update_rep`/`apply_cp` | same | Hm | engine |
| OUT-05 | break token | Ad → `break_x` / break trigger | same | Hm | engine |
| OUT-06 | scoring/notepad tokens | P state + token objects | Svc state | app | engine |
| OUT-07 | snap display card | Ad → display + refill + `apply_hooks` | same | Hm | engine |
| OUT-08/09 | zoo/university | Ad → `take_partner_zoo`/`take_university` (bot variant) | same | Hm | engine |
| OUT-10 | worker | Ad → association board | same | Hm | engine |
| OUT-11 | project support | Ad → project cube + reward | same | Hm | engine |
| OUT-12 | donate | Ad (**semantics TBD**) | same | Hm | engine |
| OUT-13 | upgrade card | P | Svc | app | engine |
| OUT-14 | bonus tile | P d2 + Ad | Svc + Ad | Hm | engine |
| OUT-15 | break draws | Ad (deck → mat/discard) | same | Hm | engine |
| OUT-16 | bot end CP | P → mod scoring | Svc → mod | app | engine |
| OUT-17 | project-module status | UI | UI | app | UI |

## 6. Recommendation: **Option A**, built and shipped in stages

Reasons:

1. **The adapter dominates every TTS option, and it has to be Lua either way.** B saves
   only the smallest and best-tested part (~300 lines), and adds a runtime, a network hop
   that is unverified on TTS v14, and async-versus-rewind failure modes.
2. **A is the only option where undo is simple:** ARNO state and seed live in the mod's
   own checkpoint, and an ARNO turn replays deterministically.
3. **Faithfulness can be proven for the part the app computes**: a differential harness
   (seeded Lua vs the original TypeScript with a stubbed `Math.random`) plus the helper's
   own test cases. The parts the app does not compute need your rulings in either option.
4. **C1 does not reduce the outputs you apply by hand.** C2 means rebuilding everything
   the mod already does, and it could never be published.

Proposed stages, each one playable on its own:

1. **Core + panel.** ARNO core in Lua, a seeded RNG in checkpoint state, ARNO joins as
   Yellow (2-player rules), and its turn runs automatically after yours (plus a manual
   button). The panel shows the drawn card and the actions, and **tracks are applied
   automatically**. The other outputs are shown as instructions.
2. **Association and projects:** zoo, university, workers, conservation projects, bonus
   tiles, upgrades.
3. **Cards:** display snap, break draws, animal hooks for your effects.
4. **End:** game end and scoring.

### Sharing (owner decision, 2026-10-19)

The owner will publish the result as **a new version of the mod**
(`dist/ArkNova_Scripted_ARNO.json`), not as a separate add-on. Notes recorded with that
decision:
- The ARNO port is Apache-2.0: ship NOTICE and credits for Andre K (ARNO design) and
  Stefan Seifert (helper app).
- The base mod's Lua has no stated licence, which means all rights reserved by default,
  and its card art belongs to Feuerland/Capstone. Recommended, not required: ask the base
  mod's author before publishing, and credit them in the Workshop description and in-game.
- Design consequences, kept anyway for maintainability:
  - ARNO code goes in separate files.
  - Hooks are small, named, and anchored to function names.
  - `tools/tts_build.py` rebuilds the new version from a fresh extract, so base-mod
    updates can be absorbed quickly.

### Owner decisions for Phase 2 (2026-10-19)

- **Option A.** ARNO is seated as a **real player entry** in the mod's `players`.
- **Player mixes:** 1–4 humans plus 0–3 ARNOs, at most 4 in total (the mod's colours
  White/Red/Blue/Yellow). Each ARNO takes a colour **no human is seated in**. The
  difficulty is set per ARNO, as in the helper. Any colour can be an ARNO, not just Yellow.
- **Regression requirement:** with 0 ARNOs the mod must behave exactly as the original,
  including the official solo challenge for 1 human. With ≥ 1 ARNO, `#players > 1`, so
  every solo path (`#players == 1`) is off automatically and the normal multi-player
  rules apply.
- **Turn order (from `Global.lua:4213–4240`):** the colour order is fixed around the
  table, and the start player is `math.random` over all `players`. Required hook: choose
  the start player among **humans only** (ARNO 3.0: a human starts). ARNOs can sit
  between humans. Starting appeal for each ARNO = (position in actual turn order − 1),
  which is the rule text "according to player order". It equals the helper's
  `bot + playerCount − 1` when all ARNOs sit after the humans.
- **Several ARNOs:** each one keeps its own card slots, upgrades, tokens, difficulty and
  project-module tracker (the helper is per-bot already). Each ARNO runs automatically
  when its turn comes, and consecutive ARNOs chain. Every seated player sees the panel
  and log. The manual trigger works for any seated player.
- **Multiplayer:** scripts run on the host, and the ARNO state lives in the host's
  checkpoint. There is no network dependency.
- **Open for multiple ARNOs (rules):** in a break, the order in which several ARNOs draw
  their 3 cards. Proposal: turn order starting after the player who triggered the break.
  To confirm against the 3.0 rules.

### Before Phase 2, please decide or answer

1. **Choose an option** (my recommendation is A).
2. Open rule questions from `ARNO_LOGIC.md` §9:
   - ARNO **2.0 or 3.0**?
   - What does **DONATE** do?
   - Association fallback: **CP 1 (code) or 2 (prose)**?
   - **Marine Worlds** and **project module** in scope?
   - Auto-reroll an unavailable zoo/university?
   - Definition of **"missing most"**?
   - The `[absent]` rules: action order, a break in the middle of ARNO's turn, no project
     possible, reputation over 15, ARNO's worker return, the purpose of the kiosk count.

   If you can, put the ARNO 3.0 rules PDF in `reference/`. The PDFs cached for the
   reference table are the base-game rulebook, glossary and icon sheet, not ARNO's rules.
3. **Two 5-minute probes in TTS** (I'll provide the snippets):
   - A, risk 1: does `Player.Yellow.getHandObjects()` work with nobody seated?
   - B only: can `WebRequest.get("http://127.0.0.1:PORT")` reach a local server on your
     TTS v14?
4. Phase 3 prerequisite: Node ≥ 20.19 (you have 20.18) to run the helper's tests.
