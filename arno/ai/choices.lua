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

-- what the AI sees: its panel and every choice on offer. An input that leaves this
-- unchanged was not taken in by the mod (a Confirm that cannot confirm, ...).
function M.fingerprint(player, list)
  local labels = {}
  for i, c in ipairs(list or M.list(player)) do labels[i] = c.label end
  return tostring(active_panels and active_panels[player.color]) .. "\0" .. table.concat(labels, "\0")
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
  end

  display_choices(list, color)

  local animal = animal_actions and animal_actions[color]
  if animal ~= nil and animal.phase == "pick" then
    offer_choices(list, color, animal, "play animal")
  elseif animal ~= nil and animal.phase == "enclosure" and animal.chosen == nil then
    for _, option in ipairs(animal.options or {}) do
      local tile = player.building_tiles[option.id]
      if tile ~= nil then
        add(list, { kind = "pick_up_tile", label = "enclosure " .. tostring(option.id),
                    apply = now(function() inputs.pick_up_tile(color, tile) end) })
      end
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
    for _, b in ipairs(M.buttons(active_panels[color])) do
      add(list, { kind = "click", label = b.label, tag = tag_of(b.label), handler = b.handler, arg = b.arg,
                  apply = now(function() inputs.click(b.handler, b.arg) end) })
    end
  end

  return list
end

return M
