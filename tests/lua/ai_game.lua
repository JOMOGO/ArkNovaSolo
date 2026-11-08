-- Shared by the AI suites (module "tests.ai_game"): plays one whole game of AI seats on the
-- built Global.lua through sim.ai_table and the real game loop.
local NAMES = require("tests.card_names")
local driver = require("ai.driver")
local choices = require("ai.choices")
local rng = require("core.rng")

local M = {}

function M.zoo_cards(mw)
  local out = {}
  for n = 101, 560 do
    local data = (mw and sim.cnsts.cards.mw[n]) or sim.cnsts.cards.base[n]
    -- (the base projects 101-112 are not in the zoo deck: setup puts them on the board or in
    -- the base conservation deck; so does Marine Worlds' 133, in its conservation deck)
    if NAMES[n] and data and n > 112 and not (mw and n == 133)
       and (data.type == "animal" or data.type == "sponsor" or data.type == "project") then
      out[#out + 1] = n
    end
  end
  return out
end

local failures = {}
driver.on_error = function(color, message) failures[#failures + 1] = color .. ": " .. message end

function M.last_log(n)
  local out = {}
  for i = math.max(1, #driver.log - n + 1), #driver.log do out[#out + 1] = driver.log[i] end
  return table.concat(out, "\n")
end

function M.panels()
  local out = {}
  for _, p in ipairs(players) do
    local id = active_panels[p.color] and active_panels[p.color]:match('id="(%a+)') or "none"
    out[#out + 1] = string.format("%s %s (%d choices)", p.color, id, #choices.list(p))
  end
  return table.concat(out, ", ")
end

-- Marine Worlds (setup_game): the base bonus tile bag without "PLAY A SPONSOR FOR MONEY"
-- (d60a8e) plus the 7 MW tiles of bag 34014b
local BASE_TILES = { "1e8ab9", "14dcd6", "03d9ca", "4fb150", "840cd1", "cc1325", "7dab5a", "d60a8e", "7cd38f" }
local MW_TILES = { "1e8ab9", "14dcd6", "03d9ca", "4fb150", "840cd1", "cc1325", "7dab5a", "7cd38f",
                   "ad7da7", "1e423c", "131044", "eef749", "b0e527", "83f88a", "baace5" }

-- turns the table's seat `color` into ARNO 3.0 at `level`, as the mod's setup does
-- (ARNO.setup.add_bots, prepare_bot): his own state, cards and CP debt; no hand, no final
-- scoring cards (ARNO holds none; sim.ai_table deals him none: opts.no_cards). His setup
-- draw comes at start_game (M.arno_setup_cards, the H8 step).
function M.seat_arno(color, level, seed)
  local seat
  for _, p in ipairs(players) do if p.color == color then seat = p end end
  arno_setup = { levels = { [color] = level }, ai = {}, project_module = false }
  local others = {}
  for _, p in ipairs(players) do if p ~= seat then others[#others + 1] = p end end
  ARNO.setup.add_bots(others)
  -- ARNO's own random stream from the game's seed (add_bots takes the clock): a game replays
  local s = math.floor((seed or 0) * 2654435761) % 4294967296
  arno_state.seed = string.format("%08x", s)
  arno_state.rng = { hi = math.floor(s / 65536), lo = s % 65536 }
  for k, v in pairs(others[#others]) do seat[k] = v end
  seat.is_ai = nil
  local saved = { apply_map_choice = apply_map_choice, deal_action_cards = deal_action_cards }
  apply_map_choice, deal_action_cards = function() end, function() end   -- the table did both
  ARNO.setup.prepare_bot(seat)
  apply_map_choice, deal_action_cards = saved.apply_map_choice, saved.deal_action_cards
  return seat
end

-- ARNO's setup draw at start_game (H8, rules p3), after the players' setup discards: 8 zoo
-- cards, keeps up to 2 projects on his mat, the rest onto the discard pile, one face-down
-- final scoring card
function M.arno_setup_cards()
  local apply = require("adapter.apply")
  apply.last_discard_pile = discard_pile
  apply.deal_bot_setup_cards(ARNO.setup.bots(players), function() end)
  apply.last_discard_pile = nil
end

-- the setup discard as on the table (start_setup_discard): every AI seat keeps 4 of its 8
-- cards by its own policy on the real panel (ai.choices: pick 4 up, then Confirm). ARNO
-- sits it out (setup.open_window / close_window, as H5-H8 do) and draws at start_game.
-- M.setup_discards[color]: how many cards the seat discarded (for the reports)
M.setup_discards = {}
local function setup_discard()
  M.setup_discards = {}
  game_started = false
  local arno = arno_state ~= nil and ARNO.setup.bots(players)[1] ~= nil
  if arno then ARNO.setup.open_window() end
  sim.on_start_game = function()
    for _, p in ipairs(players) do
      local n = #Player[p.color].getHandObjects(1)
      if n ~= 4 then error(string.format("setup discard: %s keeps %d cards", p.color, n), 0) end
    end
    if arno then
      ARNO.setup.close_window()
      M.arno_setup_cards()
    end
  end
  sim.record("on_setup_discard_clicked", function(orig, obj, color, ...)
    local state = setup_discard_state and setup_discard_state[color]
    if state and not state.confirmed then M.setup_discards[color] = #state.selected end
    -- the driver counts inputs per view (choices.fingerprint, no colour in it) until a turn
    -- starts; here all seats act before any turn, and 4 seats with the same view at their
    -- Confirm would make the 4th one's a "loop" (MAX_REPEATS 3). The table has at most 3 AI
    -- seats next to a human; headless games can have 4: start each Confirm fresh.
    driver.tried, driver.rejected = {}, {}
    return orig(obj, color, ...)
  end)
  start_setup_discard()
  for _, p in ipairs(players) do
    if p.is_ai then driver.wake(p.color) end
  end
end

-- plays one game; returns outcome ("scored", "turn cap", "deck ran out"), turns, scores
-- (by colour). Raises on a Lua error, a stall or a driver loop.
-- policies: color -> policy (driver.policies); others play the seeded random policy
function M.play(seed, opts)
  opts = opts or {}
  local colors = opts.colors or { "Red", "Blue" }
  local mw = opts.mw or false
  local cap = opts.cap or 250 * #colors
  local r = rng.new(seed)
  local zoo = rng.shuffle(r, M.zoo_cards(mw))
  -- the final scoring cards shuffled too (they were dealt 1, 2 / 3, 4 in every game: the
  -- network saw 4 of the 11, found in round 17)
  -- (Marine Worlds: 1, 3, 5, 8-11 replaced by their MW cards, 12-17 added; sim.ai_table takes
  -- 9 and 17 out, as setup_game does without interactive effects)
  local final_scoring = rng.shuffle(r, mw and { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
                                           or { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 })
  -- the base projects (setup_game shuffles the base conservation deck and lays out 3, or 4;
  -- MW: 101 and 102 replaced, 133 added) and the 5/8-CP bonus tiles (the first 4 of the
  -- shuffled bag 1c73d4; MW: that bag as setup_game changes it, and a 5th tile drawn for the
  -- end of the reputation track)
  local projects = rng.shuffle(r, mw and { 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 133 }
                                      or { 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112 })
  local tiles = rng.shuffle(r, mw and MW_TILES or BASE_TILES)
  -- every AI seat is dealt 8 cards and keeps 4 (setup_discard); the discard pile starts empty
  sim.ai_table(colors, zoo, { mw = mw, names = NAMES, final_scoring = final_scoring,
                              base_projects = projects, bonus_tiles = tiles, hand = 8, discards = 0,
                              no_cards = opts.arno and { [opts.arno.color] = true } or nil })
  if opts.arno then M.seat_arno(opts.arno.color, opts.arno.level, seed) end
  driver.reset(seed)
  for color, make in pairs(opts.policies or {}) do driver.policies[color] = make(seed) end
  failures = {}
  local turns = 0
  sim.record("start_player_turn", function(orig, player, ...)
    turns = turns + 1
    if turns > cap then return end                 -- stop the game here
    return orig(player, ...)
  end)
  local ok, err = pcall(function()
    setup_discard()                      -- start_game then starts the first turn
    sim.pump(10000000)
  end)
  if not ok then failures[#failures + 1] = tostring(err) end
  local scores = {}
  for _, p in ipairs(players) do scores[p.color] = get_counter_value(p.score_counter) end
  -- the mod never reshuffles the zoo deck; a random policy can draw it empty in a very
  -- long game (a real one ends long before)
  if #failures > 0 and zoo_deck.getQuantity() < 8 then return "deck ran out", turns, scores end
  if #failures > 0 then
    error(string.format("turn %d: %s\n%s\n%s", turns, failures[1], M.panels(), M.last_log(14)), 0)
  end
  if #sim.calls.announce_winner > 0 then return "scored", turns, scores end
  if turns > cap then return "turn cap", turns, scores end
  error(string.format("stalled at turn %d: %s\n%s", turns, M.panels(), M.last_log(14)), 0)
end

return M
