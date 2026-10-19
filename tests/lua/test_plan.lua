-- Rule-level tests for arno/core/plan.lua (reference/arno3.0 rules.pdf p4-p9, DESIGN.md §11).
local T = require("tests.lib")
local rng = require("core.rng")
local plan = require("core.plan")
local bot_actions = require("core.bot_actions")

local function record_for(card, upgraded, slot, level)
  local others = {}
  for _, n in ipairs({ "animals", "association", "sponsors", "build", "cards" }) do
    if n ~= card then others[#others + 1] = n end
  end
  local slots = {}
  for i = 1, slot - 1 do slots[#slots + 1] = others[i] end
  slots[#slots + 1] = card
  for i = slot, 4 do slots[#slots + 1] = others[i] end
  return bot_actions.with_slot({ slots = slots, upgraded = upgraded and { card } or {} }, level, slot, 0)
end

local function facts(over)
  local f = {
    level = 3,
    workers_free = 1, worker_tasks = {},
    zoos = { available = { america = true, europe = true, asia = true, africa = true, australia = true }, owned = 0 },
    universities = { available = { hand_size = true, double_research = true, double_rep = true },
                     owned = 0, count = 3, species = {} },
    projects = { mat = {}, board = { { id = "p1", arno_supported = false, player_token = false,
                                       free = { true, true, true } } } },
  }
  for k, v in pairs(over or {}) do f[k] = v end
  return f
end

local function kinds(steps)
  local out = {}
  for i, s in ipairs(steps) do out[i] = s.kind end
  return out
end

T.test("non-association card resolves in card order", function()
  local rec = record_for("cards", false, 3, 3)       -- CP 1, take card, break 1, appeal 2
  local steps = plan.build(rec, rng.new(1), facts())
  T.eq(kinds(steps), { "conservation", "take_display", "break", "appeal" })
  T.eq(steps[1].n, 1); T.eq(steps[3].n, 1); T.eq(steps[4].n, 2)
  T.ok(steps[2].position >= 1 and steps[2].position <= 6)
end)

T.test("sponsors I: scoring token, sponsors II: notepad", function()
  T.eq(kinds(plan.build(record_for("sponsors", false, 4, 3), rng.new(1), facts())),
       { "reputation", "token_scoring", "break" })
  local up = plan.build(record_for("sponsors", true, 4, 3), rng.new(1), facts())
  T.eq(kinds(up), { "appeal", "token_notepad", "break" }); T.eq(up[1].n, 4); T.eq(up[3].n, 4)
end)

T.test("association: worker on the slot's task", function()
  local steps = plan.build(record_for("association", false, 3, 3), rng.new(5), facts())
  T.eq(kinds(steps), { "worker", "partner_zoo" }); T.eq(steps[1].task, 3)
  T.ok(steps[2].zoo ~= nil)
end)

T.test("association: occupied task -> next higher free task (rules p7)", function()
  local steps = plan.build(record_for("association", false, 3, 3), rng.new(5),
    facts({ worker_tasks = { [3] = true } }))
  T.eq(steps[1].task, 4); T.eq(steps[2].kind, "university")
end)

T.test("association: no higher task -> next available lower task", function()
  local steps = plan.build(record_for("association", false, 5, 3), rng.new(5),
    facts({ worker_tasks = { [5] = true } }))
  T.eq(steps[1].task, 4)
  steps = plan.build(record_for("association", false, 5, 3), rng.new(5),
    facts({ worker_tasks = { [5] = true, [4] = true } }))
  T.eq(steps[1].task, 3)
end)

T.test("association: impossible task counts as occupied (rules p7)", function()
  local f = facts({ zoos = { available = {}, owned = 2 } })
  local steps = plan.build(record_for("association", false, 3, 3), rng.new(5), f)
  T.eq(steps[1].task, 4)
  f = facts({ projects = { mat = {}, board = {} } })
  steps = plan.build(record_for("association", false, 5, 3), rng.new(5), f)
  T.eq(steps[1].task, 4)
end)

T.test("association: no worker -> alternative CP+1, break+2, partner (no donation)", function()
  local f = facts({ workers_free = 0, zoos = { available = { asia = true }, owned = 1 },
                    universities = { available = { double_rep = true }, owned = 2, count = 3, species = {} } })
  local steps = plan.build(record_for("association", true, 2, 3), rng.new(9), f)
  T.eq(kinds(steps), { "conservation", "break", "partner_zoo" })
  T.eq(steps[1].n, 1); T.eq(steps[2].n, 2); T.eq(steps[3].zoo, "asia")   -- fewer zoos owned -> zoo
end)

T.test("fallback: preferred type unavailable -> that part is skipped", function()
  local f = facts({ workers_free = 0, zoos = { available = {}, owned = 0 },
                    universities = { available = { double_rep = true }, owned = 1, count = 3, species = {} } })
  local steps = plan.build(record_for("association", false, 2, 3), rng.new(9), f)
  T.eq(kinds(steps), { "conservation", "break", "skip" })
end)

T.test("donation only on side II with a worker placed (rules p8)", function()
  T.eq(kinds(plan.build(record_for("association", true, 2, 3), rng.new(3), facts())),
       { "worker", "reputation", "donate" })
  T.eq(kinds(plan.build(record_for("association", false, 2, 3), rng.new(3), facts())),
       { "worker", "reputation" })
end)

T.test("partner zoo reroll never lands on an unavailable zoo (rules p4)", function()
  for seed = 1, 300 do
    local zoo = plan._roll_partner_zoo(rng.new(seed), { australia = true, europe = true })
    T.ok(zoo == "australia" or zoo == "europe", "seed " .. seed .. " -> " .. tostring(zoo))
  end
end)

T.test("university: generic (MW) picks an available animal university", function()
  for seed = 1, 200 do
    local unis = { available = {}, owned = 0, count = 4, species = { bird = true, reptile = true } }
    local name, species = plan._roll_university(rng.new(seed), unis)
    T.eq(name, "species", "seed " .. seed)
    T.ok(species == "bird" or species == "reptile", "seed " .. seed .. " -> " .. tostring(species))
  end
end)

T.test("project slot by level: L1/2 right, L3/4 middle, L5+ left (rules p8)", function()
  local free = { true, true, true }
  for level, expected in pairs({ [1] = 3, [2] = 3, [3] = 2, [4] = 2, [5] = 1, [6] = 1 }) do
    local f = facts({ level = level, projects = { mat = {}, board = { { id = "p", arno_supported = false,
                      player_token = false, free = free } } } })
    local steps = plan.build(record_for("association", false, 5, level), rng.new(level), f)
    T.eq(steps[2].kind, "project"); T.eq(steps[2].reward_slot, expected, "level " .. level)
    T.eq(steps[2].place_slot, expected)
  end
end)

T.test("project slot taken -> next to the left, else next to the right", function()
  T.eq(plan.choose_slot({ true, false, true }, "middle"), 1)
  T.eq(plan.choose_slot({ false, false, true }, "middle"), 3)
  T.eq(plan.choose_slot({ false, true, false }, "right"), 2)
  T.eq(plan.choose_slot({ false, false, false }, "left"), nil)
end)

T.test("project choice: 2+ cards on mat -> own card (rules p9)", function()
  local f = facts({ projects = { mat = { "a", "b" }, board = { { id = "p", arno_supported = false,
                    player_token = false, free = { true, true, true } } } } })
  for seed = 1, 50 do
    local s = plan.build(record_for("association", false, 5, 3), rng.new(seed), f)[2]
    T.eq(s.source, "mat"); T.ok(s.id == "a" or s.id == "b")
  end
end)

T.test("project choice: 0 on mat -> prefers projects without player tokens", function()
  local f = facts({ projects = { mat = {}, board = {
    { id = "taken", arno_supported = false, player_token = true, free = { true, false, true } },
    { id = "clean", arno_supported = false, player_token = false, free = { true, true, true } },
    { id = "mine", arno_supported = true, player_token = false, free = { true, true, true } } } } })
  for seed = 1, 50 do
    T.eq(plan.build(record_for("association", false, 5, 3), rng.new(seed), f)[2].id, "clean")
  end
end)

T.test("project module: placement from tracker, points from level (rules p11)", function()
  local f = facts({ level = 1, project_module = { preferred = { "left", "middle", "right" } } })
  local s = plan.build(record_for("association", false, 5, 1), rng.new(2), f)[2]
  T.eq(s.place_slot, 1); T.eq(s.reward_slot, 3)
end)

T.finish("plan")
