-- Whole games of AI seats on the BUILT Global.lua (docs/AI_OPPONENT.md, milestone M1):
-- 2 to 4 AI seats with a random policy play from the first turn through breaks (hand limit,
-- display, income) to the game end and the final scoring, through the mod's real game loop
-- (tests.ai_game, sim.ai_table).
-- Fails on: a Lua error, a stall (no AI has anything to do and the game is not over), or a
-- loop (the driver's step cap). A game that reaches the turn cap or empties the zoo deck is
-- counted, not failed: random play can take very long to score 100 points.
local T = require("tests.lib")
local OPTIONS = require("tests.options")
local game = require("tests.ai_game")

local GAMES = OPTIONS.quick and 4 or (OPTIONS.games or 20)
local outcomes = {}
for seed = 1, GAMES do
  local mw = seed % 3 == 0
  local colors = ({ { "Red", "Blue" }, { "Red", "Blue", "Yellow" }, { "Red", "Blue", "Yellow", "White" } })
    [seed % 5 == 0 and 2 or seed % 7 == 0 and 3 or 1]
  T.test(string.format("%d AI seats, seed %d%s", #colors, seed, mw and " (Marine Worlds)" or ""), function()
    local outcome, turns, scores = game.play(seed, { colors = colors, mw = mw })
    outcomes[outcome] = (outcomes[outcome] or 0) + 1
    local list = {}
    for _, color in ipairs(colors) do list[#list + 1] = scores[color] end
    print(string.format("  seed %d: %s after %d turns, scores %s", seed, outcome, turns, table.concat(list, " / ")))
  end)
end

local summary = {}
for k, n in pairs(outcomes) do summary[#summary + 1] = k .. " " .. n end
table.sort(summary)
print("AI games: " .. table.concat(summary, ", "))

T.finish("integration AI games")
