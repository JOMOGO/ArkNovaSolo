-- ARNO 3.0 for "Ark Nova - Complete Scripted" (Tabletop Simulator).
--
-- Small list helpers shared by the core, adapter and ui modules.

local M = {}

-- true when list (may be nil) holds value
function M.contains(list, value)
  for _, v in ipairs(list or {}) do
    if v == value then return true end
  end
  return false
end

return M
