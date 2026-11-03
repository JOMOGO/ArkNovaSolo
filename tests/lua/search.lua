-- Search labels for training (docs/AI_OPPONENT.md §10, search labels), run by
-- tools/ai_train.py search (not part of the test suite). For sampled decisions of real games it
-- values EACH of the best few candidates by playing on from it, instead of the one noisy
-- sample a self-play D line gives. The game state cannot be copied, so every sample replays
-- the game from its seed:
--   1. record: the game is played once with the base policies; every call of every policy seat
--      notes which choice it took (the choice lists are deterministic for a given state)
--   2. N points per searched seat (>= 2 choices, no fixed rule; one per stretch of the game)
--   3. per point and candidate (top k by the network's Q, plus the base choice) and sample:
--      replay forcing the recorded choices up to the point (no scoring: fast), force the
--      candidate, play on with the policies (sample-seeded, rollout budget) for H own
--      decisions; value = margin then - margin at the point + Q there for the choice then
--      made (as train --bootstrap); if the game ends first, final margin - margin at the point
-- Lines:
--   S|seed|color|point|rank|value|sd|base|inputs|card    (inputs at the point, before the
--     candidate: features.state .. features.choice, features.VERSION, as selfplay's D lines;
--     point = the decision's index among the seat's D lines; rank = by the network's Q, 1 = best)
--   V|seed|color|point|rank|value of each sample        (for the noise report)
--   T|seed|color|point|seconds|rollouts                  (time spent on that point)
--   C|seed|ok|details                                   (determinism check, opts.check)
--   E|seed|color|final margin|outcome|score             (the recorded game, as selfplay)
--   X|seed|message                                      (a failure)
-- Options (module "tests.search_options"):
--   { from, to, seats (as selfplay), mw_every, points, k, samples, horizon, searched = "ai" | color,
--     rollout_budget (nil: the seats' own budgets), check, reshuffle (false: keep the seed's deck order
--     after the point; by default every sample shuffles the cards left in the zoo deck there) }
local game = require("tests.ai_game")
local OPTS = require("tests.search_options")
local policy = require("ai.policy")
local features = require("ai.features")
local driver = require("ai.driver")
local net = require("ai.net")
local rng = require("core.rng")
local levels = require("ai.levels")

local COLORS = { "Red", "Blue", "Yellow", "White" }
os.clock()          -- (MoonSharp: the first call of a process returns nothing)
local POINTS, K, SAMPLES, HORIZON = OPTS.points or 5, OPTS.k or 5, OPTS.samples or 2, OPTS.horizon or 20

local function player_of(color)
  for _, p in ipairs(players) do if p.color == color then return p end end
end

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

-- as ai.policy: Back only when nothing else is offered
local function forward(list)
  local out = {}
  for _, c in ipairs(list) do if c.tag ~= "back" then out[#out + 1] = c end end
  if #out == 0 then return list end
  return out
end

local function index_of(list, c)
  for i, e in ipairs(list) do if e == c then return i end end
end

local function heuristic(player, c)
  local ok, s = pcall(policy.score, player, c)
  return (ok and type(s) == "number") and s or 0
end

local function inputs(player, c, h, version)
  local x = features.state(player, version)
  for _, v in ipairs(features.choice(player, c, h, version)) do x[#x + 1] = v end
  return x
end

local function card_number(c)
  local name
  if c.obj then
    local ok, n = pcall(function() return c.obj.getName() end)
    if ok then name = n end
  end
  name = name or (c.label or ""):match(": (.+)$") or c.label or ""
  return tonumber(tostring(name):match("%((%d+)%)")) or 0
end

-- ------------------------------------------------------------------ seats
local seed_now = 0
local specs, colors, arno, qweights = {}, {}, nil, {}
local function setup_seats(seed)
  specs, colors, arno, qweights = {}, {}, nil, {}
  local with_arno = false
  for _, spec in ipairs(OPTS.seats) do if spec.arno then with_arno = true end end
  for i = 1, #OPTS.seats do
    local spec = with_arno and OPTS.seats[i] or OPTS.seats[((i - 1 + seed) % #OPTS.seats) + 1]
    colors[i] = COLORS[i]
    if spec.arno then arno = { color = COLORS[i], level = spec.arno }
    else
      specs[COLORS[i]] = { spec = spec, i = i }
      qweights[COLORS[i]] = spec.policy == "network_b" and require("ai.net_weights_b") or net.weights()
    end
  end
end

-- the base policy of a seat; budget: nil = the seat's own
local function make(color, s, budget)
  local spec, i = specs[color].spec, specs[color].i
  if spec.level then
    if budget == nil then return levels.policy(spec.level, s * 31 + i) end
    return policy.budgeted(rng.new(s * 31 + i), budget, { network = true })
  end
  local opts = { network = spec.policy == "network" or spec.policy == "network_b" }
  if spec.policy == "network_b" then opts.weights = require("ai.net_weights_b") end
  return policy.budgeted(rng.new(s * 31 + i), budget or spec.budget or 0, opts)
end

local function searched(color)
  if not specs[color] then return false end
  return OPTS.searched == nil or OPTS.searched == "ai" or OPTS.searched == color
end

-- ------------------------------------------------------------------ one pass
-- run = { record = bool, rec = color -> { idx = {}, n = {}, multi = {}, ruled = {} },
--         at = { color, call } (switch to free play there), hook(player, list, call) -> choice,
--         after(player, list, base) -> choice or nil, policy_seed, budget }
local run
-- A pass is ended early (the horizon reached, a replay that went astray) at the next turn
-- boundary, as the turn cap ends a game: the rest of this turn is played by the cheap random
-- policy and the next turn never starts. (Raising an error in the middle of a turn left the
-- mod's per-colour panel state behind, and the next replay of the seed saw other choices.)
local function stop()
  run.stopping = true
  start_player_turn = function() end      -- ai_game's next sim.record wraps the mod's own again
end

-- the policy of seat `color` in this pass: records, forces or plays (see run)
-- (MoonSharp: locals of a loop body captured by closures can alias each other, so this is not
-- built inside the loop over the seats, and its state lives in a table)
local function seat_policy(color, seed, cheap)
  local seat = {}
  local function get_base()
    seat.base = seat.base or make(color, run.policy_seed or seed, run.budget)
    return seat.base
  end
  return function(player, list, step)
    if run.stopping then return cheap(player, list) end
    local n = (run.calls[color] or 0) + 1
    run.calls[color] = n
    if run.record then
      local pick = get_base()(player, list, step)
      local r = run.rec[color]
      local fw = forward(list)
      local ruled = false
      for _, c in ipairs(fw) do if policy.rule(player, c) ~= nil then ruled = true end end
      r.idx[n], r.n[n], r.multi[n], r.ruled[n] = index_of(list, pick), #list, #fw >= 2, ruled
      return pick
    end
    if not run.free then
      local r = run.rec[color]
      if r.idx[n] == nil or r.n[n] ~= #list then
        run.diverged = string.format("%s call %d: %d choices, recorded %s", color, n, #list, tostring(r.n[n]))
        stop()
        return cheap(player, list)
      end
      if run.at and run.at.color == color and run.at.call == n then
        run.free = true
        return run.hook(player, list)
      end
      return list[r.idx[n]]
    end
    if run.after and color == run.at.color then
      local c = run.after(player, list, get_base())
      if c then return c end
    end
    return get_base()(player, list, step)
  end
end

local function pass(seed)
  run.free = run.record
  run.calls, run.diverged, run.stopping = {}, nil, false
  local cheap = policy.random(rng.new(seed))
  local makers = {}
  for color in pairs(specs) do
    makers[color] = function() return seat_policy(color, seed, cheap) end
  end
  math.randomseed(seed)        -- the mod's own math.random (a pilfered card): the same every pass
  local ok, outcome, _, scores = pcall(game.play, seed, { colors = colors, policies = makers, arno = arno,
                                                          mw = OPTS.mw_every and seed % OPTS.mw_every == 0 })
  return ok, outcome, scores
end

-- ------------------------------------------------------------------ a game
local function sd_of(values, mean)
  if #values < 2 then return 0 end
  local s = 0
  for _, v in ipairs(values) do s = s + (v - mean) ^ 2 end
  return math.sqrt(s / (#values - 1))
end

-- the cards still in the zoo deck, shuffled anew for this sample (the same order for every
-- candidate of a sample): a replay keeps the seed's deck, so without this the rollouts would
-- know which cards come next
local function reshuffle_deck(sample_seed)
  local deck = zoo_deck
  local contents = deck and deck._s and deck._s.contents
  if type(contents) ~= "table" then return end
  local r = rng.new(sample_seed % 4294967296)
  for i = #contents, 2, -1 do
    local j = math.floor(rng.next(r) * i) + 1
    contents[i], contents[j] = contents[j], contents[i]
  end
end

-- (MoonSharp: locals of a loop body captured by closures can alias each other, so the state
-- of a point lives in a table `st` and the functions are not nested in loops)

-- the candidates at the point: by the network's Q (the seat's network), the base choice always in
local function candidates(st, player, list)
  local w = qweights[st.color]
  local version = features.version_of(w)
  local fw, scored = forward(list), {}
  for i, c in ipairs(fw) do
    local h = heuristic(player, c)
    scored[i] = { c = c, i = index_of(list, c), q = net.forward(inputs(player, c, h, version), w),
                  x = inputs(player, c, h), card = card_number(c), pos = i }
  end
  table.sort(scored, function(a, b) if a.q ~= b.q then return a.q > b.q end return a.pos < b.pos end)
  local out = {}
  local base_i = st.rec[st.color].idx[st.pt.call]
  for rank, e in ipairs(scored) do
    e.rank, e.base = rank, e.i == base_i
    if rank <= K or e.base then out[#out + 1] = e end
  end
  return out
end

-- one rollout of candidate cands[pos], sample `sample`: its value, or nil (st.failed set)
local function rollout(st, pos, sample)
  local ro = { own = 0 }
  run = { record = false, rec = st.rec, at = { color = st.color, call = st.pt.call },
          policy_seed = st.seed + 7919 * sample, budget = OPTS.rollout_budget }
  run.hook = function(player, list)
    ro.start = margin(player)
    if st.cands == nil then
      st.cands, st.margin = candidates(st, player, list), ro.start
    elseif ro.start ~= st.margin or #list ~= st.rec[st.color].n[st.pt.call] then
      st.failed = "the point replayed differently"
    end
    if OPTS.reshuffle ~= false then reshuffle_deck(st.seed * 131 + st.pt.dline * 7 + sample) end
    return list[st.cands[pos].i]
  end
  run.after = function(player, list, base)
    if #forward(list) < 2 then return nil end
    ro.own = ro.own + 1
    if ro.own < HORIZON then return nil end
    -- the horizon: the margin change plus the network's Q for the choice the policy makes here
    local pick = base(player, list)
    local w = qweights[st.color]
    local q = net.forward(inputs(player, pick, heuristic(player, pick), features.version_of(w)), w)
    ro.value = margin(player) - ro.start + q
    stop()
    return pick
  end
  local ok, err = pass(st.seed)
  st.rollouts = st.rollouts + 1
  if run.diverged then st.failed = run.diverged return nil end
  if ro.value == nil then
    if ro.start == nil then st.failed = "the point was not reached" return nil end
    if not ok then
      st.failed = (tostring(err) .. " / " .. game.last_log(6)):gsub("\n", " / ")
      return nil
    end
    ro.value = margin(player_of(st.color)) - ro.start     -- the game ended first
  end
  return ro.value
end

local function search_point(seed, color, pt, rec)
  local st = { seed = seed, color = color, pt = pt, rec = rec, t0 = os.clock(), rollouts = 0, values = {} }
  local v = rollout(st, 1, 1)
  if v ~= nil then
    st.values[1] = { v }
    for pos = 1, #st.cands do
      st.values[pos] = st.values[pos] or {}
      for sample = 1, SAMPLES do
        if not (pos == 1 and sample == 1) and not st.failed then
          local value = rollout(st, pos, sample)
          if value ~= nil then table.insert(st.values[pos], value) end
        end
      end
    end
  end
  if st.failed or st.cands == nil then
    print(string.format("X|%d|search %s point %d: %s", seed, color, pt.dline, tostring(st.failed or "no candidates")))
    return
  end
  for pos, e in ipairs(st.cands) do
    local vs, sum = st.values[pos], 0
    for _, x in ipairs(vs) do sum = sum + x end
    local mean = sum / #vs
    local parts = {}
    for i, x in ipairs(e.x) do parts[i] = fmt(x) end
    print(string.format("S|%d|%s|%d|%d|%s|%s|%d|%s|%d", seed, color, pt.dline, e.rank, fmt(mean),
      fmt(sd_of(vs, mean)), e.base and 1 or 0, table.concat(parts, ","), e.card))
    local each = {}
    for i, x in ipairs(vs) do each[i] = fmt(x) end
    print(string.format("V|%d|%s|%d|%d|%s", seed, color, pt.dline, e.rank, table.concat(each, ",")))
  end
  print(string.format("T|%d|%s|%d|%.2f|%d", seed, color, pt.dline, os.clock() - st.t0, st.rollouts))
end

-- N points of a seat: one per stretch of its eligible decisions (>= 2 choices, no fixed rule)
local function points_of(seed, ci, r)
  local eligible, dline = {}, 0
  for call = 1, #r.idx do
    if r.multi[call] then
      dline = dline + 1
      if not r.ruled[call] then eligible[#eligible + 1] = { call = call, dline = dline } end
    end
  end
  local pr = rng.new((seed * 7 + ci) % 4294967296)
  local points = {}
  local n = math.min(POINTS, #eligible)
  for t = 1, n do
    local a, b = math.floor((t - 1) * #eligible / n) + 1, math.floor(t * #eligible / n)
    points[#points + 1] = eligible[a + math.floor(rng.next(pr) * (b - a + 1))]
  end
  return points
end

local function search_game(seed)
  seed_now = seed
  setup_seats(seed)
  -- 1. record
  run = { record = true, rec = {} }
  for color in pairs(specs) do run.rec[color] = { idx = {}, n = {}, multi = {}, ruled = {} } end
  local ok, outcome, scores = pass(seed)
  if not ok then
    print("X|" .. seed .. "|" .. tostring(outcome):gsub("\n", " / "))
    return
  end
  local rec = run.rec
  local final = {}
  for _, p in ipairs(players) do
    final[p.color] = scores[p.color]
    print(string.format("E|%d|%s|%d|%s|%d", seed, p.color, margin(p), outcome, scores[p.color]))
  end
  -- determinism: every choice forced must give the same game
  if OPTS.check then
    run = { record = false, rec = rec }
    local ok2, outcome2, scores2 = pass(seed)
    local bad = {}
    if not ok2 then bad[#bad + 1] = run.diverged or tostring(outcome2):gsub("\n", " / ") end
    for color, s in pairs(final) do
      if ok2 and scores2[color] ~= s then bad[#bad + 1] = string.format("%s %d vs %d", color, scores2[color], s) end
    end
    for color, r in pairs(rec) do
      if ok2 and (run.calls[color] or 0) ~= #r.idx then
        bad[#bad + 1] = string.format("%s %d calls vs %d", color, run.calls[color] or 0, #r.idx)
      end
    end
    if ok2 and outcome2 ~= outcome then bad[#bad + 1] = outcome2 .. " vs " .. outcome end
    print(string.format("C|%d|%s|%s", seed, #bad == 0 and "ok" or "FAIL", table.concat(bad, "; ")))
  end
  -- 2. points per searched seat, 3. their candidates and samples
  local order = {}
  for color in pairs(specs) do order[#order + 1] = color end
  table.sort(order)
  for ci, color in ipairs(order) do
    if searched(color) then
      for _, pt in ipairs(points_of(seed, ci, rec[color])) do search_point(seed, color, pt, rec) end
    end
  end
end

driver.LOG_LINES = 50
for seed = OPTS.from, OPTS.to do
  local ok, err = pcall(search_game, seed)
  if not ok then print("X|" .. seed .. "|" .. tostring(err):gsub("\n", " / ")) end
end
