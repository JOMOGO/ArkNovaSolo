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

local function color_code(color)
  local n = 0
  for i = 1, #color do n = n * 31 + color:byte(i) end
  return n
end

-- the policy of a level. Every decision draws from its own stream, seeded by the game's
-- seed (ai_state, saved in the mod's checkpoints), the seat, the turn and the input of the
-- turn: a rewind to the turn checkpoint replays the same choices.
function M.policy(level, seed)
  return function(player, choices, step)
    local base = seed or (ai_state and ai_state.seed) or 1
    local mixed = (base + color_code(player.color) * 7919 + (player.turns_taken or 0) * 104729
                   + (step or 0) * 1299709) % 4294967296
    return policy.budgeted(rng.new(mixed), M.budget(level), { network = true })(player, choices)
  end
end

return M
