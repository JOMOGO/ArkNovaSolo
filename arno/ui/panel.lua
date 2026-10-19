-- ARNO 3.0 for "Ark Nova - Complete Scripted" (Tabletop Simulator).
-- ARNO solo mode designed by Andre K. See NOTICE.
--
-- The ARNO panel, visible to every seat: per bot the five action-card slots (active
-- one highlighted, upgrades marked), difficulty, CP debt, tokens, module status, the
-- last log lines and the Run / Pause / Auto controls. Rendered through the mod's own
-- panel system (set_active_panel) so mod re-renders keep it.

local state = require("adapter.state")
local tracker = require("core.project_tracker")

local M = {}

M.KEY = "arno"
M.collapsed = false   -- per session; not persisted

local CARD_LABEL = { animals = "Animals", association = "Assoc.", sponsors = "Sponsors",
                     build = "Build", cards = "Cards" }

local function esc(s)
  return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local function contains(list, v)
  for _, x in ipairs(list or {}) do if x == v then return true end end
  return false
end

local function slot_row(bot)
  local cells = {}
  local cs = bot.card_slots
  for i = 1, 5 do
    local name = cs and cs.slots[i]
    local label = name and CARD_LABEL[name] or "?"
    local upgraded = name and contains(cs.upgraded, name)
    if upgraded then label = label .. " II" end
    local active = cs ~= nil and bot.last_slot == i
    cells[#cells + 1] = string.format(
      '<Text fontSize="13" color="%s" preferredWidth="62">%d %s</Text>',
      active and "#00E5FF" or (upgraded and "#FF9BE0" or "#FFFFFF"), i, esc(label))
  end
  return '<HorizontalLayout spacing="2" minHeight="20">' .. table.concat(cells) .. '</HorizontalLayout>'
end

local function bot_block(color, bot)
  local lines = {}
  lines[#lines + 1] = string.format(
    '<Text fontSize="15" color="%s" alignment="MiddleLeft" minHeight="20">%s  -  Level %d%s  -  CP debt %d</Text>',
    color == "White" and "#FFFFFF" or color, esc(bot.name or ("ARNO " .. color)), bot.level,
    (bot.extra_cp or 0) > 0 and (" (+" .. bot.extra_cp .. ")") or "", bot.cp_debt or 0)
  lines[#lines + 1] = slot_row(bot)
  local extra = string.format("Scoring-card tokens %d, notepad %d, end CP now %d",
    bot.tokens_scoring or 0, bot.tokens_notepad or 0, require("core.decide").final_cp(bot))
  if arno_state.project_module then
    local pos = tracker.position(bot.sponsor_discards or 0)
    extra = extra .. string.format("  |  module: %s, kiosks %d", tracker.slot(pos), tracker.kiosk_count(pos))
  end
  lines[#lines + 1] = '<Text fontSize="12" color="#CCCCCC" alignment="MiddleLeft" minHeight="16">' .. esc(extra) .. '</Text>'
  return table.concat(lines)
end

function M.xml(running_color)
  local st = state.get()
  if st == nil or not state.active() then return nil end
  if M.collapsed then
    return [[<Panel id="arnoPanel" rectAlignment="UpperRight" offsetXY="-10 -60" width="120" height="34" color="#1B2B3AEE">
      <Button onClick="on_arno_panel_toggle" fontSize="14" color="#2E5D7A" textColor="#FFFFFF">ARNO ▸</Button></Panel>]]
  end
  local blocks = {}
  for _, color in ipairs(st.order) do
    blocks[#blocks + 1] = bot_block(color, st.bots[color])
  end
  local log = {}
  local first = math.max(1, #st.log - 7)
  for i = first, #st.log do
    log[#log + 1] = '<Text fontSize="12" color="#E8E8E8" alignment="MiddleLeft" minHeight="15">' .. esc(st.log[i]) .. '</Text>'
  end
  local controls = string.format([[
        <HorizontalLayout spacing="6" minHeight="28">
          <Button onClick="on_arno_run_clicked" interactable="%s" fontSize="13" color="#3A7D44" textColor="#FFFFFF">Run ARNO turn</Button>
          <Button onClick="on_arno_auto_clicked" fontSize="13" color="#2E5D7A" textColor="#FFFFFF">Auto: %s</Button>
          <Button onClick="on_arno_panel_toggle" fontSize="13" color="#555555" textColor="#FFFFFF">Hide</Button>
        </HorizontalLayout>]], running_color and "true" or "false", st.auto and "on" or "off")
  local height = 70 + #st.order * 64 + #log * 16
  return string.format([[
    <Panel id="arnoPanel" rectAlignment="UpperRight" offsetXY="-10 -60" width="400" height="%d" color="#1B2B3AEE">
      <VerticalLayout spacing="2" padding="8 8 6 6" childForceExpandHeight="false">
        <Text fontSize="16" color="#EBD717" alignment="MiddleLeft" minHeight="20">A.R.N.O. 3.0  (seed %s)</Text>
%s
%s
%s
        <Text fontSize="10" color="#999999" alignment="MiddleLeft" minHeight="12">ARNO by Andre K. - logic ported from Ark Nova Solo Helper (Stefan Seifert, Apache-2.0)</Text>
      </VerticalLayout>
    </Panel>]], height, esc(st.seed or "?"), table.concat(blocks), table.concat(log), controls)
end

function M.render(running_color)
  if not set_active_panel then return end
  local xml = M.xml(running_color)
  if xml == nil then
    if clear_active_panel then clear_active_panel(M.KEY) end
  else
    set_active_panel(M.KEY, xml)
  end
end

return M
