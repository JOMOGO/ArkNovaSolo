-- ARNO 3.0 for "Ark Nova - Complete Scripted" (Tabletop Simulator).
-- ARNO solo mode designed by Andre K. See NOTICE.
--
-- Rule choices that the helper app leaves to the human, taken from the printed ARNO 3.0
-- rules (reference/arno3.0 rules.pdf) or decided by the owner. One constant per entry of
-- docs/DESIGN.md §11 so that a ruling change is a one-line edit.

return {
  -- R3: Association fallback when no worker is left (rules p7, cards; app code)
  FALLBACK_CP = 1,
  FALLBACK_BREAK = 2,
  -- R2: donation only when a worker was placed and Association is on side II (rules p8)
  DONATE_CP = 1,
  -- R4: starting conservation debt; -3 with Marine Worlds' new action cards (rules p3, p9)
  START_CP_DEBT = 5,
  START_CP_DEBT_MW = 3,
  -- R10: no upgrade-gated limits for ARNO (rules p2)
  MAX_PARTNER_ZOOS = 4,
  MAX_UNIVERSITIES = 3,
  REPUTATION_MAX = 15,
  -- R17: from this many CP on, ARNO always takes the extra worker over other choices (rules p4)
  ALWAYS_WORKER_FROM_CP = 2,
  -- R19: bonus kinds ARNO receives (rules p2)
  ALLOWED_BONUSES = { appeal = true, cp = true, rep = true, upgrade = true, worker = true },
  -- R17: the only bonus tiles ARNO can use (rules p2)
  USABLE_BONUS_TILES = { partner_zoo = true, university = true, ["2 rep"] = true },
  -- R6 (owner): "lacks the most" = owns fewer of; tie -> d2
  -- R13 (owner): several ARNOs draw at breaks in the mod's income order
  -- R16: ARNO wins ties against humans (rules p10)
  ARNO_WINS_TIES = true,
}
