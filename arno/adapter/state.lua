-- ARNO 3.0 for "Ark Nova - Complete Scripted" (Tabletop Simulator).
-- ARNO solo mode designed by Andre K. See NOTICE.
--
-- The persistent ARNO state: the global `arno_state`, which is added to the mod's
-- cnsts.saved_globals (see hooks.lua) so it is written into every checkpoint and
-- restored on load/rewind. Everything in it must survive TTS JSON: plain tables,
-- strings, small numbers. The RNG state is kept as two 16-bit halves because large
-- numbers may be printed in exponent form by JSON.encode.

local rng = require("core.rng")

local M = {}

M.VERSION = 1
M.LOG_LINES = 30

function M.get()
  return arno_state
end

function M.active()
  return arno_state ~= nil and arno_state.bots ~= nil and next(arno_state.bots) ~= nil
end

function M.init(seed, options)
  local s = math.floor(seed) % 4294967296
  arno_state = {
    version = M.VERSION,
    seed = string.format("%08x", s),
    rng = { hi = math.floor(s / 65536), lo = s % 65536 },
    auto = true,
    project_module = options and options.project_module or false,
    bots = {},
    order = {},
    log = {},
  }
  return arno_state
end

function M.bot(color)
  if arno_state == nil or arno_state.bots == nil then return nil end
  return arno_state.bots[color]
end

function M.rng()
  local s = arno_state.rng
  return rng.new(s.hi * 65536 + s.lo)
end

function M.put_rng(r)
  arno_state.rng = { hi = math.floor(r.s / 65536), lo = r.s % 65536 }
end

M.COLOR_HEX = { White = "#FFFFFF", Red = "#E5484D", Blue = "#3B9BFF", Yellow = "#EBD717" }
local CHAT_RGB = { White = { 1, 1, 1 }, Red = { 0.9, 0.28, 0.3 }, Blue = { 0.23, 0.61, 1 }, Yellow = { 0.92, 0.84, 0.09 } }

-- Chat only (not in the panel).
function M.chat(text)
  if printToAll then printToAll("[ARNO] " .. text, { 0.92, 0.84, 0.09 }) end
end

-- What an ARNO did: kept as his "last turn" lines (shown in the panel in his colour),
-- added to the history log and printed to chat in his colour.
function M.note(player, text)
  local color = type(player) == "table" and player.color or player
  local bot = M.bot(color)
  if bot ~= nil then
    bot.last_turn = bot.last_turn or {}
    bot.last_turn[#bot.last_turn + 1] = text
    while #bot.last_turn > 14 do table.remove(bot.last_turn, 1) end
  end
  local name = bot and bot.name or "ARNO"
  M.log(name .. ": " .. text, CHAT_RGB[color])
end

-- Start a fresh "last turn" list for this ARNO.
function M.new_turn(player, header)
  local bot = M.bot(player.color)
  if bot ~= nil then bot.last_turn = {} end
  M.note(player, header)
end

-- History log (persisted, not shown in the panel) and chat.
function M.log(text, color)
  local log = arno_state and arno_state.log
  if log ~= nil then
    log[#log + 1] = text
    while #log > M.LOG_LINES do table.remove(log, 1) end
  end
  if printToAll then printToAll("[ARNO] " .. text, color or { 0.92, 0.84, 0.09 }) end
end

return M
