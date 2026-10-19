-- ARNO 3.0 for "Ark Nova - Complete Scripted" (Tabletop Simulator).
-- Port of brdgm/ark-nova-solo-helper (c) Stefan Seifert, Apache License 2.0.
-- ARNO solo mode designed by Andre K. See NOTICE. Modified: ported to Lua (MoonSharp).
--
-- The actions of the active card. Port of src/services/BotActions.ts.

local rng = require("core.rng")
local cards_data = require("core.cards_data")
local card_slots = require("core.card_slots")

local M = {}

local CARDS = {}
for _, card in ipairs(cards_data) do CARDS[card.name] = card end

function M.card(name)
  local card = CARDS[name]
  if card == nil then error("Unknown ARNO card: " .. tostring(name)) end
  return card
end

-- TypeScript truthiness of an optional numeric filter: undefined and 0 mean "no filter".
local function no_filter(value)
  return value == nil or value == 0
end

local function to_bot_action(action, slot, tokens_scoring)
  -- special case: if there are already 6 tokens on the scoring card, take 2 conservation instead
  if action.action == "token-scoring-card" and tokens_scoring >= 6 then
    return { action = "conservation", amount = 2 }
  end
  local amount = 0
  if action.amount then amount = amount + action.amount end
  if action.slot_amount then amount = amount + slot end
  return { action = action.action, amount = amount }
end

-- BotActions.getActions(difficultyLevel, fallback?)
-- `action.fallback == fallback`: with fallback undefined only entries without the flag
-- match; with fallback true only flagged entries match.
local function get_actions(card, upgraded, level, slot, tokens_scoring, fallback)
  local list = upgraded and card.upgraded or card.standard
  local out = {}
  for _, action in ipairs(list) do
    local fallback_matches
    if fallback then fallback_matches = action.fallback == true
    else fallback_matches = action.fallback == nil end
    if (no_filter(action.slot_filter) or action.slot_filter == slot)
        and (no_filter(action.level_filter) or action.level_filter == level)
        and fallback_matches then
      out[#out + 1] = to_bot_action(action, slot, tokens_scoring)
    end
  end
  return out
end

local function amount_sum(actions, name)
  local sum = 0
  for _, a in ipairs(actions) do
    if a.action == name then sum = sum + a.amount end
  end
  return sum
end

-- BotActions.newWithSlot(cardSlots, difficultyLevel, slotNumber, tokenScoringCardCount)
function M.with_slot(cs, level, slot, tokens_scoring)
  local name = card_slots.get(cs, slot)
  local card = M.card(name)
  local upgraded = card_slots.is_upgraded(cs, name)
  local actions = get_actions(card, upgraded, level, slot, tokens_scoring, nil)
  local fallback = get_actions(card, upgraded, level, slot, tokens_scoring, true)
  return {
    card = name,
    upgraded = upgraded,
    slot = slot,
    actions = actions,
    fallback = fallback,
    has_fallback = #fallback > 0,
    token_scoring = amount_sum(actions, "token-scoring-card"),
    token_notepad = amount_sum(actions, "token-notepad"),
    appeal = amount_sum(actions, "appeal"),
  }
end

-- BotActions.determineRandomSlot(): same probability for slots 2..5
function M.random_slot(r)
  return rng.dice(r, 4) + 1
end

return M
