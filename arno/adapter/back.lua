-- ARNO 3.0 for "Ark Nova - Complete Scripted" (Tabletop Simulator).
--
-- Owner request (H20): a "Back" button after a human chose an action but before making any
-- choice in it. Choosing an action only sets up Lua state for Association, Build, Animals
-- and Sponsors, so it can be undone exactly: the player table (scalar fields, persistent
-- and post-action rewards) is snapshotted before the click and restored, the action state
-- is cleared, spent X-tokens are refunded and the action card is put back. Not offered when
-- the click already did something irreversible: Cards (moves the break token and draws),
-- X-token mode, a multiplier or hypnosis turn, or a venom token on the card.
-- The button disappears on the player's next interaction (any button or picking up a card).
-- Applies to every human, with or without ARNO in the game.

local M = {}

M.pending = {}          -- color -> snapshot (transient: rewind/load clears it, which is fine)

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
  local prefix = string.sub(card.getName(), 1, 2)
  if prefix == "CA" then return nil end
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
  }
end

local function key(color) return "arno_back_" .. color end

function M.offer(snap)
  local color = snap.player.color
  M.pending[color] = snap
  if not set_active_panel then return end
  set_active_panel(key(color), string.format([[
    <Panel id="arnoBackPanel_%s" visibility="%s" rectAlignment="LowerRight" offsetXY="-60 90" width="260" height="44" color="#222222DD">
      <Button onClick="arno_back_clicked(%s)" fontSize="16" color="#8A6D1F" textColor="#FFFFFF">Back to action choice</Button>
    </Panel>]], color, color, color))
end

function M.clear(color)
  if M.pending[color] == nil then return end
  M.pending[color] = nil
  if clear_active_panel then clear_active_panel(key(color)) end
end

function M.clear_all()
  for color in pairs(M.pending) do M.clear(color) end
end

function M.back(color)
  local snap = M.pending[color]
  if snap == nil then return end
  M.clear(color)
  local player = snap.player
  -- end the action's own state first (these may touch player fields), then restore
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
