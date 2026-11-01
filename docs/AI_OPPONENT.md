# Plan: a real AI opponent that plays through the player's systems

Status: **in development** on branch `ai-opponent` (progress: §8). References: `src/Global.lua:<line>` (master),
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
  opponent_model.lua      what each opponent collects, needs and how fast they go (Expert, §4)
  levels.lua              per level: point budget, personality, opponent inputs, lookahead depth
  forward.lua             simplified model of one own turn on the snapshot, for lookahead (§4b)
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
| setup-panel row per unseated colour (Off / ARNO 1-10 / **AI Easy, Medium, Hard, Expert**; the level is saved with the seat) | H1 `setup.extend_setup_panel` |
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
projects and open slots, break track, the opponents' public state (never their hidden cards,
see Fair play below). Legality comes from the
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

**Owner's goals for the ends of the range:**
- **Easy is a beginner who knows the rules.** It never plays an illegal or senseless move (the
  mod's panels only offer legal ones, and the point budget keeps it from the worst), but it
  plays without much plan or foresight.
- **Expert aims to be the Stockfish of Ark Nova:** as strong as the hardware allows. The limits
  are real (no deep search in MoonSharp, §4a), so Expert's strength comes from the network
  and the lookahead (§4b), and the tournament measures how far it gets. Ways to push it
  further, each kept only if it wins in the tournament: a bigger network if P5 allows it,
  more lookahead in the end game (fewer moves left), and thinking during the other players'
  turns.

**Levels.** Four, set per AI seat in the setup panel: Easy, Medium, Hard, Expert. **All four
use the same trained network** (§4a). The lower levels are weaker because they play below
their best on purpose, not because they think less. Every level plays by the same rules
with the same resources: **no level gets extra money, cards or CP** (unlike ARNO 7-10). A
level is only a parameter table for the same code, so there is one code path to test.

How a level plays below its best:

1. **A point budget per move (the main control).** The network estimates each legal move
   in points of final score (§4a). Expert takes the best move. A lower level has a budget
   of points it may give up per move. It picks at random among the moves within that
   budget of the best one, and never a move below it.
   - It controls exactly what the levels are about: how much lower the average score
     is. The budget is set in points, not through a knob that has to be guessed.
   - The mistakes land where people make them. When one move is clearly best, every other
     move is far below it and outside the budget, so even Easy finds it. When several
     moves are close, the level errs, which is where real players differ too.
   - No single silly move throws the game.
2. **A personality for Easy and Medium.** At the start of a game, the level draws one simple
   plan: "lots of animals", "conservation projects first", "build and income", "sponsors".
   Moves that fit the plan get a bonus in points on top of the network's estimate, so
   it plays the plan a bit stubbornly, even when the cards, opponents or display call for
   something else. That is how a beginner loses: by not adapting, not by misclicking. And
   each game feels different. The bonus also stays within the budget, so it cannot lead to
   a silly move.
3. **Easy ignores the opponents.** The only blind spot kept: the opponents' inputs are set
   to "unknown", so Easy does not deny cards or race for project slots. It looks natural.
   Blind spots such as "ignores the break track" are not used: they make the AI throw away
   its hand at every break, which looks broken, not weak.

| | Easy | Medium | Hard | Expert |
|---|---|---|---|---|
| Point budget per move (starting values; set by measurement) | ~6+ | ~3-4 | ~1-2 | 0 (always the best) |
| Looks ahead (own turns, §4b) | 1 (this turn) | 2 | 3 | 4 |
| Personality | strong bonus for its plan | light bonus | none | none |
| Opponents | ignored | seen | seen | **read and countered during the game** (below) |

**Never weaker at the end.** In the last 2-3 turns (once the game end is in sight) every
level plays with the budget of the level above, so a game is never thrown in its last
turns and feels honest to the end.

**Expert adapts to the player during the game.** Expert does not get easier or harder
to keep the game close (that is not what adapting means here). It plays at full strength
and reads what each opponent is doing, then plays against it. An `opponent_model.lua`
module keeps per opponent, from public information only:

- what they collect: icons, continents, categories, the enclosures they have built;
- which conservation projects and slots they qualify for or nearly qualify for;
- which display cards fit their zoo, so taking or snapping one denies them something;
- their pace: how fast their appeal and CP grow, so how many turns until they can end
  the game. Expert then times its own end game against theirs;
- their likely final scoring goal, guessed from what they play (Expert never sees the card);
- the effects they have that can hit it (pilfer, hypnosis, venom, constriction).

This feeds the network as extra inputs. The network learns how much each one is worth by
training against many opponent styles: the Easy and Medium personalities and ARNO make a
varied training field, so Expert learns to recognise a style and counter it.

**All public information (owner).** The AI has access to everything a player at the table
can see: every player's counters, upgrades, workers, partner zoos and universities, played
cards, maps, icons, hand sizes; the display, the projects and their slots, the association
board, the break track, pile sizes. It also knows its own hand and final scoring cards. The
network gets it summarised (network inputs version 3, `ai/features.lua`).

**Fair play.** No level ever sees hidden information: not the humans' hands or final scoring
cards, not the deck order. The snapshot only contains what a player at the table could
see, plus the AI's own hand and cards. The mod has all of it in memory; `snapshot.lua` is
where this is enforced, and a test checks that two games that differ only in hidden
information give the AI the same snapshot.

**Backup: earlier versions of the network.** Training saves the network several times along
the way, and an early version is naturally weaker. It learns the obvious things first (play
animals, earn income) and the subtle ones last (timing the game end, denying the opponent),
roughly as people improve. If the budgets and personalities alone do not make the levels
feel different enough, Easy and Medium use an earlier version instead (about 100-150 KB
extra in the save per version). It cannot be set as precisely, so it is measured the same way.

**Calibrated on the average score.** The budgets and personality bonuses in the table are
starting values. For each level, headless games measure its average final score and win
rate. The budgets are then adjusted until the levels sit at even steps below Expert, each
beating the one below in about 65% of games. ARNO gives a fixed yardstick ("Medium ≈ ARNO
5"); the real numbers come from the measurements.

The random picks and the personality draw come from the seeded RNG, so a rewind replays the
same game at every level (§4, determinism).

**One consequence: no level ships before the network.** The hand-written evaluation is
still built (M2), but only to bootstrap the training games, as the fallback if the network
cannot load, and as a sanity check ("the network beats the formula"). It is not a level in
the setup panel.

**Tuning offline.** The headless harness plays whole games (speed still to measure, P6). Self-play
(AI vs AI, AI vs ARNO level N) over hundreds of seeds tunes the weights and gives each level a
measured strength ("hard beats ARNO 6 in x% of games"). No in-TTS sandboxing or rollouts:
the mod's state is global and physical, so lookahead runs on the snapshot only.

**Determinism and rewind.** The AI's RNG is seeded in the saved state and keyed by
(seed, turn, panel step), like ARNO's. A rewind to the turn checkpoint
(`DECISION.md` §1.5) replays the same choices. The intent is not saved: it is recomputed
from the snapshot at the turn start, which gives the same result.

## 4a. A neural network in place of the hand-written evaluation

Goal: a stronger AI that still runs on any PC, inside the save, with nothing to install.
No GPU, no local AI program, no internet.

**The rules stay in the mod.** The network never learns the rules or generates moves. The
mod's panels and predicates list the legal choices (§3), and the network only replaces
`eval.lua`: it scores the position after each candidate intent, and the best score wins. A
badly trained network can play weakly but never illegally.

**Measured cost** (MoonSharp, the TTS interpreter, plain Lua MLP with flat weight arrays,
2 ReLU hidden layers, 1 output; `tools/moonsharp` runner on the owner's PC, 2026-10-31):

| Network | Weights | Per evaluation |
|---|---|---|
| 200 inputs, 2 × 64 | 17k | 7 ms |
| 300 inputs, 2 × 128 | 55k | 22 ms |
| 500 inputs, 2 × 256 | 194k | 84 ms |

That is about 2.3 M multiply-adds per second. Conclusions:

- A **~200 × 64 × 64** network fits. With 30-80 candidate intents per turn that is
  0.2-0.6 s of thinking. Tiny networks for the sub-panels (claims, discards) cost less.
- **Spread over frames.** TTS runs Lua on the main thread, so a 0.5 s loop freezes the
  table. The driver scores a few candidates per frame (a coroutine resumed by `Wait.frames`)
  and shows "AI is thinking".
- **Sparse inputs.** Cards in hand, the display and the played cards are one-hot. The first
  layer only adds the columns of the inputs that are set, which makes it several times cheaper
  than the dense benchmark.
- **No big networks, no full tree search** (AlphaZero style): too slow in MoonSharp, and the
  mod's state cannot be cloned to search on. A narrow lookahead on a simplified model of
  its own next turns does fit (§4b).
- Speed in TTS itself still has to be measured (probe P5). If it is slower, use fewer
  candidates (pre-filtered by the heuristic) or a smaller network.

**Size.** 17k weights saved as numbers rounded to 3-4 digits come to about 100-150 KB of
Lua text in the save. That is fine.

**Training happens offline, once, on the developer's PC.** Players only get the finished
weights.

1. Play many headless games with the heuristic AI (M2) through the existing harness. Log the
   feature vector of each position and the final score difference.
2. Fit the network to predict the outcome (supervised, Python/PyTorch on the logs). Export
   the weights to a generated Lua table (like `tools/gen_cards_data.py` does for ARNO's
   cards).
3. Self-play with the network, then retrain on the new games. Repeat while the strength report
   improves.
4. Release only once Expert clearly beats the hand-written evaluation. Until then,
   train more (more games, better inputs from the checklist in §4c).

Open point: self-play speed. Games run in the slow interpreter too, so training needs many
games in parallel processes (overnight runs). Measure games per hour first (P6).

The network drives every level (§4, Levels). Easy to Hard cost the same to run as Expert
(they score as many or fewer moves).

## 4b. Looking ahead: higher levels see more turns

Each level higher looks one more of **its own turns** ahead: Easy 1 (only this turn), Medium
2, Hard 3, Expert 4.

**What it looks ahead on.** The mod's real state cannot be copied to try moves on (it is
global and has physical objects), so lookahead uses `forward.lua`: a simplified model of a
turn on the snapshot. It covers what matters most for planning:

- action-card rotation: the card used goes to slot 1 and the others move up. This part is
  exact, and it is the main reason to look ahead ("use the weak card now, so Animals is at
  strength 5 next turn");
- money, income, appeal, CP, reputation and X-tokens from the move;
- enclosures filled and space left, cards leaving the hand or display;
- the break track and the income at the break.

Card effects are only approximated (their main reward). The network then scores the
position at the end of each line, so the model only has to get it roughly right.

**Opponents in the lookahead.** It cannot simulate them: that needs their hidden cards. The
lookahead assumes they make no move, except that Expert uses its opponent model: "they will
probably take display card 3", "they reach the project slot in 2 turns".

**Cost: beam search, not a full tree.** At each depth it keeps only the best 3 lines (the
beam) and expands those:

| Depth | Positions scored (50 moves per turn, beam 3) | Time at 7 ms (headless) |
|---|---|---|
| 1 | 50 | 0.35 s |
| 2 | 200 | 1.4 s |
| 3 | 350 | 2.5 s |
| 4 | 500 | 3.5 s |

That grows linearly, not exponentially. Three things keep it usable:

- **It thinks during the other players' turns.** A human turn takes far longer than this.
  After their move, only the lines they changed (display, project slots) are rescored.
- **Sparse first layer** (§4a): several times faster than these dense timings.
- **A fixed count, not a time limit.** Each level scores a fixed number of positions, so a
  slow PC waits longer but plays the same moves. A time limit would make the strength (and a
  rewind) depend on the PC. If TTS turns out much slower (P5), the beam shrinks for every
  PC alike.

**Only if it helps.** Lookahead on an approximate model can also mislead. For each level,
the tournament (§5, test 6) plays depth d against depth d-1 with everything else the same.
A depth that does not win is not used, and that level gets more strength from its point
budget instead.

**Test against the real engine.** The headless harness has the real mod. For many positions,
the forward model's prediction of one move is compared with what the mod really does
(money, appeal, CP, slots, hand). The fields it claims to predict must match exactly; the
approximated ones are reported as an error rate.

## 4c. Expert checklist: what a strong player looks out for

This list has two uses:
- **Network inputs.** The network can only learn from what it is shown, so every point
  here becomes one or more input features in `snapshot.lua`.
- **Test positions.** Each point gets a few set-up positions where the strong move is
  known (test 4). Expert must find it. The weaker levels may miss it, as long as they do it
  at their measured rate.

**Score and game end**
- The real score is where appeal and CP stand against each other on the scoring track,
  not either number alone. CP are worth more per point later on (the conversion steps up),
  so CP and appeal are not interchangeable.
- Who triggers the game end, and when. Everyone else gets one more turn: end it when
  ahead, and never trigger it while behind.
- Its own final scoring card(s): what they reward and how far it is from each threshold.
- The last 2-3 turns: switch to moves that score now (appeal, CP) over moves that pay off
  later (income, cards).

**Economy and tempo**
- Income early: appeal income and buildings that pay at every break compound over the game.
- The break track: how close the break is, who will trigger it, and what it brings
  (income, refilled display, hand limit). Don't hold more cards than the limit allows.
- Money for next turn: the action it wants next must be affordable.
- Turns are the scarcest resource. A move that does two things beats two moves.

**Action cards**
- The strength of each card is its slot (1-5), and a card moves to slot 1 when used. Plan
  which card will be strong next turn, and don't waste a strong slot on a weak move.
- X-tokens: bank them when there is no good move (the X action), spend them to push a key
  action over a threshold.
- Which card to upgrade when a flip comes, matched to its strategy (animals, building,
  association, cards, sponsors).

**Zoo map**
- Build enclosures that fit the animals it holds or will soon get, in the right sizes and
  next to water or rock where the animals need it.
- Special enclosures (reptile house, large bird aviary, petting zoo, Marine Worlds
  aquariums) only when the animals for them are coming.
- Map bonuses: covering bonus spaces and filling map areas.
- Kiosks and pavilions where they earn the most. Keep free space for later big buildings
  (no dead corners).

**Cards and the display**
- The value of a card depends on the plan: icons it needs for projects, sponsors that pay
  every break, animals that fit the enclosures it has.
- Reputation sets how far into the display it can reach. Higher reputation means more
  choice.
- What the opponents need from the display: take or snap a card they want when it costs
  little.
- Card effects and their timing: immediate, at every break, at the end of the game.

**Conservation and the association**
- Conservation projects: the requirement (icons, released animals) and the race for the
  better slots. Another player may take the slot first.
- Partner zoos make animals of that continent cheaper. Universities give reputation and
  science icons.
- Workers are limited. Each association task costs a worker, so choose the tasks.
- CP bonus tiles and reputation milestones: the next step that gives a bonus.

**Opponents**
- Their score, how close they are to ending the game, and which projects and display
  cards they need.
- Effects aimed at it (pilfer, hypnosis, Marine Worlds venom and constriction tokens): keep
  money and cards less exposed when those are around.

**Marine Worlds** (when enabled)
- Sea animals and the reef, aquariums, and the draft at the start: draft toward one plan.

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
   enclosure + appeal), no illegal intent, and the §4c test positions (Expert finds the
   strong move).
5. **Replay determinism:** the same seed gives the same game, also after a resume from a
   checkpoint.
5a. **No hidden information:** two games that differ only in the humans' hands, final
   scoring cards or the deck order give the AI the same snapshot.
5b. **Expert counters:** set-up positions where the opponent needs a display card or a
   project slot; Expert takes it when it costs little.
6. **Tournament and strength report.** Every level plays every other level and the ARNO
   levels, in 2- and 3-player games, with the seats rotated (start player matters) and over
   many seeds. Out of it come:
   - a rating per level (Elo), plus average final score and win rate against each opponent;
   - the ladder check: each level beats the one below in about 65% of games, and the steps
     in average score are about even;
   - the lookahead check (§4b): each level against itself with one step less;
   - a regression check: a new network or new settings must not lose rating against the
     previous release.
   It gates the release (M4b) and is rerun after every training round.
6a. **Forward model vs the real mod** (§4b): one move predicted against one move played.
7. Strict globals and the "0 AIs = base mod" build check, as today.

`TESTING.md` gets an in-TTS checklist: a seat in each colour, a rewind mid-turn, a break with
the AI over the hand limit, game end and scoring, MW draft.

## 6. Milestones

| # | Deliverable | Gate |
|---|---|---|
| M0 | Probes P1-P3 in TTS | answers written into this doc |
| M1 | Seat + hand + driver + random policy | test 1 green for 200 seeds, base + MW |
| M2 | Snapshot (with the §4c inputs), intent, hand-written evaluation (bootstrap only, not a level); in TTS 1 human + 1 AI | tests 2-5; one full game played in TTS |
| M3 | Mixed tables: 1-3 AIs, with ARNOs and humans; map choice for the AI (best map for its start, or random) | tests in every mix; TESTING.md checklist |
| M4 | Neural network (§4a): logging, training, Lua export, frame-spread scoring | Expert clearly beats the hand-written evaluation; the §4c test positions pass; in TTS no visible freeze |
| M4b | Levels Easy / Medium / Hard / Expert: point budgets, personalities, lookahead depth 1-4 (`forward.lua`, beam search, thinking during other turns), Expert's opponent model; calibrate in the tournament; Workshop release | each level beats the one below in ≥ ~65% of games; report in this doc |
| M5 (optional, only for players with a local AI) | LLM policy: the same interface, sent to a local bridge over `WebRequest` (host only, `DECISION.md` §2), one request per intent, timeout → heuristic fallback | probe P4; not deterministic, so a rewind keeps the fallback's choice |

## 7. Open questions, each with how to settle it

| # | Question | Settle by |
|---|---|---|
| P1 | Can cards be dealt to and read from the hand of a colour nobody sits in, and are they hidden from the humans? | 5-minute TTS probe: `card.deal(1, "Yellow")`, `Player.Yellow.getHandObjects()` |
| P2 | Does moving a placement tile by script and calling `refresh_placement_validity` in the next frame behave as a human drag does (the building-tile script callbacks)? | TTS probe on one build; headless already passes with fakes |
| P3 | How long does enumerating every placement of a size-5 tile on a late-game map take in MoonSharp? | timing in the headless runner (same interpreter); cap the candidates if it is over ~50 ms |
| P4 | Does TTS v14 allow `http://127.0.0.1` WebRequests? (only for M5) | the probe already listed in `DECISION.md` §2 |
| P5 | Network speed inside TTS (same MoonSharp, but in Unity) | time 100 evaluations from a button in TTS, compare with the 7 ms headless |
| P6 | Headless games per hour on one core (training data) | time the existing full-game soak |
| Q1 | Interactive effects a human aims at the AI (hypnosis, pilfer): which colour gets the panel? | read `hypnosis` 8707, `start_pilfer` 8765, `pilfer_panel_xml` 8796; test |
| Q2 | Solo challenge (`#players == 1`, 27 cubes): an AI makes it a 2-player game. Keep the challenge only for no-AI games? | owner decision; default: yes |
| Q3 | Names and labels: "AI" next to "ARNO" in the setup panel and the Workshop text | owner decision |

## 8. Progress

| Date | Step | Result |
|---|---|---|
| 2026-10-31 | M1 start: `arno/ai/` seat, inputs, choices, random policy, driver; hooks AI1 (`set_active_panel`), AI2 (`start_player_turn`) | `tests/lua/int_ai.lua`: 300 single AI turns from random positions (money, hand, display, upgrades, card order, base and Marine Worlds) and 40 chains of 20 turns in a row with the real end of turn, all ending cleanly; every other suite unchanged |

Found on the way:
- **"Acting too fast races the mod" was a test fake.** The reputation-draw crash came from fake
  cubes without a colour tag (the display-mark payout found no owner). The driver still waits
  until the mod has reacted to each input and stays still for a few frames (§3).
- **Not every button does something.** An animal that cannot be played still gets a
  Confirm button, which does nothing. The driver remembers inputs that changed nothing and
  does not retry them for the same view; buttons with the same text (+/- of every row) get
  their argument added so they are told apart.
- **Base-mod dead ends a human can reach too** (the AI avoids them; suggested fixes, not
  changed): BUILD is offered with only 2 money checked (`build_action_available`), then
  "nowhere to build, use rewind", without Back when the card carries a venom token; the
  end-of-turn venom fee cannot be paid with less than 2 money and has no other button; the
  animal panel offers every animal in hand and Confirm on one that cannot be played does
  nothing (and ends H20's Back offer).
- **Possible base-mod issue (unverified):** `scavenging` and `deal_tagged_card` take cards from
  the discard pile without checking it has enough. With an empty discard pile the headless
  run failed; whether TTS fails the same way needs a check in game.
- **The mod never reshuffles the zoo deck.** Random play over 250+ turns can empty it; a real
  game ends long before.

| Date | Step | Result |
|---|---|---|
| 2026-10-31 | Whole games headless (`sim.ai_table`, `tests/lua/int_ai_games.lua`) | 2-4 AI seats play to the final scoring, ~3 s per game (P6: ~1000 games per hour per core) |
| 2026-10-31 | Setup (`tests/lua/int_ai_setup.lua`) | setup row Off / ARNO 1-10 / AI Easy-Expert; AI seats as full players; setup discard, draft, classic/custom map steps (AI3-AI5) |
| 2026-10-31 | Hand-written policy (`ai/value.lua`, `policy.heuristic`) | beats random 94.8 vs 67.4 average (20 games) |
| 2026-10-31 | Network round 0: 1500 self-play games of the hand-written policy (budgets 1 and 3), 765k decisions; target = margin change over the next 10 own decisions (the final margin gave no signal) | Q network 85 inputs, 64-64 hidden, 9.7k weights: **beats the hand-written policy +31.7 average margin, 89% of 99 games** |
| 2026-10-31 | Round 1 (network self-play) | stopped by the system (low memory while idle); not restarted |
| 2026-10-31 | Levels calibrated (budgets Hard 0.8, Medium 1.3, Easy 1.6; personalities for Easy and Medium) | ladder below; 0 stalls in the last 200 games |
| 2026-10-31 | The base-mod dead ends found by the AI fixed in the mod (FIXBUILD, FIXVENOM, FIXANIMAL, FIXSCAV, FIXPILE; on master) and merged in | the AI's own dead-end filter removed; all tests pass |
| 2026-10-31 | Network round 1: 1500 games of the round-0 network against itself (budgets 1 and 2), trained on rounds 0+1 (1.5M decisions) | **beats round 0: +17.0 margin, 68% of 100 games**; bundled |
| 2026-10-31 | Ladder with the round-1 network (same budgets), 100 games each | Expert vs Hard +15.5 (66%), Hard vs Medium +13.4 (67%), Medium vs Easy +15.3 (65%): even steps, 0 stalls in 300 games |
| 2026-10-31 | Round 2: 1500 games of the round-1 network, trained on rounds 0-2 (2.2M decisions) | **no gain**: −4.3 vs round 1 (49%, noise); round 1 stays. One game looped in a cube allocation: now a fixed rule (+ until placed, then Confirm) |
| 2026-10-31 | Wider network (128-128, 27.6k weights) on rounds 0-2 | +3.2 vs round 1 (53%, noise): size is not the limit |
| 2026-10-31 | Network inputs version 2 (the leader, both zoos' icons, the display, icon fit of a card); round 3 self-play logs them | v2 and v3 networks lose to round 1 (§10) |
| 2026-11-01 | Round 5 network: v1 inputs trained on every round (0-4, 3.7M decisions; later rounds cut to the v1 inputs), horizon 20, lr 3e-4, best of 24 epochs (13) | **beats round 1: +22.9 / 72% (100 games), confirmed +24.5 / 72% (200 games)**; bundled |
| 2026-11-01 | Ladder with the round-5 network (same budgets), 100 games each | Expert vs Hard +16.8 (66%), Hard vs Medium +12.5 (66%), Medium vs Easy +15.2 (67%): even steps, 0 stalls in 300 games |

Ladder (2-seat games, seats swapped, `tools/ai_train.py match`; a margin is the average
final score difference; ±4 points is noise at 100 games):

| Pairing | Games | Margin | Win |
|---|---|---|---|
| Expert vs Hard | 80 | +14.6 | 67% |
| Hard vs Medium | 100 | +7.8 | 61% |
| Expert vs Medium | 100 | +12.0 | 61% |
| Medium (1.05) vs Easy | 80 | +13.8 | 60% |
| Expert vs Easy | 100 | +32.6 | 80% |
| Easy vs hand-written policy | 80 | +14.1 | 73% |
| Expert vs hand-written policy | 99 | +31.7 | 89% |

The order holds; the steps are uneven (Easy stands out further below). The plan's next
strength steps, not done yet: more training rounds (network self-play, §9), the lookahead
(§4b) and Expert's opponent model (§4 Levels), each kept only if it wins in the ladder.

## 9. Training the network

```
python tools/ai_train.py play  --games 1500 --seats heuristic:3,heuristic:1 --out build/ai/round0.txt
python tools/ai_train.py train --data build/ai/round0.txt --horizon 10 --out arno/ai/net_weights.lua
# the bundled network (round 5): every round, v1 inputs, horizon 20
python tools/ai_train.py train --data build/ai/round0.txt --data build/ai/round1.txt --data build/ai/round1b.txt --data build/ai/round2.txt --data build/ai/round3_v2.txt --data build/ai/round4_v3.txt --inputs 1 --horizon 20 --lr 3e-4 --epochs 24 --out build/ai/r5.lua
python tools/ai_train.py match --games 100 --seats network:0,heuristic:0 --weights arno/ai/net_weights.lua
python tools/ai_train.py match --games 60 --seats expert:0,hard:0 --workers 4
```

A next round plays the current network against itself with budgets (`network:1,network:3`),
trains on all rounds and keeps the new weights only if they beat the old ones in `match`.
Use `--workers 4` when the machine is short of memory (each worker is one MoonSharp process).

## 10. Improvement loop (hand-over)

Started 2026-11-01 ~01:30 on the owner's request: keep improving the AI for 24 hours. Anyone
(a new chat) can pick this up from here; the state is in git (branch `ai-opponent`) and in
`build/ai/` (training data, not in git).

The loop, one round at a time:
1. **Play:** the best network plays itself with budgets 1 and 2, logging the current input
   version (`features.VERSION`, now 3):
   `python tools/ai_train.py play --games 1500 --first <new seeds> --seats network:1,network:2 --weights arno/ai/net_weights.lua --workers <n> --out build/ai/roundN_v3.txt`
2. **Train** on every round with the same input version:
   `python tools/ai_train.py train --data build/ai/round4_v3.txt [--data ...] --horizon 10 --out build/ai/rN.lua`
3. **Check** against the bundled network, 100 games:
   `python tools/ai_train.py match --games 100 --first <new seeds> --seats network_b:0,network:0 --weights-b build/ai/rN.lua --workers <n>`
4. **Keep it only if it wins** (average margin > +5 and win rate > 55%): copy to
   `arno/ai/net_weights.lua`, run `python tools/run_tests.py --skip-node --quick -k int_ai`,
   re-check the ladder (Expert/Hard/Medium/Easy, 100 games each; budgets in `ai/levels.lua`),
   rebuild the dev save, commit and push, add a row to §8.
5. Experiments when a round brings nothing: the target horizon (20, or a mix with the final
   margin: `--horizon 0`), a wider network (`--hidden 128,128`), more epochs.

Memory rule (owner, 2026-11-01): the machine is free for training (no games, no WSL), so use
it fully: 10 workers (12 cores; each worker is one MoonSharp process of ~0.6 GB, ~6 GB of
32 GB). Only if less than ~4 GB is free when starting, use fewer. If the system stops a job
for low memory, restart it at once with one step fewer workers (10 -> 8 -> 6 -> 4 -> 2) until
it runs through (owner's go, 2026-11-01). A stopped play job keeps the chunks it finished in
its --out file: keep that file, and play the remaining games on fresh seeds into a new --out
file (chunks finish out of order; `train` takes several --data files). A stopped match is
simply run again.

Seeds used so far (do not reuse for new data): 1000-2499 (round 0), 5000-5999 and 7000-7499
(round 1), 9000-10499 (round 2), 12000-13499 (round 3, inputs v2), 15000-16499 (round 4,
inputs v3); matches 100001+, 200001+, 300001+, 400001+, 500001+, 600001+, 700001+, 800001+,
900001+ (FIXPILE repro), 1000001+ ... 2300001+ (every 100000 up to 2300001; 2026-11-01 checks and ladder).

| Round | Data | Result |
|---|---|---|
| 3 | 1500 games, inputs v2 (724k decisions) | v2 network trained (r3_v2.lua); match against round 1 still to run |
| 4 | 1500 games, inputs v3 (730k decisions, `build/ai/round4_v3.txt`) | done |
| 4 check (2026-11-01) | v3 network on round 4, horizon 10. The validation error is lowest after epoch 1-4 and rises after (overfit): `train` now keeps the best epoch (`--lr` added) | all **lose** to round 1 (100 games each): lr 3e-4 (epoch 4) −13.0 / 42%; lr 1e-3 (epoch 1) −7.3 / 45%. v2 `r3_v2.lua` −2.7 / 44%. v1 inputs on rounds 0-1 again with the early stop (epoch 8) +5.0 / 53% (noise). Not kept |

The richer inputs (v2, v3) predict held-out games better but play worse: a lower validation
error does not mean better choices (the state inputs explain most of the target; the
choice inputs, which decide, get little of the network). `train --inputs 1` trains the v1
network on rows logged with a later version (an earlier version's inputs are a column
subset), so every round can feed it.

| 5 (2026-11-01) | no new games: v1 inputs on every round (3.7M decisions), lr 3e-4, early stop | horizon 10, 12 epochs: +2.7 / 52% (noise). Horizon 20, 12 epochs (kept 11): +12.1 / 62%, again +7.5 / 49%. **Horizon 20, 24 epochs (kept 13): +22.9 / 72%, confirmed +24.5 / 72% in 200 games: bundled.** Horizon 30, 24 epochs: +12.9 / 64%. v3 inputs, horizon 20 on round 4: −26.7 / 24% |

What won: more data (every round, through the v1 inputs) together with the longer horizon (20
own decisions); neither alone did. The ladder kept its steps with the same budgets (§8).
`train --baseline` (fit the state alone first, train on what the choice adds) is in but not
checked yet.

**FIXPILE stall: fixed 2026-11-01** (here and on branch `fix-pile-break-refill` from master, for
the owner's /merge): the discarded display cards are shuffled into the zoo deck with the
discard pile and count as landed there (they may even come back into the display); seed
900002 plays through. Tests in `tests/lua/int_fixes.lua`. The original note:
a heuristic game reproduced a stall at turn 208:
`python tools/ai_train.py match --games 2 --first 900001 --seats heuristic:0,heuristic:0 --workers 2`
(seed 900002; the log goes to `build/ai/failures.txt`). Both players discard down to the hand
limit at a break after the zoo deck ran out, then nothing happens. Already fixed on the way:
`departures_landed` read a discard pile that had become the zoo deck (Lua error); the test fakes
now form a deck when a card is put on a single-card pile. Look at `break_phase_display` ->
`refill_display` -> `zoo_deck_needs` / `wait_for_departures` with a short or empty discard pile.
Fix it on a branch from master (the owner merges with /merge), and in `ai-opponent`.
