-- ARNO 3.0 for "Ark Nova - Complete Scripted" (Tabletop Simulator).
-- ARNO solo mode designed by Andre K. See NOTICE.
--
-- Installs ARNO's wrappers around mod functions (docs/DESIGN.md §4). Runs once when the
-- bundle loads, after every mod function is defined and before the mod's on_* interaction
-- wrapper (so ARNO's on_* handlers are wrapped too). Every wrapper is a no-op unless an
-- ARNO is in the game (state.active()), so a game without ARNO behaves like the base mod.
-- Each wrapper is listed in CHANGES.md.

local state = require("adapter.state")
local setup = require("adapter.setup")

local M = {}

M.installed = {}

local function wrap(id, name, make)
  local orig = _G[name]
  if type(orig) ~= "function" then
    error("ARNO hook " .. id .. ": mod function '" .. name .. "' not found (base mod changed?)")
  end
  _G[name] = make(orig)
  M.installed[#M.installed + 1] = id .. " " .. name
end
M.wrap = wrap

local is_bot = setup.is_bot

function M.install(ARNO)
  -- H15: persistence of ARNO state in the mod's checkpoints
  table.insert(cnsts.saved_globals, "arno_state")
  table.insert(cnsts.saved_player_fields, "is_arno")
  table.insert(cnsts.saved_player_fields, "arno_index")

  -- H1: ARNO rows in the setup panel
  wrap("H1", "game_setup_panel_xml", function(orig)
    return function(...) return setup.extend_setup_panel(orig(...)) end
  end)

  -- H5-H7: ARNO's own setup, then the humans-only window for the simultaneous prompts
  wrap("H5", "setup_player_maps", function(orig)
    return function(...)
      if state.active() and not setup.window_open then
        for _, p in ipairs(setup.bots(players)) do setup.prepare_bot(p) end
        setup.open_window()
      end
      return orig(...)
    end
  end)

  -- H8: close the window and process ARNO's starting cards before start_game counts discards
  wrap("H8", "start_game", function(orig)
    return function(...)
      setup.close_window()
      if state.active() then
        local args = { ... }
        return require("adapter.apply").deal_bot_setup_cards(setup.bots(players), function()
          orig((table.unpack or unpack)(args))
        end)
      end
      return orig(...)
    end
  end)

  -- H9: ARNO's turn starts where a human would get the action panel
  wrap("H9", "create_action_selection_panel", function(orig)
    return function(player, only_action, multiplier, hypnosis)
      if is_bot(player) then return ARNO.turn.start(player, only_action, multiplier, hypnosis) end
      return orig(player, only_action, multiplier, hypnosis)
    end
  end)

  -- H13: ARNO is never the target of an interactive effect (rules p2)
  wrap("H13", "targetable", function(orig)
    return function(other)
      if is_bot(other) then return false end
      return orig(other)
    end
  end)

  -- H16: ARNO has no hand; loops over all hands treat him as an empty, unchanging hand
  wrap("H16", "wait_for_all_hand_counts", function(orig)
    return function(index, count, callback)
      if not state.active() then return orig(index, count, callback) end
      local humans = setup.humans(players)
      return Wait.condition(callback, function()
        for _, player in ipairs(humans) do
          local want = (type(count) == "function") and count(player) or count
          if #Player[player.color].getHandObjects(index) ~= want then return false end
        end
        return true
      end)
    end
  end)
  wrap("H16", "other_hand_counts", function(orig)
    return function(color, index)
      local counts = orig(color, index)
      for _, p in ipairs(setup.bots(players)) do counts[p.color] = nil end
      return counts
    end
  end)
  wrap("H16", "final_scoring_cards", function(orig)
    return function(player)
      if is_bot(player) then return {} end
      return orig(player)
    end
  end)
  wrap("H16", "player_hand_cards", function(orig)
    return function(player, ...)
      if is_bot(player) then return {} end
      return orig(player, ...)
    end
  end)

  -- H17: ARNO wins ties against humans (rules p10)
  wrap("H17", "game_winners", function(orig)
    -- the mod breaks score ties by supported projects (map cubes, always 0 for ARNO), so
    -- the score comparison must come first: any ARNO with the best score wins
    return function(...)
      if not state.active() then return orig(...) end
      local best = nil
      for _, p in ipairs(players) do
        local s = get_counter_value(p.score_counter)
        if best == nil or s > best then best = s end
      end
      local bots = {}
      for _, p in ipairs(setup.bots(players)) do
        if get_counter_value(p.score_counter) == best then bots[#bots + 1] = p end
      end
      if #bots > 0 then return bots end       -- several ARNOs tied: they share the win
      return orig(...)
    end
  end)

  -- H19 (owner request): undo hint in the human action panel
  wrap("H19", "action_selection_panel_xml", function(orig)
    return function(...)
      local xml = orig(...)
      if type(xml) ~= "string" then return xml end
      return require("ui.hint").add_undo_hint(xml)
    end
  end)

  -- panel after load/rewind (transient panels are rebuilt by the mod; add ours)
  wrap("PANEL", "resume_checkpoint", function(orig)
    return function(...)
      require("ui.panel").render(nil)
      return orig(...)
    end
  end)

  require("adapter.apply").install_hooks(wrap)
end

return M
