-- ARNO 3.0 for "Ark Nova - Complete Scripted" (Tabletop Simulator).
-- Port of brdgm/ark-nova-solo-helper (c) Stefan Seifert, Apache License 2.0.
-- ARNO solo mode designed by Andre K. See NOTICE.
--
-- Entry point: the global `ARNO` table used by the hook edits in hooks/hooks.json and by
-- the button handlers below. ARNO.install() is called once when the bundle loads.

local ARNO = {}

ARNO.VERSION = "1.0.0"
ARNO.state = require("adapter.state")
ARNO.setup = require("adapter.setup")
ARNO.turn = require("adapter.turn")

function ARNO.is_bot(player)
  return ARNO.setup.is_bot(player)
end

function ARNO.install()
  require("adapter.hooks").install(ARNO)
end

-- ---------------------------------------------------------------- UI handlers
-- (named on_* so the mod's interaction wrapper also wraps them)

function on_arno_setup_clicked(_, color, _)
  ARNO.setup.on_setup_clicked(color)
end

function on_arno_module_clicked()
  ARNO.setup.on_module_clicked()
end

function on_arno_run_clicked()
  if current_player ~= nil and ARNO.is_bot(current_player) then
    ARNO.turn.pending = current_player.color
    ARNO.turn.run(current_player)
  end
end

function on_arno_auto_clicked()
  if arno_state == nil then return end
  arno_state.auto = not arno_state.auto
  ARNO.state.chat("automatic ARNO turns " .. (arno_state.auto and "on" or "off"))
  require("ui.panel").render(ARNO.turn.pending)
end

function on_arno_panel_toggle()
  local panel = require("ui.panel")
  panel.collapsed = not panel.collapsed
  panel.render(ARNO.turn.pending)
end

return ARNO
