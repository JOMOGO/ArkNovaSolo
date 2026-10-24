# Changes to "Ark Nova - Complete Scripted"

`dist/ArkNova_Scripted_ARNO.json` differs from the base save
(`mods/original/3812420704.json`, mod v14.2.2) in **only two fields**: the Global
`LuaScript` and `SaveName`. Objects, assets, positions and object scripts are byte-identical.
This is checked by `tests/test_arno_build.py`, which also catches an accidental edit to an
object script under `src/objects/`.

The Global script is the base script plus:
1. **edits** made directly in `src/Global.lua` (§1; `git diff upstream -- src` shows
   them). They are used for changes **inside** a function body and to the mod's static
   panel text and card data. A base-mod update is merged in from the `upstream` branch, so
   an edit under changed code shows up as a merge conflict (see README);
2. the **ARNO bundle** (`arno/**/*.lua`), inserted just before the base mod's `on_*`
   interaction wrapper (`local handler_names = {}`);
3. **wrappers** that the bundle installs at load time around existing global functions,
   for behaviour before or after a whole function (mostly an ARNO-only branch) and for
   anything that depends on runtime state. Every ARNO wrapper does nothing unless an ARNO is
   in the game. The human conveniences H19 (undo hint, action panel flush right), H20 (Back
   buttons) and H21 (Cancel shown as Back, bonus build back to the action panel) apply in **every** game, also without ARNO; otherwise a game without ARNO
   behaves exactly like the base mod.

## 1. Edits to `src/Global.lua`

| ID | Location (base `Global.lua`) | Edit | Why |
|---|---|---|---|
| H2 | `setup_game`, after `players` is built from seated players (~4039) | `if ARNO then ARNO.setup.add_bots(players) end` | ARNO entries join `players` before the per-colour component loop, so their colours keep boards, counters and tokens |
| H3 | `continue_setup_game`, start player (~4219) | `(ARNO and ARNO.setup.starting_player(players)) or players[math.random(#players)]` | ARNO 3.0: a human is always the start player |
| H8 | `start_game`, `expected_discards` (~8346) | `(ARNO and ARNO.setup.expected_discards(players)) or 4 * #players` | humans discard 4 each; ARNO discards the cards he doesn't keep |
| H6 | `destruct_action_card_decks` (~7066) | skip a zone without a deck | ARNO's action cards were dealt from his colour's zone during his own setup; fixes the setup crash before the discard prompt. Every game (harmless without ARNO) |
| H16 | `wait_for_all_hand_counts` (~10554) | loop over `(ARNO and ARNO.setup.humans(players)) or players` | ARNO's (non-existent) hand is never waited for |
| H19 | `action_selection_panel_xml` (~10132-10154), 3 edits | `offsetXY="-60 0"` → `"0 0"`; height 370 → 392; one `<Text>` line before the closing `</VerticalLayout>` | **owner request, every game:** the hint "Undo later choices: press the rewind arrow twice."; the panel sits flush right like the mod's other panels |
| H21 | 8 panel templates: card selection (~8055), project support (~9298), extra shift (~9938), claims (~13559), trade (~13975), marketing (~14158), cut down (~17017), building placement (~17102, ~17109), 9 edits | red `#C61715` → Back colour `#8A6D1F`; `Cancel` → `Back`; `Go back to` → `Back to` | **owner request, every game:** the mod's red Cancel buttons only ever go back one step, so they are Back buttons, same handlers. Red **Pass** buttons stay (passing is a game choice), also glide discard's Pass in the card-selection panel and the claims panel's Pass |
| FIX471 | `cnsts.cards.base`, card 471 (~2436) | adds `enclosure={repthouse=2}` | **base-mod data fix, every game:** African Spurred Tortoise was missing its Reptile House option (printed card: Reptile House 2) |
| FIX138 | after `finish_animal_play` (~12021) | adds the reward function `reef_effect(player, source)`: one claim per played animal with a reef effect, the loop `finish_animal_play` uses for reef animals | **base-mod fix, Marine Worlds:** the left slot of Sea Animal Management Plan (card 138, printed: 2 CP + the reef icon) awards `"reef effect"`, which had no handler, so `apply_reward_string` called nil and the claims stopped. Found by `tests/lua/int_cards.lua` |

## 2. Wrappers (installed by `arno/adapter/hooks.lua` and `arno/adapter/apply.lua`)

| ID | Function | ARNO behaviour |
|---|---|---|
| H1 | `game_setup_panel_xml` | adds a row per unseated colour (ARNO Off / Level 1–10) and the project-module toggle |
| H5 | `setup_player_maps` | ARNO gets map A and his base action cards, CP debt is set, then a **humans-only window** opens for the map, Marine Worlds draft and setup-discard prompts |
| H8 | `start_game` | closes the window (full turn order back), deals ARNO's 8 cards (keep ≤ 2 projects, discard the rest) and his face-down final scoring card |
| H8 | `discard_cards_to_new_pile` | remembers the setup discard pile, so ARNO's setup discards join the same pile (zone contents lag physical moves) |
| H9 | `create_action_selection_panel` | an ARNO turn starts here (after the mod's own `"turn"` checkpoint); human-only prompts (multiplier, hypnosis) are ignored for ARNO |
| H10 | `render_claims_table` | ARNO's claims are resolved in order; ARNO never gets a panel and the claims engine never ends his turn |
| H11 | `apply_reward_string` | ARNO keeps appeal, CP (debt first), reputation (cap 15, no Cards gate), upgrades and workers; everything else is ignored and logged |
| MONEY | `update_money` | no-op for ARNO |
| XTOKEN | `update_x_token` | no-op for ARNO |
| H12 | `break_phase_discard` | ARNO has no hand limit (runs over humans only) |
| H12 | `start_player_income` | ARNO's income slot runs his **break draw** (3 cards: first project kept, first animal on mat, rest discarded), after an `"income"` checkpoint |
| H13 | `targetable` | ARNO is never the target of an interactive effect |
| H14 | `prompt_final_scoring_discard` | ARNO discards nothing |
| H14 | `start_final_scoring` | the discard round runs over humans only |
| H14 | `score_final_scoring_cards` | ARNO scores `clamp(tokens−2,0,4) + notepad tokens` CP (remaining debt first) |
| H16 | `other_hand_counts`, `final_scoring_cards`, `player_hand_cards`, `hands_released_guids`, `card_settled_in_hand` | ARNO's (non-existent) hand is never read or waited for |
| H17 | `game_winners` | ARNO wins ties against humans |
| H18 | `map_income` | card 265 Franchise Business counts ARNO's kiosks as the module tracker value (0 without the module), not map A's printed kiosk |
| H20 | `on_action_card_button_clicked`, `on_claim_button_clicked`, `take_association_task`, `open_sponsor_panel`, `on_building_placement_go_back`, `note_player_interaction`, `onObjectPickUp`, `set_player_panel`, `break_x` | **owner request, for humans:** a "Back to action choice" button inside the action's own panel (grown to fit) right after choosing any action, until the next click or card pick-up. Restores the player's state exactly (X-tokens refunded, card put back, any association worker placed since goes home and is free again). Cards: the break-token move is held back until the player commits (Snap/Draw) and dropped on Back. Association tasks 3/4/5 get "Back to association tasks" in their picker/project panel (workers go home, task list restored, then "Back to action choice" is available again). Sponsors "Play a Sponsor Card" gets "Back to sponsor choice" in the sponsor panel, still available after selecting a card (until Confirm). Animals: selecting an animal card keeps "Back to action choice" until Confirm. Build: after the mod's "Go back to building selection", "Back to action choice" returns if nothing was built yet in that action. Cards: "Snap a card" and Cards II's "Draw N cards" (from reputation range) get "Back to Cards choice" until a card is picked up (no "Back to action choice" after that: the break token has moved). Not offered for X-token mode, multiplier or hypnosis turns, or a venom-poisoned card |
| H21 | `on_persistent_reward_button_clicked` | **owner request, for humans:** A bonus build (Engineer) started from the action panel returns to the action panel afterwards (Back, a failed start or Confirm), like the mod's trade and marketing; before, it reached an empty claims table, which ended the turn without an action |
| PANEL | `resume_checkpoint` | re-draws the ARNO panel after load or rewind |

## 3. Additions to base data (at load time)

- **ARNO's action cards (owner request):** in ARNO's setup his 5 dealt action cards are
  replaced by spawned cards showing the real ARNO 3.0 cards (same names and tags; face =
  side I, back = side II; Animals, Build and Cards green for levels 1-3, red for 4+;
  one 4x2 sheet per side, CustomDeck id 7701 with unique backs). The sheets are on Steam Cloud
  (`tools/arno_card_urls.json`, set by the build as `ARNO_CARD_IMAGES`, see README);
  without them the mod's cards stay.
- `cnsts.saved_globals` += `"arno_state"`: ARNO's state is saved in every checkpoint.
- `cnsts.saved_player_fields` += `"is_arno"`, `"arno_index"`.
- New globals: `ARNO` (module), `arno_state` (persistent), `arno_setup` (setup choices),
  `on_arno_*` button handlers.
- New UI panel `arno` (through the mod's `set_active_panel`).

## 4. Not changed

The base mod's rules for humans, object scripts, assets, decks, positions and the official
solo challenge (1 human, no ARNO) are not changed (apart from the card fixes FIX471 and FIX138).
