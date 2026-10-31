-- AI opponent (docs/AI_OPPONENT.md §4): hand-written values, in points of final score.
-- The score the mod keeps is appeal + 2 per CP (3 per CP above 10) (cp_to_score); every
-- value here is an estimate on that scale. Used by the hand-written policy (the bootstrap
-- for the network, §4a) and as its fallback.

local M = {}

-- how far the game is: 0 at the start, 1 when someone reaches the end score
function M.progress()
  local best = -14
  for _, p in ipairs(players or {}) do
    best = math.max(best, get_counter_value(p.score_counter))
  end
  return math.max(0, math.min(1, (best + 14) / (cnsts.game_end_score + 14)))
end

-- one money, one reputation, one CP, in points, at this stage of the game
-- (money is only worth what it buys: an animal gives about 1 appeal per 3 money)
function M.money(progress) return 0.3 - 0.25 * (progress or M.progress()) end
function M.rep(player)
  local rep = get_counter_value(player.rep_counter)
  return rep >= 9 and 0.2 or 0.5
end
-- appeal also raises income (appeal_to_income), worth more early
function M.appeal(progress) return 1 + 0.5 * (1 - (progress or M.progress())) end
function M.cp(player)
  return get_counter_value(player.cp_counter) >= 10 and 3 or 2
end

-- breaks still to come (income), roughly
function M.breaks_left(progress)
  return math.max(0, 4 * (1 - (progress or M.progress())))
end

local KEYWORDS = {        -- rewards without a number, in points
  ["x_token"] = 1.2, ["x-token"] = 1.2, ["draw"] = 0.9, ["snap"] = 1.6, ["clever"] = 1.5,
  ["boost"] = 1.5, ["action"] = 2.5, ["multiplier"] = 2, ["worker"] = 2, ["partner zoo"] = 3,
  ["university"] = 3, ["kiosk"] = 1.5, ["pavilion"] = 1.5, ["enclosure"] = 2, ["build"] = 2,
  ["income"] = 1, ["mark"] = 0.8, ["hunter"] = 1, ["scavenging"] = 0.8, ["sprint"] = 1,
  ["posturing"] = 1.2, ["sunbathing"] = 1, ["pouch"] = 1.5, ["digging"] = 0.8,
  ["perception"] = 1, ["jumping"] = 1, ["inventive"] = 1, ["venom"] = 1, ["pilfering"] = 1.2,
}

-- the value of one reward text ("2 appeal", "1 cp", "3 money", "draw 2", "Build a Kiosk", ...)
function M.reward(text, player)
  if type(text) ~= "string" then return 0 end
  local t = text:lower()
  local n = tonumber(t:match("(%d+)")) or 1
  if t:find("appeal", 1, true) then return n * M.appeal() end
  if t:find("conservation", 1, true) or t:match("%f[%w]cp%f[%W]") then return n * M.cp(player) end
  if t:find("money", 1, true) then
    if t:find("pay", 1, true) or t:find("donate", 1, true) then return -n * M.money() end
    return n * M.money()
  end
  if t:find("rep", 1, true) then return n * M.rep(player) end
  for key, v in pairs(KEYWORDS) do
    if t:find(key, 1, true) then return v * (t:match("%d") and math.min(n, 4) or 1) end
  end
  return 0.5
end

local function rewards_value(list, player)
  local v = 0
  for _, r in ipairs(list or {}) do v = v + M.reward(r, player) end
  return v
end

-- a zoo card's worth to its owner (to play it, or to keep it for later)
function M.card(name, player)
  local ok, data = pcall(card_data_for, name)
  if not ok or data == nil then return 0 end
  local progress = M.progress()
  if data.type == "animal" then
    local v = rewards_value(data.rewards, player) + 0.6 * #(data.icons or {})
    return v - (data.cost or 0) * M.money(progress)
  elseif data.type == "sponsor" then
    local v = 1 + rewards_value(type(data.rewards) == "table" and data.rewards or {}, player)
    if data.income then v = v + M.reward(data.income, player) * M.breaks_left(progress) end
    return v + 0.4 * #(data.icons or {}) - 0.3 * (data.level or 0) * M.money(progress)
  elseif data.type == "project" then
    return 2
  end
  return 0.5
end

-- the best animals this player can play now from hand and display (as the mod checks it)
function M.playable_animals(player)
  local out = {}
  for _, c in ipairs(playable_animal_candidates(player, nil)) do
    if is_animal_playable(c.name, player, c.display_pos) then
      local data = card_data_for(c.name)
      out[#out + 1] = { name = c.name, cost = animal_play_cost(data, player, c.display_pos),
                        value = M.card(c.name, player) - (c.display_pos or 0) * M.money() }
    end
  end
  table.sort(out, function(a, b) return a.value > b.value end)
  return out
end

-- what one action card is worth at a strength, roughly (the best thing it can do now)
function M.action(kind, strength, player)
  local progress = M.progress()
  local mv = M.money(progress)
  kind = kind:upper()
  if kind == "ANIMALS" then
    if not animals_action_available(player, strength, "0") then return -1 end
    local animals = M.playable_animals(player)
    local count = (strength >= (animals_upgraded(player) and 4 or 5)) and 2 or 1
    local v, money = 0, get_counter_value(player.money_counter)
    for i = 1, math.min(count, #animals) do
      if animals[i].cost <= money then
        v, money = v + math.max(0, animals[i].value), money - animals[i].cost
      end
    end
    return v + 0.5
  elseif kind == "SPONSORS" then
    local best = strength * (player.sponsors_flipped and 2 or 1) * mv      -- the money option
    for _, c in ipairs(playable_sponsor_candidates(player, strength)) do
      best = math.max(best, M.card(c.obj.getName(), player))
    end
    return best
  elseif kind == "BUILD" then
    local need = 0
    for _, card in ipairs(player_hand_cards(player)) do
      local data = card_data_for(card.getName())
      if data.type == "animal" and data.size and data.size <= strength
         and not animal_fits_enclosure(data, player) then
        need = math.max(need, 2.5)
      end
    end
    return 0.6 * math.min(strength, 5) + need - 1.5 * progress
  elseif kind == "ASSOCIATION" then
    local by_strength = { 0.5, 2 * M.rep(player), 3, 3, 4 + 2 * progress }
    return by_strength[math.min(strength, 5)] or 0.5
  elseif kind == "CARDS" then
    local draws = player.cards_flipped and { 1, 2, 2, 3, 4 } or { 1, 1, 2, 2, 3 }
    return 0.6 * draws[math.min(strength, 5)] * (1 - 0.6 * progress) + 0.2
  end
  return 0
end

return M
