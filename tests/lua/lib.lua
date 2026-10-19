-- Minimal test harness for MoonSharp (no busted available in TTS's Lua subset).
-- test(name, fn); eq(actual, expected, msg) deep-compares; finish() errors on failure.
local T = { passed = 0, failed = 0, current = nil }

local function serialize(v, depth)
  depth = depth or 0
  if type(v) ~= "table" then
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
  end
  if depth > 4 then return "{...}" end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. serialize(v[k], depth + 1) end
  return "{" .. table.concat(parts, ", ") .. "}"
end
T.serialize = serialize

local function deep_equal(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not deep_equal(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end
T.deep_equal = deep_equal

function T.eq(actual, expected, msg)
  if not deep_equal(actual, expected) then
    error((msg or "values differ") .. "\n  expected: " .. serialize(expected) ..
      "\n  actual:   " .. serialize(actual), 2)
  end
end

function T.ok(cond, msg)
  if not cond then error(msg or "expected true", 2) end
end

function T.raises(fn, msg)
  local ok = pcall(fn)
  if ok then error(msg or "expected an error", 2) end
end

function T.test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    T.passed = T.passed + 1
  else
    T.failed = T.failed + 1
    print("FAIL " .. name .. ": " .. tostring(err))
  end
end

function T.finish(suite)
  print(string.format("%s: %d passed, %d failed", suite, T.passed, T.failed))
  if T.failed > 0 then error(suite .. " failed") end
end

return T
