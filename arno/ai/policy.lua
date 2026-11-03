-- AI opponent (docs/AI_OPPONENT.md §4): picks one of the choices ai.choices lists.
-- For now only the policies the no-stall tests need (milestone M1):
--   random  a seeded random legal choice; Back/Cancel only when nothing else is offered
--           (going back and forth would never end a turn), Pass less often than the rest
--   first   the first choice that is not Back (the every-card driver's habit)
-- The level policies (network, point budget, personalities, lookahead) come later.

local rng = require("core.rng")

local M = {}

M.PASS_WEIGHT = 0.25

local function forward(choices)
  local out = {}
  for _, c in ipairs(choices) do
    if c.tag ~= "back" then out[#out + 1] = c end
  end
  if #out == 0 then return choices end
  return out
end

function M.random(r)
  return function(_, choices)
    local pool = forward(choices)
    local total = 0
    for _, c in ipairs(pool) do total = total + (c.tag == "pass" and M.PASS_WEIGHT or 1) end
    local x = rng.next(r) * total
    for _, c in ipairs(pool) do
      x = x - (c.tag == "pass" and M.PASS_WEIGHT or 1)
      if x < 0 then return c end
    end
    return pool[#pool]
  end
end

function M.first()
  return function(_, choices) return forward(choices)[1] end
end

-- ---------------------------------------------------------------- hand-written policy
-- Scores every choice in points with ai.value and takes the best (ties broken by the
-- seeded RNG). The bootstrap for the network (docs/AI_OPPONENT.md §4a) and its fallback.

local value = require("ai.value")
local choices_mod = require("ai.choices")

local function panel_id(player)
  local xml = active_panels and active_panels[player.color]
  return xml and xml:match('id="(%a+)')
end

local function card_label(label)
  return label:match(": (.+)$") or label
end

local function placement_value(player, choice)
  local state = tile_placements and tile_placements[player.color]
  local opts = (state and state.opts) or (player.pending_building and player.pending_building.opts) or {}
  local v = 0
  -- the map rewards under the tile (Board:previewReward: tags like "x_token", "2 money")
  local ok, reward = pcall(function() return player.map:previewReward(choice.cells, opts) end)
  if ok and type(reward) == "table" then
    for _, tag in ipairs(reward.tags or {}) do v = v + value.reward(tostring(tag), player) end
    if reward.clearedBoard then v = v + 5 end
  end
  return v
end

local function enclosure_value(player, choice)
  local id = tonumber(choice.label:match("(%d+)$") or "")
  local tile = id and player.map.tiles[id]
  if tile == nil then return 0 end
  -- the smallest enclosure that fits, so the big ones stay free for big animals
  return -#tile.cells * 0.3
end

local function selection_value(player, card_value)
  local state = selection_panels and selection_panels[player.color]
  local action = state and state.action or ""
  if action:find("discard", 1, true) or action == "sell" then return -card_value end
  return card_value
end

-- choices decided by a fixed rule, over the hand-written scores and the network (nil: none)
--   Back last (it never ends a turn by itself); a venom fee paid as soon as offered;
--   spreading an animal's cubes over several aquariums (allocate): + until the cubes are
--   placed (a + on a full enclosure changes nothing and drops out), never -, then Confirm.
--   (Left to the network, the + and - went round in circles: found in round-2 self-play.)
local ALLOCATE_CONFIRM = { on_animal_allocate_confirm_clicked = true, on_enclosure_vacate_allocate_confirm_clicked = true }
local ALLOCATE_SPIN = { on_animal_allocate_spin = true, on_enclosure_vacate_allocate_spin = true }
function M.rule(player, c)
  if c.tag == "back" then return -1000 end
  if (c.label or ""):find("Venom Fee", 1, true) then return 1000 end
  if ALLOCATE_CONFIRM[c.handler or ""] then return 1000 end
  if ALLOCATE_SPIN[c.handler or ""] then
    return (c.arg or ""):find("|up$") and 500 or -500
  end
  return nil
end

function M.score(player, c)
  local ruled = M.rule(player, c)
  if ruled ~= nil then return ruled end
  local panel = panel_id(player)
  if c.kind == "click" then
    if c.handler == "on_action_card_button_clicked" then
      local strength = choices_mod.strength(player, c) or 1
      local v = value.action(c.label:match("^(%a+)") or c.label, strength, player)
      -- a venom fee is due: using the poisoned card settles it
      local slot = tonumber((c.arg or ""):match("_(%d+)$") or "")
      if player.venom_unpaid and slot and action_card_has_token(player, slot, "venom") then
        v = v + 1.5
      end
      return v
    end
    if c.handler == "on_take_x_token_clicked" then return 0.9 end
    -- (the venom fee is paid as soon as offered, M.rule: honest play; holding money back to
    -- pay less at the end, FIXVENOM, would be gaming the rule)
    -- the -1 condition / -3 conditions toggles: on when the chosen animal needs them
    if c.handler == "on_animal_discount_clicked" or c.handler == "on_animal_condition_token_clicked" then
      local state = animal_actions and animal_actions[player.color]
      if state and state.selected and not choices_mod.animal_playable(player, state, state.selected, false) then
        return 40
      end
      return -5
    end
    if c.handler == "on_x_token_spin_clicked" then return -1 end
    if c.handler and c.handler:find("spin", 1, true) then return 0 end
    if c.tag == "confirm" then return 30 end
    if c.tag == "pass" then return 0 end
    if panel == "incomePanel" or (c.handler or ""):find("income", 1, true) then return 5 end
    return value.reward(c.label, player)
  elseif c.kind == "pick_up" then
    local label = c.label
    local name = card_label(label)
    if label:find("^play animal") then
      -- (only playable animals are offered, ai.choices); display cards cost their slot
      local state = animal_actions and animal_actions[player.color]
      local pos = state and c.obj and state.offers[c.obj.getGUID()]
      return 10 + value.card(name, player) - (pos or 0) * value.money()
    elseif label:find("^select") then
      return selection_value(player, value.card(name, player))
    elseif label:find("^take from the deck") then
      return 1
    end
    return value.card(name, player)
  elseif c.kind == "drop_tile" then
    return placement_value(player, c)
  elseif c.kind == "pick_up_tile" then
    return enclosure_value(player, c)
  end
  return 0
end

-- { choice, score, heuristic } for every choice but Back (unless Back is all there is)
local function scored(player, choices)
  local out = {}
  for _, c in ipairs(forward(choices)) do
    local ok, s = pcall(M.score, player, c)
    s = (ok and type(s) == "number") and s or 0
    out[#out + 1] = { choice = c, score = s, heuristic = s }
  end
  return out
end

function M.heuristic(r)
  return M.budgeted(r, 0)
end

-- ---------------------------------------------------------------- assists
-- Points added to the network's Q of some choices (policy "network_a", opts.assist), for two
-- habits the network does not learn (docs/AI_OPPONENT.md §10, behaviour analysis): a hand full
-- of animals it cannot place (it never builds a special enclosure), and conservation projects
-- left unsupported. The shipped levels use M.ASSIST (ai.levels); a weight of 0 is off.
--   build  per animal in hand that has no enclosure now and would fit the one this choice
--          builds (half for an animal one condition short); half of that on the BUILD
--          action card, for the best such build it can afford at its strength
--   cp     on the ASSOCIATION action card when it can support a conservation project at
--          its strength (a worker free: the mod's own check), and on "Support a
--          Conservation Project" in the association panel
--   final  per CP a card play adds to the own final scoring card (the best one held), read
--          smoothly between the card's thresholds (so a step towards the next one counts),
--          times a CP's worth in points now; half of the best such play on the ANIMALS /
--          SPONSORS action card at its strength; and at the final scoring discard, minus a
--          card's award (it keeps the better card)
--   ending on an action card that would end the game (the own score crosses 100 with what
--          the action gives now, roughly) while the score at the end is short: own score +
--          own final scoring card vs the best other score + its final scoring (ARNO's tokens)
--          + its last turn (END_LAST_TURN); minus the points short, at most `ending` (0 when
--          short by more than END_RANGE: no waiting saves that game)
-- (round 17, docs/AI_OPPONENT.md §10: final 1 / 2 and ending 6 brought nothing against ARNO 1: off)
M.ASSIST = { build = 3, cp = 4, final = 0, ending = 0 }
M.END_LAST_TURN = 6       -- what the other player's last turn brings, roughly (traces: ~6)
M.END_OTHER_CP = 1.5      -- the final scoring CP of a player whose cards the AI cannot see
M.END_RANGE = 25

-- slots of a special enclosure (HexBoard SLOT_COUNTS) and the animal enclosure key it serves
local SPECIAL = {
  ["PETTING ZOO"] = { petting = true, slots = 3 },
  ["REPTILE HOUSE"] = { key = "repthouse", slots = 5 },
  ["LARGE BIRD AVIARY"] = { key = "aviary", slots = 5 },
  ["SMALL AQUARIUM"] = { key = "aquarium", slots = 2 },
  ["LARGE AQUARIUM"] = { key = "aquarium", slots = 5 },
}

local function has_icon(data, icon)
  for _, i in ipairs(data.icons or {}) do if i == icon then return true end end
  return false
end

-- would an animal fit a new building of this search name ("SIZE 3", "PETTING ZOO", ...)?
-- (as valid_animal_enclosures; terrain touches and size bonuses left out)
local function fits_new(data, search_name)
  local petting = has_icon(data, "petting")
  local special = SPECIAL[search_name]
  if petting then return special ~= nil and special.petting == true end
  local size = tonumber(search_name:match("^SIZE (%d)$") or "")
  if size then return not data.no_std_enc and (data.size or 0) <= size end
  if special and special.key and data.enclosure then
    local need = data.enclosure[special.key]
    return need ~= nil and need <= special.slots
  end
  return false
end

-- animals in hand helped by a new building: no enclosure fits now, the new one would
-- (conditions met: 1, one short: 1/2); at most as many as the building holds
function M.build_gain(player, search_name)
  local special = SPECIAL[search_name]
  if not (special or search_name:match("^SIZE %d$")) then return 0 end
  local n = 0
  for _, card in ipairs(player_hand_cards(player)) do
    local ok, data = pcall(card_data_for, card.getName())
    if ok and data and data.type == "animal" and fits_new(data, search_name)
       and not waza_assignment_blocks(data, player)
       and not animal_fits_enclosure(data, player) then
      local unmet = animal_conditions_unmet(data, player)
      if unmet <= 0 then n = n + 1 elseif unmet == 1 then n = n + 0.5 end
    end
  end
  return math.min(n, special and special.slots or 1)
end

local function action_card_num(player, slot)
  local ok, name = pcall(function() return action_card_object(player, slot).getName() end)
  return ok and name and string.sub(name, -1) or "0"
end

local function build_card_gain(player, c)
  local slot = tonumber((c.arg or ""):match("_(%d+)$") or "")
  local strength = choices_mod.strength(player, c)
  if slot == nil or strength == nil then return 0 end
  local num = action_card_num(player, slot)
  local best = 0
  for _, cand in ipairs(build_candidates(player, { upgd = player.build_flipped, num = num, built = {},
                                                   remaining = strength + (num == "3" and 1 or 0) })) do
    best = math.max(best, M.build_gain(player, cand.option.search_name))
  end
  return best
end

local function association_card_supports(player, c)
  local slot = tonumber((c.arg or ""):match("_(%d+)$") or "")
  local strength = choices_mod.strength(player, c)
  if slot == nil or strength == nil then return false end
  local num = action_card_num(player, slot)
  local upgd = player.association_flipped
  return association_task_open(player, 5, strength, num, upgd, false)
    or (association_extra_worker_allowed(num, upgd)
        and association_task_open(player, 5, strength, num, upgd, true))
end

-- ---- final scoring cards (final): the award read smoothly between the thresholds
local function smooth_award(rule, count)
  local cp
  if rule.bands then
    local pts = { { 0, 0 } }
    for i = #rule.bands, 1, -1 do pts[#pts + 1] = rule.bands[i] end
    cp = pts[#pts][2]
    for i = 1, #pts - 1 do
      local a, b = pts[i], pts[i + 1]
      if count < b[1] then cp = a[2] + (b[2] - a[2]) * (count - a[1]) / (b[1] - a[1]) break end
    end
  elseif rule.divisor then cp = count / rule.divisor
  elseif rule.per then cp = count
  else cp = count - (rule.offset or 0) end
  return math.max(0, math.min(4, cp))
end
M.smooth_award = smooth_award

local function count_icons(data, icon)
  local n = 0
  for _, i in ipairs(data.icons or {}) do if i == icon then n = n + 1 end end
  return n
end

local function reward_amount(data, word)
  local n = 0
  if type(data.rewards) ~= "table" then return 0 end
  for _, r in ipairs(data.rewards) do
    if type(r) == "string" then
      local k, what = r:match("^(%d+) (%a+)$")
      if k and what == word then n = n + tonumber(k) end
    end
  end
  return n
end

-- how much playing a card (its data) adds to a final scoring count (nil: a count that a
-- card play does not move, or a card that does not count: projects, maps, majorities)
local FINAL_DELTA = {
  large_animals = function(d) return (d.type == "animal" and (d.size or 0) >= 4) and 1 or 0 end,
  small_animals = function(d) return (d.type == "animal" and (d.size or 9) <= 2) and 1 or 0 end,
  research_icons = function(d) return count_icons(d, "research") end,
  rock_icons = function(d) return count_icons(d, "rock") end,
  water_icons = function(d) return count_icons(d, "water") end,
  played_sponsors = function(d) return d.type == "sponsor" and 1 or 0 end,
  reputation = function(d) return reward_amount(d, "rep") end,
  played_conditions = function(d) return #(d.conditions or {}) end,
}

-- CP the play of a card (its data) adds to the best final scoring card held (smooth awards)
function M.final_gain(player, data)
  local before, after = 0, 0
  for _, card in ipairs(final_scoring_cards(player)) do
    local rule = final_scoring_data_for(card_number_of(card.getName()))
    if rule then
      local delta = rule.count and FINAL_DELTA[rule.count]
      local b, a
      if delta then
        local n = final_score_count(player, rule.count)
        b, a = smooth_award(rule, n), smooth_award(rule, n + delta(data))
      else
        b = final_score_award(player, rule); a = b
      end
      before, after = math.max(before, b), math.max(after, a)
    end
  end
  return after - before
end

-- a held final scoring card's award now (smooth between the thresholds), in CP
function M.final_card_award(player, name)
  local rule = final_scoring_data_for(card_number_of(name))
  if rule == nil then return 0 end
  if rule.count and FINAL_DELTA[rule.count] then return smooth_award(rule, final_score_count(player, rule.count)) end
  return final_score_award(player, rule)
end

local function card_final_bonus(player, name, w)
  local data = card_data_for(name)
  if data == nil or (data.type ~= "animal" and data.type ~= "sponsor") then return 0 end
  return w.final * M.final_gain(player, data) * value.cp(player)
end

local function animals_count(player, strength)
  return (strength >= (animals_upgraded(player) and 4 or 5)) and 2 or 1
end

local function affordable_animals(player)
  local out, money = {}, get_counter_value(player.money_counter)
  for _, a in ipairs(value.playable_animals(player)) do
    if a.cost <= money then out[#out + 1] = a end
  end
  return out
end

-- ---- the end of the game (ending)
local function points_of(player, data)
  return reward_amount(data, "appeal") + reward_amount(data, "cp") * value.cp(player)
end

local function cp_points(player, cp)
  local now = get_counter_value(player.cp_counter)
  return cp_to_score(now + cp) - cp_to_score(now)
end

-- the points a player gets at the final scoring: ARNO's tokens (less his CP debt); the own
-- best final scoring card (own = true); another player's estimated (END_OTHER_CP)
function M.final_points(player, own)
  local bot = arno_state and arno_state.bots and arno_state.bots[player.color]
  if bot then
    local cp = math.max(0, math.min(4, (bot.tokens_scoring or 0) - 2)) + (bot.tokens_notepad or 0)
    return cp_points(player, cp - math.min(cp, bot.cp_debt or 0))
  end
  if not own then return cp_points(player, M.END_OTHER_CP) end
  local best = 0
  for _, card in ipairs(final_scoring_cards(player)) do
    local rule = final_scoring_data_for(card_number_of(card.getName()))
    if rule then best = math.max(best, final_score_award(player, rule)) end
  end
  return cp_points(player, best)
end

-- the score an action card brings at once, roughly
local function action_points(player, kind, c, strength)
  if kind == "ANIMALS" then
    local v, money = 0, get_counter_value(player.money_counter)
    local list = affordable_animals(player)
    for i = 1, math.min(animals_count(player, strength), #list) do
      if list[i].cost <= money then
        v, money = v + points_of(player, card_data_for(list[i].name)), money - list[i].cost
      end
    end
    return v
  elseif kind == "SPONSORS" then
    local best = 0
    for _, cand in ipairs(playable_sponsor_candidates(player, strength)) do
      best = math.max(best, points_of(player, card_data_for(cand.obj.getName())))
    end
    return best
  elseif kind == "ASSOCIATION" then
    return association_card_supports(player, c) and 3 * value.cp(player) or 0
  elseif kind == "BUILD" then
    return 1
  end
  return 0
end

-- the points short at the end if this action card ends the game now (0: it does not end
-- it, or the game is won that way, or lost by more than END_RANGE)
function M.ending_shortfall(player, c, kind, strength)
  if game_end_triggered or #(players or {}) < 2 then return 0 end
  local score = get_counter_value(player.score_counter)
  local gain = action_points(player, kind, c, strength)
  if score >= cnsts.game_end_score or score + gain < cnsts.game_end_score then return 0 end
  local best
  for _, p in ipairs(players) do
    if p ~= player then
      local s = get_counter_value(p.score_counter) + M.final_points(p, false) + M.END_LAST_TURN
      if best == nil or s > best then best = s end
    end
  end
  local margin = score + gain + M.final_points(player, true) - best
  if margin >= 0 or margin < -M.END_RANGE then return 0 end
  return -margin
end

local function assist_bonus(player, c, w)
  local label = c.label or ""
  if c.kind == "pick_up" then
    if (w.final or 0) == 0 then return 0 end
    -- the final scoring discard: keep the card that scores more (the hand-written score and
    -- the network do not read these cards)
    local sel = selection_panels and selection_panels[player.color]
    local held = label:match("^select: (.+)$")
    if held and sel and sel.action == "final scoring discard" then
      return -w.final * M.final_card_award(player, held) * value.cp(player)
    end
    local name = label:match("^play animal: (.+)$") or label:match("^sponsor: (.+)$")
    return name and card_final_bonus(player, name, w) or 0
  end
  if c.kind ~= "click" then return 0 end
  if c.handler == "on_action_card_button_clicked" then
    local kind = label:match("^(%a+)")
    local v = 0
    if (w.ending or 0) ~= 0 and kind then
      local strength = choices_mod.strength(player, c)
      if strength then v = v - math.min(w.ending, M.ending_shortfall(player, c, kind, strength)) end
    end
    if (w.final or 0) ~= 0 and (kind == "ANIMALS" or kind == "SPONSORS") then
      local strength = choices_mod.strength(player, c)
      local best = 0
      if strength and kind == "ANIMALS" then
        for _, a in ipairs(affordable_animals(player)) do
          best = math.max(best, card_final_bonus(player, a.name, w))
        end
      elseif strength then
        for _, cand in ipairs(playable_sponsor_candidates(player, strength)) do
          best = math.max(best, card_final_bonus(player, cand.obj.getName(), w))
        end
      end
      v = v + 0.5 * best
    end
    if kind == "BUILD" and (w.build or 0) ~= 0 then
      return v + 0.5 * w.build * build_card_gain(player, c)
    elseif kind == "ASSOCIATION" and (w.cp or 0) ~= 0 and association_card_supports(player, c) then
      return v + w.cp
    end
    return v
  end
  if label:find("^Support a Conservation Project") then return w.cp or 0 end
  local building = label:match("^Build an? ([^\n]+)")
  if building and (w.build or 0) ~= 0 then
    building = building:gsub("%s*%(.*$", "")         -- "Build a Kiosk (3 money)", "(Engineer)"
    return w.build * M.build_gain(player, build_tile_search_name("Build a " .. building))
  end
  return 0
end

-- the assists' points for one choice under weights w ({ build, cp, final, ending }); 0 on any error
function M.assist_bonus(player, c, w)
  local ok, v = pcall(assist_bonus, player, c, w or M.ASSIST)
  if not ok and M.on_assist_error then M.on_assist_error(v, c) end     -- tests, analysis
  return (ok and type(v) == "number") and v or 0
end

-- the network's scores (Q: expected change of the margin, in points); the hand-written
-- score is one of its inputs. Falls back to the hand-written scores without weights.
local features = require("ai.features")
local net = require("ai.net")

-- set by the driver while the policy runs in its coroutine: the network's scoring then
-- yields every YIELD_EVERY choices, so a big decision is spread over several frames
M.yielding = false
M.YIELD_EVERY = 8

local function q_scored(player, choices, weights, assist)
  local list = scored(player, choices)
  if (weights == nil and not net.available()) or #list < 2 then return list end
  local version = features.version_of(weights or net.weights())     -- the inputs it was trained on
  local state = features.state(player, version)
  -- an ensemble does the work of all its members per choice: yield as often per pass
  local w = weights or net.weights()
  local every = math.max(1, math.floor(M.YIELD_EVERY / ((w and w.members) and #w.members or 1)))
  -- card-identity inputs (weights with `cards`): the card the choice is about, as in training
  local with_cards = net.cards_of(w) > 0
  for i, e in ipairs(list) do
    if M.yielding and i % every == 0 then coroutine.yield() end
    local x = {}
    for i, v in ipairs(state) do x[i] = v end
    for _, v in ipairs(features.choice(player, e.choice, e.heuristic, version)) do x[#x + 1] = v end
    -- rules over the network (M.rule); the assists (M.assist_bonus) on top of the network only
    local ruled = M.rule(player, e.choice)
    if ruled ~= nil then
      e.score = ruled
    else
      e.score = net.forward(x, weights, with_cards and features.card_number(e.choice) or nil)
      if assist then e.score = e.score + M.assist_bonus(player, e.choice, assist) end
    end
  end
  return list
end
M.q_scored = q_scored

-- the best choice, or (budget > 0) a seeded random one among those within `budget` points
-- of the best: a level that gives up points where choices are close.
-- opts.network: score with the network (when trained), else the hand-written scores
function M.budgeted(r, budget, opts)
  return function(player, choices)
    -- opts.weights: another network than the bundled one (training: new against current)
    -- opts.assist: true (M.ASSIST) or { build =, cp =, final =, ending = }: the assists on the network's Q
    local assist = opts and opts.assist
    if assist == true then assist = M.ASSIST end
    local list = (opts and opts.network) and q_scored(player, choices, opts.weights, assist) or scored(player, choices)
    local best
    for _, e in ipairs(list) do
      if best == nil or e.score > best then best = e.score end
    end
    local near, total = {}, 0
    for _, e in ipairs(list) do
      if e.score >= best - (budget or 0) - 1e-9 then
        -- opts.weight: a personality's preference among the choices within the budget
        e.weight = (opts and opts.weight) and opts.weight(player, e.choice) or 1
        near[#near + 1] = e
        total = total + e.weight
      end
    end
    local x, pick = rng.next(r) * total, near[#near]
    for _, e in ipairs(near) do
      x = x - e.weight
      if x < 0 then pick = e break end
    end
    if M.on_decision then M.on_decision(player, list, pick) end    -- training logs
    return pick.choice
  end
end

return M
