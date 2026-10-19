-- Tests for adapter UI helpers that only transform XML strings.
local T = require("tests.lib")

-- minimal stand-ins for mod globals used by these helpers
seated_game_players = function() return { { color = "Red" } } end
set_ui_attributes = function() end

local setup = require("adapter.setup")
local hint = require("ui.hint")

local SETUP_XML = [[
    <Panel id="gameSetupPanel" rectAlignment="MiddleCenter" width="600" height="400" color="#222222FF">
      <VerticalLayout>
        <Button id="setupProceedButton" onClick="on_setup_proceed_clicked">Proceed</Button>
      </VerticalLayout>
    </Panel>]]

T.test("setup panel gets one ARNO row per unseated colour plus the module row", function()
  arno_setup = { levels = {}, project_module = false }
  local xml = setup.extend_setup_panel(SETUP_XML)
  local rows = 0
  for _ in xml:gmatch('onClick="on_arno_setup_clicked%(') do rows = rows + 1 end
  T.eq(rows, 3, "White, Blue, Yellow (Red is seated)")
  T.ok(xml:find('on_arno_module_clicked', 1, true) ~= nil)
  T.ok(xml:find('height="592"', 1, true) ~= nil, "panel grew by 4 rows x 48")
  T.ok(xml:find('arnoSetup_Yellow', 1, true) < xml:find('setupProceedButton', 1, true), "rows before Proceed")
end)

T.test("ARNO setup toggle cycles Off -> L1..L10 -> Off", function()
  arno_setup = { levels = {}, project_module = false }
  for _ = 1, 10 do setup.on_setup_clicked("Yellow") end
  T.eq(arno_setup.levels.Yellow, 10)
  setup.on_setup_clicked("Yellow")
  T.eq(arno_setup.levels.Yellow, 0)
end)

T.test("add_bots appends ARNO entries for chosen unseated colours only", function()
  arno_setup = { levels = { Yellow = 4, Red = 2, Blue = 8 }, project_module = true }
  printToAll = function() end
  local list = { { color = "Red", steam_name = "human" } }
  setup.add_bots(list)
  T.eq(#list, 3)
  T.eq(list[2].color, "Blue"); T.eq(list[2].is_arno, true); T.eq(list[2].steam_name, "ARNO 1")
  T.eq(list[3].color, "Yellow"); T.eq(list[3].steam_name, "ARNO 2")
  T.eq(arno_state.bots.Blue.level, 6); T.eq(arno_state.bots.Blue.extra_cp, 2)
  T.eq(arno_state.bots.Yellow.level, 4)
  T.eq(arno_state.project_module, true)
  T.eq(arno_state.order, { "Blue", "Yellow" })
end)

T.test("starting player is always a human", function()
  local list = { { color = "Blue", is_arno = true }, { color = "Red" }, { color = "Yellow", is_arno = true } }
  for _ = 1, 50 do T.eq(setup.starting_player(list).color, "Red") end
end)

T.test("humans-only window swaps and restores players", function()
  players = { { color = "Red" }, { color = "Yellow", is_arno = true }, { color = "White" } }
  local full = players
  setup.open_window()
  T.eq(#players, 2); T.eq(players[2].color, "White")
  setup.close_window()
  T.ok(players == full)
end)

T.test("undo hint grows the action panel and adds one line", function()
  local xml = [[<Panel id="actionSelectionPanel_Red" visibility="Red" rectAlignment="MiddleRight" offsetXY="-60 0" width="260" height="300" color="#222222DD">
      <VerticalLayout><Button/></VerticalLayout></Panel>]]
  local out = hint.add_undo_hint(xml)
  T.ok(out:find('height="322"', 1, true) ~= nil)
  T.ok(out:find(hint.TEXT, 1, true) ~= nil)
  T.ok(out:find(hint.TEXT, 1, true) < out:find("</VerticalLayout>", 1, true))
  T.eq(hint.add_undo_hint("<Panel id=\"other\"/>"), "<Panel id=\"other\"/>")
end)

T.finish("adapter ui")
