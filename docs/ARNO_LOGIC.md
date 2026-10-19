# ARNO logic as implemented by the helper app

Source of truth: `vendor/ark-nova-solo-helper` (brdgm/ark-nova-solo-helper, Apache-2.0,
v3.1.20, commit `f4cda53`, 2026-10-17). ARNO design: Andre K. App: Stefan Seifert.
Paths below are relative to that folder.

## 0. How to read this document

The helper is **not a rules engine**. It replaces ARNO's physical action-card deck and
dice, and tracks a few counters. Most of ARNO's behaviour is either shown as prose to the
human or decided by the human. Every rule below carries a tag:

| Tag | Meaning |
|---|---|
| `[code]` | Executed by TypeScript in `src/services/*`, `src/util/*` or component methods. |
| `[prose]` | Stated only in locale strings (`src/locales/en.json`); the human applies it. |
| `[human]` | The app asks the human for a value or a click. |
| `[absent]` | Needed to play, but neither computed nor stated by the app (lives in the printed rules). |

Inputs are numbered `IN-xx`, outputs `OUT-xx`. `DECISION.md` refers to these IDs.

**Rules version.** The app says **A.R.N.O. 3.0** (`en.json` → `home.play1`). The reference
TTS table `2960339961.json` is titled **"ARNO 2.0 Solo Setup"**. I have **not** checked the
app against the printed 3.0 rules (they are on BGG and not in this repo). See §9.

## 1. Setup

| # | Rule | Tag | Where |
|---|---|---|---|
| S1 | Human players 1–4, ARNO bots 1–3, colours from blue/red/yellow/black. Solo = 1 human + 1 ARNO. A human is the start player. | `[human]` / `[prose]` | `store/state.ts` `PlayerSetup`; `setupARNO.setupPlayerCount` |
| S2 | Difficulty per bot, levels 1–6 (`DifficultyLevel` enum). Level 7+: +1 CP to ARNO at start for each level above 6. | `[human]` / `[prose]` | `components/setup/DifficultyLevel.vue`; `setup.difficultyLevel.level7plus` |
| S3 | Optional modules: `arno-conservation-project-module` (variable project-slot choice) and `marine-worlds`. | `[human]` | `enum/Expansion.ts`; `ExpansionsSetup.vue` |
| S4 | ARNO starts with **−5 CP** (**−3 with Marine Worlds**). These are shown as N player tokens next to the CP counter, removed one by one as ARNO scores CP. | `[prose]` (value `[code]`) | `SetupARNOInstructions.vue` `conservationPointStartMinus` |
| S5 | Starting appeal = seat order − 1, so `botNumber + playerCount − 1`. Solo: **1**. | `[code]` | `util/NavigationState.ts` `getBotRound` (round 1) |
| S6 | ARNO gets components of one colour, zoo mat **map A**, one face-down Final Scoring card on the left of the mat, and 8 random zoo cards. He keeps at most the first 2 conservation-project cards. All sponsors and animals are discarded. | `[prose]` | `setupARNO.startComponents*` |
| S7 | Project module only: how many sponsor cards ARNO discarded at setup (0–8 per bot). | `[human]` **IN-01** | `SetupARNOInstructions.vue` → `setupBotInitialSponsorCardDiscardCount` |
| S8 | One association worker on his notepad, the other 3 on the spaces below the notepad. All player tokens next to his mat. No dice or action cards. | `[prose]` | `setupARNO.associationWorker`, `playerTokens` |
| S9 | Zoo maps are picked for **human** players only (A, 0, 1–8, map packs 9–10, 11–14, T1). | `[human]` | `PickZooMap.vue` |
| S10 | ARNO's 5 action cards: **Animals** fixed in slot 1, the other four shuffled into slots 2–5 (`lodash.shuffle`). | `[code]` | `CardSlots.new()` |

## 2. Turn loop

The app's "round" is one human turn followed by one turn per bot
(`/round/N/player/1 → … → /round/N/bot/1 → … → /round/N+1/player/1`). It is **not** the
break-to-break period of Ark Nova.

### 2.1 Drawing ARNO's card `[code]`

`NavigationState.getBotRound(round, bot)`:

1. Round 1: `CardSlots.new()`. Later rounds: copy the previous round's slots, then
   **move the previously used card to slot 1** (`CardSlots.moveFirst`).
2. Slot = `rollDice(4) + 1`, uniform over **2..5**. Slot 1 is never played.
3. The card in that slot is the **active card**. Upgraded or standard side comes from
   `upgradedCards`.
4. Actions = the card's action list filtered by `slotFilter` (absent = every slot) and
   `difficultyLevelFilter` (absent = every level), excluding `fallback` entries
   (`BotActions.getActions`).
5. Amount = `amount` + (`slotAmount` ? slot number : 0) (`BotActions.toBotAction`).
6. Special case: `TOKEN_SCORING_CARD` when ARNO already has **≥ 6** tokens on his
   scoring card becomes **2 CP** instead (`toBotAction`).
7. Persist `BotRound{cardSlots, slotNumber, tokenScoringCardCount += sum(TOKEN_SCORING_CARD),
   tokenNotepadCount += sum(TOKEN_NOTEPAD), appealCount += sum(APPEAL)}`.
   `state.round()` **deletes all later rounds**, so they are recalculated.

### 2.2 Action tables `[code]` (`services/Cards.ts`)

Values are per difficulty L1/L2/L3/L4/L5/L6. `s` = slot number (2–5).

| Card | Side | Slot | Actions |
|---|---|---|---|
| Animals | std | any | APPEAL s + 0/1/1/1/2/3 |
| Animals | upg | any | APPEAL s + 1/1/2/2/3/4 |
| Association | std | 2 | REPUTATION 2 |
| | | 3 | GAIN_PARTNER_ZOO |
| | | 4 | GAIN_PARTNER_UNIVERSITY |
| | | 5 | CONSERVATION_PROJECT_WORK |
| | | fallback | CONSERVATION 1, BREAK 2, GAIN_PARTNER_ZOO_OR_UNIVERSITY |
| Association | upg | 2–5 | same as std, **plus DONATE on every slot** |
| | | fallback | same as std |
| Sponsors | std | any | REPUTATION 1, TOKEN_SCORING_CARD 1 (→ CP 2 if ≥ 6 tokens), BREAK s |
| Sponsors | upg | any | APPEAL s, TOKEN_NOTEPAD 1, BREAK s |
| Build | std | 2 | REPUTATION 1/1/1/2/2/2 |
| | | 3 | APPEAL 2/3/3/4/4/5 |
| | | 4 | TAKE_CARD_DISPLAY, REPUTATION 1 |
| | | 5 | CONSERVATION 2/3/3/3/3/4 |
| Build | upg | 2 | TAKE_CARD_DISPLAY, REPUTATION 1/1/1/2/2/2 |
| | | 3 | APPEAL 3/3/4/5/5/5 |
| | | 4 | TAKE_CARD_DISPLAY, TOKEN_NOTEPAD 1/1/1/2/2/2 |
| | | 5 | CONSERVATION 3/3/3/4/4/4 |
| Cards | std | any | CONSERVATION 1, TAKE_CARD_DISPLAY, BREAK 1, APPEAL 1/2/2/3/3/3 |
| Cards | upg | any | CONSERVATION 2, TAKE_CARD_DISPLAY, BREAK 1 |

The app does **not** state an order for resolving the actions of one card. The UI shows
APPEAL, REPUTATION, CONSERVATION and BREAK as icons first, then the described actions
(`BotActions.vue` `isIconOnly`). `[absent]`: resolution order, and what happens when a
BREAK amount triggers a break partway through a turn.

### 2.3 Resolving each action

| Action | What ARNO does | Randomness | Tag |
|---|---|---|---|
| APPEAL n | +n appeal | – | `[code]` amount, track move by human |
| REPUTATION n | +n reputation. Appeal instead of reputation past step 15 is **not tracked** by the app (`scoring.appealReputationTrack`). | – | amount `[code]`; overflow `[absent]` |
| CONSERVATION n | +n CP | – | amount `[code]` |
| BREAK n | Advance the break token n | – | amount `[code]` |
| TOKEN_SCORING_CARD 1 | Put a player token on his Final Scoring card | – | `[code]` count |
| TOKEN_NOTEPAD n | Put n tokens on his notepad (end-game CP) | – | `[code]` count |
| TAKE_CARD_DISPLAY | "Snap card **#d6** from the display" | `rollDice(6)` in `BotActions.vue data()` | `[code]` roll |
| ↳ received card | Sponsor: discard. Animal: stack on his zoo mat; its icons can **trigger the human's card effects**. Project card: stack on mat. | – | `[prose]` `aboutARNO.receiveCards`, `referenceValues` |
| ↳ project module | "Was it a sponsor card (discarded)?" checkbox | – | `[human]` **IN-02** |
| GAIN_PARTNER_ZOO | Partner zoo **#d5**: 1 America, 2 Europe, 3 Asia, 4 Africa, 5 Australia. **Reroll** button picks a different value than the current one. | `rollDice(5)`, `rollDiceDifferentValue` | `[code]` roll; `[human]` reroll **IN-03** |
| GAIN_PARTNER_UNIVERSITY | University **#d3** (**#d4** with Marine Worlds): 1 cards+reputation, 2 science, 3 science+reputation, 4 science+animal type. For #4, also a random `AnimalType` of 6 (bird, herbivore, predator, primate, reptile, sea), with its own reroll. | `rollDice`, `randomEnum` | `[code]` roll; `[human]` reroll **IN-04** |
| CONSERVATION_PROJECT_WORK | See §2.4 | several d2/dN | `[code]` + `[human]` |
| DONATE | "ARNO donates." No amount, cost or reward in code. | – | `[absent]` (see §9) |
| Association worker | Each Association action places a worker. If one of his workers is already on that task, he takes the **next higher** free task, else the next lower one. He never puts two workers on one task. | – | `[prose]` `actionHelpAssociationWorker.text` |
| ↳ manual override | Human may swap the association action for another unused one (REPUTATION is then 2). | – | `[human]` **IN-05** (`overwriteAssociationAction`) |
| Association fallback | When no worker is left: CP, BREAK +2, and a partner zoo or university, whichever he "misses most". | – | amounts `[code]`; **CP is 1 in code but "+2" in prose**, see §9 |
| ↳ zoo vs university | "What is ARNO missing most?" radio, or **Pick Random** (d2) | `rollDice(2)` | `[human]` **IN-06** |

### 2.4 Conservation-project work (`PickConservationProject.vue`)

Inputs `[human]`:
- **IN-07** project cards on ARNO's zoo mat (`hand`)
- **IN-08** projects next to the association board with **no player token**, ignoring
  blocker tokens of the unused colour (asked only if hand < 2)
- **IN-09** projects next to the board that ARNO **has not supported yet** (asked only if
  hand < 2 and IN-08 = 0)

Algorithm `[code]`:
```
preferFromHand = d2 == 1
if hand >= 2 or (hand == 1 and preferFromHand) or (hand == 1 and noToken == 0 and available == 0):
    support project #d(hand) from his mat
elif noToken > 0:  support project #d(noToken) beside the board (no-token ones)
elif available > 0: support project #d(available) beside the board (available ones)
else: no button. Nothing is possible, and the app does not say what happens then.   [absent]
```
Note that d2 is always rolled, even when it is not needed. That matters for an exact RNG match.

Token placement / reward slot:
- **Without** project module `[code]` + `[prose]`: preferred slot by difficulty. L1–2 is
  **right**, L3–4 is **middle**, L5–6 is **left**. If that slot is taken, he uses the next
  level to the left, otherwise the next free level to the right.
- **With** project module `[code]`: `ProjectModuleTracker(totalSponsorDiscards)`.
  - `steps = (discards + 1) mod 28`; the position bounces between 1 and 14.
  - The slot for a position comes from a fixed table: 2/5/7/11/13 are middle,
    4/8/10/12/14 are left, the rest are right.
  - Token placement order is `getPreferredProjectSlots()`: the current slot, then slots
    from earlier positions going down, then the remaining slots in order right, middle,
    left.
  - **CP/bonus gained** still uses the difficulty slot, with the same left/right fallback.
  - The tracker also shows a **kiosk count** (0–5 at positions 3/6/9/12/14). The app does
    not say what it is used for. `[absent]`
  - `totalSponsorDiscards` = IN-01 + every break's IN-10 + every turn's IN-02
    (`util/getProjectModuleTrackerForRound.ts`).

### 2.5 Card upgrades and bonus tiles

| Rule | Tag |
|---|---|
| When ARNO earns an upgrade, the human clicks **Upgrade**. A random non-upgraded card is chosen, `rollDice(#standard)` (`ActionCards.vue upgradeCard`). At most **3** upgraded cards (`canUpgradeCard`). | trigger `[human]` **IN-11**; choice `[code]` |
| **Revert** an accidental upgrade. This removes it from all stored rounds. | `[human]` **IN-12** |
| Once ARNO has **≥ 2 CP**, he always takes an association worker instead of an upgrade. | `[prose]` `upgradeCard.note` |
| Bonus tile: he never takes the pre-printed bonus. **Left or right tile by d2**. He only benefits from three tiles: partner zoo, partner university, reputation. For zoo/university tiles the human opens the matching roll. | trigger `[human]` **IN-13**; d2 `[code]`; usage `[prose]` |
| Marine Worlds: he takes the bonus tile when he passes 15 reputation, if one is still available. | `[prose]` |
| ARNO earns CP, card upgrades, reputation and association workers from his zoo mat (right area only) and the general boards. He gets nothing from money, buildings, enclosures, X tokens, animal/sponsor card effects or break income. | `[prose]` `aboutARNO.*` |

### 2.6 Breaks `[prose]`, except one input

During a break ARNO draws **3 cards** from the deck. He keeps the first project card,
plays the first animal card to his mat (which may trigger the human's bonus), and discards
the rest. With the project module, the human enters how many sponsor cards were discarded
in this break (0–3): **IN-10** (`BreakInfo.vue`). Everything else about the break (worker
return, display discard and refill, income) uses the normal Ark Nova rules, with no money
for ARNO. `[absent]`: worker return for ARNO and break-token reset are not mentioned.

### 2.7 Interaction rules `[prose]`

- ARNO never uses or receives money.
- ARNO can **never be the target of interactive effects**. The human uses the solo
  alternative effect of those cards.
- The animal cards stacked on his mat are reference values for the human's card effects.

## 3. Game end and scoring

| Rule | Tag |
|---|---|
| The game-end trigger is not modelled. The human clicks **Finish Game** at any time. | `[human]` **IN-14**, trigger `[absent]` |
| ARNO end-game CP = `clamp(tokensOnScoringCard − 2, 0, 4) + tokensOnNotepad` (`FinalScoring.vue getBotConservationPoints`) | `[code]` **OUT-16** |
| ARNO appeal is prefilled from `appealCount`, which includes starting appeal but **not** appeal from reputation overflow. The human edits it. | `[code]` + `[human]` **IN-15** |
| CP and appeal for each player are typed in. VP = appeal − f(CP), where f(cp) = 114 − 2cp for cp ≤ 10, otherwise 94 − 3(cp − 10), floored at 0. | `[human]` **IN-15**, `[code]` |
| Human players score their Final Scoring cards and end-game icons. | `[prose]` |

## 4. Inputs (everything the app asks the human)

Split by whether a script could read the value from a TTS table instead of asking.

| ID | Input | When | Derivable from table state? |
|---|---|---|---|
| IN-01 | Sponsor cards ARNO discarded at setup (project module) | setup | **Yes**, if setup is scripted |
| IN-02 | Snapped card was a sponsor (project module) | TAKE_CARD_DISPLAY | **Yes** (card type) |
| IN-03 | Reroll partner zoo (zoo unavailable or already owned) | zoo action | **Yes** (availability and ownership) |
| IN-04 | Reroll university / animal type | university action | **Yes** |
| IN-05 | Override association action (worker collision) | association card | **Yes**, from his worker positions, but the human applies the "next higher, else lower" prose |
| IN-06 | Zoo vs university "missing most" | association fallback | **Mostly**. "Missing most" has no exact definition; Pick Random is the app's fallback. **Judgement** |
| IN-07/08/09 | Project counts on mat and board | project work | **Yes** |
| IN-10 | Sponsor cards discarded in a break (project module) | break | **Yes** |
| IN-11 | ARNO earned a card upgrade | when a bonus triggers | **Yes**, if ARNO's mat and track bonuses are modelled |
| IN-12 | Revert a mistaken upgrade | correction | Not needed when automated |
| IN-13 | ARNO earned a bonus tile | rep/CP track | **Yes** |
| IN-14 | Game ended | end | **Yes** (normal end condition) |
| IN-15 | Final CP and appeal for all players | scoring | **Yes** |
| IN-16 | Navigation Next/Back (PageDown/PageUp) | every turn | Turn change |

Not asked, but the human must keep track of these today (the app does not model them):
ARNO's CP, reputation, break-token position, held partner zoos and universities, worker
positions, project cards on his mat, which bonuses are uncovered on his mat, the display
contents, and the conservation-project boards.

## 5. Outputs (everything the human must apply)

| ID | Output | Shared state touched |
|---|---|---|
| OUT-01 | Show the active card and slot, upgraded or not, and the new slot order | ARNO mat (virtual) |
| OUT-02 | +n appeal | appeal track; may reach game end |
| OUT-03 | +n reputation (overflow past 15 not tracked) | reputation track; reputation bonuses, display range |
| OUT-04 | +n CP (removes starting −CP reminder tokens first) | CP track; CP bonuses, bonus tiles, game end |
| OUT-05 | Advance break token n | break track; may **trigger a break** |
| OUT-06 | Token on final scoring card / notepad | ARNO mat |
| OUT-07 | Snap display card #d6, then discard/stack it and refill the display | display, deck, discard; may trigger the human's effects |
| OUT-08 | Take partner zoo #d5 to his mat | association board; uncovers a mat bonus |
| OUT-09 | Take university #dN (and animal type) to his mat | association board; uncovers a mat bonus |
| OUT-10 | Place an association worker on a task | association board |
| OUT-11 | Support project X with a token on slot Y and gain that slot's CP and bonus | project cards, base projects, CP track |
| OUT-12 | Donate | donation track **(semantics unknown)** |
| OUT-13 | Upgrade card #d(remaining) | ARNO action cards |
| OUT-14 | Bonus tile left/right (d2), only zoo/university/reputation usable | bonus tile display |
| OUT-15 | Break: draw 3, keep first project, stack first animal, discard rest | deck, discard, ARNO mat |
| OUT-16 | End-game CP from tokens; final appeal | scoring |
| OUT-17 | Project module: preferred slot and kiosk count status | display only |

## 6. Randomness

- Everything uses `Math.random` through `@brdgm/brdgm-commons` (`rollDice`,
  `rollDiceDifferentValue`, `randomEnum`, `randomEnumDifferentValue`) or `lodash.shuffle`.
  **Nothing is seeded.**
- **Persisted** (in localStorage via `pinia-plugin-persistedstate`): slot order, upgraded
  cards, chosen slot, token counts, appeal count, sponsor-discard counts.
- **Not persisted**: the display-card number, the zoo/university/animal-type rolls, the
  bonus-tile side, the conservation-project picks, and the upgrade target. These are
  rolled in component `data()`/`setup()`, so they come out differently after navigating
  away and back. The upgrade itself is persisted, but which card got it is decided at
  click time.
- Undo in the app = **Back** navigation (stored rounds are reused, later rounds are
  recalculated on the next visit) and **Revert upgrade**. ARNO's next card is drawn only
  when the human navigates to the bot page.
- For a faithful seeded port, the call order of every roll must be matched, including the
  unconditional d2 in §2.4 and the `lodash.shuffle` algorithm in `CardSlots.new()`.

## 7. Shared-state interactions (summary)

| Shared component | ARNO reads | ARNO writes |
|---|---|---|
| Display (6 cards) | position #d6 only | removes 1 card; refill; break discard |
| Deck/discard | – | 3 draws per break; discards sponsors |
| Conservation projects (base + played) | counts IN-07..09, free slots | token placement, takes reward |
| Bonus tiles | left/right availability | takes one |
| Association board | zoo/university availability, own workers | workers, zoo, university, donation |
| Tracks (appeal, CP, reputation, break) | own positions (for bonuses) | moves own markers, break token |
| Human's card effects | – | his stacked animals trigger human bonuses; never targeted |
| Breaks | – | his BREAK actions can trigger them |
| Game end / scoring | – | end-game CP from tokens |

## 8. Tests in the helper

`tests/unit`: `BotActions.spec.ts` (12 cases: random pick and several card/slot/level
combinations, including the ≥ 6 token rule), `Cards.spec.ts`, `CardSlots.spec.ts` (shuffle,
upgrade, move-first, revert), `ProjectModuleTracker.spec.ts` (positions, slots, kiosks,
preferences), `getDifficultyLevel.spec.ts`.

**Environment note:** `npx vitest run` fails here because Vite 8/rolldown needs
Node `^20.19 || >=22.12`, and the machine has 20.18.0 (nvm-windows is installed). Phase 3
prerequisite: install Node 22 LTS.

## 9. Open questions (need a decision from the owner, not from me)

1. **Rules version.** The app implements A.R.N.O. **3.0**. The reference TTS table is
   **2.0**. Which one do you play? I have not compared the app with the printed 3.0 rules.
   Can you share that PDF (it is on BGG)?
2. **DONATE** (Association upgraded) has no defined cost or reward in the app. What does
   ARNO's donation do?
3. **Association fallback CP.** The prose says "+2 CP, break +2". The card data
   (`Cards.ts`) gives **CONSERVATION 1**, BREAK 2, and the unit test
   `association-upgraded-5-easy` pins CP 1. Which is right?
4. **Scope:** Marine Worlds? The ARNO project module? Each one adds input paths, and
   Marine Worlds changes the starting CP (−3 vs −5) and the university count.
5. **Rerolls.** The app leaves "is this zoo/university available?" to the human, with a
   reroll button that excludes only the current value. If automated, should the adapter
   reroll until an available one comes up? That differs subtly from the app's
   human-driven reroll.
6. **"Missing most"** (zoo vs university in the fallback). Is there an exact definition?
   Otherwise, should it be "fewer owned; tie → random d2"?
7. **`[absent]` rules:** the order of actions within one card, a break triggered partway
   through ARNO's turn, the case where no conservation project is possible, reputation
   overflow past 15, ARNO's worker return at breaks, the end-game trigger for ARNO, and
   the purpose of the kiosk count. These need the printed rules.
