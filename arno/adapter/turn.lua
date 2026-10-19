-- ARNO 3.0 for "Ark Nova - Complete Scripted" (Tabletop Simulator).
-- ARNO solo mode designed by Andre K. See NOTICE.
--
-- ARNO's turn (docs/DESIGN.md §5, §8). Entered from the H9 wrapper of
-- create_action_selection_panel, i.e. after start_player_turn has set current_player
-- and stored the mod's "turn" checkpoint. Order of events:
--   0. wait until checkpoint_open == false: nothing in arno_state may change before the
--      checkpoint store has serialised it (otherwise a resume would replay another turn)
--   1. auto mode: 2 s grace (panel shows "ARNO is about to play"); manual: wait for button
--   2. draw card (core.decide), snapshot facts, build plan (core.plan), persist RNG
--   3. execute the plan step by step (adapter.apply), then end the turn through the mod

local state = require("adapter.state")
local decide = require("core.decide")
local plan = require("core.plan")
local panel = require("ui.panel")

local M = {}

M.AUTO_DELAY = 2
M.running = nil      -- color of the ARNO whose plan is executing (transient)
M.pending = nil      -- color of the ARNO waiting to start (transient)

local function describe(step)
  local k = step.kind
  if k == "appeal" or k == "reputation" or k == "conservation" or k == "break" then
    return string.format("%s +%d", k, step.n)
  elseif k == "token_scoring" then return "token on final scoring card"
  elseif k == "token_notepad" then return string.format("%d token(s) on notepad", step.n)
  elseif k == "take_display" then return "takes display card #" .. step.position
  elseif k == "worker" then return "association worker on task " .. step.task
  elseif k == "partner_zoo" then return "partner zoo " .. tostring(step.zoo)
  elseif k == "university" then
    return "university " .. tostring(step.name) .. (step.species and (" (" .. step.species .. ")") or "")
  elseif k == "project" then
    return string.format("supports project (%s) on slot %s, points of slot %s",
      step.pick, tostring(step.place_slot), tostring(step.reward_slot))
  elseif k == "donate" then return "donates (+1 CP)"
  elseif k == "skip" then return "skipped: " .. tostring(step.reason)
  end
  return k
end
M.describe = describe

-- H9: called instead of the human action panel.
function M.start(player, only_action, multiplier, hypnosis)
  if only_action ~= nil or multiplier ~= nil or hypnosis ~= nil then
    state.log("ignored a human-only action prompt for " .. player.steam_name)
    return
  end
  if M.running ~= nil or M.pending ~= nil then return end
  M.pending = player.color
  if cancel_rewind_spacer_timer then cancel_rewind_spacer_timer() end
  panel.render(nil)
  local function ready()
    -- ARNO's turn emits no spacer store (the checkpoint callback has just armed one)
    checkpoint_needs_spacer = false
    if not arno_state.auto then
      state.log(player.steam_name .. " is waiting: press 'Run ARNO turn'")
      panel.render(player.color)
      return
    end
    panel.render(player.color)
    Wait.time(function()
      if M.pending == player.color and arno_state.auto then M.run(player) end
    end, M.AUTO_DELAY)
  end
  local started = false
  local function once() if not started then started = true; ready() end end
  -- the checkpoint store callback comes from TTS; never let ARNO wait forever on it
  Wait.condition(once, function() return not checkpoint_open end, 10, function()
    state.log("checkpoint store did not confirm; ARNO plays anyway")
    checkpoint_open = false
    once()
  end)
end

-- Manual trigger / auto run. Safe to call twice: only runs for the pending ARNO.
function M.run(player)
  player = player or current_player
  if player == nil or not player.is_arno or M.running ~= nil then return end
  if checkpoint_open then return end          -- never decide before the checkpoint is stored
  M.pending = nil
  M.running = player.color
  local bot = state.bot(player.color)
  local r = state.rng()
  local record = decide.turn(bot, r)
  local facts = require("adapter.snapshot").facts(player, bot, record)
  local steps = plan.build(record, r, facts)
  state.put_rng(r)
  state.log(string.format("%s: slot %d, %s%s", player.steam_name, record.slot,
    record.card, record.upgraded and " (II)" or ""))
  require("adapter.apply").run(player, steps, describe, function()
    M.finish(player)
  end)
end

function M.finish(player)
  local apply = require("adapter.apply")
  apply.sync_action_cards(player)
  M.running = nil
  panel.render(nil)
  apply.end_turn(player)
end

return M
