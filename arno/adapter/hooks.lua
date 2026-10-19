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
    -- ARNOs are prepared one after another: map A's start kiosk is cloned from a template
    -- that building_clone_source takes out of the bag asynchronously, so a second ARNO in
    -- the same frame finds the bag empty ("no KIOSK in the building bag", found in play)
    return function(...)
      if not state.active() or setup.window_open or setup.preparing then return orig(...) end
      local args = { ... }
      local bots = setup.bots(players)
      setup.preparing = true
      local function prepare(i)
        if i > #bots then
          setup.preparing = false
          setup.open_window()
          return orig((table.unpack or unpack)(args))
        end
        setup.prepare_bot(bots[i])
        local function next_bot() prepare(i + 1) end
        Wait.condition(next_bot, function() return building_parents["KIOSK"] ~= nil end, 10, next_bot)
      end
      prepare(1)
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

  -- H6: ARNO's action cards were dealt from his colour's zone earlier (prepare_bot), so that
  -- zone is empty when the mod removes the leftover decks; skip missing decks
  -- (found in play: "attempt to index a nil value" in destruct_action_card_decks)
  wrap("H6", "destruct_action_card_decks", function(orig)
    return function(...)
      if not state.active() then return orig(...) end
      for _, zones in pairs(cnsts.action_card_init_zones) do
        for _, guid in pairs(zones) do
          local zone = getObjectFromGUID(guid)
          local deck = zone and getDeck(zone)
          if deck ~= nil then deck.destruct() end
        end
      end
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

  -- H20 (owner request): "Back to action choice" right after choosing an action
  local back = require("adapter.back")
  wrap("H20", "on_action_card_button_clicked", function(orig)
    return function(p, value, id)
      local color, slot = tostring(value):match("^(%a+)_(%d+)$")
      local sel = color and action_selection_state[color]
      local snap = sel and back.capture(sel.player, tonumber(slot), sel)
      back.capturing = snap
      local ok, r = pcall(orig, p, value, id)
      back.capturing = nil
      if not ok then error(r, 0) end
      if snap ~= nil then back.offer(snap) end
      return r
    end
  end)
  -- Association tasks 3/4/5 get their own Back (to the task list), owner request
  wrap("H20", "on_claim_button_clicked", function(orig)
    return function(p, value, id)
      local color = tostring(value):match("^(%a+)_")
      local player = color and claims_players[color]
      local snap = nil
      if player ~= nil and not is_bot(player)
          and (association_actions[color] ~= nil or sponsor_actions[color] ~= nil) then
        snap = back.capture_task(player)
      end
      back.recent[color or ""] = nil
      back.task_started = nil
      local ok, r = pcall(orig, p, value, id)
      local started = back.task_started
      back.task_started = nil
      if not ok then error(r, 0) end
      if snap ~= nil and started ~= nil then
        if started == "sponsor" then
          snap.label = "Back to sponsor choice"
          snap.assoc = nil
        else
          snap.sponsor = nil
        end
        back.offer(snap)
      end
      return r
    end
  end)
  wrap("H20", "take_association_task", function(orig)
    return function(player, task, ...)
      if task == 3 or task == 4 or task == 5 then back.task_started = task end
      return orig(player, task, ...)
    end
  end)

  wrap("H20", "open_sponsor_panel", function(orig)
    return function(player, additional, ...)
      if additional == nil then back.task_started = "sponsor" end
      return orig(player, additional, ...)
    end
  end)

  -- Cards moves the break token on choosing; hold that back until the choice is committed
  wrap("H20", "break_x", function(orig)
    return function(n, player, ...)
      local snap = back.capturing
      if snap ~= nil and player == snap.player then
        snap.held_breaks[#snap.held_breaks + 1] = n
        return
      end
      return orig(n, player, ...)
    end
  end)
  -- panels shown while Back is available get the button too
  wrap("H20", "set_player_panel", function(orig)
    return function(color, xml, refresh)
      if back.pending[color] ~= nil then xml = back.add_button(color, xml) end
      return orig(color, xml, refresh)
    end
  end)
  -- any further interaction commits the choice (the Back handler itself is not on_*,
  -- so the mod's interaction wrapper does not call this for it)
  wrap("H20", "note_player_interaction", function(orig)
    return function(...)
      back.clear_all()
      return orig(...)
    end
  end)
  wrap("H20", "onObjectPickUp", function(orig)
    return function(color, obj, ...)
      back.clear(color)
      return orig(color, obj, ...)
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
