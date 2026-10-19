-- ARNO 3.0 for "Ark Nova - Complete Scripted" (Tabletop Simulator).
--
-- Owner request (H20): a "Back to action choice" button inside the action's own panel,
-- right after a human chose an action and before making any choice in it. Choosing an
-- action only sets up Lua state, so it can be undone exactly: the player table (scalar
-- fields, persistent and post-action rewards) is snapshotted before the click and
-- restored, the action state is cleared, spent X-tokens are refunded and the action card
-- is put back.
-- Cards: the mod moves the break token as soon as the action is chosen; while Back is
-- available that move is held back and applied when the player commits (clicks Snap/Draw
-- or anything else), so Back never has to undo it.
-- Not offered when the click already did something irreversible: X-token mode, a
-- multiplier or hypnosis turn, or a venom token on the card.
-- Any further interaction (a button or picking up a card) commits the choice.

local M = {}

M.pending = {}          -- color -> snapshot (transient: rewind/load clears it, which is fine)
M.capturing = nil       -- player whose break moves are being held back during the click
M.EXTRA_HEIGHT = 46

local function copy_list(t)
  local out = {}
  for i, v in ipairs(t or {}) do
    if type(v) == "table" then
      local c = {}
      for k, x in pairs(v) do c[k] = x end
      out[i] = c
    else
      out[i] = v
    end
  end
  return out
end

local function copy_map(t)
  local out = {}
  for k, v in pairs(t or {}) do out[k] = v end
  return out
end

function M.capture(player, slot, sel)
  if player == nil or player.is_arno or sel == nil then return nil end
  if sel.x_token_active or sel.multiplier ~= nil or sel.hypnosis ~= nil then return nil end
  local card = action_card_object(player, slot)
  if card == nil then return nil end
  if action_card_has_token(player, slot, "venom") then return nil end
  local fields = {}
  for k, v in pairs(player) do fields[k] = v end
  return {
    player = player,
    slot = slot,
    x_used = sel.x_tokens_used or 0,
    fields = fields,
    persistent_rewards = copy_map(player.persistent_rewards),
    post_action_rewards = copy_list(player.post_action_rewards),
    held_breaks = {},
  }
end

-- ---------------------------------------------------------------- the button in the panel

local function marker(color) return 'id="arnoBack_' .. color .. '"' end

function M.add_button(color, xml)
  if type(xml) ~= "string" or xml:find(marker(color), 1, true) then return xml end
  local grown, n = xml:gsub('(<Panel[^>]-height=")(%d+)(")',
    function(head, h, tail) return head .. (tonumber(h) + M.EXTRA_HEIGHT) .. tail end, 1)
  if n == 0 then return xml end
  local pos, start = nil, 1
  while true do
    local i = string.find(grown, "</VerticalLayout>", start, true)
    if i == nil then break end
    pos, start = i, i + 1
  end
  if pos == nil then return xml end
  local button = string.format(
    '<Button %s onClick="arno_back_clicked(%s)" fontSize="16" minHeight="38" preferredHeight="38" color="#8A6D1F" textColor="#FFFFFF">Back to action choice</Button>',
    marker(color), color)
  return string.sub(grown, 1, pos - 1) .. button .. string.sub(grown, pos)
end

function M.strip_button(color, xml)
  if type(xml) ~= "string" then return xml end
  local i = xml:find("<Button " .. marker(color), 1, true)
  if i == nil then return xml end
  local j = xml:find("</Button>", i, true)
  local out = string.sub(xml, 1, i - 1) .. string.sub(xml, j + #"</Button>")
  return (out:gsub('(<Panel[^>]-height=")(%d+)(")',
    function(head, h, tail) return head .. (tonumber(h) - M.EXTRA_HEIGHT) .. tail end, 1))
end

local function rerender(color, transform)
  if active_panels == nil or set_active_panel == nil then return end
  local xml = active_panels[color]
  if xml == nil then return end
  local new = transform(color, xml)
  if new ~= xml then set_active_panel(color, new) end
end

function M.offer(snap)
  M.pending[snap.player.color] = snap
  rerender(snap.player.color, M.add_button)
end

-- commit: the choice stands; apply what was held back
function M.clear(color)
  local snap = M.pending[color]
  if snap == nil then return end
  M.pending[color] = nil
  rerender(color, M.strip_button)
  for _, n in ipairs(snap.held_breaks) do break_x(n, snap.player) end
end

function M.clear_all()
  for color in pairs(M.pending) do M.clear(color) end
end

-- ---------------------------------------------------------------- Back

function M.back(color)
  local snap = M.pending[color]
  if snap == nil then return end
  M.pending[color] = nil                  -- held breaks are dropped: the action never happened
  local player = snap.player
  clear_build_action_state(player)
  clear_sponsor_action_state(player)
  clear_animal_action_state(player)
  clear_association_action_state(player)
  for k in pairs(player) do
    if snap.fields[k] == nil then player[k] = nil end
  end
  for k, v in pairs(snap.fields) do player[k] = v end
  player.persistent_rewards = snap.persistent_rewards
  player.post_action_rewards = snap.post_action_rewards
  player.claims = {}
  player.on_claims_empty = nil
  player.current_action = nil
  claims_players[color] = nil
  if snap.x_used > 0 then update_x_token(player, snap.x_used, "taking back their action choice") end
  seat_action_card(player, snap.slot)
  clear_player_panel(color)
  printToAll(player.steam_name .. " takes back their action choice.")
  create_action_selection_panel(player)
end

return M
