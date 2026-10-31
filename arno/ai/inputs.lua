-- AI opponent (docs/AI_OPPONENT.md §0, §3): the only four ways the AI acts on the game,
-- the same four a human has. Nothing here changes game state by itself; each input calls
-- the mod's own entry point for it:
--   click        a panel button          -> the button's onClick handler
--   pick_up      a card (hand, display)  -> onObjectPickUp, as TTS calls it
--   pick_up_tile a building tile         -> on_building_tile_picked_up (the tile's script)
--   drop_tile    move a tile, let it go  -> on_building_tile_settled (the tile's script)

local M = {}

-- frames between moving a tile and reporting it settled (TTS: once it rests)
M.SETTLE_FRAMES = 2

function M.click(handler, arg)
  local fn = _G[handler]
  if type(fn) ~= "function" then error("AI: no handler " .. tostring(handler)) end
  fn(nil, arg, nil)
end

function M.pick_up(color, obj)
  onObjectPickUp(color, obj)
end

function M.pick_up_tile(color, tile)
  on_building_tile_picked_up({ tile = tile, color = color })
end

-- done() runs once the mod has seen the tile settle
function M.drop_tile(color, tile, transform, done)
  tile.setPosition(transform.position)
  tile.setRotation(transform.rotation)
  Wait.frames(function()
    on_building_tile_settled({ tile = tile, color = color })
    if done then done() end
  end, M.SETTLE_FRAMES)
end

return M
