-- Integration test on the BUILT Global.lua: ARNO's step runner against the mod's real claims
-- engine (create_claims_*, render_claims_table, apply_reward_string, unlock_worker), with only
-- physical primitives replaced. Checks: no panel, no early turn end, rewards per R17/R19.
local T = require("tests.lib")

local function run_steps(p, steps)
  local done = 0
  require("adapter.apply").run(p, steps, require("adapter.turn").describe, function() done = done + 1 end)
  sim.pump()
  return done
end

T.test("CP debt, 2-CP worker, upgrades from partner zoo and reputation track", function()
  local p, bot = sim.setup_game()
  local done = run_steps(p, {
    { kind = "conservation", n = 7 },            -- 5 pay debt, 2 CP -> 2-CP bonus = worker (R17)
    { kind = "partner_zoo", zoo = "america" },   -- partner 1: no map reward
    { kind = "partner_zoo", zoo = "europe" },    -- partner 2: map A "card flip" -> upgrade
    { kind = "reputation", n = 9 },              -- 1 -> 10: 5 card flip, 8 unlock worker, 10 draw (ignored)
    { kind = "donate", cp = 1 },
  })
  T.eq(done, 1, "run finished exactly once")
  T.eq(bot.cp_debt, 0)
  T.eq(get_counter_value(p.cp_counter), 3, "2 from the CP step + 1 donation")
  T.eq(get_counter_value(p.rep_counter), 10)
  T.eq(p.worker_count, 3, "2-CP bonus worker + reputation 8 worker")
  T.eq(#bot.card_slots.upgraded, 2, "partner zoo 2 + reputation 5")
  T.eq(#p.claims, 0, "no claims left")
  T.eq(#sim.calls.finish_player_turn, 0, "mod's end of turn not reached by the claims engine")
  T.eq(get_counter_value(p.money_counter), 25, "no money for ARNO")
end)

T.test("reputation above 9 without Cards upgrade, overflow past 15 to appeal (R10)", function()
  local p = sim.setup_game()
  run_steps(p, { { kind = "reputation", n = 20 } })
  T.eq(get_counter_value(p.rep_counter), 15)
  T.eq(get_counter_value(p.appeal_counter), 6, "overflow 6 -> appeal")
end)

T.test("5 and 8 CP: variable bonus tiles only; usable ones applied (R17)", function()
  local p, bot = sim.setup_game()
  bot.cp_debt = 0
  run_steps(p, { { kind = "conservation", n = 8 } })
  T.eq((cp_bonuses_5[1] == nil) ~= (cp_bonuses_5[2] == nil), true, "exactly one 5-CP tile taken")
  T.eq((cp_bonuses_8[1] == nil) ~= (cp_bonuses_8[2] == nil), true, "exactly one 8-CP tile taken")
  T.eq(get_counter_value(p.money_counter), 25)
  T.eq(#p.claims, 0)
end)

T.test("10 CP triggers the humans' final-scoring discard and the run continues", function()
  local p, bot = sim.setup_game()
  bot.cp_debt = 0
  sim.record("prompt_final_scoring_discard", function(orig, player, count, pool, cb)
    if player.is_arno then return orig(player, count, pool, cb) end
    cb()                                        -- the human discards at once in this test
  end)
  local done = run_steps(p, { { kind = "conservation", n = 10 }, { kind = "appeal", n = 1 } })
  T.eq(final_scoring_discard_triggered, true)
  T.eq(done, 1)
  T.eq(get_counter_value(p.appeal_counter), 1, "step after the discard still ran")
end)

T.finish("integration claims")
