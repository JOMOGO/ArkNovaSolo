-- AI opponent on the BUILT Global.lua (docs/AI_OPPONENT.md, milestone M1): an AI seat plays
-- whole turns through the mod's real code, from the action choice to the end of the turn,
-- with a seeded random policy. It acts only through ai.inputs (button clicks, card and
-- tile pick-ups, tile drops), as a human does.
-- Fails on: a Lua error inside an input, a stall (the turn did not end and the AI has nothing
-- it can do), or a loop (the driver's step cap).
local T = require("tests.lib")
local NAMES = require("tests.card_names")
local OPTIONS = require("tests.options")
local driver = require("ai.driver")
local choices = require("ai.choices")
local rng = require("core.rng")

local function card_obj(n)
  return sim.fake(NAMES[n] or string.format("(%03d) Card %d", n, n))
end

-- the zoo cards of the sets in play (a base game knows no Marine Worlds card)
local function zoo_cards(mw)
  local out = {}
  for n = 101, 560 do
    local data = (mw and sim.cnsts.cards.mw[n]) or sim.cnsts.cards.base[n]
    if NAMES[n] and data and (data.type == "animal" or data.type == "sponsor" or data.type == "project") then
      out[#out + 1] = n
    end
  end
  return out
end

local function deck_of(name, numbers)
  local deck = sim.fake(name)
  deck.tag = "Deck"
  for _, n in ipairs(numbers) do deck.putObject(card_obj(n)) end
  return deck
end

local function shuffled(r, mw)
  return rng.shuffle(r, zoo_cards(mw))
end

-- one AI seat (Red) in sim.human_game, set up from the seed: money, hand, display, which
-- action cards are upgraded and where they lie
local function ai_game(seed)
  local r = rng.new(seed)
  local mw = rng.next(r) < 0.3
  local p = sim.human_game(mw, "map_A")
  p.is_ai = true
  p.turns_taken = 0
  p.steam_name = "AI"
  local order = shuffled(r, mw)
  zoo_deck = deck_of("zoo deck", order)
  discard_pile = deck_of("discard pile", { table.unpack(order, 1, 30) })
  base_conservation_deck = deck_of("base conservation deck", { 101, 102, 103, 104, 105 })
  set_counter(p.money_counter, rng.dice(r, 41) - 1, sim.cnsts.counter_style.cp)
  set_counter(p.rep_counter, rng.dice(r, 6), sim.cnsts.counter_style.cp)
  for i = 1, 6 do display_cards[i] = card_obj(order[#order - i + 1]) end
  for i = 1, rng.dice(r, 6) + 1 do card_obj(order[#order - 6 - i]).deal(1, "Red", 1) end
  local flips = { "animals_flipped", "cards_flipped", "build_flipped", "sponsors_flipped", "association_flipped" }
  for i, rec in ipairs(p.action_cards) do
    local up = rng.next(r) < 0.3
    getObjectFromGUID(rec.guid).is_face_down = up
    p[flips[i]] = up or nil
  end
  p.action_cards = rng.shuffle(r, p.action_cards)
  driver.reset(seed)
  return p
end

local failures = {}
driver.on_error = function(color, message) failures[#failures + 1] = message end

local function last_log(n)
  local out = {}
  for i = math.max(1, #driver.log - n + 1), #driver.log do out[#out + 1] = driver.log[i] end
  return table.concat(out, "\n")
end

-- plays one AI turn; returns "ended", or raises with what went wrong
local function play_turn(p)
  failures = {}
  local before = #sim.calls.end_player_turn
  local ok, err = pcall(function()
    start_player_turn(p)
    sim.pump()
  end)
  local open = active_panels.Red and active_panels.Red:match('id="(%a+)') or "none"
  if not ok then failures[#failures + 1] = tostring(err) end
  if #failures > 0 then error(failures[1] .. " (panel " .. open .. ")\n" .. last_log(12), 0) end
  if #sim.calls.end_player_turn > before then return "ended" end
  local n = #choices.list(p)
  error(string.format("stalled: panel %s, %d choices\n%s", open, n, last_log(12)), 0)
end

local SEEDS = OPTIONS.quick and 60 or 300
local outcomes, panels = {}, {}
for seed = 1, SEEDS do
  T.test("AI turn, seed " .. seed, function()
    local p = ai_game(seed)
    local ok, err = pcall(play_turn, p)
    for _, line in ipairs(driver.log) do
      local kind = line:match("^%a+ (%a[%a_]*):")
      if kind then panels[kind] = (panels[kind] or 0) + 1 end
    end
    if ok then outcomes.ended = (outcomes.ended or 0) + 1 return end
    error(err, 0)
  end)
end

local summary = {}
for k, n in pairs(panels) do summary[#summary + 1] = k .. " " .. n end
table.sort(summary)
print(string.format("AI turns ended: %d of %d; inputs: %s", outcomes.ended or 0, SEEDS, table.concat(summary, ", ")))

-- chains of turns by the same AI: the real end of turn runs (action card back to slot 1,
-- post-action rewards, multiplier, venom fee); only finish_player_turn, the hand-over to
-- the next player, is recorded. The zoo, hand and money carry over from turn to turn.
local CHAINS, CHAIN_TURNS = OPTIONS.quick and 10 or 40, 20
local chained = 0
for seed = 1, CHAINS do
  T.test("AI plays " .. CHAIN_TURNS .. " turns in a row, seed " .. seed, function()
    local p = ai_game(1000 + seed)
    sim.record("end_player_turn", function(orig, ...) return orig(...) end)
    sim.record("finish_player_turn")
    sim.record("move_action_card")
    for turn = 1, CHAIN_TURNS do
      failures = {}
      local before = #sim.calls.finish_player_turn
      local ok, err = pcall(function()
        start_player_turn(p)
        sim.pump()
      end)
      if not ok then failures[#failures + 1] = tostring(err) end
      local open = active_panels.Red and active_panels.Red:match('id="(%a+)') or "none"
      if #failures > 0 then
        error(string.format("turn %d: %s (panel %s)\n%s", turn, failures[1], open, last_log(12)), 0)
      end
      if #sim.calls.finish_player_turn ~= before + 1 then
        error(string.format("turn %d did not end: panel %s, %d choices\n%s", turn, open,
          #choices.list(p), last_log(12)), 0)
      end
      T.eq(#p.claims, 0, "turn " .. turn .. " left no claims")
      chained = chained + 1
    end
  end)
end
print(string.format("AI chained turns ended: %d of %d", chained, CHAINS * CHAIN_TURNS))

T.test("the view tells a new claim table from the same one shown again", function()
  -- seed 5100150: the Archaeologist's second pick offers the same reward in a new table
  local p = sim.human_game(false, "map_A")
  p.claims = { { { button_text = "1 X-token" } } }
  local first = choices.fingerprint(p)
  T.eq(choices.fingerprint(p), first, "the same table: the same view")
  p.claims = { { { button_text = "1 X-token" } } }
  T.ok(choices.fingerprint(p) ~= first, "a new table just like it: another view")
end)

-- ---------------------------------------------------------------- assists (policy.ASSIST)
local policy = require("ai.policy")
local net = require("ai.net")
local W = { build = 3, cp = 4 }
local ANY_TERRAIN = { upgd = true, rock = true, water = true, cover = 0 }

local function click(label, handler, arg)
  return { kind = "click", label = label, handler = handler or "on_claim_clicked", arg = arg }
end

local function card_button(p, name)
  local slot = action_card_slot_named(p, name)
  return click(string.upper(name), "on_action_card_button_clicked", "Red_" .. slot)
end

local function hand_game(numbers)
  local p = sim.human_game(false, "map_A")
  for _, n in ipairs(numbers) do card_obj(n).deal(1, "Red", 1) end
  -- the map's starting enclosures taken: no animal has an enclosure yet
  for _, tile in pairs(p.map.tiles) do
    if tile.tags.occupied == false then tile.tags.occupied = true end
  end
  return p
end

local function place(p, kind)
  local cells = p.map:findValidPlacement(sim.cnsts.build_tile_shapes[kind], { allowed = ANY_TERRAIN })
  T.ok(p.map:place(cells, { (kind:lower():gsub(" ", "_")) }, ANY_TERRAIN) ~= nil, kind .. " placed")
end

T.test("assist: a petting zoo for a petting-zoo animal in hand, no other building", function()
  local p = hand_game({ 519 })
  T.eq(policy.assist_bonus(p, click("Build a Petting Zoo"), W), 3)
  T.eq(policy.assist_bonus(p, click("Build a Size-1 Enclosure"), W), 0, "a petting animal needs the petting zoo")
  T.eq(policy.assist_bonus(p, click("Build a Reptile House"), W), 0)
  T.eq(policy.assist_bonus(p, click("Build a Kiosk"), W), 0)
  T.eq(policy.assist_bonus(p, click("Build a Kiosk (3 money)"), W), 0)
  T.eq(policy.assist_bonus(p, click("Build a Petting Zoo\n(Engineer)"), W), 3, "the Engineer's build too")
  place(p, "PETTING ZOO")
  T.eq(policy.assist_bonus(p, click("Build a Petting Zoo"), W), 0, "it has a petting zoo already")
end)

T.test("assist: an enclosure big enough, once per enclosure, conditions counted", function()
  local p = hand_game({ 408, 404 })               -- size-3 and size-2 predators, no conditions
  T.eq(policy.assist_bonus(p, click("Build a Size-3 Enclosure"), W), 3, "one enclosure houses one animal")
  T.eq(policy.assist_bonus(p, click("Build a Size-1 Enclosure"), W), 0, "too small for both")
  place(p, "SIZE 2")
  T.eq(policy.assist_bonus(p, click("Build a Size-2 Enclosure"), W), 0, "the size-2 animal has its enclosure")
  T.eq(policy.assist_bonus(p, click("Build a Size-3 Enclosure"), W), 3, "the size-3 animal has none")
  local q = hand_game({ 402 })                      -- size 4, three predator conditions unmet
  T.eq(policy.assist_bonus(q, click("Build a Size-4 Enclosure"), W), 0, "conditions far from met")
end)

T.test("assist: a reptile house for a reptile that needs one", function()
  local p = hand_game({ 470 })                       -- size 2, repthouse 1, two conditions unmet
  T.eq(policy.assist_bonus(p, click("Build a Reptile House"), W), 0, "conditions unmet")
  set_icon_counter(p.icon_counters.reptile, 1, sim.cnsts.counter_style.icon)
  T.eq(policy.assist_bonus(p, click("Build a Reptile House"), W), 1.5, "one condition short: half")
  set_icon_counter(p.icon_counters.africa, 1, sim.cnsts.counter_style.icon)
  T.eq(policy.assist_bonus(p, click("Build a Reptile House"), W), 3)
  T.eq(policy.assist_bonus(p, click("Build a Large Bird Aviary"), W), 0)
end)

T.test("assist: the BUILD action card, when such a build is affordable at its strength", function()
  local p = hand_game({ 519 })
  local strength = choices.strength(p, card_button(p, "build"))
  T.eq(strength, 3, "BUILD in slot 3")
  T.eq(policy.assist_bonus(p, card_button(p, "build"), W), 1.5, "half of the petting zoo's bonus")
  set_counter(p.money_counter, 5, sim.cnsts.counter_style.cp)
  T.eq(policy.assist_bonus(p, card_button(p, "build"), W), 0, "the petting zoo costs 6")
  T.eq(policy.assist_bonus(p, card_button(p, "build"), { build = 3, cp = 0 }), 0)
  local q = hand_game({})
  T.eq(policy.assist_bonus(q, card_button(q, "build"), W), 0, "no animal in hand")
end)

T.test("assist: ASSOCIATION when a project can be supported at its strength and a worker is free", function()
  local p = sim.human_game(false, "map_A")
  local assoc = card_button(p, "association")
  T.eq(choices.strength(p, assoc), 5)
  T.eq(policy.assist_bonus(p, assoc, W), 0, "no project on the table")
  base_projects = { { sim.fake("(102) Habitat Diversity").getGUID(), {} } }
  for i, icon in ipairs(sim.cnsts.icons.habitat) do
    set_icon_counter(p.icon_counters[icon], i <= 3 and 1 or 0, sim.cnsts.counter_style.icon)
  end
  T.eq(policy.assist_bonus(p, assoc, W), 4, "Habitat Diversity, slot 3")
  T.eq(policy.assist_bonus(p, card_button(p, "build"), W), 0, "not on other cards")
  p.deployed_workers = { { guid = "w", task = 2 } }
  T.eq(policy.assist_bonus(p, assoc, W), 0, "no worker free")
  p.deployed_workers = {}
  -- at strength 4 (ASSOCIATION in slot 4) a project is out of reach
  p.action_cards[4], p.action_cards[5] = p.action_cards[5], p.action_cards[4]
  T.eq(policy.assist_bonus(p, card_button(p, "association"), W), 0, "strength 4")
  T.eq(policy.assist_bonus(p, click("Support a Conservation Project"), W), 4, "the association panel")
  T.eq(policy.assist_bonus(p, click("Take 2 Reputation"), W), 0)
  T.eq(policy.assist_bonus(p, click("Support a Conservation Project"), { build = 3 }), 0)
end)

T.test("assist: q_scored adds the assists to the network's Q, never to a rule's choice", function()
  if not net.available() then return end
  local p = hand_game({ 519 })
  local list = { click("Build a Petting Zoo"), click("Build a Size-1 Enclosure"), click("Pay the Venom Fee") }
  local plain, assisted = policy.q_scored(p, list), policy.q_scored(p, list, nil, W)
  T.ok(math.abs(assisted[1].score - plain[1].score - 3) < 1e-9, "petting zoo + 3")
  T.ok(math.abs(assisted[2].score - plain[2].score) < 1e-9, "size 1 unchanged")
  T.eq(assisted[3].score, 1000, "the rule's score")
  T.eq(assisted[1].heuristic, plain[1].heuristic, "the hand-written score (an input) unchanged")
end)

T.finish("integration AI")
