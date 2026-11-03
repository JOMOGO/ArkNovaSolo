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
    if NAMES[n] and data and n ~= 101 and n ~= 102 and n ~= 103
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

-- turns the table's seat `color` into ARNO 3.0 at `level`, as the mod's setup does
-- (ARNO.setup.add_bots, prepare_bot): his own state, cards and CP debt; no hand, no final
-- scoring cards (ARNO holds none)
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
  for _, index in ipairs({ 1, 2 }) do
    for _, card in ipairs(Player[color].getHandObjects(index)) do put_on_discard_pile(card) end
  end
  local saved = { apply_map_choice = apply_map_choice, deal_action_cards = deal_action_cards }
  apply_map_choice, deal_action_cards = function() end, function() end   -- the table did both
  ARNO.setup.prepare_bot(seat)
  apply_map_choice, deal_action_cards = saved.apply_map_choice, saved.deal_action_cards
  return seat
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
  sim.ai_table(colors, rng.shuffle(r, M.zoo_cards(mw)), { mw = mw, names = NAMES })
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
    start_player_turn(players[1])
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
