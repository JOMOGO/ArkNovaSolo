# Plan: a real AI opponent that plays through the player's systems

Status: **plan for review**, nothing built yet. References: `src/Global.lua:<line>` (master),
`MOD_ARCHITECTURE.md`, `MOD_PRIMITIVES.md` (§0 "ten things that will bite"), `DESIGN.md`
(hooks H1-H21, rulings), `DECISION.md` (§2 TTS WebRequest facts).

## 0. What "the same systems" means here

ARNO is an automa. He has no hand, no money and no action strength, and he never sees a
panel. His adapter writes the outcome straight onto the table with the mod's internal
primitives (`apply_cp`, `take_partner_zoo`, `break_x(n, nil)`, a bot rep routine ...).

The AI player is the opposite: **a full player seat that plays by the human rules, through
the human's entry points.** It holds a hand, pays money, draws, uses all 5 action cards at
their strength, upgrades them, takes X-tokens, places tiles on its own map, and answers every
panel the mod shows for its colour by calling the same handler a click calls:
`on_*_clicked(nil, value, nil)` and `onObjectPickUp(color, obj)`.

Why this is the right cut:

- The mod enforces the rules by **which buttons it shows**, not in the mutators
  (`DECISION.md` §1.4). If the AI acts only through the buttons, it cannot cheat or break the
  game state. Every rule, card effect and base-mod fix applies to it for free.
- It is already proven headless: `tests/lua/int_cards.lua` `drive()` plays a human turn
  through each of the 281 cards. It reads `active_panels[color]`, parses the panel XML and
  calls the handlers. **The AI is `drive()` with a policy instead of "first choice"**,
  promoted from test code into the mod.

The decision layer is a plug-in (§4). v1 is a heuristic policy inside the mod. A second
reading of the request, an opponent whose decisions come from an LLM such as Claude, is then
a different policy behind the same interface (M5). It needs no other change.

## 1. Architecture

```
arno/ai/                  bundled with arno/ (one bundle, same require, strict globals)
  seat.lua                setup: a full players entry for an unseated colour (§2)
  hand.lua                hand access for a colour nobody sits in (§2, probe P1)
  driver.lua              panel watcher + dispatcher: which panel is open, answer it (§3)
  panels/*.lua            one enumerator per panel kind: legal choices + how to apply one
  snapshot.lua            the AI's view of the game as plain tables (§4)
  policy/heuristic.lua    v1 decision layer: (snapshot, panel, choices, intent) -> choice
  policy/random.lua       random legal choice (tests, milestone M1)
  intent.lua              the turn plan chosen at action selection, which sub-panels follow
  eval.lua                state evaluation used by the heuristic policy
```

Hooks follow `arno/adapter/hooks.lua` (`wrap(id, name, make)`). Each one is a no-op unless an
AI seat is in the game, so **0 AIs means the base mod unchanged** (`DESIGN.md` §1 goal). Each
one gets a row in `CHANGES.md`.

## 2. The seat

A real `players` entry like a human's: the fields from `setup_game` (`Global.lua` ~4084),
`steam_name = "AI <colour>"`, `is_ai = true` (saved via `cnsts.saved_player_fields`, as H15
does for `is_arno`).

Reused from ARNO:

| Piece | ARNO code |
|---|---|
| setup-panel row per unseated colour (Off / ARNO 1-10 / **AI easy-normal-hard**) | H1 `setup.extend_setup_panel` |
| adding the entry to `players` | H2 `setup.add_bots` |
| keeping an unseated colour's board, cloning the start kiosk one seat at a time | H5 `setup_player_maps` wrapper, `prepare_bot` |
| a human is the starting player (or random, owner's choice) | H3 |
| persistence of AI state in checkpoints | H15 (`saved_globals`) |
| panel and log | `ui/panel.lua` |

The difference from ARNO: the AI **takes part in the simultaneous prompts** instead of being
held out of them by the humans-only window (`setup.open_window`, H5-H7). These are the map
choice, the setup discard (keep 4 of 8, `start_setup_discard` 8251), the Marine Worlds draft,
the break-time hand limit (`break_phase_discard` 12190), income (`start_player_income` 12386 /
`render_income_table` 12505) and the final scoring discard (`start_final_scoring` 12979).
So MOD_PRIMITIVES §0 items 1-8 do not apply to the AI at all. They exist only because ARNO
skips the human flow.

**Hand (probe P1).** The mod reads hands with `Player[color].getHandObjects(index)` in about
20 places (5285 ... 15657) and deals with `obj.deal(n, color, index)`.

- If TTS keeps a working hand zone for a colour nobody sits in (deal into it, read it back):
  use it as is. Check that its cards are hidden from the humans.
- If not: an AI-only proxy. `Player` is wrapped so that, for an AI colour,
  `getHandObjects(i)` returns the cards in a hidden holding zone behind the AI's board, and
  `deal` puts them there. The headless harness already swaps `Player` the same way
  (`sim.hand_players`).

## 3. The driver

**Trigger.** Wrap `set_player_panel` / `set_active_panel` (7908, 7951). When an AI colour
gets a panel, schedule one answer on the next frame. When it gets several in a row, it answers
one step per frame (MOD_PRIMITIVES §0.10: zone contents lag a frame behind moves). Things the
AI must answer that open no panel (the snap / rep-draw / shark / digging prompts expect a
pick-up) get `onObjectPickUp(color, obj)`, as in `drive()`.

**Watchdog.** If it is the AI's turn, no AI panel is open, nothing is queued in `Wait` and the
turn has not ended for N seconds: log it, say it in chat, and click the open panel's
Pass/Back if there is one. Otherwise show a "Continue AI" button on the AI panel. A stuck
AI must never be a silent hang.

**Panels and their choices** (`drive()` already handles the first group):

| Panel | Choices | Apply |
|---|---|---|
| claims (`render_claims_table` 13614) | each claim of the top sub-table, Pass if allowed | `on_claim_button_clicked(nil, "C_i")` / `on_claim_pass_clicked` |
| card selection (8057) | subsets of `selection_panels[c].pool` of size `num` (or up to) | `onObjectPickUp` per card, Confirm / Cancel |
| tile placement (16062) | every cell set × rotation with `map:canPlace` + `placement_meets_requirements` (17292) | move the tile with `tile_object_transform_for_cells` (17753), `refresh_placement_validity`, Confirm |
| snap / rep draw / shark attack / digging / mark | the display slots the state allows | `onObjectPickUp(color, display_cards[i])`, Confirm / Pass |
| project support | project × slot × cube (× animal for release) | the 4 `on_project_support_*` handlers |
| card flip | the not-yet-upgraded action cards | `on_card_flip_clicked` |
| rescue | confirm / discard | `on_rescue_*` |
| **action selection** (10178 / 10208) | the 5 slots, X-tokens to add, multiplier, persistent-reward tokens | `on_action_card_button_clicked(nil, "C_slot")` and its token buttons |
| **animals** (`animal_panel_xml` 10780) | hand/display animals with `is_animal_playable` (10510), enclosure per card (`valid_animal_enclosures` 10302), discount / condition token | pick-up + enclosure + Confirm / Pass |
| **sponsors** (14618), **build** (15908), **association** (9763), **cards** (15666) | that action's offers (sponsor cards, tile kinds, the 4 tasks, draw/snap) | the panel's own buttons |
| income table, setup discard, MW draft, break discard, final scoring discard | as the panel offers | their handlers / pick-ups |
| map choice, solo difficulty | fixed by setup (the AI plays map A at first; see §6) | |

The generic fallback stays. Any panel the driver does not model has its buttons
parsed from the XML (`onClick="fn(arg)"` + label). The policy then picks among them, with Pass/Back as
the safe default. A new base-mod panel degrades the AI's play but cannot lock it up.

## 4. Decisions

**Interface.** `policy.choose(snapshot, panel_kind, choices, intent) -> choice`. Pure Lua, no
TTS calls, so it runs and is tested headless.

**Snapshot.** Hand (card numbers → `cnsts.cards`), display 1-6 with costs
(`animal_play_cost` 10279), money, income, appeal/CP/rep/X, icons, action cards (slot,
upgraded, tokens), `player.map` (HexBoard queries), partner zoos, universities, workers,
projects and open slots, break track, the opponents' public state. Legality comes from the
mod's own predicates (`*_action_available`, `is_animal_playable`, `findValidPlacement`).
The snapshot never reimplements a rule.

**Two levels**, because Ark Nova turns are multi-step:

1. **Intent at action selection.** For each available action card at its strength (and with
   X-tokens), list the macro-moves: "play animal 412 into the size-3 enclosure", "build a
   size-4 enclosure + kiosk next to the 2 empty ones", "support project Africa on slot 2",
   "snap display slot 1", "sponsor 222". Score each with `eval` and keep the best as `intent`.
2. **Sub-panels follow the intent.** The animal panel picks the card the intent named, tile
   placement picks the cells it named, and so on. Panels with no intent (claims, rewards,
   break discard) use a local greedy rule: take the reward with the highest `eval`
   gain, and keep the cards with the best value for the current plan.

**Evaluation (v1, hand-written).** The distance between appeal and CP on the final scoring
track (the score), plus weighted income, money, reputation, icons toward projects and
partner-zoo/university value, free enclosure space against animals in hand, action-card
strength (an upgrade), X-tokens and the tempo to the break. Weights live in one table.

**Levels.** Easy = noise on the scores + a 1-turn horizon. Hard = no noise, a lookahead on
the break and the end game, and card valuation that accounts for the final scoring cards.

**Tuning offline.** The headless harness plays whole games in a few seconds. Self-play
(AI vs AI, AI vs ARNO level N) over hundreds of seeds tunes the weights and gives each level a
measured strength ("hard beats ARNO 6 in x% of games"). No in-TTS sandboxing or rollouts:
the mod's state is global and physical, so lookahead runs on the snapshot only.

**Determinism and rewind.** The AI's RNG is seeded in the saved state and keyed by
(seed, turn, panel step), like ARNO's. A rewind to the turn checkpoint
(`DECISION.md` §1.5) replays the same choices. The intent is not saved: it is recomputed
from the snapshot at the turn start, which gives the same result.

## 5. Tests

On the built Global, with `sim_lib` as today:

1. **No stall (gate for M1):** random policy, N seeded full games (1 human-driver + 1 AI,
   AI + AI, AI + ARNO, base and Marine Worlds) to the final scoring, with no Lua error, stall
   or unanswered panel. This uses the `drive()` stall rules.
2. **Enumerators:** for each panel kind, every choice the enumerator lists is one the mod
   accepts (Confirm becomes possible), and on fixtures nothing the mod offers is missing.
3. **Every card through the AI:** `int_cards.lua` run with the AI driver instead of the test
   driver.
4. **Policy unit tests** on snapshots: the obvious move wins (affordable animal + free
   enclosure + appeal), and no illegal intent.
5. **Replay determinism:** the same seed gives the same game, also after a resume from a
   checkpoint.
6. **Strength report** (not a pass/fail): win rates per level against ARNO levels.
7. Strict globals and the "0 AIs = base mod" build check, as today.

`TESTING.md` gets an in-TTS checklist: a seat in each colour, a rewind mid-turn, a break with
the AI over the hand limit, game end and scoring, MW draft.

## 6. Milestones

| # | Deliverable | Gate |
|---|---|---|
| M0 | Probes P1-P3 in TTS | answers written into this doc |
| M1 | Seat + hand + driver + random policy | test 1 green for 200 seeds, base + MW |
| M2 | Snapshot, intent, heuristic policy, 3 levels; in TTS 1 human + 1 AI | tests 2-5; one full game played in TTS |
| M3 | Mixed tables: 1-3 AIs, with ARNOs and humans; map choice for the AI (best map for its start, or random) | tests in every mix; TESTING.md checklist |
| M4 | Tuning and strength report; Workshop release | report in this doc |
| M5 (optional) | LLM policy: the same interface, sent to a local bridge over `WebRequest` (host only, `DECISION.md` §2), one request per intent, timeout → heuristic fallback | probe P4; not deterministic, so a rewind keeps the fallback's choice |

## 7. Open questions, each with how to settle it

| # | Question | Settle by |
|---|---|---|
| P1 | Can cards be dealt to and read from the hand of a colour nobody sits in, and are they hidden from the humans? | 5-minute TTS probe: `card.deal(1, "Yellow")`, `Player.Yellow.getHandObjects()` |
| P2 | Does moving a placement tile by script and calling `refresh_placement_validity` in the next frame behave as a human drag does (the building-tile script callbacks)? | TTS probe on one build; headless already passes with fakes |
| P3 | How long does enumerating every placement of a size-5 tile on a late-game map take in MoonSharp? | timing in the headless runner (same interpreter); cap the candidates if it is over ~50 ms |
| P4 | Does TTS v14 allow `http://127.0.0.1` WebRequests? (only for M5) | the probe already listed in `DECISION.md` §2 |
| Q1 | Interactive effects a human aims at the AI (hypnosis, pilfer): which colour gets the panel? | read `hypnosis` 8707, `start_pilfer` 8765, `pilfer_panel_xml` 8796; test |
| Q2 | Solo challenge (`#players == 1`, 27 cubes): an AI makes it a 2-player game. Keep the challenge only for no-AI games? | owner decision; default: yes |
| Q3 | Names and labels: "AI" next to "ARNO" in the setup panel and the Workshop text | owner decision |
