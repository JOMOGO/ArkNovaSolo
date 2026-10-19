# Changes to "Ark Nova - Complete Scripted"

`dist/ArkNova_Scripted_ARNO.json` differs from the base save
(`mods/original/3812420704.json`, mod v14.2.2) in **only two fields**: the Global
`LuaScript` and `SaveName`. Objects, assets, positions and object scripts are byte-identical.
This is checked by the build (see README).

The Global script is the base script plus:
1. three **one-line text edits** (`hooks/hooks.json`). Each anchor must occur exactly once,
   otherwise the build fails;
2. the **ARNO bundle** (`arno/**/*.lua`), inserted just before the base mod's `on_*`
   interaction wrapper (`local handler_names = {}`);
3. **wrappers** that the bundle installs at load time around existing global functions. No
   base function body is edited. Every wrapper does nothing unless an ARNO is in the game,
   so a game without ARNO behaves exactly like the base mod.

## 1. Text edits (`hooks/hooks.json`)

| ID | Location (base `Global.lua`) | Edit | Why |
|---|---|---|---|
| H2 | `setup_game`, after `players` is built from seated players (~4039) | `if ARNO then ARNO.setup.add_bots(players) end` | ARNO entries join `players` before the per-colour component loop, so their colours keep boards, counters and tokens |
| H3 | `continue_setup_game`, start player (~4219) | `(ARNO and ARNO.setup.starting_player(players)) or players[math.random(#players)]` | ARNO 3.0: a human is always the start player |
| H8 | `start_game`, `expected_discards` (~8346) | `(ARNO and ARNO.setup.expected_discards(players)) or 4 * #players` | humans discard 4 each; ARNO discards the cards he doesn't keep |

## 2. Wrappers (installed by `arno/adapter/hooks.lua` and `arno/adapter/apply.lua`)

| ID | Function | ARNO behaviour |
|---|---|---|
| H1 | `game_setup_panel_xml` | adds a row per unseated colour (ARNO Off / Level 1–10) and the project-module toggle |
| H5 | `setup_player_maps` | ARNO gets map A and his base action cards, CP debt is set, then a **humans-only window** opens for the map, Marine Worlds draft and setup-discard prompts |
| H6 | `destruct_action_card_decks` | skips colours whose action-card deck is already gone (ARNO's cards were dealt during his own setup); fixes the setup crash before the discard prompt |
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
| H16 | `wait_for_all_hand_counts`, `other_hand_counts`, `final_scoring_cards`, `player_hand_cards`, `hands_released_guids`, `card_settled_in_hand` | ARNO's (non-existent) hand is never read or waited for |
| H17 | `game_winners` | ARNO wins ties against humans |
| H18 | `map_income` | card 265 Franchise Business counts ARNO's kiosks as the module tracker value (0 without the module), not map A's printed kiosk |
| H19 | `action_selection_panel_xml` | one hint line for humans: "Undo later choices: press the rewind arrow twice." |
| H20 | `on_action_card_button_clicked`, `on_claim_button_clicked`, `take_association_task`, `open_sponsor_panel`, `on_building_placement_go_back`, `note_player_interaction`, `onObjectPickUp`, `set_player_panel`, `break_x` | **owner request, for humans:** a "Back to action choice" button inside the action's own panel (grown to fit) right after choosing any action, until the next click or card pick-up. Restores the player's state exactly (X-tokens refunded, card put back). Cards: the break-token move is held back until the player commits (Snap/Draw) and dropped on Back. Association tasks 3/4/5 get "Back to association tasks" in their picker/project panel (workers go home, task list restored, then "Back to action choice" is available again). Sponsors "Play a Sponsor Card" gets "Back to sponsor choice" in the sponsor panel, still available after selecting a card (until Confirm). Build: after the mod's "Go back to building selection", "Back to action choice" returns if nothing was built yet in that action. Not offered for X-token mode, multiplier or hypnosis turns, or a venom-poisoned card |
| PANEL | `resume_checkpoint` | re-draws the ARNO panel after load or rewind |

## 3. Additions to base data (at load time)

- `cnsts.saved_globals` += `"arno_state"`: ARNO's state is saved in every checkpoint.
- `cnsts.saved_player_fields` += `"is_arno"`, `"arno_index"`.
- New globals: `ARNO` (module), `arno_state` (persistent), `arno_setup` (setup choices),
  `on_arno_*` button handlers.
- New UI panel `arno` (through the mod's `set_active_panel`).

## 4. Not changed

The base mod's rules for humans, object scripts, assets, decks, positions and the official
solo challenge (1 human, no ARNO) are not changed.
