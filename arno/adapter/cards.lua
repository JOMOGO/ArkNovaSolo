-- ARNO 3.0 for "Ark Nova - Complete Scripted" (Tabletop Simulator).
-- ARNO solo mode designed by Andre K. See NOTICE.
--
-- Owner request: ARNO's action cards on the table are the real ARNO 3.0 cards (images
-- cut from the cards PDF by tools/arno_cards.py; the build sets ARNO_CARD_IMAGES).
-- The mod's dealt cards are swapped, slot by slot, for a spawned card with the same name
-- and tags, face = side I, back = side II, exactly like the mod's own action cards, so
-- slot moves, flips on upgrade and tokens work unchanged. Animals, Build and Cards come
-- in a green (levels 1-3) and a red (levels 4+) version. Without images nothing changes.

local M = {}

-- CustomDeck ids above every id in the base save (max 2537)
M.DECK_BASE = 7700
M.IMAGES = { "animals_g", "animals_r", "association", "build_g", "build_r",
             "cards_g", "cards_r", "sponsors" }

local VARIANTS = { ANIMALS = true, BUILD = true, CARDS = true }

-- image key for an action ("ANIMALS", ...) at a difficulty level
function M.image(action, level)
  local key = string.lower(action)
  if VARIANTS[action] then key = key .. ((level or 1) >= 4 and "_r" or "_g") end
  return key
end

local function deck_id(key)
  for i, k in ipairs(M.IMAGES) do if k == key then return M.DECK_BASE + i end end
end

function M.replace(player, level)
  local images = ARNO_CARD_IMAGES
  if images == nil or player.action_cards == nil then return end
  for slot, record in ipairs(player.action_cards) do
    local old = getObjectFromGUID(record.guid)
    local key = old and M.image(string.upper(string.sub(old.getName(), 1, -3)), level)
    local img = key and images[key]
    if img ~= nil then
      local id = deck_id(key)
      local pos = action_card_slot_position(player.player_board.getPosition(), slot)
      local card = spawnObjectData({
        data = {
          Name = "CardCustom", Nickname = old.getName(), Tags = old.getTags(),
          Transform = { posX = pos.x, posY = pos.y, posZ = pos.z, rotX = 0, rotY = 180, rotZ = 0,
                        scaleX = 1.5, scaleY = 1, scaleZ = 1.5 },
          ColorDiffuse = { r = 0.713235259, g = 0.713235259, b = 0.713235259 },
          Locked = true, Hands = true, CardID = id * 100, SidewaysCard = false,
          CustomDeck = { [tostring(id)] = { FaceURL = img.face, BackURL = img.back, NumWidth = 1,
            NumHeight = 1, BackIsHidden = true, UniqueBack = false, Type = 0 } },
        },
        position = pos, rotation = { 0, 180, 0 },
      })
      old.destruct()
      record.guid = card.getGUID()
    end
  end
end

return M
