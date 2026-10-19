-- Minimal Tabletop Simulator API stand-ins so the built Global.lua can be executed headless
-- (load-time only: function definitions, cnsts data, ARNO hook installation).
local vmt = {}
vmt.__index = vmt
vmt.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
vmt.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
vmt.__mul = function(a, k) return Vector(a.x * k, a.y * k, a.z * k) end
function Vector(x, y, z)
  if type(x) == "table" then return setmetatable({ x = x.x or x[1], y = x.y or x[2], z = x.z or x[3] }, vmt) end
  return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vmt)
end
Color = setmetatable({ fromString = function(s) return { s = s } end }, { __call = function(_, r, g, b) return { r, g, b } end })
JSON = { encode = function() return "{}" end, decode = function() return {} end }
Wait = { frames = function() end, time = function() end, condition = function() end, stop = function() end }
UI = { setXml = function() end, setAttribute = function() end, setAttributes = function() end, getXml = function() return "" end }
Player = setmetatable({ getPlayers = function() return {} end, getColors = function() return {} end }, { __index = function() return {} end })
Turns = {}
Hands = {}
Tables = {}
Lighting = {}
Physics = {}
Grid = {}
Notes = {}
Info = {}
Time = {}
self = {}
function getObjectFromGUID() return nil end
function getObjectsWithTag() return {} end
function getAllObjects() return {} end
function getSeatedPlayers() return {} end
function broadcastToAll() end
function broadcastToColor() end
function printToAll() end
function printToColor() end
function log() end
function spawnObject() return {} end
function startLuaCoroutine() end
function storeRewindState() end
function allowRewindStore() end
function addHotkey() end
function addContextMenuItem() end
function setNotes() end
