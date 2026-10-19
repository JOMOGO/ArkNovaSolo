-- ARNO 3.0 for "Ark Nova - Complete Scripted" (Tabletop Simulator).
-- ARNO solo mode designed by Andre K. See NOTICE.
--
-- Reads the table into the plain `facts` table that core.plan consumes (see plan.lua
-- header). This replaces every question the helper app asks the human (IN-03..IN-10).
-- Read-only: no mod state is changed here.

local decide = require("core.decide")
local tracker = require("core.project_tracker")

local M = {}

local function set_of(list)
  local s = {}
  for _, v in ipairs(list or {}) do s[v] = true end
  return s
end

local function project_entries(player)
  local out = {}
  for _, row in ipairs({ { "base", base_projects or {} }, { "added", added_projects or {} } }) do
    for i, entry in ipairs(row[2]) do
      local obj = getObjectFromGUID(entry[1])
      if obj ~= nil then
        local cubes = entry[2] or {}
        local free, player_token = {}, false
        for slot = 1, 3 do
          local guid = cubes[slot]
          free[slot] = guid == nil
          if guid ~= nil then
            local cube = getObjectFromGUID(guid)
            if cube ~= nil and cube_owner_color(cube) ~= nil then player_token = true end
          end
        end
        out[#out + 1] = {
          id = row[1] .. ":" .. i,
          arno_supported = project_already_supported(player, cubes),
          player_token = player_token,
          free = free,
        }
      end
    end
  end
  return out
end

function M.facts(player, bot, record)
  local tasks = {}
  for _, w in ipairs(player.deployed_workers or {}) do tasks[w.task] = true end
  local unis = { available = {}, species = {}, owned = #(player.acquired_universities or {}),
                 count = marine_worlds_enabled and 4 or 3 }
  for _, name in ipairs(available_universities(player, false)) do
    if cnsts.universities[name] and cnsts.universities[name].species then
      unis.species[name] = true
    else
      unis.available[name] = true
    end
  end
  local facts = {
    level = bot.level,
    upgraded = record and record.upgraded or false,
    workers_free = (player.worker_count or 1) - #(player.deployed_workers or {}),
    worker_tasks = tasks,
    zoos = { available = set_of(available_partner_zoos(player, false)),
             owned = #(player.acquired_partner_zoos or {}) },
    universities = unis,
    projects = { mat = bot.mat_projects or {}, board = project_entries(player) },
  }
  if arno_state.project_module then
    facts.project_module = { preferred = tracker.preferred_slots(tracker.position(bot.sponsor_discards or 0)) }
  end
  return facts
end

return M
