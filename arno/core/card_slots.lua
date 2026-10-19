-- ARNO 3.0 for "Ark Nova - Complete Scripted" (Tabletop Simulator).
-- Port of brdgm/ark-nova-solo-helper (c) Stefan Seifert, Apache License 2.0.
-- ARNO solo mode designed by Andre K. See NOTICE. Modified: ported to Lua (MoonSharp).
--
-- ARNO's five action cards in slots 1..5 plus the set of upgraded cards.
-- Port of src/services/CardSlots.ts. A card-slots value is the plain table
-- { slots = {card names}, upgraded = {card names} }, which is also its persistence.

local rng = require("core.rng")
local cards_data = require("core.cards_data")

local M = {}

M.MAX_UPGRADES = 3

local function contains(list, value)
  for _, v in ipairs(list) do
    if v == value then return true end
  end
  return false
end

function M.copy(cs)
  local slots, upgraded = {}, {}
  for i, v in ipairs(cs.slots) do slots[i] = v end
  for i, v in ipairs(cs.upgraded) do upgraded[i] = v end
  return { slots = slots, upgraded = upgraded }
end

-- CardSlots.get(slot), 1-based
function M.get(cs, slot)
  if slot < 1 or slot > #cs.slots then
    error("Invalid slot number: " .. tostring(slot))
  end
  return cs.slots[slot]
end

function M.is_upgraded(cs, name)
  return contains(cs.upgraded, name)
end

function M.upgrade(cs, name)
  if M.is_upgraded(cs, name) then error("Card is already upgraded: " .. name) end
  cs.upgraded[#cs.upgraded + 1] = name
end

function M.revert_upgrade(cs, name)
  if not M.is_upgraded(cs, name) then error("Card is not upgraded: " .. name) end
  local kept = {}
  for _, v in ipairs(cs.upgraded) do
    if v ~= name then kept[#kept + 1] = v end
  end
  cs.upgraded = kept
end

-- ARNO can upgrade max. 3 cards.
function M.can_upgrade(cs)
  return #cs.upgraded < M.MAX_UPGRADES
end

function M.can_revert_upgrade(cs)
  return #cs.upgraded > 0
end

-- Move card to first position after usage.
function M.move_first(cs, name)
  local slots = { name }
  for _, v in ipairs(cs.slots) do
    if v ~= name then slots[#slots + 1] = v end
  end
  cs.slots = slots
end

-- CardSlots.new(): ANIMALS first, the other cards shuffled (lodash.shuffle).
function M.new(r)
  local others = {}
  for _, card in ipairs(cards_data) do
    if card.name ~= "animals" then others[#others + 1] = card.name end
  end
  local slots = { "animals" }
  for _, name in ipairs(rng.shuffle(r, others)) do slots[#slots + 1] = name end
  return { slots = slots, upgraded = {} }
end

return M
