-- ARNO 3.0 for "Ark Nova - Complete Scripted" (Tabletop Simulator).
-- ARNO solo mode designed by Andre K. See NOTICE.
--
-- Executes ARNO's plan steps through the mod's own primitives, and installs the wrappers
-- that keep the mod's claims engine from showing ARNO a panel or ending his turn early.
-- Every call sequence follows docs/MOD_PRIMITIVES.md (§ numbers in comments).
--
-- Step runner: a run is an ordered list of steps; a step handler gets `continue`, which it
-- calls exactly once when the step (including its rewards) is complete. Steps that use a
-- rendering primitive (take_partner_zoo, take_university, unlock_worker, the 10-CP discard)
-- continue through `player.on_claims_empty`, consumed by the H10 bot branch of
-- render_claims_table. Rewards that arrive while a step runs (CP checkpoints, track bonuses,
-- map bonuses) are queued as sub-steps that run right after the current step.

local state = require("adapter.state")
local decide = require("core.decide")
local plan = require("core.plan")
local rulings = require("core.rulings")
local tracker = require("core.project_tracker")

local M = {}

M.current = nil            -- the active run (transient)

-- ---------------------------------------------------------------- positions on ARNO's mat
-- ARNO only uses the right area of his mat (rules p2). His zoo cards and final scoring
-- card lie in front of the mat (owner choice). Boards are axis aligned: world = board + offset.
M.OFFSETS = {
  -- owner choice: everything ARNO receives lies in front of his mat, in his (unused)
  -- played-cards row (base mod: played_cards_col_1 = -7.23, -0.03, -12.87; columns 3.6
  -- apart). Boards are only ~2 units apart sideways, so nothing goes beside the mat.
  scoring = { -7.23, 0.3, -12.87 },      -- column 1: face-down final scoring card
  scoring_token = { -8.1, 0.7, -12.87 }, --   its tokens, +0.45 x per token
  projects = { -3.63, 0.3, -12.87 },     -- column 2: kept conservation project cards,
  project_step = { 0, 0.05, -1.3 },      --   fanned downwards like played cards
  animals = { -0.03, 0.3, -12.87 },      -- column 3: pile of his animal cards
  notepad_token = { 2.9, 0.4, -12.87 },  -- column 4: notepad tokens, +0.45 x per token
  reveal = { -6.0, 2.0, 7.0 },           -- break draw reveal row, +2.6 x per card
}

local function at(player, key, dx, dy, dz)
  local o = M.OFFSETS[key]
  local p = player.player_board.getPosition()
  return { x = p.x + o[1] + (dx or 0), y = p.y + o[2] + (dy or 0), z = p.z + o[3] + (dz or 0) }
end
M.at = at

local function bot_of(player) return state.bot(player.color) end

local function contains(list, v)
  for _, x in ipairs(list or {}) do if x == v then return true end end
  return false
end

-- ---------------------------------------------------------------- runner

local function new_run(player, steps, describe, done)
  local run = { player = player, items = {}, describe = describe, done = done, insert_at = 1 }
  for i, s in ipairs(steps or {}) do run.items[i] = s end
  return run
end

local function next_step(run)
  -- MoonSharp errors on table.remove(t, 1) for an empty t (stock Lua 5.2 does not)
  local step = nil
  if #run.items > 0 then step = table.remove(run.items, 1) end
  if step == nil then
    if M.current == run then M.current = nil end
    if run.done then run.done() end
    return
  end
  run.insert_at = 1
  local handler = M.STEPS[step.kind]
  local finished = false
  local function continue()
    if finished then return end
    finished = true
    Wait.frames(function() next_step(run) end, 1)
  end
  if handler == nil then
    state.note(run.player, "(no handler for step " .. tostring(step.kind) .. ")")
    return continue()
  end
  local ok, err = pcall(handler, run.player, step, continue)
  if not ok then
    state.note(run.player, "ERROR in step " .. tostring(step.kind) .. ": " .. tostring(err) ..
      " (rewind, or use 'Run ARNO turn')")
    run.player.on_claims_empty = nil
    return continue()
  end
end

function M.run(player, steps, describe, done)
  local run = new_run(player, steps, describe, done)
  M.current = run
  next_step(run)
end

-- Queue a sub-step behind the current step (or run it at once when no run is active).
function M.queue(player, step)
  step.internal = true
  local run = M.current
  if run ~= nil and run.player == player then
    table.insert(run.items, run.insert_at, step)
    run.insert_at = run.insert_at + 1
  else
    local solo = new_run(player, { step }, nil, nil)
    next_step(solo)
  end
end

-- ---------------------------------------------------------------- tracks (§3 steps 1-4)

function M.gain_cp(player, n, source)
  local bot = bot_of(player)
  local pay = math.min(n, bot.cp_debt or 0)
  if pay > 0 then bot.cp_debt = bot.cp_debt - pay end
  local surplus = n - pay
  if surplus <= 0 then
    state.note(player, string.format("Conservation +%d pays off his starting debt (%d left)", n, bot.cp_debt))
    return
  end
  local applied, old, new = apply_cp(player, surplus)
  if pay > 0 then
    state.note(player, string.format("Conservation +%d (%d pay off the debt) -> %d CP", n, pay, new))
  else
    state.note(player, string.format("Conservation +%d -> %d CP", n, new))
  end
  print_track_change(player, applied, "conservation point", source or "ARNO")
  -- checkpoints, in the order the mod offers them (4549-4580)
  if old < 2 and new >= 2 then M.queue(player, { kind = "cp_bonus_2" }) end
  if old < 5 and new >= 5 then M.queue(player, { kind = "bonus_tile", cp = 5 }) end
  if old < 8 and new >= 8 then M.queue(player, { kind = "bonus_tile", cp = 8 }) end
  if old < 10 and new >= 10 and not final_scoring_discard_triggered then
    final_scoring_discard_triggered = true
    M.queue(player, { kind = "humans_discard_final_scoring" })
  end
end

function M.gain_rep(player, n, source)
  local old = get_counter_value(player.rep_counter)
  local max = rulings.REPUTATION_MAX
  local new = math.min(max, old + n)
  set_counter(player.rep_counter, new, cnsts.counter_style.rep)
  move_when_settled(player.reputation_token.getGUID(), get_rep_zone_position(new))
  print_track_change(player, new - old, "reputation", source or "ARNO")
  state.note(player, string.format("Reputation +%d -> %d", new - old, new))
  local overflow = old + n - new
  if overflow > 0 then
    if marine_worlds_enabled and rep_max_bonus ~= nil then
      local tile = rep_max_bonus
      local reward = bonus_tile_reward(tile)
      rep_max_bonus = nil
      set_tile_face(tile, true)
      state.note(player, "Takes the maximum-reputation bonus tile (" .. tostring(reward) .. ")")
      M.queue(player, { kind = "tile_reward", reward = reward })
      if overflow > 1 then
        update_appeal(player, overflow - 1, "maxing reputation")
        state.note(player, string.format("Reputation maxed: +%d appeal", overflow - 1))
      end
    else
      update_appeal(player, overflow, "maxing reputation")
      state.note(player, string.format("Reputation maxed: +%d appeal", overflow))
    end
  end
  for v = old + 1, new do                     -- reputation track rewards (R19)
    local r = cnsts.rep_rewards[v]
    if r == "card flip" then M.queue(player, { kind = "upgrade" })
    elseif r == "unlock worker" then M.queue(player, { kind = "unlock_worker" })
    elseif r ~= nil and r:match("^%d+ cp$") then M.gain_cp(player, tonumber(r:match("^(%d+)")), "the reputation track")
    elseif r ~= nil and r ~= "" then state.log("ignores reputation reward '" .. r .. "'")
    end
  end
end

-- ---------------------------------------------------------------- upgrades (§3 step 12)

function M.flip_physical(player, name)
  local slot = action_card_slot_named(player, string.upper(name))
  if slot == nil then return end
  local card = action_card_object(player, slot)
  if card ~= nil and not action_card_upgraded(card) then
    set_tile_face(card, true)
  end
  if card ~= nil then
    local attr = cnsts.action_flip_attributes[string.sub(card.getName(), 1, 2)]
    if attr then player[attr] = true end
  end
end

function M.upgrade(player)
  local bot = bot_of(player)
  local r = state.rng()
  local name = decide.upgrade(bot, r)
  state.put_rng(r)
  if name == nil then
    state.note(player, "Card upgrade earned, but 3 cards are already upgraded")
    return
  end
  M.flip_physical(player, name)
  state.note(player, "Upgrades his " .. string.upper(name) .. " card")
end

-- Order after the used card moved to slot 1 (what the table shows between ARNO turns).
function M.physical_order(bot)
  local cs = bot.card_slots
  local order = { }
  if bot.last_slot ~= nil then order[1] = cs.slots[bot.last_slot] end
  for i, name in ipairs(cs.slots) do
    if i ~= bot.last_slot then order[#order + 1] = name end
  end
  return order
end

-- Physical action cards follow the core's slot order and upgrades (cards are display only).
function M.sync_action_cards(player)
  local bot = bot_of(player)
  local cs = bot and bot.card_slots
  if cs == nil or player.action_cards == nil then return end
  -- physically the used card moves to slot 1 at the end of the turn (as for humans)
  local order = M.physical_order(bot)
  for i, name in ipairs(order) do
    local cur = action_card_slot_named(player, string.upper(name))
    if cur ~= nil and cur ~= i then move_action_card(player, cur, i) end
  end
  for _, name in ipairs(cs.upgraded) do M.flip_physical(player, name) end
end

-- ---------------------------------------------------------------- cards on ARNO's mat

local function card_name(obj) return string.sub(obj.getName(), 7) end

function M.place_animal(player, obj, data)
  local bot = bot_of(player)
  bot.mat_animals = bot.mat_animals or {}
  bot.mat_animals[#bot.mat_animals + 1] = obj.getGUID()
  player.played_animals[#player.played_animals + 1] = obj.getGUID()
  obj.locked = false
  obj.setPositionSmooth(at(player, "animals", 0, 0.03 * #bot.mat_animals, 0), false, false)
  obj.setRotationSmooth({ 0, 180, 0 }, false, false)
  Wait.condition(function() obj.locked = true end, function() return not obj.isSmoothMoving() end, 5)
  -- icons count as ARNO's (reference values) and fire human "whenever any player" hooks;
  -- ARNO's own hook rewards (returned) are ignored (rules p2)
  add_remove_icons(player, data.icons or {})
  state.note(player, "  " .. card_name(obj) .. " goes on his mat (" .. table.concat(data.icons or {}, ", ") .. ")")
end

function M.keep_project(player, obj)
  local bot = bot_of(player)
  bot.mat_projects[#bot.mat_projects + 1] = obj.getGUID()
  M.layout_projects(player)
  state.note(player, "  keeps project " .. card_name(obj) .. " on his mat")
end

function M.layout_projects(player)
  local bot = bot_of(player)
  for i, guid in ipairs(bot.mat_projects) do
    local obj = getObjectFromGUID(guid)
    if obj ~= nil then
      local s = M.OFFSETS.project_step
      obj.locked = false
      obj.setPositionSmooth(at(player, "projects", s[1] * (i - 1), s[2] * (i - 1), s[3] * (i - 1)), false, false)
      obj.setRotationSmooth({ 0, 180, 0 }, false, false)
    end
  end
end

-- discard a received sponsor: it can still trigger human effects (R18), counts for the module
function M.discard_sponsor(player, obj, data)
  local bot = bot_of(player)
  bot.sponsor_discards = (bot.sponsor_discards or 0) + 1
  report_discard(player, { obj }, true)
  obj.locked = false
  discard_pile.putObject(obj)
  if data and data.icons and #data.icons > 0 then apply_hooks(player, data.icons) end
end

-- ---------------------------------------------------------------- steps

M.STEPS = {}
local S = M.STEPS

S.appeal = function(p, step, continue)
  update_appeal(p, step.n, "ARNO")
  state.note(p, string.format("Appeal +%d -> %d", step.n, get_counter_value(p.appeal_counter)))
  continue()
end
S.reputation = function(p, step, continue) M.gain_rep(p, step.n, "ARNO"); continue() end
S.conservation = function(p, step, continue) M.gain_cp(p, step.n, "ARNO"); continue() end

S["break"] = function(p, step, continue)
  local before = break_current_val or 0
  break_x(step.n, nil)                               -- nil: ARNO gets no X-token (R7)
  printToAll(string.format("%s advances the break token %d space(s).", p.steam_name, before - (break_current_val or 0)))
  state.note(p, string.format("Break token +%d (%d left before the break)", before - (break_current_val or 0), break_current_val or 0))
  continue()
end

local function token_cube(p, key, index)
  local pos = at(p, key, 0.45 * (index - 1), 0, 0)
  local cube = take_player_cube(p, pos)
  local bot = bot_of(p)
  bot.token_cubes = bot.token_cubes or {}
  bot.token_cubes[#bot.token_cubes + 1] = cube.getGUID()
end

S.token_scoring = function(p, step, continue)
  -- the count was added when the card was drawn (decide.turn); this is the visual token
  token_cube(p, "scoring_token", math.min(bot_of(p).tokens_scoring, 8))
  state.note(p, string.format("Token on his final scoring card (%d now)", bot_of(p).tokens_scoring))
  continue()
end

S.token_notepad = function(p, step, continue)
  local bot = bot_of(p)
  for i = 1, step.n do token_cube(p, "notepad_token", bot.tokens_notepad - step.n + i) end
  state.note(p, string.format("%d token(s) on his notepad (%d now)", step.n, bot.tokens_notepad))
  continue()
end

S.take_display = function(p, step, continue)
  local k = step.position
  local obj = display_cards[k]
  if obj == nil then
    state.note(p, "Display slot " .. k .. " is empty: no card")
    return continue()
  end
  local data = card_data_for(obj.getName())
  state.note(p, string.format("Takes display card #%d: %s", k, card_name(obj)))
  resolve_display_mark(k, false)                      -- a marking player is paid (§3 step 5)
  display_cards[k] = nil
  if data.type == "animal" then
    M.place_animal(p, obj, data)
  elseif data.type == "sponsor" then
    state.note(p, "  sponsor card: discarded")
    M.discard_sponsor(p, obj, data)
  else
    M.keep_project(p, obj)
  end
  refill_display(function() continue() end)
end

S.worker = function(p, step, continue)
  if available_workers(p) >= 1 then
    deploy_workers_to_task(p, step.task, 1)
    local TASK = { [2] = "Reputation", [3] = "Partner zoo", [4] = "University", [5] = "Conservation project" }
    state.note(p, string.format("Places a worker on the %s task", TASK[step.task] or tostring(step.task)))
  else
    state.note(p, "No free worker (unexpected)")
  end
  continue()
end

local function take_zoo(p, zoo, continue)
  if zoo == nil or not contains(available_partner_zoos(p, false), zoo) then
    state.note(p, "Partner zoo " .. tostring(zoo) .. " not available")
    return continue()
  end
  state.note(p, "Gains the " .. partner_zoo_label(zoo))
  p.on_claims_empty = continue
  take_partner_zoo(p, zoo, false)
end

local function take_uni(p, name, species, continue)
  local key = (name == "species") and species or name
  if key == nil or not contains(available_universities(p, false), key) then
    state.note(p, "University " .. tostring(key) .. " not available")
    return continue()
  end
  local spec = cnsts.universities[key]
  state.note(p, "Gains the " .. (spec and spec.label or tostring(key)))
  p.on_claims_empty = continue
  take_university(p, key, false)
end

S.partner_zoo = function(p, step, continue) take_zoo(p, step.zoo, continue) end
S.university = function(p, step, continue) take_uni(p, step.name, step.species, continue) end

local function find_entry(id)
  local row, i = id:match("^(%a+):(%d+)$")
  local list = row == "base" and base_projects or added_projects
  return list and list[tonumber(i)]
end

S.project = function(p, step, continue)
  local bot = bot_of(p)
  local entry, obj
  if step.source == "mat" then
    obj = getObjectFromGUID(step.id)
    for i, guid in ipairs(bot.mat_projects) do
      if guid == step.id then table.remove(bot.mat_projects, i) break end
    end
    if obj == nil then state.note(p, "Project card missing"); return continue() end
    obj.locked = false
    add_project_to_row(obj)
    entry = added_projects[#added_projects]
    M.layout_projects(p)
  else
    entry = find_entry(step.id)
    obj = entry and getObjectFromGUID(entry[1])
  end
  if entry == nil or obj == nil or step.place_slot == nil then
    state.note(p, "No project slot available"); return continue()
  end
  local data = card_data_for(obj.getName())
  local s = step.place_slot
  if entry[2][s] ~= nil then state.note(p, "Project slot is taken"); return continue() end
  local pos = project_slot_world_position(obj, data.project, s)
  local cube = take_player_cube(p, { x = pos.x, y = pos.y + cnsts.drop_height, z = pos.z })
  entry[2][s] = cube.getGUID()
  local SLOT_NAME = { "left", "middle", "right" }
  state.note(p, string.format("Supports project %s (%s condition)", card_name(obj), SLOT_NAME[s] or tostring(s)))
  local source = "supporting " .. card_name(obj)
  for _, r in ipairs(project_slot_awards(p, data, step.reward_slot or s) or {}) do
    if r:match("^%d+ cp$") then M.gain_cp(p, tonumber(r:match("^(%d+)")), source)
    elseif r:match("^%d+ rep$") then M.gain_rep(p, tonumber(r:match("^(%d+)")), source)
    elseif r:match("^%d+ appeal$") then update_appeal(p, tonumber(r:match("^(%d+)")), source)
    elseif r == "management rep" then M.gain_rep(p, management_rep_amount(p), source)
    else state.log("ignores project reward '" .. r .. "'") end
  end
  continue()
end

S.donate = function(p, step, continue)
  local _, key = donation_slot()
  if key ~= nil then
    take_player_cube(p, zones[key].getPosition() + Vector(0, 1, 0))
  else
    take_player_cube(p, donation_12_position(donation_12_count() + 1))
  end
  state.note(p, "Donates (token on the next donation spot)")
  M.gain_cp(p, step.cp or rulings.DONATE_CP, "the donation")
  continue()
end

S.skip = function(p, step, continue)
  state.note(p, "Skipped: " .. tostring(step.reason))
  continue()
end

-- sub-steps -------------------------------------------------------------------------

S.upgrade = function(p, _, continue) M.upgrade(p); continue() end

S.unlock_worker = function(p, _, continue)
  if (p.worker_count or 1) >= 4 then
    state.note(p, "Worker earned, but all 4 are already unlocked")
    return continue()
  end
  state.note(p, "Unlocks an association worker")
  p.on_claims_empty = continue
  unlock_worker(p, "ARNO")
end

-- 2-CP bonus: worker or upgrade; from 2 CP on ARNO always takes the worker (R17)
S.cp_bonus_2 = function(p, _, continue)
  if (p.worker_count or 1) < 4 then return S.unlock_worker(p, {}, continue) end
  M.upgrade(p)
  continue()
end

-- 5/8-CP bonus tile: one of the two variable tiles, never the pre-printed bonus (R17)
S.bonus_tile = function(p, step, continue)
  local pool = step.cp == 5 and cp_bonuses_5 or cp_bonuses_8
  local sides = {}
  for side = 1, 2 do if pool[side] ~= nil then sides[#sides + 1] = side end end
  if #sides == 0 then
    state.note(p, "No " .. step.cp .. "-CP bonus tile left")
    return continue()
  end
  local side = sides[1]
  if #sides == 2 then
    local r = state.rng()
    side = decide.bonus_tile_roll(r)
    state.put_rng(r)
  end
  local tile = pool[side]
  local reward = bonus_tile_reward(tile)
  pool[side] = nil
  set_tile_face(tile, true)
  local tile_text = tostring(reward):gsub("^BONUS: ", ""):gsub("^TOKEN: ", "")
  state.note(p, string.format("%d CP: takes the %s bonus tile (%s)", step.cp, side == 1 and "left" or "right", tile_text))
  return S.tile_reward(p, { reward = reward }, continue)
end

S.tile_reward = function(p, step, continue)
  local reward = step.reward
  if reward == "BONUS: 2 rep" then
    M.gain_rep(p, 2, "a bonus tile")
    return continue()
  end
  local r = state.rng()
  if reward == "BONUS: get partner zoo" then
    local zoo = plan._roll_partner_zoo(r, require("adapter.snapshot").facts(p, bot_of(p)).zoos.available)
    state.put_rng(r)
    return take_zoo(p, zoo, continue)
  elseif reward == "BONUS: get university" then
    local unis = require("adapter.snapshot").facts(p, bot_of(p)).universities
    local name, species = plan._roll_university(r, unis)
    state.put_rng(r)
    return take_uni(p, name, species, continue)
  end
  state.put_rng(r)
  state.note(p, "  he cannot use it; the tile is removed")
  continue()
end

S.humans_discard_final_scoring = function(p, _, continue)
  state.note(p, "10 CP: every human discards a final scoring card")
  p.on_claims_empty = continue
  start_final_scoring_discard(p)
end

-- ---------------------------------------------------------------- turn end (§4)

function M.end_turn(player)
  player.on_claims_empty = nil
  player.claims = {}
  player.post_action_rewards = {}
  player.offer_multiplier = nil
  player.venom_unpaid = nil
  if player.persistent_rewards then player.persistent_rewards.venom_fee = nil end
  player.hypnotize_action = false
  player.current_action = nil
  claims_players[player.color] = nil
  if action_selection_state then action_selection_state[player.color] = nil end
  finish_player_turn(player)
end

-- ---------------------------------------------------------------- setup cards (rules p3)

-- 8 random zoo cards: keep up to the first 2 projects, discard the rest; one face-down
-- final scoring card. Called from the H8 start_game wrapper (players already restored).
function M.deal_bot_setup_cards(bots, done)
  -- the humans' pile was built this frame by discard_cards_to_new_pile; zone contents lag
  -- physical moves, so use the pile object it returned (captured by the wrapper below)
  local pile = arno_last_discard_pile
  if pile == nil then
    local zone = getObjectFromGUID(cnsts.discard_pile_zone)
    pile = getByType(zone, "Deck") or getByType(zone, "Card")
  end
  for _, p in ipairs(bots) do
    local bot = bot_of(p)
    bot.setup_discards = 0
    local kept, discards = 0, {}
    for _ = 1, cnsts.starting_hand_size do
      local card = zoo_deck.takeObject({ position = at(p, "reveal"), smooth = false })
      card.addTag("zoo_card")
      local data = card_data_for(card.getName())
      if data.type == "project" and kept < 2 then
        kept = kept + 1
        M.keep_project(p, card)
      else
        if data.type == "sponsor" then bot.sponsor_discards = (bot.sponsor_discards or 0) + 1 end
        discards[#discards + 1] = card
      end
    end
    bot.setup_discards = #discards
    if #discards > 0 then pile = discard_cards_to_new_pile(p, discards, pile) end
    local scoring = final_scoring_deck.takeObject({ position = at(p, "scoring"), rotation = { 0, 180, 180 }, smooth = false })
    scoring.locked = true
    bot.scoring_card = scoring.getGUID()
    state.note(p, string.format("Setup: keeps %d project card(s), discards %d card(s)", kept, bot.setup_discards))
  end
  done()
end

-- ---------------------------------------------------------------- break draw (rules p4)

function M.break_draw(player, done)
  local bot = bot_of(player)
  local n = math.min(3, #zoo_deck.getObjects())
  local got_project, got_animal = false, false
  state.note(player, "Break: draws " .. n .. " card(s)")
  for i = 1, n do
    local card = zoo_deck.takeObject({ position = at(player, "reveal", 2.6 * (i - 1), 0, 0), rotation = { 0, 180, 0 }, smooth = false })
    card.addTag("zoo_card")
    local data = card_data_for(card.getName())
    if data.type == "project" and not got_project then
      got_project = true
      M.keep_project(player, card)
    elseif data.type == "animal" and not got_animal then
      got_animal = true
      M.place_animal(player, card, data)
    elseif data.type == "sponsor" then
      state.note(player, "  discards sponsor " .. card_name(card))
      M.discard_sponsor(player, card, data)
    else
      state.note(player, "  discards " .. card_name(card))
      report_discard(player, { card }, true)
      discard_pile.putObject(card)
    end
  end
  if arno_state.project_module then require("ui.panel").render(nil) end
  Wait.frames(done, 5)
end

-- ---------------------------------------------------------------- wrappers

function M.install_hooks(wrap)
  local setup = require("adapter.setup")
  local is_bot = setup.is_bot

  -- Runs a mod function with `players` = humans only. Returns exactly the original's return
  -- values: a padded tuple (true, nil, nil) is rejected by TTS's Wait.condition
  -- ("condition_function does not return bool", found in play).
  local function pack(...) return { n = select("#", ...), ... } end
  local function with_humans(orig, ...)
    if not state.active() then return orig(...) end
    local saved = players
    players = setup.humans(players)
    local r = pack(pcall(orig, ...))
    players = saved
    if not r[1] then error(r[2], 0) end
    return (table.unpack or unpack)(r, 2, r.n)
  end

  -- H10: ARNO's claims are claimed in order; never a panel, never end_player_turn
  wrap("H10", "render_claims_table", function(orig)
    return function(player)
      if not is_bot(player) then return orig(player) end
      claims_players[player.color] = nil
      while #player.claims > 0 do
        local sub = player.claims[#player.claims]
        if sub.refresh then local r = sub.refresh; sub.refresh = nil; r(sub) end
        while pop_first_invalid_claim(sub) do end
        if #sub == 0 then
          table.remove(player.claims)
        elseif sub.grouped then
          state.log("passes a choice (" .. tostring(resolve_claim_text(sub[1])) .. ")")
          table.remove(player.claims)
        else
          local claim = sub[1]
          pop_claim(sub, 1)
          persistent_origin = sub.from_persistent or false
          claim.function_call(resolve_claim_text(claim))
          if claim.async then return end
        end
      end
      persistent_origin = false
      local resume = player.on_claims_empty
      if resume ~= nil then
        player.on_claims_empty = nil
        Wait.frames(function()
          if #player.claims == 0 then resume()
          else player.on_claims_empty = resume; render_claims_table(player) end
        end, 1)
      end
    end
  end)

  -- H11: ARNO's rewards: appeal, CP, reputation, upgrades, workers; nothing else (R19)
  wrap("H11", "apply_reward_string", function(orig)
    return function(player, reward, source)
      if not is_bot(player) then return orig(player, reward, source) end
      reward = effective_reward(reward)
      local a, b = split_combined_reward(reward)
      if a ~= nil then
        apply_reward_string(player, a, source)
        return apply_reward_string(player, b, source)
      end
      local n = tonumber(reward:match("^(%d+) "))
      if reward:match("^%d+ appeal$") then
        update_appeal(player, n, source)
        return
      elseif reward:match("^%d+ cp$") then M.gain_cp(player, n, source)
      elseif reward:match("^%d+ rep$") then M.gain_rep(player, n, source)
      elseif reward == "card flip" or reward == "card flip b" then M.queue(player, { kind = "upgrade" })
      elseif reward == "unlock worker" then M.queue(player, { kind = "unlock_worker" })
      else
        state.log("ignores reward '" .. tostring(reward) .. "'")
      end
      if not is_reward_sync(reward) then render_claims_table(player) end
    end
  end)

  -- ARNO never uses money or X-tokens (rules p2)
  wrap("MONEY", "update_money", function(orig)
    return function(player, amount, ...)
      if is_bot(player) then return end
      return orig(player, amount, ...)
    end
  end)
  wrap("XTOKEN", "update_x_token", function(orig)
    return function(player, amount, ...)
      if is_bot(player) then return end
      return orig(player, amount, ...)
    end
  end)

  -- remember the setup discard pile object for ARNO's own setup discards (H8)
  wrap("H8", "discard_cards_to_new_pile", function(orig)
    return function(...)
      local pile = orig(...)
      arno_last_discard_pile = pile
      return pile
    end
  end)

  -- H12: no hand limit and no income for ARNO; his income slot runs his break draw
  wrap("H12", "break_phase_discard", function(orig)
    return function(...) return with_humans(orig, ...) end
  end)
  wrap("H12", "start_player_income", function(orig)
    return function(player)
      if not is_bot(player) then return orig(player) end
      take_checkpoint("income", player)
      local started = false
      local function go()
        if started then return end
        started = true
        M.break_draw(player, function() advance_income_phase() end)
      end
      Wait.condition(go, function() return not checkpoint_open end, 10, function()
        state.log("checkpoint store did not confirm; break draw continues anyway")
        go()
      end)
    end
  end)

  -- H14: final scoring: ARNO discards nothing; his CP come from his tokens (rules p10)
  wrap("H14", "prompt_final_scoring_discard", function(orig)
    return function(player, count, pool, callback)
      if is_bot(player) then
        if callback then callback() end
        return
      end
      return orig(player, count, pool, callback)
    end
  end)
  wrap("H14", "start_final_scoring", function(orig)
    return function(...)
      if final_scoring_discard_triggered then return orig(...) end
      return with_humans(orig, ...)
    end
  end)
  wrap("H14", "score_final_scoring_cards", function(orig)
    return function(player)
      if not is_bot(player) then return orig(player) end
      local bot = bot_of(player)
      local cp = decide.final_cp(bot)
      local pay = math.min(cp, bot.cp_debt or 0)
      bot.cp_debt = (bot.cp_debt or 0) - pay
      state.note(player, string.format("Final scoring: %d CP from his tokens (%d pay off the debt)", cp, pay))
      if cp - pay > 0 then award_final_score(player, cp - pay, "cp", "ARNO's final scoring tokens") end
    end
  end)

  -- H16 (more): hand loops that run while humans wait for cards
  wrap("H16", "hands_released_guids", function(orig)
    return function(...) return with_humans(orig, ...) end
  end)
  wrap("H16", "card_settled_in_hand", function(orig)
    return function(color, ...)
      if state.active() and state.bot(color) ~= nil then return false end
      return orig(color, ...)
    end
  end)

  -- H18: kiosks for card 265 Franchise Business: module tracker value, else 0 (R14)
  wrap("H18", "map_income", function(orig)
    return function(player)
      local total = orig(player)
      if not state.active() or not player.franchise_business then return total end
      for _, other in ipairs(players) do
        if other ~= player and is_bot(other) and other.map ~= nil then
          local kiosks = 0
          if arno_state.project_module then
            kiosks = tracker.kiosk_count(tracker.position(bot_of(other).sponsor_discards or 0))
          end
          total = total - #other.map:tilesWithTag("kiosk") + kiosks
        end
      end
      return total
    end
  end)
end

return M
