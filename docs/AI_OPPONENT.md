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
| 2026-11-01 | Round 9: an ensemble of 4 networks (Q averaged: the round-5 network, r7, and two more trained alike with seeds 2 and 3) | **beats the round-5 network: +8.1 / 60%, confirmed +11.2 / 62% (200 + 200 games)**; bundled |
| 2026-11-01 | Ladder with the ensemble (same budgets), 100 games each | Expert vs Hard +18.5 (72%), Hard vs Medium +8.2 (62%), Medium vs Easy +18.5 (70%): order holds, 0 stalls in 300 games |
| 2026-11-02 | Round 11: temporal-difference targets (`train --bootstrap`, two iterations), an ensemble of 4 such networks (ens_td2) | **beats the round-9 ensemble: +9.0 / 62.5%, confirmed +12.3 / 67% (200 + 200 games)**; bundled |
| 2026-11-02 | Ladder with ens_td2 (same budgets), 100 games each | Expert vs Hard +9.0 (63%), Hard vs Medium +11.3 (57%), Medium vs Easy +10.5 (64%): order holds, 0 stalls in 300 games; Hard-Medium is the narrow step (next: recalibrate the budgets, the TD network's Q has a larger spread) |
| 2026-11-03 | Levels with the assists (build 3, cp 4; seats `expert`...), 100 games each | Expert vs Hard +9.4 (64%), Hard vs Medium +19.1 (71%), Medium vs Easy +10.2 (58%): Medium too weak |
| 2026-11-03 | Shipped: + unlock 3 / upgrade 0.5 (round 19), Medium budget 1.3 -> 1.15; 100 games each (seeds 22000001+) | Expert vs Hard +13.5 (72%), Hard vs Medium +9.1 (64%), Medium vs Easy +9.0 (59%): order holds, 0 stalls in 300 games |
| 2026-11-04 | Shipped: + xtoken 3 (round 20); 100 games each (seeds 26000001+) | Expert vs Hard +10.4 (59%), Hard vs Medium +9.2 (62%), Medium vs Easy +9.9 (62%); Expert vs ARNO 1 **−0.1 (52%)** on the table's seeds (was −8.6 / 38%), vs ARNO 3 −22.1 (17%) |
| 2026-11-04 | Shipped: + slot/discard/partner (round 24) + flip (round 25); 100 games each (seeds 31000001+) | Expert vs Hard +14.3 (68%), Hard vs Medium +8.0 (60%), Medium vs Easy +7.5 (58%); Expert vs ARNO 1 **+9.3 (57%)** on the table's seeds (was −8.6 / 38% on 2026-11-03); resumed 2026-11-06, 60 games each on the table's seeds: vs ARNO 2 **−6.1 (37%)** (was −20.6), vs ARNO 3 **−19.3 (18%)** (was −25.4), vs ARNO 5 **−34.3 (5%)** (was −41.1) |

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

AI levels against ARNO 3.0 (2026-11-03, bundled ens_td2; 60 games each, the AI starts;
`ai_train.py match --seats expert:0,arno:5`; AI's average margin and win rate). A harness
audit found it fair (ARNO's scoring, CP debt, start order, end trigger as in TTS); its two
fixes (ARNO's setup draw, the base projects' blocking cubes) landed during the sweep, so the
later rows face a slightly stronger, correct ARNO:

| AI \ ARNO | 1 | 3 | 5 | 7 | 10 |
|---|---|---|---|---|---|
| Expert | −8.6 (38%) | −23.8 (18%) | −49.2 (0%) | −55.3 (0%) | −63.8 (0%) |
| Hard | −19.5 (22%) | −43.1 (2%) | −62.7 (0%) | −72.5 (0%) | −82.2 (0%) |
| Medium | −30.7 (8%) | −49.4 (2%) | −70.2 (0%) | −81.4 (0%) | −84.4 (0%) |
| Easy | −42.3 (7%) | −58.4 (0%) | −81.5 (0%) | −85.9 (0%) | −94.2 (0%) |

With the assists (round 16, 2026-11-03): Expert vs ARNO 1 −4.7 (48%) on the table's seeds. Round 17's two further assists (final scoring card, end timing) brought nothing and are off. Round 19's two (`unlock`, `upgrade`) help against ARNO 1 and against the network without them, not against ARNO 3: off.

Shipped levels against ARNO (2026-11-03 evening: ens_td2 + assists build 3 / cp 4 / unlock 3 /
upgrade 0.5, Medium 1.15; after the harness fixes, so not strictly paired with the table above;
60 games each, the same seeds; paused by the owner before Easy vs ARNO 3 finished):

| AI \ ARNO | 1 | 2 | 3 | 5 | 10 |
|---|---|---|---|---|---|
| Expert | −5.1 (35%) | −20.6 (20%) | −25.4 (17%) | −41.1 (5%) | −61.5 (0%) |
| Hard | −9.3 (35%) | | −29.4 (5%) | | |
| Medium | −18.3 (10%) | | −38.1 (5%) | | |
| Easy | −31.5 (7%) | | −46.9 (0%) | | |

Against the first table every level gained 3-15 points against ARNO 1 and 3; Hard and below most.

Round 20 (2026-11-04, §10): the `xtoken` assist (X-tokens spent where they lift an action
card) helps against ARNO 3 (+7.0) and ARNO 1 (+5.6) at weight 3: kept, to be switched on
(`xtoken = 3` in M.ASSIST) once the running batch build/ai/r21.cmd is done. Still open: the last
line of build/ai/final.cmd (Easy vs ARNO 3).

Round 24 (2026-11-04, §10): an audit of the choices the network scores the same; three tie-break
assists (`slot`, `discard`, `partner`) together +1.3 to +3.6 against ARNO 3 and 1 on two seed sets: switched on.

Every AI level loses to every ARNO level: the AI, trained only against AIs, plays a slow
game; ARNO races (in a traced game ARNO had 105 points after 40 turns, the AI 53). The goal
(owner, 2026-11-03): Expert near unbeatable against any player; this table is the benchmark.

Round 13 (running, 2026-11-03): mixed opponents, played by td2 (budget 1), card numbers
logged: 800 games each against ARNO 3, 5, 8 (seeds 30000+, 31000+, 32000+;
`round7_arno3/5/8.txt`), 500 against the hand-written policy (33000+, `round7_heur.txt`).
Next: search labels (`ai_train.py search`, --samples 4) in the same matchups, then train on
everything and check against ens_td2 and this table.

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
2. **Train** on every round (all of them, cut to the bundled network's inputs, v1; see §9 for
   the full list of --data files):
   `python tools/ai_train.py train --data build/ai/round0.txt [--data ...] --inputs 1 --horizon 20 --lr 3e-4 --epochs 24 --out build/ai/rN.lua`
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
900001+ (FIXPILE repro), 1000001+ ... 2300001+ (every 100000 up to 2300001; 2026-11-01 checks and ladder),
2400001+ and 2600001+ (200 games each), 3000001+ ... 3400001+ (100 each), 3500001+ and 3700001+
(200 each), 3900001+ (200), 4100001+ ... 4300001+ (100 each), 4400001+ (2, smoke test),
4500001+ and 4700001+ (200 each), 4900001+ and 5100001+ (200 each), 5300001+ ... 5500001+ (ladder), 5700001+ (200), 6000001+ and 7000001+ (sweeps, 1000 each, 0 failures), 8000001+ (smoke test), 10000001+ ... 10800001+ (round 11), 11000001+ ... 11200001+ (ladder), 12000001+ and 12200001+ (round 12). Self-play 23000-27499 (round 10). Self-play: 20000-22499 (round 5). Search probes (2026-11-03): 30000001-30000003, 40000001-40000002, 40000101-40000102, 40001001-40001008, 40001101-40001106, 40001201-40001202; search labels from 40100001. Round 17 (2026-11-03): traces 91000001-91000012, 91100001-91100012, 91200001-91200008 (91300001+ started and stopped), matches 18000001+ (60 each), 18100001+ (100 each), 18900001-18900002 (smoke test). Round 19 (2026-11-03): traces 91900001, 92000001-92000024, 92100001-92100020, 92200001-92200010, 92300001-92300003, 92400001-92400002; matches 21000001+ and 21100001+ (60 each), 21200001+, 21300001+ and 21400001+ (100 each). Round 20 (2026-11-03/04): traces 93000001, 93000008, 93100001; matches 23000001+ (100), 23100001+ (60), 23200001+ (100). Round 22 (2026-11-04): traces 94000001-94000012, 94100001-94100012, 94000101-94000110, 94100101-94100108; matches 27000001+ (100), 27100001+ (60). Round 23 (2026-11-04): traces 95000001-95000010 (and 95000001-95000004 with rep 4); matches 28000001+ (100), 28100001+ (60). Round 24 (2026-11-04): traces 96000001-96000030 (ARNO 3), 96100001-96100020 (self); matches 29000001+ (100), 29100001+ (60), 29200001+ (100), 29300001+ (60), 29400001+ (100). Round 25 (2026-11-04): tie rollouts 97000001-97000120 (ARNO 3), 97100001-97100080 (ARNO 1), 97200001-97200050 (self, stopped after 32 games); matches 30000001+ (100), 30100001+ (60), 30200001+ (100), 30300001+ (60), 30400001+ (100).

| Round | Data | Result |
|---|---|---|
| 3 | 1500 games, inputs v2 (724k decisions) | v2 network trained (r3_v2.lua): −2.7 / 44% against round 1, not kept |
| 4 | 1500 games, inputs v3 (730k decisions, `build/ai/round4_v3.txt`) | done |
| 4 check (2026-11-01) | v3 network on round 4, horizon 10. The validation error is lowest after epoch 1-4 and rises after (overfit): `train` now keeps the best epoch (`--lr` added) | all **lose** to round 1 (100 games each): lr 3e-4 (epoch 4) −13.0 / 42%; lr 1e-3 (epoch 1) −7.3 / 45%. v2 `r3_v2.lua` −2.7 / 44%. v1 inputs on rounds 0-1 again with the early stop (epoch 8) +5.0 / 53% (noise). Not kept |
| 5 (2026-11-01) | no new games: v1 inputs on every round (3.7M decisions), lr 3e-4, early stop | horizon 10, 12 epochs: +2.7 / 52% (noise). Horizon 20, 12 epochs (kept 11): +12.1 / 62%, again +7.5 / 49%. **Horizon 20, 24 epochs (kept 13): +22.9 / 72%, confirmed +24.5 / 72% in 200 games: bundled.** Horizon 30, 24 epochs: +12.9 / 64%. v3 inputs, horizon 20 on round 4: −26.7 / 24% |
| 6 (2026-11-01) | 2500 games of the round-5 network (budgets 1 and 2; seeds 20000-22499; 1.12M decisions, `round5_v3.txt`; budget 1 beat budget 2 by +30.9 / 80%). Trained on every round (4.8M), same recipe | r6 (kept epoch 19) −0.2 / 52%; 128-128 (epoch 10) −8.3 / 43% (200 games each): not kept |
| 7 (2026-11-01) | same data; validation now every 10th game of every round (was the first 10% = round 0 only); epoch snapshots | 100 games each: e8 −7.6 / 43%, e12 +0.6 / 51%, e16 +9.0 / 63%, e20 −2.1 / 48%, e24 −3.2 / 52%. Confirmed on fresh seeds (200 games): e16 +3.6 / 56%, e15 (validation best) −0.1 / 47.5%: not kept (the e16 sweep result was the best of five, i.e. luck) |
| 8 (2026-11-01) | probes, same data | weight average of the round-7 snapshots (`ai_train average`) +0.8 / 51.5% (200 games); round 5 alone −21.3 / 25%; rounds 3-5 −3.5 / 46.5%; every round with the final margin mixed in (`--final-weight 0.3`) −0.5 / 53% (100 games each): not kept. The older, more varied games (round 0: the hand-written policy) are what the network needs; the latest self-play alone is much worse |
| 9 (2026-11-01) | ensembles (`net.lua`: `members`, Q averaged; `ai_train ensemble`; `train --seed`) | round-5 + r7 + r6: +6.8 / 61%; round-5 + r7 + seed 2 + seed 3 (**ens4**): +8.1 / 60%, confirmed +11.2 / 62%: **bundled**. 5 members (+ r6): +11.2 / 62.8% (199 games; no better than 4). One move costs 4 forward passes (the ladder ran ~1.5x slower) |
| 10 (2026-11-01) | ensemble self-play was ~4x slower (10 of 60 chunks in an hour): stopped after 250 games (seeds within 23000-24499, `round6a_v3.txt`, kept). Instead the round-5 network (`build/ai/v1_all_h20_e24.lua`): 1500 games against itself (budgets 0.5 and 1.5; seeds 26000-27499; `round6c_v3.txt`), then 1000 against the hand-written policy (budget 2; seeds 25000-25999; `round6b_v3.txt`) | 4 members (seeds 1-4) on every round (6.0M decisions), ensembled (ens10): +3.1 / 52.5% against the bundled ens4 (200 games, seeds 5700001+): not kept. The round-5 recipe is at its plateau; more games of the same kind no longer add |
| 11 (2026-11-02) | new recipe, temporal difference (`train --bootstrap NET`): the target is the margin change over 20 own decisions **plus the given network's Q at the position reached then** (the horizon no longer blinds it, without the noise of the final margin). Every round (6.0M decisions), v1 inputs, lr 3e-4, 24 epochs | single networks against the round-5 network (200 games each, seeds 10000001+, 10200001+, 10400001+): td1 (Q from round 5) +3.4 / 55.5%; td1 with gamma 0.5 +7.5 / 61.5%; **td2 (Q from td1) +11.6 / 66.5%**. Ensemble of td2 and 3 more members alike (seeds 2-4, Q from td1): **+9.0 / 62.5% against ens4, confirmed +12.3 / 67%** (seeds 10600001+, 10800001+): **bundled** |
| 12 (2026-11-02) | third TD iteration: Q from the 4 td2 members averaged (`--bootstrap` given 4 times), 4 members (seeds 1-4) | td3 seed 1 against td2 (single networks): +0.6 / 51%; ensemble of the 4 (ens_td3) against the bundled ens_td2: −0.3 / 50% (200 games each, seeds 12000001+, 12200001+): not kept. Two TD iterations take what this data holds; a third adds nothing |
| 13 (2026-11-03) | mixed opponents: td2 (budget 1) against ARNO 3/5/8 (800 games each; lost 99-100%, by 52/70/82) and the hand-written policy (500; won 98%); card numbers logged (`round7_*.txt`). Trained on every round with td2's recipe (margin, h20, Q from the td2 members), with and without card inputs; and with the own-score target (`--target score`, cards), once more bootstrapped from itself | paired, same seeds (vs ARNO 3: 60 games, 14000001+; vs td2: 100, 14100001+). td2 itself: −38.2 / 1.7% vs ARNO 3. r13: −58.9 vs ARNO 3, −21.2 / 30% vs td2. r13c (cards): −44.7, −3.9 / 48%. r13s (own score): −68.7, −41.2 / 13%. r13s2: −63.0 vs ARNO 3. **All worse: not kept.** Games lost from early on carry no choice signal (44-58% of the ARNO 3/5 decisions were taken 20+ points behind, 18% in self-play), only "I am losing"; and td2's Q, bootstrapped there, is extrapolated. Next: a curriculum against ARNO 1-2, where the AI is competitive |
| 14 (2026-11-03) | curriculum: td2 (budget 1) against ARNO 1 (1000 games, lost 92%), ARNO 2 (1000), ARNO 3 (500) (`round8_arno1/2/3.txt`). Trained on the older rounds + these: td2's recipe (margin, h20, Q from td1) = r14t; margin with `--baseline` (state value first), no bootstrap = r14b | paired: td2 vs ARNO 1 −25.5 / 13% (60 games, 15000001+). r14t −28.2 vs ARNO 1, −39.8 vs ARNO 3, −2.6 vs td2; r14b −47.8 / −57.3 / −20.9; (r13s2 −54.9 vs td2). None kept: competitive games no longer hurt, but data alone does not lift this network |
| 15 (2026-11-03) | search pilot: `ai_train.py search` on 100 games td2 vs ARNO 1 (`--samples 4`, seeds 42000001+; 2400 labels). Unbiased best-vs-base gap +1.30 (+0.4 in the lost ARNO 5 games), split-half 62%. Trained td2's recipe + `--search` (weight 5) = r15s | r15s vs ARNO 1 −21.5 / **25%** (td2 −25.5 / 13%), vs td2 +1.2 / 52% (100): a small step up; search labels at scale next (ARNO 1, 2, self; 6 workers: a search worker takes ~1.5 GB) |
| 16 (2026-11-03) | the assists (policy.ASSIST), measured on td2 and then on the shipped Expert | td2 vs ARNO 1 (60 games, 16000001+): plain −19.1 / 20%; build/cp 2/3 −7.7 / 32%; 3/4 −9.7 / 28%; 4/6 −12.8 / 30%. Assisted vs plain td2 (100, 16100001+): +8.1 / 65%, +10.8 / 68%, +10.7 / 70%. **Levels use 3/4 (shipped).** Expert (ens_td2 + assists): vs ARNO 1 −4.7 / 48% (same seeds as the table: −8.6 / 38%), vs ARNO 3 −26.6 / 7% (table −23.8 / 18%, but that row ran before the harness fix gave ARNO his setup draw), vs the same ensemble without assists +12.2 / 66% (100, 17000001+). The largest single step against ARNO: two hand-written blind spots fixed |
| 17 (2026-11-03) | second analysis (traces of the shipped Expert, with the assists) and two more assists, `final` and `ending` (below), measured on td2 + the round-16 assists (build 3, cp 4) | vs ARNO 1 (60 games, 18000001+): round 16 alone −12.6 / 25%; + final 1 −14.4 / 20%; + final 2 −13.3 / 23%; + ending 6 −13.1 / 23% (20 debug games: final 4 doubles the final scoring card's CP, 1.15 -> 2.3, and loses 1.7 points; ending fired in 3 games of 20 and changed one by 1 point). Against td2 without assists (100, 18100001+): round 16 / + ending 6: +8.0 / 57% and +6.7 / 55%. **Not kept: both weights stay 0** (the code and `--assist-final/--assist-end` are in for later tries) |
| 18 (2026-11-03) | search labels at scale (td2 against ARNO 1 100 games, ARNO 2 100, itself 17 of 60; ~7200 labels + the pilot's 2400) in td2's recipe (`--search`, weight 5) = r18; after the card shuffle fix, new baselines | with the assists (network_a): vs ARNO 1 (60, 19000001+) td2 −17.3 / 23%, r18 −15.3 / 27%; vs ARNO 3 (60, 19100001+) td2 −34.3 / 7%, r18 −34.8 / 3%; r18 vs td2 (100) −5.4 / 41%. **Not kept: search distillation does not help this network** (the pilot's gain was noise; at single decisions the candidates are close, the losses come from blind spots the assists fix) |
| 19 (2026-11-03) | third analysis (early game, own turns 1-16; traces of the shipped Expert vs ARNO 3, 1 and itself) and two assists, `unlock` and `upgrade` (below), measured on td2 + the round-16 assists (build 3, cp 4); every baseline rerun on the same seeds (the final scoring cards are shuffled now) | vs ARNO 3 (60 games, 21000001+): round 16 alone −28.8 / 7%; + unlock 3 −22.5 / 17%; + unlock 3 + upgrade 0.5 −24.3 / 10%; + upgrade 0.5 −27.6 / 10%. **Confirmed on fresh seeds (100, 21300001+): round 16 −31.9 / 5%, + unlock 3 −32.0 / 7%, + both −32.0 / 6%: no gain against ARNO 3.** vs ARNO 1 (60, 21100001+): −14.6 / 23%; unlock 3 −14.7 / 22%; both −9.8 / 28%; confirmed (100, 21400001+): −16.4 / 21% against both −10.2 / 35%. Against td2 without assists (100, 21200001+): round 16 +9.7 / 67%, + unlock 3 +15.3 / 70%, + both +17.0 / 69%. **Not kept (the keep rule asks for a gain against ARNO 3): both weights stay 0**; both together are a confirmed step against ARNO 1 (+6) and the network (+7): a candidate if the rule allows it |
| 20 (2026-11-04) | fourth analysis (X-tokens; traces of td2 with the shipped assists against ARNO 3 and itself) and one assist, `xtoken` (below), measured on td2 + the current defaults (build 3, cp 4, unlock 3, upgrade 0.5; network_a) | paired: vs ARNO 3 (100 games, 23000001+): without −27.8 / 7%; xtoken 3 **−20.8 / 22%**; xtoken 6 −22.7 / 17%. vs ARNO 1 (60, 23100001+): −11.9 / 30%; xtoken 3 **−6.3 / 42%**; xtoken 6 −10.0 / 32%. vs the network without assists (100, 23200001+): +16.9 / 67%; xtoken 3 +18.9 / 73%; xtoken 6 not run (stopped: low memory on the owner's PC). **Kept at weight 3** (+7.0 against ARNO 3, +5.6 against ARNO 1, not worse against the network); the default stays 0 until build/ai/r21.cmd (which reads M.ASSIST) is done, then `xtoken = 3` |
| 21 (2026-11-04) | data played by the assisted policy (`network_a` on td2): 1000 games against itself, 800 each against ARNO 1 and 2, 400 against the hand-written policy (seeds 37000-40399, `round9_*.txt`); td2's recipe on every round (minus the ARNO 3-8 games) + these = r21. xtoken (round 20) confirmed on fresh seeds | both with the assists, paired: vs ARNO 1 (60, 24000001+) td2 −3.2 / 43%, r21 −4.7 / 47%; vs ARNO 3 (60, 24100001+) td2 −27.4 / 12%, r21 −30.1 / 7%; vs plain td2 (100) td2 +11.5 / 64%, r21 +15.5 / 70%: r21 not kept (no gain against ARNO). xtoken 3, fresh seeds: vs ARNO 3 (100, 25000001+) −28.9 → −25.1, vs ARNO 1 (60, 25100001+) −5.5 → −4.0: positive on both seed sets, **switched on** (M.ASSIST xtoken = 3). Easy vs ARNO 3 (the paused cell): −46.9 / 0% |
| 22 (2026-11-04) | fifth analysis (traces of the shipped Expert against ARNO 3 and itself, 12 games each, + 10 / 8 with the display at each CARDS choice) and one assist, `snap` (below), measured on td2 + the current defaults (build 3, cp 4, unlock 3, upgrade 0.5, xtoken 3; network_a) | paired: vs ARNO 3 (100 games, 27000001+): without −26.8 / 12%; snap 2 (near animals 1/2) −27.9 / 13%; snap 2 (playable animals only) −27.6 / 12%. vs ARNO 1 (60, 27100001+): −6.5 / 35%; −7.6 / 42%; −5.7 / 40%. **Not kept: the weight stays 0** (no gain against ARNO 3, under the +3 needed for a confirmation; the code and `--assist-snap` are in for later tries) |
| 23 (2026-11-04) | sixth analysis (reputation; traces of the shipped Expert against ARNO 3, 10 games, + 4 with rep 4) and one assist, `rep` (below), measured on td2 + the current defaults (build 3, cp 4, unlock 3, upgrade 0.5, xtoken 3; network_a) | paired: vs ARNO 3 (100 games, 28000001+): without −28.6 / 11%; rep 2 −26.1 / 9%; rep 4 −27.1 / 15%. vs ARNO 1 (60, 28100001+): −4.9 / 40%; rep 2 −5.3 / 38%; rep 4 −3.1 / 45%. **Not kept: the weight stays 0** (+2.5 / +1.5 against ARNO 3, under the +3 needed for a confirmation; the code and `--assist-rep` are in for later tries) |
| 24 (2026-11-04) | seventh analysis (an audit of the choices the network scores the same: traces of the shipped Expert, 30 games against ARNO 3, 20 against itself) and three assists, `slot`, `discard`, `partner` (below), measured on td2 + the current defaults (network_a) | paired, vs ARNO 3 (100 games, 29000001+): without −29.1 / 13%; slot 1 −28.1; discard 1 −28.4; partner 1 −27.0; all three −26.5 / 13%. vs ARNO 1 (60, 29100001+): −5.4 / 45%; slot −2.5; discard −5.3; partner −5.4; all three −1.8 / 47%. All three, fresh seeds: vs ARNO 3 (100, 29200001+) −24.9 → −23.6, vs ARNO 1 (60, 29300001+) −0.8 → +1.5; vs the network without assists (100, 29400001+) +15.3 / 70% → +20.5 / 73%. **Kept and switched on** (M.ASSIST slot = 1, discard = 1, partner = 1): positive on both seed sets, better against the plain network |
| 25 (2026-11-04) | eighth analysis (rollouts of the tied options at those decisions only, `build/assist8/`, below) and three tie-break assists, `flip`, `uni`, `enc` (below), measured on td2 + the current defaults (network_a) | paired, vs ARNO 3 (100 games, 30000001+): without −26.7 / 9%; flip 1 **−19.5 / 18%**; uni 1 −26.5; enc 1 −27.2; all three −20.5 / 13%. vs ARNO 1 (60, 30100001+): −6.2 / 33%; flip −3.3 / 42%; uni −7.2; enc −8.7; all three −2.1 / 43%. Fresh seeds: vs ARNO 3 (100, 30200001+) −22.3 / 16% → flip −15.4 / 27% (all three −16.7), vs ARNO 1 (60, 30300001+) −8.4 / 35% → flip **+0.3 / 55%** (all three −2.5); vs the network without assists (100, 30400001+) +15.5 / 68% → flip +22.6 / 79% (all three +19.6). **flip kept and switched on** (M.ASSIST flip = 1): +6.9 / +8.7 on fresh seeds, better against the plain network; uni and enc stay 0 (no gain alone; all three is below flip alone) |

**Behaviour analysis (2026-11-03, 1000 games td2 vs ARNO 1 + 21 traced games):** the AI keeps
pace on appeal and loses on CP, final scoring and game length (ARNO ends it, ~5 turns earlier
than self-play). Its hand clogs with unplayable animals (no playable animal in 75% of its
action choices, 2-3 animals and ~28 money in hand); it never built a Petting Zoo / Reptile
House / Aviary (value.reward scores a size-N enclosure 2 x min(N, 4)); after turn 24 a project
is supportable in 67% of its action choices but it takes ASSOCIATION in 24%; it cannot see
ARNO's final-scoring tokens and its own scoring card's award (ends games it then loses).
**Assists** (`policy.ASSIST`, off by default; seat `network_a`, `--assist-build/--assist-cp`): a
build gets a bonus per hand animal it would make playable; ASSOCIATION / project support gets a
bonus when a project is supportable and a worker is free. Measured in round 16.

**Second analysis (round 17, 2026-11-03; traces of the shipped Expert with the assists:
12 games each against ARNO 1 and 3, 8 against itself; `build/assist2/an.py`):** against ARNO 1
it is now about even (−0.3 / 42%; small sample, the 60-game table row is −4.7 / 48%), against
ARNO 3 −13.9 / 25%. What changed since the first analysis (td2 without assists): the game is
no longer shorter against ARNO (37.5 own turns, ARNO 37.2; self-play 37.9, was 43.8), the AI
is ahead of ARNO 1 from turn 12 to 30, the own final scoring card gives 1.8 CP (was 0.8),
money at the turn start 24-25 (was 26; 25+ in 46-51%, was 54%). Still: ARNO's final scoring
tokens give 4.3-5.7 CP (13-17 points) against the AI's 1.8; against ARNO 1 the AI ended 8 of
12 games and lost 2 of them (by up to 10), and lost all 4 that ARNO ended; against ARNO 3 ARNO
ends 9 of 12 and is ahead from turn 12 (the race, not the ending, decides those). SPONSORS
turns are still half money / break (3.3-3.7 of 6.2-6.8), but taken with 14.6 money on average
(the other actions with 22-29): a cash move, not hoarding. 15% of the hand animals are
playable; half of them have their conditions met (no enclosure or money).
**Harness finding:** the headless table (`sim.ai_table`) deals the final scoring cards from an
unshuffled deck: the first seat (the AI against ARNO) always holds cards 1 and 2 (large /
small animals), in self-play the second seat 3 and 4. Training and matches never saw the
other cards; a fix (shuffle by the game's seed) changes every game, so it waits for a moment
without running batches.
**Assists of round 17** (off, weight 0): `final` (per CP a card play adds to the own best final
scoring card, read smoothly between its thresholds, times a CP's worth; half of the best such
play on the ANIMALS / SPONSORS card; at the final scoring discard, minus the card's award) and
`ending` (on an action card that would make the own score cross 100 with what it brings at
once, while own score + own final scoring card < the best other score + its final scoring
(ARNO's tokens less his CP debt) + one last turn (6): minus the points short, at most the
weight). Neither helped (round 17): the final scoring card is worth only 3-6 points, and
chasing it costs as much elsewhere; the losing endings the AI can avoid are rare (2 of 12).

**Third analysis (round 19, 2026-11-03; the early game, own turns 1-16; traces of the shipped
Expert: 24 games against ARNO 3, 10 against ARNO 1, 20 against itself; `build/assist3/`:
`trace.lua` (+ U| upgrades, slot order, workers; P| every card pick with its options'
conditions; F| every upgrade choice with its options' Q), `early.py` (per own turn: state and
what each action did), `hand.py`, `life.py`, `conds.py`, `picks.py`, `corr.py`, `firstup.py`):**
the AI's own pace is the same against ARNO 3 and against itself (turn 16: appeal 18.4 / 17.6,
CP 3.1 / 3.8, income 18, 3.3 animals, 1.8 upgrades); ARNO 3 is just faster (score 20.3
against 10.6 at turn 16: −2.5 appeal and −3.4 CP, most of his CP from his own deck). Action mix
in turns 1-16 (per seat): ASSOCIATION 3.6 (mostly university / partner zoo, 0.9 projects),
CARDS 3.4 (2.2 draws at strength ~4), BUILD 3.1 (size 4-5), ANIMALS 3.0 (one animal each; two
only 0.07 times), SPONSORS 2.9 (1.7 of them break / money while ~20 money lie idle). Found:
- **The hand clogs with animals whose conditions are unmet**, not only with ones that lack an
  enclosure: in turns 1-16, 68% of the hand animals have unmet conditions and only 23% of the
  turns have a playable animal (then ANIMALS is taken 81%). Animals with 1+ unmet conditions
  when they reach the hand are played 8-15% of the time and sit 10-13 turns; with none 63-69%.
  The blockers: `upgrade` (ANIMALS II; 22 of 127 against ARNO 3), `research` (21), then
  continents, partner zoos and species. Discards and snaps already lean the right way (a
  playable animal is snapped 64% of the times one is offered, a blocked one 12%).
- **The network cannot tell the upgrades apart:** at every upgrade choice ANIMALS, CARDS,
  SPONSORS and ASSOCIATION get exactly the same Q (BUILD 1-2 lower, never taken), so the
  first upgrade was a random draw (against ARNO 3: SPONSORS 7, CARDS 7, ANIMALS 5,
  ASSOCIATION 5 of 24; in self-play ANIMALS 18 of 40). The choice inputs do not say which
  card is flipped. In self-play, ANIMALS among the first two upgrades: +4.7 against −5.2
  (40 seats, noise level).

**Assists of round 19** (off, weight 0): `unlock` (per hand card whose unmet conditions a
choice meets, 1 if all, 1/2 if some: the ANIMALS / SPONSORS upgrade for `upgrade` animals /
sponsors, a partner zoo (its continent icon, `<continent> partner`, `partner zoo`), a
university (its icons, `university`, its reputation); on "Take a Partner Zoo / University"
the best on offer; `--assist-unlock`) and `upgrade` (points on the ANIMALS upgrade: a fixed
tie-break, ANIMALS II first; `--assist-upgrade`). Results in the table: unlock alone and
both together are flat against ARNO 3 on 160 games (−30.7 → −29.1 for both) but help against
ARNO 1 (both: +4.8 and +6.2 on two seed sets) and against the network without them (+7.3).
Next candidates: the upgrade choice in the network itself (an input naming the flipped
card), and the money left idle (SPONSORS for money with ~20 in hand).

**Fourth analysis (round 20, 2026-11-03; X-tokens; traces of td2 with the shipped assists:
14 seats against ARNO 3, 20 in self-play; `build/assist4/`: `trace.lua`, `xt.py` (tokens gained,
used, held), `under.py` (actions below strength 5 with tokens in hand)):** the network spends
few X-tokens: 1.8 per game against ARNO 3 (3.3 in self-play), never on ANIMALS, and ends with
3.3 unused (2.6); 60 of its 506 turns against ARNO 3 began at the cap of 5, where new tokens are
lost. It took 59 ANIMALS actions below strength 5 with tokens in hand, 71 times one token would
have reached 5.

**Assist of round 20** (weight 0 for now, kept at 3): `xtoken` (on an X-token "+" the best gain
per token over the action cards, `M.card_gain_at`: 1 for a second animal (two playable and
affordable together) or a supportable conservation project, the build assist's points for a
build that houses a hand animal, 1/2 for a sponsor that becomes playable; minus that on "-";
and on the action card the chosen tokens lift; `--assist-x`). With weight 3 the AI spends 6
tokens a game (mostly ASSOCIATION, BUILD, SPONSORS), holds 0.6 at the end and never sits at
the cap. Results in the table: +7.0 against ARNO 3 and +5.6 against ARNO 1 at weight 3; 6 is
weaker (+5.1, +1.9). Not yet confirmed on fresh seeds.

**Fifth analysis (round 22, 2026-11-04; traces of the shipped Expert: 12 games against ARNO 3,
12 against itself, then 10 / 8 more logging the display at every CARDS choice; `build/assist5/`:
`trace.lua` (+ S| lines), `traj.py`, `rep.py`, `snap.py`):** against ARNO 3 the AI is behind from
turn 3 (turn 16: score 8.8 against 19.9, appeal −6.5, CP −2.3, 2.9 animals against 3.8; turn 32:
−17). Its reputation stays at 1-2 for 12 turns (ARNO 3: 5 by then); it reaches 5 (the free
upgrade) at own turn 19 and 8 (the worker) at 24, in self-play 21 and 31 (the 5 seats that reached
5 by turn 16 won by +17, the others lost by 4: confounded with doing well, not tried). Found:
**at the CARDS action the network scores Snap and Draw within 0.1-0.6 points** (v1 inputs: it
cannot see the display); with an animal it could play in the display it drew 17 times of 35.

**Assist of round 22** (off, weight 0): `snap` (on "Snap a card" / "Snap two cards" the best
display card's gain, `M.snap_gain`: 1 for an animal playable now, `M.SNAP_NEAR` for one a
condition or the enclosure short; on a snap pick that card's gain; half of it on the CARDS action
card at a strength that snaps, `M.cards_snaps`; `--assist-snap`). With weight 2 and SNAP_NEAR 1/2
it snapped at 51 of 52 CARDS choices (a near animal is almost always on display), so SNAP_NEAR
is 0 now. Neither moved the result (table): one better card a few times a game is worth little,
the gap to ARNO 3 is the pace of appeal from turn 3.

**Sixth analysis (round 23, 2026-11-04; reputation; traces of the shipped Expert against ARNO 3,
10 games, + R| lines (every choice with a reputation option, all options' Q) and W| lines (at each
action choice: could ASSOCIATION take the reputation task); `build/assist6/`: `trace.lua`, `rep23.py`):**
the AI's reputation comes passively: map placement bonuses 2.4 a game, the map project bonus 1.9,
ANIMALS II at strength 5 2.4, universities 1.5, the 8-CP bonus 0.6, cards ~0.7; ASSOCIATION's
"Take 2 Reputation" 0.2 (taken once in 73 offers, Q 1-2.5 points under a partner zoo or university
early, 5-8 under a conservation project later). ARNO 3's lead is his own deck (9.6 of his ~12 a
game), not choices the AI could copy. Rep at own turn 8 / 16 / 24: AI 2.2 / 3.5 / 8.3, ARNO 3.2 /
7.1 / 10.4; 5 reached at turn 19.5 (ARNO 10.5). Early workers are the limit: 0.4-0.5 free at the
action choices of turns 1-16. Without the CARDS upgrade the track stops at 9 ("cannot gain any
more" 9 times in 12 round-22 games). The partner zoo and the university get the same Q at the
association panel (the network cannot tell them apart).

**Assist of round 23** (off, weight 0): `rep` (a choice's reputation, `M.rep_gain`: each track reward
(`M.REP_REWARD`: card flip 1.5, worker 1, CP 0.5, draw / X-token 0.3) spread evenly over the steps
from the previous reward, 0 above the cap; + `M.REP_DISPLAY` (1/2) x `M.display_card_gain` for a
display slot it opens with ANIMALS / SPONSORS upgraded; times 1 − progress. On "Take 2
Reputation", "N Reputation" (claims, project cubes), a university (its reputation; "Take a
University": the best on offer) and one reputation's worth on the ASSOCIATION action card that
can take the task; `--assist-rep`). With weight 4 the AI reached 5 at turn 13 (was 20.5), mostly
through the Double Reputation University; it still never took "Take 2 Reputation" (the network
rates it ~5 points under the alternatives). Results in the table: +2.5 / +1.5 against ARNO 3, −0.4
/ +1.8 against ARNO 1: earlier reputation is worth little on its own; the free upgrade at 5 comes
6 turns sooner but costs the actions that would have scored.

**Seventh analysis (round 24, 2026-11-04; ties; traces of the shipped Expert, 30 games against ARNO 3
and 20 against itself; `build/assist7/`: `trace.lua` (T| every decision whose top choices lie within
0.05 of each other, with Q, the network's part, the hand-written score and how far their choice
inputs differ), `ties.py` (groups by panel + choice type), `show.py`):** of 13,400 decisions with 2+
choices, the near ties per seat and game (70 seat-games), nearly all with identical inputs: tile
spots 6.9 (196 of 483 the same cells in another order; the rest differ only in place); the X-token
+ / − 4.3 (a round trip, no stake); card picks at a discard 2.8 and sponsor picks 2.2 (inputs
differ: the network's own judgement); Size-4 against Size-5 enclosure 2.0 (2 money); Take a
Partner Zoo / University 1.3, which university 1.1, which continent 0.9; the final scoring discard
1.1; the clever / boost card 0.9 / 0.8; upgrades other than ANIMALS 1.8; Kiosk / Pavilion 1.2; which
project slot 0.5 (1st 5 CP, 3rd 2 CP: it took the 3rd with the 1st open). The labels of these
choices carry no number or word the inputs read, so value.reward gives them all the same (0.5,
3, 8), and the hand-written score cannot tell them apart either.

**Assists of round 24** (on, weight 1 each): `slot` (on a project slot, its rewards in points,
`M.project_slot_value`; on a project in the support panel its best slot's), `discard` (at the
final scoring discard, minus the card's award in points now: the `final` assist's discard part on
its own key) and `partner` (on "<continent> Partner Zoo", the money it saves on the hand's animals
of that continent, 3 each, `M.partner_saving`; `--assist-slot/--assist-discard/--assist-partner`).
Each alone +0.7 to +2.9; together +2.6 / +3.6 and on fresh seeds +1.3 / +2.3 against ARNO 3 / 1,
+5.2 against the plain network (table). Left: Partner Zoo against University and which
university (no clear rule), the upgrades other than ANIMALS, tile spots.

**Eighth analysis (round 25, 2026-11-04; rollouts of the tied options; `build/assist8/`: `tsearch.lua`
(search.lua's machinery: the game is recorded once with network_a on td2; at each decision whose top
options lie within 0.05 and form one of the groups, every tied option is forced on a replay and
played on, H = 20 own decisions + the network's Q or to the end, 4 paired samples (the same policy
seed and deck reshuffle for every option); F| lines with the state: hand, conditions, icons,
money, reputation, workers, upgrades, the universities / partner zoos on offer), `run.py`, `analyze.py`
(option advantage against a random pick, median splits by feature, rules; `analysis.txt`)):** 120
games against ARNO 3, 80 against ARNO 1, 32 in self-play; 1516 points. Per group, the rollout value
of a rule's pick minus the random tie-break's, and how often it picks the rollout-best option at the
points where one option is clearly ahead (gap > 1.5 standard errors):
- **the upgrade after ANIMALS** (429 points): ASSOCIATION +2.8, BUILD 0.0 (21 points), CARDS −0.8,
  SPONSORS −2.2. The order ASSOCIATION > CARDS > BUILD > SPONSORS: **+2.55 ± 0.16, rollout-best 84%**
  (random 41%), the same in every pool (ARNO 3 +2.2, ARNO 1 +2.9, self +2.9) and in every median
  split of the state (no condition found that turns it). CARDS first −0.4, SPONSORS first −2.0.
- **which university** (293; Hand Size against Double Research, Double Reputation rarely tied):
  Hand Size first +0.59 ± 0.11, 75% (random 50%); "Double Research when a hand card needs
  research" +0.50 (the unlock assist already takes it then).
- **Size-4 against Size-5 enclosure** (510): Size-5 +0.37 ± 0.13, 58%.
- **Partner Zoo against University** (284): no difference (+0.09 ± 0.15, 50%); "the partner
  zoo when a hand animal's continent is open" +0.34 ± 0.15, 55%, not the same across pools: no rule.

**Assists of round 25** (`flip` on, weight 1; `uni`, `enc` off): fixed tie-breaks in points per
unit weight, below the `upgrade` assist's 0.5 on ANIMALS and far below unlock's 3 per hand card:
`flip` on the upgrade buttons (`M.FLIP_ORDER`: ASSOCIATION 0.3, CARDS 0.2, BUILD 0.1, SPONSORS 0),
`uni` on "Hand Size University" (`M.UNI_ORDER`, 0.3), `enc` on "Build a Size-5 Enclosure"
(`M.ENC_ORDER`, 0.3); `--assist-flip/--assist-uni/--assist-enc`. Only the upgrade order carries
into the matches (table): +6 to +9 points against ARNO 3 and 1 on two seed sets, the largest single
assist since round 16; the university and enclosure gains (~0.5 a choice, once or twice a game) do
not show in 100-game matches. Left from round 24: tile spots, Kiosk / Pavilion, clever / boost.
**Ninth analysis (round 26, 2026-11-04 / 06; rollouts of the action card choice; `build/assist9/`:
`asearch.lua` (round 25's machinery; at a quarter of the shipped Expert's fresh action choices, every
card at +0, +1 X-token (strength <= 5), +2 when it reaches 5 or adds `card_gain_at`, the X-token action,
and the AI's own pick are forced as plans and played on, H = 20 + Q; samples 1-2 for every option,
3-4 for the pick and the 2 best others), `collect.py`, `analyze.py` (unbiased regret: the best on
samples 1-2 valued on 3-4; a picked -> best confusion table), `rules.py` (single-feature rules found on
odd seeds, checked on even), `measure.sh`):** 146 games (70 against ARNO 3, 50 against ARNO 1, 30 in
self-play; seeds 98000001+, 98100001+, 98200001+), 1757 points. The AI's pick is the rollout-best 27%
of the time and **loses at least 2.65 ± 0.14 points a choice** (ARNO 3 2.8, ARNO 1 2.3, self 2.8), but
the loss is diffuse: no picked -> best pair carries more than 6% of it (BUILD -> CARDS, CARDS ->
SPONSORS, ANIMALS -> SPONSORS lead). The one rule steady on the held-out seeds and in every pool:
SPONSORS (at 5, with X-tokens) when a hand sponsor is playable there, +0.18 to +0.20 a point, +1.6 each
time it changes the pick.
**Assist of round 26** (off, weight 0): `sponsor` (+w on the SPONSORS action card when a hand sponsor
is playable at its strength; on the X-token "+" 1/j when j more tokens make one playable, −1 on "−"
when one token fewer loses it; `--assist-sponsor`). Set A (100 games vs ARNO 3 from 32000001, 60 vs
ARNO 1 from 32100001; base −17.8 / +2.0): card part only 1.5 −19.2 / +3.0, 3 −18.5 / +1.4, 8 −18.8 /
−1.2; with the X-token part 3 −19.1 / +0.1, 8 −19.7 / −0.8. Flat to slightly worse: as in rounds 22-23,
a rollout rule's gain does not carry into matches. The rollout regret of the action choice is large
but not reachable with single-feature rules; whether it is real (a player that searches the action
choice) has not been measured in a match (rollouts need the headless forced replay, so it could not
ship to TTS as is).
**Tenth analysis (round 27, 2026-11-06 / 07; rollouts of the ties round 24 left; `build/assist10/`: `tsearch.lua`
(round 25's runner + groups tile (tied tile spots with distinct cells, per-spot C| features: bonuses
under the tile, terrain, touching tiles, free regions and footprints left), kp (Kiosk / Pavilion, also
the free-kiosk panel), clever (which card a clever bonus sets back to position 1), boost), `collect.py`,
`analyze.py`):** 200 games (100 against ARNO 3, 60 against ARNO 1, 40 in self-play; seeds 96000001+,
96100001+, 96200001+); the AI's pick scores ~0 against a random tie-break everywhere (unbiased).
- **clever** (182 points): CARDS +1.06 ± 0.23, SPONSORS +0.39, ANIMALS +0.20, BUILD −1.3 (13),
  ASSOCIATION −1.56 against a random pick; CARDS first in every pool.
- **Kiosk / Pavilion** (304): Pavilion +0.21 ± 0.07, the same sign in every pool.
- **tile spots** (1004 points, 2.9 distinct candidates): fewest card-draw bonuses, then most bonuses
  +0.26 ± 0.08 on the held-out seeds (+0.17 to +0.39 per pool); a reputation bonus under the tile
  +0.9 a bonus, a draw bonus −1.7; the board's shape (free regions, footprints, water side) ±0.1.
- **boost** (199): nothing.
**Assists of round 27** (weight 0): `clever` (`M.CLEVER_ORDER`: CARDS 0.4, SPONSORS 0.3, ANIMALS 0.2, BUILD
0.1), `kp` (`M.KP_ORDER`: Pavilion 0.3), `tile` (on a tile spot 0.3 per reputation bonus under it,
−0.3 per card draw; `M.TILE_REP` / `M.TILE_DRAW`); `--assist-clever/--assist-kp/--assist-tile`. Set A
(base −17.8 / +2.0 against ARNO 3 / 1): clever −19.2 / +1.0, kp −18.6 / +2.7, tile −18.9 / −1.6, all three −19.1 / −2.4: flat to
slightly worse, none switched on. Like round 25's university and enclosure assists, gains of +0.2 to +1
a tie, once or a few times a game, do not show in 100-game matches; round 24's ties are now used up.
**Round 28 (2026-11-07; is round 26's action choice regret real? `build/assist11/`: `psearch.lua` (a
headless player: at every fresh action selection it rolls out asearch's option set, 2 paired samples,
H = 20 + Q, and plays the best mean; every other decision is network_a; modes plain / follow / random),
`run.py`, `summary.py`):** against ARNO 3, seeds 32000001-32000032 (Red = network_a starts, as in `match`;
follow mode reproduces plain exactly, own plain baseline −17.8 / 16% on 100 seeds = the match's). Search
changed the network's pick at 57% of the choices (20 a game; in-sample +2.6 a choice by its own
rollouts), and **played exactly as well: −18.4 against −18.4 on the same 32 seeds, +0.0 ± 5.6** (16
better, 16 worse). A random option at every choice: −98. So the rollouts carry signal, but at the
action choice they are no better a judge than the network: round 26's 2.65 a choice was the rollout
value's own error, not a loss in play. Rollouts at tied choices still help (round 25's flip). The action
choice is closed for rollout-based work (rules, distillation, search). A likely cause (not checked): the horizon counts
own decisions, so options with fewer follow-up decisions (low-strength SPONSORS, the X-token action)
cover more game time inside it; the random control's −98 says the error is systematic, not noise. Open
question parked in build/assist11/STATE.md (rollout mean against the value reached, per option kind).
Found on the way: `tests/lua/sim_lib.lua` keeps fake objects, stopped passes' Wait callbacks and recorded
calls across the games of one process: a runner with many replays grew ~15 MB a CPU second (asearch /
tsearch's ~2 GB workers); psearch.lua resets them per pass (workers flat at ~150 MB). Port that reset to asearch / tsearch (or sim_lib) before another rollout round.
**Round 29a (2026-11-07; reweight of the shipped assists, one at a time, x0.5 and x2, set A; base −17.8 /
+2.0 against ARNO 3 / 1; `build/assist9/r29w.sh`):** build 1.5 −19.1 / +1.4, 6 −17.3 / +3.0; cp 2 −18.2 /
+0.6, 8 −17.4 / +2.1; unlock 1.5 −17.6 / +2.6, 6 −18.8 / +0.5; xtoken 1.5 −18.4 / +0.6, 6 −20.1 / +0.2.
All within ±2 (noise): the weights sit on a flat plateau; nothing changed.

The richer inputs (v2, v3) predict held-out games better but play worse: a lower validation
error does not mean better choices. (Not because the state explains most of the target: with
v1 inputs the state alone predicts little, 38.1 against 40.0 for the mean and 36.3 for the
full network, round0a.) Play strength also swings by ±10 points between neighbouring epochs of
one run while the validation error barely moves: the choice (an argmax) is sensitive to small
weight changes, so a sweep's best must be confirmed on fresh seeds. `train --inputs 1` trains the v1
network on rows logged with a later version (an earlier version's inputs are a column
subset), so every round can feed it.

What won: more data (every round, through the v1 inputs) together with the longer horizon (20
own decisions); neither alone did. The ladder kept its steps with the same budgets (§8).
`train --baseline` (fit the state alone first, train on what the choice adds) is in but not
checked yet.

**Next steps (2026-11-02):** recalibrate the level budgets for the TD ensemble (Hard vs Medium
57%); check in
TTS how long the ensemble (4 passes per choice) thinks on big decisions.

### Search labels (`ai_train.py search`, 2026-11-03)

AlphaZero-lite, step 1: for sampled decisions of real games, a value for **each** of the best
few candidates, instead of the one noisy sample of the choice made (a D line). The state cannot
be copied, so every sample replays the game from its seed (`tests/lua/search.lua`):

1. **Record:** the game is played once with the base policies; every call of every policy seat
   notes the index of the choice it took (the choice lists are deterministic for a state).
2. **Points:** `--points` N per searched seat (`--searched` colour or `ai`), one per stretch of
   its decisions with >= 2 choices and no fixed rule (`policy.rule`), seeded by the game.
3. **Candidates:** the top `--k` by the seat's network Q, plus the base choice if it is not
   among them. Per candidate and sample (`--samples` m): replay forcing the recorded choices
   up to the point (no scoring: fast), force the candidate, shuffle the cards left in the zoo
   deck (the replay would otherwise know the next draws; `--no-reshuffle`), then play on
   with the policies (seed per sample, the same for every candidate; `--rollout-budget`,
   default 0) for `--horizon` H = 20 own decisions: value = margin then − margin at the point
   + the network's Q there for the choice the policy makes (as `train --bootstrap`); if the
   game ends first, final margin − margin at the point. The rollout then ends at the turn's
   end (as the turn cap; an error in mid-turn left panel state behind for the next replay).
   `--target score` (default `margin`, as `train --target`): the own score instead of the
   margin (own score then − own score at the point + Q; at the end, final own score − own
   score at the point); `--weights` must then be a network trained with `train --target score`.
   (Smoke test, 1 game vs arno:3, m 2, td2 as a stand-in network: 24 labels, value mean +6.6,
   sd 6.4; 7.7 s per point.)

```
python tools/ai_train.py search --games 100 --first 40100001 --seats network:1,arno:5 --weights build/ai/td2.lua --workers 10 --out build/ai/search1.txt
python tools/ai_train.py search --report build/ai/search1.txt          # timing, best vs base, noise
python tools/ai_train.py train --data ... --search build/ai/search1.txt --search-weight 3 --inputs 1 --horizon 20 --bootstrap ... --out build/ai/rS.lua
```

Lines (`--out` gets each finished game's lines, `<out>.done` at the end):
`S|seed|color|point|rank|value|sd|base|inputs|card|target` per candidate (point = the decision's index
among the seat's D lines; rank by Q, 1 = best; value = mean over the samples, sd between
them; base = 1 for the base policy's choice; inputs at the point before the candidate,
`features.state .. features.choice` at the current `features.VERSION`, exactly as a D line;
card number as D field 7; target = `margin` or `score`, what the value measures; files
before 2026-11-03 have no field 11 and are margin). Also `V|` (each sample's value), `T|` (seconds and rollouts per
point), `E|` (the recorded game), `C|` (`--check`: the game replayed with every choice forced
gives the same scores, outcome and call counts) and `X|` (failures). `train --search FILE`
(repeatable) adds every S row with its value as the target (after the bootstrap; not
bootstrapped again), each repeated `--search-weight` times (default 3), projected by
`--inputs` like D rows; `--data` is then optional. It refuses S rows whose target is not
`train --target` (a margin and a score value cannot share a network).

Determinism: the forced replay reproduces the final scores exactly (2-seat network self-play,
network vs ARNO, a Marine Worlds game). Two causes fixed in the runner: the mod's own
`math.random` (`pilfer_card`) is reseeded per replay, and a rollout no longer stops by an error
in mid-turn. MoonSharp traps met: the first `os.clock()` of a process returns nothing, and
locals of a loop body captured by closures can alias each other (state kept in tables).

**Measured (2026-11-03, network:1 (td2) vs arno:5, H 20, k 5; a point has 4.2 candidates on
average, many decisions offer fewer than 5):**

| Rollouts | One worker, idle machine | Sample sd | Noise of a value (sd/√m) | Median gap of two candidates |
|---|---|---|---|---|
| budget 1, m 2 | 12.3 s per point (1.5 s per rollout), 1230 labels/h | 6.1-6.8 | 4.8 | 2.5 |
| budget 1, m 4 | (loaded machine) | 6.1 | 3.0 | 2.7 |
| budget 0, m 3 (**default**) | 18.0 s per point, 840 labels/h | 4.2-5.0 | 2.6-2.9 | 2.5-2.7 |
| budget 0, m 4 | (loaded machine) | 4.2 | 2.1 | 2.8 |

A rollout costs about the same before and after the point: late points take 2-3x longer than
early ones (the forced replay of the game so far). Labels per hour fall with m only (each
label costs m rollouts; k only sets the labels per point). Budget-0 rollouts are less noisy
(the deck reshuffle is the only randomness left) and value a candidate under the network's
best play; m 3 brings the noise to about the typical gap between two candidates, m 4 below it.
Two candidates' sample values do not move together (sd of a difference 4.9-7.4, more than one
value's): the samples share their seeds, but the games part at once.

Search's best candidate is not the base choice at 54-75% of the points (mean gap best - base
+2 to +5), but most of that is noise: a split-half check (best on the odd samples, measured on
the even ones; 48 points with m 4) agrees 58% and leaves an unbiased gap of only +0.4 to +0.5.
At these settings the labels refine the values of the candidates (far less noisy than a D row's
one sample to the horizon) rather than flip many choices. Whether training on them wins is the
next check (`train --search`, then `match`).

### Card identity inputs (`train --cards`, 2026-11-03)

The base inputs only summarise a card (cost, size, rewards, icons), so the network cannot
learn what a particular card is worth. `train --cards` appends a one-hot of the number of the
card the move is about (1..560; D field 7, S field 10; 0 or a row without the field, i.e.
files before round 7: all zeros) after the base inputs (after the `--inputs` projection):

```
python tools/ai_train.py train --data build/ai/round7_arno3.txt [--data ...] --inputs 1 --horizon 20 --lr 3e-4 --epochs 24 --cards --out build/ai/rC.lua
```

Training keeps it sparse (the card's row of a 561 x hidden block is added to the first
layer's pre-activation; row 0, no card, stays 0), so the memory is that of the base inputs.
The exported file has `inputs = base + 560`, `features = <base version>`, `cards = 560`, and
the card columns have mean 0 and std 1 (never standardised: a zero stays exactly 0). In Lua,
`net.forward(x, w, card)` adds only that card's weight to the first layer (a choice costs the
base inputs + 1); `policy.q_scored` passes `features.card_number(choice)` (the same rule as
the D lines' field 7) when the network or any ensemble member has `cards`. `ensemble` may mix
members with and without cards (it checks the base inputs and writes the largest `cards`);
`average`, `read_weights` and `--bootstrap` (each row's own card, so Q at the row
`--horizon` on uses that row's card) handle card networks.

Sanity run (the first 1250 games' lines of `round7_arno3.txt` + `round6c_v3.txt`, 745k rows,
2% of them about a card; `--inputs 1 --horizon 20 --lr 3e-4 --epochs 8`): validation error
71.0 with `--cards` against 71.1 without. On the held-out round-7 rows that name a card
(1667 rows): 62.1 against 66.1 (predicting the mean: 68.2); the rows without a card stay the
same (72.4 / 72.4). Not checked in play yet. To do once the round-7 job is done:
`tests/lua/selfplay.lua` should call `features.card_number` (its `M_card_number` is the same
rule) and `tests/lua/search.lua` should pass `features.card_number(c)` as `net.forward`'s third
argument (it scores candidates without it, i.e. as "no card", for a card network).

**Robustness sweeps (2026-11-01/02, round-5 network and the hand-written policy, mixed
budgets):** 2000 two-player games (seeds 6000001+, 7000001+), 200 three-player (8000101+) and
100 four-player games (9000001+): 0 failures.

**FIXANIMAL dead end: fixed 2026-11-01** (here and on `fix-pile-break-refill`): ANIMALS at
strength 5 counts a display animal that the reputation draw could fetch; a player who draws
from the deck instead had an animal panel without a way out (seed 4200076). With no animal on
offer that can be played, the first animal can now be passed ("Play no animal").

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
