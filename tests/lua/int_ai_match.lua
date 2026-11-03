-- Matches between AI policies on the BUILT Global.lua (docs/AI_OPPONENT.md §5, test 6):
-- whole 2-seat games, each pairing played with the seats both ways round (the start player
-- matters), reporting wins and average scores. Gate: the hand-written policy beats the
-- random one clearly.
local T = require("tests.lib")
local OPTIONS = require("tests.options")
local game = require("tests.ai_game")
local policy = require("ai.policy")
local rng = require("core.rng")

local levels = require("ai.levels")
local net = require("ai.net")

local POLICIES = {
  random = function(seed) return policy.random(rng.new(seed * 7 + 1)) end,
  heuristic = function(seed) return policy.heuristic(rng.new(seed * 7 + 2)) end,
  expert = function(seed) return levels.policy("expert", seed * 7 + 3) end,     -- the bundled network
}

-- plays `games` seeds twice (a as Red, then a as Blue); returns a's results
local function match(a, b, games)
  local res = { wins = 0, losses = 0, draws = 0, score = 0, opp = 0, n = 0, outcomes = {} }
  for seed = 1, games do
    for _, a_first in ipairs({ true, false }) do
      local ca, cb = a_first and "Red" or "Blue", a_first and "Blue" or "Red"
      local outcome, _, scores = game.play(seed, { policies = { [ca] = POLICIES[a], [cb] = POLICIES[b] },
                                                   mw = seed % 3 == 0 })
      res.outcomes[outcome] = (res.outcomes[outcome] or 0) + 1
      res.n = res.n + 1
      res.score, res.opp = res.score + scores[ca], res.opp + scores[cb]
      if scores[ca] > scores[cb] then res.wins = res.wins + 1
      elseif scores[ca] < scores[cb] then res.losses = res.losses + 1
      else res.draws = res.draws + 1 end
    end
  end
  return res
end

local function report(a, b, res)
  local outcomes = {}
  for k, n in pairs(res.outcomes) do outcomes[#outcomes + 1] = k .. " " .. n end
  table.sort(outcomes)
  print(string.format("%s vs %s: %d-%d-%d (win %.0f%%), average score %.1f vs %.1f (%s)",
    a, b, res.wins, res.losses, res.draws, 100 * res.wins / res.n, res.score / res.n, res.opp / res.n,
    table.concat(outcomes, ", ")))
end

local GAMES = OPTIONS.quick and 3 or (OPTIONS.games or 10)

-- gate on the average margin: a handful of games says little about a win rate
T.test("the hand-written policy beats the random one", function()
  local res = match("heuristic", "random", GAMES)
  report("heuristic", "random", res)
  T.ok((res.score - res.opp) / res.n >= 10, "heuristic scores at least 10 points more on average")
end)

T.test("Expert (the bundled network) beats the hand-written policy", function()
  T.ok(net.available(), "ai.net_weights is bundled")
  local res = match("expert", "heuristic", GAMES)
  report("expert", "heuristic", res)
  T.ok((res.score - res.opp) / res.n >= 5, "Expert scores at least 5 points more on average")
end)

T.test("an ensemble's Q is the average of its members'", function()
  -- one input, no hidden layer: Q = b + w * (x - mean) / std
  local function linear(w, b, mean, std)
    return { version = 1, inputs = 1, mean = { mean }, std = { std },
             layers = { { n_in = 1, n_out = 1, w = { w }, b = { b } } } }
  end
  local a, b = linear(2, 1, 0, 1), linear(-1, 3, 1, 2)
  T.eq(net.forward({ 3 }, a), 7)
  T.eq(net.forward({ 3 }, b), 2)
  T.eq(net.forward({ 3 }, { version = 1, inputs = 1, features = 1, members = { a, b } }), 4.5)
end)

-- card-identity inputs (train --cards): `cards = N` one-hot inputs after the base inputs
local features = require("ai.features")

T.test("features.card_number: the card a choice is about", function()
  T.eq(features.card_number({ kind = "pick_up", label = "play animal: (402) Lion", obj = sim.fake("(402) Lion") }), 402)
  T.eq(features.card_number({ kind = "pick_up", label = "select: (045) Something" }), 45, "named in the label")
  T.eq(features.card_number({ kind = "click", label = "Confirm" }), 0)
  T.eq(features.card_number({ kind = "click", label = "2 money" }), 0)
end)

T.test("a network with card inputs adds the card's weight", function()
  -- one base input, 3 cards, no hidden layer: Q = b + w * x + w_card
  local w = { version = 1, inputs = 4, features = 1, cards = 3, mean = { 1, 0, 0, 0 }, std = { 2, 1, 1, 1 },
              layers = { { n_in = 4, n_out = 1, w = { 2, 10, 20, 30 }, b = { 1 } } } }
  T.eq(net.cards_of(w), 3)
  T.eq(net.forward({ 3 }, w, 0), 3, "no card: the base inputs only")
  T.eq(net.forward({ 3 }, w, 2), 23)
  T.eq(net.forward({ 3 }, w, 3), 33)
  T.eq(net.forward({ 3, 0, 1, 0 }, w), 23, "a dense one-hot in x gives the same")
  T.eq(net.forward({ 3 }, w, 7), 3, "a card beyond the inputs: none")
  -- an ensemble may mix it with a network without card inputs
  local plain = { version = 1, inputs = 1, mean = { 0 }, std = { 1 }, layers = { { n_in = 1, n_out = 1, w = { 1 }, b = { 0 } } } }
  local ens = { version = 1, inputs = 1, features = 1, members = { w, plain } }
  T.eq(net.cards_of(ens), 3)
  T.eq(net.cards_of(plain), 0)
  T.eq(net.forward({ 3 }, ens, 2), (23 + 3) / 2)
end)

T.test("policy.q_scored gives a choice about card N its card weight", function()
  local p = sim.human_game(false, "map_A")
  local n_base = features.SIZES[1][1] + features.SIZES[1][2]
  local n = n_base + 560
  local mean, std, wt = {}, {}, {}
  for i = 1, n do mean[i], std[i], wt[i] = 0, 1, 0 end
  wt[n_base + 402], wt[n_base + 45] = 5, -2          -- the base inputs weigh nothing
  local w = { version = 1, inputs = n, features = 1, cards = 560, mean = mean, std = std,
              layers = { { n_in = n, n_out = 1, w = wt, b = { 1 } } } }
  local choices = {
    { kind = "pick_up", label = "select: (402) Lion", obj = sim.fake("(402) Lion") },
    { kind = "pick_up", label = "select: (045) Something", obj = sim.fake("(045) Something") },
    { kind = "pick_up", label = "select: (111) Other", obj = sim.fake("(111) Other") },
  }
  local scores = {}
  for _, e in ipairs(policy.q_scored(p, choices, w)) do scores[features.card_number(e.choice)] = e.score end
  T.eq(scores[402], 6)
  T.eq(scores[45], -1)
  T.eq(scores[111], 1, "a card without weight: the bias")
  -- in an ensemble with a network without card inputs (Q 0 here)
  local zero = {}
  for i = 1, n_base do zero[i] = 0 end
  local plain = { version = 1, inputs = n_base, features = 1, mean = zero, std = std,
                  layers = { { n_in = n_base, n_out = 1, w = zero, b = { 0 } } } }
  scores = {}
  for _, e in ipairs(policy.q_scored(p, choices, { version = 1, inputs = n_base, features = 1, members = { w, plain } })) do
    scores[features.card_number(e.choice)] = e.score
  end
  T.eq(scores[402], 3)
  T.eq(scores[45], -0.5)
end)

T.finish("integration AI match")
