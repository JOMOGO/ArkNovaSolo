-- ARNO 3.0 for "Ark Nova - Complete Scripted" (Tabletop Simulator).
--
-- Owner request (H19): the base mod has no "back" button once an action is chosen; the way
-- back is TTS rewind (twice: the mod stores a spacer state after the first click). This adds
-- a one-line hint to the human action-selection panel and grows the panel to fit.
-- No game logic changes.

local M = {}

M.TEXT = "Undo later choices: press the rewind arrow twice."
M.EXTRA_HEIGHT = 22

function M.add_undo_hint(xml)
  local grown, n = xml:gsub('(<Panel id="actionSelectionPanel_[^"]*"[^>]-height=")(%d+)(")',
    function(head, h, tail) return head .. (tonumber(h) + M.EXTRA_HEIGHT) .. tail end, 1)
  if n == 0 then return xml end
  local pos, start = nil, 1
  while true do
    local i = string.find(grown, "</VerticalLayout>", start, true)
    if i == nil then break end
    pos, start = i, i + 1
  end
  if pos == nil then return xml end
  local hint = '<Text fontSize="12" color="#BBBBBB" minHeight="16">' .. M.TEXT .. '</Text>'
  return string.sub(grown, 1, pos - 1) .. hint .. string.sub(grown, pos)
end

-- Owner request: the base mod places only this panel 60 px in from the right edge
-- (offsetXY="-60 0"); every other panel sits flush right. Move it flush right too.
function M.flush_right(xml)
  return (xml:gsub('(<Panel id="actionSelectionPanel_[^"]*"[^>]-offsetXY=")%-60 0(")', "%10 0%2", 1))
end

return M
