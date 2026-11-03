-- Self-play for training (docs/AI_OPPONENT.md §4a), run by tools/ai_train.py (not part of the
-- test suite). Plays whole games on the built Global.lua and prints one line per decision
-- with two or more choices:
--   D|<seed>|<color>|<margin now>|<inputs, comma separated>|<own score now>|<card number or 0>
-- and per seat at the end:
--   E|<seed>|<color>|<final margin>|<outcome>
-- margin = own score minus the best other score. The trainer's target for a decision is
-- final margin minus margin now. Options (module "tests.selfplay_options"):
--   { from, to, seats = { { policy = "heuristic" | "network" | "network_b" | "network_a", budget = n }, ... },
--     mw_every, assist_build, assist_cp }   (network_a: the network with policy's assists)
local game = require("tests.ai_game")
local OPTS = require("tests.selfplay_options")
local policy = require("ai.policy")
local features = require("ai.features")
local driver = require("ai.driver")
local rng = require("core.rng")
local levels = require("ai.levels")

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

local M_card_number = features.card_number   -- the card a choice is about (0: none)

local seed_now = 0
policy.on_decision = function(player, list, pick)
  if #list < 2 or OPTS.log == false then return end
  local x = features.state(player)
  for _, v in ipairs(features.choice(player, pick.choice, pick.heuristic)) do x[#x + 1] = v end
  local parts = {}
  for i, v in ipairs(x) do parts[i] = fmt(v) end
  print(string.format("D|%d|%s|%d|%s|%d|%d", seed_now, player.color, margin(player), table.concat(parts, ","),
    get_counter_value(player.score_counter), M_card_number(pick.choice)))
end

driver.LOG_LINES = 50
for seed = OPTS.from, OPTS.to do
  seed_now = seed
  local seats = OPTS.seats
  local colors, makers, arno = {}, {}, nil
  local with_arno = false
  for _, spec in ipairs(seats) do if spec.arno then with_arno = true end end
  -- the seats rotate with the seed, so every policy plays every position (not against
  -- ARNO: a player starts, ARNO sits after the AI seats)
  for i = 1, #seats do
    local spec = with_arno and seats[i] or seats[((i - 1 + seed) % #seats) + 1]
    local color = COLORS[i]
    colors[i] = color
    if spec.arno then arno = { color = color, level = spec.arno } end
    if not spec.arno then makers[color] = function(s)
      if spec.level then return levels.policy(spec.level, s * 31 + i) end     -- a shipped level
      local opts = { network = spec.policy == "network" or spec.policy == "network_b" or spec.policy == "network_a" }
      if spec.policy == "network_b" then opts.weights = require("ai.net_weights_b") end
      -- network_a: the network with the assists (policy.ASSIST, or the options' assist_build / assist_cp)
      if spec.policy == "network_a" then
        opts.assist = { build = OPTS.assist_build or policy.ASSIST.build, cp = OPTS.assist_cp or policy.ASSIST.cp }
      end
      return policy.budgeted(rng.new(s * 31 + i), spec.budget or 0, opts)
    end end
  end
  local ok, outcome, _, scores = pcall(game.play, seed, { colors = colors, policies = makers, arno = arno,
                                                          mw = OPTS.mw_every and seed % OPTS.mw_every == 0 })
  if not ok then
    print("X|" .. seed .. "|" .. tostring(outcome):gsub("\n", " / "))
  else
    for _, p in ipairs(players) do
      print(string.format("E|%d|%s|%d|%s|%d", seed, p.color, margin(p), outcome, scores[p.color]))
    end
  end
end
