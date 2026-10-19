-- ARNO 3.0 for "Ark Nova - Complete Scripted" (Tabletop Simulator).
-- ARNO solo mode designed by Andre K. See NOTICE. Uses the ported helper logic in decide.lua.
--
-- Turns one drawn ARNO card into an ordered list of fully resolved steps, using a
-- snapshot of table facts. Pure: no TTS or mod access; all randomness through `r`.
-- Rules: reference/arno3.0 rules.pdf p4-p9; rulings: docs/DESIGN.md §11.
--
-- facts = {
--   level = 1..6, upgraded = bool (active card),           -- from the record
--   workers_free = n, worker_tasks = { [task] = true },     -- ARNO's association workers
--   zoos = { available = { name = true }, owned = n },      -- available = on board and not ARNO's
--   universities = { available = { name = true }, owned = n, count = 3|4,
--                    species = { animal = true } },          -- available species universities
--   projects = { mat = { id, ... },
--                board = { { id=, arno_supported=bool, player_token=bool, free={[1]=b,[2]=b,[3]=b} }, ... } },
--   project_module = nil | { preferred = { "right"|"middle"|"left", ... } },
-- }
-- step kinds: appeal, reputation, conservation, break, token_scoring, token_notepad,
--   take_display{position}, worker{task}, partner_zoo{zoo}, university{name, species},
--   project{source="mat"|"board", id, place_slot, reward_slot}, donate, skip{reason}

local rng = require("core.rng")
local decide = require("core.decide")
local rulings = require("core.rulings")

local M = {}

-- slot index on a project card: 1 = left (highest), 2 = middle, 3 = right (lowest)
M.SLOT_INDEX = { left = 1, middle = 2, right = 3 }

-- helper numbering (GainPartnerUniversity.vue) -> mod university keys
M.UNIVERSITY_BY_NUMBER = { "hand_size", "double_research", "double_rep", "species" }

local SIMPLE = {
  ["appeal"] = "appeal", ["reputation"] = "reputation", ["conservation"] = "conservation",
  ["break"] = "break", ["token-scoring-card"] = "token_scoring", ["token-notepad"] = "token_notepad",
}

local ASSOCIATION_TASK_BY_ACTION = {
  ["reputation"] = 2, ["gain-partner-zoo"] = 3, ["gain-partner-university"] = 4,
  ["conservation-project-work"] = 5,
}

local function count_true(set)
  local n = 0
  for _, v in pairs(set or {}) do if v then n = n + 1 end end
  return n
end

-- R5: roll, reroll results that are unavailable (excluding every value tried)
local function roll_partner_zoo(r, available)
  if count_true(available) == 0 then return nil end
  local tried = {}
  while true do
    local n = decide.partner_zoo_roll(r, tried)
    local zoo = decide.PARTNER_ZOOS[n]
    if available[zoo] then return zoo, tried end
    tried[#tried + 1] = n
  end
end

local function species_list(species)
  local out = {}
  for _, animal in ipairs(decide.ANIMAL_TYPES) do
    if species and species[animal] then out[#out + 1] = animal end
  end
  return out
end

local function roll_species(r, species)
  local tried = {}
  for _, animal in ipairs(decide.ANIMAL_TYPES) do
    if not species[animal] then tried[#tried + 1] = animal end
  end
  if #tried == #decide.ANIMAL_TYPES then return nil end
  if #tried == 0 then return decide.animal_type_roll(r) end
  return decide.animal_type_roll(r, tried)
end

local function university_possible(unis)
  for i = 1, unis.count do
    local key = M.UNIVERSITY_BY_NUMBER[i]
    if key == "species" then
      if #species_list(unis.species) > 0 then return true end
    elseif unis.available[key] then
      return true
    end
  end
  return false
end

local function roll_university(r, unis)
  if unis.owned >= rulings.MAX_UNIVERSITIES or not university_possible(unis) then return nil end
  local tried = {}
  while true do
    local n = decide.university_roll(r, unis.count, tried)
    local key = M.UNIVERSITY_BY_NUMBER[n]
    if key == "species" then
      if #species_list(unis.species) > 0 then
        return "species", roll_species(r, unis.species)
      end
    elseif unis.available[key] then
      return key, nil
    end
    tried[#tried + 1] = n
  end
end

-- R12: board projects ARNO may support
local function eligible_board_projects(projects)
  local no_token, available = {}, {}
  for _, p in ipairs(projects.board or {}) do
    local has_free = p.free[1] or p.free[2] or p.free[3]
    if not p.arno_supported and has_free then
      available[#available + 1] = p
      if not p.player_token then no_token[#no_token + 1] = p end
    end
  end
  return no_token, available
end

local function project_possible(projects)
  local _, available = eligible_board_projects(projects)
  return #(projects.mat or {}) > 0 or #available > 0
end

-- Rules p8: preferred slot by level; taken -> next to the left, else next to the right.
function M.choose_slot(free, preferred)
  local start = M.SLOT_INDEX[preferred]
  for s = start, 1, -1 do
    if free[s] then return s end
  end
  for s = start + 1, 3 do
    if free[s] then return s end
  end
  return nil
end

-- Project module (rules p10-11): placement follows the tracker's preference list.
local function module_slot(free, preferred_list)
  for _, name in ipairs(preferred_list) do
    local s = M.SLOT_INDEX[name]
    if free[s] then return s end
  end
  return nil
end

local function plan_project(r, facts)
  local projects = facts.projects
  local no_token, available = eligible_board_projects(projects)
  local pick = decide.pick_project(r, #(projects.mat or {}), #no_token, #available)
  local id, free
  if pick.source == "mat" then
    id = projects.mat[pick.number]
    free = { true, true, true }
  elseif pick.source == "no_token" then
    id, free = no_token[pick.number].id, no_token[pick.number].free
  elseif pick.source == "available" then
    id, free = available[pick.number].id, available[pick.number].free
  else
    return nil
  end
  local level_slot = decide.project_slot_for_level(facts.level)
  local reward_slot = M.choose_slot(free, level_slot)
  local place_slot = reward_slot
  if facts.project_module then
    place_slot = module_slot(free, facts.project_module.preferred) or reward_slot
  end
  return { kind = "project", source = pick.source == "mat" and "mat" or "board",
           pick = pick.source, id = id, place_slot = place_slot, reward_slot = reward_slot }
end

local function task_possible(task, facts)
  if task == 2 then return true end
  if task == 3 then
    return facts.zoos.owned < rulings.MAX_PARTNER_ZOOS and count_true(facts.zoos.available) > 0
  end
  if task == 4 then
    return facts.universities.owned < rulings.MAX_UNIVERSITIES and university_possible(facts.universities)
  end
  if task == 5 then return project_possible(facts.projects) end
  return false
end

-- Rules p7: occupied or impossible task -> next higher free task, else next lower.
function M.choose_task(start, facts)
  local order = { start }
  for t = start + 1, 5 do order[#order + 1] = t end
  for t = start - 1, 2, -1 do order[#order + 1] = t end
  for _, t in ipairs(order) do
    if not facts.worker_tasks[t] and task_possible(t, facts) then return t end
  end
  return nil
end

local function task_steps(task, r, facts, steps)
  if task == 2 then
    steps[#steps + 1] = { kind = "reputation", n = 2 }
  elseif task == 3 then
    local zoo = roll_partner_zoo(r, facts.zoos.available)
    steps[#steps + 1] = { kind = "partner_zoo", zoo = zoo }
  elseif task == 4 then
    local name, species = roll_university(r, facts.universities)
    steps[#steps + 1] = { kind = "university", name = name, species = species }
  elseif task == 5 then
    steps[#steps + 1] = plan_project(r, facts)
  end
end

-- R6 (owner): fewer owned; tie -> d2 (1 = zoo, 2 = university); none of that type -> skip
local function fallback_partner(r, facts, steps)
  local zoos, unis = facts.zoos.owned, facts.universities.owned
  local kind
  if zoos < unis then kind = 1
  elseif unis < zoos then kind = 2
  else kind = decide.zoo_or_university_roll(r) end
  if kind == 1 then
    if task_possible(3, facts) then
      steps[#steps + 1] = { kind = "partner_zoo", zoo = (roll_partner_zoo(r, facts.zoos.available)) }
    else
      steps[#steps + 1] = { kind = "skip", reason = "no partner zoo available" }
    end
  else
    if task_possible(4, facts) then
      local name, species = roll_university(r, facts.universities)
      steps[#steps + 1] = { kind = "university", name = name, species = species }
    else
      steps[#steps + 1] = { kind = "skip", reason = "no university available" }
    end
  end
end

local function plan_association(record, r, facts, steps)
  local task_action
  for _, a in ipairs(record.actions) do
    if ASSOCIATION_TASK_BY_ACTION[a.action] then task_action = a end
  end
  local task = nil
  if facts.workers_free > 0 and task_action then
    task = M.choose_task(ASSOCIATION_TASK_BY_ACTION[task_action.action], facts)
  end
  if task == nil then
    -- no worker available (or no task possible at all): the alternative (rules p7)
    steps[#steps + 1] = { kind = "conservation", n = rulings.FALLBACK_CP }
    steps[#steps + 1] = { kind = "break", n = rulings.FALLBACK_BREAK }
    fallback_partner(r, facts, steps)
    return
  end
  steps[#steps + 1] = { kind = "worker", task = task }
  task_steps(task, r, facts, steps)
  if record.upgraded then
    steps[#steps + 1] = { kind = "donate", cp = rulings.DONATE_CP }    -- R2
  end
end

-- record: decide.turn() result; facts: see header. Returns the list of steps.
function M.build(record, r, facts)
  local steps = {}
  if record.card == "association" then
    plan_association(record, r, facts, steps)
    return steps
  end
  for _, a in ipairs(record.actions) do
    local kind = SIMPLE[a.action]
    if kind == "token_scoring" then
      steps[#steps + 1] = { kind = kind }
    elseif kind then
      steps[#steps + 1] = { kind = kind, n = a.amount }
    elseif a.action == "take-card-display" then
      steps[#steps + 1] = { kind = "take_display", position = decide.display_position(r) }
    else
      steps[#steps + 1] = { kind = "skip", reason = "unexpected action " .. tostring(a.action) }
    end
  end
  return steps
end

M._roll_partner_zoo = roll_partner_zoo
M._roll_university = roll_university
return M
