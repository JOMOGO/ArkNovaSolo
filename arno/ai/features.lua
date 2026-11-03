-- AI opponent (docs/AI_OPPONENT.md §4a, §4c): the network's inputs, as one flat list of
-- numbers for a (player, choice) pair: what the player knows about the game (its own zoo and
-- hand, the public state of the others; never their hands, final scoring cards or the deck)
-- and what the choice is. Roughly scaled to 0..1. The order is fixed: the trained weights
-- depend on it (bump VERSION when it changes, and retrain).

local value = require("ai.value")
local choices = require("ai.choices")

local M = {}

M.VERSION = 3     -- 1: 39 + 46 inputs; 2: + 7 leader + 32 icons + 18 display + 1 turn, + 3 choice;
                  -- 3: + 54 opponents + 3 scoring + 7 projects + 7 map + 15 tokens + 4 hand + 6 table

local ACTIONS = { "ANIMALS", "CARDS", "BUILD", "SPONSORS", "ASSOCIATION" }
local KINDS = { "click", "pick_up", "drop_tile", "pick_up_tile" }
local TAGS = { "confirm", "pass", "back" }
local PANELS = { "actionSelectionPanel", "claimsPanel", "animalPanel", "sponsorPanel", "selectionPanel",
                 "tilePlacementPanel", "buildingPlacementPanel", "repDrawPrompt", "snapPrompt" }

local function counter(c) return c and get_counter_value(c) or 0 end
local function clip(x, lo, hi) return math.max(lo or -3, math.min(hi or 3, x)) end

local function panel_id(player)
  local xml = active_panels and active_panels[player.color]
  return xml and xml:match('id="(%a+)')
end

local function slot_of(player, kind)
  for slot = 1, 5 do
    local ok, card = pcall(action_card_object, player, slot)
    if ok and card and card.getName():upper():find("^" .. kind) then return slot end
  end
  return 0
end

-- the other player with the best score (public information only)
local function leader_of(player)
  local best, leader = nil, nil
  for _, p in ipairs(players or {}) do
    if p ~= player then
      local s = counter(p.score_counter)
      if best == nil or s > best then best, leader = s, p end
    end
  end
  return leader
end

local function icon_count(p, icon)
  local c = p and p.icon_counters and p.icon_counters[icon]
  return c and (get_icon_counter_value(c) or 0) or 0
end

-- how well a card's icons fit a zoo (0..1): its icons the zoo already collects
local function icon_fit(p, data)
  local icons = data and data.icons or {}
  if p == nil or #icons == 0 then return 0 end
  local fit = 0
  for _, icon in ipairs(icons) do fit = fit + math.min(icon_count(p, icon), 5) / 5 end
  return fit / #icons
end

local function card_data(name)
  if name == nil then return nil end
  local ok, data = pcall(card_data_for, name)
  return ok and data or nil
end

-- version 2 (docs/AI_OPPONENT.md §4c, the Expert checklist): the leading opponent, both
-- zoos' icons, the display (worth, reach, what it gives the leader) and the turn
local function state_v2(player, put)
  local leader = leader_of(player)
  put(leader and counter(leader.appeal_counter) / 50 or 0)
  put(leader and counter(leader.cp_counter) / 15 or 0)
  put(leader and counter(leader.money_counter) / 40 or 0)
  put(leader and counter(leader.income_counter) / 20 or 0)
  put(leader and counter(leader.rep_counter) / 12 or 0)
  put(leader and #(leader.x_tokens or {}) / 5 or 0)
  put(leader and #Player[leader.color].getHandObjects(1) / 8 or 0)        -- how many, not which
  for _, icon in ipairs(cnsts.icons.all) do put(icon_count(player, icon) / 5) end
  for _, icon in ipairs(cnsts.icons.all) do put(icon_count(leader, icon) / 5) end
  local rep = counter(player.rep_counter)
  for i = 1, 6 do
    local card = display_cards and display_cards[i]
    local data = card and card_data(card.getName())
    put(card and value.card(card.getName(), player) / 10 or 0)
    put(card and rep >= (cnsts.rep_range_thresholds[i] or 99) and 1 or 0)
    put(icon_fit(leader, data))
  end
  put((player.turns_taken or 0) / 40)
end

-- version 3 (owner: "the AI should have access to all public info"): everything a player at
-- the table can see, summarised (counts and totals; card-by-card would need a far bigger
-- network than fits in MoonSharp), plus the AI's own final scoring cards. Never another
-- player's hand cards or final scoring cards, nor the deck order (only how many).
local function safe(fn, default)
  local ok, v = pcall(fn)
  if ok and v ~= nil then return v end
  return default
end

local function supportable_count(p)
  return safe(function() return #supportable_projects(p) end, 0)
end

local function opponent_inputs(p, put)
  put(p and 1 or 0)
  if p == nil then
    for _ = 1, 17 do put(0) end
    return
  end
  put((counter(p.score_counter) + 14) / 114)
  put(counter(p.appeal_counter) / 50)
  put(counter(p.cp_counter) / 15)
  put(counter(p.money_counter) / 40)
  put(counter(p.income_counter) / 20)
  put(counter(p.rep_counter) / 12)
  put(#(p.x_tokens or {}) / 5)
  put(#Player[p.color].getHandObjects(1) / 8)                      -- how many cards, not which
  local upgrades = 0
  for _, flag in ipairs({ "animals_flipped", "cards_flipped", "build_flipped", "sponsors_flipped",
                          "association_flipped" }) do
    if p[flag] then upgrades = upgrades + 1 end
  end
  put(upgrades / 5)
  put(((p.worker_count or 1) - #(p.deployed_workers or {})) / 4)
  put(#(p.acquired_partner_zoos or {}) / 4)
  put(#(p.acquired_universities or {}) / 3)
  local free = 0
  if p.map then
    for id, tile in pairs(p.map.tiles) do
      local capacity = safe(function() return p.map:enclosureCapacity(id, enclosure_capacity_opts(p)) end, nil)
      if capacity and tile.tags.occupied == false then free = free + 1 end
    end
  end
  put(free / 3)
  put(p.map and p.map:countUnoccupied() / 50 or 0)
  put(#(p.played_animals or {}) / 15)
  put(#(p.played_sponsors or {}) / 10)
  put(supportable_count(p) / 3)
end

local function state_v3(player, put)
  -- the other players, best score first (up to three)
  local others = {}
  for _, p in ipairs(players or {}) do
    if p ~= player then others[#others + 1] = p end
  end
  table.sort(others, function(a, b) return counter(a.score_counter) > counter(b.score_counter) end)
  for i = 1, 3 do opponent_inputs(others[i], put) end

  -- own final scoring cards (the AI sees its own): how many, their points now
  local awards = {}
  for _, card in ipairs(safe(function() return final_scoring_cards(player) end, {})) do
    awards[#awards + 1] = safe(function()
      return final_score_award(player, final_scoring_data_for(card_number_of(card.getName())))
    end, 0)
  end
  table.sort(awards, function(a, b) return a > b end)
  put(#awards / 2); put((awards[1] or 0) / 4); put(((awards[1] or 0) + (awards[2] or 0)) / 8)

  -- conservation projects on the table
  local projects, free_slots, best_award, shortfall = 0, 0, 0, 10
  safe(function()
    each_table_project(function(guid, cubes)
      projects = projects + 1
      for slot = 1, 3 do if cubes[slot] == nil then free_slots = free_slots + 1 end end
      local obj = getObjectFromGUID(guid)
      local card = obj and card_data_for(obj.getName())
      if card and card.project == "icons" then
        local have = project_match_count(player, card.match)
        for slot = 1, 3 do
          if cubes[slot] == nil then
            local need = card.thresholds[slot] - have
            if need <= 0 then best_award = math.max(best_award, card.awards[slot] or 0)
            else shortfall = math.min(shortfall, need) end
          end
        end
      end
    end)
    return true
  end, false)
  put(projects / 8); put(free_slots / 24); put(supportable_count(player) / 3); put(best_award / 5)
  put(shortfall / 10)
  local leader = others[1]
  put(leader and supportable_count(leader) / 3 or 0)
  put(safe(function() return #playable_project_candidates(player, player.association_flipped) end, 0) / 3)

  -- own map
  local map = player.map
  put(map and safe(function() return map:countUnclaimedRewards() end, 0) / 10 or 0)
  put(map and (safe(function() return map:unoccupiedRegionSizes()[1] end, 0) or 0) / 20 or 0)
  put(map and safe(function() return map:kioskIncome() end, 0) / 10 or 0)
  for _, tag in ipairs({ "reptile_house", "large_bird_aviary", "petting_zoo", "large_aquarium" }) do
    put(map and safe(function() return #map:tilesWithTag(tag) end, 0) > 0 and 1 or 0)
  end

  -- tokens on its own action cards
  for slot = 1, 5 do
    for _, kind in ipairs({ "venom", "constriction", "multiplier" }) do
      put(safe(function() return action_card_has_token(player, slot, kind) end, false) and 1 or 0)
    end
  end

  -- what the hand can do now
  local animals = value.playable_animals(player)
  local cheapest = nil
  for _, a in ipairs(animals) do
    if cheapest == nil or (a.cost or 0) < cheapest then cheapest = a.cost or 0 end
  end
  put(#animals / 5)
  put((cheapest or 0) / 30)
  put(safe(function() return #playable_sponsor_candidates(player, 5) end, 0) / 5)
  local limit = 3 + (player.hand_size_plus_1 and 1 or 0)
  for _, uni in ipairs(player.acquired_universities or {}) do
    if uni == "hand_size" then limit = limit + 2 break end
  end
  put((limit - #player_hand_cards(player)) / 5)

  -- the table: association board, piles (how many), the next CP bonus
  put(safe(function() return #available_partner_zoos() end, 0) / 5)
  put(safe(function() return #available_universities() end, 0) / 3)
  put(safe(function() return pile_quantity(live_zoo_deck()) end, 0) / 200)
  put(safe(function() return pile_quantity(live_discard_pile()) end, 0) / 100)
  local cp, next_bonus = counter(player.cp_counter), 0
  for _, mark in ipairs({ 2, 5, 8, 10 }) do
    if cp < mark then next_bonus = mark - cp break end
  end
  put(next_bonus / 5)
  put(#(player.bonus_tiles or {}) / 3)
end

local function choice_v2(player, c, put)
  local name = c.obj and c.obj.getName() or (c.label:match(": (.+)$"))
  local data = card_data(name)
  put(icon_fit(player, data))
  put(icon_fit(leader_of(player), data))
  put((tonumber((c.label or ""):match("^%a+ (%d)") or "") or 0) / 6)    -- display slot of a snap/take
end

-- what the player knows (the same for every choice of one decision: computed once).
-- version: the input layout of the network that reads it (default the current one)
function M.state(player, version)
  local f = M.state_v1(player)
  local put = function(x) f[#f + 1] = clip(x) end
  if (version or M.VERSION) >= 2 then state_v2(player, put) end
  if (version or M.VERSION) >= 3 then state_v3(player, put) end
  return f
end

function M.state_v1(player)
  local f = {}
  local function put(x) f[#f + 1] = clip(x) end
  local progress = value.progress()
  put(progress)
  put(counter(player.money_counter) / 40)
  put(counter(player.income_counter) / 20)
  put(counter(player.appeal_counter) / 50)
  put(counter(player.cp_counter) / 15)
  put(counter(player.rep_counter) / 12)
  put((counter(player.score_counter) + 14) / 114)
  put(#(player.x_tokens or {}) / 5)
  local animals, sponsors, projects, hand = 0, 0, 0, 0
  for _, card in ipairs(player_hand_cards(player)) do
    hand = hand + 1
    local ok, data = pcall(card_data_for, card.getName())
    if ok and data then
      if data.type == "animal" then animals = animals + 1
      elseif data.type == "sponsor" then sponsors = sponsors + 1
      elseif data.type == "project" then projects = projects + 1 end
    end
  end
  put(hand / 8); put(animals / 5); put(sponsors / 5); put(projects / 3)
  for _, flag in ipairs({ "animals_flipped", "cards_flipped", "build_flipped", "sponsors_flipped",
                          "association_flipped" }) do
    put(player[flag] and 1 or 0)
  end
  for _, kind in ipairs(ACTIONS) do put(slot_of(player, kind) / 5) end
  put(((player.worker_count or 1) - #(player.deployed_workers or {})) / 4)
  put(#(player.acquired_partner_zoos or {}) / 4)
  put(#(player.acquired_universities or {}) / 3)
  -- free enclosures that fit an animal of size 1..5
  local free = { 0, 0, 0, 0, 0 }
  if player.map then
    for id, tile in pairs(player.map.tiles) do
      local ok, capacity = pcall(function() return player.map:enclosureCapacity(id, enclosure_capacity_opts(player)) end)
      if ok and capacity and tile.tags.occupied == false then
        for s = 1, math.min(5, capacity) do free[s] = free[s] + 1 end
      end
    end
    put(player.map:countUnoccupied() / 50)
  else
    put(0)
  end
  for s = 1, 5 do put(free[s] / 3) end
  put(#(player.played_animals or {}) / 15)
  put(#(player.played_sponsors or {}) / 10)
  -- the others (public)
  local own = counter(player.score_counter)
  local best, appeal, cp, n = -14, 0, 0, 0
  for _, p in ipairs(players or {}) do
    if p ~= player then
      n = n + 1
      best = math.max(best, counter(p.score_counter))
      appeal, cp = appeal + counter(p.appeal_counter), cp + counter(p.cp_counter)
    end
  end
  put((own - best) / 30)
  put(n > 0 and appeal / n / 50 or 0)
  put(n > 0 and cp / n / 15 or 0)
  put(#(players or {}) / 4)
  put((break_current_val or 0) / math.max(1, break_init_val or 9))
  put(game_end_triggered and 1 or 0)
  return f
end

local function reward_sum(list, pattern)
  local n = 0
  for _, r in ipairs(type(list) == "table" and list or {}) do
    if type(r) == "string" and r:lower():find(pattern) then n = n + (tonumber(r:match("(%d+)")) or 1) end
  end
  return n
end

-- what the choice is; `heuristic` is ai.policy.score for it
function M.choice(player, c, heuristic, version)
  local f = M.choice_v1(player, c, heuristic)
  if (version or M.VERSION) >= 2 then
    choice_v2(player, c, function(x) f[#f + 1] = clip(x) end)
  end
  return f
end

function M.choice_v1(player, c, heuristic)
  local f = {}
  local function put(x) f[#f + 1] = clip(x) end
  for _, k in ipairs(KINDS) do put(c.kind == k and 1 or 0) end
  for _, t in ipairs(TAGS) do put(c.tag == t and 1 or 0) end
  local panel = panel_id(player)
  for _, id in ipairs(PANELS) do put(panel == id and 1 or 0) end
  -- an action card
  local action, strength = nil, 0
  if c.handler == "on_action_card_button_clicked" then
    action = (c.label:match("^(%a+)") or ""):upper()
    strength = choices.strength(player, c) or 0
  end
  for _, a in ipairs(ACTIONS) do put(action == a and 1 or 0) end
  put(strength / 5)
  put(c.handler == "on_take_x_token_clicked" and 1 or 0)
  put((c.handler or ""):find("spin", 1, true) and 1 or 0)
  -- a card
  local name = c.obj and c.obj.getName() or (c.label:match(": (.+)$"))
  local data
  if name then
    local ok, d = pcall(card_data_for, name)
    if ok then data = d end
  end
  put(data and data.type == "animal" and 1 or 0)
  put(data and data.type == "sponsor" and 1 or 0)
  put(data and data.type == "project" and 1 or 0)
  put(data and (data.cost or 0) / 30 or 0)
  put(data and (data.size or 0) / 5 or 0)
  put(data and reward_sum(data.rewards, "appeal") / 10 or 0)
  put(data and reward_sum(data.rewards, "cp") / 5 or 0)
  put(data and reward_sum(data.rewards, "rep") / 3 or 0)
  put(data and #(data.icons or {}) / 4 or 0)
  put(data and (data.level or 0) / 10 or 0)
  put(data and name and data.type == "animal" and select(2, pcall(is_animal_playable, name, player, nil)) == true and 1 or 0)
  local selection = selection_panels and selection_panels[player.color]
  local sel_action = selection and selection.action or ""
  put(sel_action:find("discard", 1, true) and 1 or 0)
  put(sel_action == "keep" and 1 or 0)
  put(sel_action == "sell" and 1 or 0)
  -- the label as a reward
  local label = (c.label or ""):lower()
  put(value.reward(c.label, player) / 10)
  put(label:find("appeal", 1, true) and 1 or 0)
  put((label:find("conservation", 1, true) or label:match("%f[%w]cp%f[%W]")) and 1 or 0)
  put(label:find("money", 1, true) and 1 or 0)
  put(label:find("rep", 1, true) and 1 or 0)
  -- a tile spot or an enclosure
  put(c.cells and #c.cells / 5 or 0)
  local id = c.kind == "pick_up_tile" and tonumber(c.label:match("(%d+)$") or "")
  local tile = id and player.map and player.map.tiles[id]
  put(tile and #tile.cells / 5 or 0)
  put(clip((heuristic or 0) / 20))
  return f
end

-- inputs per version (state + choice); a network's weights say which one it reads
M.SIZES = { [1] = { 39, 46 }, [2] = { 97, 49 }, [3] = { 193, 49 } }

function M.version_of(weights)
  if weights == nil then return M.VERSION end
  if weights.features then return weights.features end
  for v, s in pairs(M.SIZES) do
    if s[1] + s[2] == weights.inputs - (weights.cards or 0) then return v end
  end
  return 1
end

-- card-identity inputs (weights with `cards`, tools/ai_train.py train --cards): the number of
-- the card a choice is about (a card picked up, or named in the label as "...: (123) Name"),
-- 0 if none. The same as the D lines' field 7 (tests/lua/selfplay.lua M_card_number).
function M.card_number(c)
  local name
  if c.obj then
    local ok, n = pcall(function() return c.obj.getName() end)
    if ok then name = n end
  end
  name = name or (c.label or ""):match(": (.+)$") or c.label or ""
  return tonumber(tostring(name):match("%((%d+)%)")) or 0
end

return M
