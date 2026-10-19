-- Differential test: the Lua core must reproduce build/harness/ts_reference.json, which the
-- ORIGINAL helper TypeScript produced under the same seeded PRNG (tests/harness).
-- REF is injected by tools/run_tests.py as a Lua table literal.
local T = require("tests.lib")
local rng = require("core.rng")
local cards_data = require("core.cards_data")
local card_slots = require("core.card_slots")
local bot_actions = require("core.bot_actions")
local tracker = require("core.project_tracker")
local decide = require("core.decide")
local REF = require("tests.ref")

local function strip_actions(list)
  local out = {}
  for i, a in ipairs(list or {}) do out[i] = { action = a.action, amount = a.amount } end
  return out
end

T.test("rng known answers", function()
  for _, case in ipairs(REF.rng) do
    local r = rng.new(case.seed)
    for i, expected in ipairs(case.values) do
      T.eq(rng.next(r), expected, "seed " .. case.seed .. " value " .. i)
    end
  end
end)

T.test("enums match", function()
  T.eq(decide.ANIMAL_TYPES, REF.enums.animalType)
  local names = {}
  for i, c in ipairs(cards_data) do names[i] = c.name end
  T.eq(names, { "animals", "association", "sponsors", "build", "cards" })
end)

T.test("BotActions exhaustive (2400 cases)", function()
  local n = 0
  for _, case in ipairs(REF.botActions) do
    local others = {}
    for _, c in ipairs(cards_data) do
      if c.name ~= case.card then others[#others + 1] = c.name end
    end
    local slots = {}
    for i = 1, case.slot - 1 do slots[#slots + 1] = others[i] end
    slots[#slots + 1] = case.card
    for i = case.slot, #others do slots[#slots + 1] = others[i] end
    while #slots > 5 do table.remove(slots) end
    local cs = { slots = slots, upgraded = case.upgraded and { case.card } or {} }
    local ba = bot_actions.with_slot(cs, case.level, case.slot, case.tokens)
    local label = string.format("%s up=%s slot=%d level=%d tokens=%d", case.card,
      tostring(case.upgraded), case.slot, case.level, case.tokens)
    T.eq(ba.actions, strip_actions(case.actions), label .. " actions")
    T.eq(ba.fallback, strip_actions(case.fallback), label .. " fallback")
    T.eq(ba.token_scoring, case.tokenScoring, label)
    T.eq(ba.token_notepad, case.tokenNotepad, label)
    T.eq(ba.appeal, case.appeal, label)
    n = n + 1
  end
  T.eq(n, 2400)
end)

T.test("ProjectModuleTracker 0..89 discards", function()
  for _, case in ipairs(REF.tracker) do
    local pos = tracker.position(case.discards)
    T.eq(pos, case.position, "position " .. case.discards)
    T.eq(tracker.slot(pos), case.slot, "slot " .. case.discards)
    T.eq(tracker.kiosk_count(pos), case.kiosk, "kiosk " .. case.discards)
    T.eq(tracker.preferred_slots(pos), case.preferred, "preferred " .. case.discards)
  end
end)

T.test("CardSlots.new shuffle (200 seeds)", function()
  for _, case in ipairs(REF.newSlots) do
    T.eq(card_slots.new(rng.new(case.seed)).slots, case.slots, "seed " .. case.seed)
  end
end)

T.test("whole games via NavigationState (300 games)", function()
  local turns = 0
  for _, game in ipairs(REF.games) do
    local upgrade_after = {}
    for _, t in ipairs(game.upgradeAfter) do upgrade_after[t] = true end
    local bot = decide.new_bot(game.level)
    local r = rng.new(game.seed)
    for t, expected in ipairs(game.turns) do
      local label = "seed " .. game.seed .. " turn " .. t
      local rec = decide.turn(bot, r)
      T.eq(rec.slots.slots, expected.slots, label .. " slots")
      T.eq(rec.slots.upgraded, expected.upgradedAtDraw, label .. " upgraded at draw")
      T.eq(bot.last_slot, expected.slot, label .. " slot")
      T.eq(bot.tokens_scoring, expected.tokenScoring, label .. " scoring tokens")
      T.eq(bot.tokens_notepad, expected.tokenNotepad, label .. " notepad tokens")
      if upgrade_after[t] then
        T.eq(decide.upgrade(bot, r), expected.upgraded, label .. " upgrade")
      end
      turns = turns + 1
    end
  end
  T.ok(turns > 3000, "covered " .. turns .. " turns")
end)

T.test("component dice (400 seeds)", function()
  for _, c in ipairs(REF.dice) do
    local label = "seed " .. c.seed
    local r = rng.new(c.seed)
    local project = decide.pick_project(r, c.hand, c.noToken, c.available)
    T.eq(project, c.project, label .. " project")
    T.eq(decide.display_position(r), c.takeCard, label .. " takeCard")
    local zoo = decide.partner_zoo_roll(r)
    T.eq(zoo, c.zoo, label .. " zoo")
    local zoo2 = decide.partner_zoo_roll(r, { zoo })
    T.eq(zoo2, c.zooReroll, label .. " zoo reroll")
    T.eq(decide.partner_zoo_roll(r, { zoo, zoo2 }), c.zooReroll2, label .. " zoo reroll 2")
    local uni = decide.university_roll(r, c.universityCount)
    T.eq(uni, c.university, label .. " university")
    T.eq(decide.university_roll(r, c.universityCount, { uni }), c.universityReroll, label .. " university reroll")
    local animal = decide.animal_type_roll(r)
    T.eq(animal, c.animal, label .. " animal")
    T.eq(decide.animal_type_roll(r, { animal }), c.animalReroll, label .. " animal reroll")
    T.eq(decide.zoo_or_university_roll(r), c.zooOrUniversity, label .. " zoo or university")
    T.eq(decide.bonus_tile_roll(r), c.bonusTile, label .. " bonus tile")
  end
end)

T.finish("differential")
