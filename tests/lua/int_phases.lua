-- Integration tests on the BUILT Global.lua for ARNO outside his own turns:
-- setup cards (rules p3), break draw (p4), final scoring (p10), ties (p10), interactive
-- targeting (p2), hand waits (H16) and the setup panel rows (H1).
local T = require("tests.lib")

local function base()
  local p, bot = sim.setup_game()
  sim.record("report_discard")
  sim.record("add_remove_icons")
  sim.record("apply_hooks")
  return p, bot
end

T.test("setup: keeps the first 2 project cards, discards the rest, 1 scoring card (rules p3)", function()
  local p, bot = base()
  zoo_deck = sim.deck({ 101, 401, 102, 103, 228, 405, 104, 230 })
  final_scoring_deck = sim.deck({ 1, 2, 3 })
  local zone = getObjectFromGUID(cnsts.discard_pile_zone)
  local called = false
  require("adapter.apply").deal_bot_setup_cards({ p }, function() called = true end)
  T.ok(called)
  T.eq(#bot.mat_projects, 2)
  T.eq(getObjectFromGUID(bot.mat_projects[1]).getName():sub(2, 4), "101")
  T.eq(getObjectFromGUID(bot.mat_projects[2]).getName():sub(2, 4), "102")
  T.eq(bot.setup_discards, 6)
  T.eq(bot.sponsor_discards, 2, "228 and 230 are sponsors")
  T.eq(ARNO.setup.expected_discards(players), 4 + 6, "4 per human + ARNO's 6")
  T.ok(bot.scoring_card ~= nil)
end)

T.test("setup discards join the humans' pile even before it is in the zone (H8)", function()
  local p, bot = base()
  zoo_deck = sim.deck({ 401, 402, 403, 404, 405, 406, 407, 408 })
  final_scoring_deck = sim.deck({ 1, 2 })
  local humans_pile = sim.deck({ 201, 202, 203, 204 })
  arno_last_discard_pile = nil
  discard_cards_to_new_pile(players[1], {}, humans_pile)   -- the mod's call, captured by H8
  require("adapter.apply").deal_bot_setup_cards({ p }, function() end)
  T.eq(humans_pile.getQuantity(), 4 + 8, "all of ARNO's 8 animals went onto the same pile")
  arno_last_discard_pile = nil
end)

T.test("leftover action-card decks: ARNO's empty zone is skipped (H6, found in play)", function()
  base()
  local decks = {}
  for _, set in pairs(cnsts.action_card_init_zones) do
    for color, guid in pairs(set) do
      local zone = sim.fake("zone " .. color, nil, guid)
      if color ~= "Yellow" then
        local deck = sim.fake("deck " .. color); deck.tag = "Deck"
        decks[#decks + 1] = deck.getGUID()
        zone.getObjects = function() return { deck } end
      else
        zone.getObjects = function() return {} end   -- ARNO's cards were already dealt
      end
    end
  end
  destruct_action_card_decks()
  for _, guid in ipairs(decks) do T.eq(sim.objects[guid], nil, "deck destroyed") end
end)

T.test("human hand waits through the H16 wrappers return a single boolean (found in play)", function()
  base()
  Player = setmetatable({}, { __index = function() return { getHandObjects = function() return {} end } end })
  local fired = false
  wait_for_cards_out_of_hand(players[1], 1, { sim.fake("discarded card") }, function() fired = true end)
  sim.pump()
  T.ok(fired)
end)

T.test("two ARNOs are prepared one after another (kiosk template is async, found in play)", function()
  local p = base()
  local second = sim.make_player("Blue", true)
  second.steam_name = "ARNO 2"
  table.insert(players, second)
  arno_state.bots.Blue = { name = "ARNO 2", level = 2, extra_cp = 0, mat_projects = {} }
  arno_state.order[#arno_state.order + 1] = "Blue"
  building_parents = {}
  local kiosks_in_bag, order = 1, {}
  local real_prepare = ARNO.setup.prepare_bot
  ARNO.setup.prepare_bot = function(player)       -- emulates building_clone_source (4654)
    if building_parents["KIOSK"] == nil then
      if kiosks_in_bag == 0 then error("no KIOSK in the building bag to clone") end
      kiosks_in_bag = 0
      Wait.frames(function() building_parents["KIOSK"] = "kiosk-template" end, 1)
    end
    order[#order + 1] = player.color
  end
  sim.record("count_player_maps", function() return 0 end)
  sim.record("show_map_setup_panel")
  setup_player_maps()
  sim.pump()
  ARNO.setup.prepare_bot = real_prepare
  ARNO.setup.close_window()
  T.eq(order, { "Yellow", "Blue" })
  T.eq(#sim.calls.show_map_setup_panel, 1, "the humans' map setup continued")
end)

T.test("Marine Worlds: ARNO's drafting box is removed in his setup (found in play)", function()
  local p = base()
  marine_worlds_enabled = true
  sim.record("apply_map_choice")
  sim.record("deal_action_cards")
  local box = sim.fake("drafting box", nil, cnsts.drafting_boxes.Yellow)
  ARNO.setup.prepare_bot(p)
  T.eq(sim.objects[cnsts.drafting_boxes.Yellow], nil, "box destroyed")
  T.eq(sim.calls.deal_action_cards[1][2], cnsts.action_card_init_zones.mw.Yellow, "his regular cards from his own zone")
  T.eq(arno_state.bots.Yellow.cp_debt, 3, "-3 CP with the new action cards (rules p9)")
  marine_worlds_enabled = false
end)

local ORDER = { "animals_g", "animals_r", "association", "build_g", "sponsors", "cards_g", "cards_r", "build_r" }
local function fake_images()
  return { face = "sheet_1.jpg", back = "sheet_2.jpg", width = 4, height = 2, order = ORDER }
end

-- the card's image (from its position on the sheet), its deck entry and its data
local function face_of(p, slot)
  local data = getObjectFromGUID(p.action_cards[slot].guid)._s.data
  if data == nil then return nil end
  local id, deck = next(data.CustomDeck)
  return ORDER[data.CardID - tonumber(id) * 100 + 1], deck, data
end

T.test("setup: ARNO's action cards are the real ARNO cards, green up to level 3 (owner request)", function()
  local p, bot = base()
  bot.level = 3
  sim.record("apply_map_choice")
  sim.record("deal_action_cards")
  ARNO_CARD_IMAGES = fake_images()
  local old = p.action_cards[1].guid
  getObjectFromGUID(old).addTag("action_card")
  ARNO.setup.prepare_bot(p)
  T.eq(sim.objects[old], nil, "the mod's card is gone")
  local faces = {}
  for slot = 1, 5 do faces[slot] = (face_of(p, slot)) end
  T.eq(faces, { "animals_g", "cards_g", "build_g", "sponsors", "association" })
  local _, deck, data = face_of(p, 1)
  T.eq({ deck.FaceURL, deck.BackURL, deck.NumWidth, deck.NumHeight, deck.UniqueBack },
       { "sheet_1.jpg", "sheet_2.jpg", 4, 2, true }, "side II sheet on the back, per card")
  T.eq(data.Nickname, "ANIMALS 0", "same name: the mod finds it by name")
  T.ok(getObjectFromGUID(p.action_cards[1].guid).hasTag("action_card"), "same tags")
  T.ok(tonumber((next(data.CustomDeck))) > 2537, "deck id above the base save's")
  T.eq(action_card_slot_named(p, "BUILD"), 3)
  ARNO_CARD_IMAGES = nil
end)

T.test("setup: red ARNO cards from level 4 (and L7+)", function()
  for _, level in ipairs({ 4, 9 }) do
    local p, bot = base()
    bot.level = level
    sim.record("apply_map_choice")
    sim.record("deal_action_cards")
    ARNO_CARD_IMAGES = fake_images()
    ARNO.setup.prepare_bot(p)
    T.eq((face_of(p, 1)), "animals_r")
    T.eq((face_of(p, 2)), "cards_r")
    T.eq((face_of(p, 4)), "sponsors")
    ARNO_CARD_IMAGES = nil
  end
end)

T.test("setup: without card images ARNO keeps the mod's cards", function()
  local p = base()
  sim.record("apply_map_choice")
  sim.record("deal_action_cards")
  local old = p.action_cards[1].guid
  ARNO.setup.prepare_bot(p)
  T.eq(p.action_cards[1].guid, old)
end)

T.test("break draw: first project kept, first animal on mat, rest discarded (rules p4)", function()
  local p, bot = base()
  zoo_deck = sim.deck({ 208, 401, 101, 402 })
  discard_pile = sim.deck({})
  local done = false
  require("adapter.apply").break_draw(p, function() done = true end)
  sim.pump()
  T.ok(done)
  T.eq(#bot.mat_projects, 1)
  T.eq(#bot.mat_animals, 1)
  T.eq(#p.played_animals, 1)
  T.eq(discard_pile.getQuantity(), 1, "the sponsor; 402 stays in the deck (only 3 drawn)")
  T.eq(bot.sponsor_discards, 1)
  T.eq(#sim.calls.add_remove_icons, 1, "animal icons fire human hooks")
  T.eq(#sim.calls.apply_hooks, 1, "discarded sponsor may trigger human effects (R18)")
end)

T.test("final scoring: CP from tokens, debt paid first (rules p10)", function()
  local p, bot = base()
  bot.tokens_scoring, bot.tokens_notepad, bot.cp_debt = 5, 2, 1
  set_counter(p.cp_counter, 3, cnsts.counter_style.cp)
  score_final_scoring_cards(p)
  T.eq(get_counter_value(p.cp_counter), 3 + (3 + 2 - 1))
  T.eq(bot.cp_debt, 0)
end)

T.test("ARNO wins ties against humans (rules p10)", function()
  local p = base()
  local human = players[1]
  set_counter(human.score_counter, 50, cnsts.counter_style.score)
  set_counter(p.score_counter, 50, cnsts.counter_style.score)
  sim.record("projects_supported", function(_, pl) return pl.is_arno and 0 or 3 end)
  local w = game_winners()
  T.eq(#w, 1); T.eq(w[1].color, "Yellow")
  set_counter(human.score_counter, 51, cnsts.counter_style.score)
  w = game_winners()
  T.eq(#w, 1); T.eq(w[1].color, "Red")
end)

T.test("ARNO is never the target of an interactive effect (rules p2)", function()
  local p = base()
  T.eq(targetable(p), false)
end)

T.test("hand waits ignore ARNO (H16)", function()
  base()
  local fired = false
  local hands = { Red = 2 }
  Player = setmetatable({}, { __index = function(_, color)
    return { getHandObjects = function() local t = {} for i = 1, (hands[color] or 0) do t[i] = i end return t end }
  end })
  wait_for_all_hand_counts(1, 2, function() fired = true end)
  sim.pump()
  T.ok(fired, "only the human's hand is counted")
end)

T.test("setup panel shows ARNO rows for unseated colours (H1)", function()
  base()
  seated_game_players = function() return { { color = "Red" } } end
  setup_options = {}
  for _, option in ipairs(cnsts.setup_options) do setup_options[option.key] = 1 end
  local xml = game_setup_panel_xml()
  T.ok(xml:find("on_arno_setup_clicked(Yellow)", 1, true) ~= nil)
  T.ok(xml:find("on_arno_setup_clicked(Red)", 1, true) == nil, "seated colour has no ARNO row")
  T.ok(xml:find("setupProceedButton", 1, true) ~= nil)
end)

T.finish("integration phases")
