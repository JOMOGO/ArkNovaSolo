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
    local z = sim.fake("zone " .. k); z.getObjects = function() return {} end
    rawset(t, k, z); return z
  end })
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

T.test("any further click commits the choice", function()
  local p = human_turn()
  on_action_card_button_clicked(nil, "Red_" .. slot_of(p, "AS"), nil)
  T.ok(back.pending.Red ~= nil)
  note_player_interaction()
  T.eq(back.pending.Red, nil)
end)

T.finish("integration back")
