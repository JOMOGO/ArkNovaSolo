-- Static check on the BUILT Global.lua: every reward text in the mod's data reaches a
-- function that exists. Catches a reward with no handler (like "reef effect" before FIX138)
-- without playing the card. Sources: every card (rewards, hooks, reef effect, income,
-- project slot awards), every map's project / partner zoo / university / worker rewards,
-- universities, the 2-CP bonus, the reputation track and the bonus tiles; with interactive
-- effects on and off.
local T = require("tests.lib")

local p = sim.human_game()
p.okapi_stable = { "cube" }          -- so "okapi stable marketing" reads as the "marketing" it pays

-- the function apply_reward_string (~5636) ends up calling for reward r, or nil when it
-- is settled, absorbed or a TOKEN: (handled before the name lookup)
local function handler_names(r, out)
  r = effective_reward(r)
  local first_half, second_half = split_combined_reward(r)
  if first_half ~= nil then
    handler_names(first_half, out); handler_names(second_half, out)
    return out
  end
  local prefix, rest = split_reward_prefix(r)
  if prefix == "BONUS: " then return handler_names(rest, out) end
  if prefix == "TOKEN: " or is_absorbed_reward(r) then return out end
  local settled = settled_reward_string(p, r)
  if settled ~= nil and settled ~= r then return handler_names(settled, out) end

  local parts = split(r)
  local first, last = parts[1], parts[#parts]
  if tonumber(last) then out[#out + 1] = (r:sub(1, #r - #last - 1):gsub(" ", "_"))
  elseif tonumber(first) then out[#out + 1] = "update_" .. (r:sub(#first + 2):gsub(" ", "_"))
  elseif first == "free" then out[#out + 1] = "free_building"
  elseif last == "magnet" then out[#out + 1] = "magnet"
  elseif first == "search" then out[#out + 1] = "search"
  else out[#out + 1] = (r:gsub(" ", "_")) end
  return out
end

local rewards = {}   -- reward text -> where it was found
local function add(r, where)
  if type(r) == "string" and r ~= "" and rewards[r] == nil then rewards[r] = where end
end

-- a card's rewards table: { "1 rep", ... } or { research = { "2 money", ... } }; numbered
-- entries go through reward_string_from_key as append_reward_claims does them
local function add_card_rewards(list, where)
  for key, value in pairs(list or {}) do
    if type(key) == "number" then
      add(reward_string_from_key(p, key, value), where)
    elseif type(value) == "table" then
      for _, r in ipairs(value) do add(r, where) end
    else
      add(value, where)
    end
  end
end

for _, set in ipairs({ "base", "mw" }) do
  for n, card in pairs(sim.cnsts.cards[set]) do
    local where = set .. " #" .. n
    add_card_rewards(card.rewards, where)
    for _, hooks in ipairs({ card.hook_self or {}, card.hook_all or {} }) do
      for _, r in pairs(hooks) do add_card_rewards({ r }, where .. " hook") end
    end
    add(card.reef, where .. " reef")
    if type(card.income) == "string" then add(card.income, where .. " income") end
    if card.type == "project" then
      for slot = 1, 3 do add_card_rewards(project_slot_awards(p, card, slot), where .. " slot " .. slot) end
    end
  end
end
for key, map in pairs(sim.cnsts.map_data) do
  for i, entry in ipairs(map.project_rewards or {}) do add(entry[1], key .. " project bonus " .. i) end
  for _, field in ipairs({ "partner_zoo_rewards", "university_rewards", "worker_rewards" }) do
    for _, list in ipairs(map[field] or {}) do
      for _, r in ipairs(list) do add(r, key .. " " .. field) end
    end
  end
end
for key, university in pairs(sim.cnsts.universities) do
  for _, r in ipairs(university.rewards or {}) do add(r, "university " .. key) end
end
for _, r in ipairs(sim.cnsts.cp_bonus_2) do add(r, "2-CP bonus") end
for i, r in ipairs(sim.cnsts.rep_rewards) do add(r, "reputation " .. i) end
for guid, r in pairs(sim.cnsts.bonus_tile_mapping) do add(r, "bonus tile " .. guid) end

T.test("the data holds a few hundred reward texts", function()
  local n = 0
  for _ in pairs(rewards) do n = n + 1 end
  T.ok(n > 150, "found " .. n)
end)

for _, interactive in ipairs({ true, false }) do
  T.test("every reward text has a handler (interactive effects " .. (interactive and "on" or "off") .. ")", function()
    interactive_effects = interactive
    local missing = {}
    for r, where in pairs(rewards) do
      for _, name in ipairs(handler_names(r, {})) do
        if type(_G[name]) ~= "function" then
          missing[#missing + 1] = string.format("%q (%s) calls %s, which does not exist", r, where, name)
        end
      end
    end
    table.sort(missing)
    T.eq(missing, {})
  end)
end

T.finish("integration rewards")
