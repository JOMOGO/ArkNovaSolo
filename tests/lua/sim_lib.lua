-- Headless simulation support for integration tests that execute the BUILT Global.lua
-- (mod + ARNO). Loaded after tts_stubs.lua and before the Global. Provides:
--   * a deterministic Wait scheduler (sim.pump runs pending callbacks / conditions)
--   * fake TTS objects with a GUID registry (getObjectFromGUID)
--   * helpers to build a minimal two-player game state (one human, ARNO)
sim = { queue = {}, objects = {}, next_guid = 1, calls = {} }

-- ---------------------------------------------------------------- scheduler
local function push(item) sim.queue[#sim.queue + 1] = item; return #sim.queue end
Wait = {
  frames = function(fn, _) return push({ fn = fn }) end,
  time = function(fn, _) return push({ fn = fn }) end,
  condition = function(fn, cond) return push({ fn = fn, cond = cond }) end,
  stop = function(id) if id and sim.queue[id] then sim.queue[id].dead = true end end,
}
function sim.pump(limit)
  limit = limit or 100000
  local steps = 0
  while true do
    local progressed = false
    for _, item in ipairs(sim.queue) do
      local ready = item.cond == nil
      if not ready and not item.dead and not item.done then
        -- as strict as TTS: a condition must return exactly one boolean
        local r = { n = select("#", item.cond()), item.cond() }
        if r.n ~= 1 or type(r[1]) ~= "boolean" then
          error("Wait.condition: condition_function does not return bool (" .. r.n .. " values)")
        end
        ready = r[1]
      end
      if not item.dead and not item.done and ready then
        item.done = true
        progressed = true
        item.fn()
        steps = steps + 1
        if steps > limit then error("sim.pump: too many callbacks (loop?)") end
        break
      end
    end
    if not progressed then return steps end
  end
end

-- ---------------------------------------------------------------- hands
-- sim.hands[color][index] lists the fakes dealt there; Player[color].getHandObjects reads it
-- when a test installs sim.hand_players()
sim.hands = {}
function sim.hand(color, index)
  index = index or 1
  sim.hands[color] = sim.hands[color] or {}
  sim.hands[color][index] = sim.hands[color][index] or {}
  return sim.hands[color][index]
end
function sim.leave_hand(obj)
  for _, by_index in pairs(sim.hands) do
    for _, hand in pairs(by_index) do
      for i = #hand, 1, -1 do
        if hand[i] == obj then table.remove(hand, i) end
      end
    end
  end
end
function sim.hand_players()
  sim.hands = {}
  return setmetatable({}, { __index = function(_, color)
    return { color = color, seated = true,
             getHandObjects = function(index) local out = {} for i, o in ipairs(sim.hand(color, index)) do out[i] = o end return out end }
  end })
end

-- ---------------------------------------------------------------- fake objects
local fake_mt = { __index = function() return function() end end }
function sim.fake(name, pos, guid)
  if guid == nil then guid = string.format("g%05d", sim.next_guid); sim.next_guid = sim.next_guid + 1 end
  local o = setmetatable({}, fake_mt)
  local state = { name = name or "Object", pos = Vector(pos or { 0, 0, 0 }), buttons = {}, tags = {},
                  contents = {}, face_down = false }
  o._s = state
  o.guid = guid
  o.tag = "Card"
  o.getGUID = function() return guid end
  o.getName = function() return state.name end
  o.setName = function(n) state.name = n end
  o.getPosition = function() return state.pos end
  o.setPosition = function(p) sim.leave_hand(o); state.pos = Vector(p) end
  o.setPositionSmooth = function(p) sim.leave_hand(o); state.pos = Vector(p) end
  o.deal = function(_, color, index)                 -- a card: into that player's hand
    sim.leave_hand(o)
    local hand = sim.hand(color, index)
    hand[#hand + 1] = o
  end
  -- the turn (y) is kept, and a roll (z) near 180 turns the object face down, as TTS reports
  -- it in is_face_down
  local function rotate(r)
    local v = Vector(r)
    state.rot_y = v.y
    state.face_down = math.abs(v.z % 360 - 180) < 90
    o.is_face_down = state.face_down
  end
  o.getRotation = function() return Vector(0, state.rot_y or 180, state.face_down and 180 or 0) end
  o.setRotation = rotate
  o.setRotationSmooth = rotate
  o.getScale = function() return Vector(1, 1, 1) end
  o.isSmoothMoving = function() return false end
  o.createButton = function(b) state.buttons[#state.buttons + 1] = b end
  o.clearButtons = function() state.buttons = {} end
  o.getButtons = function() return state.buttons end
  -- a test may give objects snap points by name (building tiles: sim.snap_points_for)
  o.getSnapPoints = function() return sim.snap_points_for and sim.snap_points_for(state.name) or {} end
  o.addTag = function(t) state.tags[t] = true end
  o.removeTag = function(t) state.tags[t] = nil end
  o.hasTag = function(t) return state.tags[t] == true end
  o.getTags = function() local out = {} for t in pairs(state.tags) do out[#out + 1] = t end return out end
  o.getObjects = function() return state.contents end
  o.takeObject = function(params)
    local at = 1
    if params and params.guid then
      for i, entry in ipairs(state.contents) do
        if entry.guid == params.guid then at = i; break end
      end
    end
    local item = table.remove(state.contents, at)
    if item == nil then error("takeObject from empty container " .. state.name) end
    local obj = sim.objects[item.guid] or sim.fake(item.name, nil, item.guid)
    if params and params.position then obj.setPosition(params.position) end
    -- as in TTS, the callback runs once the object has spawned (a later frame)
    if params and params.callback_function then
      Wait.frames(function() params.callback_function(obj) end, 1)
    end
    return obj
  end
  o.putObject = function(obj) sim.leave_hand(obj); state.contents[#state.contents + 1] = { guid = obj.getGUID(), name = obj.getName() } return o end
  o.getQuantity = function() return #state.contents end
  o.reload = function() return o end
  o.clone = function(params)
    local copy = sim.fake(state.name, params and params.position)
    for t in pairs(state.tags) do copy.addTag(t) end
    copy.setRotation((params and params.rotation) or o.getRotation())
    return copy
  end
  o.destruct = function() sim.objects[guid] = nil end
  sim.objects[guid] = o
  return o
end

-- spawnObjectData: a fake with the data's name and tags; the data is kept in o._s.data
function spawnObjectData(params)
  local o = sim.fake(params.data.Nickname, params.position)
  for _, t in ipairs(params.data.Tags or {}) do o.addTag(t) end
  o._s.data = params.data
  return o
end

function getObjectFromGUID(guid)
  if guid == nil then return nil end
  return sim.objects[guid] or sim.fake("auto " .. tostring(guid), nil, guid)
end

-- a deck whose cards are given by card numbers, e.g. { 401, 101, 228 }
function sim.deck(numbers)
  local deck = sim.fake("deck")
  deck.tag = "Deck"
  for _, n in ipairs(numbers) do
    local card = sim.fake(string.format("#%03d card %d", n, n))
    deck.putObject(card)
  end
  return deck
end

-- record calls of a global function (optionally replacing it)
-- (replacement gets the mod's own function, also when name was recorded before)
sim.originals = {}
function sim.record(name, replacement)
  sim.calls[name] = {}
  if sim.originals[name] == nil then sim.originals[name] = _G[name] or false end
  local orig = sim.originals[name] or nil
  _G[name] = function(...)
    local args = { ... }
    table.insert(sim.calls[name], args)
    if replacement then return replacement(orig, ...) end
  end
end

-- ---------------------------------------------------------------- minimal game (1 human + ARNO)
function sim.counter(v)
  local c = sim.fake("counter")
  set_counter(c, v, sim.cnsts.counter_style.cp)
  return c
end

function sim.make_player(color, is_arno)
  local p = {
    color = color, steam_name = is_arno and "ARNO" or "Human", is_arno = is_arno or nil,
    appeal_counter = sim.counter(0), cp_counter = sim.counter(0), rep_counter = sim.counter(1),
    score_counter = sim.counter(-14), money_counter = sim.counter(25), income_counter = sim.counter(5),
    appeal_token = sim.fake("appeal token"), conservation_point_token = sim.fake("cp token"),
    reputation_token = sim.fake("rep token"), player_board = sim.fake("board", { 10, 1, 0 }),
    claims = {}, acquired_partner_zoos = {}, acquired_universities = {}, worker_count = 1,
    deployed_workers = {}, played_animals = {}, persistent_rewards = {}, post_action_rewards = {},
    partial_rewards = {}, income = {}, sponsorships = {}, bonus_tiles = {}, hooks = {},
    workers = {}, map_key = "map_A", map_A = true, icon_counters = {}, engineer_builds = {}, played_sponsors = {},
  }
  for i = 1, 4 do p.workers[i] = sim.fake("worker " .. i).getGUID() end
  p.action_cards = {}
  for i, n in ipairs({ "ANIMALS 0", "CARDS 0", "BUILD 0", "SPONSORS 0", "ASSOCIATION 0" }) do
    p.action_cards[i] = { guid = sim.fake(n).getGUID(), tokens = {} }
  end
  for _, icon in ipairs(sim.cnsts.icons.all) do
    p.icon_counters[icon] = sim.fake("icon " .. icon)
    set_icon_counter(p.icon_counters[icon], 0, sim.cnsts.counter_style.icon)
  end
  return p
end

function sim.setup_game()
  sim.queue = {}
  arno_setup = { levels = { Yellow = 3 }, project_module = false }
  players = { sim.make_player("Red", false) }
  ARNO.setup.add_bots(players)
  local bot_player = players[2]
  for k, v in pairs(sim.make_player("Yellow", true)) do
    if bot_player[k] == nil then bot_player[k] = v end
  end
  local bot = arno_state.bots.Yellow
  bot.cp_debt = 5
  bot.card_slots = { slots = { "animals", "cards", "build", "sponsors", "association" }, upgraded = {} }
  bot.last_slot = 2
  current_player = bot_player
  final_scoring_discard_triggered = false
  cp_bonuses_5 = { sim.fake("tile5a", nil, "cc1325"), sim.fake("tile5b", nil, "4fb150") }
  cp_bonuses_8 = { sim.fake("tile8a", nil, "840cd1"), sim.fake("tile8b", nil, "03d9ca") }
  rep_max_bonus = nil
  marine_worlds_enabled = false
  base_projects, added_projects = {}, {}
  -- physical primitives: recorded
  sim.record("move_when_settled")
  sim.record("set_tile_face")
  sim.record("move_action_card")
  sim.record("finish_player_turn")
  sim.record("deploy_workers_to_task", function(_, p, task, n)
    p.deployed_workers[#p.deployed_workers + 1] = { guid = "w", task = task }
  end)
  sim.record("available_partner_zoos", function() return { "america", "europe", "asia", "africa", "australia" } end)
  sim.record("available_universities", function() return { "hand_size", "double_rep", "double_research" } end)
  -- take_partner_zoo as the mod does it, minus the physical tile (6865-6888)
  sim.record("take_partner_zoo", function(_, p, owner)
    p.acquired_partner_zoos[#p.acquired_partner_zoos + 1] = owner
    local i = #p.acquired_partner_zoos
    create_claims_from_reward_groups(p, { { rewards = sim.cnsts.map_data[p.map_key].partner_zoo_rewards[i] or {},
      source = "partner zoo" } }, false)
  end)
  sim.record("take_university", function(_, p, key)
    p.acquired_universities[#p.acquired_universities + 1] = key
    local i = #p.acquired_universities
    local rewards = {}
    for _, r in ipairs(sim.cnsts.map_data[p.map_key].university_rewards[i] or {}) do rewards[#rewards + 1] = r end
    for _, r in ipairs(sim.cnsts.universities[key].rewards or {}) do rewards[#rewards + 1] = r end
    create_claims_from_reward_groups(p, { { rewards = rewards, source = "university" } }, false)
  end)
  sim.record("donation_slot", function() return 2, nil end)
  sim.record("donation_12_position", function() return Vector(0, 0, 0) end)
  sim.record("donation_12_count", function() return 0 end)
  sim.record("take_player_cube", function() return sim.fake("cube") end)
  return bot_player, bot
end


-- ---------------------------------------------------------------- one human, no ARNO
-- bags like the mod's infinite ones (cubes, ...): an empty bag still gives an object
function sim.bottomless_bags(prefix)
  return setmetatable({}, { __index = function(t, k)
    local o = sim.fake(prefix .. k)
    local take = o.takeObject
    o.takeObject = function(params)
      if o.getQuantity() == 0 then o.putObject(sim.fake(prefix .. k .. " item")) end
      return take(params)
    end
    rawset(t, k, o); return o
  end })
end

-- building tiles carry "building_shape" snap points like the real ones, one per cell of
-- cnsts.build_tile_shapes, centred on the tile; single cells have none (the mod's default)
function sim.snap_points_for(name)
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

-- a game of one human (Red) on map_key (default map A), set up as setup_game and
-- apply_map_choice leave it: the real hex board with its starting tiles, the map's own player
-- attribute, project cubes, bags, hands, decks, empty display. The turn end, checkpoints
-- and worker moves are recorded, not run.
function sim.human_game(mw, map_key)
  sim.queue = {}
  local p = sim.make_player("Red", false)
  players = { p }
  arno_state = nil
  current_player = p
  marine_worlds_enabled = mw or false
  p.x_tokens = {}
  map_key = map_key or "map_A"
  p.map = sim.HexBoard.Board.new(sim.cnsts.map_data[map_key].cells)      -- apply_map_choice
  p.map_A, p.map_key = nil, map_key
  local attribute = player_map_attribute_name(map_tile_name_for(map_key) or map_key, map_key)
  if sim.cnsts.listed_map_attributes[attribute] then p[attribute] = {}
  elseif sim.cnsts.counted_map_attributes[attribute] then p[attribute] = 0
  else p[attribute] = true end
  p.building_tiles, p.pouched_cards = {}, {}
  for _, tile in pairs(p.map.tiles) do                       -- spawn_player_starting_tiles
    p.building_tiles[tile.id] = sim.fake((string.upper(tile.tags.type):gsub("_", " ")))
  end
  for _, rec in ipairs(p.action_cards) do getObjectFromGUID(rec.guid).is_face_down = false end
  p.project_cubes = {}
  for i = 1, sim.cnsts.project_cube_count do p.project_cubes[i] = sim.fake("cube " .. i).getGUID() end
  all_zoo_hooks = {}
  bags = sim.bottomless_bags("bag ")
  if p.map_geographical_zoo then spawn_player_geographical_cubes(p, p.player_board.getPosition()) end
  for _, name in ipairs({ "X-token", "Association Worker" }) do bags.tokens.putObject(sim.fake(name)) end
  for _, spec in pairs(sim.cnsts.action_card_tokens) do bags.tokens.putObject(sim.fake(spec.name)) end
  for kind in pairs(sim.cnsts.build_tile_shapes) do
    bags.sponsor_buildings.putObject(sim.fake(kind))
    bags.build_buildings.putObject(sim.fake(kind))
  end
  zoo_deck, discard_pile = sim.deck({ 401, 402, 403, 201, 202, 101 }), sim.deck({ 404, 203 })
  base_conservation_deck = sim.deck({ 101, 102, 103 })
  final_scoring_deck = sim.deck({ 1, 2, 3, 4, 5, 6, 7, 8 })
  placeholder_card = sim.fake("placeholder card")
  base_projects, added_projects = {}, {}
  cp_bonuses_5 = { sim.fake("tile5a", nil, "cc1325"), sim.fake("tile5b", nil, "4fb150") }
  cp_bonuses_8 = { sim.fake("tile8a", nil, "840cd1"), sim.fake("tile8b", nil, "03d9ca") }
  pouch_slot_count = 0
  action_selection_state = { Red = { player = p, x_tokens_used = 0, x_token_active = false } }
  association_actions, build_actions, animal_actions, sponsor_actions = {}, {}, {}, {}
  claims_players, player_prompted, player_panel_refresh, active_panels = {}, {}, {}, {}
  selection_panels, tile_placements, project_supports, reconstruction_actions = {}, {}, {}, {}
  snap_player, rep_draw_player = nil, nil
  Player = sim.hand_players()
  display_cards, display_marks = {}, {}
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
