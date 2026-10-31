-- AI opponent (docs/AI_OPPONENT.md §3): everything the AI could do right now, as a list of
-- choices. A choice is { kind, label, tag, apply(done) }: kind is the input
-- (ai.inputs), tag is "pass", "back", "confirm" or nil, and apply carries it out and calls
-- done() once the mod has taken it in (tile drops settle a few frames later).
--
-- The choices are read from what a human would see and could touch:
--   * the buttons of the AI's open panel (active_panels), minus disabled or hidden ones;
--   * the objects the mod's pick-up dispatcher (onObjectPickUp) would accept now;
--   * every legal spot for a tile the mod asks the AI to place.
-- Nothing here decides; ai.policy does.

local inputs = require("ai.inputs")

local M = {}

-- at most this many tile spots are offered per placement (P3 in the plan: cost)
M.MAX_PLACEMENTS = 60

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function tag_of(label)
  local l = label:lower()
  if l == "pass" or l:find("^pass%W") then return "pass" end
  if l == "back" or l:find("^back") or l:find("go back", 1, true) or l == "cancel" then return "back" end
  if l == "confirm" then return "confirm" end
  return nil
end
M.tag_of = tag_of

-- the clickable buttons of a panel's XML: { handler, arg, label }
function M.buttons(xml)
  local out = {}
  if xml == nil then return out end
  for attrs, label in xml:gmatch("<Button([^>]*)>(.-)</Button>") do
    local handler, arg = attrs:match('onClick="([%w_]+)%(([^)]*)%)"')
    if handler ~= nil and not attrs:find('interactable="false"', 1, true)
       and not attrs:find('active="false"', 1, true) then
      out[#out + 1] = { handler = handler, arg = arg, label = trim(label) }
    end
  end
  return out
end

local function add(list, choice)
  list[#list + 1] = choice
end

local function now(fn)
  return function(done) fn(); done() end
end

local function card_name(obj)
  local ok, name = pcall(function() return obj.getName() end)
  return ok and name or "?"
end

local function pick_up(list, color, obj, why)
  if obj == nil then return end
  add(list, { kind = "pick_up", label = why .. ": " .. card_name(obj), obj = obj,
              apply = now(function() inputs.pick_up(color, obj) end) })
end

-- every legal placement of `shape` under `opts` (the mod's own search, asked for all)
function M.placements(player, shape, opts, accept, limit)
  local out = {}
  local search = {}
  for k, v in pairs(opts or {}) do search[k] = v end
  local extra = opts and opts.extra_check
  search.extra_check = function(cells)
    if (extra == nil or extra(cells))
       and placement_meets_requirements(player.map, cells, opts or {})
       and (accept == nil or accept(cells)) then
      out[#out + 1] = cells
    end
    return #out >= (limit or M.MAX_PLACEMENTS)    -- true stops the search
  end
  player.map:findValidPlacement(shape, search)
  return out
end

local function cells_label(cells)
  return table.concat(cells, ",")
end

local function tile_drops(list, player, tile_guid, shape, opts, accept)
  if tile_guid == nil or shape == nil then return end
  local tile = getObjectFromGUID(tile_guid)
  if tile == nil then return end
  local board_pos = player.player_board.getPosition()
  for _, cells in ipairs(M.placements(player, shape, opts, accept)) do
    local transform = tile_object_transform_for_cells(tile, board_pos, cells)
    add(list, { kind = "drop_tile", label = "place on " .. cells_label(cells), cells = cells,
                apply = function(done) inputs.drop_tile(player.color, tile, transform, done) end })
  end
end

-- display prompts (snap, reputation draw, mark, shark attack, digging), as onObjectPickUp
-- tests them
local function display_choices(list, color)
  if display_cards == nil then return end
  for i = 1, 6 do
    local obj = display_cards[i]
    if obj ~= nil then
      local guid = obj.getGUID()
      if snap_player ~= nil and snap_player.color == color and snappable_display_card(i) then
        pick_up(list, color, obj, "snap " .. i)
      elseif rep_draw_player ~= nil and rep_draw_player.color == color and rep_draw_lookup
             and rep_draw_lookup[guid] then
        pick_up(list, color, obj, "take " .. i)
      elseif mark_state ~= nil and mark_state.player.color == color and mark_state.slots[i] then
        pick_up(list, color, obj, "mark " .. i)
      elseif shark_attack_state ~= nil and shark_attack_state.player.color == color
             and shark_attack_state.lookup[guid] then
        pick_up(list, color, obj, "attack " .. i)
      elseif digging_player ~= nil and digging_player.color == color and digging_selected == nil then
        pick_up(list, color, obj, "dig " .. i)
      end
    end
  end
  if rep_draw_player ~= nil and rep_draw_player.color == color and placeholder_card ~= nil then
    add(list, { kind = "pick_up", label = "take from the deck",
                apply = now(function() on_placeholder_card_picked_up({ color = color }) end) })
  end
  if digging_player ~= nil and digging_player.color == color and digging_selected == nil
     and digging_hand_lookup then
    for guid in pairs(digging_hand_lookup) do
      pick_up(list, color, getObjectFromGUID(guid), "dig from hand")
    end
  end
end

-- the cards an action offers; picking another one replaces the selection, as for a human
local function offer_choices(list, color, state, why)
  if state == nil or state.offers == nil then return end
  local selected = state.selected and state.selected.getGUID()
  local guids = {}
  for guid in pairs(state.offers) do
    if guid ~= selected then guids[#guids + 1] = guid end
  end
  table.sort(guids)                                 -- pairs order is not stable
  for _, guid in ipairs(guids) do pick_up(list, color, getObjectFromGUID(guid), why) end
end

-- what the AI sees, cheaply: its panel and the state its inputs change (selections, the
-- phase of an action, tiles, hand, display, money, claims). An input that leaves this
-- unchanged was not taken in by the mod (a Confirm that cannot confirm, ...). Polled every
-- frame while an input settles, so it must not search placements.
local function guid_of(obj) return obj and obj.getGUID() or "-" end

function M.fingerprint(player)
  local color = player.color
  local parts = { tostring(active_panels and active_panels[color]) }
  local function put(v) parts[#parts + 1] = tostring(v) end
  local selection = selection_panels and selection_panels[color]
  put(selection and #selection.selected)
  local discard = setup_discard_state and setup_discard_state[color]
  if discard then put(#discard.selected); put(discard.confirmed) end
  local draft = draft_state and draft_state[color]
  if draft then
    put(draft.phase); put(draft.selected_guid); put(#draft.chosen); put(draft.confirmed)
    put(draft_round); put(draft_transition_pending)
  end
  local animal = animal_actions and animal_actions[color]
  -- spin buttons (cube allocation, X-tokens) change counts the mod shows with
  -- UI.setAttribute, not in the panel XML
  local function counts(t)
    if type(t) ~= "table" then return end
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    for _, k in ipairs(keys) do put(k .. "=" .. tostring(t[k] or t[tonumber(k)])) end
  end
  if animal then
    put(animal.phase); put(guid_of(animal.selected)); put(animal.chosen and #animal.chosen)
    put(animal.discount_on); put(animal.condition_token_on)
    counts(animal.allocation)
  end
  local vacate = enclosure_vacates and enclosure_vacates[color]
  if vacate then put(vacate.phase); put(vacate.chosen); counts(vacate.allocation) end
  local sel = action_selection_state and action_selection_state[color]
  if sel then put(sel.x_tokens_used); put(sel.x_token_active) end
  for _, states in ipairs({ sponsor_actions, marketing_plays }) do
    local s = states and states[color]
    put(s and guid_of(s.selected))
  end
  local placement = tile_placements and tile_placements[color]
  put(placement and placement.can_confirm); put(placement and placement.kind)
  put(player.pending_building and player.pending_building.tile_guid)
  put(snap_player and snap_player.color); put(rep_draw_player and rep_draw_remaining)
  put(mark_state and mark_state.player.color); put(shark_attack_state and shark_attack_state.player.color)
  put(digging_player and guid_of(digging_selected))
  -- not the hand or the display: a dealt card shows up there before the mod has finished
  -- with it (its callbacks wait for the card to land)
  put(get_counter_value(player.money_counter))
  put(#player.claims); put(player.claims[#player.claims] and #player.claims[#player.claims])
  return table.concat(parts, "\0")
end

-- all choices for the player's colour right now (empty: nothing to answer)
function M.list(player)
  local color = player.color
  local list = {}

  local selection = selection_panels and selection_panels[color]
  if selection ~= nil and #selection.selected < selection.num then
    local chosen = {}
    for _, card in ipairs(selection.selected) do chosen[card.getGUID()] = true end
    for _, card in ipairs(selection.pool) do
      if not chosen[card.getGUID()] then pick_up(list, color, card, "select") end
    end
    -- a final scoring card is discarded by taking it out of the hand: the mod waits for
    -- the hand to hold one card less (discard_final_scoring_cards), so it is put down next
    -- to the board, as a human would drop it on the table
    if selection.action == "final scoring discard" then
      for _, c in ipairs(list) do
        local obj, apply = c.obj, c.apply
        c.apply = function(done)
          apply(function() end)
          local at = player.player_board.getPosition()
          obj.setPosition({ x = at.x, y = at.y + 2, z = at.z - 12 })
          done()
        end
      end
    end
  end

  -- setup: discard 4 of the 8 cards (one panel for every player, UI.setXml)
  local discard = setup_discard_state and setup_discard_state[color]
  if discard ~= nil and not discard.confirmed then
    local chosen = {}
    for _, card in ipairs(discard.selected) do chosen[card.getGUID()] = true end
    if #discard.selected < discard.num then
      for _, card in ipairs(discard.pool) do
        if not chosen[card.getGUID()] then pick_up(list, color, card, "setup discard") end
      end
    else
      add(list, { kind = "click", label = "Confirm", tag = "confirm", handler = "on_setup_discard_clicked",
                  arg = color, apply = now(function() inputs.click("on_setup_discard_clicked", color) end) })
    end
  end

  -- Marine Worlds: the action-card draft (pick one per round, then 2 to play)
  local draft = draft_state and draft_state[color]
  if draft ~= nil and not draft.confirmed and not draft_transition_pending then
    local ready
    if draft.phase == "final_pick" then
      local chosen = {}
      for _, guid in ipairs(draft.chosen) do chosen[guid] = true end
      if #draft.chosen < 2 then
        for _, card in ipairs(Player[color].getHandObjects(DRAFT_SELECTED_INDEX)) do
          if not chosen[card.getGUID()] then pick_up(list, color, card, "draft keep") end
        end
      end
      ready = #draft.chosen == 2
    else
      if draft.selected_guid == nil then
        local guids = {}
        for guid in pairs(draft.pool) do
          if not draft.locked[guid] then guids[#guids + 1] = guid end
        end
        table.sort(guids)
        for _, guid in ipairs(guids) do pick_up(list, color, getObjectFromGUID(guid), "draft pick") end
      end
      ready = draft.selected_guid ~= nil
    end
    if ready then
      add(list, { kind = "click", label = "Confirm", tag = "confirm", handler = "on_draft_confirm_clicked",
                  arg = color, apply = now(function() inputs.click("on_draft_confirm_clicked", color) end) })
    end
  end

  display_choices(list, color)

  local animal = animal_actions and animal_actions[color]
  if animal ~= nil and animal.phase == "pick" then
    -- only animals that can be played (with the discounts this action can give), as a
    -- player reads the cards: the panel offers every animal in hand, and Confirm on one that
    -- cannot be played does nothing (and ends the H20 Back offer, a dead end)
    local before = #list
    offer_choices(list, color, animal, "play animal")
    local keep = {}
    for i = before + 1, #list do
      local c = list[i]
      if M.animal_playable(player, animal, c.obj, true) then keep[#keep + 1] = c end
      list[i] = nil
    end
    for _, c in ipairs(keep) do list[#list + 1] = c end
  elseif animal ~= nil and animal.phase == "enclosure" and animal.chosen == nil then
    for _, option in ipairs(animal.options or {}) do
      local tile = player.building_tiles[option.id]
      if tile ~= nil then
        add(list, { kind = "pick_up_tile", label = "enclosure " .. tostring(option.id),
                    apply = now(function() inputs.pick_up_tile(color, tile) end) })
      end
    end
  end

  -- actions that ask for one of the player's own building tiles (on_building_tile_picked_up):
  -- every tile is offered, the ones the mod does not take change nothing and drop out
  local vacate = enclosure_vacates and enclosure_vacates[color]
  local recon = reconstruction_actions and reconstruction_actions[color]
  local expand = expand_actions and expand_actions[color]
  if (vacate ~= nil and vacate.phase == "standard" and vacate.chosen == nil)
     or (cut_down_actions and cut_down_actions[color] ~= nil)
     or (recon ~= nil and recon.phase == "select")
     or (expand ~= nil and expand.phase == "select") then
    local ids = {}
    for id in pairs(player.building_tiles or {}) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
    for _, id in ipairs(ids) do
      local tile = player.building_tiles[id]
      add(list, { kind = "pick_up_tile", label = "tile " .. tostring(id),
                  apply = now(function() inputs.pick_up_tile(color, tile) end) })
    end
  end

  offer_choices(list, color, sponsor_actions and sponsor_actions[color], "sponsor")
  offer_choices(list, color, marketing_plays and marketing_plays[color], "marketing")

  local placement = tile_placements and tile_placements[color]
  if placement ~= nil and not placement.can_confirm then
    tile_drops(list, player, placement.tile_guid, cnsts.build_tile_shapes[placement.kind], placement.opts)
  end

  local pending = player.pending_building
  if pending ~= nil and pending.dropped == nil then
    local shape = cnsts.build_tile_shapes[pending.option.search_name]
    tile_drops(list, player, pending.tile_guid, shape, pending.opts, function(cells)
      return build_placement_cost(player, cells, pending) <= get_counter_value(player.money_counter)
    end)
    for _, c in ipairs(list) do
      if c.kind == "drop_tile" then
        local apply = c.apply
        c.apply = function(done) pending.dropped = true; apply(done) end
      end
    end
  end

  if player_prompted and player_prompted[color] then
    -- dead-end actions are left out, unless nothing else would be left to do (then the AI
    -- takes its chances, as a human without a better option would)
    local buttons, any_way_on = M.buttons(active_panels[color]), false
    local dead = {}
    for i, b in ipairs(buttons) do
      dead[i] = M.dead_end(player, b)
      -- a way on: any live button but the X-token spins and Back (a multiplier's Pass counts)
      if not dead[i] and not (b.handler or ""):find("spin", 1, true) and tag_of(b.label) ~= "back" then
        any_way_on = true
      end
    end
    for i, b in ipairs(buttons) do
      if not dead[i] or not any_way_on then
        add(list, { kind = "click", label = b.label, tag = tag_of(b.label), handler = b.handler, arg = b.arg,
                    apply = now(function() inputs.click(b.handler, b.arg) end) })
      end
    end
  end

  -- labels name a choice in the driver's memory: buttons with the same text (the + and -
  -- of every row of a cube allocation) get their argument added
  local seen = {}
  for _, c in ipairs(list) do seen[c.label] = (seen[c.label] or 0) + 1 end
  for _, c in ipairs(list) do
    if seen[c.label] > 1 and c.arg ~= nil then c.label = c.label .. " [" .. c.arg .. "]" end
  end

  return list
end

-- can `obj` be played in this animal action? with_offers: count the discounts the panel
-- offers (-1 condition, the -3 conditions token) as if switched on
function M.animal_playable(player, state, obj, with_offers)
  if obj == nil then return false end
  local discounts = animal_action_discounts(state)
  if with_offers then
    discounts = {
      condition = (animal_discount_offered(state) and 1 or 0) + (animal_condition_token_offered(state) and 3 or 0),
      money = discounts.money,
    }
  end
  local pos = state.offers[obj.getGUID()]
  local ok, playable = pcall(is_animal_playable, obj.getName(), player, pos or nil, discounts)
  return ok and playable == true
end

-- the strength an action button plays at, as the mod computes it (slot, X-tokens chosen,
-- map bonuses, a constriction token: action_strength); nil for any other button
function M.strength(player, button)
  if button.handler ~= "on_action_card_button_clicked" then return nil end
  local slot = tonumber((button.arg or ""):match("_(%d+)$") or "")
  if slot == nil then return nil end
  local state = action_selection_state and action_selection_state[player.color]
  local owner = state and state.hypnosis and state.hypnosis.target or player
  local ok, s = pcall(action_strength, player, slot, state and state.x_tokens_used or 0, owner)
  return ok and s or slot
end

-- an action button that leads to a dead end, as a human could see on the map: BUILD with
-- nowhere to build at that strength. The mod only checks the money (build_action_available)
-- and then shows "Use rewind to undo this action" (build_dead_end_xml), which the AI cannot.
-- Also (Marine Worlds): a venom fee due at the end of the turn with less than 2 money: only
-- the poisoned card (using it settles the fee, use_action_card) or SPONSORS (it can earn
-- money) avoid the end-of-turn "Pay Venom Fee" panel that cannot be paid.
function M.dead_end(player, button)
  if button.handler ~= "on_action_card_button_clicked" then return false end
  local state = action_selection_state and action_selection_state[player.color]
  if player.venom_unpaid and state ~= nil and state.hypnosis == nil
     and get_counter_value(player.money_counter) < 2 then
    local slot = tonumber((button.arg or ""):match("_(%d+)$") or "")
    if slot ~= nil and not action_card_has_token(player, slot, "venom") then
      -- (an X-token from the poisoned card settles the fee too: x_token_action uses the card)
      if state.x_token_active or not (button.label or ""):upper():find("^SPONSORS") then return true end
      -- SPONSORS' money option: strength money (twice that upgraded), enough for the fee?
      local gain = (M.strength(player, button) or 0) * (player.sponsors_flipped and 2 or 1)
      if get_counter_value(player.money_counter) + gain < 2 then return true end
    end
  end
  if not (button.label or ""):upper():find("^BUILD") then return false end
  -- (X-token mode turns the card into an X-token, it does not build; a multiplier's second
  -- BUILD does build, at the card's strength)
  if state == nil or state.x_token_active then return false end
  local strength = M.strength(player, button)
  if strength == nil then return false end
  local ok, candidates = pcall(build_candidates, player,
    { upgd = player.build_flipped, num = "0", built = {}, remaining = strength })
  return ok and #candidates == 0
end

return M
