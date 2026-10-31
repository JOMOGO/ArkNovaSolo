-- AI opponent (docs/AI_OPPONENT.md §1): the wrappers that let the driver see the AI's
-- panels. Each one is a no-op unless an AI seat is in the game (ai.seat.active), so a game
-- without an AI behaves exactly as before. Listed in CHANGES.md (AI1, AI2).

local seat = require("ai.seat")
local driver = require("ai.driver")

local M = {}

function M.install(wrap)
  -- AI1: a panel for an AI colour wakes the driver (it reads active_panels itself)
  wrap("AI1", "set_active_panel", function(orig)
    return function(color, xml, ...)
      local result = orig(color, xml, ...)
      if xml ~= nil and seat.active() and seat.is_ai(seat.player(color)) then driver.wake(color) end
      return result
    end
  end)

  -- AI2: the step cap counts per turn
  wrap("AI2", "start_player_turn", function(orig)
    return function(player, ...)
      if seat.is_ai(player) then driver.turn_started(player.color) end
      return orig(player, ...)
    end
  end)
end

return M
