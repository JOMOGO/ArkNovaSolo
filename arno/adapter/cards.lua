-- ARNO 3.0 for "Ark Nova - Complete Scripted" (Tabletop Simulator).
-- ARNO solo mode designed by Andre K. See NOTICE.
--
-- Owner request: ARNO's action cards on the table are the real ARNO 3.0 cards (two sheets
-- cut from the cards PDF by tools/arno_cards.py: side I faces, and side II at the same
-- positions; the build sets ARNO_CARD_IMAGES = { face, back, width, height, order }).
-- The mod's dealt cards are swapped, slot by slot, for a spawned card with the same name
-- and tags, face = side I, back = side II, exactly like the mod's own action cards, so
-- slot moves, flips on upgrade and tokens work unchanged. Animals, Build and Cards come
-- in a green (levels 1-3) and a red (levels 4+) version. Without images nothing changes.

local M = {}

-- CustomDeck id above every id in the base save (max 2537)
M.DECK_ID = 7701

local VARIANTS = { ANIMALS = true, BUILD = true, CARDS = true }

-- image key for an action ("ANIMALS", ...) at a difficulty level
function M.image(action, level)
  local key = string.lower(action)
  if VARIANTS[action] then key = key .. ((level or 1) >= 4 and "_r" or "_g") end
  return key
end

local function sheet_index(images, key)
  for i, k in ipairs(images.order or {}) do if k == key then return i - 1 end end
end

function M.replace(player, level)
  local images = ARNO_CARD_IMAGES
  if images == nil or player.action_cards == nil then return end
  for slot, record in ipairs(player.action_cards) do
    local old = getObjectFromGUID(record.guid)
    local key = old and M.image(string.upper(string.sub(old.getName(), 1, -3)), level)
    local index = key and sheet_index(images, key)
    if index ~= nil then
      local id = M.DECK_ID
      local pos = action_card_slot_position(player.player_board.getPosition(), slot)
      local card = spawnObjectData({
        data = {
          Name = "Card", Nickname = old.getName(), Tags = old.getTags(),
          Transform = { posX = pos.x, posY = pos.y, posZ = pos.z, rotX = 0, rotY = 180, rotZ = 0,
                        scaleX = 1.5, scaleY = 1, scaleZ = 1.5 },
          ColorDiffuse = { r = 0.713235259, g = 0.713235259, b = 0.713235259 },
          Locked = true, Hands = true, CardID = id * 100 + index, SidewaysCard = false,
          CustomDeck = { [tostring(id)] = { FaceURL = images.face, BackURL = images.back,
            NumWidth = images.width, NumHeight = images.height, BackIsHidden = true,
            UniqueBack = true, Type = 0 } },
        },
        position = pos, rotation = { 0, 180, 0 },
      })
      old.destruct()
      record.guid = card.getGUID()
    end
  end
end

return M
