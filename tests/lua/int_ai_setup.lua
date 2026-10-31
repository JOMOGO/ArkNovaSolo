-- AI seats in setup on the BUILT Global.lua (docs/AI_OPPONENT.md §2): the setup panel row,
-- the AI entry in `players`, and the table-wide setup prompts the AI answers like a human:
-- the setup discard (4 of 8), the Marine Worlds draft and the map steps.
local T = require("tests.lib")
local driver = require("ai.driver")
local policy = require("ai.policy")
local rng = require("core.rng")

local function ai_seat(color)
  local p = sim.make_player(color, false)
  p.is_ai, p.ai_level, p.steam_name = true, "medium", "AI " .. color
  return p
end

T.test("setup row: Off, ARNO 1-10, AI Easy-Expert, Off", function()
  arno_setup = { levels = {}, ai = {}, project_module = false }
  local seen = {}
  for _ = 1, 15 do
    ARNO.setup.on_setup_clicked("Blue")
    seen[#seen + 1] = arno_setup.ai.Blue or tostring(arno_setup.levels.Blue)
  end
  T.eq(seen, { "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "easy", "medium", "hard", "expert", "0" })
end)

T.test("add_bots: an AI seat joins players as a full entry, ARNO next to it", function()
  arno_setup = { levels = { Yellow = 3 }, ai = { Blue = "hard" }, project_module = false }
  local list = { { color = "Red", steam_name = "Human" } }
  ARNO.setup.add_bots(list)
  T.eq(#list, 3)
  T.eq(list[2].color, "Blue")
  T.ok(list[2].is_ai == true and list[2].is_arno == nil, "the AI is not an ARNO")
  T.eq(list[2].ai_level, "hard")
  T.ok(list[3].is_arno == true, "ARNO still joins")
  arno_setup = { levels = {}, ai = {}, project_module = false }
  arno_state = nil
end)

T.test("setup discard: the AI picks 4 of its 8 cards and confirms (H5 prompt)", function()
  sim.queue = {}
  Player = sim.hand_players()
  local human, ai = sim.make_player("Red", false), ai_seat("Blue")
  players = { human, ai }
  for _, n in ipairs({ 401, 402, 403, 201, 202, 203, 101, 404 }) do
    sim.fake(string.format("(%03d) card %d", n, n)).deal(1, "Blue", 1)
  end
  sim.fake("(405) human card").deal(1, "Red", 1)
  driver.reset(1)
  driver.policies.Blue = policy.heuristic(rng.new(1))
  sim.record("discard_cards_to_new_pile")
  sim.record("start_game")
  start_setup_discard()
  driver.wake("Blue")
  sim.pump()
  local state = setup_discard_state.Blue
  T.eq(#state.selected, 4, "four cards picked")
  T.ok(state.confirmed, "and confirmed")
  T.eq(#sim.calls.start_game, 0, "the game waits for the human")
end)

T.test("draft: the AI picks a card each round and 2 at the end (Marine Worlds)", function()
  sim.queue = {}
  Player = sim.hand_players()
  local ai = ai_seat("Blue")
  players = { sim.make_player("Red", false), ai }
  local cards = {}
  for i = 1, 3 do
    cards[i] = sim.fake("ANIMALS " .. i)
    cards[i].deal(1, "Blue", DRAFT_UNSELECTED_INDEX)
  end
  draft_round, draft_transition_pending = 1, false
  draft_state = {
    Red = { phase = "round1", pool = {}, locked = {}, confirmed = false, chosen = {} },
    Blue = { phase = "round1", pool = { [cards[1].getGUID()] = true, [cards[2].getGUID()] = true,
                                        [cards[3].getGUID()] = true }, locked = {}, confirmed = false, chosen = {} },
  }
  driver.reset(2)
  driver.wake("Blue")
  sim.pump()
  T.ok(draft_state.Blue.selected_guid ~= nil, "a card picked")
  T.ok(draft_state.Blue.confirmed, "and confirmed")
  draft_state = nil
end)

T.test("classic map setup: the AI clicks Ready with its tile as dealt (AI4)", function()
  sim.queue = {}
  local ai = ai_seat("Blue")
  players = { sim.make_player("Red", false), ai }
  sim.record("on_map_ready_clicked")
  show_map_ready_panels(true)
  sim.pump()
  T.eq(#sim.calls.on_map_ready_clicked, 1)
  T.eq(sim.calls.on_map_ready_clicked[1][2], "Blue")
end)

T.test("custom map setup: the AI plays map A and sits out Ready, then rejoins (AI4, AI5)", function()
  sim.queue = {}
  local human, ai = sim.make_player("Red", false), ai_seat("Blue")
  players = { human, ai }
  local applied = {}
  sim.record("apply_map_choice", function(_, p, key) applied[p.color] = key end)
  sim.record("start_action_card_draft")
  sim.record("distribute_action_cards")
  show_map_ready_panels(false)
  T.eq(applied.Blue, "map_A")
  T.eq(#players, 1, "only the human readies")
  finish_map_setup()
  T.eq(#players, 2, "the AI is back")
  T.eq(players[2].color, "Blue", "in its seat")
end)

T.finish("integration AI setup")
