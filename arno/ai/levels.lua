-- AI opponent (docs/AI_OPPONENT.md §4, Levels): what each level changes. All levels score
-- the same choices the same way (ai.policy.score; the network once trained). A lower level
-- gives up points on purpose:
--   budget       per choice, it picks at random among the choices within this many points
--                of the best one (never one further below), so it errs where choices are
--                close, as people do
--   endgame      in the last turns it plays with the budget of the level above
--   personality  Easy and Medium draw one plan per game (seeded by the game and the seat)
--                and, among the choices within their budget, favour the ones that fit it:
--                they play it a bit stubbornly, as a beginner does, without a silly move
-- (lookahead and an opponent model are not in: see docs/AI_OPPONENT.md §8)

local policy = require("ai.policy")
local value = require("ai.value")
local rng = require("core.rng")

local M = {}

M.ORDER = { "easy", "medium", "hard", "expert" }
-- budgets in the network's points, calibrated against Expert (tools/ai_train.py match,
-- 60 games each; docs/AI_OPPONENT.md §8): budget 0.5 -> 0 points behind, 0.7 -> 5,
-- 1.0 -> 18, 1.3 -> 35, 1.6 -> 26, 2.0 -> 30 (strength falls steeply around 1)
M.LEVELS = {
  easy   = { budget = 1.6, personality = 3 },     -- personality: weight of a fitting choice
  medium = { budget = 1.3, personality = 1.5 },   -- 1.05 / 1.2: within 3-6 points of Hard
  hard   = { budget = 0.8 },
  expert = { budget = 0 },
}

-- the plans and the choices that fit them (action cards, and what is picked inside them)
M.PLANS = {
  animals      = { actions = { ANIMALS = true }, words = { "animal", "enclosure" } },
  conservation = { actions = { ASSOCIATION = true }, words = { "conservation", "project", "partner zoo", "university" } },
  building     = { actions = { BUILD = true }, words = { "build", "kiosk", "pavilion", "enclosure" } },
  sponsors     = { actions = { SPONSORS = true }, words = { "sponsor", "money" } },
}
M.PLAN_ORDER = { "animals", "conservation", "building", "sponsors" }
M.ENDGAME_PROGRESS = 0.85
M.ASSIST = true          -- the levels play with policy.ASSIST (false: the network alone)

local function above(level)
  for i, name in ipairs(M.ORDER) do
    if name == level then return M.ORDER[math.min(i + 1, #M.ORDER)] end
  end
  return level
end

function M.budget(level)
  local spec = M.LEVELS[level] or M.LEVELS.medium
  if value.progress() >= M.ENDGAME_PROGRESS then spec = M.LEVELS[above(level)] end
  return spec.budget
end

local function color_code(color)
  local n = 0
  for i = 1, #color do n = n * 31 + color:byte(i) end
  return n
end

-- the policy of a level. Every decision draws from its own stream, seeded by the game's
-- seed (ai_state, saved in the mod's checkpoints), the seat, the turn and the input of the
-- turn: a rewind to the turn checkpoint replays the same choices.
-- the plan a seat follows this game (nil: no personality at this level)
function M.plan(level, player, seed)
  local spec = M.LEVELS[level]
  if spec == nil or spec.personality == nil then return nil end
  local r = rng.new(((seed or 1) + color_code(player.color) * 31) % 4294967296)
  return M.PLAN_ORDER[math.floor(rng.next(r) * #M.PLAN_ORDER) + 1]
end

-- how much a personality favours a choice (1 = not at all)
function M.fits(plan_name, choice, weight)
  local plan = M.PLANS[plan_name]
  if plan == nil then return 1 end
  local label = (choice.label or ""):lower()
  if choice.handler == "on_action_card_button_clicked" then
    return plan.actions[(choice.label:match("^(%a+)") or ""):upper()] and weight or 1
  end
  for _, word in ipairs(plan.words) do
    if label:find(word, 1, true) then return weight end
  end
  return 1
end

function M.policy(level, seed)
  return function(player, choices, step)
    local base = seed or (ai_state and ai_state.seed) or 1
    local mixed = (base + color_code(player.color) * 7919 + (player.turns_taken or 0) * 104729
                   + (step or 0) * 1299709) % 4294967296
    local plan = M.plan(level, player, base)
    local spec = M.LEVELS[level] or {}
    -- the assists (policy.ASSIST: builds that house the hand's animals, conservation projects)
    -- correct two blind spots of the network; every level uses them (round 16: +11 / 68%
    -- against the same network without, and -19 -> -10 against ARNO 1)
    local opts = { network = true, assist = M.ASSIST ~= false }
    if plan then opts.weight = function(_, c) return M.fits(plan, c, spec.personality) end end
    return policy.budgeted(rng.new(mixed), M.budget(level), opts)(player, choices)
  end
end

return M
