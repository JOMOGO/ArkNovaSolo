# Mod primitives for the ARNO adapter

Reference for `arno/adapter/*`: which functions of "Ark Nova - Complete Scripted" to call for each
ARNO step, what they really do, and what goes wrong when the target is a bot `players` entry.
All references are `src/Global.lua:<line>` (read-only extract). Companion to `MOD_ARCHITECTURE.md`
(overview) and `DESIGN.md` (§4 hooks H1-H19, §5 turn flow, §7 adapter, §11 rulings R1-R21).

Assumptions (from DESIGN): the bot is a normal entry of `players` with all counters, tokens, player
board, 5 action cards, `map_key = "map_A"` (so `player.map_A = true`, `SHARED_MAP_KEYS` 6569), 7 map
project cubes and 4 workers spawned by `apply_map_choice` (6603), `claims = {}` etc. from
`setup_game` 4084-4117, plus `is_arno = true`. No hand, no panels, no money spending, no X-tokens.

Legend: **quiet** = changes state, never touches `player.claims` and never calls
`render_claims_table`. **renders** = ends by calling `render_claims_table(player)` (directly or via
`create_claims_*`). "Unverified" = depends on TTS engine behaviour that the source cannot prove.

---

## 0. The ten things that will bite

1. **Every claim-producing call can end ARNO's turn.** `render_claims_table(bot)` with an empty
   queue and no `on_claims_empty` calls `end_player_turn(bot)` (13579-13596). `create_claims_*`
   *always* push a sub-table and render, even for an empty reward list (6332-6346). So a bare
   `update_cp(bot, 1)` ends the turn (4523 → 4549 → 4584 → 13595).
2. **That premature end crashes** unless `bot.current_action` is set: `end_player_turn` →
   `resume_end_player_turn` → `move_action_card_to_front` → `remove_action_card_token(player, nil, …)`
   → `action_card_tokens` indexes `player.action_cards[nil]` (12559, 13742-13744, 7173-7175,
   7085-7087) → Lua error. If it does not crash, the next player's turn starts while ARNO's plan is
   still running.
3. **Any panel for the bot is an invisible, silent hang.** Panels carry `visibility="<Color>"`
   (e.g. 13566, 14740); nobody sits in the bot colour. Sources: a sub-table with ≥ 2 claims, a
   grouped choice, an optional claim (13622-13638); `card_flip` (14748); `get_partner_zoo` /
   `get_university` pickers (6846, 6951); `offer_cp_bonus_choice` (4503); `offer_rep_overflow`
   (5517); `draw`/`snap`/`search` rewards; income table (12480); selection panels (8073).
4. **Rewards are absorbed before H11 can see them.** `append_reward_claims` (6290) diverts
   `clever N`, `action X`, `boost X`, `determination`, `mark`, `camouflage`, `artificial
   intelligence` and fractional rewards via `absorb_reward` (6107) into `post_action_rewards` /
   `partial_rewards` / flags *without* calling `apply_reward_string`. A management project's
   `"clever 1"` (first_award) would land in `bot.post_action_rewards`. Filter reward lists
   **before** they reach `create_claims_*`.
5. **`update_rep` is wrong for ARNO** (cap 9 unless `cards_flipped`, 5486-5492; overflow only
   with `cards_flipped`, 5503-5508; may render twice). Use a bot rep routine (§3 step 2).
6. **`break_x(n, bot)` gives ARNO an X-token** at 0 (4371-4372). Call `break_x(n, nil)`.
7. **Hand-based waits deadlock** with an empty bot hand: `prompt_final_scoring_discard` (15597),
   `start_final_scoring_discard` (4586), `start_final_scoring` + `wait_for_all_hand_counts`
   (12962-12981, 10552: wants `held - 1 = -1`), `break_phase_discard` reads the bot hand (12176).
8. **The income slot opens a panel** (`start_player_income` 12361 → `render_income_table`
   12480). Wrap `start_player_income` for bots, run the break draw there, call
   `advance_income_phase()` (12328).
9. **Tie-break and Franchise Business count ARNO wrongly:** `game_winners` (13000) breaks ties on
   `projects_supported` = holes in `player.project_cubes` (6007) → always 0 for ARNO; map A's
   start tile is a kiosk (1998), so `map_income` (17430-17435) credits a human with Franchise
   Business +1 for ARNO.
10. **Physical-zone queries lag behind smooth moves**: `available_partner_zoos` (6822),
    `available_universities` (6920), `species_universities_remaining` (6900), `donation_slot`
    (10019), `refill_association_board` (4330) read zone contents. A tile/cube moved this frame is
    still (or not yet) in its zone. One ARNO step per frame is fine; two dependent queries in the
    same frame are not.

---

## 1. Claims engine and turn end (the spine)

### 1.1 Data structures
- `player.claims`: stack of sub-tables; the **last** one is shown (13599). A sub-table is an array
  of claims `{button_text, function_call, async, optional, valid, source, color}` plus fields
  `grouped` (choose exactly one; 6343, 13469-13477), `refresh`, `note`, `cancel`, `from_persistent`.
- Not persisted: reset to `{}` on restore (MOD_ARCHITECTURE §13). `on_claims_empty` is not
  persisted either.

### 1.2 `create_claims_from_rewards(player, rewards, source, grouped)` — 6348
`create_claims_from_reward_groups(player, {{rewards, source}}, grouped)` (6332): builds one
sub-table with `append_reward_claims` (6290), appends `extra_claims`, sets `grouped`,
`from_persistent`, **always** `table.insert(player.claims, sub_table)` and **always**
`render_claims_table(player)` (6345-6346).

`append_reward_claims(sub_table, player, rewards, source, grouped, show_source)` (6290):
- skips `""` entries (6292), resolves keyed rewards (`reward_string_from_key` 6032: numeric key →
  the string; icon key → indexed by icon count), settles `SETTLED_AT_CLAIM` (5726),
- if not grouped: `absorb_reward` (6107) may divert the reward (pitfall 4),
- else inserts a claim whose `function_call` is the closure
  `apply_reward_string(player, reward, source)` (6321-6324), `async = not is_reward_sync(reward)`
  (6315), `optional = is_reward_optional(reward)` (6314, list at 5918: digging, glide, pouch,
  sunbathing, posturing, free X, peacocking, marketing, play person sponsor, trade, cut down,
  reconstruction, expand enclosure, donate, extra shift).
- `is_reward_sync` (5940): only `N appeal`, `N money`, `N x_token`, inventive/multiplier/jumping/
  venom/constriction/pack/iconic and absorbed rewards are sync. **`N cp`, `N rep`, `card flip`,
  `unlock worker`, `get partner zoo`, `get university`, `BONUS: …`, `TOKEN: …` are async**: the
  engine expects the callee to call `render_claims_table` itself when done.

### 1.3 `render_claims_table(player)` — 13574
1. `claims_players[color] = nil`, `clear_player_panel(color)` (13576-13577; for the bot this sets
   a status panel for the bot colour, or clears it while ARNO is `current_player` — harmless).
2. **Empty queue** (13579): if `player.on_claims_empty` → call it and return (it does **not** clear
   the field; the mod's resumes nil it themselves, 8403-8406, 12510-12513). Else
   `offer_waza_small_animal_program` (10862; only if `waza_small_run`, never for ARNO), the four
   `clear_*_action_state` (9886, 10857, 13913, 15984; nil-safe) and **`end_player_turn(player)`**
   (13595). This is the *only* way a human turn ends.
3. Non-empty: `refresh` hook (13601-13610), drop invalid claims (13612), persistent buttons
   (`handle_persistent_rewards` 8420; returns 0 when `income_pending ~= nil`), empty sub-table →
   pop and recurse (13616-13620).
4. **Auto-fire** (13622-13631): exactly 1 claim, not optional, not grouped, no persistent buttons
   → `function_call` runs immediately; if sync → re-render, if async → return (callee re-renders).
5. Otherwise a panel (13634-13638) → for a bot: hang.

`on_claim_button_clicked` (13661) / `on_claim_pass_clicked` (13689) are the human paths; the pass
drops the whole top sub-table plus emptied ones below it.

### 1.4 What happens when the active player is ARNO and claims are queued
- The mod has no notion of "whose turn" inside the claims engine: `render_claims_table` does not
  compare against `current_player`. Whatever entry you pass is processed.
- Queue empty → `end_player_turn(bot)` (pitfall 1/2). Exact chain:
  13595 `end_player_turn` (12539: `end_turn_prompts_player` 12532 → `take_checkpoint("end_turn")`
  only if `offer_multiplier`/`post_action_rewards`/`venom_unpaid`; `offer_multiplier_action` if
  armed) → 12551 `resume_end_player_turn` (hypnosis branch, then `move_action_card_to_front`) →
  12563 `finish_end_player_turn` (`current_action = nil`; `offer_post_action_rewards` 12576 →
  panel if any; `check_venom_fee` 12919 → panel if `venom_unpaid`) → 12872 `finish_player_turn`
  (camouflage reset; score ≥ 100 → `trigger_game_end(previous_player)`; `refill_display(cb)`;
  cb → `check_break_trigger({handler="after_turn", color})` 12146) → break or
  `BREAK_RESUMES.after_turn` (12120) → `start_player_turn(next_player(player))`.
- Queue with 1 non-optional, non-grouped claim → it auto-fires (fine).
- Queue with a grouped / optional / multi-claim sub-table → invisible panel, game stalls with
  no error. Multi-claim examples that ARNO can hit: `take_university` at index 3 with
  `double_rep` (map A `{"2 cp"}` + uni `{"2 rep"}` in one non-grouped sub-table, 6994-7000);
  `update_rep` crossing 5 and 8 (`{"card flip","unlock worker"}`, 5510-5513);
  `offer_cp_checkpoints` crossing two checkpoints (4549-4583).

### 1.5 Quiet vs rendering primitives

| Quiet (safe to call any time for the bot) | Renders (needs the H10 net / a continuation) |
|---|---|
| `update_appeal` 4440 / `apply_appeal` 4444 | `update_cp` 4523 (via `offer_cp_checkpoints` 4584, always) |
| `apply_cp` 4529 | `update_rep` 5490 (once or twice) |
| `update_money` 4604, `update_x_token` 4687 | `create_claims_from_rewards` 6348 / `_groups` 6332 |
| `break_x` 4364, `move_break_token` 4360 | `take_partner_zoo` 6865, `take_university` 6970 |
| `add_remove_icons` 6251 / `apply_hooks` 6230 (returns the bot's own hook rewards, ignore them) | `unlock_worker` 7003 (also on the cap path, 7004-7008) |
| `take_cube` 6644, `take_player_cube` 6650 | `get_partner_zoo` 6846, `get_university` 6951 (+ picker) |
| `add_project_to_row` 8970, `seat_project_cube` 9226 | `donate` 10059 (also on the money-fail path) |
| `deploy_workers_to_task` 9643, `send_worker_to_task` 9663 | `take_bonus_token` 5592, `apply_reward_string` (async rewards) |
| `refill_display` 12047, `resolve_display_mark` 14797 | `start_final_scoring_discard` 4586 (when all have discarded) |
| `set_tile_face` 17134, `move_action_card` 13711, `seat_action_card` 13726 | `card_flip` 14748 (panel; re-renders on click) |
| `take_bonus_tile` 5555, `claim_bonus_tile` 5575 | `offer_cp_bonus_choice` 4503, `offer_rep_overflow` 5517 |
| `set_counter` 86, `move_when_settled` 7114, `print_track_change` 4435 | |

### 1.6 Recommended mechanism (H10 + H11 + step runner)

**H10 – bot branch of `render_claims_table` (safety net, never ends the turn, never shows UI):**

```lua
local mod_render_claims_table = render_claims_table
render_claims_table = function(player)
  if not (player and player.is_arno) then return mod_render_claims_table(player) end
  claims_players[player.color] = nil
  while #player.claims > 0 do
    local sub = player.claims[#player.claims]
    if sub.refresh then local r = sub.refresh; sub.refresh = nil; r(sub) end
    while pop_first_invalid_claim(sub) do end            -- 13479
    if #sub == 0 then
      table.remove(player.claims)
    elseif sub.grouped then                               -- a picker: adapter bug, see §2
      ARNO.log("ARNO passes a choice: " .. tostring(resolve_claim_text(sub[1])))
      table.remove(player.claims)
    else                                                  -- claim everything, in order
      local claim = sub[1]
      pop_claim(sub, 1)                                   -- 13469
      persistent_origin = sub.from_persistent or false
      claim.function_call(resolve_claim_text(claim))      -- reward claims → apply_reward_string → H11
      if claim.async then return end                      -- callee renders again when done
    end
  end
  persistent_origin = false
  ARNO.turn.claims_empty(player)                          -- see below; NEVER end_player_turn
end
```

`ARNO.turn.claims_empty(bot)`: if `bot.on_claims_empty` is set, nil it and schedule it with
`Wait.frames(fn, 1)`; when it fires, re-check `#bot.claims == 0 and not ARNO.waiting_for_humans`
(re-arm otherwise). Deferral is needed because several mod functions render and then keep
mutating (`update_rep` 5506 then 5514; `apply_reward_string` combined rewards 5646-5656;
`take_bonus_token` 5592). With no continuation set: log "unexpected empty claims" and do nothing.

**H11 – bot branch of `apply_reward_string` (the reward dispatcher).** Every reward closure and
every map/track reward lands here. Contract: if the reward string is async (`is_reward_sync`
false), the dispatcher must call `render_claims_table(bot)` **exactly once** when it is done
(directly, or by delegating to a mod function that renders, never both).

```lua
local mod_apply_reward_string = apply_reward_string
apply_reward_string = function(player, reward, source)
  if not (player and player.is_arno) then return mod_apply_reward_string(player, reward, source) end
  reward = effective_reward(reward)                       -- 6019
  local a, b = split_combined_reward(reward)              -- 5551 ("X + Y")
  if a then
    local r = apply_reward_string(player, a, source)      -- mirror the mod (5646-5656): first half, then the sync second half
    ARNO.reward.apply_sync(player, b, source); return r
  end
  local done = ARNO.reward.apply(player, reward, source)  -- returns true if it already rendered
  if not done and not is_reward_sync(reward) then render_claims_table(player) end
end
```

`ARNO.reward.apply` (R19: appeal, CP, reputation, upgrades, workers; R17 bonus tiles):

| Reward string | ARNO action | renders? |
|---|---|---|
| `N appeal` | `update_appeal(bot, N, source)` | no (sync) |
| `N cp` | `ARNO.cp(bot, N, source)` (debt-aware, §3 step 3) | dispatcher renders after it |
| `N rep` | `ARNO.rep(bot, N, source)` (§3 step 2) | dispatcher renders after it |
| `card flip`, `card flip b` | `ARNO.upgrade(bot)` (core `decide.on_upgrade`, §3 step 12) | dispatcher renders |
| `unlock worker` | `unlock_worker(bot, source)` if `worker_count < 4` (it renders, return true); else log | — |
| `BONUS: get partner zoo` / `BONUS: get university` / `BONUS: 2 rep` | tile already taken by step 14; zoo/uni via §3 step 7/8, rep via `ARNO.rep` | per callee |
| `N money`, `N x_token`, `draw N`, `search …`, `snap N`, `free …`, `marketing`, `TOKEN: …`, `geographical …`, `management rep`, `posturing N`, `digging N`, … | **ignore + log** | dispatcher renders if async |

Also wrap `update_x_token` and `update_money` for bots as no-ops (+log) so direct callers outside
`apply_reward_string` cannot give ARNO tokens/money (e.g. `break_x` 4372, `inventive` 4726,
`pay_others_for_cp` 4796 pays *other* players including a bot — harmless but pointless).

**Step runner.** Run each plan step as:

```lua
function run_step(bot, step, next_step)
  bot.on_claims_empty = next_step          -- consumed by ARNO.turn.claims_empty (deferred)
  ARNO.steps[step.kind](bot, step)         -- must end in exactly one render_claims_table(bot),
end                                        -- or call next_step itself if it is fully quiet
```

Quiet steps (appeal, break, worker, display take, project cube placement, donation-cube,
tokens, card face) can call `next_step` directly (still via `Wait.frames(…,1)` to keep stacks
flat). Steps that use `take_partner_zoo` / `take_university` / `unlock_worker` or any async reward
go through `on_claims_empty`. Before the turn ends assert `#bot.claims == 0`.

**Rule:** never let the adapter reach a picker (`get_partner_zoo`, `get_university`,
`offer_cp_bonus_choice`, `offer_rep_overflow`, `card_flip`, `geographical_zoo_cube`). Their claims
are closures (`take_partner_zoo(...)` 6855, `take_university(...)` 6960) from which the reward
cannot be recovered; the core decides instead and the adapter calls the `take_*` directly.

---

## 2. How rewards are delivered (reference)

| Source | Function | Delivery |
|---|---|---|
| CP thresholds | `update_cp` 4523 → `apply_cp` 4529 → `offer_cp_checkpoints(player, old, new)` 4549 | One **non-grouped** sub-table of async claims "Pick 2/5/8 conservation point bonus" (each → `offer_cp_bonus_choice`) and, first player to 10 only, "Discard Final Scoring" (sets `final_scoring_discard_triggered = true` immediately, 4572-4573, → `start_final_scoring_discard(player)`). Always renders (4584). One crossing → auto-fires; two crossings → panel. |
| 2-CP bonus | `offer_cp_bonus_choice(player, 2)` 4503 | grouped `cnsts.cp_bonus_2 = {"card flip","unlock worker"}` (1419) → picker. |
| 5/8-CP bonus | `offer_cp_bonus_choice(player, 5/8)` 4511-4520 | grouped `{bonus_tile_reward(pool[1]), bonus_tile_reward(pool[2]), "5 money"}` (taken tiles are nil and skipped) → picker. `bonus_tile_reward(tile)` = `cnsts.bonus_tile_mapping[guid]` (4499, mapping 1441-1457). |
| 10 CP | `start_final_scoring_discard(player)` 4586 | every entry of `players` gets `prompt_final_scoring_discard(p, 1, nil, cb)`; when all callbacks ran → `clear_waiting_status()`, `render_claims_table(player)` (the one who reached 10). |
| Reputation track | `update_rep` 5490 | Rewards for every value passed: `cnsts.rep_rewards` (1423) indexed by new value: 5 `card flip`, 8 `unlock worker`, 10 `draw 1`, 11 `1 cp`, 12 `1 x_token`, 13 `draw 1`, 14 `1 cp`, 15 `1 x_token` (others `""`, skipped). Non-grouped, source "the reputation track". Overflow (only with `cards_flipped`): `offer_rep_overflow` → appeal directly if `rep_max_bonus == nil`, else grouped `{tile reward [+ (n-1) appeal], "n appeal"}`. |
| Map partner zoo slot *i* | `take_partner_zoo` 6882-6887 | `cnsts.map_data[map_key].partner_zoo_rewards[i]`; **map A** (1711): `{}`, `{"card flip"}`, `{"unlock worker"}`, `{"2 cp"}` + icon group, one non-grouped sub-table. |
| Map university slot *i* | `take_university` 6993-7000 | map A (1712): `{}`, `{"card flip"}`, `{"2 cp"}` + `cnsts.universities[key].rewards` (`hand_size` `{"1 rep"}`, `double_rep` `{"2 rep"}`, species `{"search <type>"}`, 1232-1252) + icon group. |
| Map worker *n* | `unlock_worker` 7003, 7020-7022 | `worker_rewards[n-1]`; map A (1713): workers 2,3 `{}`, worker 4 `{"2 cp"}`. |
| Map project bonus | `commit_project_support` 9506-9510 | `project_rewards[index]` of the uncovered map cube (map A 1710) + income for purple. **ARNO never uses this** (R11). |
| Bonus tile `BONUS: X` | `apply_reward_string` 5660-5664 | `claim_bonus_tile(reward)` (5575: `take_bonus_tile` + flip face-down **in place**) then `apply_reward_string(rest)`. |
| Bonus tile `TOKEN: X` | `take_bonus_token` 5592 | tile moved to the player board, persistent flag set, renders. |
| Icons | `append_icon_groups` 6282 → `add_remove_icons` 6251 | counters +1, `apply_hooks` pays every `all_zoo_hooks` owner **directly** (`apply_reward_string(owner, …)`, 6233-6239), the player's own `hooks` and Explorer become claims of the player. |

`all_zoo_hooks[icon] = {owner_color, reward, source}` (6219-6225; one owner per icon, last
writer wins) is set when a human plays a sponsor with `hook_all` (14550): 208 Science Library
`research = "2 money"`, 236-240 `primate/reptile/bird/predator/herbivore = "3 money"`, 251
`bear = "2 appeal"`, 266 `sea = "3 money"`, 275 `petting = "2 money"` (2309-2516). All are sync
(money/appeal) → paying a human during ARNO's turn never queues a human claim or panel.

---

## 3. The ARNO steps

For each: (a) functions, (b) behaviour, (c) bot safety, (d) recommended sequence.

### Step 1 — appeal +n
(a) `update_appeal(player, amount, source)` 4440 → `apply_appeal(player, amount)` 4444.
(b) Clamps to `0..#cnsts.appeal_zones-1` (broadcast if capped, 4449-4451), sets `appeal_counter`,
token via `move_when_settled` (7114: `Wait.frames(2)` + `Wait.condition` until not smooth-moving,
then `setPositionSmooth`), `score_counter += applied`, `income_counter += Δappeal_to_income`.
Prints "<steam_name> gains n appeal from <source>." Quiet.
(c) Safe. (The bot's income counter changes; it is never collected.)
(d) `update_appeal(bot, n, "ARNO")` → next step.

### Step 2 — reputation +n (no cap 9, max 15, overflow)
(a) `update_rep` 5490 (do **not** use), helpers `get_rep_zone_position` 5481,
`print_track_change` 4435, `rep_max_bonus` (global, MW only, 3967), `bonus_tile_reward` 4499,
`take_bonus_tile` 5555, `set_tile_face` 17134, `offer_rep_overflow` 5517 (do not use).
(b) `update_rep`: cap `max_reputation` = 15 only with `cards_flipped` else 9; overflow handling
only with `cards_flipped`; then rep-track rewards as claims (renders).
(c) Unsafe for ARNO: wrong cap, picker for the MW tile, possible double render.
(d) Bot routine (quiet except for the track rewards):

```lua
function ARNO.rep(bot, n, source)
  local old = get_counter_value(bot.rep_counter)
  local max = #cnsts.rep_zones                                  -- 15 (1421)
  local new = math.min(max, old + n)
  set_counter(bot.rep_counter, new, cnsts.counter_style.rep)
  move_when_settled(bot.reputation_token.getGUID(), get_rep_zone_position(new))
  print_track_change(bot, new - old, "reputation", source)
  local overflow = old + n - new
  if overflow > 0 then
    if marine_worlds_enabled and rep_max_bonus ~= nil then
      local reward = bonus_tile_reward(rep_max_bonus)           -- e.g. "BONUS: get university"
      claim_bonus_tile(reward)                                  -- 5575: rep_max_bonus = nil, flip in place
      ARNO.queue(bot, "bonus_tile_reward", reward)               -- only pz / uni / "2 rep" (R17); queued, because pz/uni render (keeps "one render per claim")
      if overflow > 1 then update_appeal(bot, overflow - 1, "maxing reputation") end  -- mod's 5528-5530 rule; ruling?
    else
      update_appeal(bot, overflow, "maxing reputation")
    end
  end
  for v = old + 1, new do                                       -- track rewards (ruling: which apply)
    local r = cnsts.rep_rewards[v]                              -- 1423
    if r == "card flip" then ARNO.upgrade(bot)                  -- R19 upgrades
    elseif r == "unlock worker" then ARNO.queue(bot, "unlock_worker")   -- renders; run as its own sub-step
    elseif r == "1 cp" then ARNO.cp(bot, 1, "the reputation track") end
    -- "draw 1", "1 x_token": ignore + log
  end
end
```
`ARNO.rep` itself is quiet: everything that renders (worker unlock, a partner-zoo/university tile)
is queued as a sub-step, so the H11 dispatcher's single render after it keeps the
"one render per claim" contract. `ARNO.upgrade` and `ARNO.cp` are quiet (their own follow-ups are
queued too). Whether the `+(n-1) appeal` part applies with the tile, and which track rewards ARNO collects,
are rulings (R10/R19), not mod facts. `restore_track_tokens` (3643) re-places the token from the
counter for values up to 15, so a rep > 9 without `cards_flipped` restores correctly.

### Step 3 — conservation +n (debt, checkpoints 2/5/8/10)
(a) `apply_cp(player, amount)` 4529 (quiet), `offer_cp_checkpoints` 4549 (do not use for the bot),
`start_final_scoring_discard` 4586, `prompt_final_scoring_discard` 15597.
(b) `apply_cp`: clamps to `#cnsts.cp_zones-1`, sets `cp_counter`, token via `move_when_settled`,
`score_counter += cp_to_score(new) - cp_to_score(old)` (4495: 2/CP up to 10, 3/CP above).
Returns `applied, old_cp, new_cp`.
(c) `apply_cp` safe. `update_cp` renders and would offer human pickers (pitfall 1/3).
(d)
```lua
function ARNO.cp(bot, n, source)
  local pay = math.min(n, state.cp_debt); state.cp_debt = state.cp_debt - pay
  local surplus = n - pay
  if surplus <= 0 then ARNO.log(...); return end
  local applied, old, new = apply_cp(bot, surplus)
  print_track_change(bot, applied, "conservation point", source)
  if old < 2 and new >= 2 then ARNO.queue(bot, "unlock_worker") end         -- R17: always worker
  if old < 5 and new >= 5 then ARNO.queue(bot, "bonus_tile", 5) end         -- side from decide.bonus_tile
  if old < 8 and new >= 8 then ARNO.queue(bot, "bonus_tile", 8) end
  if old < 10 and new >= 10 and not final_scoring_discard_triggered then
    final_scoring_discard_triggered = true                                  -- as 4572-4573
    ARNO.queue(bot, "humans_discard_final_scoring")                         -- see below
  end
end
```
"Queue" = sub-steps executed after the current step, in the order the mod would offer them
(2, 5, 8, 10; 4549-4580). Humans' final-scoring discard while ARNO is active:
either call `start_final_scoring_discard(bot)` with `bot.on_claims_empty = continue` and the
`prompt_final_scoring_discard` wrapper below (the final callback renders the bot → H10 → continue),
or a bot-local copy of 4586-4602 that loops only over humans and calls `continue` when all are done.
Set `ARNO.waiting_for_humans = true` during the wait. Required wrapper (H14):

```lua
local mod_prompt_fsd = prompt_final_scoring_discard
prompt_final_scoring_discard = function(player, count, pool, callback)
  if player.is_arno then if callback then callback() end; return end   -- ARNO's card is on his mat
  return mod_prompt_fsd(player, count, pool, callback)
end
```
(For a bot the callback runs synchronously inside the loop at 4591; with `remaining > 0` it only
calls `set_waiting_status(bot, …)` — harmless.)

### Step 4 — advance the break token n
(a) `break_x(raw, player)` 4364, `move_break_token(value)` 4360, `get_break_position` 4352.
(b) No-op if `#players == 1` (never with a bot). `new = max(break_current_val - raw, 0)`,
`break_token.setPositionSmooth(...)`; if `player ~= nil`: prints and, when it reaches 0 from > 0,
`update_x_token(player, 1, "triggering the break")` (4370-4373); sets `break_current_val`. Quiet.
The break itself only happens after the turn (`finish_player_turn` → `check_break_trigger`
12146: `break_current_val == 0`), matching R7.
(c) Safe with `player = nil`; with the bot it would clone an X-token onto ARNO's board.
(d) `local before = break_current_val; break_x(n, nil); printToAll(bot.steam_name .. " advances
the break token " .. (before - break_current_val) .. " spaces.")` → next step.

### Step 5 — take display card #k (no rep range, no payment)
(a) `display_cards[1..6]` (slot 1 = leftmost, `cnsts.display_locs` 1215), `display_marks`,
`resolve_display_mark(slot, to_discard)` 14797, `card_data_for(name)` 10226, `refill_display(done,
leaving)` 12047, `add_remove_icons` 6251, `apply_hooks` 6230, `played_animal_position` 11891,
`discard_pile` (global object), reference implementations `handle_snap_pickup` 14993 and
`finish_animal_play` 11902-11920.
(b)
- `resolve_display_mark(k, false)`: if a mark cube lies on slot k it is destroyed and the marking
  player gets `update_money(marker, 2, "their marked card")` (14797-14808). The mod does this
  whenever anyone takes a marked card (14998, 11911-11913, 14537). Must be called before
  `display_cards[k] = nil`, otherwise `refill_display` drops the mark from `display_marks` and
  leaves the cube on the table.
- `refill_display`: compacts remaining cards toward slot 1, draws from `zoo_deck.getObjects()`
  order (unguarded `deck_objects[drawn]`, 12063: **deck exhaustion = Lua error**), handles MW wave
  cards (washed card → discard or marker's hand), `takeObject` smooth to the slot, tags
  `zoo_card`, locks, prints. `display_cards` is updated synchronously; `done` is called
  synchronously when nothing is leaving (12038-12045), otherwise after the washed card has
  reached the discard pile (`Wait.condition`).
- Animals: `add_remove_icons(bot, card.icons or {})` increments ARNO's icon counters (16 icons,
  `set_icon_counter`), `adjust_sponsorship_income` (no-op: `bot.sponsorships` empty), and calls
  `apply_hooks(bot, icons)` → **human `all_zoo_hooks` owners are paid immediately** (sync money/
  appeal). Its return value (ARNO's own hooks / Explorer) must be discarded. This is exactly the
  call that makes a human hook fire "as if ARNO played that animal". Cross-player reference
  values that then see ARNO's icons: `inventive_bear_count` 4730, `iconic_count` 4817,
  `leader_candidates` 8616 (interactive), `mascot statue` 13447 (appeal counter).
- Sponsors: the mod triggers **nothing** when a card is discarded (`discard_cards` 6471 /
  `move_cards_to_discard` 6465 only `putObject` + print; no `onObjectEnterContainer` handler
  exists). Card 208 Science Library is `hook_all={research="2 money"}` (2309), registered at play
  (14550) and paid only through `apply_hooks` when **icons are added** (animals, sponsors,
  partner zoos, universities, buildings 17376). So R18 ("sponsors can still trigger human
  effects, e.g. 208") must be done by the adapter: `apply_hooks(bot, icons_to_fire)` **without**
  adding the icons to ARNO's counters. `icons_to_fire` = the sponsor's `icons`, or only its
  `"research"` entries if the ruling limits it to 208 (`apply_hooks` also fires 236-240/251/266/275
  for matching icons). Note: ARNO taking a research university already pays a 208 owner via
  `take_university` → `append_icon_groups` (6999).
- Projects: kept on ARNO's mat; nothing else in the mod knows about it (persist the GUID in
  `arno_state`).
(c) Safe (all quiet). No `onObjectPickUp` fires for scripted moves (7484 only handles player
pick-ups).
(d)
```lua
local obj = display_cards[k]; local name = obj.getName(); local card = card_data_for(name)
resolve_display_mark(k, false)
display_cards[k] = nil
obj.locked = false                       -- display cards are locked (12104, 14932)
if card.type == "animal" then
  table.insert(bot.played_animals, obj.getGUID())          -- persisted; relocked on restore (2910 list)
  obj.setPositionSmooth(ARNO.mat_animal_pos(bot, #bot.played_animals), false, false)  -- or played_animal_position(board_pos, i)
  obj.setRotation({0,180,0}); obj.locked = true
  add_remove_icons(bot, card.icons or {})                  -- ignore returned table
elseif card.type == "sponsor" then
  report_discard(bot, {obj}, true)                         -- print BEFORE putObject (mod order 6472-6473): the ref is merged into the deck
  discard_pile.putObject(obj)
  apply_hooks(bot, ARNO.sponsor_trigger_icons(card))       -- R18 / ruling; may be {}
  state.sponsor_discards = state.sponsor_discards + 1
else -- "project"
  obj.setPositionSmooth(ARNO.mat_project_pos(bot, i), false, false); obj.locked = true
  table.insert(state.mat_projects, obj.getGUID())
end
refill_display(function() next_step() end)
```
`played_animals` is only read for the bot's own checks (release/breeding/size counts), so adding
ARNO's animals there is harmless and gives restore-time locking. Position of ARNO's "left area"
is an adapter choice (`board_relative_world_position` 17639 with the bot's board).

### Step 6 — one association worker on task 2/3/4/5
(a) `deploy_workers_to_task(player, task, count)` 9643, `send_worker_to_task` 9663,
`task_worker_position` 9634, `available_workers` 8925, `workers_standing_on_task` 8944.
(b) Asserts `count <= worker_count - #deployed_workers` (9644-9646). Spot = workers of all players
already on the task + 1; `setPositionSmooth` to the spot, rotation, appends `{guid, task}` to
`player.deployed_workers`. Quiet. Workers return home in `break_phase_association` (12244, all
players). The mod's 2-workers-per-task cost (`task_worker_cost` 8952) is not involved.
(c) Safe. Do **not** use `commit_association_task` (9765, needs `association_actions[color]`, adds
donation/offer claims) or `take_association_task` (9797).
(d) `if available_workers(bot) >= 1 then deploy_workers_to_task(bot, task, 1) end` → next step.

### Step 7 — partner zoo <habitat> (+ map bonus)
(a) `available_partner_zoos(player, supply)` 6822, `take_partner_zoo(player, owner, supply)` 6865,
`partner_zoo_position` 6808, `partner_zoo_capacity` 6804 (2, or 4 with `association_flipped`;
only checked in `can_take_partner_zoo` 6841 / `get_partner_zoo` 6846).
(b) Appends `owner` to `acquired_partner_zoos`, index = count; moves the board tile
(`tile_in_zone(board_tile_zone(owner.."_partner"), "partner").setPositionSmooth`, 6875-6876;
**nil tile → Lua error**) or takes from the bag when `supply`; prints; one non-grouped sub-table
with map A `partner_zoo_rewards[index]` + the habitat icon (`add_remove_icons` → hooks); renders.
`partner_zoo_position` handles indexes 3 and 4 (`partner_zoo_big_step` at 3). The board refill
(`refill_association_board` 4330) only happens at breaks.
(c) Safe if called directly with an available habitat (ARNO capacity 4 is not checked here).
Renders → run through the step runner. Map A slot 2 `card flip` → H11 → `ARNO.upgrade`; slot 3
`unlock worker` → `unlock_worker` (renders, nested); slot 4 `2 cp` → `ARNO.cp`. Each sub-table
has one claim (icons add none for ARNO) → handled by H10 in order.
(d)
```lua
assert(table_contains(available_partner_zoos(bot, false), habitat))   -- reroll per R5 in the core
bot.on_claims_empty = next_step
take_partner_zoo(bot, habitat, false)
```

### Step 8 — university <key> (+ map bonus)
(a) `available_universities(player, supply)` 6920 (MW species universities only while the generic
university tile is on the board and the player has no species university, 6926-6929),
`take_university(player, name, supply)` 6970, `university_position` 6891, `can_take_university`
6946 (max 3).
(b) Appends to `acquired_universities`; moves the tile (species: the species tile from zone
`ab280b` plus the generic tile back home, 6976-6980); prints; sub-table = map A
`university_rewards[index]` + `spec.rewards` + icon group (`research`/species icons → **208 and
other `hook_all` owners are paid**); renders. Index 4+ has no map reward (nil-safe) and an
extrapolated position.
(c) Safe when called directly with an available key. Rewards through H11: `hand_size` `1 rep`,
`double_rep` `2 rep`, species `search <type>` (**ignore**: it would open a deck search),
map `card flip` / `2 cp`. **Index 3 + `double_rep` gives a 2-claim sub-table**, which the stock
renderer would show as a panel; H10 claims both in order.
(d) `bot.on_claims_empty = next_step; take_university(bot, key, false)`.

### Step 9 — support a conservation project (ARNO cube, no map cube)
(a) `base_projects` / `added_projects` (`{card_guid, {[slot] = cube_guid}}`), `add_project_to_row(obj)`
8970, `added_project_capacity` 8961 (`max(2, #players)`), `project_already_supported(player,
cubes)` 9038, `cube_owner_color` 6657, `take_player_cube(player, pos)` 6650,
`project_slot_world_position(card_obj, project, slot)` 9222, `seat_project_cube` 9226,
`project_slot_awards(player, card, slot)` 9232, reference `commit_project_support` 9470.
(b)
- `add_project_to_row`: appends `{guid, {}}`; on overflow removes the oldest entry, destroys its
  cubes (anyone's) and puts its card on the discard pile; re-lays the row (new card
  `setPosition`, i.e. instant; others smooth) and moves their cubes. Quiet.
- `take_player_cube`: `bags.cubes.takeObject` (non-smooth), non-interactable, tinted, tagged with
  the colour (the tag is how ownership is read; neutral 2-player blockers, 4134-4138, have no
  colour tag → `cube_owner_color` nil).
- `project_slot_awards`: icons `{awards[slot] .. " cp"}`; management slot 1 `{"2 cp",
  first_award}` (first_award ∈ clever 1, digging 2, hunter 0, posturing 1, reef effect,
  sunbathing 2), slot 2 `{"2 cp", "management rep"}`, slot 3 `{"2 cp", "search " .. match}`;
  breeding `{{2 cp, 2 rep},{1 cp, 2 rep},{2 cp}}`, release `{{5 cp},{4 cp},{3 cp}}` (1312-1315).
  Slot 1 = highest threshold/award (thresholds e.g. `{5,4,2}`, 2272).
- `commit_project_support` additionally: charges display money, `player.project_cubes[index] =
  nil` (uncovers the map bonus and is what `projects_supported` counts), map bonus +income,
  `commit_association_task(player, 5)`, X-token, release-animal flow, play rewards, and
  `create_claims_from_reward_groups` (absorbs `clever 1`!). **Do not call it for ARNO.**
(c) The quiet primitives are safe. Never touch `bot.project_cubes` (R11).
(d)
```lua
local entry, obj
if step.source == "mat" then
  obj = getObjectFromGUID(step.card_guid); remove_from(state.mat_projects, step.card_guid)
  obj.locked = false
  add_project_to_row(obj)                                  -- may discard the oldest added project
  entry = added_projects[#added_projects]
else
  entry = (step.row == "base" and base_projects or added_projects)[step.index]
  obj = getObjectFromGUID(entry[1])
end
local card = card_data_for(obj.getName())
assert(entry[2][s] == nil and not project_already_supported(bot, entry[2]))
local p = project_slot_world_position(obj, card.project, s)
local cube = take_player_cube(bot, { x = p.x, y = p.y + cnsts.drop_height, z = p.z })
entry[2][s] = cube.getGUID()
for _, r in ipairs(project_slot_awards(bot, card, s_reward)) do        -- s' (reward slot)
  if r:match("^%d+ cp$") or r:match("^%d+ rep$") or r:match("^%d+ appeal$") then
    ARNO.reward.apply_sync_or_queue(bot, r, "supporting " .. string.sub(obj.getName(), 7))
  else ARNO.log("ignored " .. r) end                                    -- clever/search/management rep…
end
```
Apply the filtered rewards with the bot routines directly (not via `create_claims_*`). For a card
played from the mat the "played" rewards of release/management cards (9497-9500) are card
effects → not for ARNO (R19). `take_player_cube` draws from `bags.cubes`; whether that bag is
infinite is not checked by the mod (`cnsts.expected_bag_contents` has no cube entry) —
**unverified**, the mod itself relies on it for every cube.

### Step 10 — donate (cube on next donation spot, +1 CP, no money)
(a) `donation_slot()` 10019, `donation_12_count` 10041, `donation_12_position` 10049, `zones`,
reference `donate(player, source, association)` 10059.
(b) `donation_slot`: first key of `{donation_2, 5_1, 5_2, 7_1, 7_2, 10_1, 10_2}` (1299) whose zone
holds no `cube`-tagged object → `(cost, key)`; else `(12, nil)`. 2-player games pre-fill
5_1/7_1/10_1 with neutral cubes (4146-4150). `donate` checks money (fails with
`broadcastToColor` + render), `update_money(-cost)`, places the cube, `create_claims_from_rewards
({"1 cp"})` → renders.
(c) `donate` is unsafe (money, render). The primitives are safe; the cube is dropped from
`+1` height and is counted by the zone only after it lands (pitfall 10).
(d)
```lua
local _, key = donation_slot()
if key then take_player_cube(bot, zones[key].getPosition() + Vector(0, 1, 0))
else take_player_cube(bot, donation_12_position(donation_12_count() + 1)) end
ARNO.cp(bot, 1, "the donation")
```

### Step 11 — token on final-scoring card / notepad
Pure `arno_state` bookkeeping (`tokens_scoring`, `tokens_notepad`). Optional visual: a cube via
`take_player_cube(bot, pos)` on ARNO's face-down scoring card / notepad spot; record its GUID in
`arno_state` so it can be restored/cleaned. Nothing in the mod reads it. Quiet.

### Step 12 — card upgrade (flip ARNO's action card to side II)
(a) `action_card_object(player, slot)` 7081, `action_card_slot_named(player, name)` 13733
(`name` = card name minus the trailing " n", e.g. "ANIMALS"), `action_card_upgraded(card)`
14696 (`card.is_face_down`), `set_tile_face(obj, face_down)` 17134,
`cnsts.action_flip_attributes` 2645 (`AN/BU/CA/SP/AS` → `animals_flipped` …), human path
`card_flip` 14748 → `render_card_flip_panel` 14718 → `on_card_flip_clicked` 14757.
(b) The click handler does exactly: print, `set_tile_face(card, true)` (smooth rotation, re-locks
after the move), `player[attribute] = true` (unless it is the hypnosis-borrowed attribute),
clear panel, render claims. On restore `reassert_action_card_faces` (3619) re-flips the physical
cards from the `*_flipped` flags, so the flag is the source of truth.
Side effects of the flags on mod code for the bot: `cards_flipped` → `max_reputation` 15
(irrelevant if `update_rep` is bypassed); `association_flipped` → `partner_zoo_capacity` 4
(irrelevant, not checked by `take_partner_zoo`); `*_upgraded` helpers (14700-14716) only matter
inside human actions.
(c) `card_flip` is unsafe (panel). The primitives are safe.
(d)
```lua
local slot = action_card_slot_named(bot, step.action_name)   -- "ANIMALS","BUILD","CARDS","SPONSORS","ASSOCIATION"
local card = action_card_object(bot, slot)
if not action_card_upgraded(card) then
  set_tile_face(card, true)
  bot[cnsts.action_flip_attributes[string.sub(card.getName(), 1, 2)]] = true
  printToAll(bot.steam_name .. " upgrades their " .. string.sub(card.getName(), 1, -3) .. " action card.")
end
```
Card order sync (ARNO's used card → slot 1, others shift right) uses the same mechanism as the
mod: `move_action_card(bot, slot, 1)` (13711, re-seats moved cards via `move_when_settled`) or
`bot.current_action = slot; move_action_card_to_front(bot); bot.current_action = nil` (13742; also
removes a constriction token). A full resync from core state = successive `move_action_card`.

### Step 13 — unlock worker
(a) `unlock_worker(player, source)` 7003.
(b) At 4: `broadcastToColor(..., player.color)` + render (7004-7008). Else `worker_count += 1`,
`setPosition`/`setRotation` of worker n to `worker_n_home` (instant), print, map A
`worker_rewards[n-1]` (worker 4 → `{"2 cp"}`) via `create_claims_from_rewards` → renders (always,
also with `{}`).
(c) Safe through the step runner (renders exactly once). `broadcastToColor` to an unseated colour
is presumably a no-op (**unverified**); avoid by checking `worker_count < 4` first.
(d) `if bot.worker_count < 4 then bot.on_claims_empty = next_step; unlock_worker(bot, "ARNO")
else ARNO.log(...); next_step() end`.

### Step 14 — bonus tile left/right from `cp_bonuses_5` / `cp_bonuses_8`
(a) Globals `cp_bonuses_5`, `cp_bonuses_8` (2-slot lists of objects; persisted as slot lists with
holes, 2842), `bonus_tile_reward` 4499, `take_bonus_tile(reward)` 5555, `claim_bonus_tile(reward)`
5575, `set_tile_face` 17134, `take_bonus_token` 5592 (do not use).
(b) Setup draws `[1]` at x = −30.41/−24.99 and `[2]` at x = −28.45/−23.01 (3951-3954), so index 1
is the tile with the smaller x (left from the default seat view — **visual left/right is
unverified**). `take_bonus_tile` finds the tile by its reward string in both pools and
`rep_max_bonus`, sets that slot to nil (this alone removes it from every later
`offer_cp_bonus_choice`) and returns it. `claim_bonus_tile` additionally flips it face-down in
place (the mod's "taken" look). `take_bonus_token` (for `TOKEN:` tiles) would move it onto the
player's board and set persistent flags/tokens → never for ARNO.
(c) Safe via `take_bonus_tile` / direct slot write. Tile rewards: only `BONUS: get partner zoo`,
`BONUS: get university`, `BONUS: 2 rep` are applied (R17); everything else (`10 money`, `draw 3`,
`3 x_token`, `free size_3`, `marketing`, `multiplier_token`, `posturing 3`, `adapt 3`, all
`TOKEN:`) is just removed.
(d)
```lua
local pool = (cp == 5) and cp_bonuses_5 or cp_bonuses_8
local tile = pool[side]                     -- side = 1 (left) / 2 (right) from decide.bonus_tile
if tile == nil then ARNO.log("tile already taken"); return next_step() end   -- ruling: other side?
local reward = bonus_tile_reward(tile)
pool[side] = nil
set_tile_face(tile, true)                   -- or move it beside ARNO's mat
printToAll(bot.steam_name .. " takes the " .. reward .. " bonus tile.")
if reward == "BONUS: get partner zoo" then -- core picks habitat (R5 rerolls) → step 7 sequence
elseif reward == "BONUS: get university" then -- step 8 sequence
elseif reward == "BONUS: 2 rep" then ARNO.rep(bot, 2, "a bonus tile"); next_step()
else next_step() end
```

---

## 4. Turn start and turn end

### Start
`start_player_turn(player)` 8365 (via `BREAK_RESUMES.after_turn` 12120 or
`CHECKPOINT_RESUMES.turn` 3768): `current_player = player`, `take_checkpoint("turn", player)`
(3127; opens a checkpoint, `storeRewindState` async, `checkpoint_open` true until its callback),
`turns_taken += 1`, prints, `refresh_status_panels()` (humans see "<ARNO> is playing their turn",
`status_panel_text` 7953), re-arms persistent rewards, recomputes venom, then
`create_action_selection_panel(player)` (10162). All of this is bot-safe; H9 replaces only the
last call for bots. Other callers of `create_action_selection_panel` (multiplier 10177, hypnosis,
persistent-reward resumes 8403) cannot happen for ARNO when he never gets those states.

### End — which part of the chain to call
| Function | Human-only content | For ARNO |
|---|---|---|
| `end_player_turn` 12539 | `end_turn` checkpoint if prompts pending; multiplier offer | skip |
| `resume_end_player_turn` 12551 | hypnosis; `move_action_card_to_front` (needs `current_action`) | skip (sync cards yourself, step 12) |
| `finish_end_player_turn` 12563 | `current_action = nil`; post-action reward panel; venom-fee panel | skip |
| `finish_player_turn` 12872 | — (camouflage reset, score ≥ 100 → `trigger_game_end(previous_player)`, `refill_display`, break check, next turn) | **call this** |

Recommended `ARNO.turn.finish(bot)`:
```lua
assert(#bot.claims == 0)
bot.on_claims_empty = nil
bot.post_action_rewards = {}        -- defensive: absorbed rewards (pitfall 4) would open a panel
bot.offer_multiplier = nil; bot.venom_unpaid = nil; bot.persistent_rewards.venom_fee = nil
bot.hypnotize_action = false; bot.current_action = nil
claims_players[bot.color] = nil; action_selection_state[bot.color] = nil
-- action cards already re-synced (step 12 helper)
finish_player_turn(bot)              -- refill → game-end check → check_break_trigger → next player
```
`finish_player_turn` refills the display again (idempotent if already full) and then everything
continues in mod code; the ARNO turn must not touch state after this call.

---

## 5. Break flow and ARNO's income slot

Chain: `finish_player_turn` → `refill_display(cb)` → `check_break_trigger(resume)` 12146 (multi:
`break_current_val == 0`; broadcasts "<current_player> has triggered a break!",
`break_phase_resume = resume`) → `break_phase_discard` 12165 → `break_phase_card_tokens` 12213
(removes multiplier/venom/constriction tokens from **all** action cards) →
`break_phase_association` 12244 (`refill_association_board`; every player's deployed workers
`send_worker_home` 12236, `deployed_workers = {}`) → `break_phase_display` 12257 (discard slots 1-2,
marked cards go to the marker's hand, `refill_display(break_phase_income, leaving)`) →
`break_phase_income` 12285 → `start_income_phase` 12313 → … → `finish_break_trigger` 12289 (reset
break token to `break_init_val`, score ≥ 100 → `trigger_game_end(current_player)` +
`last_round_owed`) → `run_break_resume` → `BREAK_RESUMES.after_turn`.

Bot concerns:
- `break_phase_discard` reads `Player[bot.color].getHandObjects(1)` (12176) for an unseated
  colour. Expected `{}` (no discard) but **unverified**; H12 should skip `is_arno` entries.
- Income: `start_income_phase` orders `players` starting at `current_player` (12313-12326), sets
  `income_phase_index = 0`, `advance_income_phase()`. `advance_income_phase` 12328: for index ≥ 1
  refills the display first (`refill_display(continue_income_phase)`), then
  `continue_income_phase` 12336: index+1; past the end → `clear_waiting_status()`, order = nil,
  `finish_break_trigger()`; else `rearm_effect(player, "landscape_gardener")` (17394, harmless),
  waiting text "<name> is collecting their income..." for others, `start_player_income(player)`.
- `start_player_income` 12361: `take_checkpoint("income", player)`, builds `income_pending` (+
  collect), `render_income_table` 12480 → panel for the colour → **hang for a bot**. The phase only
  advances when `render_income_table` sees an empty list (12485-12488) → `advance_income_phase()`.

Recommended H12 wrapper (the mod resumes `income` checkpoints through the global name, 3770, so
the wrapper also handles rewinds into ARNO's income slot):
```lua
local mod_start_player_income = start_player_income
start_player_income = function(player)
  if not player.is_arno then return mod_start_player_income(player) end
  take_checkpoint("income", player)                  -- keeps rewind granularity
  Wait.condition(function()
    ARNO.breaks.draw(player, function() advance_income_phase() end)
  end, function() return not checkpoint_open end)    -- DESIGN §8 ordering rule
end
```
Leave `player.income_pending` nil (it suppresses persistent buttons, 8425; nothing else needs it).

Break draw (`ARNO.breaks.draw`), all quiet:
```lua
local n = math.min(3, #zoo_deck.getObjects())       -- no reshuffle logic in the mod; never assert inside a Wait callback (it would stall the break silently): log + draw n
local cards = {}
for i = 1, n do
  local c = zoo_deck.takeObject({ position = ARNO.reveal_pos(bot, i), rotation = {0,180,0}, smooth = true })
  c.addTag("zoo_card"); cards[i] = c
end
-- classify with card_data_for(c.getName()).type; first project → mat (state.mat_projects);
-- first animal → step-5 animal branch (played_animals + add_remove_icons → human hooks);
-- rest: c.locked = false; report/log first, then discard_pile.putObject(c) (sponsors counted, R18 hook rule as step 5)
-- call done() after the discards have landed if order matters: wait_for_departures({{guid=…},…}, done) 12038
```
`zoo_deck.takeObject` removes the card from the container immediately (the mod relies on this in
`refill_display`, which is called right after by `advance_income_phase`). Human hooks fired by the
animal pay money/appeal synchronously, so no human prompt opens mid-income (the risk noted in
DESIGN §13 does not materialise with the current card set; any future async `hook_all` reward
would).

---

## 6. Game end and final scoring

- Trigger: `finish_player_turn` 12875-12877 (the active player — ARNO included — at
  `score_counter >= cnsts.game_end_score`), or `finish_break_trigger` 12297-12300
  (`any_player_at_game_end_score` 12864 counts ARNO). `trigger_game_end(last)` 12857 sets
  `game_end_triggered`, `final_turn_player`; `BREAK_RESUMES.after_turn` calls
  `start_final_scoring()` after that player's turn (R9 follows automatically).
- `start_final_scoring` 12954: if `final_scoring_discard_triggered` → `score_all_players()`.
  Else sets it, then for every player `prompt_final_scoring_discard(p, 1, nil, cb)` and, after
  all callbacks, `wait_for_all_hand_counts(2, held[c] - 1, score_all_players)` (12966-12981).
  With a bot: the prompt opens an invisible selection panel over an empty pool (hang); and even
  with the prompt wrapper, `held[bot] = 0` → wanted count −1 → the `Wait.condition` never fires.
  **Wrap `wait_for_all_hand_counts` (10552)** to skip `is_arno` players (H16), or wrap
  `start_final_scoring` for games with bots.
- `score_all_players` 12986: per player `score_final_scoring_cards` (13172; reads hand index 2 via
  `final_scoring_cards` 13163 → empty for ARNO → nothing, **unverified** for unseated colours) and
  `score_played_sponsors` (empty for ARNO); then `score_deferred_sponsor_keys`; after
  `cnsts.winner_panel_delay` → `announce_winner()` + `stop_rewind_checkpoints()`.
  Recommended: wrap `score_final_scoring_cards` so that for ARNO it awards
  `clamp(tokens_scoring − 2, 0, 4) + tokens_notepad` CP via `award_final_score(bot, cp, "cp",
  "ARNO's final scoring")` (13181 → `apply_cp`, quiet, no checkpoint claims; prints "(capped)" if
  capped) — and decide whether outstanding CP debt is subtracted first (ruling).
- `game_winners` 13000: highest `score_counter`, ties broken by `projects_supported` (6007: count of
  nil `project_cubes`, i.e. **map cubes used** → ARNO always 0), full ties → several winners
  (`winner_text` 13023 "tie between …"). `announce_winner` 13051 shows a winner panel per player
  entry (`set_active_panel`, invisible for the bot colour, harmless). H17:
  ```lua
  local mod_game_winners = game_winners
  game_winners = function()
    local best; for _, p in ipairs(players) do
      local s = get_counter_value(p.score_counter); if best == nil or s > best then best = s end end
    local bots = {}
    for _, p in ipairs(players) do
      if p.is_arno and get_counter_value(p.score_counter) == best then bots[#bots+1] = p end end
    if #bots > 0 then return bots end   -- R16; several ARNOs tied → all of them (ruling)
    return mod_game_winners()           -- no ARNO at the top: the mod's result has only humans
  end
  ```

---

## 7. Kiosk count for card 265 Franchise Business

- Card 265 (`effect = "franchise business"`, 2506) sets `player.franchise_business = true` through
  `process_effects` (6144, generic branch 6191).
- Only reader of other players' kiosks: `map_income(player)` 17420, lines 17430-17435:
  `total += #other.map:tilesWithTag("kiosk")` for every other entry of `players`.
  `refresh_map_income(player)` 17441 adds the delta to the income counter; it runs after builds
  (17415-17417 for all players), placements and `process_effects`.
- Map A has a pre-printed kiosk start tile (`startTileTag = "kiosk"`, 1998), inserted into the
  board by `Board.new` (300-322) and spawned physically by `spawn_player_starting_tiles` (6636).
  So **without a wrapper ARNO counts 1 kiosk** for a human with Franchise Business.
- Other kiosk reads (`10370` condition, `13269`, `13384`, `13420` scoring, `4885`, `15738`) only
  look at the player's own map.
- H18:
  ```lua
  local mod_map_income = map_income
  map_income = function(player)
    local total = mod_map_income(player)
    if player.franchise_business then
      for _, other in ipairs(players) do
        if other ~= player and other.is_arno then
          total = total - #other.map:tilesWithTag("kiosk") + ARNO.kiosks(other)  -- tracker or 0 (R14)
        end
      end
    end
    return total
  end
  ```
  After the ARNO kiosk value changes, call `refresh_map_income(p)` for every human `p` with
  `p.franchise_business`.

---

## 8. Other bot-relevant facts

- **Hand reads for the bot colour** (all **unverified** for an unseated colour; guard with H16):
  `break_phase_discard` 12176, `start_final_scoring` 12968, `final_scoring_cards` 13164,
  `wait_for_all_hand_counts` 10552, `other_hand_counts` 10575, `hands_released_guids` 10612,
  `card_settled_in_hand` 10621 (the last two iterate all players' hands while *humans* wait for
  cards; an error there would break human actions too).
- `broadcastToColor(msg, bot.color)` appears on failure paths ARNO should never reach
  (6848, 6953, 7005, 10062); behaviour for an unseated colour **unverified**.
- `every_player_owns` (4304, used by `refill_association_board`) includes ARNO: a tile kind ARNO
  does not own is still refilled — correct.
- `take_player_cube` / `spawn_player_*` tint with `Color.fromString(player.color)` — fine for any
  of the four colours.
- `steam_name` is concatenated into every log line; must be a string ("ARNO 1").
- `persistent_origin` (global, 13643) is set by the claims engine; H10 resets it to false at the
  end like the stock renderer (13634).
- `effective_reward` (6019) rewrites interactive rewards when `interactive_effects == false`
  (pilfering→sprint, hypnosis→determination, venom→inventive, constriction→clever 1); apply it
  before classifying a reward (H11 does).
- `refill_display` / `zoo_deck` exhaustion and the cube bag size are mod-wide risks, not ARNO
  specific, but ARNO's extra draws (display takes + break draws) make deck exhaustion likelier.

## 9. Open points / uncertainties
1. TTS behaviour of `Player[color].getHandObjects` / `card.deal` / `broadcastToColor` for an
   unseated colour (pitfall 7, §8).
2. Visual left/right of `cp_bonuses_*[1]` vs `[2]` (x −30.41 vs −28.45): assumed `[1]` = left.
3. Whether `bags.cubes` is infinite (not validated by `bag_setup_problems`).
4. Rulings the mod cannot answer: which rep-track rewards ARNO collects; `+(n−1) appeal` with the
   max-rep tile; which icons of a discarded sponsor fire hooks (only 208/research, or all
   `hook_all`); a chosen 5/8 tile that is already gone; CP debt at final scoring; ties among
   several ARNOs.
5. Zone-content timing (pitfall 10): one TTS physics tick is assumed sufficient between a smooth
   move and the next zone query; the mod itself makes the same assumption across turns.
