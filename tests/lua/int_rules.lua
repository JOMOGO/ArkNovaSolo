-- Integration tests on the BUILT Global.lua for base-mod code that refactor/general shares
-- between places: the hex board's region search and tile placement, the "all players discard
-- 1 final scoring card" flow (10 CP and game end) and reconstruction's building moves (the
-- real move and the check on a scratch board).
local T = require("tests.lib")

local ANY = { upgd = true, rock = true, water = true, cover = 0 }

local function set_of(list)
  local s = {}
  for _, v in ipairs(list) do s[v] = true end
  return s
end

-- ---------------------------------------------------------------- hex board

local function region_facts(board)
  local sizes = board:unoccupiedRegionSizes()
  local total, regions, largest = board:countGroupsOfSix()
  local groups, biggest = 0, 0
  for _, size in ipairs(sizes) do
    groups = groups + (size - size % 6) / 6
    if size > biggest then biggest = size end
  end
  return { total = total, regions = regions, largest = largest,
           sizes = #sizes, groups = groups, biggest = biggest }
end

T.test("board: countGroupsOfSix agrees with unoccupiedRegionSizes, map A as dealt", function()
  local p = sim.human_game()
  local f = region_facts(p.map)
  T.eq(f.regions, f.sizes, "one region per size")
  T.eq(f.largest, f.biggest)
  T.eq(f.total, f.groups, "groups of six per region, summed")
  T.ok(f.total > 0)
end)

T.test("board: countGroupsOfSix agrees with unoccupiedRegionSizes after building", function()
  local p = sim.human_game()
  local before = region_facts(p.map)
  for _, kind in ipairs({ "SIZE 5", "SIZE 4", "PETTING ZOO", "SIZE 2" }) do
    local cells = p.map:findValidPlacement(sim.cnsts.build_tile_shapes[kind], { allowed = ANY })
    T.ok(cells ~= nil, "room for " .. kind)
    T.ok(p.map:place(cells, { kind:lower() }, ANY) ~= nil, kind .. " placed")
  end
  local f = region_facts(p.map)
  T.eq(f.regions, f.sizes)
  T.eq(f.largest, f.biggest)
  T.eq(f.total, f.groups)
  T.ok(f.biggest < before.biggest, "the buildings took room")
end)

T.test("board: place and placeUnchecked leave the same board and reward", function()
  local a, b = sim.human_game().map, sim.human_game().map
  local cells = a:findValidPlacement(sim.cnsts.build_tile_shapes["SIZE 3"], { allowed = ANY })
  local id_a, reward_a = a:place(cells, { "size_3" }, ANY, {})
  local id_b, reward_b = b:placeUnchecked(cells, { "size_3" }, ANY, {})
  T.eq(id_a, id_b)
  T.eq(reward_a, reward_b)
  T.eq(a.unoccupiedCount, b.unoccupiedCount)
  T.eq(reward_a.clearedBoard, false)
  T.eq(a:place(cells, { "size_3" }, ANY, {}), nil, "place refuses taken cells")
end)

T.test("board: the placement that fills the last free cell reports a cleared board", function()
  local board = sim.human_game().map
  local last, placed = nil, 0
  while board.unoccupiedCount > 0 and placed < 200 do
    local cells = board:findValidPlacement(sim.cnsts.build_tile_shapes["SIZE 1"],
                                           { allowed = ANY, ignore_touch_rule = true })
    if cells == nil then break end
    local _, reward = board:placeUnchecked(cells, { "size_1" }, ANY, {})
    if board.unoccupiedCount > 0 then T.eq(reward.clearedBoard, false, "not yet cleared") end
    last, placed = reward, placed + 1
  end
  T.eq(board.unoccupiedCount, 0, "every free cell built over")
  T.eq(last.clearedBoard, true)
end)

-- ---------------------------------------------------------------- final scoring discard

-- Red and Blue, each with two final scoring cards in hand 2
local function two_humans()
  local red = sim.human_game()
  local blue = sim.make_player("Blue", false)
  players = { red, blue }
  player_status = {}
  local cards = {}
  for _, color in ipairs({ "Red", "Red", "Blue", "Blue" }) do
    local card = sim.fake("final scoring card " .. color)
    card.addTag("final_scoring")
    card.deal(1, color, 2)
    cards[color] = cards[color] or card
  end
  return red, blue, cards
end

local function discard(color, card)
  onObjectPickUp(color, card)
  on_card_selection_confirm_clicked(nil, color, nil)
end

T.test("final scoring discard at 10 CP: both discard, then the claims go on", function()
  local red, _, cards = two_humans()
  start_final_scoring_discard(red)
  T.ok(selection_panels.Red ~= nil and selection_panels.Blue ~= nil, "both asked")
  discard("Red", cards.Red)
  T.eq(player_status.Red, sim.cnsts.waiting_to_discard, "Red waits for Blue")
  T.eq(#sim.calls.end_player_turn, 0)
  discard("Blue", cards.Blue)
  T.eq(player_status.Red, nil, "waiting cleared")
  T.eq(#sim.calls.end_player_turn, 1, "Red's claims went on (none left: turn ends)")
end)

T.test("final scoring discard at game end: both discard, cards leave the hands, then scoring", function()
  local _, _, cards = two_humans()
  final_scoring_discard_triggered = false
  sim.record("score_all_players")
  start_final_scoring()
  discard("Red", cards.Red)
  T.eq(player_status.Red, sim.cnsts.waiting_to_discard)
  discard("Blue", cards.Blue)
  sim.pump()
  T.eq(#sim.calls.score_all_players, 0, "waits until the discarded cards left the hands")
  sim.leave_hand(cards.Red); sim.leave_hand(cards.Blue)      -- what TTS does with them
  sim.pump()
  T.eq(#sim.calls.score_all_players, 1)
  T.eq(final_scoring_discard_triggered, true)
end)

T.test("final scoring at game end after the 10 CP discard: scoring at once", function()
  two_humans()
  final_scoring_discard_triggered = true
  sim.record("score_all_players")
  start_final_scoring()
  T.eq(#sim.calls.score_all_players, 1)
  T.eq(selection_panels.Red, nil, "no second discard")
end)

-- ---------------------------------------------------------------- reconstruction

-- the starting size-3 enclosure of map A, selected for reconstruction and put on `cells`
local function reconstruct_size_3(p, find_opts)
  local id
  for tile_id, tile in pairs(p.map.tiles) do
    if tile.tags.type == "size_3" then id = tile_id end
  end
  local old_cells = p.map.tiles[id].cells
  reconstruction(p, "test")
  local state = reconstruction_actions.Red
  select_reconstruction_tile(p, state, id)
  on_reconstruction_select_confirm_clicked(nil, "Red", nil)
  local cells = p.map:findValidPlacement(sim.cnsts.build_tile_shapes["SIZE 3"], find_opts)
  local obj = p.building_tiles[id]
  local transform = tile_object_transform_for_cells(obj, p.player_board.getPosition(), cells)
  obj.setPosition(transform.position)
  obj.setRotation(transform.rotation)
  refresh_reconstruction_validity(p)
  return id, obj, old_cells, cells, state
end

local function tile_at(p, cells)
  local want = set_of(cells)
  for id, tile in pairs(p.map.tiles) do
    local same = #tile.cells == #cells
    for _, c in ipairs(tile.cells) do same = same and want[c] end
    if same then return id, tile end
  end
  return nil, nil
end

T.test("reconstruction: a building moves to free buildable cells", function()
  local p = sim.human_game()
  local kiosk = tile_at(p, (function()
    for _, t in pairs(p.map.tiles) do if t.tags.type == "kiosk" then return t.cells end end
  end)())
  local old_id, obj, old_cells, cells, state = reconstruct_size_3(p, reposition_opts(p, nil))
  T.ok(state.valid, "the scratch-board check accepts the move")
  on_reconstruction_confirm_clicked(nil, "Red", nil)
  local new_id, tile = tile_at(p, cells)
  T.ok(new_id ~= nil, "the enclosure stands on the new cells")
  T.eq(tile.tags.type, "size_3")
  T.eq(p.building_tiles[new_id], obj, "its tile object moved with it")
  T.eq(tile_at(p, old_cells), nil, "the old cells are free")
  T.ok(p.map.tiles[kiosk] ~= nil, "the kiosk stayed")
  T.eq(reconstruction_actions.Red, nil, "reconstruction closed")
  T.eq(#sim.calls.end_player_turn, 1, "the claims went on")
end)

T.test("reconstruction: a move onto rock or water is refused and changes nothing", function()
  local p = sim.human_game()
  local terrain = p.map.terrain
  local id, _, old_cells, cells, state = reconstruct_size_3(p, { allowed = ANY, extra_check = function(cs)
    for _, c in ipairs(cs) do
      if terrain[c] == "rock" or terrain[c] == "water" then return true end
    end
    return false
  end })
  T.ok(cells ~= nil, "found a spot on rock or water")
  T.eq(state.valid, false, "the scratch-board check refuses it")
  on_reconstruction_confirm_clicked(nil, "Red", nil)
  T.eq(tile_at(p, old_cells), id, "the enclosure is where it was")
  T.eq(tile_at(p, cells), nil)
  T.ok(reconstruction_actions.Red ~= nil, "still choosing")
  T.eq(#sim.calls.end_player_turn, 0)
end)

-- ---------------------------------------------------------------- card flip (FIXFLIP)

local function upgrade_all_but(p, keep)
  for slot = 1, 5 do
    getObjectFromGUID(p.action_cards[slot].guid).is_face_down = (slot ~= keep)
  end
end

T.test("FIXFLIP: a card flip with every action card upgraded is skipped, the turn goes on", function()
  local p = sim.human_game()
  upgrade_all_but(p, nil)
  create_claims_from_rewards(p, { "card flip", "2 appeal" }, "test")
  sim.pump()
  local flip                                              -- the player picks the card flip first
  for i, claim in ipairs(p.claims[#p.claims]) do
    if not tostring(resolve_claim_text(claim)):find("Appeal") then flip = i end
  end
  on_claim_button_clicked(nil, "Red_" .. flip, nil)
  sim.pump()
  T.eq(card_flips.Red, nil, "no upgrade panel")
  T.eq(get_counter_value(p.appeal_counter), 2, "the next reward was still paid")
  T.eq(#sim.calls.end_player_turn, 1, "the claims went on to the end of the turn")
end)

T.test("FIXFLIP: with one card left to upgrade, the panel still opens and upgrades it", function()
  local p = sim.human_game()
  upgrade_all_but(p, 3)
  create_claims_from_rewards(p, { "card flip" }, "test")
  sim.pump()
  T.ok(card_flips.Red ~= nil, "upgrade panel open")
  T.eq(#sim.calls.end_player_turn, 0, "waiting for the choice")
  on_card_flip_clicked(nil, "Red_3", nil)
  T.eq(action_card_upgraded(action_card_object(p, 3)), true, "slot 3 upgraded")
  T.eq(#sim.calls.end_player_turn, 1)
end)

T.finish("integration rules")
