-- Integration soak test on the BUILT Global.lua: complete automatic ARNO turns through the
-- real entry point (create_action_selection_panel -> H9 -> turn.start -> run -> end of turn),
-- with random cards from the seeded core, the real claims engine and table facts from fakes.
-- Also checks replay determinism: same arno_state + same table -> same decisions.
local T = require("tests.lib")
local state = require("adapter.state")

local DISPLAY = { 401, 228, 102, 405, 251, 103 }
local DECK = {}
for i = 1, 400 do DECK[i] = ({ 401, 402, 403, 404, 405, 406, 407, 408, 410, 412, 101, 102, 103, 110, 201, 205, 208, 228, 230, 251 })[(i * 7) % 20 + 1] end

local function table_setup(seed)
  local p, bot = sim.setup_game()
  arno_state.rng = { hi = math.floor(seed / 65536), lo = seed % 65536 }
  bot.card_slots, bot.last_slot = nil, nil
  bot.level = 4
  checkpoint_open = false
  break_current_val = 9
  zoo_deck = sim.deck(DECK)
  discard_pile = sim.deck({})
  display_cards = {}
  for i, n in ipairs(DISPLAY) do display_cards[i] = sim.fake(string.format("#%03d display", n)) end
  base_projects = {}
  for i, n in ipairs({ 101, 102, 103 }) do base_projects[i] = { sim.fake(string.format("#%03d base", n)).getGUID(), {} } end
  -- one base project already carries the human's cube
  local human_cube = sim.fake("red cube"); human_cube.addTag("Red")
  base_projects[2][2][3] = human_cube.getGUID()
  added_projects = {}
  sim.record("refill_display", function(_, cb)
    for i = 1, 6 do
      if display_cards[i] == nil then display_cards[i] = zoo_deck.takeObject({}) end
    end
    if cb then cb() end
  end)
  sim.record("resolve_display_mark")
  sim.record("report_discard")
  sim.record("add_remove_icons")
  sim.record("apply_hooks")
  sim.record("take_checkpoint")
  sim.record("break_x", function(_, n) break_current_val = math.max(0, break_current_val - n) end)
  sim.record("add_project_to_row", function(_, obj) added_projects[#added_projects + 1] = { obj.getGUID(), {} } end)
  sim.record("project_slot_world_position", function() return Vector(0, 0, 0) end)
  sim.record("refresh_status_panels")
  sim.record("prompt_final_scoring_discard", function(orig, player, count, pool, cb)
    if player.is_arno then return orig(player, count, pool, cb) end
    cb()                                         -- the human discards at once
  end)
  return p, bot
end

local function play_turns(p, n)
  local before = #sim.calls.finish_player_turn
  for t = 1, n do
    create_action_selection_panel(p)
    sim.pump()
    T.eq(#sim.calls.finish_player_turn, before + t, "turn " .. t .. " ended exactly once")
    T.eq(#p.claims, 0, "turn " .. t .. " left no claims")
    -- a real break returns the workers; emulate it every 6 turns
    if t % 6 == 0 then p.deployed_workers = {} end
  end
end

local function full_log()
  local out = {}
  for _, line in ipairs(arno_state.log) do out[#out + 1] = line end
  return table.concat(out, "\n")
end

T.test("60 automatic ARNO turns end cleanly, no step errors", function()
  local p, bot = table_setup(424242)
  state.LOG_LINES = 100000
  play_turns(p, 60)
  local log = full_log()
  T.ok(not log:find("ERROR", 1, true), "a step raised an error:\n" .. log)
  T.eq(bot.turns, 60)
  T.ok(#p.deployed_workers <= p.worker_count)
  T.eq(get_counter_value(p.money_counter), 25, "ARNO never gets money")
  T.ok(get_counter_value(p.appeal_counter) > 0, "ARNO scored appeal")
  T.ok(log:find("association worker", 1, true) ~= nil, "association turns happened")
  T.ok(log:find("takes display card", 1, true) ~= nil, "display snaps happened")
end)

T.test("replay determinism: same state and table give identical turns", function()
  local p1 = table_setup(777)
  state.LOG_LINES = 100000
  arno_state.log = {}
  play_turns(p1, 25)
  local first = full_log()
  local p2 = table_setup(777)
  arno_state.log = {}
  play_turns(p2, 25)
  T.eq(full_log(), first, "logs differ")
end)

T.test("manual mode waits for the Run button", function()
  local p, bot = table_setup(99)
  arno_state.auto = false
  local before = #sim.calls.finish_player_turn
  create_action_selection_panel(p)
  sim.pump()
  T.eq(#sim.calls.finish_player_turn, before, "did not play by itself")
  on_arno_run_clicked()
  sim.pump()
  T.eq(#sim.calls.finish_player_turn, before + 1)
  T.eq(bot.turns, 1)
end)

T.test("human-only prompts (multiplier, hypnosis) are ignored for ARNO", function()
  local p, bot = table_setup(5)
  create_action_selection_panel(p, "build", nil, nil)
  sim.pump()
  T.eq(bot.turns, 0)
end)

T.finish("integration turns")
