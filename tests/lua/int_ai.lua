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

-- final scoring card assist (final): the card held, read smoothly between its thresholds
local function final_card(p, n) card_obj(n).deal(1, p.color, 2) end
local FW = { build = 0, cp = 0, final = 3 }

T.test("assist final: a card play that moves the own final scoring card, read between thresholds", function()
  local p = hand_game({})
  local research_sponsor = sim.cnsts.cards.base[201]
  T.eq(policy.final_gain(p, research_sponsor), 0, "no final scoring card held")
  final_card(p, 3)                                   -- research icons: 3 / 4 / 5 / 6 for 1-4 CP
  T.ok(math.abs(policy.final_gain(p, research_sponsor) - 1 / 3) < 1e-9, "a third of the way to 3 icons")
  set_icon_counter(p.icon_counters.research, 3, sim.cnsts.counter_style.icon)
  T.ok(math.abs(policy.final_gain(p, research_sponsor) - 1) < 1e-9, "3 -> 4 icons: 1 CP more")
  T.eq(policy.final_gain(p, sim.cnsts.cards.base[404]), 0, "no research icon")
  set_icon_counter(p.icon_counters.research, 6, sim.cnsts.counter_style.icon)
  T.eq(policy.final_gain(p, research_sponsor), 0, "the card's 4 CP reached")
end)

T.test("assist final: the best card held counts; the bonus on the card choices and the action card", function()
  local p = hand_game({})
  final_card(p, 1)                                   -- large animals: 1 / 2 / 4 / 5
  final_card(p, 4)                                   -- map tests (no count): not moved by a card
  T.eq(policy.final_gain(p, sim.cnsts.cards.base[401]), 1, "size 5: a large animal")
  T.eq(policy.final_gain(p, sim.cnsts.cards.base[404]), 0, "size 2")
  T.eq(policy.smooth_award(sim.cnsts.final_scoring_cards.base[1], 3), 2.5)
  T.eq(policy.smooth_award(sim.cnsts.final_scoring_cards.base[11], 3), 1.5, "water icons / 2")
  T.eq(policy.smooth_award(sim.cnsts.final_scoring_cards.base[5], 9), 4, "at most 4")
  local lion = "play animal: " .. card_obj(401).getName()
  T.eq(policy.assist_bonus(p, { kind = "pick_up", label = lion }, FW), 3 * 1 * 2, "3 x 1 CP x 2 points")
  T.eq(policy.assist_bonus(p, { kind = "pick_up", label = lion }, W), 0, "final off")
  T.eq(policy.assist_bonus(p, { kind = "pick_up", label = "select: " .. card_obj(401).getName() }, FW), 0,
       "only a play counts")
  T.eq(policy.assist_bonus(p, card_button(p, "build"), FW), 0, "not on BUILD")
end)

T.test("assist final: the final scoring discard keeps the card that scores more", function()
  local p = hand_game({})
  final_card(p, 1)                                   -- large animals: none, 0 CP
  final_card(p, 7)                                   -- reputation 9: 2 CP
  set_counter(p.rep_counter, 9, sim.cnsts.counter_style.score)
  local large, rep = "select: " .. card_obj(1).getName(), "select: " .. card_obj(7).getName()
  T.eq(policy.assist_bonus(p, { kind = "pick_up", label = rep }, FW), 0, "no discard panel open")
  selection_panels = { Red = { action = "final scoring discard", selected = {}, num = 1, pool = {} } }
  T.eq(policy.assist_bonus(p, { kind = "pick_up", label = rep }, FW), -3 * 2 * 2, "discarding 2 CP")
  T.eq(policy.assist_bonus(p, { kind = "pick_up", label = large }, FW), 0, "discarding 0 CP")
  T.eq(policy.assist_bonus(p, { kind = "pick_up", label = rep }, W), 0, "final off")
  selection_panels = {}
end)

-- end-timing assist (ending)
local EW = { build = 0, cp = 0, ending = 5 }

local function end_game(own, other)
  local p = sim.human_game(false, "map_A")
  local q = sim.make_player("Blue", false)
  players = { p, q }
  set_counter(p.score_counter, own, sim.cnsts.counter_style.score)
  set_counter(q.score_counter, other, sim.cnsts.counter_style.score)
  -- ASSOCIATION at strength 5 can support Habitat Diversity: about 3 CP (6 points) at once
  base_projects = { { sim.fake("(102) Habitat Diversity").getGUID(), {} } }
  for i, icon in ipairs(sim.cnsts.icons.habitat) do
    set_icon_counter(p.icon_counters[icon], i <= 3 and 1 or 0, sim.cnsts.counter_style.icon)
  end
  return p, q
end

T.test("assist ending: an action that ends a game it would then lose", function()
  game_end_triggered = false
  local p = end_game(95, 95)
  local assoc = card_button(p, "association")
  -- own 95 + 6 = 101 ends it; the other: 95 + 1.5 CP (3) + its last turn (6) = 104: 3 short
  T.eq(policy.assist_bonus(p, assoc, EW), -3)
  T.eq(policy.assist_bonus(p, assoc, { build = 0, cp = 0, ending = 2 }), -2, "at most the weight")
  T.eq(policy.assist_bonus(p, card_button(p, "cards"), EW), 0, "CARDS does not end it")
  T.eq(policy.assist_bonus(p, assoc, W), 4, "ending off: the cp assist alone")
  final_card(p, 7)                                   -- reputation 6 / 9 / 12 / 15: 1 rep, 0 CP
  set_counter(p.rep_counter, 9, sim.cnsts.counter_style.score)
  T.eq(policy.assist_bonus(p, assoc, EW), 0, "own final scoring card: 2 CP (4 points), ahead")
  game_end_triggered = true
  local q = end_game(95, 95)
  T.eq(policy.assist_bonus(q, card_button(q, "association"), EW), 0, "the end already triggered")
  game_end_triggered = false
  local r = end_game(80, 95)
  T.eq(policy.assist_bonus(r, card_button(r, "association"), EW), 0, "does not reach 100")
  local s2 = end_game(99, 60)
  T.eq(policy.assist_bonus(s2, card_button(s2, "association"), EW), 0, "far ahead")
  local t2 = end_game(95, 140)
  T.eq(policy.assist_bonus(t2, card_button(t2, "association"), EW), 0, "lost by more than END_RANGE anyway")
end)

T.test("assist ending: ARNO's final scoring tokens (less his CP debt) count", function()
  game_end_triggered = false
  local p, q = end_game(95, 90)
  q.is_arno = true
  -- 90 + 6 (last turn) + 1.5 CP (3) = 99 < 101: fine without ARNO's tokens
  T.eq(policy.assist_bonus(p, card_button(p, "association"), EW), 0)
  arno_state = { bots = { Blue = { tokens_scoring = 5, tokens_notepad = 2, cp_debt = 1 } } }
  -- 3 + 2 - 1 = 4 CP = 8 points: 90 + 8 + 6 = 104, 3 short
  T.eq(policy.final_points(q, false), 8)
  T.eq(policy.assist_bonus(p, card_button(p, "association"), EW), -3)
  arno_state = nil
end)

-- conditions met (unlock)
local UW = { build = 0, cp = 0, unlock = 3 }
local function flip(name) return click(name, "on_card_flip_clicked") end

T.test("assist unlock: the ANIMALS / SPONSORS upgrade for hand cards that need it", function()
  local p = hand_game({ 421, 403 })                  -- New Zealand Fur Seal (upgrade), Leopard (africa partner)
  T.eq(policy.assist_bonus(p, flip("ANIMALS"), UW), 3, "the upgrade animal")
  T.eq(policy.assist_bonus(p, flip("SPONSORS"), UW), 0, "no sponsor needs it")
  T.eq(policy.assist_bonus(p, flip("CARDS"), UW), 0)
  T.eq(policy.assist_bonus(p, flip("ANIMALS"), W), 0, "unlock off")
  T.eq(policy.assist_bonus(p, click("ANIMALS"), UW), 0, "only the flip, not another button")
  p.animals_flipped = true
  T.eq(policy.assist_bonus(p, flip("ANIMALS"), UW), 0, "already met")
  local q = hand_game({ 207, 426, 431 })             -- Basic Research (upgrade, max 25 appeal); 2 elephants (upgrade)
  T.eq(policy.assist_bonus(q, flip("SPONSORS"), UW), 3, "the sponsor's last unmet condition")
  T.eq(policy.assist_bonus(q, flip("ANIMALS"), UW), 6, "two animals")
end)

T.test("assist upgrade: the ANIMALS upgrade first", function()
  local p = hand_game({})
  local GW = { build = 0, cp = 0, upgrade = 0.5 }
  T.eq(policy.assist_bonus(p, flip("ANIMALS"), GW), 0.5)
  T.eq(policy.assist_bonus(p, flip("CARDS"), GW), 0)
  T.eq(policy.assist_bonus(p, click("ANIMALS"), GW), 0, "not the action card")
  T.eq(policy.assist_bonus(p, flip("ANIMALS"), W), 0, "upgrade off")
  local q = hand_game({ 421 })
  T.eq(policy.assist_bonus(q, flip("ANIMALS"), { unlock = 3, upgrade = 0.5 }), 3.5, "both")
end)

T.test("assist unlock: a partner zoo or university that meets an animal's condition", function()
  local p = hand_game({ 403, 501 })                  -- africa partner; asia icon
  T.eq(policy.assist_bonus(p, click("Africa Partner Zoo"), UW), 3)
  T.eq(policy.assist_bonus(p, click("Asia Partner Zoo"), UW), 3, "its continent icon")
  T.eq(policy.assist_bonus(p, click("Europe Partner Zoo"), UW), 0)
  local saved = available_partner_zoos            -- the human test table has no partner zoo tiles
  available_partner_zoos = function() return { "europe", "asia" } end
  T.eq(policy.assist_bonus(p, click("Take a Partner Zoo"), UW), 3, "the best on offer")
  available_partner_zoos = function() return { "europe" } end
  T.eq(policy.assist_bonus(p, click("Take a Partner Zoo"), UW), 0, "none on offer helps")
  available_partner_zoos = saved
  T.eq(policy.assist_bonus(p, click("Take a University"), UW), 0, "no university helps")
  local q = hand_game({ 425, 427 })                  -- two animals that need a research icon
  T.eq(policy.assist_bonus(q, click("Double Research University"), UW), 6, "both")
  T.eq(policy.assist_bonus(q, click("Double Reputation University"), UW), 6, "its research icon")
  T.eq(policy.assist_bonus(q, click("Hand Size University"), UW), 0, "no research icon")
  local saved_uni = available_universities
  available_universities = function() return { "hand_size", "double_rep" } end
  T.eq(policy.assist_bonus(q, click("Take a University"), UW), 6, "the best on offer")
  T.eq(policy.assist_bonus(q, click("Take a University"), W), 0, "unlock off")
  available_universities = saved_uni
end)

T.finish("integration AI")
