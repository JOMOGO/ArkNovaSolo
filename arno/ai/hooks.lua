-- AI opponent (docs/AI_OPPONENT.md §1): the wrappers that let the driver see the AI's
-- panels. Each one is a no-op unless an AI seat is in the game (ai.seat.active), so a game
-- without an AI behaves exactly as before. Listed in CHANGES.md (AI1, AI2).

local seat = require("ai.seat")
local driver = require("ai.driver")

local M = {}

-- custom map setup: the AI seats sit out the humans' "place a tile, then Ready" step
local hidden_for_maps = nil

function M.install(wrap)
  table.insert(cnsts.saved_player_fields, "is_ai")
  table.insert(cnsts.saved_player_fields, "ai_level")
  table.insert(cnsts.saved_globals, "ai_state")   -- { seed }: replay-safe AI choices

  -- AI3: during setup the prompts are table-wide panels (UI.setXml, UI.setAttribute) that
  -- the panel hook does not see; a heartbeat looks for AI choices until the game starts
  wrap("AI3", "setup_game", function(orig)
    return function(...)
      local result = orig(...)
      if seat.active() then driver.setup_heartbeat() end
      return result
    end
  end)

  -- AI4: map setup. Classic match: the AI keeps the top map of its tile and clicks Ready,
  -- as a human. Custom setup (map tiles placed by hand): the AI plays map A and sits out
  -- the Ready step (restored by AI5). Mirror match needs nothing: every seat gets the map.
  wrap("AI4", "show_map_ready_panels", function(orig)
    return function(classic, ...)
      if not seat.active() then return orig(classic, ...) end
      if classic then
        local result = orig(classic, ...)
        for _, p in ipairs(players) do
          if seat.is_ai(p) then
            local color = p.color
            Wait.time(function() on_map_ready_clicked(nil, color, nil) end, 1)
          end
        end
        return result
      end
      local full, humans = players, {}
      for _, p in ipairs(players) do
        if seat.is_ai(p) then
          apply_map_choice(p, "map_A", cnsts.map_data.map_A.image)
          driver.note(p.color .. " plays map A (custom map setup)")
        else
          humans[#humans + 1] = p
        end
      end
      if #humans < #full then
        hidden_for_maps = full
        players = humans
      end
      return orig(classic, ...)
    end
  end)

  -- AI5: the AI seats rejoin `players` (in their seat order) once the maps are set
  wrap("AI5", "finish_map_setup", function(orig)
    return function(...)
      if hidden_for_maps ~= nil then
        players = hidden_for_maps
        hidden_for_maps = nil
      end
      return orig(...)
    end
  end)

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
