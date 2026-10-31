-- AI opponent (docs/AI_OPPONENT.md §3): answers whatever the mod asks an AI seat, one input
-- per frame, through ai.inputs only. Woken by the panel hook (ai.hooks) whenever an AI
-- colour gets a panel, and by itself after each input until there is nothing to answer.
--
-- Guards:
--   * one input at a time per colour: the next step waits until the input has settled
--     (tile drops report a few frames later) and the mod has reacted to it: what the AI
--     sees (ai.choices.fingerprint) changed, or SETTLE_MAX_FRAMES went by. Acting earlier
--     would race the mod's own callbacks (a second card taken while the first one is
--     still being dealt ends a reputation draw twice: found by tests/lua/int_ai.lua);
--   * an input the mod did not take in (nothing changed) is not offered again for the same
--     view, as a human stops clicking a button that does nothing;
--   * a step cap per turn, so a loop in a policy or the mod shows up as an error in the log
--     instead of a game that never ends.

local seat = require("ai.seat")
local choices = require("ai.choices")
local policy = require("ai.policy")
local rng = require("core.rng")

local M = {}

M.MAX_STEPS_PER_TURN = 400
M.SETTLE_MAX_FRAMES = 120   -- about 2 s in TTS: longer than any card or tile move

M.policy = nil         -- function(player, choices) -> choice; default: seeded random
M.scheduled = {}       -- color -> true while a step is queued
M.busy = {}            -- color -> true while an input has not settled
M.steps = {}           -- color -> inputs since the AI's turn started
M.rejected = {}        -- fingerprint .. label -> true: inputs that changed nothing
M.log = {}             -- recent lines, newest last
M.LOG_LINES = 200
M.on_error = nil       -- tests: function(color, message)

local function note(line)
  M.log[#M.log + 1] = line
  if #M.log > M.LOG_LINES then table.remove(M.log, 1) end
end
M.note = note

function M.reset(seed)
  M.policy = policy.random(rng.new(seed or 1))
  M.scheduled, M.busy, M.steps, M.log, M.rejected = {}, {}, {}, {}, {}
end

function M.turn_started(color)
  M.steps[color] = 0
  M.rejected = {}
end

-- polls once per frame until the view differs from `before`, or the frame budget is spent;
-- then calls done(changed)
local function await_change(player, before, done)
  local frames = 0
  local function poll()
    frames = frames + 1
    if choices.fingerprint(player) ~= before then return done(true) end
    if frames >= M.SETTLE_MAX_FRAMES then return done(false) end
    Wait.frames(poll, 1)
  end
  Wait.frames(poll, 1)
end

local function fail(color, message)
  note("ERROR " .. color .. ": " .. message)
  if M.on_error then M.on_error(color, message) end
end

function M.step(color)
  local player = seat.player(color)
  if not seat.is_ai(player) or M.busy[color] then return end

  local all = choices.list(player)
  if #all == 0 then return end               -- nothing to answer: the turn moved on
  local view = choices.fingerprint(player, all)
  local list = {}
  for _, c in ipairs(all) do
    if not M.rejected[view .. "\0" .. c.label] then list[#list + 1] = c end
  end
  if #list == 0 then
    fail(color, "every input on offer was tried and changed nothing")
    return
  end

  M.steps[color] = (M.steps[color] or 0) + 1
  if M.steps[color] > M.MAX_STEPS_PER_TURN then
    fail(color, "more than " .. M.MAX_STEPS_PER_TURN .. " inputs this turn (loop?)")
    return
  end

  if M.policy == nil then M.reset(1) end
  local pick = M.policy(player, list)
  note(string.format("%s %s: %s", color, pick.kind, pick.label))
  M.busy[color] = true
  local ok, err = pcall(pick.apply, function()
    await_change(player, view, function(changed)
      if not changed then M.rejected[view .. "\0" .. pick.label] = true end
      M.busy[color] = nil
      M.wake(color)
    end)
  end)
  if not ok then
    M.busy[color] = nil
    fail(color, tostring(err))
  end
end

function M.wake(color)
  if M.scheduled[color] then return end
  M.scheduled[color] = true
  Wait.frames(function()
    M.scheduled[color] = nil
    M.step(color)
  end, 1)
end

return M
