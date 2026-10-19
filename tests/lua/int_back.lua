-- Integration tests on the BUILT Global.lua for H20 (owner request): "Back to action choice"
-- after choosing an action, running the mod's real on_action_card_button_clicked.
local T = require("tests.lib")
local back = require("adapter.back")

local function human_turn()
  local p = sim.make_player("Red", false)
  players = { p }
  arno_state = nil
  current_player = p
  p.x_tokens = {}
  action_selection_state = { Red = { player = p, x_tokens_used = 0, x_token_active = false } }
  association_actions, build_actions, animal_actions, sponsor_actions = {}, {}, {}, {}
  zones = setmetatable({}, { __index = function(t, k)
    local z = sim.fake("zone " .. k)
    local contents = {}
    if k:find("_partner") then                     -- a partner zoo tile lies on the board
      local tile = sim.fake("partner tile " .. k); tile.addTag("partner"); contents = { tile }
    end
    z.getObjects = function() return contents end
    rawset(t, k, z); return z
  end })
  sim.record("send_worker_to_task", function(_, pl, guid, task)
    pl.deployed_workers[#pl.deployed_workers + 1] = { guid = guid, task = task }
  end)
  sim.record("send_worker_home")
  sim.record("action_strength", function() return 3 end)
  sim.record("arm_multiplier_offer")
  sim.record("seat_action_card")
  sim.record("create_action_selection_panel")
  sim.record("update_x_token")
  back.pending = {}
  return p
end

local function slot_of(p, prefix)
  for i, rec in ipairs(p.action_cards) do
    if getObjectFromGUID(rec.guid).getName():sub(1, 2) == prefix then return i end
  end
end

T.test("Association: Back restores the action menu and clears the action", function()
  local p = human_turn()
  local slot = slot_of(p, "AS")
  on_action_card_button_clicked(nil, "Red_" .. slot, nil)
  sim.pump()
  T.ok(association_actions.Red ~= nil, "association action started")
  T.ok(back.pending.Red ~= nil, "Back offered")
  arno_back_clicked(nil, "Red", nil)
  T.eq(association_actions.Red, nil, "action state cleared")
  T.eq(#p.claims, 0)
  T.eq(p.current_action, nil)
  T.eq(#sim.calls.seat_action_card, 1, "card put back")
  T.eq(#sim.calls.create_action_selection_panel, 1, "menu shown again")
  T.ok(back.pending.Red == nil)
end)

T.test("Back refunds spent X-tokens", function()
  local p = human_turn()
  action_selection_state.Red.x_tokens_used = 2
  on_action_card_button_clicked(nil, "Red_" .. slot_of(p, "AS"), nil)
  arno_back_clicked(nil, "Red", nil)
  local calls = sim.calls.update_x_token
  T.eq(calls[1][2], -2, "spent on choosing")
  T.eq(calls[2][2], 2, "refunded on Back")
end)

T.test("Cards: Back offered; the break moves only when the choice is committed", function()
  local p = human_turn()
  players[2] = sim.make_player("Blue", false)     -- break_x is a no-op in 1-player games
  break_current_val = 9
  sim.record("move_break_token")
  on_action_card_button_clicked(nil, "Red_" .. slot_of(p, "CA"), nil)
  T.ok(back.pending.Red ~= nil, "Back offered for Cards")
  T.eq(break_current_val, 9, "break token not moved yet")
  note_player_interaction()                      -- e.g. clicking "Draw 1 cards"
  T.eq(break_current_val, 7, "break +2 applied on commit")
end)

T.test("Cards: Back drops the held break move", function()
  local p = human_turn()
  players[2] = sim.make_player("Blue", false)
  break_current_val = 9
  sim.record("move_break_token")
  on_action_card_button_clicked(nil, "Red_" .. slot_of(p, "CA"), nil)
  arno_back_clicked(nil, "Red", nil)
  T.eq(break_current_val, 9)
  T.eq(#p.claims, 0)
  T.eq(#sim.calls.create_action_selection_panel, 1)
end)

T.test("the button sits inside the action panel, which grows to fit", function()
  local p = human_turn()
  on_action_card_button_clicked(nil, "Red_" .. slot_of(p, "AS"), nil)
  local xml = active_panels.Red
  T.ok(xml ~= nil and xml:find('id="arnoBack_Red"', 1, true) ~= nil, "button in the Red panel")
  T.ok(xml:find('arnoBack_Red', 1, true) < select(1, xml:find("</VerticalLayout>", xml:find('arnoBack_Red', 1, true), true)),
    "inside the layout")
  note_player_interaction()
  T.ok(active_panels.Red == nil or active_panels.Red:find('arnoBack_Red', 1, true) == nil, "removed on commit")
end)

local function claim_index(p, label)
  local sub = p.claims[#p.claims]
  for i, c in ipairs(sub) do
    local text = type(c.button_text) == "function" and c.button_text() or c.button_text
    if text == label then return i end
  end
end

T.test("Association task 3: Back returns to the task list, worker goes home", function()
  local p = human_turn()
  on_action_card_button_clicked(nil, "Red_" .. slot_of(p, "AS"), nil)
  local tasks = #p.claims[#p.claims]
  local i = claim_index(p, "Take a Partner Zoo")
  T.ok(i ~= nil, "task 3 offered")
  note_player_interaction()                        -- the mod's wrapper does this on every click
  on_claim_button_clicked(nil, "Red_" .. i, nil)
  T.eq(#p.deployed_workers, 1, "worker placed on task 3")
  T.eq(back.pending.Red and back.pending.Red.kind, "task", "task-level Back offered")
  T.ok(active_panels.Red:find("Back to association tasks", 1, true) ~= nil, "button in the zoo picker")
  arno_back_clicked(nil, "Red", nil)
  T.eq(#p.deployed_workers, 0, "worker went home")
  T.eq(#sim.calls.send_worker_home, 1)
  T.eq(association_actions.Red.taken[3], nil, "task 3 not taken")
  T.eq(#p.claims[#p.claims], tasks, "the full task list is back")
  T.eq(back.pending.Red and back.pending.Red.kind, "action", "Back to action choice available again")
  T.ok(active_panels.Red:find("Back to action choice", 1, true) ~= nil)
end)

T.test("ARNO panel height covers its contents with a margin", function()
  printToAll = function() end
  arno_setup = { levels = { Yellow = 3, Blue = 5 }, project_module = true }
  local list = { sim.make_player("Red", false) }
  ARNO.setup.add_bots(list)
  for _, color in ipairs({ "Blue", "Yellow" }) do
    local bot = arno_state.bots[color]
    bot.last_turn = {}
    for i = 1, 9 do bot.last_turn[i] = string.rep("a long outcome line ", 4) .. i end
  end
  local panel = require("ui.panel")
  local xml = panel.xml(nil)
  local height = tonumber(xml:match('id="arnoPanel"[^>]-height="(%d+)"'))
  local sum = 0
  for h in xml:gmatch('preferredHeight="(%d+)"') do sum = sum + tonumber(h) end
  T.ok(height >= sum + panel.MARGIN, "panel " .. height .. " vs contents " .. sum)
  T.ok(xml:find('minHeight="34" preferredHeight="34"', 1, true) ~= nil, "a wrapped line gets 2 lines of height")
end)

T.test("any further click commits the choice", function()
  local p = human_turn()
  on_action_card_button_clicked(nil, "Red_" .. slot_of(p, "AS"), nil)
  T.ok(back.pending.Red ~= nil)
  note_player_interaction()
  T.eq(back.pending.Red, nil)
end)

T.finish("integration back")
