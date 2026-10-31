-- AI opponent (docs/AI_OPPONENT.md §4): picks one of the choices ai.choices lists.
-- For now only the policies the no-stall tests need (milestone M1):
--   random  a seeded random legal choice; Back/Cancel only when nothing else is offered
--           (going back and forth would never end a turn), Pass less often than the rest
--   first   the first choice that is not Back (the every-card driver's habit)
-- The level policies (network, point budget, personalities, lookahead) come later.

local rng = require("core.rng")

local M = {}

M.PASS_WEIGHT = 0.25

local function forward(choices)
  local out = {}
  for _, c in ipairs(choices) do
    if c.tag ~= "back" then out[#out + 1] = c end
  end
  if #out == 0 then return choices end
  return out
end

function M.random(r)
  return function(_, choices)
    local pool = forward(choices)
    local total = 0
    for _, c in ipairs(pool) do total = total + (c.tag == "pass" and M.PASS_WEIGHT or 1) end
    local x = rng.next(r) * total
    for _, c in ipairs(pool) do
      x = x - (c.tag == "pass" and M.PASS_WEIGHT or 1)
      if x < 0 then return c end
    end
    return pool[#pool]
  end
end

function M.first()
  return function(_, choices) return forward(choices)[1] end
end

return M
