-- Every-card test on the BUILT Global.lua: each card of cnsts.cards (base and Marine Worlds) is
-- played by a human through the mod's real code and claims engine:
--   * animals and sponsors through finish_animal_play / finish_sponsor_play;
--   * projects through the ASSOCIATION action's "support a conservation project" task, with a
--     zoo that qualifies (icons, matching played animals, all partner zoos).
-- A driver then answers whatever panel the player sees, as a player would: every claim once
-- (optional ones too) then Pass, card selections (first cards of the pool), tile placements
-- (Confirm where the mod placed the tile), snaps (first snappable display card), reputation
-- draws (from the deck) and project support (first slot, first cube).
-- Fails on: a Lua error, a stall (no panel open, turn not ended, nothing left to run), or a
-- panel the player cannot complete (a selection that cannot be confirmed, a placement that
-- cannot be confirmed or passed, a snap with nothing to snap).
local T = require("tests.lib")
local NAMES = require("tests.card_names")   -- "(217) Engineer", from the base save

local function card_obj(n)
  return sim.fake(NAMES[n] or string.format("(%03d) Card %d", n, n))
end

-- a deck of real card objects (every card number the save has, in order)
local function full_deck(name)
  local deck = sim.fake(name)
  deck.tag = "Deck"
  for n = 101, 560 do
    if NAMES[n] then deck.putObject(card_obj(n)) end
  end
  return deck
end

-- building tiles carry "building_shape" snap points like the real ones, one per cell of
-- cnsts.build_tile_shapes, centred on the tile; single cells have none (the mod's default)
sim.snap_points_for = function(name)
  local shape = sim.cnsts.build_tile_shapes[name]
  if shape == nil or #shape < 2 then return {} end
  local locals, cx, cz = {}, 0, 0
  for i, cell in ipairs(shape) do
    locals[i] = cell_local_position(cell)
    cx, cz = cx + locals[i].x, cz + locals[i].z
  end
  cx, cz = cx / #shape, cz / #shape
  local out = {}
  for i, l in ipairs(locals) do
    out[i] = { position = Vector(l.x - cx, 0, l.z - cz), tags = { "building_shape" } }
  end
  return out
end

local DISPLAY = { 486, 476, 220, 223, 101, 488 }   -- size-1 and size-3 animal, sponsors, project
local HAND = { 484, 205, 102 }                     -- an animal, a sponsor, a project

local function human_game(mw)
  sim.queue = {}
  local p = sim.make_player("Red", false)
  players = { p }
  arno_state = nil
  current_player = p
  marine_worlds_enabled = mw
  p.x_tokens = {}
  -- the fields apply_map_choice sets (6604), with the real hex board of map A
  p.map = HexBoard.Board.new(sim.cnsts.map_data.map_A.cells)
  p.building_tiles, p.pouched_cards = {}, {}
  for _, tile in pairs(p.map.tiles) do                -- spawn_player_starting_tiles (6636)
    p.building_tiles[tile.id] = sim.fake(string.upper(tile.tags.type):gsub("_", " "))
  end
  for _, rec in ipairs(p.action_cards) do getObjectFromGUID(rec.guid).is_face_down = false end
  p.project_cubes = {}
  for i = 1, sim.cnsts.project_cube_count do p.project_cubes[i] = sim.fake("cube " .. i).getGUID() end
  all_zoo_hooks = {}
  local function lazy(prefix)
    return setmetatable({}, { __index = function(t, k)
      -- like the mod's infinite bags (cubes, ...): an empty bag still gives an object
      local o = sim.fake(prefix .. k)
      local take = o.takeObject
      o.takeObject = function(params)
        if o.getQuantity() == 0 then o.putObject(sim.fake(prefix .. k .. " item")) end
        return take(params)
      end
      rawset(t, k, o); return o
    end })
  end
  bags = lazy("bag ")
  for _, name in ipairs({ "X-token", "Association Worker" }) do bags.tokens.putObject(sim.fake(name)) end
  for _, spec in pairs(sim.cnsts.action_card_tokens) do bags.tokens.putObject(sim.fake(spec.name)) end
  for kind in pairs(sim.cnsts.build_tile_shapes) do
    bags.sponsor_buildings.putObject(sim.fake(kind))
    bags.build_buildings.putObject(sim.fake(kind))
  end
  zoo_deck, discard_pile = full_deck("zoo deck"), full_deck("discard pile")
  base_conservation_deck = full_deck("base conservation deck")
  final_scoring_deck = sim.deck({ 1, 2, 3, 4, 5, 6, 7, 8 })
  placeholder_card = sim.fake("placeholder card")
  base_projects, added_projects = {}, {}
  cp_bonuses_5 = { sim.fake("tile5a", nil, "cc1325"), sim.fake("tile5b", nil, "4fb150") }
  cp_bonuses_8 = { sim.fake("tile8a", nil, "840cd1"), sim.fake("tile8b", nil, "03d9ca") }
  pouch_slot_count = 0
  set_counter(p.money_counter, 100, sim.cnsts.counter_style.cp)
  action_selection_state = { Red = { player = p, x_tokens_used = 0, x_token_active = false } }
  association_actions, build_actions, animal_actions, sponsor_actions = {}, {}, {}, {}
  claims_players, player_prompted, player_panel_refresh, active_panels = {}, {}, {}, {}
  selection_panels, tile_placements, project_supports = {}, {}, {}
  snap_player, rep_draw_player = nil, nil
  Player = sim.hand_players()
  display_cards, display_marks = {}, {}
  for i, n in ipairs(DISPLAY) do display_cards[i] = card_obj(n) end
  for _, n in ipairs(HAND) do card_obj(n).deal(1, "Red", 1) end
  zones = setmetatable({}, { __index = function(t, k)
    local z = sim.fake("zone " .. k)
    z.getObjects = function() return {} end
    rawset(t, k, z); return z
  end })
  sim.record("end_player_turn")
  sim.record("take_checkpoint")
  sim.record("deploy_workers_to_task", function(_, pl, task)
    pl.deployed_workers[#pl.deployed_workers + 1] = { guid = "w", task = task }
  end)
  return p
end

local function play(p, number, card)
  local obj = card_obj(number)
  if card.type == "animal" then
    animal_actions.Red = { selected = obj, card = card, cost = 0, strength = 5, num = "1",
                           offers = {}, chosen = {} }
    finish_animal_play(p)
  else
    sponsor_actions.Red = { remaining = 10 }
    finish_sponsor_play(p, obj, nil, nil)
  end
end

-- a zoo that qualifies for project `card`: every icon 10 times, all partner zoos, and played
-- animals of every size that match it (release, breeding, large / small)
local function qualify_for_project(p, card, set)
  for _, counter in pairs(p.icon_counters) do set_icon_counter(counter, 10, sim.cnsts.counter_style.icon) end
  p.acquired_partner_zoos = { "africa", "america", "asia", "australia", "europe" }
  local by_size = {}
  for n = 401, 560 do
    local data = (set == "mw" and sim.cnsts.cards.mw[n]) or sim.cnsts.cards.base[n]
    if data and data.type == "animal" and NAMES[n] and by_size[data.size] == nil then
      local fits = (card.match == "large" and data.size >= 4) or (card.match == "small" and data.size <= 2)
        or card_matches_search_key(data, card.match)
      if fits then by_size[data.size] = n end
    end
  end
  for _, n in pairs(by_size) do
    table.insert(p.played_animals, card_obj(n).getGUID())
  end
end

local function visible_panel()
  local xml = player_prompted.Red and active_panels.Red
  return xml and xml:match('id="(%a+)')
end

local answered = {}   -- panel id -> times the driver answered it, over all cards

-- answers panels until the turn ends; returns "ended" or "panel <id>" (one it cannot answer)
local function drive(p, opts)
  opts = opts or {}
  local clicked = {}
  for _ = 1, 300 do
    sim.pump()
    if #sim.calls.end_player_turn > 0 then return "ended" end
    local panel = visible_panel()
    if panel then answered[panel] = (answered[panel] or 0) + 1 end

    if panel == "claimsPanel" then
      local sub_table, pick = p.claims[#p.claims], nil
      for i, claim in ipairs(sub_table) do
        if not clicked[claim] and opts.first_claim and resolve_claim_text(claim) == opts.first_claim then
          pick = i
        end
      end
      for i, claim in ipairs(sub_table) do
        if pick == nil and not clicked[claim] then pick = i end
      end
      if pick then
        clicked[sub_table[pick]] = true
        on_claim_button_clicked(nil, "Red_" .. pick, nil)
      else
        on_claim_pass_clicked(nil, "Red", nil)
      end

    elseif panel == "selectionPanel" then
      local state = selection_panels.Red
      for i = 1, math.min(state.num, #state.pool) do onObjectPickUp("Red", state.pool[i]) end
      if selection_ready(state) then
        on_card_selection_confirm_clicked(nil, "Red", nil)
      elseif active_panels.Red:find("on_card_selection_cancel_clicked", 1, true) then
        on_card_selection_cancel_clicked(nil, "Red", nil)    -- "up to" choices: Back / Pass
      else
        error(string.format("selection '%s' cannot be confirmed: %d cards for %d",
                            state.action, #state.pool, state.num))
      end

    elseif panel == "tilePlacementPanel" then
      local state = tile_placements.Red
      if state.can_confirm then
        answered["tile confirmed"] = (answered["tile confirmed"] or 0) + 1
        on_tile_placement_confirm_clicked(nil, "Red", nil)
      elseif state.config.allow_pass then
        on_tile_placement_pass_clicked(nil, "Red", nil)
      else
        error("tile placement of " .. tostring(state.kind) .. " can be neither confirmed nor passed")
      end

    elseif panel == "snapPrompt" then
      local slot
      for i = 1, 6 do if slot == nil and snappable_display_card(i) then slot = i end end
      if slot == nil then error("snap prompt with nothing to snap") end
      onObjectPickUp("Red", display_cards[slot])

    elseif panel == "sharkAttackPrompt" then
      local slot
      for i = 1, 6 do
        if slot == nil and display_cards[i] and shark_attack_state.lookup[display_cards[i].getGUID()] then slot = i end
      end
      if slot == nil then error("shark attack prompt with nothing to attack") end
      onObjectPickUp("Red", display_cards[slot])

    elseif panel == "repDrawPrompt" then
      on_placeholder_card_picked_up({ color = "Red" })

    elseif panel == "projectSupportPanel" then
      local state = project_supports.Red
      if state.chosen == nil then
        local pick = 1
        for i, offer in ipairs(state.offers) do
          if opts.project and offer.obj == opts.project then pick = i end
        end
        if state.offers[pick] == nil then error("project support with nothing to support") end
        on_project_support_project_clicked(nil, "Red|" .. pick, nil)
      elseif state.chosen.card.project == "release" and state.slot == nil then
        on_project_support_animal_clicked(nil, "Red|1", nil)
      elseif state.slot == nil then
        on_project_support_slot_clicked(nil, "Red|" .. state.chosen.slots[1].slot, nil)
      else
        local cube
        for i = 1, sim.cnsts.project_cube_count do
          if cube == nil and p.project_cubes[i] ~= nil then cube = i end
        end
        on_project_support_cube_clicked(nil, "Red|" .. cube, nil)
      end

    elseif panel == "cardFlipPanel" then
      local slot
      for i = 1, 5 do
        if slot == nil and not action_card_upgraded(action_card_object(p, i)) then slot = i end
      end
      on_card_flip_clicked(nil, "Red_" .. slot, nil)

    elseif panel == "diggingPanel" then
      if digging_selected == nil and not clicked.digging then
        clicked.digging = true
        onObjectPickUp("Red", display_cards[1])
      elseif digging_selected ~= nil then
        on_digging_confirm_clicked(nil, "Red", nil)
      else
        on_digging_pass_clicked(nil, "Red", nil)
      end

    elseif panel ~= nil then
      -- any other panel: its Pass / Back button, as a player not taking the option would
      local handler, arg
      for fn, a, label in active_panels.Red:gmatch('onClick="([%w_]+)%(([^)]*)%)"[^>]*>%s*([^<]-)%s*</Button>') do
        if handler == nil and (label == "Pass" or label == "Back" or label:find("^Back to")) then
          handler, arg = fn, a
        end
      end
      if handler == nil then return "panel " .. panel end
      _G[handler](nil, arg, nil)
    else
      error("stalled: no panel open and the turn did not end")
    end
  end
  error("driver: more than 300 panels (loop?)")
end

-- bugs in the base mod this test found; the test checks they still fail the same way, so it
-- says when one gets fixed (then remove it here)
-- (found and fixed so far: mw #138, "reef effect" had no handler, FIX138)
local KNOWN = {}

local outcomes = {}
local function count(outcome) outcomes[outcome] = (outcomes[outcome] or 0) + 1 end

local function card_test(id, name, fn)
  if KNOWN[id] == nil then return T.test(name, fn) end
  T.test(name .. " (known base-mod bug)", function()
    local ok, err = pcall(fn)
    T.ok(not ok, "now passes: remove it from KNOWN")
    T.ok(tostring(err):find(KNOWN[id], 1, true) ~= nil, "fails differently now: " .. tostring(err))
  end)
end

for _, set in ipairs({ "base", "mw" }) do
  local numbers = {}
  for n in pairs(sim.cnsts.cards[set]) do numbers[#numbers + 1] = n end
  table.sort(numbers)
  for _, n in ipairs(numbers) do
    local card = sim.cnsts.cards[set][n]
    if card.type == "animal" or card.type == "sponsor" then
      card_test(string.format("%s #%03d", set, n), string.format("%s #%03d (%s) plays to the end of the turn", set, n, card.type), function()
        local p = human_game(set == "mw")
        play(p, n, card)
        count(drive(p))
      end)
    elseif card.type == "project" then
      card_test(string.format("%s #%03d", set, n), string.format("%s #%03d (project) is supported to the end of the turn", set, n), function()
        local p = human_game(set == "mw")
        qualify_for_project(p, card, set)
        local obj = card_obj(n)
        obj.deal(1, "Red", 1)
        start_association_action(p, 5, "0")
        count(drive(p, { first_claim = sim.cnsts.association_tasks[5].label, project = obj }))
        T.eq(#added_projects, 1, "the project joined the row")
        T.eq(p.project_cubes[1], nil, "a project cube was used")
      end)
    end
  end
end

local summary = {}
for outcome, n in pairs(outcomes) do summary[#summary + 1] = outcome .. " " .. n end
table.sort(summary)
print("every card: " .. table.concat(summary, ", "))
local panels = {}
for id, n in pairs(answered) do panels[#panels + 1] = id .. " " .. n end
table.sort(panels)
print("panels answered: " .. table.concat(panels, ", "))

T.test("FIX138: Sea Animal Management Plan's left slot carries out every reef effect", function()
  local p = human_game(true)
  set_icon_counter(p.icon_counters.sea, 2, sim.cnsts.counter_style.icon)
  for _, n in ipairs({ 530, 534, 535 }) do                -- reef: 2 appeal, 3 money, none ("")
    table.insert(p.played_animals, card_obj(n).getGUID())
  end
  local sources = {}
  sim.record("apply_reward_string", function(orig, player, reward, source)
    if tostring(source):find("reef effect", 1, true) then sources[#sources + 1] = reward end
    return orig(player, reward, source)
  end)
  local obj = card_obj(138)
  obj.deal(1, "Red", 1)
  start_association_action(p, 5, "0")
  T.eq(drive(p, { first_claim = sim.cnsts.association_tasks[5].label, project = obj }), "ended")
  table.sort(sources)
  T.eq(sources, { "2 appeal", "3 money" }, "the reef effects of both reef animals")
end)

T.finish("integration every card")
