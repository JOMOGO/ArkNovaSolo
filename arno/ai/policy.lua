-- AI opponent (docs/AI_OPPONENT.md §4): picks one of the choices ai.choices lists.
-- For now only the policies the no-stall tests need (milestone M1):
--   random  a seeded random legal choice; Back/Cancel only when nothing else is offered
--           (going back and forth would never end a turn), Pass less often than the rest
--   first   the first choice that is not Back (the every-card driver's habit)
-- The level policies (network, point budget, personalities, lookahead) come later.

local rng = require("core.rng")

local M = {}

M.PASS_WEIGHT = 0.25

local function forward(choices)
  local out = {}
  for _, c in ipairs(choices) do
    if c.tag ~= "back" then out[#out + 1] = c end
  end
  if #out == 0 then return choices end
  return out
end

function M.random(r)
  return function(_, choices)
    local pool = forward(choices)
    local total = 0
    for _, c in ipairs(pool) do total = total + (c.tag == "pass" and M.PASS_WEIGHT or 1) end
    local x = rng.next(r) * total
    for _, c in ipairs(pool) do
      x = x - (c.tag == "pass" and M.PASS_WEIGHT or 1)
      if x < 0 then return c end
    end
    return pool[#pool]
  end
end

function M.first()
  return function(_, choices) return forward(choices)[1] end
end

-- ---------------------------------------------------------------- hand-written policy
-- Scores every choice in points with ai.value and takes the best (ties broken by the
-- seeded RNG). The bootstrap for the network (docs/AI_OPPONENT.md §4a) and its fallback.

local value = require("ai.value")
local choices_mod = require("ai.choices")

local function panel_id(player)
  local xml = active_panels and active_panels[player.color]
  return xml and xml:match('id="(%a+)')
end

local function card_label(label)
  return label:match(": (.+)$") or label
end

local function placement_value(player, choice)
  local state = tile_placements and tile_placements[player.color]
  local opts = (state and state.opts) or (player.pending_building and player.pending_building.opts) or {}
  local v = 0
  -- the map rewards under the tile (Board:previewReward: tags like "x_token", "2 money")
  local ok, reward = pcall(function() return player.map:previewReward(choice.cells, opts) end)
  if ok and type(reward) == "table" then
    for _, tag in ipairs(reward.tags or {}) do v = v + value.reward(tostring(tag), player) end
    if reward.clearedBoard then v = v + 5 end
  end
  return v
end

local function enclosure_value(player, choice)
  local id = tonumber(choice.label:match("(%d+)$") or "")
  local tile = id and player.map.tiles[id]
  if tile == nil then return 0 end
  -- the smallest enclosure that fits, so the big ones stay free for big animals
  return -#tile.cells * 0.3
end

local function selection_value(player, card_value)
  local state = selection_panels and selection_panels[player.color]
  local action = state and state.action or ""
  if action:find("discard", 1, true) or action == "sell" then return -card_value end
  return card_value
end

function M.score(player, c)
  if c.tag == "back" then return -50 end
  local panel = panel_id(player)
  if c.kind == "click" then
    if c.handler == "on_action_card_button_clicked" then
      local strength = choices_mod.strength(player, c) or 1
      local v = value.action(c.label:match("^(%a+)") or c.label, strength, player)
      -- a venom fee is due: using the poisoned card settles it
      local slot = tonumber((c.arg or ""):match("_(%d+)$") or "")
      if player.venom_unpaid and slot and action_card_has_token(player, slot, "venom") then
        v = v + 1.5
      end
      return v
    end
    if c.handler == "on_take_x_token_clicked" then return 0.9 end
    -- the venom fee is due at the end of the turn and cannot be paid without 2 money (a
    -- dead end in the mod): pay it as soon as it is offered
    if (c.label or ""):find("Venom Fee", 1, true) then return 40 end
    -- the -1 condition / -3 conditions toggles: on when the chosen animal needs them
    if c.handler == "on_animal_discount_clicked" or c.handler == "on_animal_condition_token_clicked" then
      local state = animal_actions and animal_actions[player.color]
      if state and state.selected and not choices_mod.animal_playable(player, state, state.selected, false) then
        return 40
      end
      return -5
    end
    if c.handler == "on_x_token_spin_clicked" then return -1 end
    if c.handler and c.handler:find("spin", 1, true) then return 0 end
    if c.tag == "confirm" then return 30 end
    if c.tag == "pass" then return 0 end
    if panel == "incomePanel" or (c.handler or ""):find("income", 1, true) then return 5 end
    return value.reward(c.label, player)
  elseif c.kind == "pick_up" then
    local label = c.label
    local name = card_label(label)
    if label:find("^play animal") then
      -- (only playable animals are offered, ai.choices); display cards cost their slot
      local state = animal_actions and animal_actions[player.color]
      local pos = state and c.obj and state.offers[c.obj.getGUID()]
      return 10 + value.card(name, player) - (pos or 0) * value.money()
    elseif label:find("^select") then
      return selection_value(player, value.card(name, player))
    elseif label:find("^take from the deck") then
      return 1
    end
    return value.card(name, player)
  elseif c.kind == "drop_tile" then
    return placement_value(player, c)
  elseif c.kind == "pick_up_tile" then
    return enclosure_value(player, c)
  end
  return 0
end

-- { choice, score, heuristic } for every choice but Back (unless Back is all there is)
local function scored(player, choices)
  local out = {}
  for _, c in ipairs(forward(choices)) do
    local ok, s = pcall(M.score, player, c)
    s = (ok and type(s) == "number") and s or 0
    out[#out + 1] = { choice = c, score = s, heuristic = s }
  end
  return out
end

function M.heuristic(r)
  return M.budgeted(r, 0)
end

-- the network's scores (Q: expected change of the margin, in points); the hand-written
-- score is one of its inputs. Falls back to the hand-written scores without weights.
local features = require("ai.features")
local net = require("ai.net")

-- set by the driver while the policy runs in its coroutine: the network's scoring then
-- yields every YIELD_EVERY choices, so a big decision is spread over several frames
M.yielding = false
M.YIELD_EVERY = 8

local function q_scored(player, choices)
  local list = scored(player, choices)
  if not net.available() or #list < 2 then return list end
  local state = features.state(player)
  for i, e in ipairs(list) do
    if M.yielding and i % M.YIELD_EVERY == 0 then coroutine.yield() end
    local x = {}
    for i, v in ipairs(state) do x[i] = v end
    for _, v in ipairs(features.choice(player, e.choice, e.heuristic)) do x[#x + 1] = v end
    -- Back stays last whatever the network says (it never ends a turn by itself)
    e.score = (e.choice.tag == "back") and -1000 or net.forward(x)
  end
  return list
end
M.q_scored = q_scored

-- the best choice, or (budget > 0) a seeded random one among those within `budget` points
-- of the best: a level that gives up points where choices are close.
-- opts.network: score with the network (when trained), else the hand-written scores
function M.budgeted(r, budget, opts)
  return function(player, choices)
    local list = (opts and opts.network) and q_scored(player, choices) or scored(player, choices)
    local best
    for _, e in ipairs(list) do
      if best == nil or e.score > best then best = e.score end
    end
    local near = {}
    for _, e in ipairs(list) do
      if e.score >= best - (budget or 0) - 1e-9 then near[#near + 1] = e end
    end
    local pick = near[math.floor(rng.next(r) * #near) + 1]
    if M.on_decision then M.on_decision(player, list, pick) end    -- training logs
    return pick.choice
  end
end

return M
