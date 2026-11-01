-- Base-mod dead-end fixes on the BUILT Global.lua (CHANGES.md §1: FIXBUILD, FIXVENOM,
-- FIXANIMAL, FIXSCAV, FIXPILE). Each was found by the AI opponent's headless games: a state
-- a player could reach and not leave without rewind (or a Lua error).
local T = require("tests.lib")

local function deck_of(name, numbers)
  local deck = sim.fake(name)
  deck.tag = "Deck"
  for _, n in ipairs(numbers) do deck.putObject(sim.fake(string.format("(%03d) card %d", n, n))) end
  return deck
end

-- a player whose map has no room for any building (every free cell taken by a 1-cell tile)
local function fill_map(p)
  local cells = {}
  for _, c in ipairs(p.map:unoccupiedCells()) do cells[#cells + 1] = c end
  for _, c in ipairs(cells) do
    p.map:placeUnchecked({ c }, { type = "filler" }, nil, { ignore_touch_rule = true })
  end
end

-- FIXBUILD -------------------------------------------------------------------------------

T.test("FIXBUILD: BUILD is available with money and room, not with money but no room", function()
  local p = sim.human_game(false, "map_A")
  T.ok(build_action_available(p, 3, "0"), "room and money: available")
  T.ok(build_action_available(p), "without a strength: the money check only (as before)")
  fill_map(p)
  T.ok(not build_action_available(p, 5, "0"), "no room: not available (" .. p.map:countUnoccupied()
    .. " cells free, " .. #build_candidates(p, { upgd = false, num = "0", built = {}, remaining = 5 }) .. " candidates)")
  set_counter(p.money_counter, 1, sim.cnsts.counter_style.cp)
  T.ok(not build_action_available(p), "1 money: not available (as before)")
end)

T.test("FIXBUILD: the action panel greys BUILD out when nothing fits", function()
  local p = sim.human_game(false, "map_A")
  fill_map(p)
  local slot
  for i = 1, 5 do
    if action_card_object(p, i).getName():find("^BUILD") then slot = i end
  end
  T.ok(not action_row_available(p, p, slot, 5), "BUILD row not available")
end)

-- FIXVENOM -------------------------------------------------------------------------------

T.test("FIXVENOM: with 1 money the end-of-turn venom fee takes it and the turn goes on", function()
  local p = sim.human_game(false, "map_A")
  set_counter(p.money_counter, 1, sim.cnsts.counter_style.cp)
  p.venom_unpaid = true
  sim.record("finish_player_turn")
  show_venom_fee_panel(p)
  T.ok(active_panels.Red:find("1 Money (all you have)", 1, true) ~= nil, "the button says what is paid")
  on_venom_fee_clicked(nil, "Red", nil)
  T.eq(get_counter_value(p.money_counter), 0)
  T.eq(p.venom_unpaid, nil, "fee settled")
  T.eq(#sim.calls.finish_player_turn, 1, "the turn goes on")
end)

T.test("FIXVENOM: with 2 money or more it costs 2 as before", function()
  local p = sim.human_game(false, "map_A")
  set_counter(p.money_counter, 7, sim.cnsts.counter_style.cp)
  p.venom_unpaid = true
  sim.record("finish_player_turn")
  show_venom_fee_panel(p)
  T.ok(active_panels.Red:find("Pay Venom Fee: 2 Money<", 1, true) ~= nil)
  on_venom_fee_clicked(nil, "Red", nil)
  T.eq(get_counter_value(p.money_counter), 5)
  T.eq(#sim.calls.finish_player_turn, 1)
end)

-- FIXANIMAL ------------------------------------------------------------------------------

local function animal_pick(p, number, money)
  set_counter(p.money_counter, money, sim.cnsts.counter_style.cp)
  set_animal_action(p, 5, "0")
  local obj = sim.fake(string.format("(%03d) animal %d", number, number))
  local state = animal_actions.Red
  state.offers[obj.getGUID()] = false
  state.selected = obj
  render_animal_panel(p)
  return state
end

T.test("FIXANIMAL: an animal that cannot be played gets no Confirm, but the reason", function()
  local p = sim.human_game(false, "map_A")
  animal_pick(p, 401, 3)                       -- Cheetah costs 17
  T.ok(not active_panels.Red:find("on_animal_confirm_clicked", 1, true), "no Confirm")
  T.ok(active_panels.Red:find("Insufficient money: need 17", 1, true) ~= nil, "the reason is shown")
end)

T.test("FIXANIMAL: a playable animal gets Confirm", function()
  local p = sim.human_game(false, "map_A")
  p.map:placeUnchecked({ 30, 31 }, { type = "enclosure_2", enclosure = true, occupied = false }, nil,
                       { ignore_touch_rule = true })
  local state = animal_pick(p, 418, 50)        -- Wolf, a size-3 animal: needs a big enough enclosure
  local problem = animal_selection_problem(state)
  if problem == nil then
    T.ok(active_panels.Red:find("on_animal_confirm_clicked", 1, true) ~= nil, "Confirm offered")
  else
    T.ok(not active_panels.Red:find("on_animal_confirm_clicked", 1, true), "no Confirm: " .. problem)
  end
end)

T.test("FIXANIMAL: with no animal on offer that can be played, the first animal can be passed", function()
  -- seed 4200076: ANIMALS II at strength 5 counted a display animal the reputation draw could
  -- fetch; the player drew from the deck instead and was left without a way out
  local p = sim.human_game(false, "map_A")
  local state = animal_pick(p, 401, 3)          -- Cheetah costs 17: cannot be played
  state.selected = nil
  render_animal_panel(p)
  T.ok(active_panels.Red:find("on_animal_pass_clicked", 1, true) ~= nil, "Play no animal offered")
  sim.record("render_claims_table")
  on_animal_pass_clicked(nil, "Red", nil)
  T.eq(state.phase, "done", "the pick ends")
  T.eq(#sim.calls.render_claims_table, 1, "back to the claims")
end)

T.test("FIXANIMAL: with an animal that can be played, the first animal cannot be passed", function()
  local p = sim.human_game(false, "map_A")
  local state = animal_pick(p, 401, 3)
  state.selected = nil
  local playable = false
  sim.record("animal_selection_problem", function() playable = true return nil end)
  render_animal_panel(p)
  T.ok(playable, "the offers were checked")
  T.ok(not active_panels.Red:find("on_animal_pass_clicked", 1, true), "no Pass")
  on_animal_pass_clicked(nil, "Red", nil)
  T.eq(state.phase, "pick", "a click on a stale Pass does nothing")
end)

-- FIXSCAV / FIXPILE ----------------------------------------------------------------------

T.test("FIXSCAV: scavenging from an empty discard pile ends the effect", function()
  local p = sim.human_game(false, "map_A")
  discard_pile = nil
  sim.record("render_claims_table")
  sim.record("prompt_keep")
  scavenging(p, 2, "test")
  sim.pump()
  T.eq(#sim.calls.render_claims_table, 1, "back to the claims")
  T.eq(#sim.calls.prompt_keep, 0, "nothing to keep")
end)

T.test("FIXSCAV: scavenging 3 from a pile of 2 draws the 2", function()
  local p = sim.human_game(false, "map_A")
  discard_pile = deck_of("discard pile", { 401, 402 })
  local kept
  sim.record("prompt_keep", function(_, _, dealt) kept = dealt end)
  scavenging(p, 3, "test")
  sim.pump()
  T.eq(#kept, 2)
end)

T.test("FIXPILE: an empty zoo deck is refilled from the discard pile", function()
  local p = sim.human_game(false, "map_A")
  zoo_deck = deck_of("zoo deck", { 401 })
  discard_pile = deck_of("discard pile", { 402, 403, 404 })
  local got
  deal_cards_to_hand(zoo_deck, 3, p, 1, "zoo_card", function(cards) got = cards end)
  sim.pump()
  T.eq(#got, 3, "3 cards dealt")
  T.eq(discard_pile, nil, "the discard pile became the zoo deck")
end)

T.test("FIXPILE: with both piles empty, nothing is dealt and play goes on", function()
  local p = sim.human_game(false, "map_A")
  zoo_deck = deck_of("zoo deck", {})
  discard_pile = nil
  local got
  deal_cards_to_hand(zoo_deck, 2, p, 1, "zoo_card", function(cards) got = cards end)
  sim.pump()
  T.eq(got and #got, 0)
end)

T.test("FIXPILE: the display stays short when the zoo deck runs out", function()
  sim.human_game(false, "map_A")
  zoo_deck = deck_of("zoo deck", { 401, 402 })
  discard_pile = nil
  display_cards = { sim.fake("(403) a"), sim.fake("(404) b") }
  local done = false
  refill_display(function() done = true end)
  sim.pump()
  T.ok(done, "refill finished")
  T.ok(display_cards[4] ~= nil and display_cards[5] == nil, "4 cards, no more")
end)

T.test("FIXPILE: a search with no matching card ends instead of looping forever", function()
  local p = sim.human_game(false, "map_A")
  zoo_deck = deck_of("zoo deck", { 401, 402, 403 })   -- animals only
  discard_pile = nil
  local called = false
  search(p, "person_sponsor", "test", function() called = true end)
  T.ok(called, "the search ended")
end)

T.test("FIXPILE: a card leaving the display lands even when the discard pile became the zoo deck", function()
  sim.human_game(false, "map_A")
  discard_pile = nil                                  -- it refilled the zoo deck
  local card = sim.fake("(405) leaving")
  T.ok(not departures_landed({ { guid = card.getGUID() } }), "not there yet (no error)")
  put_on_discard_pile(card)                           -- starts a new pile
  T.ok(departures_landed({ { guid = card.getGUID() } }), "landed")
end)

T.test("FIXPILE: the break refill goes on when the cards just discarded are shuffled into the zoo deck", function()
  -- seed 900002, turn 208: the 2 display cards went to the discard pile, the zoo deck ran
  -- short, the discard pile (with those 2) became the zoo deck and the break waited forever
  sim.human_game(false, "map_A")
  zoo_deck = deck_of("zoo deck", { 401 })
  discard_pile = deck_of("discard pile", { 402, 403, 404, 405, 406 })
  display_cards = {}
  for i = 1, 6 do display_cards[i] = sim.fake(string.format("(%d) shown", 410 + i)) end
  local leaving = {}
  for slot = 1, 2 do
    local card = display_cards[slot]
    leaving[#leaving + 1] = { guid = card.getGUID() }
    card.locked = false
    put_on_discard_pile(card)
    display_cards[slot] = nil
  end
  local done = false
  refill_display(function() done = true end, leaving)
  sim.pump()
  T.ok(done, "refill finished")
  T.ok(display_cards[6] ~= nil, "display full again")
end)

T.test("FIXPILE: the break refill goes on when a card just discarded comes straight back to the display", function()
  sim.human_game(false, "map_A")
  zoo_deck = deck_of("zoo deck", { 401 })
  discard_pile = nil
  display_cards = {}
  for i = 1, 6 do display_cards[i] = sim.fake(string.format("(%d) shown", 410 + i)) end
  local leaving = {}
  for slot = 1, 2 do                      -- the discard pile is only these 2 cards
    local card = display_cards[slot]
    leaving[#leaving + 1] = { guid = card.getGUID() }
    card.locked = false
    put_on_discard_pile(card)
    display_cards[slot] = nil
  end
  local done = false
  refill_display(function() done = true end, leaving)  -- draws 2 of the 3: one comes back
  sim.pump()
  T.ok(done, "refill finished")
  T.ok(display_cards[6] ~= nil, "display full again")
end)

T.finish("integration base-mod fixes")
