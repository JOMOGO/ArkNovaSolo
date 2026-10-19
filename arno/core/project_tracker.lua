-- ARNO 3.0 for "Ark Nova - Complete Scripted" (Tabletop Simulator).
-- Port of brdgm/ark-nova-solo-helper (c) Stefan Seifert, Apache License 2.0.
-- ARNO solo mode designed by Andre K. See NOTICE. Modified: ported to Lua (MoonSharp).
--
-- Optional ARNO conservation project module: tracker driven by discarded sponsor cards.
-- Port of src/services/ProjectModuleTracker.ts.

local M = {}

local MAX_TRACKER_POS = 14
-- Object.values(ProjectSlot), in declaration order
M.SLOTS = { "right", "middle", "left" }

-- Token steps forward for each discarded sponsor card; once it reached the last
-- position on the track, it steps backward for each further step.
function M.position(sponsor_discards)
  local steps = ((sponsor_discards or 0) + 1) % (MAX_TRACKER_POS * 2)
  if steps > MAX_TRACKER_POS then
    return MAX_TRACKER_POS - (steps - MAX_TRACKER_POS)
  end
  return steps
end

local MIDDLE = { [2] = true, [5] = true, [7] = true, [11] = true, [13] = true }
local LEFT = { [4] = true, [8] = true, [10] = true, [12] = true, [14] = true }

function M.slot(position)
  if MIDDLE[position] then return "middle" end
  if LEFT[position] then return "left" end
  return "right"
end

function M.kiosk_count(position)
  if position >= 14 then return 5
  elseif position >= 12 then return 4
  elseif position >= 9 then return 3
  elseif position >= 6 then return 2
  elseif position >= 3 then return 1
  end
  return 0
end

local function contains(list, value)
  for _, v in ipairs(list) do
    if v == value then return true end
  end
  return false
end

-- getPreferredProjectSlots(): preferred slot, then fallbacks
function M.preferred_slots(position)
  local slots = { M.slot(position) }
  for i = position - 1, 1, -1 do
    local alternative = M.slot(i)
    if not contains(slots, alternative) and #slots < 3 then slots[#slots + 1] = alternative end
  end
  for _, alternative in ipairs(M.SLOTS) do
    if not contains(slots, alternative) and #slots < 3 then slots[#slots + 1] = alternative end
  end
  return slots
end

return M
