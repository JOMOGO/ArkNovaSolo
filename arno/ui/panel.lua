-- ARNO 3.0 for "Ark Nova - Complete Scripted" (Tabletop Simulator).
-- ARNO solo mode designed by Andre K. See NOTICE.
--
-- The ARNO panel, visible to every seat: per bot the five action-card slots (upgrades
-- marked), difficulty, CP debt, tokens, module status, the
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

-- Shows the table order: the card ARNO used last sits in slot 1 (no highlight: his last
-- turn is listed below; owner choice). Upgraded cards are pink.
local function slot_row(bot)
  local cells = {}
  local cs = bot.card_slots
  local order = cs and require("adapter.apply").physical_order(bot) or {}
  for i = 1, 5 do
    local name = order[i]
    local label = name and CARD_LABEL[name] or "?"
    local upgraded = name and contains(cs.upgraded, name)
    if upgraded then label = label .. " II" end
    cells[#cells + 1] = string.format(
      '<Text fontSize="13" color="%s" preferredWidth="62">%d %s</Text>',
      upgraded and "#FF9BE0" or "#FFFFFF", i, esc(label))
  end
  return '<HorizontalLayout spacing="2" minHeight="20">' .. table.concat(cells) .. '</HorizontalLayout>'
end

-- Text element sized for its wrapped line count, so the panel height always fits.
-- Width 420 minus padding leaves ~404 px; average glyph widths are estimated generously.
M.WIDTH = 420
local CHARS_PER_LINE = { [12] = 54, [15] = 44, [16] = 42 }

local function text(content, size, color, bold)
  local per_line = CHARS_PER_LINE[size] or 50
  local lines = math.max(1, math.ceil(#content / per_line))
  local h = lines * (size + 5)
  return string.format(
    '<Text fontSize="%d"%s color="%s" alignment="UpperLeft" minHeight="%d" preferredHeight="%d">%s</Text>',
    size, bold and ' fontStyle="Bold"' or "", color, h, h, esc(content)), h
end

-- one ARNO: header, slots, status and what he did in his last turn, all in his colour
local function bot_block(color, bot)
  local hex = state.COLOR_HEX[color] or "#FFFFFF"
  local parts, height, count = {}, 0, 0
  local function add(xml, h) parts[#parts + 1] = xml; height = height + h; count = count + 1 end
  add(text(string.format("%s  -  Level %d%s  -  CP debt %d", bot.name or ("ARNO " .. color), bot.level,
    (bot.extra_cp or 0) > 0 and (" (+" .. bot.extra_cp .. ")") or "", bot.cp_debt or 0), 15, hex, true))
  add(slot_row(bot), 20)
  local extra = string.format("Scoring-card tokens %d, notepad %d, end CP now %d",
    bot.tokens_scoring or 0, bot.tokens_notepad or 0, require("core.decide").final_cp(bot))
  if arno_state.project_module then
    local pos = tracker.position(bot.sponsor_discards or 0)
    extra = extra .. string.format("  |  module: %s, kiosks %d", tracker.slot(pos), tracker.kiosk_count(pos))
  end
  add(text(extra, 12, "#CCCCCC"))
  for _, line in ipairs(bot.last_turn or {}) do add(text(line, 12, hex)) end
  return table.concat(parts), height, count
end

M.SPACING = 2
M.PADDING_TOP, M.PADDING_BOTTOM = 8, 8
M.CONTROLS_HEIGHT = 30
M.MARGIN = 16

function M.xml(running_color)
  local st = state.get()
  if st == nil or not state.active() then return nil end
  if M.collapsed then
    return [[<Panel id="arnoPanel" rectAlignment="UpperLeft" offsetXY="70 -10" width="120" height="34" color="#1B2B3AEE">
      <Button onClick="on_arno_panel_toggle" fontSize="14" color="#2E5D7A" textColor="#FFFFFF">ARNO</Button></Panel>]]
  end
  local title, title_h = text("A.R.N.O. 3.0  (seed " .. tostring(st.seed or "?") .. ")", 16, "#EBD717")
  local blocks, height, count = {}, title_h, 1
  for _, color in ipairs(st.order) do
    local xml, h, n = bot_block(color, st.bots[color])
    blocks[#blocks + 1] = xml
    height, count = height + h, count + n
  end
  local controls = string.format([[
        <HorizontalLayout spacing="6" minHeight="%d" preferredHeight="%d">
          <Button onClick="on_arno_run_clicked" interactable="%s" fontSize="13" color="#3A7D44" textColor="#FFFFFF">Run ARNO turn</Button>
          <Button onClick="on_arno_auto_clicked" fontSize="13" color="#2E5D7A" textColor="#FFFFFF">Auto: %s</Button>
          <Button onClick="on_arno_panel_toggle" fontSize="13" color="#555555" textColor="#FFFFFF">Hide</Button>
        </HorizontalLayout>]], M.CONTROLS_HEIGHT, M.CONTROLS_HEIGHT,
    running_color and "true" or "false", st.auto and "on" or "off")
  count = count + 1
  height = height + M.CONTROLS_HEIGHT + M.SPACING * count + M.PADDING_TOP + M.PADDING_BOTTOM + M.MARGIN
  return string.format([[
    <Panel id="arnoPanel" rectAlignment="UpperLeft" offsetXY="70 -10" width="%d" height="%d" color="#1B2B3AEE">
      <VerticalLayout spacing="%d" padding="8 8 %d %d" childForceExpandHeight="false">
%s
%s
%s
      </VerticalLayout>
    </Panel>]], M.WIDTH, height, M.SPACING, M.PADDING_TOP, M.PADDING_BOTTOM + M.MARGIN, title, table.concat(blocks), controls)
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
