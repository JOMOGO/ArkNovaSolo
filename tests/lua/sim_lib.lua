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
  -- only the turn (y) is kept; face up / down stays state.face_down
  o.getRotation = function() return Vector(0, state.rot_y or 180, state.face_down and 180 or 0) end
  o.setRotation = function(r) state.rot_y = Vector(r).y end
  o.setRotationSmooth = function(r) state.rot_y = Vector(r).y end
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
function sim.record(name, replacement)
  sim.calls[name] = {}
  local orig = _G[name]
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

