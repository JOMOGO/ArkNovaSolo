-- AI opponent (docs/AI_OPPONENT.md): which players are AI seats, and their levels.
-- An AI seat is a full players entry played by the human rules; it is not an ARNO
-- (`is_arno`), so none of ARNO's wrappers touch it.

local M = {}

M.LEVELS = { "easy", "medium", "hard", "expert" }

function M.is_ai(player)
  return type(player) == "table" and player.is_ai == true
end

function M.player(color)
  for _, p in ipairs(players or {}) do
    if p.color == color then return p end
  end
  return nil
end

function M.active()
  for _, p in ipairs(players or {}) do
    if M.is_ai(p) then return true end
  end
  return false
end

return M
