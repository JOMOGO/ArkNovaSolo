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
local levels = require("ai.levels")
local rng = require("core.rng")

local M = {}

M.MAX_STEPS_PER_TURN = 400
M.SETTLE_MAX_FRAMES = 120   -- about 2 s in TTS: longer than any card or tile move

M.policy = nil         -- function(player, choices) -> choice; default: seeded random
M.policies = {}        -- color -> policy, overrides M.policy for that seat
M.scheduled = {}       -- color -> true while a step is queued
M.busy = {}            -- color -> true while an input has not settled
M.steps = {}           -- color -> inputs since the AI's turn started
M.rejected = {}        -- fingerprint .. label -> true: inputs that changed nothing
M.tried = {}           -- fingerprint -> label -> times taken from that view this turn
M.MAX_REPEATS = 3
M.log = {}             -- recent lines, newest last
M.LOG_LINES = 200
M.on_error = nil       -- tests: function(color, message)

local function note(line)
  M.log[#M.log + 1] = line
  if #M.log > M.LOG_LINES then table.remove(M.log, 1) end
end
M.note = note

-- a seat's policy: a test override (M.policies, M.policy), else its level's
function M.policy_for(player)
  local color = player.color
  if M.policies[color] then return M.policies[color] end
  if M.policy then return M.policy end
  M.policies[color] = levels.policy(player.ai_level or "medium", os.time() + #color)
  return M.policies[color]
end

-- tests: every seat plays the seeded random policy unless M.policies says otherwise
function M.reset(seed)
  M.policy = policy.random(rng.new(seed or 1))
  M.policies = {}
  M.scheduled, M.busy, M.steps, M.log, M.rejected, M.tried = {}, {}, {}, {}, {}, {}
end

function M.turn_started(color)
  M.steps[color] = 0
  M.rejected, M.tried = {}, {}
end

M.QUIET_FRAMES = 3         -- the view must then hold still this long

-- polls once per frame until the view differs from `before` and has then not changed for
-- QUIET_FRAMES (the mod's callbacks of that input are done), or the frame budget is spent;
-- then calls done(changed)
local function await_change(player, before, done)
  local frames, last, quiet = 0, before, 0
  local function poll()
    frames = frames + 1
    local now = choices.fingerprint(player)
    if now ~= last then last, quiet = now, 0 else quiet = quiet + 1 end
    if last ~= before and quiet >= M.QUIET_FRAMES then return done(true) end
    if frames >= M.SETTLE_MAX_FRAMES then return done(last ~= before) end
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
  local view = choices.fingerprint(player)
  local list = {}
  for _, c in ipairs(all) do
    if not M.rejected[view .. "\0" .. c.label] then list[#list + 1] = c end
  end
  if #list == 0 then
    fail(color, "every input on offer was tried and changed nothing")
    return
  end
  -- back in a view seen before this turn: the choices not yet taken from it come first, so
  -- picking cards back and forth in front of a Confirm that cannot confirm ends (with Back)
  local tried = M.tried[view] or {}
  M.tried[view] = tried
  local least
  for _, c in ipairs(list) do
    local n = tried[c.label] or 0
    if least == nil or n < least then least = n end
  end
  if least >= M.MAX_REPEATS then
    fail(color, "every input on offer was taken " .. M.MAX_REPEATS .. " times from this view (loop?)")
    return
  end
  local fresh = {}
  for _, c in ipairs(list) do
    if (tried[c.label] or 0) == least then fresh[#fresh + 1] = c end
  end
  list = fresh

  M.steps[color] = (M.steps[color] or 0) + 1
  if M.steps[color] > M.MAX_STEPS_PER_TURN then
    fail(color, "more than " .. M.MAX_STEPS_PER_TURN .. " inputs this turn (loop?)")
    return
  end

  local pick = M.policy_for(player)(player, list)
  tried[pick.label] = (tried[pick.label] or 0) + 1
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

-- setup (AI3): every half second, a step for each AI seat, until the game has started
M.HEARTBEAT_SECONDS = 0.5
M.HEARTBEAT_MAX = 2400           -- 20 minutes of setup at most
function M.setup_heartbeat()
  local beats = 0
  local function beat()
    beats = beats + 1
    if game_started or beats > M.HEARTBEAT_MAX then return end
    for _, p in ipairs(players or {}) do
      if seat.is_ai(p) then M.wake(p.color) end
    end
    Wait.time(beat, M.HEARTBEAT_SECONDS)
  end
  Wait.time(beat, M.HEARTBEAT_SECONDS)
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
