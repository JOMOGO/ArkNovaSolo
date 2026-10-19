-- ARNO 3.0 for "Ark Nova - Complete Scripted" (Tabletop Simulator).
-- Port of brdgm/ark-nova-solo-helper (c) Stefan Seifert, Apache License 2.0.
-- ARNO solo mode designed by Andre K. See NOTICE. Modified: ported to Lua (MoonSharp).
--
-- Seeded randomness. mulberry32 on unsigned 32-bit values, written so that every
-- intermediate fits in a double exactly (MoonSharp has no integers). The dice helpers
-- keep the exact formulas of @brdgm/brdgm-commons (rollDice, rollDiceDifferentValue,
-- randomEnum, randomEnumDifferentValue) and lodash.shuffle, so the same stream gives the
-- same results as the TypeScript (tests/harness).

local M = {}

local TWO32 = 4294967296

-- MoonSharp's bit32 is wrong for arguments >= 2^31 (bit32.bxor(3000000000, 1) == 1,
-- found by tests/lua/test_differential.lua). So 32-bit bit ops are done on 16-bit halves,
-- where bit32 is exact, and shifts are done arithmetically.
local function split(x)
  local lo = x % 65536
  return (x - lo) / 65536, lo
end

local function bxor(a, b)
  local ah, al = split(a)
  local bh, bl = split(b)
  return bit32.bxor(ah, bh) * 65536 + bit32.bxor(al, bl)
end

local function bor(a, b)
  local ah, al = split(a)
  local bh, bl = split(b)
  return bit32.bor(ah, bh) * 65536 + bit32.bor(al, bl)
end

local function rshift(a, n)
  return math.floor(a / 2 ^ n)
end

-- low 32 bits of a*b for unsigned 32-bit a, b (Math.imul without the sign)
local function imul(a, b)
  local alo = a % 65536
  local ahi = (a - alo) / 65536
  return (alo * b + ((ahi * b) % 65536) * 65536) % TWO32
end

function M.new(seed)
  return { s = math.floor(seed) % TWO32 }
end

-- float in [0, 1); advances r.s
function M.next(r)
  local a = (r.s + 0x6D2B79F5) % TWO32
  r.s = a
  local t = imul(bxor(a, rshift(a, 15)), bor(1, a))
  t = bxor((t + imul(bxor(t, rshift(t, 7)), bor(61, t))) % TWO32, t)
  return bxor(t, rshift(t, 14)) / TWO32
end

-- rollDice(maxValue): 1..n
function M.dice(r, n)
  if n < 1 then error("Unable to roll a dice " .. tostring(n)) end
  return math.floor(M.next(r) * n) + 1
end

local function contains(list, value)
  for _, v in ipairs(list) do
    if v == value then return true end
  end
  return false
end

-- rollDiceDifferentValue(maxValue, ...currentValue)
function M.dice_different(r, n, current)
  if n < 2 or #current > n - 1 then
    error("Unable to roll a dice " .. tostring(n) .. " with a different value.")
  end
  local value = M.dice(r, n)
  if contains(current, value) then return M.dice_different(r, n, current) end
  return value
end

-- randomEnum(anEnum) for a string enum given as its ordered value list
function M.random_enum(r, values)
  return values[math.floor(M.next(r) * #values) + 1]
end

-- randomEnumDifferentValue(anEnum, ...currentValue)
function M.random_enum_different(r, values, current)
  if #values < 2 or #current > #values - 1 then
    error("Unable to randomly choose a different value from an enum with a single value.")
  end
  local value = M.random_enum(r, values)
  if contains(current, value) then return M.random_enum_different(r, values, current) end
  return value
end

-- lodash.shuffle: returns a shuffled copy (shuffleSelf with baseRandom(index, lastIndex))
function M.shuffle(r, list)
  local out = {}
  for i, v in ipairs(list) do out[i] = v end
  local length = #out
  for index = 0, length - 1 do
    local rand = index + math.floor(M.next(r) * (length - 1 - index + 1))
    out[rand + 1], out[index + 1] = out[index + 1], out[rand + 1]
  end
  return out
end

return M
