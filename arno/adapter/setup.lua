-- ARNO 3.0 for "Ark Nova - Complete Scripted" (Tabletop Simulator).
-- ARNO solo mode designed by Andre K. See NOTICE.
--
-- Setup integration (docs/DESIGN.md §9, hooks H1-H3, H5-H8):
--  * setup panel rows: one ARNO toggle per unseated colour (Off / Level 1..10) + module
--  * add_bots: ARNO entries join `players` before setup_game builds components (H2)
--  * starting_player: a random HUMAN starts (H3, rules p3)
--  * humans-only window: from map setup until start_game the mod's simultaneous prompts
--    (maps, Marine Worlds draft, setup discard) run with `players` = humans only; ARNO
--    gets map A, his base action cards, his cards and CP debt separately (rules p3, p9).

local state = require("adapter.state")
local decide = require("core.decide")
local rulings = require("core.rulings")

local M = {}

M.COLORS = { "White", "Red", "Blue", "Yellow" }
M.MAX_LEVEL = 10       -- L7+ = level 6 values + 1 CP per level above 6 (rules p3, p5)

-- transient setup choices (before the game exists)
arno_setup = arno_setup or { levels = {}, project_module = false }

local function seated_colors()
  local seated = {}
  if seated_game_players then
    for _, p in ipairs(seated_game_players()) do seated[p.color] = true end
  end
  return seated
end

function M.is_bot(player)
  return type(player) == "table" and player.is_arno == true
end

function M.humans(list)
  local out = {}
  for _, p in ipairs(list or players or {}) do
    if not M.is_bot(p) then out[#out + 1] = p end
  end
  return out
end

function M.bots(list)
  local out = {}
  for _, p in ipairs(list or players or {}) do
    if M.is_bot(p) then out[#out + 1] = p end
  end
  return out
end

-- ---------------------------------------------------------------- setup panel (H1)

local function level_label(level)
  if level == nil or level == 0 then return "Off" end
  if level > 6 then return "Level " .. level .. " (L6 +" .. (level - 6) .. " CP)" end
  return "Level " .. level
end

function M.setup_rows_xml()
  local seated = seated_colors()
  local rows = {}
  local any = false
  for _, color in ipairs(M.COLORS) do
    if not seated[color] then
      any = true
      rows[#rows + 1] = string.format([[
        <HorizontalLayout spacing="10" minHeight="42" preferredHeight="42" childForceExpandWidth="false" childAlignment="MiddleLeft">
          <Text fontSize="18" color="#FFFFFF" alignment="MiddleLeft" preferredWidth="370" flexibleWidth="0">ARNO opponent (%s):</Text>
          <Button id="arnoSetup_%s" onClick="on_arno_setup_clicked(%s)" fontSize="16" minHeight="36" preferredWidth="170" flexibleWidth="0" color="#8A6D1F" textColor="#FFFFFF">%s</Button>
        </HorizontalLayout>
]], color, color, color, level_label(arno_setup.levels[color]))
    end
  end
  if any then
    rows[#rows + 1] = string.format([[
        <HorizontalLayout spacing="10" minHeight="42" preferredHeight="42" childForceExpandWidth="false" childAlignment="MiddleLeft">
          <Text fontSize="18" color="#FFFFFF" alignment="MiddleLeft" preferredWidth="370" flexibleWidth="0">ARNO project module (optional):</Text>
          <Button id="arnoSetupModule" onClick="on_arno_module_clicked" fontSize="16" minHeight="36" preferredWidth="170" flexibleWidth="0" color="#8A6D1F" textColor="#FFFFFF">%s</Button>
        </HorizontalLayout>
]], arno_setup.project_module and "Enabled" or "Disabled")
  end
  return table.concat(rows), #rows
end

-- inject ARNO rows into the mod's setup panel XML (wrapper of game_setup_panel_xml)
function M.extend_setup_panel(xml)
  local rows, n = M.setup_rows_xml()
  if n == 0 then return xml end
  local anchor = '<Button id="setupProceedButton"'
  local i = string.find(xml, anchor, 1, true)
  if i == nil then return xml end
  xml = string.sub(xml, 1, i - 1) .. rows .. "        " .. string.sub(xml, i)
  return (xml:gsub('id="gameSetupPanel" rectAlignment="MiddleCenter" width="600" height="(%d+)"',
    function(h) return 'id="gameSetupPanel" rectAlignment="MiddleCenter" width="600" height="' .. (tonumber(h) + 48 * n) .. '"' end, 1))
end

function M.on_setup_clicked(color)
  local level = (arno_setup.levels[color] or 0) + 1
  if level > M.MAX_LEVEL then level = 0 end
  arno_setup.levels[color] = level
  if set_ui_attributes then set_ui_attributes("arnoSetup_" .. color, { text = level_label(level) }) end
end

function M.on_module_clicked()
  arno_setup.project_module = not arno_setup.project_module
  if set_ui_attributes then
    set_ui_attributes("arnoSetupModule", { text = arno_setup.project_module and "Enabled" or "Disabled" })
  end
end

-- ---------------------------------------------------------------- players (H2, H3)

-- H2: called inside setup_game right after `players` is built from the seated humans.
function M.add_bots(list)
  local seated = {}
  for _, p in ipairs(list) do seated[p.color] = true end
  local colors = {}
  for _, color in ipairs(M.COLORS) do
    if (arno_setup.levels[color] or 0) > 0 and not seated[color] then colors[#colors + 1] = color end
  end
  if #colors == 0 then
    arno_state = nil
    return
  end
  state.init(os.time() + math.random(0, 2147483646), { project_module = arno_setup.project_module })
  for i, color in ipairs(colors) do
    local level = arno_setup.levels[color]
    local name = #colors == 1 and "ARNO" or ("ARNO " .. i)
    table.insert(list, { color = color, steam_name = name, is_arno = true, arno_index = i })
    local bot = decide.new_bot(math.min(level, 6))
    bot.name = name
    bot.color = color
    bot.extra_cp = math.max(0, level - 6)
    bot.cp_debt = 0              -- set in prepare_bot once Marine Worlds is known
    bot.sponsor_discards = 0
    bot.mat_projects = {}
    bot.mat_animals = {}
    arno_state.bots[color] = bot
    arno_state.order[#arno_state.order + 1] = color
  end
  state.log(string.format("%d ARNO opponent(s), seed %s", #colors, arno_state.seed))
end

-- H3: a human is always the starting player (rules p3).
function M.starting_player(list)
  if not state.active() then return nil end
  local humans = M.humans(list)
  if #humans == 0 then return nil end
  return humans[math.random(#humans)]
end

-- ---------------------------------------------------------------- humans-only window

M.window_open = false
M.full_players = nil

function M.open_window()
  if M.window_open or not state.active() then return end
  M.full_players = players
  players = M.humans(players)
  M.window_open = true
end

function M.close_window()
  if not M.window_open then return end
  players = M.full_players
  M.full_players = nil
  M.window_open = false
end

-- ARNO's own setup, before the humans' map/draft prompts (rules p3, p9).
function M.prepare_bot(player)
  local bot = state.bot(player.color)
  local data = cnsts.map_data.map_A
  apply_map_choice(player, "map_A", data.image)
  local zones = marine_worlds_enabled and cnsts.action_card_init_zones.mw or cnsts.action_card_init_zones.base
  deal_action_cards(player, zones[player.color])
  require("adapter.cards").replace(player, bot.level)   -- the real ARNO cards (owner request)
  -- ARNO doesn't draft (rules p9); the mod only removes a player's drafting box when that
  -- player finishes the draft, so remove his here (it covered his action cards, found in play)
  if marine_worlds_enabled then
    local box = getObjectFromGUID(cnsts.drafting_boxes[player.color])
    if box ~= nil then box.destruct() end
  end
  local debt = marine_worlds_enabled and rulings.START_CP_DEBT_MW or rulings.START_CP_DEBT
  debt = debt - (bot.extra_cp or 0)
  bot.cp_debt = math.max(0, debt)
  if debt < 0 then require("adapter.apply").gain_cp(player, -debt, "difficulty level") end
end

-- H8: humans discard 4 each; ARNO discards what he does not keep (counted in deal_bot_cards).
function M.expected_discards(list)
  if not state.active() then return nil end
  local n = 4 * #M.humans(list)
  for _, p in ipairs(M.bots(list)) do
    n = n + (state.bot(p.color).setup_discards or 0)
  end
  return n
end

return M
