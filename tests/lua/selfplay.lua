-- Self-play for training (docs/AI_OPPONENT.md §4a), run by tools/ai_train.py (not part of the
-- test suite). Plays whole games on the built Global.lua and prints one line per decision
-- with two or more choices:
--   D|<seed>|<color>|<margin now>|<inputs, comma separated>|<own score now>
-- and per seat at the end:
--   E|<seed>|<color>|<final margin>|<outcome>
-- margin = own score minus the best other score. The trainer's target for a decision is
-- final margin minus margin now. Options (module "tests.selfplay_options"):
--   { from, to, seats = { { policy = "heuristic" | "network", budget = n }, ... }, mw_every }
local game = require("tests.ai_game")
local OPTS = require("tests.selfplay_options")
local policy = require("ai.policy")
local features = require("ai.features")
local driver = require("ai.driver")
local rng = require("core.rng")

local COLORS = { "Red", "Blue", "Yellow", "White" }

local function margin(player)
  local own, best = get_counter_value(player.score_counter), nil
  for _, p in ipairs(players) do
    if p ~= player then
      local s = get_counter_value(p.score_counter)
      if best == nil or s > best then best = s end
    end
  end
  return own - (best or own)
end

local function fmt(x) return string.format("%.3f", x):gsub("%.?0+$", "") end

local seed_now = 0
policy.on_decision = function(player, list, pick)
  if #list < 2 then return end
  local x = features.state(player)
  for _, v in ipairs(features.choice(player, pick.choice, pick.heuristic)) do x[#x + 1] = v end
  local parts = {}
  for i, v in ipairs(x) do parts[i] = fmt(v) end
  print(string.format("D|%d|%s|%d|%s|%d", seed_now, player.color, margin(player), table.concat(parts, ","),
    get_counter_value(player.score_counter)))
end

driver.LOG_LINES = 50
for seed = OPTS.from, OPTS.to do
  seed_now = seed
  local seats = OPTS.seats
  local colors, makers = {}, {}
  -- the seats rotate with the seed, so every policy plays every position
  for i = 1, #seats do
    local spec = seats[((i - 1 + seed) % #seats) + 1]
    local color = COLORS[i]
    colors[i] = color
    makers[color] = function(s)
      return policy.budgeted(rng.new(s * 31 + i), spec.budget or 0, { network = spec.policy == "network" })
    end
  end
  local ok, outcome, _, scores = pcall(game.play, seed, { colors = colors, policies = makers,
                                                          mw = OPTS.mw_every and seed % OPTS.mw_every == 0 })
  if not ok then
    print("X|" .. seed .. "|" .. tostring(outcome):gsub("\n", " / "))
  else
    for _, p in ipairs(players) do
      print(string.format("E|%d|%s|%d|%s|%d", seed, p.color, margin(p), outcome, scores[p.color]))
    end
  end
end
