# Ark Nova - Complete Scripted (TTS v14.2.2): Mod Architecture

Analysis of the extracted scripts in `src/` (from `mods/original/3812420704.json`, see `src/manifest.json`).
All references are `src/Global.lua:<line>` of the unedited extract (branch `upstream`) unless stated otherwise. Written as groundwork for integrating an
automated ARNO opponent (Yellow) against a human (Red).

Conventions used below:

- "players" = the global Lua array `players` of player *tables* (not TTS `Player` objects).
- "claims" = the mod's internal queue of pending choices/rewards (`player.claims`), rendered as button panels.
- Where something could not be verified from the source alone it is marked **(unverified)**.

---

## 1. Overview and code organisation

`Global.lua` is one hand-written file of 18,058 lines. No `require`/bundler. Rough layout:

| Lines | Content |
|---|---|
| 1-100 | Small helpers: `getByType`, `getCard`, `getDeck`, `deal_tagged_card(s)`, `tile_in_zone`, `null_func`, `single/double/triple`, counter helpers `set_counter_display` (70), `set_counter` (86), `get_counter_value` (90), `set_icon_counter` (94), `get_icon_counter_value` (98). |
| 102-1211 | `HexBoard` module (IIFE). Hex grid geometry + `Board` class (`Board.new` 247, `canPlace` 395, `findValidPlacement` 411, `place` 595, `placeUnchecked` 606, `remove` 619, many count/query helpers up to `countDistinctTileShapes` 1195). Pure Lua, no TTS calls. |
| 1213-2970 | `cnsts` module (IIFE): all static data. GUID tables per color, positions, map data (`cnsts.map_data` 1592), card database (`cnsts.cards.base` 2269, `cnsts.cards.mw` 2496), final scoring rules (2217), solo constants (`cnsts.solo` 2192), action strengths (2557), setup options (2758), checkpoint/save schema (2827-2942), object script templates (2800, 2808, 2944). |
| 2971-3800 | Bootstrap and rewind/checkpoint system: `onLoad` 2976, `resolve_scene_objects` 3022, `start_fresh_table` 3048, `onSave` 3104, `take_checkpoint` 3127, `checkpoint_state` 3216, `restore_checkpoint` 3467, `restore_scene_after_load` 3634, `CHECKPOINT_RESUMES` 3774, `show_unresumable_panels` 3791. |
| 3810-4320 | Setup: setup panel, `setup_game` 3913, `continue_setup_game` 4190, `setup_solo_challenge` 4257, `show_solo_difficulty_panel` 4277. |
| 4320-4610 | Association board refill (4330), break token (4352-4375), tracks: appeal (4440), CP (4523), CP bonuses (4499-4600), money (4604). |
| 4610-6550 | Reward engine: card ability functions (`inventive`, `sprint`, `hunter`, `pouch`, ... ), rep track (`update_rep` 5490), `apply_reward_string` 5635, effects/hooks (`process_effects` 6144, `add_remove_hooks` 6199, `apply_hooks` 6230), icons (6251), claim creation (6290-6350), search/discard helpers (6352-6545). |
| 6546-7060 | Maps per player (`apply_player_map` 6586, `apply_map_choice` 6603), cubes, partner zoos (6804-6890), universities (6891-7002), workers (7003-7050). |
| 7051-7900 | Action cards: dealing (7378), MW draft (7422-7895), action-card tokens (multiplier/venom/constriction 7081-7375), `onObjectPickUp` dispatcher 7484. |
| 7897-8330 | Panel infrastructure (`active_panels`, `render_active_panels` 7901, `set_player_panel` 7963), status panels, card-selection panel (8073), setup discard (8252), `start_game` 8327. |
| 8365-8540 | `start_player_turn` 8365, persistent rewards (8420). |
| 8538-10230 | Action strength/availability (8538-8615), interactive effects (hypnosis/pilfer 8616-8920), workers, conservation projects (8961-9545), Association action (9546-10080), action selection panel (10082-10225). |
| 10226-12045 | Animals action: costs/conditions/enclosures (10226-10545), hand helpers (10546-10660), animal panel and play (10691-12020). |
| 12047-12330 | `refill_display` 12047, break (12118-12305), income phase (12308-12530). |
| 12532-13460 | End of turn (12539-12575), post-action rewards, turn order (12834-12850), game end (12857-12890), solo track (12890-12920), final scoring (12954-13460). |
| 13462-13700 | Claims table: `render_claims_table` 13574, `on_claim_button_clicked` 13661, `on_claim_pass_clicked` 13689. |
| 13703-13860 | Action cards on board, `use_action_card` 13759, `on_action_card_button_clicked` 13788. |
| 13860-14700 | Sponsors action, trade, marketing. |
| 14700-15580 | Card flips (upgrades), display mark/snap/rep-range draw, shark attack, digging, rescue, store (caves). |
| 15578-15690 | Cards action (`cards_action` 15609). |
| 15683-17790 | Build action, tile placement, expand, reconstruction, cut down, building tile physics callbacks, map geometry. |
| 17790-18040 | Map selection at setup. |
| 18043-18058 | Wrapper: every global function named `on_*` is wrapped to call `note_player_interaction()` first. |

### Global state

There is no central state object. State is in plain Lua globals plus per-player tables:

- Game-wide globals (persisted list in `cnsts.saved_globals` 2827): `game_started`, `marine_worlds_enabled`,
  `discard_face_down`, `left_to_right_order`, `interactive_effects`, `solo_turn_cubes`, `solo_cubes_advanced`,
  `final_scoring_discard_triggered`, `game_end_triggered`, `break_init_val`, `break_current_val`, `base_projects`,
  `added_projects`, `player_status`, `all_zoo_hooks`, `checkpoint_resume`, etc.
- Object globals: `zoo_deck`, `final_scoring_deck`, `discard_pile`, `base_conservation_deck`, `rep_max_bonus`,
  `placeholder_card`, `display_cards[1..6]`, `display_marks`, `cp_bonuses_5`, `cp_bonuses_8`, `break_token`,
  `zones`, `bags` (`resolve_scene_objects` 3022).
- Turn globals: `current_player`, `final_turn_player`, `income_phase_order`.
- Transient per-color UI/action state tables (NOT persisted): `action_selection_state` (8536), `association_actions`
  (9632), `animal_actions` (10734), `sponsor_actions` (13858), `build_actions` (15725), `project_supports` (9216),
  `tile_placements` (15997), `selection_panels` (8007), `claims_players` (13460), `snap_player`/`rep_draw_player`/
  `digging_player` single globals (14938-15229), etc.
- `players[i]`: per-player table (see section 6).

### How the UI is generated

`Global.xml` is just a comment. All UI is built at runtime as XML strings:

- During setup, functions call `UI.setXml(...)` directly with a whole document (e.g. 3834, 3885, 4285, 7468, 8274, 17999).
- During the game, every panel is a string in `active_panels[key]` (7897). `set_active_panel(key, xml)` (7923) /
  `clear_active_panel` (7928) schedule `render_active_panels` (7901), which concatenates all panels and calls
  `UI.setXml` with the result (one frame debounce, `schedule_panel_render` 7909). Small updates use
  `UI.setAttributes` (`set_ui_attributes` 7918).
- Per-player panels: `set_player_panel(color, xml, refresh)` (7963) stores the panel under the color key. Each panel's
  root has `visibility="<Color>"`, so only that seat sees it. Waiting text uses `status_panel_xml` (7943).
- Button callbacks are global `on_*` functions with TTS signature `(player, value, id)`; 82 of the 90 `on_*` functions
  discard the first (clicking-player) parameter (declared `(_, value, _)`, `(_, color, _)` etc.); the color is parsed
  out of the value string (e.g. `"Red_3"` in `on_action_card_button_clicked` 13788). Only panel visibility stops another seat from clicking.

### Object scripts (`src/objects/*.lua`)

37 files, 548 lines total. They are not behaviour:

- 16 partner zoos + 15 universities + 2 aquarium tiles contain `Key=value` lines (e.g. `Africa=1`, `Income=0`), i.e.
  legacy icon data. Global never reads object scripts (no `getLuaScript` call anywhere in Global.lua); partner zoo /
  university icons come from `cnsts.universities` (1232) and `append_icon_groups`.
- `The_Kraken_Table_0b2ed0.lua`: `onLoad` sets `self.interactable = false`.
- Scripts Global *injects* at runtime: `cnsts.placeholder_card_script` (2800, the zoo-deck placeholder forwards
  pick-ups to `on_placeholder_card_picked_up` 15571), `cnsts.building_tile_script` (2808, building tiles call
  `on_building_tile_settled` 17451 / `on_building_tile_picked_up` 17170), and `cnsts.counter_script` (2944, see 6/13).

---

## 2. Setup flow

1. `onLoad` (2976) with empty script state -> `resolve_scene_objects` (3022) -> `start_fresh_table` (3048), which resets
   globals and puts an invisible click-button on the "Setup Game" object (`cnsts.button_guids.setup_game`, tooltip
   "Please ensure all players are seated before clicking this button").
2. `on_setup_game_button_clicked` (3825): requires >= 1 seated non-Grey/Black player (`seated_game_players` 3890),
   destroys the button, shows `game_setup_panel_xml` (3837).
3. Options (`cnsts.setup_options` 2758), each toggled by `on_setup_option_toggled` (3867) and written to a global by
   `on_setup_proceed_clicked` (3876):
   - `marine_worlds_enabled` (Marine Worlds expansion),
   - `discard_face_down`,
   - `left_to_right_order` (play order),
   - `interactive_effects` (Pilfering, Hypnosis, Venom, Constriction). Locked to "Disabled" (`solo_state = 2`) when one
     player is seated (`setup_option_locked_state` 3818), and forced `false` again at 3881-3883.
   Then `apply_association_board_image` (3900) and `setup_game`.
4. `setup_game` (3913):
   - Grabs `zoo_deck`, `base_conservation_deck`, `final_scoring_deck`. With MW: removes replaced base cards by number
     prefix (3918-3940, 3983-3985), merges MW decks, swaps bonus tiles. Without MW: destroys MW decks.
   - If `not interactive_effects`: removes final scoring cards 009 and 017 (4008-4010).
   - Draws 2+2 CP bonus tiles for the 5 and 8 CP checkpoints (`draw_bonus_tiles` 3947) and, with MW, the
     max-reputation bonus tile `rep_max_bonus`.
   - Hides the zoo deck and creates a scripted placeholder card (4016-4034).
   - **Builds `players`** from `seated_game_players()` (4036-4039): `{color, steam_name}`.
   - Loops over all four colors White/Red/Blue/Yellow (4043-4082): for seated colors installs counter scripts and
     stores object refs; for **unseated colors destroys their tokens, counters, icon counters, player board** and
     drafting box.
   - Initial values (4084-4117): money 25, appeal 0, CP 0, rep 1, income 5, score -14, all icon counters 0,
     `worker_count = 1`, empty lists, all action cards unflipped.
   - Base conservation projects: 3, or 4 with >3 players (4121-4144). In 2-player games a neutral cube blocks one slot
     on each base project (4134-4138) and on donation spots 5/7/10 (4146-4150).
   - Break track start: 15/12/9 for 4/3/2 players (4152-4163); nil for solo.
   - Bag integrity check `bag_setup_problems` (3707), `lock_bags`.
   - Waits until the zoo deck has 212 (266 with MW) cards, then `continue_setup_game`.
5. `continue_setup_game` (4190): deals 6 display cards, locks decks, `refill_association_board` (4330), picks a random
   starting player and re-orders `players` by seat color order (4215-4240). If `#players == 1` ->
   `setup_solo_challenge` and return. Otherwise destroys the solo board, gives appeal 1/2/3 to players 2/3/4
   (4247-4250), then `setup_player_maps`.
6. `setup_solo_challenge` (4257): moves the solo board (`cnsts.solo.board_guid` "0f91b5") next to the player board,
   spawns 7 neutral cubes (`solo_turn_cubes`, GUIDs), `show_solo_difficulty_panel` (4277) -> `on_solo_difficulty_clicked`
   (4294): Easy/Medium/Hard = +20/+10/+0 starting appeal, then `setup_player_maps`.
7. Map selection: `setup_player_maps` (17951) auto-proceeds if each player already has exactly one map tile on their
   board; otherwise `show_map_setup_panel` (17810), "classic" / "custom" / "mirror" choices, ready panels
   (`show_map_ready_panels` 17980, `on_map_ready_clicked` 18002). `apply_player_map` (6586) -> `apply_map_choice`
   (6603): sets board image, creates `player.map = HexBoard.Board.new(...)`, spawns starting tiles, the 7 project bonus
   cubes (`spawn_player_project_bonus_cubes` 6664), geographical cubes, and workers (`spawn_player_workers` 7029).
8. `finish_map_setup` (17972): MW -> action card draft `start_action_card_draft` (7422; solo: choose 2 of 3, otherwise
   pick-and-pass), `finish_drafting` (7842). Then `distribute_action_cards` (7071): `deal_action_cards` (7378) puts
   ANIMALS in slot 1 and shuffles the other four into slots 2-5; `finish_player_action_cards` (7055) deals 8 zoo cards
   to hand index 1 and 2 final scoring cards to hand index 2.
9. `start_setup_discard` (8252): every player selects 4 cards to discard (by picking them up), confirm button
   `on_setup_discard_clicked` (8302) -> `start_game` (8327): flips display face up, waits for discard pile of
   `4 * #players`, sets `game_started = true`, `all_zoo_hooks = {}`, `start_player_turn(players[1])`.

Action card names in the save are `CARDS 0`, `BUILD 0`, ... (base, 8 copies each = 4 colors x base/MW zones) and
`CARDS 1..4` etc. (MW variant cards). The trailing digit is passed as `num` to every action.

---

## 3. Player and color handling

- Supported colors: exactly White, Red, Blue, Yellow. Every per-color GUID table in `cnsts` has all four
  (e.g. `appeal_tokens` 1384-1388, `player_boards` 1469-1473, counters 2021-2055, `icon_counters` 2262-2266,
  `action_card_init_zones` 1475-1483, `drafting_boxes` 1569-1572, `store_params.hand_zones` 2168-2173). 1-4 players.
- **Who plays is decided once**, at `setup_game` 4036, from `Player.getPlayers()` filtered by `seated_game_players`
  (3890; excludes Grey and Black). There is no later join/leave handling (no `onPlayerChangeColor`,
  `onPlayerConnect` etc. anywhere).
- **A seat cannot exist without a human at setup time**: components of unseated colors are destroyed (4043-4082).
  After setup, the game runs on `players` entries keyed by color; the seated human is not re-checked, so if a human
  leaves a color mid-game the Lua keeps going (panels would just be invisible to everyone) **(unverified in play)**.
- `player.steam_name` is copied from the TTS player at setup (4038) and used in hundreds of log lines.
- Hands: hand zone index 1 = zoo cards, 2 = final scoring cards, 3/4 = MW draft (`DRAFT_UNSELECTED_INDEX`/
  `DRAFT_SELECTED_INDEX` 7417-7418), 5 = "store" (caves, `cnsts.store_params.hand_index` 2167). The save has 5 hand
  triggers for every color including Yellow; `Hands.DisableUnused` is false.
- Hand access is always via `Player[color].getHandObjects(i)` (5301, 5389, 6498, 7801, 8256, 8497, 8523, 10548,
  10556, 10564, 10577, 10585, 10613, 10623, 10649, 12176, 12199-12200, 12968, 13164, 15233, 15339, 15359, 15593, 15600)
  and dealing via `card.deal(1, color, index)` (23, 5422, 7444, 8861, 14920, 14997 ...). Whether these behave for a
  color with nobody seated is a TTS engine question **(unverified - test in game)**; with `DisableUnused=false` hand
  zones should still exist.
- **Hot-seat**: not explicitly supported. Since callbacks ignore the clicking player and only `visibility` gates
  panels, one human switching colors would see and could operate that color's panels, but setup would still only
  create players for colors seated at the moment of setup. **(unverified)**
- **Is Yellow usable?** Yes, as a normal human seat: it has its full component set. For a bot, Yellow's components
  only survive setup if a player is seated in Yellow when `setup_game` runs, or if `setup_game` is patched.

---

## 4. Turn manager

- TTS `Turns` API is never used (no `Turns.` in Global.lua); the save has `Turns.Enable = false`.
- Turn ownership: global `current_player` set in `start_player_turn` (8365). Order is the `players` array, sorted in
  `continue_setup_game` (4211-4240). `next_player` (12840), `previous_player` (12844), `right_neighbour` (12849).
- `start_player_turn(player)` (8365): `take_checkpoint("turn", player)`, `turns_taken += 1`, refreshes waiting
  panels for others, re-arms persistent rewards, venom check, then `create_action_selection_panel(player)` (10162).
- A turn ends **implicitly** when the player's claim queue empties: `render_claims_table` (13574) with
  `#player.claims == 0` and no `on_claims_empty` resume calls `clear_*_action_state` and `end_player_turn` (13592-13598).
  There is no "End turn" button.
- End-of-turn chain:
  1. `end_player_turn` (12539): checkpoint `"end_turn"` only if end-of-turn prompts are pending
     (`end_turn_prompts_player` 12532); multiplier offer (`offer_multiplier_action` 10175).
  2. `resume_end_player_turn` (12551): hypnosis cleanup, `move_action_card_to_front` (13742; used card -> slot 1,
     others shift right).
  3. `finish_end_player_turn` (12563): `offer_post_action_rewards` (12576), `check_venom_fee` (12919).
  4. `finish_player_turn` (12872): clears camouflage; game-end trigger check (multi-player, score >= 100);
     `refill_display(cb)`; in cb: solo cube advance (`advance_solo_turn_cube` 12890) possibly -> `start_final_scoring`;
     else `check_break_trigger({handler="after_turn", color=...})` (12146).
  5. `BREAK_RESUMES.after_turn` (12120): game-end check against `final_turn_player`, else
     `start_player_turn(next_player(player))`.
- There are no registered hooks/callback lists at end of turn; it is a hard-coded call chain. The nearest natural
  seams are `finish_player_turn` (12872), `BREAK_RESUMES.after_turn` (12120) and `start_player_turn` (8365).

---

## 5. Action UI

- `create_action_selection_panel(player, only_action, multiplier, hypnosis)` (10162) stores
  `action_selection_state[color]` and renders `action_selection_panel_xml` (10082): five buttons (one per action card
  slot 1-5, label = card name, strength shown left), "Take an X-token" toggle, X-token spinner, persistent reward
  buttons.
- Strength: `action_strength` (8538) = `cnsts.action_strengths[ai_level][slot]` (2557; `ai_level` = number of cubes on
  the "Artificial Intelligence" map, normally row 0 = `{1,2,3,4,5}`) + 1 if T1 effect active - 2 if constriction token
  + X-tokens used. `action_performable` (8553), `max_action_strength` (8557).
- Availability per row: `action_row_availability` (8597) -> `action_row_available` (8567): Build ->
  `build_action_available` (15692), Animals -> `animals_action_available` (10691), Association ->
  `association_action_available` (9605); Cards/Sponsors always available.
- Upgrades: `player.cards_flipped`, `build_flipped`, `animals_flipped`, `sponsors_flipped`, `association_flipped`
  (`cnsts.action_flip_attributes` 2645). Flipping via `card_flip` (14748) / `render_card_flip_panel` (14718) /
  `on_card_flip_clicked` (14757). Helpers `animals_upgraded` (14700), `sponsors_upgraded` (14706), `build_upgraded`
  (14712).
- X-tokens: `on_take_x_token_clicked` (10201) toggles X-token mode; clicking a row then calls `x_token_action` (13777):
  card goes to slot 1, +1 X-token via claim. `on_x_token_spin_clicked` (10211) sets how many to spend.
  `update_x_token` (4687) adds/removes physical tokens (cap 5).
- `on_action_card_button_clicked(_, "Color_slot", _)` (13788): spends X-tokens, `use_action_card` (13759: lifts card,
  venom, returns strength), `arm_multiplier_offer`, then dispatches by card-name prefix:
  - `CA` -> `cards_action(player, strength, num)` (15609)
  - `BU` -> `build_action(player, strength, num)` (15851)
  - `AN` -> `start_animals_action(player, strength, num)` (11000)
  - `SP` -> `start_sponsors_action(player, strength, num)` (14578)
  - `AS` -> `start_association_action(player, strength, num)` (9748)

**Programmatic invocation.** Everything is global, so Lua can call these directly:

- Simulate a click: `on_action_card_button_clicked(nil, "Red_3", nil)` after `create_action_selection_panel` set
  `action_selection_state["Red"]`. Same pattern for `on_claim_button_clicked(nil, "Red_1", nil)` (13661),
  `on_claim_pass_clicked` (13689), etc.
- Call the action entry functions directly (strength/num computed by the caller). However each action only *queues
  claims* and opens panels; resolution still waits for further button clicks or physical card pick-ups
  (`onObjectPickUp` 7484 dispatches to `handle_animal_pickup`, `handle_sponsor_pickup`, `handle_snap_pickup`,
  `handle_card_selection_pickup` ...) or physical tile drops (`on_building_tile_settled` 17451). All of them operate on
  a `players` entry with a player board, hand, map and counters. They are not designed to run headless for a
  non-player.
- Primitive state changes without UI: `apply_reward_string(player, "2 cp", source)` (5635) dispatches reward strings to
  `update_*` / named reward functions; `update_money` (4604), `update_appeal` (4440), `update_cp` (4523),
  `update_rep` (5490), `update_x_token` (4687). Note several of these queue claims (e.g. rep track rewards, CP bonus
  choices) for the player.

---

## 6. Player state model

Per-player table `players[i]` (created 4036-4113, filled by map setup 6603-6633). Two storage classes:

**(a) Values stored on TTS objects (counters)** - not in the Lua table. Each counter is an object whose single
zero-size button label holds the number (`set_counter_display` 70, read back with `get_counter_value` 90). The objects
carry `cnsts.counter_script` (2944, installed by `install_counter_script` 2971), which persists the button in its own
`onSave`. So these survive save/rewind as object state, independent of Global's script state:

| Value | Field (object ref) | GUID table |
|---|---|---|
| money | `money_counter` | `cnsts.money_counters` |
| appeal | `appeal_counter` (+ `appeal_token` on track) | `appeal_counters`, `appeal_tokens` |
| conservation points | `cp_counter` (+ `conservation_point_token`) | `cp_counters`, `conservation_point_tokens` |
| reputation | `rep_counter` (+ `reputation_token`) | `rep_counters`, `reputation_tokens` |
| income | `income_counter` | `income_counters` |
| score | `score_counter` | `score_counters` |
| icon counts (16 icons) | `icon_counters[icon]` | `cnsts.icon_counters[color]`, icons `cnsts.icons.all` 2258 |

Score is maintained incrementally: starts at -14 (4090), += appeal change (`apply_appeal` 4444), += change of
`cp_to_score` (4495: 2 per CP up to 10, 3 per CP above) in `apply_cp` (4529). Game end at >= 100
(`cnsts.game_end_score` 2176). (My reading: the counter is the official score + 100; i.e. 100 = tracks crossed.)

**(b) Lua fields** (persisted list `cnsts.saved_player_fields` 2860 + all card-effect and map attribute names, see
`saved_player_field_names` 3307):

- `color`, `steam_name`, `turns_taken`
- Action cards: `action_cards[slot] = {guid, tokens}`; `current_action`; `*_flipped`
- X-tokens: `x_tokens` (list of objects, max 5)
- Workers: `worker_count` (1-4), `workers` (GUIDs), `deployed_workers` ({guid, task})
- Partner zoos / universities: `acquired_partner_zoos` (habitat names), `acquired_universities` (names)
- Map: `map` (a `HexBoard.Board`, saved via `cnsts.saved_board_fields` 2938), `map_key`, `building_tiles`
  (object map), `project_cubes` (7 GUID slots from the map project bonus row), map flags (`map_*`)
- Played cards: `played_animals`, `played_sponsors` (GUIDs), `pouched_cards`, `bonus_tiles`, `sponsorships`
- Reward machinery: `claims` (not persisted; reset to `{}`), `post_action_rewards`, `persistent_rewards`,
  `partial_rewards`, `income` (list of `{reward, source}`), `hooks` (per-icon triggers), card-effect flags
- Hand: not stored; read from TTS hand zones each time (`player_hand_cards` 10640).

Board (`HexBoard.Board`, 247): `owner[cell]`, `terrain`, `blocked`, `tiles[id] = {cells, tags}`, `cellTags`
(placement bonuses), `special` cells; placement legality `canPlace` (395) and helpers.

---

## 7. Card display

- 6 slots, positions `cnsts.display_locs` (1215-1222), slot 1 leftmost. Objects in `display_cards[1..6]`, marks in
  `display_marks`. Cards are `locked` and unlocked selectively (`unlock_display_cards` 14926, `lock_display_cards`
  14932, `unlock_snappable_display_cards` 14985).
- Reputation range: `cnsts.rep_range_thresholds = {1,2,4,7,10,13}` (1425) - slot i is in range if rep >= threshold i
  (`cards_in_rep_range` 15028). Extra cost of taking from the display = slot number (`animal_play_cost` 10263 adds
  `display_pos`; `commit_project_support` 9478-9481 charges `display_pos` money for a project card).
- Taking a card: `onObjectPickUp` (7484) maps the picked-up display card to slot and routes to snap / rep-draw / mark
  / shark attack / digging handlers. E.g. `handle_snap_pickup` (14993) deals the card to hand, sets
  `display_cards[slot] = nil`, optional refill.
- `refill_display(done, leaving)` (12047): compacts remaining cards toward slot 1, draws from `zoo_deck` using
  `zoo_deck.getObjects()` order, handles MW "wave" cards (a wave card pushes the slot-1 card to the discard), moves
  cards smoothly, then `wait_for_departures` (12038) and `done`. Called after every turn (`finish_player_turn` 12878)
  and at breaks.
- Discard pile: `discard_pile` object (found in `start_game` 8349), face-down per `discard_face_down`. Helpers
  `discard_cards` (6471), `move_cards_to_discard` (6465), `report_discard` (6453).
- Draw pile: `zoo_deck` (hidden, invisible; a scripted placeholder sits at its visible position),
  `deal_cards_to_hand` (10601).
- **No deck-exhaustion / reshuffle logic found**: `refill_display` indexes `deck_objects[drawn]` unguarded (12063);
  `discard_pile.shuffle()` only appears in `scavenging` (5195).

---

## 8. Conservation projects and rewards

- Rows: `base_projects` and `added_projects`, each entry `{card_guid, {[slot] = cube_guid}}`. Base: 3 cards (4 with 4
  players) from `base_conservation_deck` (4121-4144). Added (played) projects: capacity `max(2, #players)`
  (`added_project_capacity` 8961); overflow discards the oldest with its cubes (`add_project_to_row` 8970).
- Cube ownership is the cube's color tag: `take_player_cube` (6650) tints and tags; `cube_owner_color` (6657) returns the
  first non-"cube" tag. Neutral blocking cubes (2-player, 4134-4138) have no color tag.
- Project kinds (`card.project`): `icons` (thresholds per slot), `release`, `breeding`, `management`
  (`supportable_project_slots` 9112). One support per project per player (`project_already_supported` 9038),
  except release with Migration Recording.
- Requirements: `project_match_count` (9012), boosts (wildcard token, breeding program cubes; `project_boost_available`
  9029), `breeding_project_met` (9069), `played_animal_with_icon` (9057).
- Flow: Association task 5 -> `start_project_support` (9392) -> panel (`project_support_panel_xml` 9281) ->
  `commit_project_support` (9470): optional play-from-hand/display, moves a cube from `player.project_cubes[index]`
  onto the slot, slot rewards (`project_slot_awards` 9232, `cnsts.project_slot_awards` 1312), map project bonus
  (`cnsts.map_data[map_key].project_rewards[index]`), optional income.
- `can_support_conservation_project` (9541) = cubes left and any offer.
- CP thresholds (`offer_cp_checkpoints` 4549): 2 CP -> `cnsts.cp_bonus_2` (card flip / unlock worker); 5 and 8 CP -> pick
  one of the two bonus tiles in `cp_bonuses_5` / `cp_bonuses_8` or 5 money (`offer_cp_bonus_choice` 4503,
  `claim_bonus_tile` 5575); 10 CP (first player only) -> `final_scoring_discard_triggered = true` and
  `start_final_scoring_discard` (4586): everyone discards a final scoring card. Who can take bonus tiles: any player,
  each tile once (taken tiles are removed from the pool by `take_bonus_tile` 5555).

---

## 9. Association board

- Tasks (`cnsts.association_tasks` 1269): 2 = take 2 reputation, 3 = partner zoo, 4 = university, 5 = conservation
  project. Extra tasks for MW cards (`cnsts.association_extra_tasks` 1276), extra worker (`association_extra_worker`).
- Worker cost per task: own workers already there + 1, max 2 per player per task (`task_worker_cost` 8952). Workers are
  per player; there is no shared occupancy rule (`workers_standing_on_task` 8944 is only for physical placement).
- Action: `start_association_action` (9748) builds `association_actions[color]` and queues task claims
  (`association_task_claims` 9671); `take_association_task` (9797) -> `commit_association_task` (9765, deploys
  workers) -> `get_partner_zoo` (6846) / `get_university` (6951) / `start_project_support`.
- Partner zoos: available = tile on the board zone (or in bag when "from supply"); capacity 2, or 4 when association
  upgraded (`partner_zoo_capacity` 6804); `take_partner_zoo` (6865) appends to `acquired_partner_zoos`, moves the tile
  to the player board, grants map rewards + icon.
- Universities: max 3 (`can_take_university` 6946), `take_university` (6970).
- Donations (upgraded association): `donation_slot` (10019) = first donation zone without a cube (2,5,5,7,7,10,10, then
  12 overflow); `donation_cost` (10028); `donate` (10059) checks money, places a player cube, +1 CP.
- Refill: `refill_association_board` (4330) - only at breaks (12245) and at setup. A zoo/university tile is replaced
  from its bag only if its zone is empty and not every player already owns that kind (`every_player_owns` 4304).

---

## 10. Breaks

- Break track (multi-player only): `break_init_val` 9/12/15, `break_current_val`; `break_x(raw, player)` (4364) moves
  the token and gives the triggering player 1 X-token when it reaches 0. **Returns immediately when `#players == 1`**.
  Callers: Cards action (+2, 15613), Sponsors "Break N, gain money" (14635), `jumping` (5397).
- Trigger check after each turn: `check_break_trigger` (12146): multi-player `break_current_val == 0`; solo
  `solo_break_due()` (12141).
- Steps:
  1. `break_phase_discard` (12165): hand limit 3 (+1 with `hand_size_plus_1`, +2 with the hand-size university);
     overflow players choose via `create_card_selection_panel`.
  2. `break_phase_card_tokens` (12213): remove multiplier/venom/constriction tokens from action cards.
  3. `break_phase_association` (12244): `refill_association_board`, all workers return (`send_worker_home` 12236).
  4. `break_phase_display` (12257): discard display slots 1 and 2 (respecting marks), `refill_display`.
  5. `break_phase_income` (12285) -> `start_income_phase` (12313): players in order starting with `current_player`;
     each `start_player_income` (12361) takes checkpoint `"income"` and renders `render_income_table` (12480) with
     `player.income` items + "collect" (appeal income from the counter); `advance_income_phase` refills the display
     between players.
  6. `finish_break_trigger` (12289): solo -> `reset_solo_turn_track`; else reset break token; game-end check
     (`any_player_at_game_end_score` 12864, multi-player only) with `last_round_owed`; then
     `run_break_resume` -> `BREAK_RESUMES.after_turn` (12120).

---

## 11. Official solo mode ("solo challenge")

Activated purely by `#players == 1` (one seated human at setup). Constants `cnsts.solo` (2192): board GUID "0f91b5",
7 cubes, `final_cubes = 2`, `pass_score = 100`, difficulties Easy/Medium/Hard = 20/10/0 starting appeal.

What it changes, with every code site:

| Site | Effect |
|---|---|
| 2780, 3818-3823, 3881-3883 | `interactive_effects` forced off; rewards remapped by `effective_reward` (6019) via `cnsts.non_interactive_rewards` (2785): pilfering->sprint, hypnosis->determination, venom->inventive, constriction->clever 1. |
| 4008-4010 | Final scoring cards 009 and 017 removed (because interactive effects disabled). |
| 4152-4163 | No break track value (`break_init_val` stays nil). |
| 4242-4245 | `setup_solo_challenge` instead of the normal start; no starting appeal by turn order. |
| 4257-4302 | Solo board placement, 7 turn cubes, difficulty panel. |
| 4365 | `break_x` is a no-op. |
| 7427-7470 | MW draft: solo picks 2 of 3 directly. |
| 12137-12150 | `solo_turn_track_active`, `solo_break_due`, break when all cubes have advanced. |
| 12290-12291 | After a break: `reset_solo_turn_track` (12901) retires the first cube onto the next free donation spot (`solo_donation_position` 12913, raising donation cost) and moves the rest back. |
| 12865 | `any_player_at_game_end_score` returns false (no score-based end in solo). |
| 12874-12883 | Score-based end skipped; `advance_solo_turn_cube` (12890) each turn; returns "game_end" when all remaining cubes are advanced and only `final_cubes` (2) remain -> `start_final_scoring` directly (no break). |
| 13040-13054 | Result text: pass if score >= 100. |

Timeline: rounds of 7, 6, 5, 4, 3 turns each followed by a break, then a final round of 2 turns and immediate final
scoring: 27 turns, 5 breaks.

For ARNO (human + bot), the code paths that must be disabled or bypassed if the human stays the only `players` entry:
`setup_solo_challenge`/`show_solo_difficulty_panel` (4242-4245, 4257-4302), `solo_turn_track_active` usage in
`finish_player_turn` (12881) and `check_break_trigger` (12148-12149), `reset_solo_turn_track` in
`finish_break_trigger` (12290-12291), `break_x`'s solo early return (4365) and the nil `break_init_val` (4152-4163),
`any_player_at_game_end_score` (12865) / the `#players > 1` guard at 12875, `solo_result_text`/`announce_winner`
(13040-13054). Whether to keep `interactive_effects` off and cards 009/017 removed depends on ARNO rules.

Design fork (both possible, not a recommendation):

- **Bot as a second `players` entry (Yellow)**: `#players == 2` makes the normal 2-player rules apply automatically
  (neutral cubes 4134-4138 and 4146-4150, break track 9, score-based end, `game_winners`). But the bot then needs a seat at setup
  (else its components are destroyed, 4043-4082), a `steam_name`, a map tile (`setup_player_maps` 17951 requires
  one per player), a hand for `Player[color].getHandObjects`, and it would get its own panels, income table, break
  discard prompt, setup discard, draft, final scoring discard; interactive targets (`leader_candidates` 8616,
  `constriction` 7295, `pilfering` 8732) would include it.
- **Bot outside `players`**: the solo code remains active and must be patched; every function iterating `players`
  (income, break discard, final scoring, `every_player_owns`, `game_winners`, `apply_hooks`, `leader_candidates`)
  ignores the bot, so the bot's effects on shared components (display, association tiles, projects, break) must be
  applied through the shared-state primitives listed in section 14.

---

## 12. Game end and final scoring

- Multi-player trigger: in `finish_player_turn` (12872) when the active player's score >= 100, or after a break
  (`finish_break_trigger` 12297). `trigger_game_end(previous_player(player))` (12857) sets `game_end_triggered`,
  `final_turn_player`. `BREAK_RESUMES.after_turn` (12120) calls `start_final_scoring` after the final turn player
  (unless `last_round_owed`).
- Solo trigger: `advance_solo_turn_cube` -> "game_end" (12881-12883).
- `start_final_scoring` (12954): if nobody reached 10 CP, every player first discards one final scoring card (12962-12982).
  Then `score_all_players` (12986): `score_final_scoring_cards` (13172, rules `cnsts.final_scoring_cards` 2217,
  `final_score_award` 13195 capped 0-4 CP), `score_played_sponsors` (13104), `score_deferred_sponsor_keys` (13087).
  Points are applied with `apply_cp` / `apply_appeal` (`award_final_score` 13181), so they flow into `score_counter`.
- `announce_winner` (13051): `game_winners` (13000) highest score, tie-break by number of supported projects
  (`projects_supported` 6007); winner panel; `stop_rewind_checkpoints` (3206).

---

## 13. Rewind and reload

The mod builds its own checkpoint layer on top of TTS rewind. It relies on two functions that are **called but not
defined anywhere in the script**: `storeRewindState(callback, true)` (3139, 3181, 3199) and `allowRewindStore()`
(3212). They must be host-provided by TTS (manifest says v14.2.2); their exact semantics are not verifiable from the
source. From usage, `storeRewindState` stores a rewind point now (calling `onSave` to get script state) and the
callback reports success; `allowRewindStore` appears to hand rewind storage back to the engine's default.

**onSave** (3104):
- Before `game_started`: returns `""`.
- If `checkpoint_open` (only true between `take_checkpoint` and its store callback): returns
  `JSON.encode(checkpoint_state())`.
- Otherwise: returns the marker string `"in-turn:<rewind_junk_depth>"` (`cnsts.rewind_junk_prefix` 2824).
  Consequence: **any automatic rewind point, and any manual File > Save made mid-game, carries only the marker**
  unless it happens to coincide with a checkpoint.

**Checkpoints** - `take_checkpoint(entry, player)` (3127) at exactly three places:
- `"turn"` in `start_player_turn` (8368),
- `"income"` in `start_player_income` (12362),
- `"end_turn"` in `end_player_turn` when end-of-turn prompts are pending (12541).
It sets `checkpoint_resume = {entry, color}`, opens the checkpoint, calls `storeRewindState`. Afterwards:
- a "spacer" store (`store_rewind_spacer` 3178, depth 1) on the next player interaction (`note_player_interaction`
  3150, called by every wrapped `on_*` handler, 18045-18058) or after 8 s (`arm_rewind_spacer_timer` 3163), so the
  checkpoint sits one rewind press back;
- a heartbeat store every 50 s (`arm_rewind_heartbeat` 3188, `rewind_heartbeat_store` 3196) incrementing the depth.

**script_state contents** (`checkpoint_state` 3216): all `cnsts.saved_globals`; `current_player` and
`final_turn_player` as colors; `income_phase_order` as colors; deck/discard/placeholder/rep bonus objects as GUIDs;
`display_cards`, `display_marks`, `cp_bonuses_5/8` as slot lists; per player (`checkpoint_player_state` 3325) all
`saved_player_field_names()` plus `x_tokens` and `building_tiles` as GUIDs, `project_cubes` slots, and the board
fields. **Not included**: counter values (they live on the counter objects, persisted by their own `onSave`, 2944),
hand contents, object positions (TTS object state), any transient action/UI state (`claims` is reset to `{}`,
3503-3505).

**onLoad** (2976) via `classify_saved_data` (3425):
- `"fresh"` (empty / not a started game): `start_fresh_table`.
- `"junk"` (marker, or state without a valid `checkpoint_resume`): `game_started = true`, `show_unresumable_panels`
  (3791) telling players how many more rewind presses reach a checkpoint. **The game cannot continue from that point.**
- `"state"`: `resolve_scene_objects`, wait until counters are ready (`checkpoint_objects_ready` 3457), then
  `restore_checkpoint` (3467), `restore_scene_after_load` (3634: object flags, display row positions, track tokens
  re-placed from counter values, board tiles, action card faces and seats), `arm_rewind_spacer_timer`, and
  `resume_checkpoint` (3780), which re-enters `start_player_turn` / `start_player_income` / `end_player_turn` via
  `CHECKPOINT_RESUMES` (3774). `restoring_checkpoint = true` makes the re-entered `take_checkpoint` skip once
  (3130-3133).

**In-flight coroutines/timers**: a rewind or load reloads the Global script, so all `Wait.*` timers, pending
`Wait.condition` callbacks and in-memory transient state are gone. The design copes by only resuming from the three
entry points. `reset_rewind_after_load` (3015) clears the checkpoint flags. Anything an external module schedules with
`Wait` will likewise be lost on rewind; it must re-derive its state in `onLoad`.

**Implications for an external module**: (1) its state must be added to `checkpoint_state` / `restore_checkpoint`
(e.g. via `cnsts.saved_globals`, or extra fields) or it will silently revert/vanish on rewind; (2) a normal TTS save
of a game in progress is resumable only if it was a checkpoint save, so "save game and reload later" is effectively
not supported by this mod **(inferred from code; verify in game)**; (3) bot turns should probably start with their
own `take_checkpoint`-style entry and a matching `CHECKPOINT_RESUMES` handler, otherwise rewinding into a bot turn
yields "unresumable".

---

## 14. Legality checks

(a) **Check functions** - all are used to decide which buttons/offers the UI shows:

- Action rows: `action_row_available` (8567), strength >= 1 (`action_performable` 8553).
- Animals: `is_animal_playable` (10494) = money vs `animal_play_cost` (10263), enclosure fit (`animal_fits_enclosure`
  10338, `valid_animal_enclosures` 10286, `flock_available` 10346), conditions (`animal_conditions_unmet` 10427,
  `conditions_unmet` 10396, `player_condition_supply` 10354), WAZA blocks.
- Sponsors: `sponsor_unplayable_reason` (14277), `sponsor_card_blocked_reason` (14074), `playable_sponsor_candidates`
  (14292); marketing `marketing_unplayable_reason` (14104).
- Build: `Board:canPlace` (395) + `placement_meets_requirements` (17251) + cost vs money (17498-17501); invalid physical
  placement just disables the Confirm button (`show_building_placement_panel` 17093).
- Association: `association_task_open` (9596), `task_performable` (9554), `can_take_partner_zoo` (6841),
  `can_take_university` (6946), `can_support_conservation_project` (9541), `supportable_project_slots` (9112),
  `donate` money check (10061).
- Tracks: caps only - appeal 0..max zone (4446), CP 0..max zone (4531), rep max 9 or 15 depending on Cards upgrade
  (`max_reputation` 5486), X-tokens max 5 (4703), workers max 4 (7004).

(b) **Unchecked mutators** - they assume the check already happened:
`update_money` (4604, can go negative), `update_appeal`/`apply_appeal`, `update_cp`/`apply_cp`, `update_rep`,
`update_x_token`, `apply_reward_string`, `take_partner_zoo` (6865), `take_university` (6970), `unlock_worker` (7003,
only checks the cap), `add_project_to_row` (8970), `seat_project_cube` (9226), `take_cube` (6644), `take_player_cube`
(6650), `break_x` (4364), `move_break_token` (4360), `refill_display` (12047), `refill_association_board` (4330),
direct writes to `display_cards[i]`, `base_projects[i][2][slot]`.

So an external agent calling (b) bypasses (a); the rules are enforced only by what the UI offers. Nothing would block a
bot from taking a conservation project slot (place a tagged cube and write `entry[2][slot] = cube_guid`), taking a
partner zoo/university tile off the board (move or destroy it; `refill_association_board` only refills empty zones at
breaks, and `available_partner_zoos` reads physical zone contents), advancing the break token
(`break_current_val` + `move_break_token`, but note `break_x` is a no-op in solo), or removing a display card without
paying (`display_cards[slot] = nil`, move/destroy the card, `refill_display(cb)`). However, the `take_*` functions are
written for a `players` entry (they need `player.player_board`, `player.map_key`, counters) and queue claims for that
player, so they are not reusable as-is for a bot that is not in `players`.

Manual/admin adjustment: none. No chat commands, hotkeys, context menu items or scripting buttons (no `onChat`,
`addHotkey`, `addContextMenuItem`, `onScriptingButtonDown`). Counters are zero-size label buttons with
`click_function = "null_func"` (70-84) - not clickable. Track tokens, decks, display cards, cubes, partner zoo /
university tiles, workers, X-tokens and action cards are made non-interactable or locked (`restored_object_flags`
2910; setup code). Hand cards remain movable by players; the only recovery path the mod offers is TTS rewind (e.g. the
"nowhere to build" dead end tells players to rewind, 15878-15884).

---

## 15. Extension points

**Scope first.** All `function name()` definitions and the state globals (`players`, `current_player`,
`display_cards`, `base_projects`, `added_projects`, `break_current_val`, `zones`, `bags`, the per-color `*_actions`
tables, ...) are true globals, reachable from another object's script via `Global.call` / `Global.getVar` /
`Global.setVar` / `Global.getTable`. But these are **file-scope `local`s**, reachable only by code placed inside
`Global.lua`: `HexBoard` (102), `cnsts` (1213; so `cnsts.saved_globals`, `cnsts.map_data`, `cnsts.solo` ...),
`EFFECT_ATTRIBUTES`/`MAP_ATTRIBUTES`/`SAVED_PLAYER_FIELDS` (3245-3247), `CHECKPOINT_RESUMES` (3423, assigned 3774),
`LIVE_PAYOUT`, `LIVE_PAYOUT_NAMES`, `SETTLED_AT_CLAIM`, `VARIABLE_ICON_COUNT` (5702-5766), `SHARED_MAP_KEYS` (6569),
`DRAFT_*` (7417-7420), `SELECTION_BAIL_LABEL` (8045), `BREAK_RESUMES` (12120), `FINAL_SCORE_TESTS` and the other score
tables (12950-12952), `DONATION_AREAS` (13353), `BUILD_OPTIONS`/`UNIQUE_BUILDS` (15703-15718). In particular
`resumable_state` (3443) treats a checkpoint whose `entry` is not a key of `CHECKPOINT_RESUMES` as junk, so a bot-turn
checkpoint needs an in-file `CHECKPOINT_RESUMES` entry; otherwise every rewind into a bot turn is "unresumable".

Minimal places to hook (globals can be wrapped with `local orig = f; f = function(...) ... end` from code that runs
after their definition; for `on_*` handlers note that the interaction wrapper at 18045-18058 only wraps functions that
exist when that loop runs, so handlers added later must call `note_player_interaction()` themselves):

- Start of a turn: `start_player_turn` (8365) - natural place to run a bot turn instead of showing the action panel
  when `player` (or `next_player`) is the bot.
- End of a turn: `finish_player_turn` (12872) (before refill/break), or `BREAK_RESUMES.after_turn` (12120) (after break
  handling, before the next player's turn). `BREAK_RESUMES` is a `local` table, so it can only be modified from code
  in the same file (after line 12118).
- Break: `check_break_trigger` (12146) for triggering, `break_phase_display` (12257) / `break_phase_income` (12285) /
  `finish_break_trigger` (12289) for steps; `start_income_phase` (12313) for adding a bot's income step.
- Game end: `trigger_game_end` (12857), `start_final_scoring` (12954), `score_all_players` (12986), `game_winners`
  (13000), `announce_winner` (13051).
- Save/load: `cnsts.saved_globals` (2827, file-local via `cnsts`; in-file only) lists the globals persisted in checkpoints - adding a bot state global name
  there makes it round-trip; `CHECKPOINT_RESUMES` (file-local, 3423/3774; in-file only) for a bot-turn
  resume entry; `onLoad` (2976) and `onSave` (3104).
- UI: any extra panel must go through `set_active_panel(key, xml)` (7923); a direct `UI.setXml` would be overwritten by
  the next `render_active_panels`.
- Shared-state primitives for bot moves: `display_cards` + `refill_display`, `base_projects`/`added_projects` +
  tagged cubes, association board zones (`zones`, `board_tile_zone` 4326) and bags, `donation_slot` (10019),
  `break_current_val` + `move_break_token`.

Hard assumptions that every participant is a human with a seat, hand and panels:

- Setup derives players from seated humans (4036) and destroys unseated colors' components (4043-4082).
- `steam_name` used in all log lines.
- Hand zone reads `Player[color].getHandObjects` (list in section 3), dealing with `card.deal(1, color, idx)`.
- Simultaneous prompts wait for every entry in `players`: setup discard (8252-8324), MW draft (7422), break discard
  (12165), final scoring discard (4586, 12962), map ready (17980).
- Income phase iterates all players with a UI (12313-12361).
- `apply_hooks` (6230) pays "any zoo" hooks only to the owner in `players`, and only when the hooks are applied via
  `add_remove_icons` for a player in `players` - a bot playing animals outside the system would not trigger the human's
  "whenever any player..." sponsor hooks unless the integration calls them.
- Interactive targeting (`leader_candidates` 8616, `constriction` 7295, `pilfering` 8732) iterates `players`.
- `game_winners` / `announce_winner` iterate `players`.

---

## 16. Existing AI/bot/automa or ARNO support

None. Case-insensitive searches for `arno`, `automa`, `bot`, `robot`, `npc`, `dummy`, `virtual player`, `opponent`
find nothing relevant in Global.lua. Every occurrence of "AI" / "artificial intelligence" refers to the Marine Worlds
"Artificial Intelligence" map (map_12, `cnsts.map_keys` 1587), its cube track (`add_ai_cube` 6677,
`artificial_intelligence` 6689, `cnsts.ai_cube_steps` 2249) which raises action strengths (`action_strength` 8540-8543).
The only single-player support is the official solo challenge in section 11.

For reference, `mods/original/2960339961.json` ("Ark Nova - ARNO 2.0 Solo Setup") is an unscripted table (one
"Flex Table Control" object script); its top-level objects carry no ARNO-specific nicknames, so its components were not
mapped here.
