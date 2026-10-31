-- AI opponent (docs/AI_OPPONENT.md §4, Levels): what each level changes. All levels score
-- the same choices the same way (ai.policy.score; the network once trained). A lower level
-- gives up points on purpose:
--   budget       per choice, it picks at random among the choices within this many points
--                of the best one (never one further below), so it errs where choices are
--                close, as people do
--   endgame      in the last turns it plays with the budget of the level above
-- (personalities, lookahead and the opponent model come with the network, §4b, §4c)

local policy = require("ai.policy")
local value = require("ai.value")
local rng = require("core.rng")

local M = {}

M.ORDER = { "easy", "medium", "hard", "expert" }
M.LEVELS = {
  easy   = { budget = 6 },
  medium = { budget = 3 },
  hard   = { budget = 1 },
  expert = { budget = 0 },
}
M.ENDGAME_PROGRESS = 0.85

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

-- the policy of a level, with its own seeded stream
function M.policy(level, seed)
  local r = rng.new(seed or 1)
  return function(player, choices)
    return policy.budgeted(r, M.budget(level), { network = true })(player, choices)
  end
end

return M
