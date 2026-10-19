-- ARNO 3.0 for "Ark Nova - Complete Scripted" (Tabletop Simulator).
-- Port of brdgm/ark-nova-solo-helper (c) Stefan Seifert, Apache License 2.0.
-- ARNO solo mode designed by Andre K. See NOTICE. Modified: ported to Lua (MoonSharp).
--
-- ARNO's per-turn draw and the dice that the helper rolls in its Vue components.
-- Pure: bot state + rng in, records out. No TTS or mod access.
--   turn        <- util/NavigationState.ts getBotRound()
--   upgrade     <- components/round/ActionCards.vue:99-105 upgradeCard()
--   pick_project<- components/round/PickConservationProject.vue:130-152
--   other dice  <- BotActions.vue:130, GainPartnerZoo.vue:27/31-33,
--                  GainPartnerUniversity.vue:39-40/50-55, GainPartnerZooOrUniversity.vue:49-51,
--                  BonusTile.vue:82-84, FinalScoring.vue getBotConservationPoints()

local rng = require("core.rng")
local card_slots = require("core.card_slots")
local bot_actions = require("core.bot_actions")

local M = {}

M.PARTNER_ZOOS = { "america", "europe", "asia", "africa", "australia" }       -- GainPartnerZoo.vue
M.UNIVERSITIES = { "cards-reputation", "science", "science-reputation", "science-animal" } -- GainPartnerUniversity.vue
M.ANIMAL_TYPES = { "bird", "herbivore", "predator", "primate", "reptile", "sea" } -- enum/AnimalType.ts order

-- A fresh bot. Card slots are created lazily on the first turn, like the helper.
function M.new_bot(level)
  return {
    level = level,
    card_slots = nil,
    last_slot = nil,
    tokens_scoring = 0,
    tokens_notepad = 0,
    turns = 0,
  }
end

-- One ARNO turn draw. Mutates bot; returns the BotActions record of the active card.
function M.turn(bot, r)
  local cs
  if bot.card_slots == nil then
    cs = card_slots.new(r)                                        -- start new game
  else
    cs = card_slots.copy(bot.card_slots)                          -- continue with cards from previous round
    card_slots.move_first(cs, card_slots.get(cs, bot.last_slot))  -- move previous card to first position
  end
  local slot = bot_actions.random_slot(r)
  local record = bot_actions.with_slot(cs, bot.level, slot, bot.tokens_scoring)
  bot.card_slots = cs
  bot.last_slot = slot
  bot.tokens_scoring = bot.tokens_scoring + record.token_scoring
  bot.tokens_notepad = bot.tokens_notepad + record.token_notepad
  bot.turns = bot.turns + 1
  record.slots = card_slots.copy(cs)
  return record
end

-- ActionCards.vue upgradeCard(): a random standard card (in slot order) is upgraded.
-- Returns the card name, or nil when ARNO already has 3 upgrades.
function M.upgrade(bot, r)
  if bot.card_slots == nil then bot.card_slots = card_slots.new(r) end
  local cs = bot.card_slots
  if not card_slots.can_upgrade(cs) then return nil end
  local standard = {}
  for _, name in ipairs(cs.slots) do
    if not card_slots.is_upgraded(cs, name) then standard[#standard + 1] = name end
  end
  local name = standard[rng.dice(r, #standard)]
  card_slots.upgrade(cs, name)
  return name
end

-- PickConservationProject.vue pickConservationProject(). Note the d2 is always rolled.
-- Returns { source = "mat" | "no_token" | "available" | "none", number = n }.
function M.pick_project(r, from_hand, from_board_no_token, from_board_available)
  local prefer_from_hand = rng.dice(r, 2) == 1
  if from_hand >= 2 or (from_hand == 1 and prefer_from_hand)
      or (from_hand == 1 and from_board_no_token == 0 and from_board_available == 0) then
    return { source = "mat", number = rng.dice(r, from_hand) }
  end
  if from_board_no_token > 0 then
    return { source = "no_token", number = rng.dice(r, from_board_no_token) }
  end
  if from_board_available > 0 then
    return { source = "available", number = rng.dice(r, from_board_available) }
  end
  return { source = "none", number = 0 }
end

-- BotActions.vue:130 takeCardRandomNumber
function M.display_position(r)
  return rng.dice(r, 6)
end

-- GainPartnerZoo.vue: first roll, then rerolls that exclude the given values.
function M.partner_zoo_roll(r, exclude)
  if exclude == nil or #exclude == 0 then return rng.dice(r, 5) end
  return rng.dice_different(r, 5, exclude)
end

-- GainPartnerUniversity.vue: 3 universities, 4 with Marine Worlds.
function M.university_roll(r, count, exclude)
  if exclude == nil or #exclude == 0 then return rng.dice(r, count) end
  return rng.dice_different(r, count, exclude)
end

function M.animal_type_roll(r, exclude)
  if exclude == nil or #exclude == 0 then return rng.random_enum(r, M.ANIMAL_TYPES) end
  return rng.random_enum_different(r, M.ANIMAL_TYPES, exclude)
end

-- GainPartnerZooOrUniversity.vue pickRandom(): 1 = partner zoo, 2 = university
function M.zoo_or_university_roll(r)
  return rng.dice(r, 2)
end

-- BonusTile.vue pickBonusTilePosition(): 1 = left, 2 = right
function M.bonus_tile_roll(r)
  return rng.dice(r, 2)
end

-- FinalScoring.vue getBotConservationPoints()
function M.final_cp(bot)
  local scoring = bot.tokens_scoring - 2
  if scoring < 0 then scoring = 0 elseif scoring > 4 then scoring = 4 end
  return scoring + bot.tokens_notepad
end

-- PickConservationProject.vue projectSlotDifficultyLevel
function M.project_slot_for_level(level)
  if level >= 5 then return "left" end
  if level >= 3 then return "middle" end
  return "right"
end

return M
