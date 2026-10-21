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
M.recent = {}           -- color -> action-level snapshot just committed by a click
M.task_started = nil    -- set while an Association task 3/4/5 click is being handled
M.capturing = nil       -- player whose break moves are being held back during the click
M.raw = {}              -- color -> panel XML as the mod rendered it (before our edits)
M.shown = {}            -- color -> that panel as we put it on screen
M.EXTRA_HEIGHT = 46
M.COLOR = "#8A6D1F"     -- every Back button; also hard-coded in the mod's panels (hooks/hooks.json)

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

-- workers deployed now but not in the snapshot go home; the list is restored as a copy
-- (the snapshot's fields hold the live list, which the action appended to)
local function restore_workers(player, saved)
  local keep = {}
  for _, w in ipairs(saved) do keep[w.guid] = true end
  for _, w in ipairs(player.deployed_workers or {}) do
    if not keep[w.guid] then send_worker_home(player, w.guid) end
  end
  player.deployed_workers = copy_list(saved)
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
    kind = "action",
    label = "Back to action choice",
    turn = player.turns_taken,
    player = player,
    slot = slot,
    x_used = sel.x_tokens_used or 0,
    fields = fields,
    persistent_rewards = copy_map(player.persistent_rewards),
    post_action_rewards = copy_list(player.post_action_rewards),
    deployed = copy_list(player.deployed_workers),
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
    '<Button %s onClick="arno_back_clicked(%s)" fontSize="16" minHeight="38" preferredHeight="38" color="%s" textColor="#FFFFFF">%s</Button>',
    marker(color), color, M.COLOR, (M.pending[color] and M.pending[color].label) or "Back")
  return string.sub(grown, 1, pos - 1) .. button .. string.sub(grown, pos)
end

-- Besides ours, the mod's panels have their own one-step Back buttons and red "Pass"
-- buttons. Pass is a game choice, not a way back, so it is never touched.
-- (plain finds: TTS's MoonSharp rejects patterns like <Button[^>]-...[^>]*>)

-- each <Button ...>...</Button> passed to fn; a string result replaces it
local function map_buttons(xml, fn)
  local out, start = {}, 1
  while true do
    local i = xml:find("<Button ", start, true)
    local j = i and xml:find("</Button>", i, true)
    if j == nil then break end
    j = j + #"</Button>" - 1
    local b = string.sub(xml, i, j)
    out[#out + 1] = string.sub(xml, start, i - 1)
    out[#out + 1] = fn(b) or b
    start = j + 1
  end
  out[#out + 1] = string.sub(xml, start)
  return table.concat(out)
end

-- one of the mod's one-step Back buttons (not ours; "Back to building selection" is kept)
local MOD_BACK = 'color="' .. M.COLOR .. '" textColor="#FFFFFF">Back</Button>'
local function mod_back(b) return b:find(MOD_BACK, 1, true) and not b:find('id="arnoBack_', 1, true) end

-- while our Back is offered the mod's one-step Back would be a second, weaker way back:
-- drop it and give its height back to the panel
local function drop_cancel(xml)
  local freed = 0
  local out = map_buttons(xml, function(b)
    if freed == 0 and mod_back(b) then
      freed = (tonumber(b:match(' height="(%d+)"')) or 34) + 6
      return ""
    end
  end)
  if freed == 0 then return xml end
  return (out:gsub('(<Panel[^>]-height=")(%d+)(")',
    function(head, ph, tail) return head .. (tonumber(ph) - freed) .. tail end, 1))
end

-- the panel as shown: with our Back (in place of the mod's) if offered
function M.decorate(color, xml)
  if type(xml) ~= "string" or M.pending[color] == nil then return xml end
  return M.add_button(color, drop_cancel(xml))
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
  local new
  if xml == M.shown[color] and M.raw[color] ~= nil then
    new = M.decorate(color, M.raw[color])   -- rebuilt from the mod's XML, so its own Back returns
    M.shown[color] = new
  else
    new = transform(color, xml)
  end
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
  M.recent[color] = snap
  rerender(color, M.strip_button)
  for _, n in ipairs(snap.held_breaks or {}) do break_x(n, snap.player) end
end

function M.clear_all()
  for color in pairs(M.pending) do M.clear(color) end
end

-- ---------------------------------------------------------------- Back

-- An action-level snapshot committed earlier in THIS turn of this player (never older).
function M.same_turn(snap, player)
  return snap ~= nil and snap.kind == "action" and snap.player == player
    and snap.turn == player.turns_taken and current_player == player
end

-- Association tasks 3/4/5 and Sponsors "Play a Sponsor Card": snapshot taken before the
-- button is handled (owner request); Back returns to that choice
function M.capture_task(player)
  local color = player.color
  local claims = {}
  for i, sub in ipairs(player.claims or {}) do
    local c = {}
    for k, v in pairs(sub) do c[k] = v end
    claims[i] = c
  end
  local a = association_actions[color]
  local assoc = nil
  if a ~= nil then
    assoc = {}
    for k, v in pairs(a) do assoc[k] = v end
    assoc.taken = copy_map(a.taken)
  end
  local sp = sponsor_actions[color]
  local sponsor = nil
  if sp ~= nil then
    sponsor = {}
    for k, v in pairs(sp) do sponsor[k] = v end
    sponsor.offers = copy_map(sp.offers)
  end
  local fields = {}
  for k, v in pairs(player) do fields[k] = v end
  local parent = M.recent[color]
  if not M.same_turn(parent, player) then parent = nil end
  return {
    kind = "task",
    label = "Back to association tasks",
    player = player,
    fields = fields,
    claims = claims,
    assoc = assoc,
    sponsor = sponsor,
    persistent_rewards = copy_map(player.persistent_rewards),
    post_action_rewards = copy_list(player.post_action_rewards),
    deployed = copy_list(player.deployed_workers),
    parent = parent,
    held_breaks = {},
  }
end

-- the Cards action's grouped "Snap a card / Draw N cards" choice (owner request: Snap, and
-- Cards II's Draw from reputation range, only arm a pick-up, so Back can return to it)
function M.cards_choice(player, idx)
  local sub = player.claims and player.claims[#player.claims]
  if sub == nil or not sub.grouped or sub[idx] == nil then return false end
  local draw = false
  for _, c in ipairs(sub) do
    local text = resolve_claim_text(c)
    if type(text) ~= "string" then return false end
    if text:find("^Draw %d+ cards") then
      draw = true
    elseif not text:find("^Snap ") then
      return false
    end
  end
  return draw
end

-- what Snap / Draw armed (nothing has been taken yet: a pick-up commits)
local function disarm_cards(player)
  if snap_player == player then
    snap_player, snap_remaining, snap_refill = nil, 0, false
    snap_card_type, snap_max_size, snap_callback = nil, nil, nil
  end
  if rep_draw_player == player then
    rep_draw_player, rep_draw_remaining, rep_draw_callback, rep_draw_lookup = nil, 0, nil, nil
    if placeholder_card ~= nil then placeholder_card.interactable = false end
  end
  lock_display_cards()
end

local function back_task(snap)
  local player, color = snap.player, snap.player.color
  if snap.cards then disarm_cards(player) end
  local live = player.deployed_workers
  for k in pairs(player) do
    if snap.fields[k] == nil then player[k] = nil end
  end
  for k, v in pairs(snap.fields) do player[k] = v end
  player.deployed_workers = live
  restore_workers(player, snap.deployed)
  player.persistent_rewards = snap.persistent_rewards
  player.post_action_rewards = snap.post_action_rewards
  player.claims = snap.claims
  player.on_claims_empty = nil
  -- restore in place: the choice buttons' closures hold the original state tables
  local function restore(tbl, saved)
    local live = tbl[color]
    if live ~= nil and saved ~= nil then
      for k in pairs(live) do live[k] = nil end
      for k, v in pairs(saved) do live[k] = v end
    else
      tbl[color] = saved
    end
  end
  restore(association_actions, snap.assoc)
  restore(sponsor_actions, snap.sponsor)
  if snap.sponsor ~= nil and lock_display_cards then lock_display_cards() end
  if project_supports ~= nil then project_supports[color] = nil end
  active_claim = nil
  claims_players[color] = nil
  clear_player_panel(color)
  local what = snap.cards and "Cards" or (snap.sponsor and "sponsor" or "association task")
  printToAll(player.steam_name .. " takes back their " .. what .. " choice.")
  if snap.parent ~= nil then M.pending[color] = snap.parent end
  render_claims_table(player)
end

function M.back(color)
  local snap = M.pending[color]
  if snap == nil then return end
  if snap.kind == "task" then
    M.pending[color] = nil
    return back_task(snap)
  end
  M.pending[color] = nil                  -- held breaks are dropped: the action never happened
  local player = snap.player
  clear_build_action_state(player)
  clear_sponsor_action_state(player)
  clear_animal_action_state(player)
  clear_association_action_state(player)
  for k in pairs(player) do
    if snap.fields[k] == nil then player[k] = nil end
  end
  local live = player.deployed_workers
  for k, v in pairs(snap.fields) do player[k] = v end
  player.deployed_workers = live
  restore_workers(player, snap.deployed or {})
  player.persistent_rewards = snap.persistent_rewards
  player.post_action_rewards = snap.post_action_rewards
  player.claims = {}
  player.on_claims_empty = nil
  player.current_action = nil
  claims_players[color] = nil
  if snap.x_used > 0 then update_x_token(player, snap.x_used, "taking back their action choice") end
  seat_action_card(player, snap.slot)
  if lock_display_cards then lock_display_cards() end   -- Animals/Sponsors II unlock display cards
  clear_player_panel(color)
  printToAll(player.steam_name .. " takes back their action choice.")
  create_action_selection_panel(player)
end

return M
