function getByType(zone, tag)
  if zone then
    for _, obj in pairs(zone.getObjects(true)) do
      if obj.tag == tag then return obj end
    end
  end
  return nil
end

function getCard(zone) return getByType(zone, "Card") end

function getDeck(zone)
  local deck = getByType(zone, "Deck")
  if deck == nil then
    deck = getCard(zone)
  end
  return deck
end

function deal_tagged_card(deck, guid, color, index, tag)
  local card = deck.takeObject({ guid = guid, smooth = false })
  card.addTag(tag)
  card.deal(1, color, index)
  return card
end

function deal_tagged_cards(deck, count, color, index, tag)
  for _ = 1, count do
    deal_tagged_card(deck, nil, color, index, tag)
  end
end

function tile_in_zone(zone, tag)
  for _, obj in pairs(zone.getObjects(true)) do
    if obj.hasTag(tag) then return obj end
  end
  return nil
end

function tile_missing(zone, tag)
  return tile_in_zone(zone, tag) == nil
end

function null_func() end

function single(arg)
  local t = {}
  for i = 1, 20 do
    t[i] = i .. " " .. arg
  end
  return t
end

function double(arg)
  local t = {}
  for i = 1, 20 do
    t[i] = (2 * i) .. " " .. arg
  end
  return t
end

function triple(arg)
  local t = {}
  for i = 1, 5 do
    t[i] = (3 * i) .. " " .. arg
  end
  return t
end

function set_counter_display(obj, value, font_color, position, font_size)
  local pos = position or { 0, 0 }
  obj.clearButtons()
  obj.createButton({
    label = tostring(value),
    click_function = "null_func",
    function_owner = nil,
    position = { pos[1], 0.05, pos[2] },
    width = 0,
    height = 0,
    scale = { 2, 2, 2 },
    font_size = font_size or 500,
    font_color = font_color or { 1, 1, 1, 1 }
  })
end

function set_counter(obj, value, style)
  set_counter_display(obj, value, style.color, style.position, style.font_size)
end

function get_counter_value(obj)
  return tonumber(obj.getButtons()[1].label)
end

function set_icon_counter(counter, value, style)
  set_counter(counter, value == 0 and "" or value, style)
end

function get_icon_counter_value(counter)
  return tonumber(counter.getButtons()[1].label) or 0
end

local HexBoard = (function()
local HexBoard = (function()

  local M = {}


  local N_COLS, V_MAX = 9, 12
  local DIRS = { {0,-2}, {0,2}, {-1,-1}, {-1,1}, {1,-1}, {1,1} }
  local GROUP_SIZE = 6

  local CELLS, COORD_ID = {}, {}
  for col = 0, N_COLS - 1 do
    for v = 0, V_MAX do
      if (col + v) % 2 == 1 then
        CELLS[#CELLS + 1] = { col = col, v = v }
        COORD_ID[col .. "," .. v] = #CELLS
      end
    end
  end

  local N_CELLS = #CELLS
  local MAX_TILE_SIZE = 5

  local NEIGHBORS = {}
  for id = 1, N_CELLS do
    local c, t = CELLS[id], {}
    for k = 1, 6 do
      local n = COORD_ID[(c.col + DIRS[k][1]) .. "," .. (c.v + DIRS[k][2])]
      if n then t[#t + 1] = n end
    end
    NEIGHBORS[id] = t
  end

  local IS_BORDER, N_BORDER, BORDER_LIST = {}, 0, {}
  for id = 1, N_CELLS do
    local b = #NEIGHBORS[id] < 6
    IS_BORDER[id] = b
    if b then N_BORDER = N_BORDER + 1; BORDER_LIST[N_BORDER] = id end
  end

  local ADJ = {}
  for id = 1, N_CELLS do
    local nb = NEIGHBORS[id]
    for k = 1, #nb do ADJ[id * 64 + nb[k]] = true end
  end

  local EMPTY = 0
  local TERRAIN_TAGS = { rock = true, water = true, upgd = true }
  local SPECIAL_SIZE_BONUS = { ["outdoor areas"] = 2 }
  local EXPANSION_AREA_TYPE, EXPANSION_AREA_BONUS = "size_3", 2
  local SLOT_COUNTS = {
    large_aquarium    = 5,
    small_aquarium    = 2,
    petting_zoo       = 3,
    reptile_house     = 5,
    large_bird_aviary = 5,
    underwater_tunnel = 2,
  }
  local UNCOUNTABLE = { rock = true, water = true }
  local COVERABLE = { rock = true, water = true }
  local KEEPS_COVERED_TERRAIN = { underwater_tunnel = true }

  local COLUMN_CELLS = {}
  for col = 0, N_COLS - 1 do
    local list = {}
    for v = 0, V_MAX do
      local id = COORD_ID[col .. "," .. v]
      if id then list[#list + 1] = id end
    end
    COLUMN_CELLS[col + 1] = list
  end

  local DIRS_CUBE_STEP = {
    { 0, -1, 1 }, { 0, 1, -1 }, { -1, 0, 1 }, { -1, 1, 0 }, { 1, -1, 0 }, { 1, 0, -1 }
  }
  local CUBE_Q, CUBE_R, CUBE_S = {}, {}, {}
  CUBE_Q[1], CUBE_R[1], CUBE_S[1] = 0, 0, 0
  local frontier, fi = { 1 }, 1
  local cubeVisited = { [1] = true }
  while fi <= #frontier do
    local id = frontier[fi]; fi = fi + 1
    local c = CELLS[id]
    for k = 1, 6 do
      local nid = COORD_ID[(c.col + DIRS[k][1]) .. "," .. (c.v + DIRS[k][2])]
      if nid and not cubeVisited[nid] then
        cubeVisited[nid] = true
        local step = DIRS_CUBE_STEP[k]
        CUBE_Q[nid] = CUBE_Q[id] + step[1]
        CUBE_R[nid] = CUBE_R[id] + step[2]
        CUBE_S[nid] = CUBE_S[id] + step[3]
        frontier[#frontier + 1] = nid
      end
    end
  end

  local CUBE_TO_CELL = {}
  for id = 1, N_CELLS do
    CUBE_TO_CELL[CUBE_Q[id] .. "," .. CUBE_R[id]] = id
  end

  local function cubeOf(cell)
    return CUBE_Q[cell], CUBE_R[cell], CUBE_S[cell]
  end

  M.N_CELLS, M.N_BORDER, M.MAX_TILE_SIZE, M.GROUP_SIZE = N_CELLS, N_BORDER, MAX_TILE_SIZE, GROUP_SIZE
  M.CELLS, M.NEIGHBORS, M.IS_BORDER, M.BORDER_LIST = CELLS, NEIGHBORS, IS_BORDER, BORDER_LIST
  M.EMPTY, M.TERRAIN_TAGS = EMPTY, TERRAIN_TAGS
  M.COLUMN_CELLS = COLUMN_CELLS

  function M.cellAt(col, v) return COORD_ID[col .. "," .. v] end
  function M.coordOf(id) local c = CELLS[id]; return c.col, c.v end

  local SCRATCH = { false, false, false, false, false }

  function M.isContiguous(cells)
    local n = #cells
    if n <= 1 then return n == 1 end
    for i = 1, n do SCRATCH[i] = false end
    SCRATCH[1] = true
    local total, changed = 1, true
    while changed and total < n do
      changed = false
      for i = 2, n do
        if not SCRATCH[i] then
          local ci = cells[i] * 64
          for j = 1, n do
            if SCRATCH[j] and ADJ[ci + cells[j]] then
              SCRATCH[i] = true; total = total + 1; changed = true; break
            end
          end
        end
      end
    end
    return total == n
  end

  local MARK, markGen = {}, 0
  for i = 1, N_CELLS do MARK[i] = 0 end
  local STACK = {}


  local Board = {}
  Board.__index = Board
  M.Board = Board

  function Board.new(layout)
    local self = setmetatable({}, Board)
    self.owner     = {}
    self.terrain   = {}
    self.blocked   = {}
    self.countable = {}
    self.adjTile   = {}
    self.special      = {}
    self.specialCells = {}
    for i = 1, N_CELLS do
      self.owner[i], self.blocked[i] = EMPTY, false
      self.adjTile[i] = 0
      self.countable[i] = true
    end

    self.terrainCells = { rock = {}, water = {}, upgd = {} }
    self.blockedCount = { rock = 0, water = 0, upgd = 0 }

    self.cellTags = {}
    self.cellTagsInitial = {}

    local startTiles = {}

    layout = layout or {}
    for col = 0, N_COLS - 1 do
      local ids = COLUMN_CELLS[col + 1]
      local column = layout[col + 1]
      if column then
        for i = 1, #ids do
          local c = ids[i]
          local entry = column[i]
          if entry then
            local tag = entry.terrain
            if TERRAIN_TAGS[tag] then
              self.terrain[c] = tag
              self.blocked[c] = true
              self.countable[c] = not UNCOUNTABLE[tag]
              local list = self.terrainCells[tag]; list[#list + 1] = c
              self.blockedCount[tag] = self.blockedCount[tag] + 1
            end

            if entry.special ~= nil then
              self.special[c] = entry.special
              local slist = self.specialCells[entry.special]
              if not slist then slist = {}; self.specialCells[entry.special] = slist end
              slist[#slist + 1] = c
            end

            if entry.reward ~= nil then
              self.cellTags[c] = { { tag = entry.reward } }
              self.cellTagsInitial[c] = { { tag = entry.reward } }
            end

            if entry.startTile ~= nil then
              local key = entry.startTile
              local group = startTiles[key]
              if not group then group = { cells = {} }; startTiles[key] = group end
              group.cells[#group.cells + 1] = c
              if entry.startTileTag ~= nil then group.tag = entry.startTileTag end
            end
          end
        end
      end
    end

    self.tiles      = {}
    self.tileCount, self.placedCount, self.nextId = 0, 0, 1

    self.unoccupiedCount = 0
    for i = 1, N_CELLS do
      if self.countable[i] then self.unoccupiedCount = self.unoccupiedCount + 1 end
    end

    for _, group in pairs(startTiles) do
      self:_insert(group.cells, group.tag and { group.tag } or nil)
    end

    return self
  end


  function Board:isOnBoard(cells)
    local owner = self.owner
    for i = 1, #cells do
      if owner[cells[i]] == nil then return false end
    end
    return true
  end

  function Board:_cellsUnusable(cells, allowed)
    local owner, blocked, terrain = self.owner, self.blocked, self.terrain
    local budget = (allowed and allowed.cover) or 0
    for i = 1, #cells do
      local c = cells[i]
      local o = owner[c]
      if o == nil    then return "off board" end
      if o ~= EMPTY  then return "overlap" end
      if blocked[c] and not (allowed and allowed[terrain[c]]) then
        if budget > 0 and COVERABLE[terrain[c]] then
          budget = budget - 1
        else
          return "blocked"
        end
      end
    end
    return nil
  end

  function Board:coverBudgetUsed(cells, allowed)
    local blocked, terrain = self.blocked, self.terrain
    local n = 0
    for i = 1, #cells do
      local c = cells[i]
      if blocked[c] and COVERABLE[terrain[c]]
         and not (allowed and allowed[terrain[c]]) then
        n = n + 1
      end
    end
    return n
  end

  function Board:isOverlapping(cells)
    local owner, blocked = self.owner, self.blocked
    for i = 1, #cells do
      local c = cells[i]
      if owner[c] ~= EMPTY or blocked[c] then return true end
    end
    return false
  end

  function Board:countBorderCells(cells)
    local n = 0
    for i = 1, #cells do
      if IS_BORDER[cells[i]] then n = n + 1 end
    end
    return n
  end

  function Board:touchesExistingTile(cells)
    local adj = self.adjTile
    for i = 1, #cells do
      if adj[cells[i]] > 0 then return true end
    end
    return false
  end

  function Board:needsBorderStart() return self.placedCount == 0 end

  function Board:canPlace(cells, allowed, opts)
    local n = #cells
    if n < 1 or n > MAX_TILE_SIZE then return false, "size" end
    local bad = self:_cellsUnusable(cells, allowed)
    if bad                       then return false, bad end
    if not M.isContiguous(cells) then return false, "not contiguous" end
    if not (opts and opts.ignore_touch_rule) then
      if self:needsBorderStart() then
        if self:countBorderCells(cells) == 0 then return false, "needs border" end
      else
        if not self:touchesExistingTile(cells) then return false, "must touch a tile" end
      end
    end
    return true
  end

  function Board:findValidPlacement(shape, opts)
    opts = opts or {}
    local terrain_requirements = opts.terrain_requirements or {}
    local min_border = opts.min_border_cells or 0

    local offsets = {}
    for i, cell in ipairs(shape) do
      offsets[i] = { cubeOf(cell) }
    end
    local base = offsets[1]
    for i = 1, #offsets do
      offsets[i] = { offsets[i][1] - base[1], offsets[i][2] - base[2], offsets[i][3] - base[3] }
    end

    for _ = 1, 6 do
      for anchor = 1, N_CELLS do
        local q0, r0 = cubeOf(anchor)
        local cells, ok = {}, true
        for i = 1, #offsets do
          local cell = CUBE_TO_CELL[(q0 + offsets[i][1]) .. "," .. (r0 + offsets[i][2])]
          if cell == nil then ok = false; break end
          cells[i] = cell
        end

        if ok and not self:_cellsUnusable(cells, opts.allowed) and M.isContiguous(cells) then
          local placement_ok = opts.ignore_touch_rule
          if not placement_ok then
            if self:needsBorderStart() then
              placement_ok = self:countBorderCells(cells) > 0
            else
              placement_ok = self:touchesExistingTile(cells)
            end
          end

          if placement_ok and self:countBorderCells(cells) >= min_border
             and (not opts.water_cells_only or self:cellsAllTerrain(cells, "water")) then
            local terrain_ok = true
            for _, req in ipairs(terrain_requirements) do
              if self:countTerrainFor(cells, req.tag) < req.min then
                terrain_ok = false
                break
              end
            end

            if terrain_ok and (not opts.extra_check or opts.extra_check(cells)) then
              return cells
            end
          end
        end
      end

      for i = 1, #offsets do
        local q, r, s = offsets[i][1], offsets[i][2], offsets[i][3]
        offsets[i] = { -r, -s, -q }
      end
    end

    return nil
  end

  function Board:hasValidPlacement(shape, opts)
    return self:findValidPlacement(shape, opts) ~= nil
  end


  function Board:_insert(cells, tags)
    local id = self.nextId
    self.nextId = id + 1

    local own = {}
    for i = 1, #cells do own[i] = cells[i] end

    local tile = { id = id, cells = own, tags = {}, adj = {}, adjN = 0 }
    self.tiles[id] = tile

    local covered = nil
    for i = 1, #own do
      local c = own[i]
      if self.blocked[c] and COVERABLE[self.terrain[c]] then
        covered = covered or {}
        covered[#covered + 1] = c
        self:_setBlocked(c, false)
      end
    end
    tile.covered = covered
    self.tileCount = self.tileCount + 1
    self.placedCount = self.placedCount + 1

    for i = 1, #own do
      local c = own[i]
      if self.countable[c] then self.unoccupiedCount = self.unoccupiedCount - 1 end
      self.owner[c] = id
    end

    local adjTile, owner = self.adjTile, self.owner
    for i = 1, #own do
      local nb = NEIGHBORS[own[i]]
      for k = 1, #nb do
        local n = nb[k]
        adjTile[n] = adjTile[n] + 1
        local o = owner[n]
        if o > 0 and o ~= id and not tile.adj[o] then
          local other = self.tiles[o]
          tile.adj[o]   = true; tile.adjN  = tile.adjN + 1
          other.adj[id] = true; other.adjN = other.adjN + 1
        end
      end
    end

    if tags and tags[1] then
      tile.tags.type = tags[1]
      if SLOT_COUNTS[tags[1]] then
        tile.tags.slots = SLOT_COUNTS[tags[1]]
      end
      if tags[1]:match("^size_%d$") then
        tile.tags.occupied = false
      end
      for i = 2, #tags do self:addTag(id, tags[i]) end
    end

    return id
  end

  function Board:_rewardFrom(cells, multiplier)
    multiplier = multiplier or 1
    local r = { tags = {}, count = 0,
                borderTags = {}, borderCount = 0,
                cells = {}, clearedBoard = false, specials = {} }
    local ct, special = self.cellTags, self.special
    for i = 1, #cells do
      local c = cells[i]
      local tag = special[c]
      if tag then r.specials[#r.specials + 1] = { cell = c, tag = tag } end
    end
    for i = 1, #cells do
      local c = cells[i]
      local list = ct[c]
      if list then
        local onBorder = IS_BORDER[c] == true
        for k = 1, #list do
          local rec = list[k]
          for _ = 1, multiplier do
            r.count = r.count + 1
            r.tags[r.count] = rec.tag
            r.cells[r.count] = { cell = c, tag = rec.tag, border = onBorder }
            if onBorder then
              r.borderCount = r.borderCount + 1
              r.borderTags[r.borderCount] = rec.tag
            end
          end
        end
      end
    end
    return r
  end

  function Board:_rewardMultiplier(opts)
    return (opts and opts.double_placement_bonus) and 2 or 1
  end

  function Board:_consume(id, cells)
    local tile, collected = self.tiles[id], nil
    for i = 1, #cells do
      local c = cells[i]
      local list = self.cellTags[c]
      if list then
        collected = collected or {}
        collected[c] = list
        self.cellTags[c] = nil
      end
    end
    tile.collected = collected
  end

  function Board:previewReward(cells, opts)
    local r = self:_rewardFrom(cells, self:_rewardMultiplier(opts))
    local drop, countable = 0, self.countable
    for i = 1, #cells do
      if countable[cells[i]] then drop = drop + 1 end
    end
    r.clearedBoard = (self.unoccupiedCount > 0 and self.unoccupiedCount - drop == 0)
    return r
  end

  function Board:place(cells, tags, allowed, opts)
    local ok, why = self:canPlace(cells, allowed, opts)
    if not ok then return nil, why end
    local before = self.unoccupiedCount
    local reward = self:_rewardFrom(cells, self:_rewardMultiplier(opts))
    local id = self:_insert(cells, tags)
    self:_consume(id, cells)
    reward.clearedBoard = (before > 0 and self.unoccupiedCount == 0)
    return id, reward
  end

  function Board:placeUnchecked(cells, tags, allowed, opts)
    if #cells < 1 or #cells > MAX_TILE_SIZE then return nil, "size" end
    local bad = self:_cellsUnusable(cells, allowed)
    if bad then return nil, bad end
    if not M.isContiguous(cells) then return nil, "not contiguous" end
    local before = self.unoccupiedCount
    local reward = self:_rewardFrom(cells, self:_rewardMultiplier(opts))
    local id = self:_insert(cells, tags)
    self:_consume(id, cells)
    reward.clearedBoard = (before > 0 and self.unoccupiedCount == 0)
    return id, reward
  end

  function Board:remove(id)
    local tile = self.tiles[id]
    if not tile then return false end
    local cells = tile.cells

    if tile.collected then
      for c, list in pairs(tile.collected) do self.cellTags[c] = list end
      tile.collected = nil
    end
    local restored = self:_rewardFrom(cells)

    local adjTile, owner = self.adjTile, self.owner

    for i = 1, #cells do
      local nb = NEIGHBORS[cells[i]]
      for k = 1, #nb do adjTile[nb[k]] = adjTile[nb[k]] - 1 end
    end

    for i = 1, #cells do
      local c = cells[i]
      owner[c] = EMPTY
      if self.countable[c] then self.unoccupiedCount = self.unoccupiedCount + 1 end
    end

    if tile.covered then
      for i = 1, #tile.covered do self:_setBlocked(tile.covered[i], true) end
    end

    for o in pairs(tile.adj) do
      local other = self.tiles[o]
      if other and other.adj[id] then
        other.adj[id] = nil; other.adjN = other.adjN - 1
      end
    end
    self.tiles[id] = nil
    self.tileCount = self.tileCount - 1
    self.placedCount = self.placedCount - 1
    return true, restored
  end


  function Board:_setBlocked(c, flag)
    if self.blocked[c] == flag then return false end
    local tag = self.terrain[c]
    if tag == nil then return false end
    self.blocked[c] = flag
    self.blockedCount[tag] = (self.blockedCount[tag] or 0) + (flag and 1 or -1)
    return true
  end

  function Board:unblock(tag)
    if not TERRAIN_TAGS[tag] then return 0 end
    local list, freed = self.terrainCells[tag], 0
    for i = 1, #list do
      if self:_setBlocked(list[i], false) then freed = freed + 1 end
    end
    return freed
  end

  function Board:isBlocked(cell)   return self.blocked[cell] == true end
  function Board:terrainOf(cell)   return self.terrain[cell] end

  function Board:cellsAllTerrain(cells, tag)
    for i = 1, #cells do
      if self.terrain[cells[i]] ~= tag then return false end
    end
    return true
  end
  function Board:countBlocked(tag) return self.blockedCount[tag] or 0 end

  function Board:specialAt(cell) return self.special[cell] end

  function Board:cellsWithSpecial(tag)
    local out, s = {}, self.specialCells[tag]
    if s then for i = 1, #s do out[i] = s[i] end end
    return out
  end

  function Board:activeSpecialCells(tag)
    local out, s, owner = {}, self.specialCells[tag], self.owner
    if s then
      for i = 1, #s do
        if owner[s[i]] == EMPTY then out[#out + 1] = s[i] end
      end
    end
    return out
  end

  function Board:tileCoversSpecial(id, tag)
    local tile = self.tiles[id]
    if tile == nil then return false end
    local special, cells = self.special, tile.cells
    for i = 1, #cells do
      if special[cells[i]] == tag then return true end
    end
    return false
  end

  function Board:tileTouchesSpecial(id, tag)
    local tile = self.tiles[id]
    if tile == nil then return false end
    local special, owner, cells = self.special, self.owner, tile.cells
    for i = 1, #cells do
      local nb = NEIGHBORS[cells[i]]
      for k = 1, #nb do
        if special[nb[k]] == tag and owner[nb[k]] == EMPTY then return true end
      end
    end
    return false
  end

  function Board:enclosureCapacity(id, opts)
    local tile = self.tiles[id]
    if tile == nil then return nil end
    local printed = tile.tags.type and tile.tags.type:match("^size_(%d)$")
    if printed == nil then return nil end

    local size = tonumber(printed)
    for tag, bonus in pairs(SPECIAL_SIZE_BONUS) do
      if self:tileTouchesSpecial(id, tag) then size = size + bonus end
    end

    if opts and opts.expansion_area
       and tile.tags.type == EXPANSION_AREA_TYPE
       and self:countBorderCells(tile.cells) > 0 then
      size = size + EXPANSION_AREA_BONUS
    end

    return size
  end

  function Board:terrainStillCounts(c)
    if self.blocked[c] then return true end
    local o = self.owner[c]
    if o == nil or o == EMPTY then return false end
    local tile = self.tiles[o]
    return tile ~= nil and KEEPS_COVERED_TERRAIN[tile.tags.type] == true
  end

  function Board:countTerrainAdjacent(cells, tag)
    markGen = markGen + 1
    local g, n = markGen, 0
    local terrain = self.terrain
    for i = 1, #cells do
      local nb = NEIGHBORS[cells[i]]
      for k = 1, #nb do
        local c = nb[k]
        if MARK[c] ~= g then
          MARK[c] = g
          if terrain[c] == tag and self:terrainStillCounts(c) then n = n + 1 end
        end
      end
    end
    return n
  end

  function Board:countTerrainCovered(cells, tag)
    local blocked, terrain = self.blocked, self.terrain
    local n = 0
    for i = 1, #cells do
      local c = cells[i]
      if blocked[c] and terrain[c] == tag then n = n + 1 end
    end
    return n
  end

  function Board:countUncoveredTerrainAdjacentToTile(tag)
    local list = self.terrainCells[tag]
    if list == nil then return 0 end
    local owner, adjTile, n = self.owner, self.adjTile, 0
    for i = 1, #list do
      local c = list[i]
      if adjTile[c] > 0 and (owner[c] == EMPTY or self:terrainStillCounts(c)) then
        n = n + 1
      end
    end
    return n
  end

  function Board:countUncoveredTerrain(tag)
    local list = self.terrainCells[tag]
    if list == nil then return 0 end
    local owner, n = self.owner, 0
    for i = 1, #list do
      local c = list[i]
      if owner[c] == EMPTY or self:terrainStillCounts(c) then n = n + 1 end
    end
    return n
  end

  function Board:countPlacementCellsBesideTerrain(cells, tag)
    local owner, terrain = self.owner, self.terrain
    local own = {}
    for i = 1, #cells do own[cells[i]] = true end

    local n = 0
    for i = 1, #cells do
      local nb = NEIGHBORS[cells[i]]
      for k = 1, #nb do
        local c = nb[k]
        if terrain[c] == tag and (owner[c] == EMPTY or own[c]) then
          n = n + 1
          break
        end
      end
    end
    return n
  end

  function Board:countOccupiedAdjacentTo(tag)
    local total, tiles = 0, self.tiles
    local ids = self:tilesWithTag(tag)
    for i = 1, #ids do
      for o in pairs(tiles[ids[i]].adj) do
        if tiles[o].tags.occupied ~= false then total = total + 1 end
      end
    end
    return total
  end

  function Board:kioskIncome()
    return self:countOccupiedAdjacentTo("kiosk")
  end

  function Board:sideEntranceIncome()
    return 2 * self:countOccupiedAdjacentTo("side_entrance")
  end

  function Board:countCoveredAdjacentToSpecial(tag)
    local cells, owner, n = self:activeSpecialCells(tag), self.owner, 0
    for i = 1, #cells do
      local nb = NEIGHBORS[cells[i]]
      for k = 1, #nb do
        if owner[nb[k]] ~= EMPTY then n = n + 1 end
      end
    end
    return n
  end

  function Board:countTerrainFor(cells, tag)
    return self:countTerrainAdjacent(cells, tag) + self:countTerrainCovered(cells, tag)
  end

  function Board:countTouchingBlocked(id, tag)
    local tile = self.tiles[id]
    if not tile then return 0 end
    return self:countTerrainAdjacent(tile.cells, tag)
  end

  function Board:touchingBlockedCells(id, tag)
    local tile = self.tiles[id]
    if not tile then return {} end
    markGen = markGen + 1
    local g, out = markGen, {}
    local cells, terrain = tile.cells, self.terrain
    for i = 1, #cells do
      local nb = NEIGHBORS[cells[i]]
      for k = 1, #nb do
        local c = nb[k]
        if MARK[c] ~= g then
          MARK[c] = g
          if terrain[c] == tag and self:terrainStillCounts(c) then
            out[#out + 1] = c
          end
        end
      end
    end
    table.sort(out)
    return out
  end


  function Board:countUnoccupied() return self.unoccupiedCount end

  function Board:isCleared() return self.unoccupiedCount == 0 end

  function Board:countUnoccupiedBorderAdjacentToTile()
    local owner, countable, adjTile = self.owner, self.countable, self.adjTile
    local n = 0
    for k = 1, N_BORDER do
      local c = BORDER_LIST[k]
      if countable[c] and owner[c] == EMPTY and adjTile[c] > 0 then
        n = n + 1
      end
    end
    return n
  end

  function Board:countUnoccupiedBorder()
    local owner, countable = self.owner, self.countable
    local n = 0
    for k = 1, N_BORDER do
      local c = BORDER_LIST[k]
      if countable[c] and owner[c] == EMPTY then n = n + 1 end
    end
    return n
  end

  function Board:countUnoccupiedAdjacentToTile(id)
    local tile = self.tiles[id]
    if not tile then return 0 end

    markGen = markGen + 1
    local g, n = markGen, 0
    local owner, countable, cells = self.owner, self.countable, tile.cells
    for i = 1, #cells do
      local nb = NEIGHBORS[cells[i]]
      for k = 1, #nb do
        local c = nb[k]
        if MARK[c] ~= g then
          MARK[c] = g
          if countable[c] and owner[c] == EMPTY then n = n + 1 end
        end
      end
    end
    return n
  end

  function Board:unoccupiedCells()
    local out, owner, countable = {}, self.owner, self.countable
    for c = 1, N_CELLS do
      if countable[c] and owner[c] == EMPTY then out[#out + 1] = c end
    end
    return out
  end

  function Board:countGroupsOfSix()
    markGen = markGen + 1
    local g = markGen
    local owner, countable = self.owner, self.countable
    local total, regions, largest = 0, 0, 0
    for c = 1, N_CELLS do
      if countable[c] and owner[c] == EMPTY and MARK[c] ~= g then
        MARK[c] = g
        local top, size = 1, 0
        STACK[1] = c
        while top > 0 do
          local x = STACK[top]; top = top - 1
          size = size + 1
          local nb = NEIGHBORS[x]
          for k = 1, #nb do
            local u = nb[k]
            if countable[u] and owner[u] == EMPTY and MARK[u] ~= g then
              MARK[u] = g; top = top + 1; STACK[top] = u
            end
          end
        end
        regions = regions + 1
        if size > largest then largest = size end
        total = total + (size - size % GROUP_SIZE) / GROUP_SIZE
      end
    end
    return total, regions, largest
  end

  function Board:unoccupiedRegionSizes()
    markGen = markGen + 1
    local g = markGen
    local owner, countable, out = self.owner, self.countable, {}
    for c = 1, N_CELLS do
      if countable[c] and owner[c] == EMPTY and MARK[c] ~= g then
        MARK[c] = g
        local top, size = 1, 0
        STACK[1] = c
        while top > 0 do
          local x = STACK[top]; top = top - 1
          size = size + 1
          local nb = NEIGHBORS[x]
          for k = 1, #nb do
            local u = nb[k]
            if countable[u] and owner[u] == EMPTY and MARK[u] ~= g then
              MARK[u] = g; top = top + 1; STACK[top] = u
            end
          end
        end
        out[#out + 1] = size
      end
    end
    table.sort(out, function(a, b) return a > b end)
    return out
  end


  function Board:cellTagsAt(cell) return self.cellTags[cell] end

  function Board:cellTagsCovered(cells)
    local out, ct = {}, self.cellTags
    for i = 1, #cells do
      local t = ct[cells[i]]
      if t then
        for k = 1, #t do out[#out + 1] = t[k].tag end
      end
    end
    return out
  end

  function Board:unclaimedRewards()
    local out, ct, adjTile = {}, self.cellTags, self.adjTile
    for c = 1, N_CELLS do
      local list = ct[c]
      if list then
        local border   = IS_BORDER[c] == true
        local adjacent = adjTile[c] > 0
        local blocked  = self.blocked[c] == true
        for k = 1, #list do
          out[#out + 1] = { cell = c, tag = list[k].tag,
                            border = border, adjacent = adjacent, blocked = blocked }
        end
      end
    end
    return out
  end

  function Board:countUnclaimedRewards()
    local n, adj, ct, adjTile = 0, 0, self.cellTags, self.adjTile
    for c = 1, N_CELLS do
      local list = ct[c]
      if list then
        local touching = adjTile[c] > 0
        n = n + #list
        if touching then adj = adj + #list end
      end
    end
    return n, adj
  end

  function Board:clearCellTags(cells)
    for i = 1, #cells do self.cellTags[cells[i]] = nil end
  end

  function Board:initialCellTagsAt(cell) return self.cellTagsInitial[cell] end


  function Board:addTag(id, tag)
    local tile = self.tiles[id]; if not tile then return false end
    tile.tags[tag] = true
    return true
  end

  function Board:removeTag(id, tag)
    local tile = self.tiles[id]; if not tile then return false end
    tile.tags[tag] = nil
    return true
  end

  function Board:hasTag(id, tag)
    local tile = self.tiles[id]
    return tile ~= nil and (tile.tags.type == tag or tile.tags[tag] == true)
  end

  function Board:tilesWithTag(tag)
    local out = {}
    for id, tile in pairs(self.tiles) do
      if tile.tags.type == tag or tile.tags[tag] == true then
        out[#out + 1] = id
      end
    end
    table.sort(out)
    return out
  end

  function Board:removeTilesWithTag(tag)
    local doomed = self:tilesWithTag(tag)
    local all = { tags = {}, count = 0, borderTags = {}, borderCount = 0,
                  cells = {}, clearedBoard = false }
    for i = 1, #doomed do
      local _, r = self:remove(doomed[i])
      if r then
        for k = 1, r.count do
          all.count = all.count + 1
          all.tags[all.count] = r.tags[k]
          all.cells[all.count] = r.cells[k]
        end
        for k = 1, r.borderCount do
          all.borderCount = all.borderCount + 1
          all.borderTags[all.borderCount] = r.borderTags[k]
        end
      end
    end
    return doomed, all
  end


  function Board:cellsOf(id)
    local tile = self.tiles[id]
    return tile and tile.cells or nil
  end

  function Board:cellDistance(a, b)
    local q1, r1, s1 = cubeOf(a)
    local q2, r2, s2 = cubeOf(b)
    return (math.abs(q1 - q2) + math.abs(r1 - r2) + math.abs(s1 - s2)) / 2
  end

  function Board:touchingTiles(id)
    local tile = self.tiles[id]
    if not tile then return {} end
    local out = {}
    for o in pairs(tile.adj) do out[#out + 1] = o end
    table.sort(out)
    return out
  end

  function Board:countTouching(id)
    local tile = self.tiles[id]
    return tile and tile.adjN or 0
  end

  function Board:countTouchingWithTag(id, tag, want)
    if want == nil then want = true end
    local tile = self.tiles[id]
    if not tile then return 0 end
    local n, tiles = 0, self.tiles
    for o in pairs(tile.adj) do
      if (tiles[o].tags[tag] == true) == want then n = n + 1 end
    end
    return n
  end

  function Board:touchingTilesWithTag(id, tag, want)
    if want == nil then want = true end
    local tile = self.tiles[id]
    if not tile then return {} end
    local out, tiles = {}, self.tiles
    for o in pairs(tile.adj) do
      if (tiles[o].tags[tag] == true) == want then out[#out + 1] = o end
    end
    table.sort(out)
    return out
  end

  function Board:touches(a, b)
    local t = self.tiles[a]
    return t ~= nil and t.adj[b] == true
  end

  function Board:occupiedCount()
    local n = 0
    for i = 1, N_CELLS do
      if self.owner[i] ~= EMPTY or self.blocked[i] then n = n + 1 end
    end
    return n
  end

  local function shapeSignature(cells)
    local pts = {}
    for i = 1, #cells do
      local q, r, s = cubeOf(cells[i])
      pts[i] = { q, r, s }
    end

    local best = nil
    for _ = 1, 6 do
      local minQ, minR
      for i = 1, #pts do
        local q, r = pts[i][1], pts[i][2]
        if minQ == nil or q < minQ or (q == minQ and r < minR) then
          minQ, minR = q, r
        end
      end
      local normalized = {}
      for i = 1, #pts do
        normalized[i] = (pts[i][1] - minQ) .. "," .. (pts[i][2] - minR)
      end
      table.sort(normalized)
      local key = table.concat(normalized, ";")
      if best == nil or key < best then best = key end

      for i = 1, #pts do
        local q, r, s = pts[i][1], pts[i][2], pts[i][3]
        pts[i] = { -r, -s, -q }
      end
    end
    return best
  end

  function Board:countDistinctTileShapes()
    local seen, count = {}, 0
    for _, tile in pairs(self.tiles) do
      local sig = shapeSignature(tile.cells)
      if not seen[sig] then
        seen[sig] = true
        count = count + 1
      end
    end
    return count
  end

  return M
end)()

return HexBoard
end)()

local cnsts = (function()
local cnsts = {}

  cnsts.display_locs = {
    { -30.17, 1.08, 13.50 },
    { -23.81, 1.08, 13.50 },
    { -17.41, 1.08, 13.50 },
    { -11.00, 1.08, 13.50 },
    { -4.62, 1.08, 13.50 },
    { 1.77, 1.08, 13.50 }
  }

  cnsts.display_card_rotation = { 0, 180, 0 }

cnsts.generic_university = {
  home_pos = {45.65, 1.62, 9.59},
  board_pos = {33.56, 1.14, 16.04}
}

cnsts.universities = {
  hand_size       = { label = "Hand Size University",         rewards = { "1 rep" } },
  double_rep      = { label = "Double Reputation University", rewards = { "2 rep" },
                      icons = { "research" } },
  double_research = { label = "Double Research University",
                      icons = { "research", "research" } },

  herbivore = { label = "Herbivore University",  species = true },
  primate   = { label = "Primate University",    species = true },
  sea       = { label = "Sea Animal University", species = true },
  predator  = { label = "Predator University",   species = true },
  bird      = { label = "Bird University",       species = true },
  reptile   = { label = "Reptile University",    species = true },
}

for name, uni in pairs(cnsts.universities) do
  if uni.species then
    uni.icons = { "research", name }
    uni.rewards = { "search " .. name }
  end
end

cnsts.university_order = {
  "hand_size", "double_rep", "double_research",
  "herbivore", "primate", "sea", "predator", "bird", "reptile"
}

cnsts.species_university_zone = "ab280b"
cnsts.species_university_guids = {
  ["da6892"] = "herbivore",
  ["dfc3a0"] = "primate",
  ["e7c8a2"] = "sea",
  ["d090fe"] = "predator",
  ["eaffc5"] = "bird",
  ["439584"] = "reptile",
}

cnsts.association_tasks = {
  [2] = { label = "Take 2 Reputation" },
  [3] = { label = "Take a Partner Zoo" },
  [4] = { label = "Take a University" },
  [5] = { label = "Support a Conservation Project", veterinarian = 4 },
}

cnsts.association_extra_tasks = {
  ["2"] = { key = "hire",   label = "Hire a Worker",       strength = 5, zone = 5 },
  ["4"] = { key = "action", label = "Take Another Action", strength = 5 },
}

cnsts.association_extra_worker = {
  label = "Use Additional Worker\n(-2 task value)",
  discount = 2,
}

cnsts.association_3_source = "the Association 3 action"
cnsts.association_4_source = "the Association 4 action"

cnsts.income_equivalents = {
  ["draw t1 unlock"] = "draw 1",
}

cnsts.association_worker_step = Vector(0, 0, 0.33)
cnsts.association_worker_spread = Vector(0.33, 0, 0)
cnsts.association_worker_rotations = {
  [2] = { 0, 0, 0 }, [3] = { 0, 90, 0 }, [4] = { 0, 90, 0 }, [5] = { 0, 0, 0 },
}

cnsts.donation_zones = {
  "donation_2", "donation_5_1", "donation_5_2",
  "donation_7_1", "donation_7_2", "donation_10_1", "donation_10_2",
}
cnsts.donation_overflow_cost = 12

cnsts.project_slot_positions = {
  icons = "icon_proj", breeding = "breeding_proj",
  release = "release_proj", management = "management_proj",
}

cnsts.project_slot_labels = { "1st Slot", "2nd Slot", "3rd Slot" }

cnsts.project_slot_awards = {
  breeding = { { "2 cp", "2 rep" }, { "1 cp", "2 rep" }, { "2 cp" } },
  release  = { { "5 cp" }, { "4 cp" }, { "3 cp" } },
}

cnsts.project_cube_count = 7

cnsts.project_bonus_colors = {
  purple = { button = "#D898FA", text = "#FFFFFF", income = true },
  yellow = { button = "#FFFF00", text = "#000000", income = false },
}

cnsts.project_boosts = {
  { attr = "wildcard", label = "Use Wildcard Token", token = "TOKEN: wildcard" },
  { attr = "breeding_program", label = "Use Breeding Program" },
  { attr = "breeding_cooperation", label = "Use Breeding Cooperation" },
}

cnsts.toggle_colors = { on = "#3FA34D", off = "#888888" }

cnsts.panel_text_color = "#FFFFFF"

cnsts.source_labels = {
  ["their map project bonus"] = "Map Project Bonus",
}

cnsts.breeding_helper_attrs = { "breeding_program", "breeding_cooperation" }

cnsts.release_project_sizes = {
  { min = 4 }, { min = 3, max = 3 }, { max = 2 },
}

cnsts.okapi_stable_name = "Okapi Stable"

cnsts.landscape_gardener_name = "Landscape Gardener"

cnsts.sponsor_play_modes = {
  marketing = {
    prompt = "Select a Sponsor card to play with Marketing.",
  },
  person = {
    prompt = "Select a Person Sponsor card to play.",
    free = true,
    person_only = true,
  },
}

cnsts.pilfer_tracks = {
  { counter = "appeal_counter", label = "Appeal track" },
  { counter = "cp_counter",     label = "Conservation track" },
}

cnsts.target_minimums = {
  appeal_counter = 5,
  cp_counter     = 1,
}

cnsts.card_cube_effects = {
  ["breeding program"]     = { "breeding_cube_1", "breeding_cube_2" },
  ["breeding cooperation"] = { "breeding_cube_1", "breeding_cube_2" },
  ["okapi stable"]         = { "okapi_cube_1", "okapi_cube_2", "okapi_cube_3" },
}

cnsts.record_effects = {
  ["waza special"] = true,
}

cnsts.donation_12_offsets = {
  {  0,  0 }, { -1,  0 }, { -1, -1 }, {  0, -1 }, {  1, -1 },
  {  2, -1 }, { -1, -2 }, {  0, -2 }, {  1, -2 }, {  2, -2 },
}

  cnsts.appeal_tokens = {}
  cnsts.appeal_tokens.White = "15f2f4"
  cnsts.appeal_tokens.Red = "8156c7"
  cnsts.appeal_tokens.Blue = "c0f361"
  cnsts.appeal_tokens.Yellow = "64f3fb"

  cnsts.appeal_zones = { "2c313a",
    "eec1ec", "134eef", "63ee65", "880eb2", "6ab3e2", "b2c930", "63e519", "73fc27", "f2daff", "823334",
    "0b4ef7", "9545a9", "317b14", "ac3295", "6d7a9c", "5d5c68", "816083", "b336c6", "f4c58a", "38bb05",
    "d43f4d", "d33a35", "94483f", "a8612d", "ba8ff6", "1cbaef", "73d907", "4bb58b", "04204a", "3ba30a",
    "698fef", "1323be", "6b925b", "6b5eeb", "2a2581", "7159f1", "1734b0", "ffb00f", "653a75", "3ea9c0",
    "6ab3de", "ec10a8", "971f98", "2a493e", "5913a3", "d6642a", "02eaf8", "b7b538", "953bed", "d23d7b",
    "092482", "af429b", "f81147", "5b51a7", "c7070b", "bcfc8f", "4dd51e", "0ae379", "8c4ad2", "cedb14",
    "2a2716", "8d6d75", "c71500", "3ba8b9", "891101", "0d9258", "e17757", "097f2e", "aeb356", "6767b2",
    "b91c20", "3003fe", "33051f", "e8bad7", "5bdb58", "2496b3", "bf0adf", "a60401", "35dd6c", "9fd6e6",
    "5f16cb", "6c4328", "9f2a2e", "834d49", "3ff34e", "fa41f0", "03ffc2", "662490", "c6447a", "df406b",
    "aa921a", "3aaaab", "57ffe6", "5545cc", "e7fdd0", "9db942", "a782ba", "92f9a2", "a820bb", "14bc5e",
    "32ced0", "7b372e", "df69e0", "d4ee6e", "4f6694", "f03df8", "53b857", "383d19", "e3787d", "a69ceb",
    "55ab91", "0b7a57", "c9c643"
  }

  cnsts.conservation_point_tokens = {}
  cnsts.conservation_point_tokens.White = "23f41a"
  cnsts.conservation_point_tokens.Red = "6880dc"
  cnsts.conservation_point_tokens.Blue = "d21fc0"
  cnsts.conservation_point_tokens.Yellow = "c0d4aa"

  cnsts.cp_zones = { "b23239",
    "59d80b", "32c625", "1492df", "c05149", "b2ecab", "63b976", "4e4635", "4ac3b5", "bc9ba0", "63e420",
    "d6f363", "675d05", "c5bea4", "4ad166", "de7be6", "6f75f7", "3484a6", "1dad9d", "eaec55", "0de399", "a8ac70",
    "4da3c4", "b43ac2", "eb0d20",
    "9cd442", "c470ec", "06b781", "9a218f", "1b1657", "732afb", "a32a54", "b77686", "09ab12",
    "9bb7ec", "bb2cb8", "653c20", "e61627", "e7ef72", "c32338", "c840ac", "2598dc"
  }

  cnsts.cp_bonus_2 = { "card flip", "unlock worker" }

  cnsts.rep_zones = { "4eab3a", "2d5cab", "576563", "111002", "6557a2", "81e657", "ec46aa",
    "1414a0", "3b14e8", "7c3800", "b904fe", "4087b6", "adbde9", "6473e8", "e4e4c0" }
  cnsts.rep_rewards = {"", "", "", "", "card flip", "", "", "unlock worker", "", "draw 1", "1 cp", "1 x_token", "draw 1", "1 cp", "1 x_token"}

  cnsts.rep_range_thresholds = { 1, 2, 4, 7, 10, 13 }

  cnsts.reward_units = {
    appeal  = { one = "Appeal",             many = "Appeal" },
    money   = { one = "Money",              many = "Money" },
    rep     = { one = "Reputation",         many = "Reputation" },
    cp      = { one = "Conservation Point", many = "Conservation Points" },
    x_token = { one = "X-token",            many = "X-tokens" }
  }

  cnsts.reputation_tokens = {}
  cnsts.reputation_tokens.White = "8f2664"
  cnsts.reputation_tokens.Red = "e8ee40"
  cnsts.reputation_tokens.Blue = "f67354"
  cnsts.reputation_tokens.Yellow = "fc8a15"

  cnsts.bonus_tile_mapping = {}
  cnsts.bonus_tile_mapping["cc1325"] = "BONUS: get university"
  cnsts.bonus_tile_mapping["4fb150"] = "BONUS: 10 money"
  cnsts.bonus_tile_mapping["840cd1"] = "BONUS: 2 rep"
  cnsts.bonus_tile_mapping["03d9ca"] = "BONUS: draw 3"
  cnsts.bonus_tile_mapping["7dab5a"] = "BONUS: get partner zoo"
  cnsts.bonus_tile_mapping["7cd38f"] = "BONUS: 3 x_token"
  cnsts.bonus_tile_mapping["14dcd6"] = "BONUS: free size_3"
  cnsts.bonus_tile_mapping["d60a8e"] = "BONUS: marketing"
  cnsts.bonus_tile_mapping["1e8ab9"] = "BONUS: multiplier_token"
  cnsts.bonus_tile_mapping["b0e527"] = "TOKEN: extra shift"
  cnsts.bonus_tile_mapping["baace5"] = "TOKEN: snap hand size"
  cnsts.bonus_tile_mapping["1e423c"] = "TOKEN: wildcard"
  cnsts.bonus_tile_mapping["ad7da7"] = "BONUS: posturing 3"
  cnsts.bonus_tile_mapping["83f88a"] = "TOKEN: marketing"
  cnsts.bonus_tile_mapping["131044"] = "TOKEN: -3 conditions"
  cnsts.bonus_tile_mapping["eef749"] = "BONUS: adapt 3"

  cnsts.bonus_tokens = {
    ["marketing"]      = { persistent = "marketing_token" },
    ["extra shift"]    = { persistent = "extra_shift_token" },
    ["snap hand size"] = { label = "Snap / Hand Size +1", flag = "hand_size_plus_1" },
    ["wildcard"]       = { flag = "wildcard" },
    ["-3 conditions"]  = { flag = "condition_3_discount" },
  }

  cnsts.waza_small_play = { hand_only = true, max_size = 2 }

  cnsts.player_boards = {}
  cnsts.player_boards.White = "4b4e4a"
  cnsts.player_boards.Red = "c19d47"
  cnsts.player_boards.Blue = "bc2ce0"
  cnsts.player_boards.Yellow = "cf087b"

  cnsts.action_card_init_zones = { base = {}, mw = {} }
  cnsts.action_card_init_zones.base.White = "b1a294"
  cnsts.action_card_init_zones.base.Red = "5831e8"
  cnsts.action_card_init_zones.base.Blue = "f154a9"
  cnsts.action_card_init_zones.base.Yellow = "7a48fc"
  cnsts.action_card_init_zones.mw.White = "414fdf"
  cnsts.action_card_init_zones.mw.Red = "56d444"
  cnsts.action_card_init_zones.mw.Blue = "440a93"
  cnsts.action_card_init_zones.mw.Yellow = "d35939"

  cnsts.draft_deck_zone = "094f52"
  cnsts.discard_pile_zone = "359562"
  cnsts.final_scoring_discard_zone = "fa15ae"
  cnsts.pouch_base_position = { x = 0, y = -10, z = 0 }
  cnsts.pouch_slot_spacing = 3
  cnsts.pouch_card_spacing = 0.5

  cnsts.pouch_counter = {
    card = 269,
    position = { 0, 0.2, -0.9 },
    width = 800,
    height = 180,
    font_size = 100,
    color = { 1, 1, 1, 0.9 },
    font_color = { 0, 0, 0, 1 },
  }

  cnsts.mw_zones = {
    zoo = "219a36",
    conservation = "b2f4d4",
    final_scoring = "ccdced",
    draft = cnsts.draft_deck_zone
  }

  cnsts.bonus_tile_containers = {
    base = "1c73d4",
    mw = "34014b"
  }

  cnsts.build_tile_shapes = {
    KIOSK = { 1 },
    PAVILION = { 1 },
    ["SIZE 1"] = { 1 },
    ["MASCOT STATUE"] = { 1 },

    ["SIZE 2"] = { 1, 2 },
    ["SMALL AQUARIUM"] = { 1, 2 },
    ["SIDE ENTRANCE"] = { 1, 2 },
    ["ADVENTURE PLAYGROUND"] = { 1, 2 },
    ["WATER PLAYGROUND"] = { 1, 2 },
    ["UNDERWATER TUNNEL"] = { 1, 2 },

    ["SIZE 3"] = { 49, 43, 42 },
    ["SIZE 4"] = { 42, 49, 48, 43 },
    ["SIZE 5"] = { 42, 49, 43, 50, 44 },
    ["PETTING ZOO"] = { 43, 49, 48 },
    ["LARGE AQUARIUM"] = { 30, 37, 43, 44, 51 },

    ["ZOO SCHOOL"] = { 38, 44, 43 },
    ["BARRED OWL HUT"] = { 42, 43, 44 },
    ["MEERKAT DEN"] = { 43, 49, 56 },
    ["CABLE CAR"] = { 42, 43, 44, 45 },
    AQUARIUM = { 44, 51, 57, 43 },
    ["SPOTTED HYENA COMPOUND"] = { 24, 31, 37, 43 },
    ["OKAPI STABLE"] = { 23, 30, 36, 43 },
    ["PENGUIN POOL"] = { 36, 42, 43, 48 },
    ["BABOON ROCK"] = { 30, 31, 37, 43 },
    ["POLAR BEAR EXHIBIT"] = { 24, 30, 37, 43 },
    ["RHESUS MONKEY PARK"] = { 52, 45, 43, 44 },
    ["SEA TURTLE TANK"] = { 30, 37, 38, 43 },
    ["AMAZON HOUSE"] = { 30, 37, 44, 43, 49 },
    ["EXCAVATION SITE"] = { 31, 30, 36, 43, 49 },
    ["LARGE BIRD AVIARY"] = { 29, 30, 36, 43, 35 },
    ["REPTILE HOUSE"] = { 50, 43, 36, 37, 49 }
  }

  cnsts.build_buildings = {
    "KIOSK", "PAVILION", "SIZE 1", "SIZE 2", "SIZE 3", "SIZE 4", "SIZE 5",
    "REPTILE HOUSE", "LARGE BIRD AVIARY", "PETTING ZOO", "SMALL AQUARIUM",
    "LARGE AQUARIUM",
  }

  cnsts.sponsor_buildings = {}
  do
    local in_build = {}
    for _, name in ipairs(cnsts.build_buildings) do in_build[name] = true end
    for name in pairs(cnsts.build_tile_shapes) do
      if not in_build[name] then
        cnsts.sponsor_buildings[#cnsts.sponsor_buildings + 1] = name
      end
    end
    table.sort(cnsts.sponsor_buildings)
  end

  cnsts.drafting_boxes = {}
  cnsts.drafting_boxes.White = "97fcff"
  cnsts.drafting_boxes.Red = "4b48f8"
  cnsts.drafting_boxes.Blue = "577765"
  cnsts.drafting_boxes.Yellow = "4af911"

  cnsts.map_keys = {
    ["Observation Tower"] = { top = "map_1", bottom = "map_1a" },
    ["Outdoor Areas"] = { top = "map_2", bottom = "map_2a" },
    ["Silver Lake"] = { top = "map_3", bottom = "map_3a" },
    ["Commercial Harbor"] = { top = "map_4", bottom = "map_4a" },
    ["Park Restaurant"] = { top = "map_5", bottom = "map_5a" },
    ["Research Institute"] = { top = "map_6", bottom = "map_6a" },
    ["Ice Cream Parlors"] = { top = "map_7", bottom = "map_7a" },
    ["Hollywood Hills"] = { top = "map_8", bottom = "map_8a" },
    ["Geographical Zoo"] = { top = "map_9", bottom = "map_0" },
    ["Rescue Station"] = { top = "map_10", bottom = "map_0" },
    ["Caves"] = { top = "map_11", bottom = "map_A" },
    ["Artificial Intelligence"] = { top = "map_12", bottom = "map_A" },
    ["Drawing Board"] = { top = "map_13", bottom = "map_T1" },
    ["Lagoon"] = { top = "map_14", bottom = "map_T1" }
  }

  cnsts.map_data = {
    map_1 = { image = "https://steamusercontent-a.akamaihd.net/ugc/13149468351109473583/B0EC6C1188CA5F15B7B8C8BC873F4DCF6619EC1D/",
  project_rewards = {{"snap 1", "purple"}, {"free size_2", "purple"}, {"5 money", "purple"}, {"marketing", "purple"}, {"unlock worker", "yellow"}, {"12 money", "yellow"}, {"3 x_token", "yellow"}},
partner_zoo_rewards = {{}, {"card flip"}, {"unlock worker"}, {"2 cp"}},
university_rewards = {{}, {"card flip"}, {"1 cp"}},
worker_rewards = {{}, {}, {}} },
    map_1a = { image = "https://steamusercontent-a.akamaihd.net/ugc/16137145855675517501/24FF0DBF42E8754F9CB8F64D6F4CF290D2A5539D/",
  project_rewards = {{"snap 1", "purple"}, {"free size_2", "purple"}, {"5 money", "purple"}, {"marketing", "purple"}, {"unlock worker", "yellow"}, {"12 money", "yellow"}, {"3 x_token", "yellow"}},
partner_zoo_rewards = {{}, {"card flip"}, {"unlock worker"}, {"2 cp"}},
university_rewards = {{}, {"card flip"}, {"1 cp"}},
worker_rewards = {{}, {}, {}} },
    map_2 = { image = "https://steamusercontent-a.akamaihd.net/ugc/10824427834599469527/9B82E3EF0CFCCB57C990B66A49879CDD7DA28298/",
  project_rewards = {{"snap 1", "purple"}, {"free size_2", "purple"}, {"5 money", "purple"}, {"1 cp", "yellow"}, {"unlock worker", "yellow"}, {"12 money", "yellow"}, {"3 x_token", "yellow"}},
partner_zoo_rewards = {{}, {"card flip"}, {"unlock worker"}, {}},
university_rewards = {{}, {"card flip"}, {"2 cp"}},
worker_rewards = {{}, {}, {"1 cp"}} },
    map_2a = { image = "https://steamusercontent-a.akamaihd.net/ugc/10577163683473402417/2D097F380BA3C71396DB6EE5C02C0BFF623B6B55/",
  project_rewards = {{"snap 1", "purple"}, {"free size_2", "purple"}, {"5 money", "purple"}, {"1 cp", "yellow"}, {"unlock worker", "yellow"}, {"12 money", "yellow"}, {"3 x_token", "yellow"}},
partner_zoo_rewards = {{}, {"card flip"}, {"unlock worker"}, {}},
university_rewards = {{}, {"card flip"}, {"2 cp"}},
worker_rewards = {{}, {}, {"1 cp"}} },
    map_3 = { image = "https://steamusercontent-a.akamaihd.net/ugc/12551385021451068955/E65ED37683C81E74B0C5E6719C80928DB8762733/",
  project_rewards = {{"snap 1", "purple"}, {"free size_2", "purple"}, {"5 money", "purple"}, {"determination", "yellow"}, {"unlock worker", "yellow"}, {"12 money", "yellow"}, {"3 x_token", "yellow"}},
partner_zoo_rewards = {{}, {"card flip"}, {"unlock worker"}, {"1 cp"}},
university_rewards = {{}, {"card flip"}, {"2 cp"}},
worker_rewards = {{}, {}, {}} },
    map_3a = { image = "https://steamusercontent-a.akamaihd.net/ugc/15244331060792240125/CAA0A057A77D611F1D91254674AE5EE5E142DB3F/",
  project_rewards = {{"snap 1", "purple"}, {"free size_2", "purple"}, {"5 money", "purple"}, {"determination", "yellow"}, {"unlock worker", "yellow"}, {"12 money", "yellow"}, {"3 x_token", "yellow"}},
partner_zoo_rewards = {{}, {"card flip"}, {"unlock worker"}, {"1 cp"}},
university_rewards = {{}, {"card flip"}, {"2 cp"}},
worker_rewards = {{}, {}, {}} },
    map_4 = { image = "https://steamusercontent-a.akamaihd.net/ugc/13175963203550607676/49D4984D8C70CFD42F4FDAD6AC0AF74BF70B5FF6/",
  project_rewards = {{"snap 1", "purple"}, {"free size_2", "purple"}, {"5 money", "purple"}, {"get university", "yellow"}, {"unlock worker", "yellow"}, {"12 money", "yellow"}, {"3 x_token", "yellow"}},
partner_zoo_rewards = {{}, {"card flip"}, {"unlock worker"}, {"1 cp"}},
university_rewards = {{}, {"card flip"}, {"1 cp"}},
worker_rewards = {{}, {}, {"1 cp"}} },
    map_4a = { image = "https://steamusercontent-a.akamaihd.net/ugc/11579019465649451474/1E0388FF569FB267C34E5837F95A05EE32EB2B05/",
  project_rewards = {{"snap 1", "purple"}, {"free size_2", "purple"}, {"5 money", "purple"}, {"get university", "yellow"}, {"unlock worker", "yellow"}, {"12 money", "yellow"}, {"3 x_token", "yellow"}},
partner_zoo_rewards = {{}, {"card flip"}, {"unlock worker"}, {"1 cp"}},
university_rewards = {{}, {"card flip"}, {"1 cp"}},
worker_rewards = {{}, {}, {"1 cp"}} },
    map_5 = { image = "https://steamusercontent-a.akamaihd.net/ugc/15812925102714664365/85556C88498949CE6FD8AD4295262B029C10199D/",
  project_rewards = {{"snap 1", "purple"}, {"free size_2", "purple"}, {"5 money", "purple"}, {"reptile house or aviary", "yellow"}, {"unlock worker", "yellow"}, {"12 money", "yellow"}, {"3 x_token", "yellow"}},
partner_zoo_rewards = {{}, {"card flip"}, {"unlock worker"}, {"2 cp"}},
university_rewards = {{}, {"card flip"}, {}},
worker_rewards = {{}, {}, {"1 cp"}} },
    map_5a = { image = "https://steamusercontent-a.akamaihd.net/ugc/16774745763601167727/FED11FBD44A3DCFC99DABE0144A9AB3E0C5C7F39/",
  project_rewards = {{"snap 1", "purple"}, {"free size_2", "purple"}, {"5 money", "purple"}, {"reptile house or aviary", "yellow"}, {"unlock worker", "yellow"}, {"12 money", "yellow"}, {"3 x_token", "yellow"}},
partner_zoo_rewards = {{}, {"card flip"}, {"unlock worker"}, {"2 cp"}},
university_rewards = {{}, {"card flip"}, {}},
worker_rewards = {{}, {}, {"1 cp"}} },
    map_6 = { image = "https://steamusercontent-a.akamaihd.net/ugc/16608585406936532817/25629762D82B47C122CA21E6A6782549AA8EB87A/",
  project_rewards = {{"snap 1", "purple"}, {"free size_2", "purple"}, {"5 money", "purple"}, {"clever 2", "purple"}, {"unlock worker", "yellow"}, {"12 money", "yellow"}, {"3 x_token", "yellow"}},
partner_zoo_rewards = {{}, {"card flip"}, {"unlock worker"}, {"1 cp"}},
university_rewards = {{}, {"card flip"}, {}},
worker_rewards = {{}, {}, {"2 cp"}} },
    map_6a = { image = "https://steamusercontent-a.akamaihd.net/ugc/11501893473630051831/394E40C02FA2A109A0D8A2854E49DAD9501B8A3F/",
  project_rewards = {{"snap 1", "purple"}, {"free size_2", "purple"}, {"5 money", "purple"}, {"clever 2", "purple"}, {"unlock worker", "yellow"}, {"12 money", "yellow"}, {"3 x_token", "yellow"}},
partner_zoo_rewards = {{}, {"card flip"}, {"unlock worker"}, {"1 cp"}},
university_rewards = {{}, {"card flip"}, {}},
worker_rewards = {{}, {}, {"2 cp"}} },
    map_7 = { image = "https://steamusercontent-a.akamaihd.net/ugc/16124295239135976631/59D5411132CF6420868BF81B7F3EB1398FDD62D3/",
  project_rewards = {{"snap 1", "purple"}, {"free size_2", "purple"}, {"5 money", "purple"}, {"pouch 2", "purple"}, {"unlock worker", "yellow"}, {"12 money", "yellow"}, {"3 x_token", "yellow"}},
partner_zoo_rewards = {{}, {"card flip"}, {"unlock worker"}, {}},
university_rewards = {{}, {"card flip"}, {"1 cp"}},
worker_rewards = {{}, {}, {"2 cp"}} },
    map_7a = { image = "https://steamusercontent-a.akamaihd.net/ugc/16455639169571594071/3819A3C376B6C62FAFF538114114431C18E64621/",
  project_rewards = {{"snap 1", "purple"}, {"free size_2", "purple"}, {"5 money", "purple"}, {"pouch 2", "purple"}, {"unlock worker", "yellow"}, {"12 money", "yellow"}, {"3 x_token", "yellow"}},
partner_zoo_rewards = {{}, {"card flip"}, {"unlock worker"}, {}},
university_rewards = {{}, {"card flip"}, {"1 cp"}},
worker_rewards = {{}, {}, {"2 cp"}} },
    map_8 = { image = "https://steamusercontent-a.akamaihd.net/ugc/13490828978918966928/CB17423D232A2FB5FCDC2A3D680A6C68C8916F0F/",
  project_rewards = {{"snap 1", "purple"}, {"free size_2", "purple"}, {"5 money", "purple"}, {"get partner zoo", "yellow"}, {"unlock worker", "yellow"}, {"12 money", "yellow"}, {"3 x_token", "yellow"}},
partner_zoo_rewards = {{}, {"card flip"}, {"unlock worker"}, {"1 cp"}},
university_rewards = {{}, {"card flip"}, {"1 cp"}},
worker_rewards = {{}, {}, {"1 cp"}} },
    map_8a = { image = "https://steamusercontent-a.akamaihd.net/ugc/10388413842149324218/2EDCE88686BD58B42C422ED630D0294E992D73ED/",
  project_rewards = {{"snap 1", "purple"}, {"free size_2", "purple"}, {"5 money", "purple"}, {"get partner zoo", "yellow"}, {"unlock worker", "yellow"}, {"12 money", "yellow"}, {"3 x_token", "yellow"}},
partner_zoo_rewards = {{}, {"card flip"}, {"unlock worker"}, {"1 cp"}},
university_rewards = {{}, {"card flip"}, {"1 cp"}},
worker_rewards = {{}, {}, {"1 cp"}} },
    map_9 = { image = "https://steamusercontent-a.akamaihd.net/ugc/16538003740535574358/21C8DC9DCAE28CFC8C4562CD8680F123BB6B0875/",
  project_rewards = {{"snap 1", "purple"}, {"free size_2", "purple"}, {"5 money", "purple"}, {"geographical zoo cube", "yellow"}, {"unlock worker", "yellow"}, {"12 money", "yellow"}, {"3 x_token", "yellow"}},
partner_zoo_rewards = {{}, {"card flip"}, {"unlock worker"}, {"2 cp"}},
university_rewards = {{}, {"card flip"}, {"1 cp"}},
worker_rewards = {{}, {}, {}},
geographical_rewards = {{"1 rep"}, {"4 money"}, {"clever 1"}, {"2 appeal"}, {"posturing 1"}} },
    map_10 = { image = "https://steamusercontent-a.akamaihd.net/ugc/12604488069415636168/A20AFE088B5A3B769EAD139CC4EFAAEC4CC8BFFA/",
  project_rewards = {{"snap 1", "purple"}, {"free size_2", "purple"}, {"5 money", "purple"}, {"2 rep", "yellow"}, {"unlock worker", "yellow"}, {"12 money", "yellow"}, {"3 x_token", "yellow"}},
partner_zoo_rewards = {{}, {"card flip"}, {"unlock worker"}, {"1 cp"}},
university_rewards = {{}, {"card flip"}, {}},
worker_rewards = {{}, {}, {"2 cp"}} },
    map_11 = { image = "https://steamusercontent-a.akamaihd.net/ugc/16995705196234951752/9853F944B2DDF01A71BD68F5AF5BCDFA9BA3F2F3/",
  project_rewards = {{"snap 1", "purple"}, {"free size_2", "purple"}, {"5 money", "purple"}, {"card flip", "yellow"}, {"unlock worker", "yellow"}, {"12 money", "yellow"}, {"3 x_token", "yellow"}},
partner_zoo_rewards = {{"card flip 0.5"}, {"extra shift 0.5"}, {"unlock worker", "1 cp 0.5"}, {"1 cp"}},
university_rewards = {{"card flip 0.5"}, {"extra shift 0.5"}, {"1 cp 0.5"}},
worker_rewards = {{}, {"card flip"}, {"1 cp"}} },
    map_12 = { image = "https://steamusercontent-a.akamaihd.net/ugc/14935848765409048892/2075BC8D8A6CFBB4BC47A9D2B569CEE611FA6157/",
  project_rewards = {{"snap 1", "purple"}, {"free size_2", "purple"}, {"5 money", "purple"}, {"animal magnet", "yellow"}, {"unlock worker", "yellow"}, {"12 money", "yellow"}, {"3 x_token", "yellow"}},
partner_zoo_rewards = {{"card flip 0.5"}, {"card flip b 0.5"}, {"unlock worker"}, {"2 cp"}},
university_rewards = {{"card flip 0.5"}, {"card flip b 0.5", "artificial intelligence"}, {}},
worker_rewards = {{}, {"artificial intelligence"}, {"1 cp"}} },
    map_13 = { image = "https://steamusercontent-a.akamaihd.net/ugc/13110280858456296637/3F44DCE727C43B0D3BD21447BBD6FECD2B20CBB0/",
  project_rewards = {{"snap 1", "purple"}, {"cut down", "purple"}, {"5 money", "purple"}, {"adapt 3", "yellow"}, {"unlock worker", "yellow"}, {"12 money", "yellow"}, {"3 x_token", "yellow"}},
partner_zoo_rewards = {{}, {"card flip"}, {"unlock worker"}, {"1 cp"}},
university_rewards = {{}, {"card flip"}, {"2 cp"}},
worker_rewards = {{}, {}, {}} },
    map_14 = { image = "https://steamusercontent-a.akamaihd.net/ugc/11930630501887485135/803A9889CB5CE25CADB290D9C47FBD2CE46596D2/",
  project_rewards = {{"snap 1", "purple"}, {"free size_2", "purple"}, {"5 money", "purple"}, {"play person sponsor", "purple"}, {"unlock worker", "yellow"}, {"12 money", "yellow"}, {"3 x_token", "yellow"}},
partner_zoo_rewards = {{}, {"card flip"}, {"unlock worker"}, {"1 cp"}},
university_rewards = {{}, {"card flip"}, {"1 cp"}},
worker_rewards = {{"search person_sponsor"}, {"search person_sponsor"}, {"search person_sponsor", "1 cp"}} },
    map_0 = { image = "https://steamusercontent-a.akamaihd.net/ugc/15298809577842304588/C2887768C3F1F1F6F63DC257BDC8722EBE531F31/",
  project_rewards = {{"snap 1", "purple"}, {"free size_2", "purple"}, {"5 money", "purple"}, {"1 cp", "purple"}, {"unlock worker", "yellow"}, {"12 money", "yellow"}, {"3 x_token", "yellow"}},
partner_zoo_rewards = {{}, {"card flip"}, {"unlock worker"}, {"2 cp"}},
university_rewards = {{}, {"card flip"}, {"2 cp"}},
worker_rewards = {{}, {}, {"2 cp"}} },
    map_A = { image = "https://steamusercontent-a.akamaihd.net/ugc/17823526998776023033/4C4F84459ED1664BA30CD4E5B5670C464D407F38/",
  project_rewards = {{"snap 1", "purple"}, {"free size_2", "purple"}, {"5 money", "purple"}, {"1 cp", "purple"}, {"2 rep", "yellow"}, {"12 money", "yellow"}, {"3 x_token", "yellow"}},
partner_zoo_rewards = {{}, {"card flip"}, {"unlock worker"}, {"2 cp"}},
university_rewards = {{}, {"card flip"}, {"2 cp"}},
worker_rewards = {{}, {}, {"2 cp"}} },
    map_T1 = { image = "https://steamusercontent-a.akamaihd.net/ugc/12171062570692623889/BDF8989CD45F8A7F8B16E8510E979F77D03C5697/",
  project_rewards = {{"draw t1 unlock", "purple"}, {"free size_2", "purple"}, {"5 money", "purple"}, {"3 rep", "yellow"}, {"unlock worker", "yellow"}, {"12 money", "yellow"}, {"3 x_token", "yellow"}},
partner_zoo_rewards = {{"card flip 0.5"}, {"card flip b 0.5"}, {"unlock worker"}, {"1 cp"}},
university_rewards = {{"card flip 0.5"}, {"card flip b 0.5"}, {"1 cp"}},
worker_rewards = {{"1 rep"}, {"1 rep"}, {"1 cp"}} }
  }

  cnsts.map_data.map_1.cells = {
    { { reward = "1 x_token" }, {}, { terrain = "rock" }, { terrain = "rock" }, { terrain = "rock" }, { reward = "5 money" } },
    { { terrain = "rock" }, {}, {}, { terrain = "rock", special = "observation tower" }, {}, {}, {} },
    { { terrain = "rock" }, {}, {}, {}, {}, {} },
    { { terrain = "rock" }, {}, { terrain = "upgd" }, { reward = "draw 1" }, {}, { terrain = "rock" }, { terrain = "rock" } },
    { { reward = "clever 1" }, {}, { terrain = "water" }, { terrain = "upgd" }, {}, { reward = "1 rep" } },
    { {}, {}, {}, { terrain = "water" }, { terrain = "upgd" }, {}, { terrain = "water" } },
    { {}, {}, { reward = "5 money" }, { terrain = "water" }, {}, {} },
    { {}, { reward = "draw 1" }, {}, { terrain = "water" }, { reward = "1 x_token" }, {}, { reward = "1 x_token" } },
    { {}, {}, { terrain = "water" }, { terrain = "water" }, {}, {} }
  }

  cnsts.map_data.map_1a.cells = {
    { { reward = "1 x_token" }, {}, { terrain = "rock" }, { terrain = "rock" }, { terrain = "water" }, { reward = "5 money" } },
    { { terrain = "rock" }, {}, {}, { terrain = "rock" }, { reward = "1 x_token" }, {}, {} },
    { { terrain = "rock" }, {}, {}, {}, {}, {} },
    { { terrain = "rock" }, { reward = "5 money" }, { terrain = "upgd" }, { reward = "draw 1" }, {}, { terrain = "rock" }, { terrain = "rock" } },
    { {}, {}, { terrain = "water" }, { terrain = "upgd" }, {}, { reward = "1 rep" } },
    { {}, {}, { reward = "draw 1" }, { terrain = "water" }, { terrain = "upgd" }, {}, { terrain = "water" } },
    { {}, {}, {}, {}, {}, {} },
    { {}, {}, {}, { terrain = "rock", special = "observation tower" }, {}, {}, { reward = "1 x_token" } },
    { { reward = "clever 1" }, { terrain = "water" }, { terrain = "water" }, { terrain = "water" }, {}, {} }
  }

  cnsts.map_data.map_2.cells = {
    { { terrain = "rock" }, { terrain = "rock" }, { reward = "1 rep" }, {}, { terrain = "rock" }, { terrain = "rock" } },
    { { terrain = "upgd" }, { reward = "get partner zoo" }, { terrain = "rock" }, {}, {}, { terrain = "rock" }, { reward = "marketing" } },
    { { terrain = "upgd" }, {}, {}, {}, {}, {} },
    { {}, {}, {}, { terrain = "upgd" }, { terrain = "water" }, {}, {} },
    { { terrain = "rock" }, {}, {}, { reward = "1 x_token" }, { terrain = "water" }, { terrain = "water" } },
    { { terrain = "rock" }, { reward = "draw 1" }, {}, { terrain = "upgd" }, { terrain = "water", special = "outdoor areas" }, { terrain = "water" }, {} },
    { { terrain = "water" }, {}, {}, {}, {}, {} },
    { { terrain = "water" }, { reward = "draw 1" }, {}, { reward = "1 x_token" }, {}, {}, {} },
    { {}, {}, { terrain = "rock" }, {}, {}, { reward = "clever 1" } }
  }

  cnsts.map_data.map_2a.cells = {
    { { terrain = "water" }, { terrain = "rock" }, { reward = "draw 1" }, {}, { terrain = "rock" }, { terrain = "rock" } },
    { { terrain = "upgd" }, { reward = "get partner zoo" }, { terrain = "rock" }, {}, {}, { terrain = "rock" }, { reward = "1 rep" } },
    { { terrain = "upgd" }, {}, { terrain = "upgd" }, {}, {}, {} },
    { { terrain = "upgd" }, {}, {}, {}, { terrain = "water" }, {}, {} },
    { { terrain = "rock" }, {}, {}, {}, { terrain = "water" }, {} },
    { { terrain = "rock" }, { reward = "draw 1" }, { terrain = "rock" }, { terrain = "upgd" }, { terrain = "water", special = "outdoor areas" }, { terrain = "water" }, {} },
    { { terrain = "water" }, {}, {}, {}, {}, {} },
    { { terrain = "water" }, { reward = "marketing" }, {}, { reward = "1 x_token" }, {}, { reward = "clever 1" }, {} },
    { {}, {}, { terrain = "rock" }, {}, {}, {} }
  }

  cnsts.map_data.map_3.cells = {
    { { terrain = "upgd" }, { reward = "1 rep" }, { reward = "2 money" }, { reward = "2 money" }, {}, { terrain = "water" } },
    { { terrain = "upgd" }, { terrain = "upgd", reward = "2 money" }, { terrain = "upgd", reward = "2 money" }, { terrain = "water" }, { reward = "2 money" }, {}, { reward = "draw 1" } },
    { { terrain = "upgd", reward = "2 money" }, { terrain = "water" }, { terrain = "water" }, { terrain = "water" }, { reward = "2 money" }, {} },
    { {}, { reward = "2 money" }, { reward = "2 money" }, { reward = "2 money" }, { reward = "2 money" }, {}, { terrain = "rock" } },
    { {}, {}, {}, {}, { reward = "1 rep" }, { terrain = "rock" } },
    { { terrain = "rock" }, { reward = "clever 1" }, {}, { reward = "draw 1" }, {}, { terrain = "water" }, { terrain = "water" } },
    { { terrain = "water" }, { terrain = "rock" }, {}, {}, { terrain = "water" }, { reward = "1 x_token" } },
    { { terrain = "rock" }, { reward = "marketing" }, {}, {}, {}, {}, {} },
    { {}, {}, { terrain = "rock" }, { terrain = "rock" }, { reward = "1 x_token" }, {} }
  }

  cnsts.map_data.map_3a.cells = {
    { {}, {}, {}, { terrain = "rock" }, {}, { terrain = "water" } },
    { {}, { reward = "1 rep" }, {}, {}, { reward = "draw 1" }, {}, { reward = "draw 1" } },
    { {}, {}, { reward = "2 money" }, { terrain = "upgd", reward = "2 money" }, {}, {} },
    { {}, { reward = "2 money" }, { reward = "2 money" }, { terrain = "water" }, { reward = "2 money" }, {}, { terrain = "rock" } },
    { { terrain = "upgd", reward = "2 money" }, { terrain = "water" }, { terrain = "water" }, { terrain = "water" }, { reward = "2 money" }, { terrain = "rock" } },
    { {}, { reward = "2 money" }, { reward = "2 money" }, { terrain = "upgd", reward = "2 money" }, { reward = "2 money" }, { terrain = "water" }, { terrain = "water" } },
    { { terrain = "water" }, { terrain = "rock" }, {}, {}, { terrain = "water" }, { reward = "1 x_token" } },
    { { terrain = "rock" }, { reward = "marketing" }, {}, { reward = "clever 1" }, {}, {}, {} },
    { {}, {}, { terrain = "rock" }, { terrain = "rock" }, { reward = "1 x_token" }, {} }
  }

  cnsts.map_data.map_4.cells = {
    { {}, {}, { reward = "1 rep" }, {}, { terrain = "water" }, { special = "commercial harbor" } },
    { {}, { reward = "1 x_token" }, { terrain = "water" }, {}, {}, {}, { terrain = "water" } },
    { {}, { terrain = "water" }, { terrain = "water" }, {}, { reward = "clever 1" }, {} },
    { {}, { reward = "1 x_token" }, { terrain = "water" }, { reward = "draw 1" }, { terrain = "rock" }, { terrain = "rock" }, {} },
    { {}, {}, {}, {}, {}, {} },
    { { terrain = "water" }, {}, { reward = "1 x_token" }, {}, {}, {}, { terrain = "rock" } },
    { { reward = "draw 1" }, { terrain = "upgd" }, { terrain = "rock" }, { terrain = "rock" }, {}, {} },
    { {}, { terrain = "rock" }, { reward = "multiplier_token" }, {}, {}, { terrain = "rock" }, {} },
    { { terrain = "water" }, { terrain = "water" }, { terrain = "upgd" }, { terrain = "upgd" }, { terrain = "upgd" }, { reward = "5 money" } }
  }

  cnsts.map_data.map_4a.cells = {
    { { terrain = "upgd" }, {}, { reward = "draw 1" }, {}, { terrain = "water" }, { special = "commercial harbor" } },
    { {}, { reward = "marketing" }, { terrain = "water" }, {}, {}, { reward = "draw 1" }, { terrain = "water" } },
    { {}, { terrain = "water" }, { terrain = "water" }, {}, {}, {} },
    { {}, { reward = "1 x_token" }, { terrain = "water" }, { reward = "draw 1" }, { terrain = "rock" }, { terrain = "rock" }, {} },
    { {}, {}, {}, {}, {}, { reward = "draw 1" } },
    { { terrain = "water" }, {}, { reward = "1 x_token" }, { terrain = "upgd" }, {}, {}, { terrain = "rock" } },
    { { reward = "1 rep" }, { terrain = "upgd" }, { terrain = "rock" }, { terrain = "rock" }, { reward = "clever 1" }, {} },
    { {}, { terrain = "rock" }, { reward = "multiplier_token" }, {}, {}, { terrain = "rock" }, {} },
    { { terrain = "water" }, { terrain = "water" }, { terrain = "upgd" }, {}, {}, {} }
  }

  cnsts.map_data.map_5.cells = {
    { {}, {}, { terrain = "water" }, {}, {}, {} },
    { { reward = "1 x_token" }, { terrain = "upgd" }, { terrain = "water" }, { reward = "1 x_token" }, { terrain = "rock" }, { terrain = "upgd" }, {} },
    { {}, { terrain = "rock" }, { terrain = "rock" }, { reward = "marketing" }, { terrain = "water" }, {} },
    { {}, {}, {}, {}, {}, {}, {} },
    { { reward = "clever 1" }, { terrain = "water" }, { terrain = "rock", special = "park restaurant" }, {}, { reward = "draw 1" }, {} },
    { {}, {}, {}, {}, { terrain = "water" }, { terrain = "water" }, { terrain = "upgd" } },
    { { terrain = "rock" }, { reward = "draw 1" }, {}, { reward = "draw 1" }, { terrain = "rock" }, { reward = "5 money" } },
    { {}, {}, { terrain = "rock" }, { terrain = "water" }, {}, {}, {} },
    { {}, { reward = "1 rep" }, {}, { terrain = "water" }, {}, {} }
  }

  cnsts.map_data.map_5a.cells = {
    { { terrain = "upgd" }, {}, { terrain = "water" }, {}, {}, {} },
    { { reward = "clever 1" }, {}, { terrain = "water" }, { reward = "1 x_token" }, { terrain = "rock" }, { reward = "draw 1" }, {} },
    { {}, { terrain = "rock" }, { reward = "marketing" }, {}, { terrain = "water" }, {} },
    { {}, {}, {}, {}, {}, {}, {} },
    { { reward = "1 x_token" }, {}, { terrain = "rock", special = "park restaurant" }, { terrain = "water" }, {}, { reward = "draw 1" } },
    { { terrain = "rock" }, {}, {}, {}, {}, {}, { terrain = "water" } },
    { { terrain = "rock" }, {}, { terrain = "water" }, { reward = "draw 1" }, { terrain = "rock" }, { reward = "5 money" } },
    { {}, { reward = "1 rep" }, {}, { terrain = "water" }, {}, {}, {} },
    { {}, { terrain = "upgd" }, { terrain = "rock" }, { terrain = "water" }, { terrain = "upgd" }, {} }
  }

  cnsts.map_data.map_6a.cells = {
    { { terrain = "water" }, { terrain = "water" }, {}, {}, {}, { special = "research institute" } },
    { {}, { reward = "1 rep" }, {}, {}, { reward = "5 money" }, {}, {} },
    { {}, {}, { reward = "1 x_token" }, { terrain = "rock" }, { terrain = "rock" }, {} },
    { {}, { reward = "1 x_token" }, {}, { terrain = "rock" }, { terrain = "rock" }, {}, {} },
    { { terrain = "rock" }, { terrain = "upgd" }, {}, {}, { terrain = "upgd" }, { reward = "5 money" } },
    { { terrain = "rock" }, { reward = "clever 1" }, {}, {}, {}, { terrain = "water" }, { terrain = "water" } },
    { { terrain = "upgd" }, {}, {}, {}, {}, {} },
    { { terrain = "upgd" }, { reward = "get university" }, { terrain = "water" }, { terrain = "water" }, {}, { terrain = "rock" }, { reward = "draw 1" } },
    { { terrain = "water" }, { terrain = "water" }, { reward = "draw 1" }, {}, {}, { terrain = "water" } }
  }

  cnsts.map_data.map_7a.cells = {
    { { terrain = "water" }, { terrain = "rock" }, { reward = "free kiosk", special = "ice cream parlors" }, {}, {}, {} },
    { {}, { reward = "1 rep" }, {}, {}, { terrain = "rock" }, { reward = "1 rep" }, {} },
    { {}, {}, { reward = "1 x_token" }, {}, { terrain = "rock" }, {} },
    { {}, { reward = "draw 1" }, { terrain = "rock" }, { terrain = "upgd" }, {}, { terrain = "upgd" }, { terrain = "upgd" } },
    { { terrain = "rock" }, { terrain = "rock" }, {}, { reward = "draw 1" }, { terrain = "rock" }, {} },
    { { terrain = "rock" }, { reward = "1 x_token" }, {}, {}, { terrain = "rock" }, { reward = "free kiosk", special = "ice cream parlors" }, {} },
    { { reward = "draw 1" }, {}, {}, {}, {}, {} },
    { { terrain = "water" }, {}, { reward = "free kiosk", special = "ice cream parlors" }, {}, {}, { terrain = "water" }, { reward = "5 money" } },
    { { terrain = "water" }, { terrain = "water" }, { terrain = "water" }, {}, { reward = "marketing" }, { terrain = "water" } }
  }

  cnsts.map_data.map_8a.cells = {
    { {}, {}, {}, { reward = "1 x_token" }, { terrain = "water" }, { terrain = "rock" } },
    { { terrain = "water" }, { reward = "5 money" }, { terrain = "water" }, {}, {}, { special = "hollywood hills" }, { terrain = "rock" } },
    { {}, {}, { terrain = "water" }, { terrain = "upgd" }, {}, { terrain = "rock" } },
    { { reward = "1 x_token" }, {}, {}, { terrain = "upgd" }, {}, {}, { terrain = "rock" } },
    { {}, { terrain = "water" }, { reward = "1 rep" }, {}, { terrain = "rock" }, { special = "hollywood hills" } },
    { {}, { terrain = "rock" }, { terrain = "water" }, {}, {}, { terrain = "upgd" }, { terrain = "rock" } },
    { { reward = "1 rep" }, { terrain = "water" }, {}, {}, {}, { terrain = "rock" } },
    { {}, {}, { reward = "1 x_token" }, {}, { special = "hollywood hills" }, { terrain = "rock" }, { reward = "clever 1" } },
    { {}, {}, {}, {}, { reward = "draw 1" }, {} }
  }

  cnsts.map_data.map_6.cells = {
    { { terrain = "water" }, { terrain = "water" }, {}, {}, {}, { special = "research institute" } },
    { {}, { reward = "1 x_token" }, {}, {}, { reward = "clever 1" }, {}, {} },
    { {}, {}, { reward = "5 money" }, { terrain = "rock" }, { terrain = "rock" }, {} },
    { { reward = "1 x_token" }, {}, {}, { terrain = "rock" }, { terrain = "rock" }, { reward = "draw 1" }, {} },
    { { terrain = "rock" }, { terrain = "upgd" }, {}, {}, {}, {} },
    { { terrain = "rock" }, { reward = "draw 1" }, { terrain = "upgd" }, {}, {}, { terrain = "water" }, { terrain = "water" } },
    { { terrain = "upgd" }, {}, {}, {}, {}, { reward = "1 rep" } },
    { { terrain = "upgd" }, { reward = "get university" }, { terrain = "water" }, { terrain = "water" }, {}, { terrain = "rock" }, {} },
    { { terrain = "water" }, { terrain = "water" }, {}, { reward = "5 money" }, {}, { terrain = "water" } }
  }

  cnsts.map_data.map_7.cells = {
    { { terrain = "rock" }, { terrain = "rock" }, { reward = "1 rep" }, {}, {}, {} },
    { {}, { reward = "free kiosk", special = "ice cream parlors" }, {}, {}, { terrain = "rock" }, { reward = "1 rep" }, {} },
    { {}, {}, {}, {}, { terrain = "rock" }, {} },
    { {}, { reward = "draw 1" }, { terrain = "rock" }, { reward = "marketing" }, { terrain = "upgd" }, { terrain = "upgd" }, { terrain = "upgd" } },
    { { terrain = "rock" }, { terrain = "rock" }, {}, { reward = "draw 1" }, { terrain = "rock" }, { reward = "draw 1" } },
    { {}, {}, { reward = "free kiosk", special = "ice cream parlors" }, {}, { terrain = "rock" }, { reward = "free kiosk", special = "ice cream parlors" }, {} },
    { {}, {}, {}, {}, {}, {} },
    { { terrain = "water" }, { reward = "1 x_token" }, { terrain = "water" }, { reward = "clever 1" }, {}, { terrain = "water" }, { reward = "5 money" } },
    { { terrain = "water" }, { terrain = "water" }, { terrain = "water" }, {}, { reward = "1 x_token" }, { terrain = "water" } }
  }

  cnsts.map_data.map_8.cells = {
    { {}, {}, {}, { reward = "clever 1" }, { terrain = "rock" }, { terrain = "rock" } },
    { { terrain = "water" }, { reward = "1 x_token" }, { terrain = "water" }, {}, {}, { special = "hollywood hills" }, { terrain = "rock" } },
    { {}, {}, { terrain = "water" }, { terrain = "upgd" }, {}, { terrain = "rock" } },
    { { reward = "1 x_token" }, {}, {}, { terrain = "upgd" }, {}, { terrain = "upgd" }, { terrain = "rock" } },
    { {}, { terrain = "water" }, { reward = "1 x_token" }, {}, { terrain = "rock" }, { special = "hollywood hills" } },
    { {}, { terrain = "water" }, { terrain = "water" }, {}, {}, {}, { terrain = "rock" } },
    { { reward = "5 money" }, { terrain = "water" }, {}, {}, { special = "hollywood hills" }, { terrain = "rock" } },
    { {}, {}, { reward = "draw 1" }, {}, {}, { terrain = "rock" }, {} },
    { {}, {}, {}, {}, { reward = "1 rep" }, {} }
  }

  cnsts.map_data.map_9.cells = {
    { { reward = "marketing" }, { special = "geographical america" }, { special = "geographical america" }, { special = "geographical america" }, { terrain = "rock" }, { terrain = "rock" } },
    { { terrain = "rock" }, { terrain = "water" }, { special = "geographical america" }, { special = "geographical america" }, { reward = "draw 1" }, { special = "geographical africa" }, { terrain = "rock" } },
    { { reward = "5 money" }, { terrain = "water" }, { special = "geographical america" }, { terrain = "water" }, { special = "geographical africa" }, { special = "geographical africa" } },
    { { special = "geographical europe" }, { special = "geographical europe" }, {}, { reward = "draw 1" }, { special = "geographical africa" }, { special = "geographical africa" }, { special = "geographical africa" } },
    { { special = "geographical europe" }, { special = "geographical europe" }, { terrain = "water" }, { terrain = "upgd" }, { terrain = "water" }, { reward = "clever 1" } },
    { { special = "geographical europe" }, { special = "geographical europe" }, { reward = "draw 1" }, { terrain = "upgd" }, { special = "geographical australia" }, { special = "geographical australia" }, { special = "geographical australia" } },
    { { terrain = "rock" }, {}, { special = "geographical asia" }, { terrain = "water" }, { special = "geographical australia" }, { special = "geographical australia" } },
    { { terrain = "rock" }, { reward = "1 x_token" }, { special = "geographical asia" }, { special = "geographical asia" }, { reward = "1 x_token" }, { special = "geographical australia" }, { terrain = "rock" } },
    { { terrain = "rock" }, { special = "geographical asia" }, { special = "geographical asia" }, { special = "geographical asia" }, { terrain = "water" }, { terrain = "water" } }
  }

  cnsts.map_data.map_10.cells = {
    { { reward = "rescue" }, { terrain = "water" }, { terrain = "water" }, {}, {}, {} },
    { {}, {}, { terrain = "water" }, { reward = "1 x_token" }, {}, { reward = "1 x_token" }, { terrain = "rock" } },
    { {}, { reward = "draw 1" }, { terrain = "upgd" }, {}, {}, { terrain = "rock" } },
    { { terrain = "water" }, {}, {}, {}, {}, {}, { terrain = "rock" } },
    { { terrain = "water" }, {}, {}, { terrain = "rock" }, { terrain = "upgd" }, { reward = "rescue" } },
    { {}, { reward = "1 x_token" }, { terrain = "upgd" }, { terrain = "rock" }, { terrain = "water" }, {}, {} },
    { {}, {}, { reward = "draw 1" }, {}, {}, {} },
    { {}, {}, { terrain = "rock" }, { terrain = "water" }, { reward = "5 money" }, {}, {} },
    { { reward = "rescue" }, {}, { reward = "1 rep" }, { terrain = "water" }, { terrain = "water" }, { reward = "clever 1" } }
  }

  cnsts.map_data.map_11.cells = {
    { { terrain = "water" }, {}, { reward = "1 x_token" }, { terrain = "rock" }, { terrain = "water" }, {} },
    { {}, { reward = "draw 1" }, {}, {}, {}, { reward = "store" }, {} },
    { { terrain = "rock" }, { terrain = "upgd" }, { terrain = "rock" }, {}, {}, {} },
    { { terrain = "rock" }, { reward = "store" }, {}, {}, {}, {}, {} },
    { { terrain = "upgd" }, { reward = "extra shift" }, { terrain = "rock" }, {}, { reward = "draw 1" }, { terrain = "water" } },
    { { reward = "clever 1" }, { terrain = "rock" }, { terrain = "upgd" }, {}, {}, { terrain = "water" }, { terrain = "rock" } },
    { {}, { terrain = "rock" }, { reward = "1 x_token" }, { terrain = "water" }, {}, {} },
    { {}, { reward = "5 money" }, {}, {}, { reward = "store" }, { terrain = "water" }, { reward = "1 rep" } },
    { {}, {}, {}, {}, { terrain = "water" }, { terrain = "rock" } }
  }

  cnsts.map_data.map_12.cells = {
    { { reward = "1 rep" }, {}, { terrain = "rock" }, { terrain = "water" }, { terrain = "water" }, { special = "artificial intelligence" } },
    { {}, {}, { reward = "clever 1" }, { terrain = "water" }, { reward = "clever 1" }, {}, { terrain = "rock" } },
    { {}, {}, { terrain = "upgd" }, {}, {}, { reward = "1 x_token" } },
    { { terrain = "water" }, {}, {}, { reward = "draw 1" }, {}, { terrain = "rock" }, {} },
    { { reward = "5 money" }, {}, { terrain = "water" }, { terrain = "rock" }, {}, {} },
    { { terrain = "rock" }, {}, { terrain = "rock" }, { terrain = "rock" }, { terrain = "upgd" }, { reward = "1 x_token" }, { terrain = "water" } },
    { { terrain = "upgd" }, { reward = "mark" }, {}, {}, {}, { terrain = "rock" } },
    { { terrain = "rock" }, {}, {}, { terrain = "water" }, {}, { reward = "adapt 1" }, {} },
    { { special = "artificial intelligence" }, {}, {}, { reward = "draw 1" }, {}, {} }
  }

  cnsts.map_data.map_13.cells = {
    { { terrain = "rock" }, { special = "drawing board W" }, { special = "drawing board W" }, { special = "drawing board W" }, { special = "drawing board W" }, { terrain = "water" } },
    { { special = "drawing board N" }, { terrain = "rock" }, { special = "drawing board W", reward = "mark" }, { special = "drawing board W" }, { special = "drawing board W", reward = "mark" }, { terrain = "water" }, { special = "drawing board S", reward = "1 x_token" } },
    { { special = "drawing board N" }, { terrain = "rock" }, { special = "drawing board W" }, { special = "drawing board W" }, { terrain = "water" }, { special = "drawing board S" } },
    { { special = "drawing board N" }, { special = "drawing board N", reward = "2 money" }, { terrain = "rock" }, { special = "drawing board W", reward = "draw 1" }, { terrain = "water" }, { special = "drawing board S" }, { special = "drawing board S" } },
    { { special = "drawing board N" }, { special = "drawing board N" }, { startTile = 1, startTileTag = "size_2" }, { startTile = 1 }, { special = "drawing board S", reward = "1 x_token" }, { special = "drawing board S" } },
    { { special = "drawing board N" }, { special = "drawing board N", reward = "2 money" }, { terrain = "water" }, { special = "drawing board E", reward = "clever 1" }, { terrain = "rock" }, { special = "drawing board S" }, { special = "drawing board S" } },
    { { special = "drawing board N" }, { terrain = "water" }, { special = "drawing board E" }, { special = "drawing board E" }, { terrain = "rock" }, { special = "drawing board S" } },
    { { special = "drawing board N" }, { terrain = "water" }, { special = "drawing board E", reward = "1 appeal" }, { special = "drawing board E" }, { special = "drawing board E", reward = "1 appeal" }, { terrain = "rock" }, { special = "drawing board S", reward = "1 x_token" } },
    { { terrain = "water" }, { special = "drawing board E", terrain = "upgd" }, { special = "drawing board E" }, { special = "drawing board E" }, { special = "drawing board E", terrain = "upgd" }, { terrain = "rock" } }
  }

  cnsts.map_data.map_14.cells = {
    { {}, { terrain = "rock" }, {}, { reward = "draw 1" }, {}, {} },
    { {}, { reward = "1 rep" }, { terrain = "upgd" }, {}, { terrain = "rock" }, { reward = "1 x_token" }, {} },
    { {}, {}, {}, { reward = "1 x_token" }, { terrain = "water" }, {} },
    { { reward = "clever 1" }, { terrain = "water" }, { terrain = "rock" }, {}, { reward = "wave" }, {}, {} },
    { {}, {}, {}, {}, {}, {} },
    { {}, { reward = "draw 1" }, { terrain = "rock" }, {}, { terrain = "upgd" }, { terrain = "water" }, { reward = "5 money" } },
    { { terrain = "water" }, { terrain = "rock" }, { reward = "wave" }, {}, {}, { terrain = "upgd" } },
    { { terrain = "rock" }, { reward = "shark attack 1" }, {}, {}, {}, { reward = "shark attack 1" }, { terrain = "water" } },
    { { terrain = "water" }, { terrain = "water" }, { terrain = "rock" }, { reward = "wave" }, { terrain = "water" }, { terrain = "water" } }
  }

  cnsts.map_data.map_0.cells = {
    { { terrain = "water" }, { terrain = "water" }, {}, {}, { reward = "2 rep" }, { terrain = "rock" } },
    { { terrain = "water" }, { reward = "draw 1" }, {}, {}, {}, { terrain = "water" }, { terrain = "rock" } },
    { { terrain = "rock" }, {}, { reward = "draw 1" }, { terrain = "water" }, {}, {} },
    { { terrain = "water" }, { terrain = "rock" }, {}, {}, { reward = "1 x_token" }, {}, { reward = "draw 1" } },
    { { reward = "1 x_token" }, {}, { reward = "10 money" }, {}, {}, {} },
    { {}, {}, { terrain = "water" }, { reward = "clever 1" }, { terrain = "rock" }, { reward = "1 x_token" }, { terrain = "rock" } },
    { {}, { terrain = "rock" }, { terrain = "upgd" }, {}, { terrain = "rock" }, { terrain = "rock" } },
    { {}, { reward = "5 money" }, { terrain = "upgd" }, {}, {}, { reward = "2 rep" }, { terrain = "water" } },
    { {}, {}, {}, { reward = "5 money" }, { terrain = "water" }, { terrain = "water" } }
  }

  cnsts.map_data.map_A.cells = {
    { { reward = "2 rep" }, { reward = "1 x_token" }, {}, { startTile = 1, startTileTag = "kiosk" }, { startTile = 2, startTileTag = "size_3" }, { startTile = 2 } },
    { { terrain = "rock" }, { terrain = "rock" }, {}, {}, {}, { startTile = 2 }, { terrain = "rock" } },
    { { terrain = "water" }, { terrain = "rock" }, { reward = "draw 1" }, {}, { reward = "5 money" }, { terrain = "water" } },
    { { terrain = "rock" }, { reward = "5 money" }, {}, {}, {}, {}, { terrain = "water" } },
    { { terrain = "water" }, {}, {}, { reward = "1 x_token" }, {}, {} },
    { { reward = "1 x_token" }, {}, { terrain = "rock" }, { reward = "draw 1" }, { terrain = "water" }, { reward = "draw 1" }, {} },
    { {}, {}, {}, { terrain = "water" }, { terrain = "rock" }, {} },
    { { terrain = "water" }, { reward = "unlock worker" }, {}, {}, {}, { reward = "2 rep" }, { terrain = "upgd" } },
    { { terrain = "water" }, { terrain = "water" }, { reward = "10 money" }, {}, {}, { terrain = "upgd" } }
  }

  cnsts.map_data.map_T1.cells = {
    { { terrain = "rock" }, {}, {}, {}, { terrain = "rock" }, { terrain = "rock" } },
    { { terrain = "rock" }, { reward = "1 x_token" }, { terrain = "water" }, { reward = "draw 1" }, {}, { reward = "5 money" }, {} },
    { {}, {}, { terrain = "rock" }, { terrain = "upgd" }, {}, {} },
    { { reward = "1 x_token" }, {}, { reward = "scavenging 3" }, { terrain = "rock" }, {}, {}, {} },
    { {}, { terrain = "water" }, {}, { reward = "marketing" }, { terrain = "rock" }, { reward = "mark" } },
    { { terrain = "upgd" }, { terrain = "water" }, { terrain = "upgd" }, {}, {}, {}, {} },
    { {}, {}, { reward = "draw 1" }, {}, { reward = "clever 1" }, {} },
    { {}, { reward = "5 money" }, {}, { terrain = "water" }, {}, { terrain = "rock" }, { terrain = "water" } },
    { {}, { terrain = "water" }, { terrain = "water" }, {}, { reward = "draw 1" }, { terrain = "water" } }
  }

  cnsts.appeal_counters = {}
  cnsts.appeal_counters.White = "637e9c"
  cnsts.appeal_counters.Red = "9a34f5"
  cnsts.appeal_counters.Blue = "3e801e"
  cnsts.appeal_counters.Yellow = "16ac1f"

  cnsts.cp_counters = {}
  cnsts.cp_counters.White = "680569"
  cnsts.cp_counters.Red = "9ed109"
  cnsts.cp_counters.Blue = "77a2b1"
  cnsts.cp_counters.Yellow = "851e5e"

  cnsts.score_counters = {}
  cnsts.score_counters.White = "581f77"
  cnsts.score_counters.Red = "904d27"
  cnsts.score_counters.Blue = "2e0ee1"
  cnsts.score_counters.Yellow = "f8b9a4"

  cnsts.money_counters = {}
  cnsts.money_counters.White = "6a10c5"
  cnsts.money_counters.Red = "9fe0ef"
  cnsts.money_counters.Blue = "4130ad"
  cnsts.money_counters.Yellow = "26c666"

  cnsts.income_counters = {}
  cnsts.income_counters.White = "e89012"
  cnsts.income_counters.Red = "21688a"
  cnsts.income_counters.Blue = "105d15"
  cnsts.income_counters.Yellow = "c326e2"

  cnsts.rep_counters = {}
  cnsts.rep_counters.White = "aaf021"
  cnsts.rep_counters.Red = "bd2878"
  cnsts.rep_counters.Blue = "038bae"
  cnsts.rep_counters.Yellow = "d4b754"

  cnsts.furnitures = { "437cd7", "419bb1", "c67611", "64561b", "3e1196", "fc173f", "f2c4a6", "ce32be", "fc4ad8" }

  cnsts.counter_style = {
    money        = { color = { 1, 1, 1, 1 }, position = { 0, 0 },     font_size = 600 },
    appeal       = { color = { 0, 0, 0, 1 }, position = { 0.2, 0 } },
    cp           = { color = { 0, 0, 0, 1 }, position = { 0, 0 } },
    rep          = { color = { 1, 1, 1, 1 }, position = { 0, -0.2 },  font_size = 400 },
    income       = { color = { 0, 0, 0, 1 }, position = { 0, -0.35 } },
    score        = { color = { 1, 1, 1, 1 }, position = { 0, -0.15 }, font_size = 400 },
    icon         = { color = { 1, 1, 1, 1 }, position = { 0, 3.75 }, font_size = 600 },
    icon_terrain = { color = { 1, 1, 1, 1 }, position = { 0, 2.5 } }
  }

  cnsts.absolute_positions = {
    base_project = Vector(23.33, 0.76, 9.50),
    added_project = Vector(23.33, 0.76, 21.50),
    project_step = Vector(3.56, 0, 0),
    task_2_worker = Vector(24.51, 1.09, 13.19),
    task_3_worker = Vector(27.94, 1.09, 13.48),
    task_4_worker = Vector(32.60, 1.09, 13.48),
    task_5_worker = Vector(35.37, 1.09, 13.19),
    donation_12_cube = Vector(21.93, 1.32, 13.33),
    donation_12_dx = Vector(0.48, 0, 0),
    donation_12_dz = Vector(0, 0, 0.48),

    america_partner            = Vector(26.28, 1.14, 15.71),
    europe_partner             = Vector(27.84, 1.14, 16.46),
    asia_partner               = Vector(29.64, 1.14, 16.46),
    africa_partner             = Vector(27.83, 1.14, 14.81),
    australia_partner          = Vector(29.66, 1.14, 14.81),
    hand_size_university       = Vector(32.85, 1.14, 16.39),
    hand_size_university_mw    = Vector(31.66, 1.14, 16.04),
    double_rep_university      = Vector(33.59, 1.14, 14.73),
    double_research_university = Vector(31.66, 1.14, 14.73)
  }

  cnsts.card_relative_positions = {
  breeding_cube_1 = Vector(0.02, 0.25, 1.88),
  breeding_cube_2 = Vector(0.63, 0.25, 1.88),
  okapi_cube_1 = Vector(-0.38, 0.25, 1.34),
  okapi_cube_2 = Vector(0.32, 0.25, 1.34),
  okapi_cube_3 = Vector(1.02, 0.25, 1.34),
  waza_special_small = Vector(-0.43, 0.25, 1.37),
  waza_special_large = Vector(0.75, 0.25, 1.37),

  icon_proj = { Vector(-1.04, 0.25, -1.49),
                Vector(0.03, 0.25, -1.49),
                Vector(1.1, 0.25, -1.49) },
  breeding_proj = { Vector(-0.99, 0.25, -1.36),
                    Vector(0.18, 0.25, -1.36),
                    Vector(1.23, 0.25, -1.36) },
  release_proj = { Vector(-1.05, 0.25, -1.32),
                   Vector(-0.23, 0.25, -1.32),
                   Vector(0.61, 0.25, -1.32) },
  management_proj = { Vector(-1.12, 0.25, -1.13),
                      Vector(-0.3, 0.25, -1.13),
                      Vector(0.52, 0.25, -1.13) }

  }

cnsts.board_relative_positions = {
  project_bonus_1 = Vector(-8.43, 0.82, 3.59),
  project_bonus_z_step_same_color = Vector(0, 0, -0.96),
  project_bonus_z_step_diff_color = Vector(0, 0, -1.25),
  worker_1_home = Vector(6.13, 0.74, 1.61),
  worker_2_home = Vector(7.09, 0.74, 1.61),
  worker_3_home = Vector(8.15, 0.74, 1.61),
  worker_4_home = Vector(8.15, 0.74, 0.83),
  x_token_1_home = Vector(6.78, 0.64, 3.38),
  x_token_2_home = Vector(7.53, 0.64, 3.78),
  x_token_3_home = Vector(7.53, 0.64, 2.98),
  x_token_4_home = Vector(8.33, 0.64, 3.78),
  x_token_5_home = Vector(8.33, 0.64, 2.98),
  locked_worker_1 = Vector(8.16, 0.74, -3.58),
  locked_worker_z_step = Vector(0, 0, 1.29),
  partner_zoo_1 = Vector(4.28, 0.65, -2.99),
  partner_zoo_small_step = Vector(0, 0, 1.48),
  partner_zoo_big_step = Vector(0, 0, 1.97),
  university_1 = Vector(6.4, 0.65, -3.26),
  university_step = Vector(0, 0, 1.29),
  action_card_slot_1 = Vector(-7.23, -0.03, -7.52),
  action_card_step = Vector(3.6, 0, 0),
  geographical_america = Vector(-6.34, 0.82, -0.83),
  geographical_europe = Vector(-2.01, 0.82, 4.05),
  geographical_africa = Vector(-4.21, 0.82, -3.01),
  geographical_australia = Vector(0, 0.82, -3.01),
  geographical_asia = Vector(2.04, 0.82, -0.83),
  played_cards_col_1 = Vector(-7.23, -0.03, -12.87),
  played_cards_row_offset = Vector(0, 0.03, -1.3),
  played_cards_col_offset = Vector(3.6, 0, 0),
  ai_cube_1_pos = Vector(-7.23, 0.82, -4.4),
  ai_cube_x_step = Vector(3.6, 0, 0),
  bonus_tile_1 = Vector(6.41, 0.19, 5.86),
  bonus_tile_2 = Vector(7.93, 0.19, 5.86),
  bonus_tile_3 = Vector(9.45, 0.19, 5.86)
  }

  cnsts.rescue_params = {
    rotation = Vector(4.00, 180.00, 0.00),
    first_relative_pos = Vector(-5.79, 0.46, 2.98),
    step = Vector(3.74, 0, 0),
    capacity = 3
  }

  cnsts.store_params = {
    scale = Vector(0.37, 1.00, 0.37),
    rotation = Vector(0.00, 180.00, 173.00),
    first_relative_pos = Vector(8.93, 0.59, 3.81),
    step = Vector(0, 0, -1.16),
    capacity = 3,
    hand_index = 5,
    hand_zones = {
      ["8adb0d"] = "White",
      ["dbf36b"] = "Red",
      ["623c03"] = "Blue",
      ["9c72f4"] = "Yellow"
    }
  }

  cnsts.game_end_score = 100

  cnsts.map_setup_rows = {
    { default = false, keys = { "map_1", "map_2", "map_3", "map_4",
                                "map_5", "map_6", "map_7", "map_8" } },
    { default = true,  keys = { "map_1a", "map_2a", "map_3a", "map_4a",
                                "map_5a", "map_6a", "map_7a", "map_8a" } },
    { default = true,  keys = { "map_9", "map_10", "map_11", "map_12",
                                "map_13", "map_14", "map_T1" } },
  }

  cnsts.classic_map_tile = {
    thickness = 0.1,
    scale = { 4.5, 1, 4.5 }
  }

  cnsts.solo = {
    board_guid = "0f91b5",

    board_y = 0.79,
    board_z = -2.63,
    board_dx = 12,
    board_right_of = { White = true, Red = true },

    first_cube = Vector(-0.55, 0.82, 1.9),
    cube_step = Vector(0, 0, -0.65),
    cube_count = 7,

    cube_advance = 0.62,

    final_cubes = 2,

    pass_score = 100,

    difficulties = {
      { name = "Easy",   appeal = 20 },
      { name = "Medium", appeal = 10 },
      { name = "Hard",   appeal = 0 }
    }
  }

  cnsts.final_scoring_cards = {}

  cnsts.final_scoring_cards.base = {
    [1]  = { count = "large_animals",      bands = { {5,4}, {4,3}, {2,2}, {1,1} } },
    [2]  = { count = "small_animals",      bands = { {10,4}, {8,3}, {6,2}, {3,1} } },
    [3]  = { count = "research_icons",     bands = { {6,4}, {5,3}, {4,2}, {3,1} } },
    [4]  = { tests = { "water_connected", "rock_connected",
                       "border_covered", "map_covered" } },
    [5]  = { count = "projects_supported", offset = 2 },
    [6]  = { count = "unoccupied_cells",   bands = { {24,4}, {18,3}, {12,2}, {6,1} } },
    [7]  = { count = "reputation",         bands = { {15,4}, {12,3}, {9,2}, {6,1} } },
    [8]  = { count = "played_sponsors",    bands = { {10,4}, {8,3}, {6,2}, {3,1} } },
    [9]  = { compare = "species" },
    [10] = { count = "rock_icons",         bands = { {7,4}, {5,3}, {3,2}, {1,1} } },
    [11] = { count = "water_icons",        divisor = 2 }
  }

  cnsts.final_scoring_cards.mw = {
    [1]  = { count = "large_animals",      per = true },
    [3]  = { count = "research_icons",     bands = { {7,4}, {5,3}, {4,2}, {3,1} } },
    [5]  = { count = "projects_supported", offset = 1 },
    [8]  = { count = "played_sponsors",    bands = { {9,4}, {7,3}, {5,2}, {3,1} } },
    [10] = { count = "rock_icons",         bands = { {6,4}, {5,3}, {3,2}, {1,1} } },
    [11] = { count = "water_icons",        bands = { {7,4}, {6,3}, {4,2}, {2,1} } },
    [12] = { count = "distinct_tile_shapes", bands = { {8,4}, {7,3}, {6,2}, {4,1} } },
    [13] = { count = "best_unsupported_habitat", offset = 2 },
    [14] = { count = "best_unsupported_species", offset = 2 },
    [15] = { count = "kiosk_pavilion_pairs", offset = 1 },
    [16] = { count = "played_conditions",  bands = { {12,4}, {10,3}, {7,2}, {4,1} } },
    [17] = { compare = "habitat", with_partner_zoos = true }
  }

cnsts.ai_cube_steps = { 0, 1, 3, 4 }

cnsts.break_token = {
  zero_position = Vector(-9.81, 1.42, 18.04),
  first_step = Vector(1.67, 0, 0),
  step_size = Vector(0.98, 0, 0)
}

cnsts.icons = {}
cnsts.icons.all = { "africa", "america", "asia", "europe", "australia", "bird", "herbivore", "primate", "predator", "reptile", "sea", "bear", "petting", "research", "rock", "water" }
cnsts.icons.habitat = { "africa", "america", "asia", "europe", "australia" }
cnsts.icons.species = { "bird", "herbivore", "primate", "predator", "reptile", "sea", "bear", "petting" }

cnsts.icon_counters = {}
cnsts.icon_counters.White = {"024b26", "e1ebc3", "05fb53", "346b32", "424059", "4c35ef", "f9e735", "2f8f0c", "774ef8", "374eca", "0103aa", "3f6e57", "c58786", "9675e9", "8273db", "4108dd"}
cnsts.icon_counters.Red = {"47e8d9", "aa8a76", "6a2800", "0ac619", "78aeeb", "bec6ae", "47c5b6", "14c4d4", "ccec51", "b35f35", "c92fbb", "3e12b6", "8403cf", "8df146", "352b46", "310920"}
cnsts.icon_counters.Blue = {"cec9aa", "e8960c", "548f8a", "7bed0e", "b5e600", "554acc", "8311f0", "1544e1", "3a54d0", "88a5e3", "e3f6d8", "192a11", "b2f1fd", "76df02", "e4c0c1", "1f7c8d"}
cnsts.icon_counters.Yellow = {"e3bfd4", "fe8074", "d1a0ce", "221ae6", "7c815f", "9dc1f0", "f63277", "0d7e1a", "8066d3", "cac760", "25f869", "d1ddeb", "aff8f7", "d17224", "7c52fe", "cd403c"}

cnsts.cards = {}
cnsts.cards.base = {
  [101] = {type="project", project="icons", match="species", thresholds={5,4,3}, awards={5,3,2}},
  [102] = {type="project", project="icons", match="habitat", thresholds={5,4,3}, awards={5,3,2}},
  [103] = {type="project", project="icons", match="africa", thresholds={5,4,2}, awards={5,3,2}},
  [104] = {type="project", project="icons", match="america", thresholds={5,4,2}, awards={5,3,2}},
  [105] = {type="project", project="icons", match="australia", thresholds={5,4,2}, awards={5,4,2}},
  [106] = {type="project", project="icons", match="asia", thresholds={5,4,2}, awards={5,3,2}},
  [107] = {type="project", project="icons", match="europe", thresholds={5,4,2}, awards={5,4,2}},
  [108] = {type="project", project="icons", match="primate", thresholds={5,4,2}, awards={5,4,2}},
  [109] = {type="project", project="icons", match="reptile", thresholds={5,4,2}, awards={5,4,2}},
  [110] = {type="project", project="icons", match="predator", thresholds={5,4,2}, awards={5,4,2}},
  [111] = {type="project", project="icons", match="herbivore", thresholds={5,4,2}, awards={5,4,2}},
  [112] = {type="project", project="icons", match="bird", thresholds={5,4,2}, awards={5,4,2}},
  [113] = {type="project", rewards={"1 rep"}, project="release", match="europe"},
  [114] = {type="project", rewards={"1 rep"}, project="release", match="america"},
  [115] = {type="project", rewards={"1 rep"}, project="release", match="asia"},
  [116] = {type="project", rewards={"1 rep"}, project="release", match="africa"},
  [117] = {type="project", rewards={"1 rep"}, project="release", match="australia"},
  [118] = {type="project", rewards={"1 rep"}, project="release", match="predator"},
  [119] = {type="project", rewards={"1 rep"}, project="release", match="bird"},
  [120] = {type="project", rewards={"1 rep"}, project="release", match="herbivore"},
  [121] = {type="project", rewards={"1 rep"}, project="release", match="reptile"},
  [122] = {type="project", rewards={"1 rep"}, project="release", match="primate"},
  [123] = {type="project", project="breeding", match="bird"},
  [124] = {type="project", project="breeding", match="predator"},
  [125] = {type="project", project="breeding", match="reptile"},
  [126] = {type="project", project="breeding", match="herbivore"},
  [127] = {type="project", project="breeding", match="primate"},
  [128] = {type="project", project="icons", match="water", thresholds={5,4,2}, awards={4,3,2}},
  [129] = {type="project", project="icons", match="rock", thresholds={5,3,2}, awards={4,3,2}},
  [130] = {type="project", project="icons", match="small", thresholds={8,5,2}, awards={4,3,2}},
  [131] = {type="project", project="icons", match="large", thresholds={4,3,2}, awards={4,3,2}},
  [132] = {type="project", project="icons", match="research", thresholds={5,4,2}, awards={4,3,2}},
  [201] = {type="sponsor", level=5, icons={"research"}, conditions={"upgrade"}, rewards={"draw 1"}, income="draw 1", score={research={"", "", "1 cp", "1 cp", "1 cp", "2 cp"}}},
  [202] = {type="sponsor", level=5, icons={"research"}, conditions={"research"}, person=true, hook_self={research="1 rep"}},
  [203] = {type="sponsor", level=4, icons={"research"}, rewards={university={"2 money", "5 money", "10 money"}}, score={university_3="1 cp"}, effect="veterinarian", person=true},
  [204] = {type="sponsor", level=4, icons={"research"}, conditions={"research", "research", "research", "research"}, rewards={research=double("money")}, hook_self={research="1 cp"}},
  [205] = {type="sponsor", level=3, icons={"research"}, conditions={"research", "research", "research"}, rewards={"2 rep", "1 cp"}},
  [206] = {type="sponsor", level=5, icons={"research"}, conditions={"research", "research", "research", "research"}, rewards={projects_supported=double("appeal")}, income="1 cp"},
  [207] = {type="sponsor", level=4, icons={"research"}, conditions={"upgrade", "max 25 appeal"}, rewards={"basic research"}},
  [208] = {type="sponsor", level=4, icons={"research"}, rewards={research=single("appeal")}, hook_all={research="2 money"}, score={species_5="1 cp"}},
  [209] = {type="sponsor", level=5, icons={"research"}, rewards={"1 x_token"}, income="1 x_token", score={university_3="1 cp"}},
  [210] = {type="sponsor", level=4, icons={"america"}, rewards={america=single("appeal")}, hook_self={america="free kiosk"}, score={kiosks_5="1 cp"}, person=true},
  [211] = {type="sponsor", level=5, icons={"europe"}, rewards={europe=single("appeal")}, hook_self={europe="free size_1"}, score={size_1_flipped_5="1 cp"}, person=true},
  [212] = {type="sponsor", level=5, icons={"australia"}, rewards={australia=single("appeal")}, hook_self={australia="pouch 1"}, person=true},
  [213] = {type="sponsor", level=5, icons={"asia"}, rewards={asia=single("appeal")}, hook_self={asia="free pavilion"}, person=true},
  [214] = {type="sponsor", level=4, icons={"africa"}, rewards={africa=single("appeal")}, hook_self={africa="clever 1"}, score={x_token=single("appeal")}, person=true},
  [215] = {type="sponsor", level=4, conditions={"partner zoo", "partner zoo"}, effect="breeding cooperation", score={projects_supported_5="1 cp"}},
  [216] = {type="sponsor", level=5, conditions={"upgrade"}, rewards={"unlock worker"}, score={rep_9="1 cp"}, person=true},
  [217] = {type="sponsor", level=4, effect="engineer", score={map_covered="5 appeal"}, person=true},
  [218] = {type="sponsor", level=4, conditions={"research", "research"}, effect="breeding program", score={projects_supported_5="1 cp"}},
  [219] = {type="sponsor", level=5, icons={"research"}, conditions={"upgrade"}, rewards={"diversity researcher money"}, effect="diversity researcher", score={rock_water_pairs={"2 appeal", "4 appeal", "6 appeal"}}, person=true},
  [220] = {type="sponsor", level=4, icons={"research"}, rewards={"3 money"}, income="3 money", score={rep_9="1 cp"}},
  [221] = {type="sponsor", level=4, icons={"research"}, conditions={"research"}, effect="archaeologist", score={border_covered="1 cp"}, person=true},
  [222] = {type="sponsor", level=5, conditions={"max 25 appeal"}, rewards={"release of patents"}},
  [223] = {type="sponsor", level=3, icons={"research", "research"}},
  [224] = {type="sponsor", level=4, icons={"research"}, conditions={"research"}, rewards={"1 x_token"}, effect="migration recording"},
  [225] = {type="sponsor", level=3, icons={"research"}, rewards={"1 x_token"}, effect="quarantine lab", score={habitat_5="1 cp"}},
  [226] = {type="sponsor", level=6, icons={"research"}, rewards={"2 rep"}, score={habitat_5="1 cp"}},
  [227] = {type="sponsor", level=6, conditions={"6 rep"}, rewards={"waza special assignment"}, effect="waza special"},
  [228] = {type="sponsor", level=5, conditions={"3 rep"}, rewards={small_animals=double("money")}, effect="waza small animal program"},
  [229] = {type="sponsor", level=5, rewards={small_animals=single("appeal")}, effect="expert in small animals", person=true},
  [230] = {type="sponsor", level=4, rewards={large_animals=double("appeal")}, effect="expert in large animals", person=true},
  [231] = {type="sponsor", level=3, conditions={"primate"}, rewards={primate=single("appeal")}, income=function(p) return sponsorship(p, "primate") end},
  [232] = {type="sponsor", level=3, conditions={"reptile"}, rewards={reptile=single("appeal")}, income=function(p) return sponsorship(p, "reptile") end},
  [233] = {type="sponsor", level=3, conditions={"bird"}, rewards={bird=single("appeal")}, income=function(p) return sponsorship(p, "bird") end},
  [234] = {type="sponsor", level=3, conditions={"predator"}, rewards={predator=single("appeal")}, income=function(p) return sponsorship(p, "predator") end},
  [235] = {type="sponsor", level=3, conditions={"herbivore"}, rewards={herbivore=single("appeal")}, income=function(p) return sponsorship(p, "herbivore") end},
  [236] = {type="sponsor", level=4, icons={"primate"}, hook_all={primate="3 money"}, person=true},
  [237] = {type="sponsor", level=4, icons={"reptile"}, hook_all={reptile="3 money"}, person=true},
  [238] = {type="sponsor", level=4, icons={"bird"}, hook_all={bird="3 money"}, person=true},
  [239] = {type="sponsor", level=4, icons={"predator"}, hook_all={predator="3 money"}, person=true},
  [240] = {type="sponsor", level=4, icons={"herbivore"}, hook_all={herbivore="3 money"}, person=true},
  [241] = {type="sponsor", level=5, icons={"water"}, rewards={"hydrologist appeal"}, effect="hydrologist", score={water_connected="1 cp"}, person=true},
  [242] = {type="sponsor", level=5, icons={"rock"}, rewards={"geologist appeal"}, effect="geologist", score={rock_connected="1 cp"}, person=true},
  [243] = {type="sponsor", level=5, icons={"herbivore", "rock"}, conditions={"3 rep"}, building={}, hook_self={herbivore="2 appeal"}, score={herbivore_6="1 cp"}},
  [244] = {type="sponsor", level=5, icons={"bird", "water"}, conditions={"3 rep"}, building={}, hook_self={bird="2 appeal"}, score={bird_6="1 cp"}},
  [245] = {type="sponsor", level=5, icons={"water", "water"}, conditions={"3 rep"}, building={}, hook_self={water="2 appeal"}, score={water_6="1 cp"}},
  [246] = {type="sponsor", level=6, icons={"rock", "rock"}, building={}, hook_self={rock="2 appeal"}, score={rock_6="1 cp"}},
  [247] = {type="sponsor", level=6, icons={"primate", "rock"}, building={}, hook_self={primate="2 appeal"}, score={primate_6="1 cp"}},
  [248] = {type="sponsor", level=5, icons={"primate"}, building={}, hook_self={primate="1 x_token"}},
  [249] = {type="sponsor", level=6, icons={"bird"}, building={}, hook_self={bird="perception 2"}},
  [250] = {type="sponsor", level=5, icons={"reptile", "water"}, building={}, hook_self={reptile="sunbathing 2"}},
  [251] = {type="sponsor", level=5, icons={"bear", "predator", "water"}, building={}, hook_all={bear="2 appeal"}, score={bear={"", "", "1 cp", "1 cp", "1 cp", "2 cp"}}},
  [252] = {type="sponsor", level=5, icons={"predator", "rock"}, building={}, hook_self={predator="hunter 0"}},
  [253] = {type="sponsor", level=6, icons={"herbivore"}, building={}, effect="okapi stable", hook_self={herbivore="okapi stable marketing"}},
  [254] = {type="sponsor", level=5, building={min_border_cells=2}, rewards={"draw 1", "1 rep", "1 cp"}},
  [255] = {type="sponsor", level=3, icons={"rock"}, building={}, rewards={"4 appeal"}},
  [256] = {type="sponsor", level=3, icons={"water"}, building={}, rewards={"4 appeal"}},
  [257] = {type="sponsor", level=3, building={min_border_cells=2, ignore_touch_rule=true}, score={map_covered="5 appeal"}},
  [258] = {type="sponsor", level=5, icons={"bird"}, conditions={"max 25 appeal"}, rewards={"native seabirds"}, score={"native seabirds"}},
  [259] = {type="sponsor", level=5, icons={"reptile"}, conditions={"max 25 appeal"}, rewards={"native lizards"}, score={"native lizards"}},
  [260] = {type="sponsor", level=5, icons={"herbivore"}, conditions={"max 25 appeal"}, rewards={"native farm animals"}, score={"native farm animals"}},
  [261] = {type="sponsor", level=3, rewards={"1 cp", "1 appeal"}, score={species_5="1 cp"}},
  [262] = {type="sponsor", level=5, conditions={"upgrade"}, effect="explorer", rewards={"explorer money"}, person=true},
  [263] = {type="sponsor", level=5, conditions={"upgrade", "6 rep"}, effect="waza large animal program", rewards={"free size_5"}},
  [264] = {type="sponsor", level=5, icons={"primate"}, conditions={"max 25 appeal"}, rewards={"new world monkeys"}, score={"new world monkeys"}},
  [401] = {type="animal", size=5, cost=17, icons={"predator", "predator", "africa"}, rewards={"6 appeal", "sprint 3"}},
  [402] = {type="animal", size=4, cost=16, icons={"predator", "africa"}, conditions={"predator", "predator", "predator"}, rewards={"9 appeal", "pack"}},
  [403] = {type="animal", size=3, cost=20, icons={"predator", "africa", "rock"}, conditions={"africa partner"}, rewards={"1 cp", "7 appeal", "hunter 4"}},
  [404] = {type="animal", size=2, cost=9, icons={"predator", "africa"}, rewards={"4 appeal", "hunter 2"}},
  [405] = {type="animal", size=1, cost=8, icons={"predator", "africa"}, rewards={"3 appeal", "clever 1"}},
  [406] = {type="animal", size=5, cost=30, icons={"predator", "asia"}, conditions={"asia", "asia", "asia"}, rewards={"1 rep", "2 cp", "10 appeal"}},
  [407] = {type="animal", size=4, cost=26, icons={"predator", "asia", "water", "water"}, conditions={"research", "research"}, rewards={"1 rep", "2 cp", "8 appeal"}},
  [408] = {type="animal", size=3, cost=14, icons={"predator", "bear", "asia"}, rewards={"6 appeal", "boost association"}},
  [409] = {type="animal", size=2, cost=16, icons={"predator", "bear", "asia"}, conditions={"asia partner"}, rewards={"5 appeal", "action association"}},
  [410] = {type="animal", size=1, cost=7, icons={"predator", "asia"}, rewards={"3 appeal", "hunter 1"}},
  [411] = {type="animal", size=5, cost=22, icons={"predator", "bear", "america"}, conditions={"predator", "predator", "upgrade"}, rewards={"9 appeal", "inventive bear", "full throated"}},
  [412] = {type="animal", size=4, cost=16, icons={"predator", "america"}, conditions={"america"}, rewards={"8 appeal", "hunter 4"}},
  [413] = {type="animal", size=3, cost=10, icons={"predator", "america", "rock"}, rewards={"5 appeal", "jumping 3"}},
  [414] = {type="animal", size=2, cost=11, icons={"predator", "bear", "america", "rock"}, rewards={"4 appeal", "inventive 1"}},
  [415] = {type="animal", size=1, cost=11, icons={"predator", "bear", "america"}, rewards={"4 appeal", "boost association"}},
  [416] = {type="animal", size=5, cost=20, icons={"predator", "bear", "europe", "water"}, conditions={"bear", "upgrade"}, rewards={"8 appeal", "multiplier association", "full throated"}},
  [417] = {type="animal", size=4, cost=12, icons={"predator", "europe"}, rewards={"4 appeal", "pack"}},
  [418] = {type="animal", size=3, cost=11, icons={"predator", "europe"}, conditions={"europe", "europe"}, rewards={"2 appeal", "iconic europe"}},
  [419] = {type="animal", size=2, cost=5, icons={"predator", "europe"}, rewards={"3 appeal", "boost animals"}},
  [420] = {type="animal", size=1, cost=4, icons={"predator", "europe"}, conditions={"europe"}, rewards={"3 appeal", "hunter 1"}},
  [421] = {type="animal", size=5, cost=17, icons={"predator", "australia", "rock", "water"}, conditions={"upgrade"}, rewards={"8 appeal", "full throated"}},
  [422] = {type="animal", size=4, cost=18, icons={"predator", "australia", "water"}, conditions={"australia partner"}, rewards={"1 cp", "7 appeal", "sunbathing 3"}},
  [423] = {type="animal", size=3, cost=17, icons={"predator", "australia", "water"}, rewards={"6 appeal", "pack"}},
  [424] = {type="animal", size=2, cost=13, icons={"predator", "australia"}, rewards={"3 appeal", "pack"}},
  [425] = {type="animal", size=1, cost=11, icons={"predator", "australia"}, conditions={"research"}, rewards={"1 rep", "4 appeal", "pouch 1"}},
  [426] = {type="animal", size=5, cost=36, icons={"herbivore", "africa", "africa"}, conditions={"upgrade"}, rewards={"1 rep", "10 appeal", "resistance"}},
  [427] = {type="animal", size=4, cost=24, icons={"herbivore", "africa", "rock"}, conditions={"research"}, rewards={"9 appeal", "assertion"}},
  [428] = {type="animal", size=3, cost=16, icons={"herbivore", "africa"}, rewards={"7 appeal", "boost sponsors"}},
  [429] = {type="animal", size=2, cost=12, icons={"herbivore", "africa"}, conditions={"africa", "africa", "africa"}, rewards={"1 rep", "6 appeal", "boost sponsors"}, effect="flock 2"},
  [430] = {type="animal", size=2, cost=15, icons={"herbivore", "africa", "water"}, conditions={"africa partner"}, rewards={"6 appeal", "action sponsors"}},
  [431] = {type="animal", size=5, cost=33, icons={"herbivore", "asia", "asia", "water"}, conditions={"upgrade"}, rewards={"1 cp", "8 appeal", "resistance"}},
  [432] = {type="animal", size=4, cost=25, icons={"herbivore", "asia"}, conditions={"upgrade"}, rewards={"9 appeal", "assertion"}},
  [433] = {type="animal", size=3, cost=27, icons={"herbivore", "bear", "asia"}, conditions={"herbivore", "bear", "asia partner"}, rewards={"1 rep", "2 cp", "10 appeal"}},
  [434] = {type="animal", size=2, cost=16, icons={"herbivore", "bear", "asia"}, conditions={"research", "research"}, rewards={"6 appeal", "multiplier sponsors"}},
  [435] = {type="animal", size=2, cost=17, icons={"herbivore", "asia"}, rewards={"1 rep", "5 appeal", "digging 3"}},
  [436] = {type="animal", size=5, cost=18, icons={"herbivore", "america", "america"}, conditions={"america", "america", "america"}, rewards={"4 appeal", "iconic america"}},
  [437] = {type="animal", size=4, cost=13, icons={"herbivore", "america"}, conditions={"america"}, rewards={"5 appeal", "sponsor magnet"}},
  [438] = {type="animal", size=3, cost=12, icons={"herbivore", "america"}, rewards={"5 appeal"}, effect="flock 3"},
  [439] = {type="animal", size=2, cost=10, icons={"herbivore", "america"}, rewards={"4 appeal"}, effect="flock 2"},
  [440] = {type="animal", size=2, cost=15, icons={"herbivore", "america", "rock"}, rewards={"1 cp", "4 appeal", "digging 2"}},
  [441] = {type="animal", size=5, cost=19, icons={"herbivore", "europe", "europe"}, conditions={"europe partner"}, rewards={"6 appeal", "sponsor magnet"}},
  [442] = {type="animal", size=4, cost=19, icons={"herbivore", "europe"}, conditions={"herbivore", "herbivore"}, rewards={"7 appeal", "multiplier sponsors"}, effect="flock 4"},
  [443] = {type="animal", size=3, cost=12, icons={"herbivore", "europe"}, rewards={"5 appeal"}, effect="flock 3"},
  [444] = {type="animal", size=2, cost=10, icons={"herbivore", "europe", "rock", "rock"}, rewards={"5 appeal", "jumping 2"}},
  [445] = {type="animal", size=1, cost=8, icons={"herbivore", "europe"}, rewards={"3 appeal", "digging 2"}},
  [446] = {type="animal", size=5, cost=25, icons={"herbivore", "australia", "australia", "water", "water"}, conditions={"upgrade"}, rewards={"1 cp", "9 appeal", "digging 4"}},
  [447] = {type="animal", size=4, cost=23, icons={"herbivore", "australia"}, rewards={"7 appeal", "pouch 2"}, effect="flock 4"},
  [448] = {type="animal", size=3, cost=21, icons={"herbivore", "bear", "australia", "rock"}, conditions={"australia"}, rewards={"1 rep", "8 appeal", "pouch 2"}},
  [449] = {type="animal", size=2, cost=10, icons={"herbivore", "australia", "water"}, rewards={"4 appeal", "venom 1"}},
  [450] = {type="animal", size=2, cost=9, icons={"herbivore", "australia"}, rewards={"4 appeal", "pouch 1"}},
  [451] = {type="animal", size=5, cost=32, icons={"primate", "asia", "rock"}, conditions={"primate", "primate", "upgrade"}, rewards={"2 cp", "10 appeal", "dominance"}},
  [452] = {type="animal", size=1, cost=10, icons={"primate", "africa"}, conditions={"africa", "africa"}, rewards={"1 appeal", "iconic africa"}},
  [453] = {type="animal", size=4, cost=20, icons={"primate", "africa"}, conditions={"africa"}, rewards={"8 appeal", "action cards"}},
  [454] = {type="animal", size=3, cost=12, icons={"primate", "africa", "rock"}, rewards={"6 appeal", "sunbathing 3"}},
  [455] = {type="animal", size=3, cost=13, icons={"primate", "africa"}, rewards={"6 appeal", "clever 1"}},
  [456] = {type="animal", size=2, cost=13, icons={"primate", "africa"}, conditions={"africa partner"}, rewards={"6 appeal", "pilfering 1"}},
  [457] = {type="animal", size=5, cost=28, icons={"primate", "primate", "africa"}, conditions={"primate", "primate", "primate"}, rewards={"2 cp", "9 appeal", "multiplier cards"}},
  [458] = {type="animal", size=3, cost=18, icons={"primate", "asia", "water"}, conditions={"asia"}, rewards={"7 appeal", "pilfering 2"}},
  [459] = {type="animal", size=4, cost=17, icons={"primate", "asia"}, conditions={"research"}, rewards={"1 rep", "7 appeal", "inventive primate"}},
  [460] = {type="animal", size=2, cost=12, icons={"primate", "asia"}, rewards={"5 appeal", "clever 1"}},
  [461] = {type="animal", size=1, cost=14, icons={"primate", "asia"}, conditions={"asia partner"}, rewards={"2 rep", "3 appeal", "jumping 4"}},
  [462] = {type="animal", size=3, cost=13, icons={"primate", "asia", "rock"}, rewards={"6 appeal", "jumping 3"}},
  [463] = {type="animal", size=2, cost=11, icons={"primate", "america"}, conditions={"america partner"}, rewards={"5 appeal", "pilfering 1"}},
  [464] = {type="animal", size=4, cost=17, icons={"primate", "america"}, conditions={"primate"}, rewards={"1 cp", "6 appeal", "inventive primate"}},
  [465] = {type="animal", size=1, cost=10, icons={"primate", "america"}, rewards={"4 appeal", "clever 1"}},
  [466] = {type="animal", size=3, cost=12, icons={"primate", "america"}, rewards={"6 appeal", "boost cards"}},
  [467] = {type="animal", size=2, cost=12, icons={"primate", "america"}, rewards={"5 appeal", "clever 1"}},
  [468] = {type="animal", size=1, cost=15, icons={"primate", "america"}, conditions={"research", "research"}, rewards={"1 rep", "1 cp", "4 appeal"}},
  [469] = {type="animal", size=5, cost=13, icons={"reptile", "africa", "water"}, conditions={"reptile", "reptile", "reptile"}, enclosure={repthouse=3}, rewards={"9 appeal", "snap 2"}},
  [470] = {type="animal", size=2, cost=13, icons={"reptile", "africa"}, conditions={"reptile", "africa"}, enclosure={repthouse=1}, rewards={"6 appeal", "venom 2"}},
  [471] = {type="animal", size=3, cost=22, icons={"reptile", "africa"}, rewards={"1 cp", "6 appeal", "sunbathing 3"}},
  [472] = {type="animal", size=2, cost=12, icons={"reptile", "africa", "rock"}, enclosure={repthouse=1}, rewards={"5 appeal", "sunbathing 3"}},
  [473] = {type="animal", size=1, cost=9, icons={"reptile", "africa"}, enclosure={repthouse=0}, rewards={"3 appeal", "sunbathing 2"}},
  [474] = {type="animal", size=2, cost=14, icons={"reptile", "asia"}, conditions={"reptile", "reptile"}, enclosure={repthouse=1}, rewards={"7 appeal", "constriction"}},
  [475] = {type="animal", size=2, cost=13, icons={"reptile", "asia"}, conditions={"research", "research", "upgrade"}, enclosure={repthouse=1}, rewards={"6 appeal", "hypnosis 3"}},
  [476] = {type="animal", size=3, cost=14, icons={"reptile", "asia"}, conditions={"asia", "asia"}, enclosure={repthouse=2}, rewards={"2 appeal", "iconic asia"}},
  [477] = {type="animal", size=1, cost=14, icons={"reptile", "asia"}, enclosure={repthouse=0}, rewards={"4 appeal", "snap 1"}},
  [478] = {type="animal", size=1, cost=8, icons={"reptile", "asia", "water"}, enclosure={repthouse=0}, rewards={"3 appeal", "sunbathing 2"}},
  [479] = {type="animal", size=4, cost=18, icons={"reptile", "america", "water"}, enclosure={repthouse=2}, rewards={"7 appeal", "snap 1"}},
  [480] = {type="animal", size=4, cost=16, icons={"reptile", "america", "water"}, enclosure={repthouse=2}, rewards={"6 appeal", "snap 1"}},
  [481] = {type="animal", size=3, cost=30, icons={"reptile", "america"}, conditions={"america", "america", "upgrade"}, enclosure={repthouse=2}, rewards={"1 rep", "2 cp", "8 appeal", "sunbathing 4"}},
  [482] = {type="animal", size=2, cost=13, icons={"reptile", "america", "water"}, conditions={"america partner"}, enclosure={repthouse=1}, rewards={"6 appeal", "constriction"}},
  [483] = {type="animal", size=2, cost=16, icons={"reptile", "america"}, conditions={"research", "research"}, enclosure={repthouse=1}, rewards={"7 appeal", "constriction"}},
  [484] = {type="animal", size=1, cost=9, icons={"reptile", "europe", "water"}, enclosure={repthouse=1}, rewards={"4 appeal"}},
  [485] = {type="animal", size=1, cost=10, icons={"reptile", "europe"}, conditions={"europe partner"}, enclosure={repthouse=0}, rewards={"2 appeal", "hypnosis 3"}},
  [486] = {type="animal", size=1, cost=4, icons={"reptile", "europe", "rock"}, rewards={"2 appeal"}, enclosure={repthouse=0}},
  [487] = {type="animal", size=1, cost=8, icons={"reptile", "europe", "water"}, enclosure={repthouse=0}, rewards={"3 appeal", "clever 1"}},
  [488] = {type="animal", size=1, cost=4, icons={"reptile", "europe", "water"}, enclosure={repthouse=0}, rewards={"2 appeal"}},
  [489] = {type="animal", size=5, cost=23, icons={"reptile", "reptile", "australia", "water"}, conditions={"australia partner"}, enclosure={repthouse=3}, rewards={"9 appeal", "snap 2"}},
  [490] = {type="animal", size=3, cost=15, icons={"reptile", "australia"}, enclosure={repthouse=2}, rewards={"6 appeal", "scavenging 2"}},
  [491] = {type="animal", size=2, cost=12, icons={"reptile", "australia", "rock"}, enclosure={repthouse=1}, rewards={"5 appeal", "sprint 1"}},
  [492] = {type="animal", size=2, cost=10, icons={"reptile", "australia", "rock"}, conditions={"australia", "research"}, enclosure={repthouse=1}, rewards={"5 appeal", "venom 2"}},
  [493] = {type="animal", size=1, cost=6, icons={"reptile", "australia", "rock"}, enclosure={repthouse=0}, rewards={"3 appeal"}},
  [494] = {type="animal", size=5, cost=20, icons={"bird", "africa"}, enclosure={aviary=4}, rewards={"8 appeal", "sprint 2"}},
  [495] = {type="animal", size=4, cost=14, icons={"bird", "africa"}, enclosure={aviary=1}, rewards={"1 cp", "4 appeal"}},
  [496] = {type="animal", size=3, cost=10, icons={"bird", "africa"}, enclosure={aviary=1}, rewards={"4 appeal", "scavenging 2"}},
  [497] = {type="animal", size=2, cost=15, icons={"bird", "africa", "water"}, rewards={"6 appeal", "posturing 1"}},
  [498] = {type="animal", size=1, cost=9, icons={"bird", "africa"}, conditions={"research", "research"}, enclosure={aviary=1}, rewards={"1 cp", "3 appeal"}},
  [499] = {type="animal", size=5, cost=6, icons={"bird", "asia"}, enclosure={aviary=1}, rewards={"6 appeal", "scavenging 3"}},
  [500] = {type="animal", size=4, cost=20, icons={"bird", "asia", "rock"}, conditions={"research"}, enclosure={aviary=1}, rewards={"1 rep", "1 cp", "5 appeal", "scavenging 3"}},
  [501] = {type="animal", size=3, cost=18, icons={"bird", "asia"}, conditions={"asia"}, rewards={"7 appeal", "posturing 2"}},
  [502] = {type="animal", size=2, cost=13, icons={"bird", "asia"}, rewards={"6 appeal", "boost build"}},
  [503] = {type="animal", size=1, cost=11, icons={"bird", "asia"}, conditions={"bird", "bird"}, rewards={"1 rep", "4 appeal", "perception 4"}},
  [504] = {type="animal", size=5, cost=17, icons={"bird", "america", "rock"}, conditions={"bird"}, enclosure={aviary=1}, rewards={"1 rep", "7 appeal", "scavenging 4"}},
  [505] = {type="animal", size=4, cost=23, icons={"bird", "america", "water"}, conditions={"upgrade"}, enclosure={aviary=1}, rewards={"8 appeal", "determination"}},
  [506] = {type="animal", size=3, cost=12, icons={"bird", "america"}, conditions={"bird", "bird", "bird"}, enclosure={aviary=1}, rewards={"9 appeal", "scavenging 5"}},
  [507] = {type="animal", size=2, cost=12, icons={"bird", "america"}, rewards={"5 appeal", "sprint 1"}},
  [508] = {type="animal", size=1, cost=16, icons={"bird", "america"}, conditions={"america partner"}, rewards={"4 appeal", "posturing 3"}},
  [509] = {type="animal", size=5, cost=20, icons={"bird", "europe", "rock"}, conditions={"upgrade"}, enclosure={aviary=1}, rewards={"7 appeal", "determination"}},
  [510] = {type="animal", size=4, cost=9, icons={"bird", "europe"}, conditions={"europe"}, enclosure={aviary=1}, rewards={"4 appeal", "multiplier build"}},
  [511] = {type="animal", size=3, cost=16, icons={"bird", "europe", "water"}, rewards={"7 appeal", "posturing 1"}},
  [512] = {type="animal", size=2, cost=10, icons={"bird", "europe"}, conditions={"europe partner"}, rewards={"4 appeal", "perception 4"}},
  [513] = {type="animal", size=1, cost=12, icons={"bird", "europe"}, rewards={"3 appeal", "perception 4"}},
  [514] = {type="animal", size=5, cost=22, icons={"bird", "australia"}, conditions={"australia", "australia"}, rewards={"7 appeal", "peacocking"}},
  [515] = {type="animal", size=4, cost=13, icons={"bird", "australia", "water", "water"}, rewards={"5 appeal", "action build"}},
  [516] = {type="animal", size=3, cost=12, icons={"bird", "australia"}, conditions={"australia partner"}, rewards={"6 appeal", "multiplier build"}},
  [517] = {type="animal", size=2, cost=9, icons={"bird", "australia"}, conditions={"australia"}, rewards={"iconic australia"}},
  [518] = {type="animal", size=1, cost=15, icons={"bird", "australia"}, rewards={"5 appeal", "posturing 1"}},
  [519] = {type="animal", size=0, cost=7, icons={"petting"}, rewards={petting=triple("appeal")}},
  [520] = {type="animal", size=0, cost=7, icons={"petting"}, rewards={petting=triple("appeal")}},
  [521] = {type="animal", size=0, cost=7, icons={"petting"}, rewards={petting=triple("appeal"), "1 rep"}},
  [522] = {type="animal", size=0, cost=7, icons={"petting"}, rewards={petting=triple("appeal"), "inventive 1"}},
  [523] = {type="animal", size=0, cost=7, icons={"petting"}, rewards={petting=triple("appeal")}},
  [524] = {type="animal", size=0, cost=7, icons={"petting"}, rewards={petting=triple("appeal"), "digging 1"}},
  [525] = {type="animal", size=0, cost=7, icons={"petting"}, rewards={petting=triple("appeal")}},
  [526] = {type="animal", size=0, cost=7, icons={"petting"}, rewards={petting=triple("appeal")}},
  [527] = {type="animal", size=0, cost=7, icons={"petting"}, rewards={petting=triple("appeal")}},
  [528] = {type="animal", size=0, cost=7, icons={"petting"}, rewards={petting=triple("appeal"), "pouch 1"}},
}

cnsts.cards.mw = {
  [131] = {type="project", project="icons", match="large", thresholds={3,2,1}, awards={4,3,2}},
  [133] = {type="project", project="icons", match="sea", thresholds={5,4,2}, awards={5,4,2}},
  [134] = {type="project", project="management", match="predator", rewards={"hunter 0"}, first_award="hunter 0"},
  [135] = {type="project", project="management", match="bird", rewards={"posturing 1"}, first_award="posturing 1"},
  [136] = {type="project", project="management", match="reptile", rewards={"sunbathing 2"}, first_award="sunbathing 2"},
  [137] = {type="project", project="management", match="herbivore", rewards={"digging 2"}, first_award="digging 2"},
  [138] = {type="project", project="management", match="sea", rewards={"1 rep"}, first_award="reef effect"},
  [139] = {type="project", project="management", match="primate", rewards={"clever 1"}, first_award="clever 1"},
  [250] = {type="sponsor", level=5, icons={"reptile", "sea", "water", "water"}, building={}, hook_self={reptile="sunbathing 2"}},
  [265] = {type="sponsor", level=4, conditions={"kiosk"}, rewards={"free kiosk"}, score={kiosks_5="1 cp"}, effect="franchise business"},
  [266] = {type="sponsor", level=4, icons={"sea"}, hook_all={sea="3 money"}, person=true, wave=true},
  [267] = {type="sponsor", level=5, icons={"predator"}, rewards={"farm cat"}, score={"farm cat"}},
  [268] = {type="sponsor", level=5, icons={"europe"}, rewards={europe={"2 money", "2 money", "5 money", "5 money", "10 money"}}, score={donation_3="1 cp"}, hook_self={europe="mark"}},
  [269] = {type="sponsor", level=5, icons={"australia"}, hook_self={australia="expand enclosure"}, score={"conference on australia"}},
  [270] = {type="sponsor", level=5, icons={"research", "sea"}, hook_self={sea="marine research expedition"}, wave=true},
  [271] = {type="sponsor", level=5, icons={"research"}, building={double_placement_bonus=true}, score={placement_covered="1 cp"}},
  [272] = {type="sponsor", level=5, conditions={"upgrade"}, effect="expansion area", rewards={"free size_3"}, score={border_covered="1 cp"}},
  [273] = {type="sponsor", level=4, icons={"research"}, conditions={"research"}, effect="publications", rewards={"donate"}},
  [274] = {type="sponsor", level=3, building={}, rewards={"1 appeal"}, income="1 appeal", score={"mascot statue"}},
  [275] = {type="sponsor", level=3, icons={"petting"}, conditions={"6 rep"}, hook_all={petting="2 money"}, rewards={"horse whisperer"}, person=true},
  [276] = {type="sponsor", level=6, rewards={"free pavilion", pavilion=single("appeal")}, effect="landscape gardener", person=true},
  [277] = {type="sponsor", level=3, icons={"research"}, conditions={"research", "research", "sea"}, rewards={"3 rep"}, wave=true},
  [278] = {type="sponsor", level=6, icons={"sea", "herbivore", "primate", "water", "rock"}, conditions={"upgrade", "america", "6 rep"}, building={}, rewards={"1 rep", "2 cp", "4 appeal"}},
  [279] = {type="sponsor", level=4, conditions={"upgrade"}, building={water_cells_only=true}, rewards={"2 appeal"}, score={"underwater tunnel"}, wave=true},
  [280] = {type="sponsor", level=3, effect="reconstruction", rewards={"reconstruction"}, score={map_covered="5 appeal"}},
  [529] = {type="animal", size=1, cost=6, icons={"sea", "australia"}, no_std_enc=true, enclosure={aquarium=1}, rewards={"3 appeal"}, reef="mark", wave=true},
  [530] = {type="animal", size=1, cost=10, icons={"sea", "australia"}, no_std_enc=true, enclosure={aquarium=1}, rewards={"3 appeal"}, reef="2 appeal", wave=true},
  [531] = {type="animal", size=1, cost=9, icons={"sea", "asia"}, no_std_enc=true, enclosure={aquarium=1}, rewards={"4 appeal"}, reef="trade", wave=true},
  [532] = {type="animal", size=1, cost=4, icons={"sea"}, no_std_enc=true, enclosure={aquarium=0}, rewards={"1 appeal", "sea animal magnet"}, wave=true},
  [533] = {type="animal", size=2, cost=11, icons={"sea", "australia"}, no_std_enc=true, enclosure={aquarium=1}, rewards={"4 appeal"}, reef="posturing 1", wave=true},
  [534] = {type="animal", size=2, cost=12, icons={"sea", "australia"}, no_std_enc=true, enclosure={aquarium=1}, rewards={"4 appeal", "venom 1"}, reef="3 money", wave=true},
  [535] = {type="animal", size=1, cost=7, icons={"sea", "america"}, no_std_enc=true, enclosure={aquarium=1}, rewards={"2 appeal", "symbiosis"}, reef="", wave=true},
  [536] = {type="animal", size=2, cost=9, icons={"sea", "africa"}, no_std_enc=true, enclosure={aquarium=1}, rewards={"4 appeal"}, reef="boost sponsors", wave=true},
  [537] = {type="animal", size=2, cost=14, icons={"sea", "africa"}, conditions={"university"}, no_std_enc=true, enclosure={aquarium=1}, rewards={"5 appeal", "constriction"}, reef="draw 1", wave=true},
  [538] = {type="animal", size=2, cost=16, icons={"sea", "asia"}, conditions={"research"}, no_std_enc=true, enclosure={aquarium=1}, rewards={"6 appeal", "venom 1"}, reef="1 x_token", wave=true},
  [539] = {type="animal", size=1, cost=12, icons={"sea", "america"}, no_std_enc=true, enclosure={aquarium=1}, rewards={"5 appeal"}, reef="clever 1", wave=true},
  [540] = {type="animal", size=2, cost=15, icons={"sea", "asia"}, no_std_enc=true, enclosure={aquarium=2}, rewards={"5 appeal", "venom 1"}, reef="1 rep", wave=true},
  [541] = {type="animal", size=2, cost=16, icons={"sea", "asia"}, no_std_enc=true, enclosure={aquarium=1}, rewards={"7 appeal"}, reef="digging 1", wave=true},
  [542] = {type="animal", size=3, cost=22, icons={"sea", "africa"}, conditions={"university"}, no_std_enc=true, enclosure={aquarium=2}, rewards={"1 cp", "6 appeal"}, reef="extra shift", wave=true},
  [543] = {type="animal", size=5, cost=23, icons={"sea", "asia"}, conditions={"upgrade"}, no_std_enc=true, enclosure={aquarium=4}, rewards={"1 rep", "8 appeal", "glide 3"}, reef="1 cp", wave=true},
  [544] = {type="animal", size=4, cost=20, icons={"sea", "predator", "america"}, no_std_enc=true, enclosure={aquarium=3}, rewards={"1 rep", "5 appeal"}, reef="shark attack 1", wave=true},
  [545] = {type="animal", size=4, cost=21, icons={"sea", "sea", "africa"}, conditions={"sea"}, no_std_enc=true, enclosure={aquarium=3}, rewards={"1 cp", "9 appeal", "cut down"}, wave=true},
  [546] = {type="animal", size=5, cost=32, icons={"sea", "predator", "australia", "rock"}, conditions={"upgrade"}, no_std_enc=true, enclosure={aquarium=4}, rewards={"1 cp", "8 appeal", "shark attack 2"}, wave=true},
  [547] = {type="animal", size=1, cost=8, icons={"sea", "europe", "rock"}, no_std_enc=true, enclosure={aquarium=0}, rewards={"3 appeal", "symbiosis"}, wave=true},
  [548] = {type="animal", size=1, cost=7, icons={"sea", "europe", "rock"}, no_std_enc=true, enclosure={aquarium=1}, rewards={"2 appeal", "pouch 1", "camouflage"}, wave=true},
  [549] = {type="animal", size=3, cost=9, icons={"sea", "europe", "rock"}, conditions={"research"}, no_std_enc=true, enclosure={aquarium=2}, rewards={"5 appeal", "camouflage"}, wave=true},
  [550] = {type="animal", size=3, cost=10, icons={"sea", "europe"}, conditions={"3 rep"}, no_std_enc=true, enclosure={aquarium=2}, rewards={"6 appeal", "glide 2"}, wave=true},
  [551] = {type="animal", size=4, cost=23, icons={"sea", "reptile", "europe"}, no_std_enc=true, enclosure={aquarium=3, repthouse=3}, rewards={"8 appeal", "scuba dive 0", "marketing"}, wave=true},
  [552] = {type="animal", size=3, cost=17, icons={"sea", "reptile", "america"}, no_std_enc=true, enclosure={aquarium=2, repthouse=2}, rewards={"6 appeal", "scuba dive 0"}, wave=true},
  [553] = {type="animal", size=1, cost=15, icons={"sea", "herbivore", "america"}, no_std_enc=true, enclosure={aquarium=1}, rewards={"5 appeal", "adapt 1"}, wave=true},
  [554] = {type="animal", size=3, cost=18, icons={"sea", "bird", "africa", "rock", "water"}, conditions={"upgrade"}, enclosure={aquarium=2}, rewards={"1 rep", "6 appeal", "adapt 2"}, wave=true},
  [555] = {type="animal", size=3, cost=18, icons={"primate", "asia", "rock"}, conditions={"research"}, rewards={"1 cp", "6 appeal", "pilfering 1"}},
  [556] = {type="animal", size=3, cost=15, icons={"predator", "bear", "europe", "rock"}, rewards={"1 rep", "5 appeal", "boost association"}},
  [557] = {type="animal", size=0, cost=7, icons={"petting"}, rewards={petting=triple("appeal")}},
  [558] = {type="animal", size=4, cost=16, icons={"primate", "america", "rock"}, conditions={"university"}, rewards={"1 cp", "6 appeal", "monkey gang"}},
  [559] = {type="animal", size=3, cost=17, icons={"primate", "africa", "rock"}, rewards={"7 appeal", "monkey gang", "jumping 2"}},
  [560] = {type="animal", size=3, cost=12, icons={"bird", "australia", "rock", "water"}, rewards={"6 appeal", "hunter 2"}},
}


  cnsts.action_strengths = {
    [0] = { 1, 2, 3, 4, 5 },
    [1] = { 2, 2, 3, 4, 5 },
    [2] = { 3, 3, 3, 4, 5 },
    [3] = { 3, 3, 3, 5, 5 },
    [4] = { 3, 3, 3, 6, 6 },
  }

  cnsts.rehousing_enclosures = {
    reptile_house     = "repthouse",
    large_bird_aviary = "aviary",
    small_aquarium    = "aquarium",
    large_aquarium    = "aquarium",
    underwater_tunnel = "aquarium",
  }

  cnsts.special_enclosure_order = { "repthouse", "aviary", "aquarium" }

  cnsts.special_enclosure_labels = {
    repthouse = "Reptile House",
    aviary    = "Large Bird Aviary",
    aquarium  = "Aquarium",
  }

  cnsts.animal_enclosure_types = {
    aviary    = { "large_bird_aviary" },
    repthouse = { "reptile_house" },
    aquarium  = { "large_aquarium", "small_aquarium", "underwater_tunnel" },
  }

  cnsts.building_icons = {
    small_aquarium = { "water" },
    large_aquarium = { "water" },
  }

  cnsts.build_extra_rewards = {
    { key = "build_1_effect",   text = "Build a Pavilion (3 money)", search_name = "PAVILION", price = 3 },
    { key = "build_1up_effect", text = "Build a Pavilion (2 money)", search_name = "PAVILION", price = 2 },
    { key = "build_2_effect",   text = "Build a Kiosk (3 money)",    search_name = "KIOSK",    price = 3 },
    { key = "build_2up_effect", text = "Build a Kiosk (2 money)",    search_name = "KIOSK",    price = 2 },
  }

  cnsts.worker_rotation = { 270, 180, 0 }

  cnsts.drop_height = 0.25

  cnsts.reconstruction_max_tiles = 3

  cnsts.reconstruction_drop_cell = 30

  cnsts.map_filled_appeal = 7

  cnsts.incremental_effects = {
    ["ice cream parlors"] = { attr_name = "map_ice_cream_parlors", cap = 3 },
    ["hollywood hills"] = { attr_name = "map_hollywood_hills", cap = 3,
                            reward = "sponsor search",
                            blocked_by_reconstruction = true },
    ["drawing board N"] = { attr_name = "drawing_board_n", cap = 10,
                            reward = "3 money", on_cap = true, income = true },
    ["drawing board E"] = { attr_name = "drawing_board_e", cap = 10,
                            reward = "2 appeal", on_cap = true, income = true },
    ["drawing board S"] = { attr_name = "drawing_board_s", cap = 10,
                            reward = "1 rep", on_cap = true, income = true },
    ["drawing board W"] = { attr_name = "drawing_board_w", cap = 10,
                            reward = "hunter 4", on_cap = true, income = true },
  }

  cnsts.remapped_effects = { ["research institute"] = "research_institute_effect" }

  cnsts.board_read_specials = {
    ["observation tower"] = true,
    ["park restaurant"] = true,
    ["outdoor areas"] = true,
  }
  for _, habitat in ipairs(cnsts.icons.habitat) do
    cnsts.board_read_specials["geographical " .. habitat] = true
  end

  cnsts.discard_drop_height = 3

  cnsts.action_card_tokens = {
    multiplier   = { name = "Multiplier Token",   z = 1.7 },
    venom        = { name = "Venom Token",        z = 0.85 },
    constriction = { name = "Constriction Token", z = 0 },
  }

  cnsts.multiplier_token_spread = 0.8

  cnsts.action_flip_attributes = {
    AN = "animals_flipped",
    BU = "build_flipped",
    CA = "cards_flipped",
    SP = "sponsors_flipped",
    AS = "association_flipped",
  }

  cnsts.worker_ordinals = { [2] = "second", [3] = "third", [4] = "last" }

  cnsts.commercial_harbor_sell_value = 3

  cnsts.sponsor_3_discard_value = 4

  cnsts.counted_map_attributes = {
    map_ice_cream_parlors = true,
    map_hollywood_hills = true
  }

  cnsts.listed_map_attributes = {
    map_rescue_station = true,
    map_caves = true,
    map_artificial_intelligence = true
  }

  cnsts.reward_prefixes = { "BONUS: ", "TOKEN: " }

  cnsts.starting_hand_size = 8

  cnsts.sunbathing_sell_value = 4

  cnsts.waiting_to_discard = "Waiting for other players to discard..."

  cnsts.winner_panel_delay = 2

  cnsts.appeal_income_thresholds = {
    { 0, 5 }, { 1, 6 }, { 2, 7 }, { 3, 8 }, { 4, 9 },
    { 6, 10 }, { 8, 11 }, { 10, 12 }, { 12, 13 }, { 14, 14 }, { 16, 15 },
    { 19, 16 }, { 22, 17 }, { 25, 18 }, { 28, 19 }, { 31, 20 },
    { 35, 21 }, { 39, 22 }, { 43, 23 }, { 47, 24 }, { 51, 25 }, { 55, 26 },
    { 60, 27 }, { 65, 28 }, { 70, 29 }, { 75, 30 }, { 80, 31 }, { 85, 32 }, { 90, 33 }, { 95, 34 },
    { 101, 35 }, { 107, 36 }, { 113, 37 }
  }

  cnsts.cell_offsets = { x0 = -5.8288, cx = 0.9272, z0 = 3.7025, vz = -0.5354, y = 0.6 }


  cnsts.break_token_guid             = "bbf4bd"
  cnsts.map_bag_guid                 = "4b756c"
  cnsts.generic_university_tile_guid = "cff2ff"
  cnsts.association_board_guid       = "c67611"
  cnsts.zoo_deck_guid                = "7a8eac"
  cnsts.base_conservation_deck_guid  = "e5acec"
  cnsts.final_scoring_deck_guid      = "ab2a58"


  cnsts.zone_guids = {
    america_partner            = "e1b9ee",
    europe_partner             = "9421b9",
    asia_partner               = "9ca997",
    africa_partner             = "040899",
    australia_partner          = "328fd5",
    hand_size_university       = "cc0ed7",
    hand_size_university_mw    = "445db6",
    double_rep_university      = "b99a06",
    double_research_university = "6024b9",
    generic_university         = "da3b77",
    donation_2                 = "855414",
    donation_5_1               = "c6e45f",
    donation_5_2               = "458f71",
    donation_7_1               = "17c997",
    donation_7_2               = "fe085a",
    donation_10_1              = "0e8d7e",
    donation_10_2              = "6640b7",
    donation_12                = "a43f42",
  }

  cnsts.bag_guids = {
    america_partner            = "543835",
    europe_partner             = "a358fe",
    asia_partner               = "df4d52",
    africa_partner             = "724e58",
    australia_partner          = "20f52e",
    hand_size_university       = "4fb7f2",
    double_rep_university      = "d815d4",
    double_research_university = "34104f",
    build_buildings            = "8fbe2f",
    sponsor_buildings          = "f88130",
    tokens                     = "0133f5",
    cubes                      = "cb9c17",
  }

  cnsts.expected_bag_contents = {
    america_partner            = { count = 4 },
    europe_partner             = { count = 4 },
    asia_partner               = { count = 4 },
    africa_partner             = { count = 4 },
    australia_partner          = { count = 4 },
    hand_size_university       = { count = 4 },
    double_rep_university      = { count = 4 },
    double_research_university = { count = 4 },
    tokens = { names = {
      "Association Worker", "X-token", "Constriction Token", "Venom Token",
      "Multiplier Token",
    } },
    build_buildings   = { names = cnsts.build_buildings },
    sponsor_buildings = { names = cnsts.sponsor_buildings },
  }

  cnsts.button_guids = {
    setup_game = "a081ad",
  }

  cnsts.setup_options = {
    { key = "marine_worlds",
      prompt = "Marine Worlds Expansion:",
      global = "marine_worlds_enabled",
      states = { { label = "Disabled", value = false },
                 { label = "Enabled",  value = true } } },

    { key = "discard_facing",
      prompt = "Discard Pile:",
      global = "discard_face_down",
      states = { { label = "Face Down", value = true },
                 { label = "Face Up",   value = false } } },

    { key = "play_order",
      prompt = "Play Order:",
      global = "left_to_right_order",
      states = { { label = "Left-to-Right", value = true },
                 { label = "Right-to-Left", value = false } } },

    { key = "interactive_effects",
      prompt = "Interactive Effects (Pilfering, etc.):",
      global = "interactive_effects",
      solo_state = 2,
      states = { { label = "Enabled",  value = true },
                 { label = "Disabled", value = false } } },
  }

  cnsts.non_interactive_rewards = {
    pilfering    = { head = "sprint",        count = "keep" },
    hypnosis     = { head = "determination", count = "drop" },
    venom        = { head = "inventive",     count = "keep" },
    constriction = { head = "clever",        count = "one" },
  }


  cnsts.association_board_images = {
    base          = "https://steamusercontent-a.akamaihd.net/ugc/1750203778410077352/64ACCDB916282C9CC501D09FCC01CD6E5CF83EB7/",
    marine_worlds = "https://steamusercontent-a.akamaihd.net/ugc/10677451784626482415/9C40EC96CEFD48E4A9E3306C435BD0136C574741/",
  }



  cnsts.placeholder_card_script = [[
function onPickUp(player_color)
  self.drop()
  self.setPosition(Global.getVar("placeholder_position"))
  Global.call("on_placeholder_card_picked_up", { color = player_color })
end
]]

  cnsts.building_tile_script = [[
function onDrop(player_color)
  Wait.condition(function()
    Global.call("on_building_tile_settled", { tile = self, color = player_color })
  end, function() return self.resting end)
end

function onPickUp(player_color)
  Global.call("on_building_tile_picked_up", { tile = self, color = player_color })
end
]]

  cnsts.rewind_heartbeat_seconds = 50

  cnsts.rewind_spacer_seconds = 8

  cnsts.rewind_junk_prefix = "in-turn:"


  cnsts.saved_globals = {
    "game_started", "marine_worlds_enabled", "discard_face_down",
    "left_to_right_order", "interactive_effects",
    "solo_turn_cubes", "solo_cubes_advanced",
    "final_scoring_discard_triggered",
    "game_end_triggered", "pouch_slot_count", "break_init_val",
    "break_current_val", "assocBoard", "draft_round", "map_ready",
    "income_phase_index", "break_phase_resume", "player_status",
    "base_projects", "added_projects", "placeholder_position",
    "checkpoint_resume", "all_zoo_hooks"
  }

  cnsts.saved_global_slot_lists = {
    display_cards = { length = #cnsts.display_locs, objects = true },
    display_marks = { length = #cnsts.display_locs, objects = false },
    cp_bonuses_5 = { length = 2, objects = true },
    cp_bonuses_8 = { length = 2, objects = true }
  }
  cnsts.saved_player_slot_lists = {
    project_cubes = { length = cnsts.project_cube_count, objects = false }
  }

  cnsts.saved_global_players = { "current_player", "final_turn_player" }

  cnsts.saved_global_player_lists = { "income_phase_order" }

  cnsts.saved_global_objects = {
    "zoo_deck", "final_scoring_deck", "discard_pile",
    "base_conservation_deck", "rep_max_bonus", "placeholder_card"
  }

  cnsts.saved_global_object_lists = {}

  cnsts.saved_player_fields = {
    "color", "steam_name", "worker_count", "cards_flipped", "build_flipped",
    "animals_flipped", "sponsors_flipped", "association_flipped",
    "hypnotize_action", "build_4_effect", "t1_effect", "map_ice_cream_parlors",
    "map_hollywood_hills", "partial_rewards", "persistent_rewards",
    "acquired_partner_zoos", "acquired_universities", "current_action",
    "action_cards", "venom_unpaid", "sponsor_2_active", "offer_multiplier",
    "sponsor_3_level_discount", "map_key", "map_income", "geologist",
    "hydrologist", "post_action_rewards", "sponsorships", "camouflage",
    "hand_size_plus_1", "wildcard", "condition_3_discount", "waza_special",
    "waza_large_animal_program", "waza_small_animal_program",
    "research_institute_effect", "landscape_gardener", "engineer",
    "store_info_shown", "bonus_tiles", "engineer_builds", "income",
    "pouched_cards", "breeding_program", "turns_taken",
    "breeding_cooperation", "okapi_stable", "deployed_workers", "workers",
    "map_artificial_intelligence", "map_rescue_station", "map_caves", "hooks",
    "played_animals", "played_sponsors", "geographical_cubes"
  }


  cnsts.empty_player_tables = { "claims" }

  cnsts.saved_player_object_lists = { "x_tokens" }

  cnsts.saved_player_object_maps = { "building_tiles" }

  cnsts.player_object_tables = {
    { table = cnsts.appeal_tokens, attr = "appeal_token", disable = true },
    { table = cnsts.conservation_point_tokens, attr = "conservation_point_token", disable = true },
    { table = cnsts.reputation_tokens, attr = "reputation_token", disable = true },
    { table = cnsts.appeal_counters, attr = "appeal_counter", disable = false, counter = true },
    { table = cnsts.cp_counters, attr = "cp_counter", disable = false, counter = true },
    { table = cnsts.score_counters, attr = "score_counter", disable = false, counter = true },
    { table = cnsts.money_counters, attr = "money_counter", disable = false, counter = true },
    { table = cnsts.income_counters, attr = "income_counter", disable = false, counter = true },
    { table = cnsts.rep_counters, attr = "rep_counter", disable = false, counter = true },
    { table = cnsts.player_boards, attr = "player_board", disable = true }
  }

  cnsts.association_tiles = {
    { key = "america_partner",            tag = "partner"    },
    { key = "europe_partner",             tag = "partner"    },
    { key = "asia_partner",               tag = "partner"    },
    { key = "africa_partner",             tag = "partner"    },
    { key = "australia_partner",          tag = "partner"    },
    { key = "hand_size_university",       tag = "university" },
    { key = "double_rep_university",      tag = "university" },
    { key = "double_research_university", tag = "university" }
  }

  cnsts.restored_object_flags = {
    tagged = {
      { tags = { "cube", "partner", "university" }, interactable = false },
    },
    objects = {
      { name = "zoo_deck",               interactable = false, invisible = true },
      { name = "discard_pile",           interactable = false },
      { name = "base_conservation_deck", interactable = false },
      { name = "final_scoring_deck",     interactable = false },
      { name = "placeholder_card",       interactable = false },
    },
    object_lists = {
      { name = "display_cards", locked = true },
    },
    player_objects = {
      { name = "appeal_token",             interactable = false },
      { name = "conservation_point_token", interactable = false },
      { name = "reputation_token",         interactable = false },
    },
    player_object_lists = {
      { name = "x_tokens",       interactable = false },
      { name = "building_tiles", interactable = false },
    },
    player_guid_lists = {
      { name = "workers",            interactable = false },
      { name = "played_animals",     locked = true },
      { name = "played_sponsors",    locked = true },
      { name = "map_rescue_station", locked = true },
      { name = "bonus_tiles",        locked = true },
      { name = "map_caves", interactable = false, locked = true },
    },
    project_rows = { "base_projects", "added_projects" },
  }

  cnsts.counter_script = [[
function onSave()
  local buttons = self.getButtons()
  if buttons == nil or buttons[1] == nil then return "" end
  return JSON.encode(buttons[1])
end

function onLoad(saved)
  if saved ~= nil and saved ~= "" then
    self.createButton(JSON.decode(saved))
  end
end

-- The label buttons name this as their click_function with no function_owner,
-- so TTS looks for it here. They are zero-sized and cannot be clicked, but a
-- function that exists beats a dangling name.
function null_func() end
]]

  cnsts.saved_board_fields = {
    "owner", "blocked", "adjTile", "blockedCount", "cellTags", "tiles",
    "tileCount", "placedCount", "nextId", "unoccupiedCount"
  }

return cnsts
end)()

function install_counter_script(obj)
  obj.setLuaScript(cnsts.counter_script)
  return obj.reload()
end

function onLoad(saved_data)
  local kind, payload = classify_saved_data(saved_data)
  rewind_log("onLoad kind=" .. kind .. " payload=" .. payload_shape(saved_data))

  reset_rewind_after_load()

  if kind == "junk" then
    rewind_junk_depth = payload
    game_started = true
    show_unresumable_panels()
    return
  end

  if kind == "state" then
    checkpoint_needs_spacer = true
    game_started = true
    resolve_scene_objects()
    Wait.condition(
      function()
        restore_checkpoint(payload)
        restore_scene_after_load()
        arm_rewind_spacer_timer()
        refresh_status_panels()
        refresh_pouch_counters()
        resume_checkpoint()
      end,
      function() return checkpoint_objects_ready(payload) end,
      10,
      function()
        broadcastToAll("The rewind could not find the table's objects. " ..
          "Rewind once more, or reload the save.", "Red")
      end)
    return
  end

  resolve_scene_objects()
  start_fresh_table()
end

function reset_rewind_after_load()
  checkpoint_open = false
  restoring_checkpoint = false
  rewind_heartbeat = nil
  rewind_spacer_timer = nil
end

function resolve_scene_objects()
  break_token = getObjectFromGUID(cnsts.break_token_guid)

  zones = {}
  for name, guid in pairs(cnsts.zone_guids) do
    zones[name] = getObjectFromGUID(guid)
  end

  generic_university = {}
  generic_university.tile = getObjectFromGUID(cnsts.generic_university_tile_guid)
  generic_university.home_pos = cnsts.generic_university.home_pos
  generic_university.board_pos = cnsts.generic_university.board_pos

  bags = {}
  for name, guid in pairs(cnsts.bag_guids) do
    bags[name] = getObjectFromGUID(guid)
  end

  map_bag = getObjectFromGUID(cnsts.map_bag_guid)


  for _, furn in ipairs(cnsts.furnitures) do
    getObjectFromGUID(furn).interactable = false
  end
end

function start_fresh_table()
  game_started = false
  final_scoring_discard_triggered = false
  game_end_triggered = false
  final_turn_player = nil
  pouch_slot_count = 0
  marine_worlds_enabled = false
  discard_face_down = true
  left_to_right_order = true
  interactive_effects = true
  solo_turn_cubes = {}
  solo_cubes_advanced = 0
  break_init_val = nil
  break_current_val = nil

  setup_game_button = getObjectFromGUID(cnsts.button_guids.setup_game)
  setup_game_button.createButton({
    click_function = "on_setup_game_button_clicked",
    function_owner = nil,
    label = "",
    color = { 1, 1, 1, 0 },
    position = { 0, 0.31, 0 },
    rotation = { 0, 0, 0 },
    width = 1470,
    height = 990,
    interactable = false,
    tooltip = "Please ensure all players are seated before clicking this button."
  })
end



checkpoint_open = false

rewind_heartbeat = nil

rewind_junk_depth = 0

checkpoint_resume = nil

restoring_checkpoint = false

rewind_debug = false

function rewind_log(text)
  if rewind_debug then printToAll("[rewind] " .. text) end
end

function payload_shape(payload)
  if payload == nil then return "nil" end
  if payload == "" then return "empty" end
  local prefix = cnsts.rewind_junk_prefix
  if string.sub(payload, 1, #prefix) == prefix then return payload end
  return "state(" .. #payload .. " chars)"
end

function onSave()
  if not game_started then
    rewind_log("onSave before the game -> empty")
    return ""
  end

  local payload, why
  if checkpoint_open then
    local ok, encoded = pcall(function() return JSON.encode(checkpoint_state()) end)
    if ok then
      payload, why = encoded, "checkpoint"
    else
      payload, why = cnsts.rewind_junk_prefix .. rewind_junk_depth, "FAILED"
      broadcastToAll("A checkpoint could not be saved and was marked " ..
        "unresumable: " .. tostring(encoded), "Red")
    end
  else
    payload, why = cnsts.rewind_junk_prefix .. rewind_junk_depth, "marker"
  end
  rewind_log("onSave " .. why .. " -> " .. payload_shape(payload))
  return payload
end

function take_checkpoint(entry, player)
  if not game_started then return end

  if restoring_checkpoint then
    restoring_checkpoint = false
    return
  end

  checkpoint_resume = { entry = entry, color = player.color }
  rewind_junk_depth = 0
  checkpoint_open = true
  rewind_log("checkpoint " .. entry .. " for " .. player.color)
  storeRewindState(function(success, stored)
    checkpoint_open = false
    rewind_log("  checkpoint store: success=" .. tostring(success) ..
      " stored=" .. tostring(stored))
    checkpoint_needs_spacer = true
    arm_rewind_heartbeat()
  end, true)
end

checkpoint_needs_spacer = false

function note_player_interaction()
  pay_rewind_spacer()
end

function pay_rewind_spacer()
  if not checkpoint_needs_spacer then return end
  checkpoint_needs_spacer = false
  cancel_rewind_spacer_timer()
  store_rewind_spacer()
end

rewind_spacer_timer = nil

function arm_rewind_spacer_timer()
  cancel_rewind_spacer_timer()
  rewind_spacer_timer = Wait.time(function()
    rewind_spacer_timer = nil
    pay_rewind_spacer()
  end, cnsts.rewind_spacer_seconds)
end

function cancel_rewind_spacer_timer()
  if rewind_spacer_timer ~= nil then
    Wait.stop(rewind_spacer_timer)
    rewind_spacer_timer = nil
  end
end

function store_rewind_spacer()
  rewind_junk_depth = 1
  rewind_log("spacer, so the checkpoint sits one press back")
  storeRewindState(function(success, stored)
    rewind_log("  spacer store: success=" .. tostring(success) ..
      " stored=" .. tostring(stored))
    arm_rewind_heartbeat()
  end, true)
end

function arm_rewind_heartbeat()
  if rewind_heartbeat ~= nil then Wait.stop(rewind_heartbeat) end
  rewind_heartbeat = Wait.time(function()
    rewind_heartbeat = nil
    rewind_heartbeat_store()
  end, cnsts.rewind_heartbeat_seconds)
end

function rewind_heartbeat_store()
  rewind_junk_depth = rewind_junk_depth + 1
  rewind_log("heartbeat, depth now " .. rewind_junk_depth)
  storeRewindState(function(success, stored)
    rewind_log("  heartbeat store: success=" .. tostring(success) ..
      " stored=" .. tostring(stored))
    arm_rewind_heartbeat()
  end, true)
end

function stop_rewind_checkpoints()
  if rewind_heartbeat ~= nil then
    Wait.stop(rewind_heartbeat)
    rewind_heartbeat = nil
  end
  cancel_rewind_spacer_timer()
  allowRewindStore()
end


function checkpoint_state()
  local state = { players = {} }

  for _, name in ipairs(cnsts.saved_globals) do
    state[name] = _G[name]
  end
  for _, name in ipairs(cnsts.saved_global_players) do
    state[name] = player_color_of(_G[name])
  end
  for _, name in ipairs(cnsts.saved_global_player_lists) do
    state[name] = player_color_list(_G[name])
  end
  for _, name in ipairs(cnsts.saved_global_objects) do
    state[name] = object_guid_of(_G[name])
  end
  for _, name in ipairs(cnsts.saved_global_object_lists) do
    state[name] = object_guid_list(_G[name], name)
  end
  for name, length in pairs(cnsts.saved_global_slot_lists) do
    state[name] = slot_guid_list(_G[name], length)
  end

  for i, player in ipairs(players) do
    state.players[i] = checkpoint_player_state(player)
  end

  return state
end

local EFFECT_ATTRIBUTES = nil
local MAP_ATTRIBUTES = nil
local SAVED_PLAYER_FIELDS = nil

function effect_attribute_names()
  if EFFECT_ATTRIBUTES ~= nil then return EFFECT_ATTRIBUTES end

  local names, seen = {}, {}
  local function add(name)
    if name ~= nil and not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end

  for _, set in ipairs({ cnsts.cards.base, cnsts.cards.mw }) do
    for _, card in pairs(set) do
      if card.effect ~= nil then add(to_attribute_name(card.effect)) end
    end
  end

  for _, map in pairs(cnsts.map_data) do
    for _, column in ipairs(map.cells or {}) do
      for _, cell in pairs(column) do
        if type(cell) == "table" and cell.special ~= nil then
          add(to_attribute_name(cell.special))
        end
      end
    end
  end

  for _, spec in pairs(cnsts.incremental_effects) do add(spec.attr_name) end
  for _, attr in pairs(cnsts.remapped_effects) do add(attr) end
  for key in pairs(cnsts.card_cube_effects) do add(to_attribute_name(key)) end
  for key in pairs(cnsts.record_effects) do add(to_attribute_name(key)) end

  EFFECT_ATTRIBUTES = names
  return names
end

function map_attribute_names()
  if MAP_ATTRIBUTES ~= nil then return MAP_ATTRIBUTES end

  local names, seen = {}, {}
  local function add(name)
    if name ~= nil and not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end

  for tile_name, keys in pairs(cnsts.map_keys) do
    add(player_map_attribute_name(tile_name, keys.top))
    add(player_map_attribute_name(tile_name, keys.bottom))
  end
  for name in pairs(cnsts.listed_map_attributes) do add(name) end
  for name in pairs(cnsts.counted_map_attributes) do add(name) end

  MAP_ATTRIBUTES = names
  return names
end

function saved_player_field_names()
  if SAVED_PLAYER_FIELDS ~= nil then return SAVED_PLAYER_FIELDS end

  local names, seen = {}, {}
  local function add(name)
    if not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end
  for _, name in ipairs(cnsts.saved_player_fields) do add(name) end
  for _, name in ipairs(effect_attribute_names()) do add(name) end
  for _, name in ipairs(map_attribute_names()) do add(name) end

  SAVED_PLAYER_FIELDS = names
  return names
end

function checkpoint_player_state(player)
  local saved = {}

  for _, name in ipairs(saved_player_field_names()) do
    saved[name] = player[name]
  end
  for _, name in ipairs(cnsts.saved_player_object_lists) do
    saved[name] = object_guid_list(player[name], "player." .. name)
  end
  for _, name in ipairs(cnsts.saved_player_object_maps) do
    saved[name] = object_guid_map(player[name])
  end
  for name, length in pairs(cnsts.saved_player_slot_lists) do
    saved[name] = slot_guid_list(player[name], length)
  end

  saved.map = checkpoint_board_state(player.map)
  return saved
end

function checkpoint_board_state(board)
  if board == nil then return nil end
  local saved = {}
  for _, name in ipairs(cnsts.saved_board_fields) do
    saved[name] = board[name]
  end
  return saved
end

function player_color_of(player)
  if player == nil then return nil end
  return player.color
end

function player_color_list(list)
  if list == nil then return nil end
  local out = {}
  for i, player in ipairs(list) do out[i] = player.color end
  return out
end

function object_guid_of(obj)
  if obj == nil then return nil end
  return obj.getGUID()
end

function object_guid_list(list, name)
  if list == nil then return nil end
  local out = {}
  for i, obj in ipairs(list) do
    local kind = type(obj)
    local is_object = (kind == "table" or kind == "userdata")
      and obj.getGUID ~= nil
    if not is_object then
      error(string.format(
        "%s is saved as an object list but holds a %s at index %d. " ..
        "If it already holds guids it belongs in saved_player_fields.",
        tostring(name), kind, i))
    end
    out[i] = obj.getGUID()
  end

  local total = 0
  for _ in pairs(list) do total = total + 1 end
  if total ~= #out then
    error(string.format(
      "%s is saved as a dense object list, but ipairs reached only %d of its " ..
      "%d entries. A list with holes in it belongs in a slot list declaration; " ..
      "one with named keys belongs in an object map.",
      tostring(name), #out, total))
  end

  return out
end

function object_guid_map(map)
  if map == nil then return nil end
  local out = {}
  for key, obj in pairs(map) do out[key] = obj.getGUID() end
  return out
end

function slot_guid_list(list, spec)
  local out = {}
  for i = 1, spec.length do
    local entry = list ~= nil and list[i] or nil
    if entry == nil then
      out[i] = false
    elseif type(entry) == "string" then
      out[i] = entry
    else
      out[i] = entry.getGUID()
    end
  end
  return out
end


local CHECKPOINT_RESUMES

function classify_saved_data(saved_data)
  if saved_data == nil or saved_data == "" then return "fresh" end

  local prefix = cnsts.rewind_junk_prefix
  if string.sub(saved_data, 1, #prefix) == prefix then
    return "junk", tonumber(string.sub(saved_data, #prefix + 1)) or 0
  end

  local ok, state = pcall(JSON.decode, saved_data)

  if not ok or type(state) ~= "table" or not state.game_started then
    return "fresh"
  end

  if not resumable_state(state) then return "junk", 0 end
  return "state", state
end

function resumable_state(state)
  if type(state.players) ~= "table" or state.players[1] == nil then return false end
  for _, saved in ipairs(state.players) do
    if saved.color == nil or cnsts.money_counters[saved.color] == nil then
      return false
    end
  end
  if state.checkpoint_resume == nil
     or CHECKPOINT_RESUMES[state.checkpoint_resume.entry] == nil then
    return false
  end
  return true
end

function checkpoint_objects_ready(state)
  for _, saved in ipairs(state.players) do
    local counter = getObjectFromGUID(cnsts.money_counters[saved.color])
    if counter == nil then return false end
    local buttons = counter.getButtons()
    if buttons == nil or buttons[1] == nil then return false end
  end
  return true
end

function restore_checkpoint(state)
  for _, name in ipairs(cnsts.saved_globals) do
    _G[name] = state[name]
  end
  for _, name in ipairs(cnsts.saved_global_objects) do
    _G[name] = object_from_guid(state[name])
  end
  for _, name in ipairs(cnsts.saved_global_object_lists) do
    _G[name] = objects_from_guids(state[name])
  end
  for name, spec in pairs(cnsts.saved_global_slot_lists) do
    _G[name] = slot_list_from_save(state[name], spec)
  end

  restore_players(state.players)
  for _, name in ipairs(cnsts.saved_global_players) do
    _G[name] = find_player_by_color(state[name])
  end
  for _, name in ipairs(cnsts.saved_global_player_lists) do
    _G[name] = players_from_colors(state[name])
  end
end

function restore_players(saved_players)
  players = {}
  for i, saved in ipairs(saved_players) do
    players[i] = restore_player(saved)
  end
end

function restore_player(saved)
  local player = {}

  for _, name in ipairs(saved_player_field_names()) do
    player[name] = saved[name]
  end
  for _, name in ipairs(cnsts.empty_player_tables) do
    player[name] = {}
  end
  for _, name in ipairs(cnsts.saved_player_object_lists) do
    player[name] = objects_from_guids(saved[name])
  end
  for _, name in ipairs(cnsts.saved_player_object_maps) do
    player[name] = objects_from_guid_map(saved[name])
  end
  for name, spec in pairs(cnsts.saved_player_slot_lists) do
    player[name] = slot_list_from_save(saved[name], spec)
  end

  resolve_player_objects(player)
  player.map = restore_board(player.map_key, saved.map)
  return player
end

function resolve_player_objects(player)
  for _, entry in ipairs(cnsts.player_object_tables) do
    player[entry.attr] = getObjectFromGUID(entry.table[player.color])
  end

  player.icon_counters = {}
  for i, guid in ipairs(cnsts.icon_counters[player.color]) do
    player.icon_counters[cnsts.icons.all[i]] = getObjectFromGUID(guid)
  end
end

function restore_board(map_key, saved)
  if saved == nil then return nil end
  local board = HexBoard.Board.new(cnsts.map_data[map_key].cells)
  for _, name in ipairs(cnsts.saved_board_fields) do
    board[name] = saved[name]
  end
  return board
end

function object_from_guid(guid)
  if guid == nil then return nil end
  return getObjectFromGUID(guid)
end

function objects_from_guids(list)
  if list == nil then return nil end
  local out = {}
  for i, guid in ipairs(list) do out[i] = getObjectFromGUID(guid) end
  return out
end

function objects_from_guid_map(map)
  if map == nil then return nil end
  local out = {}
  for key, guid in pairs(map) do out[key] = getObjectFromGUID(guid) end
  return out
end

function restore_object_flags()
  local spec = cnsts.restored_object_flags

  for _, entry in ipairs(spec.tagged) do
    for _, obj in ipairs(getObjectsWithAnyTags(entry.tags)) do
      apply_object_flags(obj, entry)
    end
  end

  for _, entry in ipairs(spec.objects) do
    apply_object_flags(_G[entry.name], entry)
  end
  for _, entry in ipairs(spec.object_lists) do
    apply_flags_to_objects(_G[entry.name], entry)
  end

  lock_bags()

  for _, name in ipairs(spec.project_rows) do
    for _, row in ipairs(_G[name] or {}) do
      apply_object_flags(object_from_guid(row[1]), { locked = true })
    end
  end

  for _, player in ipairs(players) do
    for _, entry in ipairs(spec.player_objects) do
      apply_object_flags(player[entry.name], entry)
    end
    for _, entry in ipairs(spec.player_object_lists) do
      apply_flags_to_objects(player[entry.name], entry)
    end
    for _, entry in ipairs(spec.player_guid_lists) do
      apply_flags_to_guids(player[entry.name], entry)
    end

    for _, pouch in pairs(player.pouched_cards) do
      apply_flags_to_guids(pouch.guids, { interactable = false })
    end
  end
end

function restore_display_row()
  for slot, loc in ipairs(cnsts.display_locs) do
    local card = display_cards[slot]
    if card ~= nil then
      card.setPosition(loc)
      card.setRotation(cnsts.display_card_rotation)
    end
  end
end

function reseat_action_cards()
  for _, player in ipairs(players) do
    for slot = 1, #player.action_cards do
      seat_action_card(player, slot, place_now)
    end
  end
end

function reassert_action_card_faces()
  for _, player in ipairs(players) do
    for slot = 1, #player.action_cards do
      local attribute = action_flip_attribute(player, slot)
      if attribute ~= nil then
        local want = player[attribute] == true
        local card = action_card_object(player, slot)
        if action_card_upgraded(card) ~= want then
          set_tile_face_now(card, want)
        end
      end
    end
  end
end

function restore_scene_after_load()
  restore_object_flags()
  restore_display_row()
  restore_track_tokens()
  reassert_board_tiles()
  reassert_action_card_faces()
  reseat_action_cards()
end

function restore_track_tokens()
  local tracks = {
    { token = "appeal_token",             counter = "appeal_counter",
      spot = appeal_token_position },
    { token = "conservation_point_token", counter = "cp_counter",
      spot = cp_token_position },
    { token = "reputation_token",         counter = "rep_counter",
      spot = rep_token_position },
  }

  for _, track in ipairs(tracks) do
    local standing = {}
    for _, player in ipairs(players) do
      local value = get_counter_value(player[track.counter])
      standing[value] = (standing[value] or 0) + 1
      local token = player[track.token]
      if token ~= nil then
        token.setPosition(track.spot(value, standing[value] - 1))
      end
    end
  end

  if break_current_val ~= nil then
    break_token.setPosition(get_break_position(break_current_val))
  end
end

function bag_content_problems(key, bag, spec)
  if bag == nil then return { key .. ": no bag at that guid" } end

  local entries = bag.getObjects()
  if spec.count ~= nil then
    if #entries == spec.count then return {} end
    return { string.format("%s: holds %d, expected %d",
                           key, #entries, spec.count) }
  end

  local wanted = {}
  for _, name in ipairs(spec.names) do wanted[name] = true end

  local seen, unexpected = {}, {}
  for _, entry in ipairs(entries) do
    if not wanted[entry.name] and not seen[entry.name] then
      unexpected[#unexpected + 1] = entry.name
    end
    seen[entry.name] = true
  end

  local missing = {}
  for _, name in ipairs(spec.names) do
    if not seen[name] then missing[#missing + 1] = name end
  end

  local problems = {}
  if #missing > 0 then
    problems[#problems + 1] = key .. ": missing " .. table.concat(missing, ", ")
  end
  if #unexpected > 0 then
    problems[#problems + 1] =
      key .. ": unexpected " .. table.concat(unexpected, ", ")
  end
  return problems
end

function bag_setup_problems()
  local problems = {}
  for key, spec in pairs(cnsts.expected_bag_contents) do
    for _, problem in ipairs(bag_content_problems(key, bags[key], spec)) do
      problems[#problems + 1] = problem
    end
  end
  table.sort(problems)
  return problems
end

function lock_bags()
  for _, bag in pairs(bags) do
    apply_object_flags(bag, { interactable = false })
  end
end

function apply_object_flags(obj, entry)
  if obj == nil then return end
  if entry.interactable ~= nil then obj.interactable = entry.interactable end
  if entry.locked ~= nil then obj.setLock(entry.locked) end
  if entry.invisible then obj.setInvisibleTo(Player.getColors()) end
end

function apply_flags_to_objects(list, entry)
  if list == nil then return end
  for _, obj in pairs(list) do apply_object_flags(obj, entry) end
end

function apply_flags_to_guids(list, entry)
  if list == nil then return end
  for _, guid in pairs(list) do
    apply_object_flags(object_from_guid(guid), entry)
  end
end

function refresh_pouch_counters()
  for _, player in ipairs(players) do
    refresh_pouch_counter(player)
  end
end

function players_from_colors(list)
  if list == nil then return nil end
  local out = {}
  for i, color in ipairs(list) do out[i] = find_player_by_color(color) end
  return out
end

function slot_list_from_save(list, spec)
  if list == nil then return nil end
  local out = {}
  for i = 1, spec.length do
    local entry = list[i]
    if entry ~= nil and entry ~= false then
      out[i] = spec.objects and getObjectFromGUID(entry) or entry
    end
  end
  return out
end

CHECKPOINT_RESUMES = {
  turn     = function(player) start_player_turn(player) end,
  income   = function(player) start_player_income(player) end,
  end_turn = function(player) end_player_turn(player) end
}

function resume_checkpoint()
  local resume = checkpoint_resume
  restoring_checkpoint = true
  CHECKPOINT_RESUMES[resume.entry](find_player_by_color(resume.color))
end

function unresumable_key(color) return "unresumable_" .. color end

function unresumable_text(depth)
  if depth <= 1 then
    return "Press the rewind arrow once more to reach a point where play can continue."
  end
  return string.format(
    "Press the rewind arrow %d more times to reach a point where play can continue.",
    depth)
end

function show_unresumable_panels()
  local text =
    "This point was saved in the middle of a turn, so play cannot resume from it."
  local instruction = unresumable_text(rewind_junk_depth)

  local height = 16 + 2 * 30 + 30 + 2 * 30 + 18
  for _, color in ipairs(getSeatedPlayers()) do
    set_active_panel(unresumable_key(color), string.format([[
    <Panel id="unresumablePanel_%s" visibility="%s" rectAlignment="MiddleCenter" width="520" height="%d" color="#222222FF">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        <Text id="unresumableText_%s" fontSize="18" color="#FFFFFF">%s</Text>
        <Text fontSize="18" color="#FFFFFF"></Text>
        <Text id="unresumableSteps_%s" fontSize="18" color="#FFFFFF">%s</Text>
      </VerticalLayout>
    </Panel>
    ]], color, color, height, color, text, color, instruction))
  end
end

setup_options = {}

function setup_option_for(key)
  for _, option in ipairs(cnsts.setup_options) do
    if option.key == key then return option end
  end
end

function setup_option_locked_state(option)
  if option.solo_state ~= nil and #seated_game_players() == 1 then
    return option.solo_state
  end
  return nil
end

function on_setup_game_button_clicked()
  if #seated_game_players() == 0 then return end

  setup_game_button.destruct()

  setup_options = {}
  for _, option in ipairs(cnsts.setup_options) do
    setup_options[option.key] = setup_option_locked_state(option) or 1
  end
  UI.setXml(game_setup_panel_xml())
end

function game_setup_panel_xml()
  local rows = {}
  for _, option in ipairs(cnsts.setup_options) do
    local locked = setup_option_locked_state(option) ~= nil
    rows[#rows + 1] = string.format([[
        <HorizontalLayout spacing="10" minHeight="42" preferredHeight="42" childForceExpandWidth="false" childAlignment="MiddleLeft">
          <Text fontSize="18" color="#FFFFFF" alignment="MiddleLeft" preferredWidth="370" flexibleWidth="0">%s</Text>
          <Button id="setupToggle_%s" onClick="on_setup_option_toggled(%s)" interactable="%s" fontSize="18" minHeight="36" preferredWidth="170" flexibleWidth="0" color="%s" textColor="%s">%s</Button>
        </HorizontalLayout>
]], option.prompt, option.key, option.key,
    locked and "false" or "true",
    locked and "#555555" or "#4A90D9",
    locked and "#999999" or "#FFFFFF",
    option.states[setup_options[option.key]].label)
  end

  return string.format([[
    <Panel id="gameSetupPanel" rectAlignment="MiddleCenter" width="600" height="400" color="#222222FF">
      <VerticalLayout spacing="6" padding="16 16 16 16" childAlignment="MiddleCenter" childForceExpandHeight="false">
        <Text fontSize="26" color="#FFFFFF" minHeight="34">Game Setup</Text>
        <Text fontSize="18" color="#FFFFFF" minHeight="18"></Text>
        <Panel color="#FFFFFF" minHeight="2" preferredHeight="2"></Panel>
        <Text fontSize="18" color="#FFFFFF" minHeight="18"></Text>
%s        <Text fontSize="18" color="#FFFFFF" minHeight="18"></Text>
        <Button id="setupProceedButton" onClick="on_setup_proceed_clicked" fontSize="18" minHeight="40" preferredWidth="260" color="#4A90D9" textColor="#FFFFFF">Proceed to Map Selection</Button>
      </VerticalLayout>
    </Panel>
  ]], table.concat(rows))
end

function on_setup_option_toggled(_, key, _)
  local option = setup_option_for(key)
  if setup_option_locked_state(option) ~= nil then return end

  setup_options[key] = setup_options[key] == 1 and 2 or 1
  set_ui_attributes("setupToggle_" .. key,
    { text = option.states[setup_options[key]].label })
end

function on_setup_proceed_clicked()
  for _, option in ipairs(cnsts.setup_options) do
    _G[option.global] = option.states[setup_options[option.key]].value
  end

  if #seated_game_players() == 1 then
    interactive_effects = false
  end

  apply_association_board_image()
  UI.setXml("")
  setup_game()
end

function seated_game_players()
  local out = {}
  for _, player in ipairs(Player.getPlayers()) do
    if player.color ~= "Grey" and player.color ~= "Black" then
      out[#out + 1] = player
    end
  end
  return out
end

function apply_association_board_image()
  local variant = marine_worlds_enabled and "marine_worlds" or "base"
  assocBoard = cnsts.association_board_images[variant]
  if not marine_worlds_enabled then return end

  local assoc = getObjectFromGUID(cnsts.association_board_guid)
  local props = assoc.getCustomObject()
  props.image = assocBoard
  assoc.setCustomObject(props)
  assoc.reload()
  getObjectFromGUID(cnsts.association_board_guid).interactable = false
end

function setup_game()
  zoo_deck = getDeck(getObjectFromGUID(cnsts.zoo_deck_guid))
  base_conservation_deck = getDeck(getObjectFromGUID(cnsts.base_conservation_deck_guid))
  final_scoring_deck = getDeck(getObjectFromGUID(cnsts.final_scoring_deck_guid))

  local mw_replaced_prefixes = {
    "(001)", "(003)", "(005)", "(008)", "(009)", "(010)", "(011)",
    "(101)", "(102)", "(131)",
    "(207)", "(208)", "(225)", "(226)", "(227)", "(250)", "(261)", "(262)"
  }

  local function remove_cards_by_prefix(deck, prefixes)
    local matching_guids = {}
    for _, obj_info in ipairs(deck.getObjects()) do
      for _, prefix in ipairs(prefixes) do
        if string.sub(obj_info.name, 1, string.len(prefix)) == prefix then
          table.insert(matching_guids, obj_info.guid)
          break
        end
      end
    end

    for _, guid in ipairs(matching_guids) do
      deck.takeObject({ guid = guid, position = { 39.5, 1, 27 }, smooth = false })
    end
  end

  local function remove_replaced_cards(deck)
    remove_cards_by_prefix(deck, mw_replaced_prefixes)
  end

  local bonus_tiles = getObjectFromGUID(cnsts.bonus_tile_containers.base)
  local mw_bonus_tiles = getObjectFromGUID(cnsts.bonus_tile_containers.mw)

  local function draw_bonus_tiles()
    local all_bonus_tiles = {}
    bonus_tiles.shuffle()

    local bonus_5_a = bonus_tiles.takeObject({ position = { -30.41, 1.1, 18.20 }, smooth = false })
    local bonus_5_b = bonus_tiles.takeObject({ position = { -28.45, 1.1, 18.20 }, smooth = false })
    local bonus_8_a = bonus_tiles.takeObject({ position = { -24.99, 1.1, 18.20 }, smooth = false })
    local bonus_8_b = bonus_tiles.takeObject({ position = { -23.01, 1.1, 18.20 }, smooth = false })

    table.insert(cp_bonuses_5, bonus_5_a)
    table.insert(cp_bonuses_5, bonus_5_b)
    table.insert(cp_bonuses_8, bonus_8_a)
    table.insert(cp_bonuses_8, bonus_8_b)

    table.insert(all_bonus_tiles, bonus_5_a)
    table.insert(all_bonus_tiles, bonus_5_b)
    table.insert(all_bonus_tiles, bonus_8_a)
    table.insert(all_bonus_tiles, bonus_8_b)

    if marine_worlds_enabled then
      rep_max_bonus = bonus_tiles.takeObject({
        position = { 5.51, 1.12, 16.55 },
        smooth = false
      })
      table.insert(all_bonus_tiles, rep_max_bonus)
    end

    for _, tile in ipairs(all_bonus_tiles) do
      tile.locked = true
    end
  end

  if marine_worlds_enabled then
    remove_replaced_cards(zoo_deck)
    remove_replaced_cards(base_conservation_deck)
    remove_replaced_cards(final_scoring_deck)

    local mw_zoo_deck = getDeck(getObjectFromGUID(cnsts.mw_zones.zoo))
    zoo_deck = zoo_deck.putObject(mw_zoo_deck)
    local mw_conservation = getDeck(getObjectFromGUID(cnsts.mw_zones.conservation))
    base_conservation_deck = base_conservation_deck.putObject(mw_conservation)
    local mw_final_scoring = getDeck(getObjectFromGUID(cnsts.mw_zones.final_scoring))
    final_scoring_deck = final_scoring_deck.putObject(mw_final_scoring)

    for _, obj_info in ipairs(bonus_tiles.getObjects()) do
      if obj_info.name == "PLAY A SPONSOR FOR MONEY" then
        bonus_tiles.takeObject({ guid = obj_info.guid, position = { 39.5, 3, 27 }, smooth = false })
        break
      end
    end

    for i = 1, #mw_bonus_tiles.getObjects() do
      bonus_tiles.putObject(mw_bonus_tiles.takeObject())
    end

  else
    for _, zone_guid in pairs(cnsts.mw_zones) do
      getDeck(getObjectFromGUID(zone_guid)).destruct()
    end
  end

  if not interactive_effects then
    remove_cards_by_prefix(final_scoring_deck, { "(009)", "(017)" })
  end

  cp_bonuses_5 = {}
  cp_bonuses_8 = {}
  draw_bonus_tiles()
  bonus_tiles.destruct()
  mw_bonus_tiles.destruct()

  local zoo_deck_position = zoo_deck.getPosition()
  zoo_deck.translate({ 10, 0, 0 })
  zoo_deck.setInvisibleTo(Player.getColors())
  local hidden_position = zoo_deck.getPosition()
  local first_card = zoo_deck.takeObject({
    smooth = false
  })
  first_card.setPosition(hidden_position)
  placeholder_card = first_card.clone({
    position = zoo_deck_position,
    rotation = first_card.getRotation()
  })
  placeholder_position = zoo_deck_position
  placeholder_card.setLuaScript(cnsts.placeholder_card_script)
  placeholder_card = placeholder_card.reload()
  placeholder_card.setHiddenFrom(Player.getColors())
  placeholder_card.interactable = false

  players = {}
  for _, player in ipairs(seated_game_players()) do
    table.insert(players, { color = player.color, steam_name = player.steam_name })
  end

  local attribute_tables = cnsts.player_object_tables

  for _, color in ipairs({ "White", "Red", "Blue", "Yellow" }) do
    local seated_player = nil
    for _, player in ipairs(players) do
      if player.color == color then
        seated_player = player
        break
      end
    end

    for _, attr_info in ipairs(attribute_tables) do
      local obj = getObjectFromGUID(attr_info.table[color])
      if seated_player ~= nil then
        if attr_info.counter then obj = install_counter_script(obj) end
        seated_player[attr_info.attr] = obj
        if attr_info.disable then
          obj.interactable = false
        end
      else
        obj.destruct()
      end
    end


    if seated_player ~= nil then
      seated_player.icon_counters = {}
    end
    for i, guid in ipairs(cnsts.icon_counters[color]) do
      local counter = getObjectFromGUID(guid)
      if seated_player ~= nil then
        seated_player.icon_counters[cnsts.icons.all[i]] =
          install_counter_script(counter)
      else
        counter.destruct()
      end
    end

    if seated_player == nil or not marine_worlds_enabled then
      getObjectFromGUID(cnsts.drafting_boxes[color]).destruct()
    end
  end

  for _, player in ipairs(players) do
    set_counter(player.money_counter, 25, cnsts.counter_style.money)
    set_counter(player.appeal_counter, 0, cnsts.counter_style.appeal)
    set_counter(player.cp_counter, 0, cnsts.counter_style.cp)
    set_counter(player.rep_counter, 1, cnsts.counter_style.rep)
    set_counter(player.income_counter, 5, cnsts.counter_style.income)
    set_counter(player.score_counter, -14, cnsts.counter_style.score)
    for icon, counter in pairs(player.icon_counters) do
      local style = (icon == "rock" or icon == "water") and cnsts.counter_style.icon_terrain or cnsts.counter_style.icon
      set_icon_counter(counter, 0, style)
    end
    player.partial_rewards = {}
    player.pouched_cards = {}
    player.acquired_partner_zoos = {}
    player.acquired_universities = {}
    player.worker_count = 1
    player.deployed_workers = {}
    player.x_tokens = {}
    player.claims = {}
    player.post_action_rewards = {}
    player.persistent_rewards = {}
    player.income = {}
    player.sponsorships = {}
    player.bonus_tiles = {}
    player.engineer_builds = {}
    player.turns_taken = 0

    player.cards_flipped = false
    player.build_flipped = false
    player.animals_flipped = false
    player.sponsors_flipped = false
    player.association_flipped = false
    player.hypnotize_action = false
  end

  broadcastToAll("Setting up a " .. #players .. "-Player game")
  base_conservation_deck.shuffle()
  base_projects = {}
  local base_project_count = #players > 3 and 4 or 3
  local card_pos = cnsts.absolute_positions.base_project
  for i = 1, base_project_count do
    base_conservation_deck.takeObject({
      position = card_pos,
      smooth = false,
      flip = true,
      callback_function = function(proj_card)
        Wait.frames(
          function()
            proj_card.locked = true
            base_projects[i] = { proj_card.guid, {} }
            if #players == 2 then
              local cube = take_cube(proj_card.getPosition() + cnsts.card_relative_positions.icon_proj[i])
              base_projects[i][2][i] = cube.guid
              cube.jointTo(proj_card, { type = "Fixed", collision = false })
            end
          end
        )
      end
    })
    card_pos = card_pos + cnsts.absolute_positions.project_step
  end

  if #players == 2 then
    for _, zone in ipairs({"donation_5_1", "donation_7_1", "donation_10_1"}) do
      take_cube(getObjectFromGUID(cnsts.zone_guids[zone]).getPosition() + Vector(0,1,0))
    end
  end

  if #players == 4 then
    break_init_val = 15
  elseif #players == 3 then
    break_init_val = 12
  elseif #players == 2 then
    break_init_val = 9
  end

  if break_init_val ~= nil then
    break_current_val = break_init_val
    move_break_token(break_current_val)
  end

  local bag_problems = bag_setup_problems()
  if #bag_problems > 0 then
    for _, problem in ipairs(bag_problems) do
      broadcastToAll(problem, { 1, 0, 0 })
    end
    broadcastToAll("Bag contents are not what setup expects. Setup aborted.",
                   { 1, 0, 0 })
    return
  end
  lock_bags()

  local expected_zoo_cards = marine_worlds_enabled and 266 or 212
  Wait.condition(
    continue_setup_game,
    function() return zoo_deck.getQuantity() == expected_zoo_cards end,
    5,
    function()
      broadcastToAll(
        "Zoo deck has " .. zoo_deck.getQuantity() .. " cards, expected " .. expected_zoo_cards .. ". Setup aborted.",
        { 1, 0, 0 }
      )
    end
  )
end

function continue_setup_game()
  display_cards = {}
  display_marks = {}
  zoo_deck.shuffle()
  for i = 1, 6 do
    local card = zoo_deck.takeObject({
      position = cnsts.display_locs[i],
      rotation = { 0, 180, 180 },
      smooth = false
    })
    card.addTag("zoo_card")
    table.insert(display_cards, card)
  end

  for _, card in ipairs(display_cards) do
    card.locked = true
  end

  for _, obj in ipairs({ zoo_deck, base_conservation_deck, final_scoring_deck, break_token }) do
    obj.interactable = false
  end

  refill_association_board()
  final_scoring_deck.shuffle()

  local color_order = { "White", "Red", "Blue", "Yellow" }
  if not left_to_right_order then
    color_order = { "Yellow", "Blue", "Red", "White" }
  end

  local starting_player = players[math.random(#players)]

  local starting_index = 1
  for i, color in ipairs(color_order) do
    if color == starting_player.color then
      starting_index = i
      break
    end
  end

  local sorted_players = {}
  for i = 0, #color_order - 1 do
    local color = color_order[((starting_index - 1 + i) % #color_order) + 1]
    for _, player in ipairs(players) do
      if player.color == color then
        table.insert(sorted_players, player)
        break
      end
    end
  end
  players = sorted_players

  if #players == 1 then
    setup_solo_challenge(players[1])
    return
  end

  getObjectFromGUID(cnsts.solo.board_guid).destruct()
  for i, player in ipairs(players) do
    if i > 1 then update_appeal(player, i - 1, "starting bonus") end
  end

  broadcastToAll(starting_player.steam_name .. " is the starting player")

  setup_player_maps()
end

function setup_solo_challenge(player)
  local board = getObjectFromGUID(cnsts.solo.board_guid)
  local dx = cnsts.solo.board_right_of[player.color]
    and cnsts.solo.board_dx or -cnsts.solo.board_dx
  local origin = Vector(player.player_board.getPosition().x + dx,
                        cnsts.solo.board_y, cnsts.solo.board_z)
  board.setPosition(origin)

  solo_turn_cubes = {}
  solo_cubes_advanced = 0
  local at = origin + cnsts.solo.first_cube
  for i = 1, cnsts.solo.cube_count do
    local cube = take_cube({ x = at.x, y = at.y + cnsts.drop_height, z = at.z })
    solo_turn_cubes[i] = cube.getGUID()
    at = at + cnsts.solo.cube_step
  end

  show_solo_difficulty_panel(player)
end

function show_solo_difficulty_panel(player)
  local buttons = ""
  for _, option in ipairs(cnsts.solo.difficulties) do
    buttons = buttons .. string.format([[
        <Button id="soloDifficulty_%d" onClick="on_solo_difficulty_clicked(%d)" fontSize="18" minHeight="40" preferredWidth="340" color="#4A90D9" textColor="#FFFFFF">%s (start with %d appeal)</Button>
]], option.appeal, option.appeal, option.name, option.appeal)
  end

  UI.setXml(string.format([[
    <Panel id="soloDifficultyPanel" visibility="%s" rectAlignment="MiddleCenter" width="560" height="250" color="#222222FF">
      <VerticalLayout spacing="8" padding="16 16 16 16" childAlignment="MiddleCenter" childForceExpandHeight="false">
        <Text fontSize="18" color="#FFFFFF" minHeight="24">Choose your desired difficulty for the solo challenge:</Text>
%s      </VerticalLayout>
    </Panel>
  ]], player.color, buttons))
end

function on_solo_difficulty_clicked(_, value, _)
  local player = players[1]
  local appeal = tonumber(value)
  if appeal == nil or solo_turn_cubes == nil then return end

  UI.setXml("")
  if appeal > 0 then update_appeal(player, appeal, "starting bonus") end
  setup_player_maps()
end

function every_player_owns(tag, owner)
  local field = tag == "partner" and "acquired_partner_zoos" or "acquired_universities"
  for _, player in ipairs(players) do
    local held = false
    for _, entry in ipairs(player[field]) do
      if entry == owner then
        held = true
        break
      end
    end
    if not held then return false end
  end
  return true
end

function board_tile_key(key)
  if marine_worlds_enabled and cnsts.zone_guids[key .. "_mw"] ~= nil then
    return key .. "_mw"
  end
  return key
end

function board_tile_zone(key)
  return zones[board_tile_key(key)]
end

function refill_association_board()
  for _, tile in ipairs(cnsts.association_tiles) do
    local key = board_tile_key(tile.key)
    local owner = tile.key:sub(1, -#tile.tag - 2)
    if tile_missing(zones[key], tile.tag)
       and #bags[tile.key].getObjects() > 0
       and not every_player_owns(tile.tag, owner) then
      local placed_tile = bags[tile.key].takeObject({
        position = cnsts.absolute_positions[key],
        smooth = false
      })
      placed_tile.interactable = false
    end
  end

  if marine_worlds_enabled then
    if tile_missing(board_tile_zone("generic_university"), "university") then
      generic_university.tile.setPosition(generic_university.board_pos)
    end
  end
end

function get_break_position(value)
  local pos = cnsts.break_token.zero_position
  if value >= 1 then
    pos = pos + cnsts.break_token.first_step + cnsts.break_token.step_size * (value - 1)
  end
  return pos
end

function move_break_token(value)
  break_token.setPositionSmooth(get_break_position(value))
end

function break_x(raw, player)
  if #players==1 then return end
  local new_break_val = math.max(break_current_val - raw, 0)
  move_break_token(new_break_val)
  if player ~= nil then
    printToAll(player.steam_name .. " advances the break token " .. (break_current_val - new_break_val) .. " spaces.")
    if break_current_val > 0 and new_break_val == 0 then
      update_x_token(player, 1, "triggering the break")
    end
  end
  break_current_val = new_break_val
end

function track_tokens_in(zone)
  local n = 0
  for _, obj in pairs(zone.getObjects(true)) do
    if obj.hasTag("track_token") then n = n + 1 end
  end
  return n
end

function appeal_token_position(value, count)
  local pos = getObjectFromGUID(cnsts.appeal_zones[value + 1]).getPosition()

  pos.y = (count < 2) and 1.5 or 2
  local sign = (count % 2 == 0) and 1 or -1
  if value > 51 and value < 61 then
    pos.x = pos.x + sign * 0.3
  else
    pos.z = pos.z + sign * 0.3
  end

  return pos
end

function get_appeal_zone_position(value)
  return appeal_token_position(value,
    track_tokens_in(getObjectFromGUID(cnsts.appeal_zones[value + 1])))
end

function sponsorship_income(count)
  if count >= 5 then return 9 end
  if count >= 3 then return 6 end
  if count >= 1 then return 3 end
  return 0
end

function sponsorship(player, species_type)
  player.sponsorships[species_type] = true
  return sponsorship_income(
    get_icon_counter_value(player.icon_counters[species_type])) .. " money"
end

function adjust_sponsorship_income(player, icon_str, prev, new)
  if not player.sponsorships[icon_str] then return end
  local delta = sponsorship_income(new) - sponsorship_income(prev)
  if delta ~= 0 then
    set_counter(player.income_counter,
      get_counter_value(player.income_counter) + delta, cnsts.counter_style.income)
  end
end

function appeal_to_income(value)
  for _, threshold in ipairs(cnsts.appeal_income_thresholds) do
    if value <= threshold[1] then
      return threshold[2]
    end
  end
  return cnsts.appeal_income_thresholds[#cnsts.appeal_income_thresholds][2]
end

function print_track_change(player, applied_amount, noun, source)
  local verb = applied_amount < 0 and "loses" or "gains"
  printToAll(player.steam_name .. " " .. verb .. " " .. math.abs(applied_amount) .. " " .. noun .. (source and (" from " .. source) or "") .. ".")
end

function update_appeal(player, amount, source)
  print_track_change(player, apply_appeal(player, amount), "appeal", source)
end

function apply_appeal(player, amount)
  local old_appeal = get_counter_value(player.appeal_counter)
  local new_appeal = math.max(0, math.min(#cnsts.appeal_zones - 1, old_appeal + amount))
  local applied_amount = new_appeal - old_appeal

  if amount > 0 and applied_amount < amount then
    broadcastToAll(player.steam_name .. " cannot gain any more appeal!")
  end

  set_counter(player.appeal_counter, new_appeal, cnsts.counter_style.appeal)
  move_when_settled(player.appeal_token.getGUID(),
    get_appeal_zone_position(new_appeal))

  local new_score = get_counter_value(player.score_counter) + applied_amount
  set_counter(player.score_counter, new_score, cnsts.counter_style.score)

  local income_delta = appeal_to_income(new_appeal) - appeal_to_income(old_appeal)
  local new_income = get_counter_value(player.income_counter) + income_delta
  set_counter(player.income_counter, new_income, cnsts.counter_style.income)

  return applied_amount
end

function cp_token_position(value, count)
  local pos = getObjectFromGUID(cnsts.cp_zones[value + 1]).getPosition()

  local sign = (count % 2 == 0) and 1 or -1
  local offset = 0.3
  if value >= 11 then
    pos.y = 1.5
    if count >= 2 then
      offset = 0.9
    end
  else
    pos.y = (count < 2) and 1.5 or 2
  end

  if value > 21 and value < 25 then
    pos.z = pos.z + sign * offset
  else
    pos.x = pos.x + sign * offset
  end

  return pos
end

function get_cp_zone_position(value)
  return cp_token_position(value,
    track_tokens_in(getObjectFromGUID(cnsts.cp_zones[value + 1])))
end

function cp_to_score(value)
  return 2 * math.min(value, 10) + 3 * math.max(0, value - 10)
end

function bonus_tile_reward(tile)
  return cnsts.bonus_tile_mapping[tile.getGUID()]
end

function offer_cp_bonus_choice(player, checkpoint)
  local source = "the " .. checkpoint .. "-CP bonus"

  if checkpoint == 2 then
    create_claims_from_rewards(player, cnsts.cp_bonus_2, source, true)
    return
  end

  local pool = (checkpoint == 5) and cp_bonuses_5 or cp_bonuses_8
  local rewards = {}
  for i = 1, 2 do
    if pool[i] ~= nil then
      table.insert(rewards, bonus_tile_reward(pool[i]))
    end
  end
  table.insert(rewards, "5 money")

  create_claims_from_rewards(player, rewards, source, true)
end

function update_cp(player, amount, source)
  local applied_amount, old_cp, new_cp = apply_cp(player, amount)
  print_track_change(player, applied_amount, "conservation point", source)
  offer_cp_checkpoints(player, old_cp, new_cp)
end

function apply_cp(player, amount)
  local old_cp = get_counter_value(player.cp_counter)
  local new_cp = math.max(0, math.min(#cnsts.cp_zones - 1, old_cp + amount))
  local applied_amount = new_cp - old_cp

  if amount > 0 and applied_amount < amount then
    broadcastToAll(player.steam_name .. " cannot gain any more conservation points!")
  end

  set_counter(player.cp_counter, new_cp, cnsts.counter_style.cp)
  move_when_settled(player.conservation_point_token.getGUID(),
    get_cp_zone_position(new_cp))

  local score_delta = cp_to_score(new_cp) - cp_to_score(old_cp)
  local new_score = get_counter_value(player.score_counter) + score_delta
  set_counter(player.score_counter, new_score, cnsts.counter_style.score)

  return applied_amount, old_cp, new_cp
end

function offer_cp_checkpoints(player, old_cp, new_cp)
  local checkpoint_claims = {}
  if old_cp < 2 and new_cp >= 2 then
    table.insert(checkpoint_claims, {
      button_text = "Pick 2 conservation point bonus",
      async = true,
      function_call = function() offer_cp_bonus_choice(player, 2) end
    })
  end
  if old_cp < 5 and new_cp >= 5 then
    table.insert(checkpoint_claims, {
      button_text = "Pick 5 conservation point bonus",
      async = true,
      function_call = function() offer_cp_bonus_choice(player, 5) end
    })
  end
  if old_cp < 8 and new_cp >= 8 then
    table.insert(checkpoint_claims, {
      button_text = "Pick 8 conservation point bonus",
      async = true,
      function_call = function() offer_cp_bonus_choice(player, 8) end
    })
  end
  if not final_scoring_discard_triggered and old_cp < 10 and new_cp >= 10 then
    final_scoring_discard_triggered = true
    table.insert(checkpoint_claims, {
      button_text = "Discard Final Scoring",
      async = true,
      function_call = function() start_final_scoring_discard(player) end
    })
  end
  if #checkpoint_claims > 0 then
    table.insert(player.claims, checkpoint_claims)
  end
  render_claims_table(player)
end

function start_final_scoring_discard(player)
  broadcastToAll(player.steam_name ..
    " has reached 10 Conservation Points. All players discard 1 Final Scoring card.")

  local remaining = #players
  for _, p in ipairs(players) do
    prompt_final_scoring_discard(p, 1, nil, function()
      remaining = remaining - 1
      if remaining == 0 then
        clear_waiting_status()
        render_claims_table(player)
      else
        set_waiting_status(p, cnsts.waiting_to_discard)
      end
    end)
  end
end

function update_money(player, amount, source)
  local bonus = 0
  if amount > 0 and player.sponsor_2_active and not persistent_origin then
    bonus = sponsors_upgraded(player) and 5 or 3
    player.sponsor_2_active = nil
  end

  if amount > 0 then
    printToAll(player.steam_name .. " gains " .. amount .. " money" .. (source and " from " .. source or "") .. ".")
  else
    printToAll(player.steam_name .. " spends " .. math.abs(amount) .. " money" .. (source and " for " .. source or "") .. ".")
  end
  if bonus > 0 then
    printToAll(player.steam_name .. " gains " .. bonus .. " additional money from Sponsors 2.")
  end

  set_counter(player.money_counter,
    get_counter_value(player.money_counter) + amount + bonus,
    cnsts.counter_style.money)
end

token_parents = {}

function token_clone_source(token_name)
  local last = token_parents[token_name]
  if last ~= nil then
    local alive = getObjectFromGUID(last)
    if alive ~= nil and alive.getName() == token_name then return alive end
  end

  local guid = nil
  for _, info in ipairs(bags.tokens.getObjects()) do
    if info.name == token_name then
      guid = info.guid
      break
    end
  end
  if guid == nil then return nil end

  local source = bags.tokens.takeObject({
    guid = guid,
    position = bags.tokens.getPosition() + Vector(0, 1, 0),
    smooth = false
  })
  token_parents[token_name] = source.getGUID()
  return source
end

building_parents = {}

function building_clone_source(search_name, and_then)
  local last = building_parents[search_name]
  if last ~= nil then
    local alive = getObjectFromGUID(last)
    if alive ~= nil and alive.getName() == search_name then
      and_then(alive)
      return
    end
  end

  local guid = tile_guid_in_bag(bags.build_buildings, search_name)
  if guid == nil then
    error("no " .. tostring(search_name) .. " in the building bag to clone")
  end

  bags.build_buildings.takeObject({
    guid = guid,
    position = bags.build_buildings.getPosition() + Vector(0, 1, 0),
    smooth = false,
    callback_function = function(obj)
      building_parents[search_name] = obj.getGUID()
      and_then(obj)
    end
  })
end

function tile_guid_in_bag(bag, search_name)
  for _, info in ipairs(bag.getObjects()) do
    if info.name == search_name then return info.guid end
  end
  return nil
end

function update_x_token(player, count, source)
  if count < 0 then
    local spent = math.min(-count, #player.x_tokens)
    for _ = 1, spent do
      table.remove(player.x_tokens).destruct()
    end

    local message = player.steam_name .. " spends " .. spent .. " " ..
      ((spent == 1) and "X-token" or "X-tokens")
    if source ~= nil then message = message .. " for " .. source end
    printToAll(message .. ".")
    return
  end

  local granted = math.min(count, 5 - #player.x_tokens)

  if granted > 0 then
    local token_source = token_clone_source("X-token")
    local board_pos = player.player_board.getPosition()
    for _ = 1, granted do
      local token = token_source.clone({})
      table.insert(player.x_tokens, token)
      token.setPositionSmooth(board_relative_world_position(board_pos, "x_token_" .. #player.x_tokens .. "_home"))
      token.setRotationSmooth({ 0, 180, 0 })
      token.interactable = false
    end
  end

  local message = player.steam_name .. " gains " .. granted .. " " ..
    ((granted == 1) and "X-token" or "X-tokens")
  if source ~= nil then
    message = message .. " from " .. source
  end
  if granted < count then
    message = message .. " (capped)"
  end
  printToAll(message .. ".")
end

function inventive(player, count, source)
  update_x_token(player, count, source)
end

function inventive_bear_count()
  local total = 0
  for _, p in ipairs(players) do
    total = total + get_icon_counter_value(p.icon_counters["bear"])
  end
  return math.min(total, 3)
end

function inventive_primate_count(player)
  local primates = get_icon_counter_value(player.icon_counters["primate"])
  if primates >= 5 then return 3 end
  if primates >= 3 then return 2 end
  if primates >= 1 then return 1 end
  return 0
end

function inventive_bear(player, source)
  update_x_token(player, inventive_bear_count(), source)
end

function inventive_primate(player, source)
  update_x_token(player, inventive_primate_count(player), source)
end

function management_rep_amount(player)
  return math.floor(get_icon_counter_value(player.icon_counters.research) / 2)
end

function management_rep(player, source)
  update_rep(player, management_rep_amount(player), source)
end

function pack(player, source)
  update_appeal(player, get_icon_counter_value(player.icon_counters["predator"]),
    (source and (source .. "'s ") or "") .. "Pack")
end

function release_of_patents_cp(player)
  return math.min(get_icon_counter_value(player.icon_counters["research"]), 3)
end

function icon_type_count(player)
  local types = 0
  for _, group in ipairs({ cnsts.icons.habitat, cnsts.icons.species }) do
    for _, icon in ipairs(group) do
      if get_icon_counter_value(player.icon_counters[icon]) > 0 then
        types = types + 1
      end
    end
  end
  return types
end

function explorer_money_amount(player)
  return 2 * icon_type_count(player)
end

function basic_research_cp(player)
  return math.floor(icon_type_count(player) / 2)
end

function diversity_researcher_money_amount(player)
  return 2 * (get_icon_counter_value(player.icon_counters["water"])
    + get_icon_counter_value(player.icon_counters["rock"]))
end

function pay_others_for_cp(player, cp, effect_name)
  if cp <= 0 then return end
  for _, other in ipairs(players) do
    if other ~= player then
      update_money(other, 2 * cp, player.steam_name .. "'s " .. effect_name)
    end
  end
end

function release_of_patents(player, source)
  local cp = release_of_patents_cp(player)
  pay_others_for_cp(player, cp, "Release of Patents")
  update_cp(player, cp, source)
end

function basic_research(player, source)
  local cp = basic_research_cp(player)
  pay_others_for_cp(player, cp, "Basic Research")
  update_cp(player, cp, source)
end

function iconic_count(habitat)
  local total = 0
  for _, p in ipairs(players) do
    total = total + get_icon_counter_value(p.icon_counters[habitat])
  end
  return math.min(total, 8)
end

function iconic(player, habitat, source)
  update_appeal(player, iconic_count(habitat),
    (source and (source .. "'s ") or "") .. "Iconic Animal: " .. habitat_label(habitat))
end

function iconic_africa(player, source)    iconic(player, "africa", source) end
function iconic_america(player, source)   iconic(player, "america", source) end
function iconic_asia(player, source)      iconic(player, "asia", source) end
function iconic_australia(player, source) iconic(player, "australia", source) end
function iconic_europe(player, source)    iconic(player, "europe", source) end

function glide(player, count, source)
  retire_active_claim()

  create_card_selection_panel(player, function() return player_hand_cards(player) end,
    count, "glide discard",
    function(names)
      if not names then
        render_claims_table(player)
        return
      end

      local sea = 0
      for _, name in ipairs(names) do
        for _, icon in ipairs(card_data_for(name).icons or {}) do
          if icon == "sea" then sea = sea + 1 end
        end
      end

      if sea == 0 then
        render_claims_table(player)
        return
      end

      local label = (source and (source .. "'s ") or "") .. "Glide"
      local sub_table = {}
      for _ = 1, sea do
        table.insert(sub_table, {
          button_text = "1-Rep/2-Appeal/Kiosk",
          optional = false,
          async = true,
          function_call = function()
            local rewards = { "1 rep", "2 appeal" }
            if player.map:findValidPlacement(cnsts.build_tile_shapes["KIOSK"],
                                             tile_placement_opts(player, "KIOSK")) ~= nil then
              rewards[#rewards + 1] = "free kiosk"
            else
              broadcastToColor("Your map cannot accommodate another Kiosk!",
                player.color, "Red")
            end
            create_claims_from_rewards(player, rewards, label, true)
          end
        })
      end
      table.insert(player.claims, sub_table)
      render_claims_table(player)
    end, nil, nil, true)
end

function farm_cat_appeal(player)
  local buildings = #player.map:tilesWithTag("kiosk") + #player.map:tilesWithTag("pavilion")
  if buildings >= 7 then return 5 end
  if buildings >= 4 then return 3 end
  if buildings >= 1 then return 1 end
  return 0
end

local SYMBIOSIS_PLAIN_UNITS = { appeal = true, rep = true, cp = true }

local function symbiosis_ability(reward)
  if reward == "symbiosis" then return false end
  local amount, unit = reward:match("^(%S+) (%S+)$")
  return not (amount ~= nil and tonumber(amount) ~= nil and SYMBIOSIS_PLAIN_UNITS[unit])
end

function symbiosis(player, source)
  local seen, abilities = {}, {}
  for _, guid in ipairs(player.played_animals) do
    local played = getObjectFromGUID(guid)
    local data = played ~= nil and card_data_for(played.getName()) or nil
    if data ~= nil then
      local is_sea = false
      for _, icon in ipairs(data.icons or {}) do
        if icon == "sea" then
          is_sea = true
          break
        end
      end
      if is_sea then
        for _, reward in ipairs(data.rewards or {}) do
          if not seen[reward] and symbiosis_ability(reward) then
            seen[reward] = true
            abilities[#abilities + 1] = reward
          end
        end
      end
    end
  end

  if #abilities == 0 then
    broadcastToColor("You have no other Sea Animals with an ability!", player.color, "Red")
    render_claims_table(player)
    return
  end

  create_claims_from_rewards(player, abilities,
    source and (source .. "'s symbiosis") or "symbiosis", true)
end

function draw(player, count, source)
  printToAll(player.steam_name .. " gets ".. (count==1 and "a" or count) .." draw" .. (count>1 and "s" or "") .. " from " .. source .. ".")
  draw_from_rep_range(player, count)
end

function draw_t1_unlock(player, source)
  player.t1_effect = "ready"
  draw(player, 1, source)
end

function income_reward_string(reward)
  return cnsts.income_equivalents[reward] or reward
end

function snap(player, count)
  start_snap(player, count, true)
end

function sprint(player, count, source)
  deal_cards_to_hand(zoo_deck, count, player, 1, "zoo_card", function()
    local message = player.steam_name .. " draws " .. count .. " card" .. (count == 1 and "" or "s") .. " from the deck"
    if source ~= nil then
      message = message .. " for " .. source
    end
    printToAll(message .. ".")
    render_claims_table(player)
  end)
end

function adapt(player, count, source)
  local message = string.format("%s adapts %d", player.steam_name, count)
  if source ~= nil then message = message .. " from " .. source end
  printToAll(message .. ".")

  deal_cards_to_hand(final_scoring_deck, count, player, 2, "final_scoring", function()
    prompt_final_scoring_discard(player, count)
  end)
end

function resistance(player, source)
  local message = player.steam_name .. " draws 2 final scoring cards"
  if source ~= nil then message = message .. " for playing " .. source end
  printToAll(message .. ".")

  deal_cards_to_hand(final_scoring_deck, 2, player, 2, "final_scoring", function(dealt)
    prompt_final_scoring_discard(player, 1, dealt, function()
      printToAll(player.steam_name .. " discards 1 final scoring card.")
      render_claims_table(player)
    end)
  end)
end

function reveal_and_keep(player, count, source, spec)
  local message = string.format("%s performs %s %d", player.steam_name, spec.name, count)
  if source ~= nil then message = message .. " from " .. source end
  printToAll(message .. ".")

  local deck_objects = zoo_deck.getObjects()
  local top, names = {}, {}
  for i = 1, count do
    table.insert(top, deck_objects[i])
    table.insert(names, string.sub(deck_objects[i].name, 7))
  end
  printToAll(string.format("%s %d reveals the cards: %s.", spec.name, count,
    table.concat(names, ", ")))

  local discard_position = getObjectFromGUID(cnsts.discard_pile_zone).getPosition()
  local caught = {}
  for _, info in ipairs(top) do
    if card_data_for(info.name).type == spec.type then
      table.insert(caught, deal_tagged_card(zoo_deck, info.guid, player.color, 1, "zoo_card"))
    else
      zoo_deck.takeObject({ guid = info.guid, position = discard_position, smooth = false })
    end
  end

  if #caught == 0 then
    printToAll("There were no cards to choose from.")
    render_claims_table(player)
    return
  end

  local function keep_card(card)
    printToAll(player.steam_name .. " keeps " .. string.sub(card.getName(), 7) ..
      " " .. spec.kept .. ".")
    render_claims_table(player)
  end

  wait_for_cards_in_hand(player, 1, caught, function()
    if #caught == 1 then
      keep_card(caught[1])
      return
    end
    prompt_keep(player, caught, 1, function(kept) keep_card(kept[1]) end, true)
  end)
end

function hunter(player, count, source)
  if count == 0 then
    count = get_icon_counter_value(player.icon_counters["predator"])
  end
  reveal_and_keep(player, count, source,
    { name = "Hunter", type = "animal", kept = "from the hunt" })
end

function scuba_dive_count(player)
  return get_icon_counter_value(player.icon_counters["reptile"])
    + get_icon_counter_value(player.icon_counters["sea"])
end

function scuba_dive(player, count, source)
  if count == 0 then
    count = scuba_dive_count(player)
  end
  reveal_and_keep(player, count, source,
    { name = "Scuba Dive", type = "sponsor", kept = "from the dive" })
end

function marine_research_expedition(player, source)
  local rewards = { "scuba dive 3" }
  if #person_sponsors(player) > 0 then
    rewards[#rewards + 1] = "expedition"
  end
  create_claims_from_rewards(player, rewards, source, true)
end

function person_sponsors(player)
  local out = {}
  for _, guid in ipairs(player.played_sponsors) do
    local obj = getObjectFromGUID(guid)
    if card_matches_search_key(card_data_for(obj.getName()), "person_sponsor") then
      out[#out + 1] = obj
    end
  end
  return out
end

expedition_picks = {}

function expedition_panel_xml(color, state)
  local body = [[<Text fontSize="18" color="#FFFFFF">Choose one of the following to send on an expedition:</Text>
    <Text fontSize="18" color="#FFFFFF"></Text>]]
  local height = 16 + 50 + 30 + 12

  for _, obj in ipairs(person_sponsors(state.player)) do
    body = body .. string.format([[
      <Button id="expeditionButton_%s_%s" onClick="on_expedition_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">%s</Button>
    ]], color, obj.getGUID(), color .. "|" .. obj.getGUID(),
        string.sub(obj.getName(), 7))
    height = height + 40
  end

  return string.format([[
    <Panel id="expeditionPanel_%s" visibility="%s" rectAlignment="MiddleRight" width="280" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="UpperCenter" childForceExpandHeight="false">
        %s
      </VerticalLayout>
    </Panel>
  ]], color, color, height, body)
end

function render_expedition_panel(player)
  set_player_panel(player.color,
    expedition_panel_xml(player.color, expedition_picks[player.color]))
end

function expedition(player, source)
  expedition_picks[player.color] = { player = player, source = source }
  render_expedition_panel(player)
end

function on_expedition_clicked(_, value, _)
  local color, guid = value:match("^(%a+)|(%w+)$")
  local state = expedition_picks[color]
  if state == nil then return end

  local player = state.player
  expedition_picks[color] = nil
  clear_player_panel(color)

  send_sponsor_away(player, guid)
  create_claims_from_rewards(player, { "1 cp" }, state.source)
end

function move_card_cube(guid, spot, dest)
  local target = dest + cnsts.card_relative_positions[spot]
  getObjectFromGUID(guid).setPositionSmooth(
    { x = target.x, y = target.y + cnsts.drop_height, z = target.z },
    false, false)
end

function move_sponsor_cubes(player, card_obj, dest)
  local effect = card_data_for(card_obj.getName()).effect
  if effect == nil then return end
  local record = player[to_attribute_name(effect)]
  if type(record) ~= "table" then return end

  if record.cube ~= nil then
    move_card_cube(record.cube, "waza_special_" .. record.type, dest)
    return
  end

  for i, spot in ipairs(cnsts.card_cube_effects[effect] or {}) do
    if record[i] ~= nil then move_card_cube(record[i], spot, dest) end
  end
end

function send_sponsor_away(player, guid)
  local obj = getObjectFromGUID(guid)
  local full_name = obj.getName()
  local name = string.sub(full_name, 7)
  local card = card_data_for(full_name)

  printToAll(player.steam_name .. " sends " .. name .. " on an expedition.")

  add_remove_icons(player, card.icons or {}, true)
  if card.effect ~= nil then process_effects(player, card.effect, true) end
  add_remove_hooks(player, name, card.hook_self, card.hook_all, true)
  remove_income(player, card.income, name)

  local index
  for i, played in ipairs(player.played_sponsors) do
    if played == guid then index = i break end
  end
  table.remove(player.played_sponsors, index)

  obj.locked = false
  discard_pile.putObject(obj)

  local board_pos = player.player_board.getPosition()
  for i = index, #player.played_sponsors do
    local card = getObjectFromGUID(player.played_sponsors[i])
    local pos = played_sponsor_position(board_pos, i)
    card.setPositionSmooth(pos, false, false)
    move_sponsor_cubes(player, card, pos)
  end

  discard_pouched_cards(player, name)
end

function discard_pouched_cards(player, source)
  local entry = player.pouched_cards[source]
  if entry == nil then return end
  player.pouched_cards[source] = nil

  local cards = {}
  for _, card_guid in ipairs(entry.guids) do
    local card = getObjectFromGUID(card_guid)
    card.locked = false
    card.interactable = true
    cards[#cards + 1] = card
  end
  discard_cards(player, cards)
  refresh_pouch_counter(player)
end

function scavenging(player, count, source)
  local message = string.format("%s scavenges %d from the discard pile", player.steam_name, count)
  if source ~= nil then message = message .. " for " .. source end
  printToAll(message .. ".")

  discard_pile.shuffle()
  deal_cards_to_hand(discard_pile, count, player, 1, "zoo_card", function(dealt)
    prompt_keep(player, dealt, 1)
  end)
end

function horse_whisperer(player, source)
  local wanted = {}
  for _, info in ipairs(discard_pile.getObjects()) do
    local data = card_data_for(info.name)
    if data ~= nil and data.type == "animal" then
      for _, icon in ipairs(data.icons or {}) do
        if icon == "petting" then
          wanted[#wanted + 1] = info.guid
          break
        end
      end
    end
  end

  if #wanted == 0 then
    printToAll("There are no Petting Zoo Animals in the discard pile.")
    render_claims_table(player)
    return
  end

  local dealt = {}
  for _, guid in ipairs(wanted) do
    dealt[#dealt + 1] = deal_tagged_card(discard_pile, guid, player.color, 1, "zoo_card")
  end

  local function keep_card(card)
    printToAll(player.steam_name .. " keeps " .. string.sub(card.getName(), 7) ..
      " from the discard pile.")
    render_claims_table(player)
  end

  wait_for_cards_in_hand(player, 1, dealt, function()
    if #dealt == 1 then
      keep_card(dealt[1])
      return
    end
    prompt_keep(player, dealt, 1, function(kept) keep_card(kept[1]) end, true)
  end)
end

function perception(player, count, source)
  local message = string.format("%s performs Perception %d", player.steam_name, count)
  if source ~= nil then message = message .. " from " .. source end
  printToAll(message .. ".")

  deal_cards_to_hand(zoo_deck, count, player, 1, "zoo_card", function(dealt)
    prompt_keep(player, dealt, math.floor(count / 2))
  end)
end


function take_base_conservation_card(player, guid, message)
  local card = deal_tagged_card(base_conservation_deck, guid, player.color, 1,
                                "zoo_card")
  printToAll(message)
  wait_for_cards_in_hand(player, 1, { card }, function()
    render_claims_table(player)
  end)
end

function assertion(player, source)
  local claims = {}
  for _, info in ipairs(base_conservation_deck.getObjects()) do
    local guid = info.guid
    claims[#claims + 1] = {
      button_text = string.sub(info.name, 7),
      source = source,
      optional = false,
      async = true,
      function_call = function()
        take_base_conservation_card(player, guid, player.steam_name ..
          " takes a card from the Base Conservation Projects deck.")
      end,
    }
  end
  create_claims_from_reward_groups(player, {}, true, claims)
end

function base_conservation_card_guid(number)
  for _, info in ipairs(base_conservation_deck.getObjects()) do
    if card_number_of(info.name) == number then return info.guid end
  end
  return nil
end

function dominance(player, source)
  local guid = base_conservation_card_guid(108)
  if guid == nil then
    broadcastToColor("The Primates Base Conservation Project is already in play.",
      player.color, "Red")
    render_claims_table(player)
    return
  end

  take_base_conservation_card(player, guid,
    player.steam_name .. " takes the Primates Base Conservation Project.")
end

function pouch(player, count, source)
  create_card_selection_panel(player,
    function() return Player[player.color].getHandObjects(1) end, count, "pouch",
    function(pouched)
      if pouched then retire_active_claim() end
      render_claims_table(player)
    end, nil, source)
end

function pouch_cards(player, cards, source, callback)
  local entry = player.pouched_cards[source]
  if entry == nil then
    pouch_slot_count = pouch_slot_count + 1
    entry = { slot = pouch_slot_count, guids = {} }
    player.pouched_cards[source] = entry
  end

  local base = cnsts.pouch_base_position
  local positions = {}
  for i, card in ipairs(cards) do
    positions[i] = {
      x = base.x + entry.slot * cnsts.pouch_slot_spacing,
      y = base.y,
      z = base.z + #entry.guids * cnsts.pouch_card_spacing
    }
    table.insert(entry.guids, card.getGUID())
  end

  for i, card in ipairs(cards) do
    card.setPosition(positions[i])
    card.setRotation({ 0, 180, 180 })
    card.interactable = false
    card.locked = true
  end

  refresh_pouch_counter(player)

  if callback ~= nil then
    wait_for_cards_out_of_hand(player, 1, cards, callback)
  end
end

function pouch_counter_card(player)
  for _, guid in ipairs(player.played_sponsors) do
    local obj = getObjectFromGUID(guid)
    if card_number_of(obj.getName()) == cnsts.pouch_counter.card then
      return obj
    end
  end
  return nil
end

function pouch_counter_lines(player)
  local sources = {}
  for source, entry in pairs(player.pouched_cards) do
    sources[#sources + 1] = { source = source, entry = entry }
  end
  table.sort(sources, function(a, b) return a.entry.slot < b.entry.slot end)

  local total, lines = 0, {}
  for _, item in ipairs(sources) do
    total = total + #item.entry.guids
    lines[#lines + 1] = item.source .. ": " .. #item.entry.guids
  end
  return total, lines
end

function refresh_pouch_counter(player)
  local card = pouch_counter_card(player)
  if card == nil then return end

  local spec = cnsts.pouch_counter
  local total, lines = pouch_counter_lines(player)
  card.clearButtons()
  card.createButton({
    label = "Pouched cards: " .. total,
    tooltip = table.concat(lines, "\n"),
    click_function = "null_func",
    function_owner = nil,
    position = spec.position,
    width = spec.width,
    height = spec.height,
    font_size = spec.font_size,
    color = spec.color,
    font_color = spec.font_color,
  })
end

function sunbathing(player, count, source)
  create_card_selection_panel(player,
    function() return Player[player.color].getHandObjects(1) end, count, "sell",
    function(sold)
      if sold then retire_active_claim() end
      render_claims_table(player)
    end, cnsts.sunbathing_sell_value, source)
end

function jumping(player, count, source)
  break_x(count, player)
  update_money(player, count, source and (source .. "'s jumping") or "jumping")
end

function magnet(player, key, source)
  local matches
  if key == "animal" or key == "sponsor" then
    matches = function(data) return data.type == key end
  elseif key == "sea animal" then
    matches = function(data)
      for _, icon in ipairs(data.icons or {}) do
        if icon == "sea" then return true end
      end
      return false
    end
  else
    broadcastToAll("Invalid key given to magnet!", {r=1, g=0, b=0})
    return
  end

  local taken, names = {}, {}
  for i = 1, 6 do
    local card = display_cards[i]
    if card ~= nil and matches(card_data_for(card.getName())) then
      card.locked = false
      card.deal(1, player.color, 1)
      taken[#taken + 1] = card
      names[#names + 1] = string.sub(card.getName(), 7)
      resolve_display_mark(i, false)
      display_cards[i] = nil
    end
  end

  if #taken == 0 then
    render_claims_table(player)
    return
  end

  local message = string.format("%s takes %s from the display with ",
    player.steam_name, table.concat(names, ", "))
  message = message .. (source and (source .. "'s") or "the") .. " "
    .. label_from_key(key) .. " Magnet"
  printToAll(message .. ".")

  wait_for_cards_in_hand(player, 1, taken, function()
    render_claims_table(player)
  end)
end

function wave(player, source)
  printToAll(player.steam_name .. " triggers a wave".. (source~=nil and (" from " .. source) or "")  ..".")

  local leaving = {}
  for i = 1, 6 do
    local card = display_cards[i]
    if card ~= nil then
      printToAll(string.sub(card.getName(), 7) .. " was washed away by the wave!")
      local guid = card.getGUID()
      local marker = redirect_marked_discard(i, card)
      if marker then
        leaving[#leaving + 1] = { guid = guid, color = marker.color }
      else
        leaving[#leaving + 1] = { guid = guid }
        card.locked = false
        discard_pile.putObject(card)
      end
      display_cards[i] = nil
      break
    end
  end

  refill_display(function() render_claims_table(player) end, leaving)
end

function rep_token_position(value, count)
  local pos = getObjectFromGUID(cnsts.rep_zones[value]).getPosition()

  pos.y = (count < 2) and 1.5 or 2
  local sign = (count % 2 == 0) and -1 or 1
  pos.x = pos.x + sign * 0.3

  return pos
end

function get_rep_zone_position(value)
  return rep_token_position(value,
    track_tokens_in(getObjectFromGUID(cnsts.rep_zones[value])))
end

function max_reputation(player)
  return player.cards_flipped and #cnsts.rep_zones or 9
end

function update_rep(player, amount, source)
  local old_rep = get_counter_value(player.rep_counter)
  local new_rep = math.min(max_reputation(player), old_rep + amount)

  set_counter(player.rep_counter, new_rep, cnsts.counter_style.rep)
  move_when_settled(player.reputation_token.getGUID(),
    get_rep_zone_position(new_rep))

  if not player.cards_flipped and new_rep-old_rep < amount then
    broadcastToAll(player.steam_name .. " cannot gain any more reputation!")
  end
  print_track_change(player, new_rep - old_rep, "reputation", source)

  if player.cards_flipped then
    local overflow = (old_rep + amount) - new_rep
    if overflow > 0 then
      offer_rep_overflow(player, overflow)
    end
  end

  local rewards = {}
  for i = old_rep + 1, new_rep do
    table.insert(rewards, cnsts.rep_rewards[i])
  end
  create_claims_from_rewards(player, rewards, "the reputation track")
end

function offer_rep_overflow(player, overflow)
  if overflow <= 0 then return end

  if rep_max_bonus == nil then
    update_appeal(player, overflow, "maxing reputation")
    return
  end

  local bonus_option = bonus_tile_reward(rep_max_bonus)
  if overflow > 1 then
    bonus_option = bonus_option .. " + " .. (overflow - 1) .. " appeal"
  end
  local appeal_option = overflow .. " appeal"

  create_claims_from_rewards(player, { bonus_option, appeal_option }, "maxing reputation", true)
end

function split(s)
  local parts = {}
  for word in s:gmatch("[^ ]+") do
    table.insert(parts, word)
  end
  return parts
end

function split_reward_prefix(reward)
  for _, prefix in ipairs(cnsts.reward_prefixes) do
    if reward:sub(1, #prefix) == prefix then
      return prefix, reward:sub(#prefix + 1)
    end
  end
  return nil, reward
end

function split_combined_reward(reward)
  return reward:match("^(.+) %+ (.+)$")
end

function take_bonus_tile(reward)
  for _, pool in ipairs({ cp_bonuses_5, cp_bonuses_8 }) do
    for i = 1, 2 do
      local tile = pool[i]
      if tile ~= nil and cnsts.bonus_tile_mapping[tile.getGUID()] == reward then
        pool[i] = nil
        return tile
      end
    end
  end

  if rep_max_bonus ~= nil and cnsts.bonus_tile_mapping[rep_max_bonus.getGUID()] == reward then
    local tile = rep_max_bonus
    rep_max_bonus = nil
    return tile
  end

  return nil
end

function claim_bonus_tile(reward)
  set_tile_face(take_bonus_tile(reward), true)
end


function bonus_token_position(player, index)
  return board_relative_world_position(player.player_board.getPosition(),
    "bonus_tile_" .. index)
end

function bonus_token_guid(player, reward)
  for _, guid in ipairs(player.bonus_tiles) do
    if cnsts.bonus_tile_mapping[guid] == reward then return guid end
  end
  return nil
end

function take_bonus_token(player, reward, key)
  local spec = cnsts.bonus_tokens[key]

  local tile = take_bonus_tile(reward)
  if tile ~= nil then
    player.bonus_tiles[#player.bonus_tiles + 1] = tile.getGUID()
    tile.setPositionSmooth(bonus_token_position(player, #player.bonus_tiles), false, false)
  end

  printToAll(string.format("%s picks the %s token.", player.steam_name,
    spec.label or reward_button_text(key, player)))

  if spec.persistent then player.persistent_rewards[spec.persistent] = true end
  if spec.flag then player[spec.flag] = true end

  if key == "snap hand size" then
    snap(player, 1)
    return
  end

  render_claims_table(player)
end

function spend_bonus_token(player, reward)
  local guid = bonus_token_guid(player, reward)
  if guid == nil then return end

  for i, held in ipairs(player.bonus_tiles) do
    if held == guid then
      table.remove(player.bonus_tiles, i)
      local tile = getObjectFromGUID(guid)
      if tile ~= nil then tile.destruct() end
      for j = i, #player.bonus_tiles do
        local moved = getObjectFromGUID(player.bonus_tiles[j])
        if moved ~= nil then
          moved.setPositionSmooth(bonus_token_position(player, j), false, false)
        end
      end
      return
    end
  end
end

function apply_reward_string(player, reward, source)
  reward = effective_reward(reward)

  local combined_first, combined_second = split_combined_reward(reward)
  if combined_first ~= nil then
    assert(is_reward_sync(combined_second),
      "combined reward: the second half must be sync, got " .. combined_second)

    if is_reward_sync(combined_first) then
      apply_reward_string(player, combined_first, source)
      apply_reward_string(player, combined_second, source)
      return
    end

    local appeal = {}
    append_reward_claims(appeal, player, { combined_second }, source)
    table.insert(player.claims, appeal)

    apply_reward_string(player, combined_first, source)
    return
  end

  local prefix, rest = split_reward_prefix(reward)
  if prefix == "BONUS: " then
    claim_bonus_tile(reward)
    apply_reward_string(player, rest, source)
    return
  end
  if prefix == "TOKEN: " then
    take_bonus_token(player, reward, rest)
    return
  end

  local absorbed, completed = absorb_reward(player, reward, source)
  if absorbed then
    if completed ~= nil then
      create_claims_from_rewards(player, { completed }, source)
    end
    return
  end

  local parts = split(reward)
  local last_word = parts[#parts]
  local last_num = tonumber(last_word)

  if last_num ~= nil then
    local without_last = reward:sub(1, #reward - #last_word - 1)
    _G[(without_last:gsub(" ", "_"))](player, last_num, source)
  else
    local first_word = parts[1]
    local first_num = tonumber(first_word)
    local without_first = reward:sub(#first_word + 2)
    if first_num ~= nil then
      _G["update_" .. (without_first:gsub(" ", "_"))](player, first_num, source)
    elseif first_word == "free" then
      free_building(player, without_first, source)
    elseif last_word == "magnet" then
      magnet(player, reward:sub(1, #reward - #last_word - 1), source)
    elseif first_word == "search" then
      search(player, (without_first:gsub(" ", "_")), source,
        function() render_claims_table(player) end)
    else
      _G[(reward:gsub(" ", "_"))](player, source)
    end
  end
end

local LIVE_PAYOUT = {
  ["pack"] = function(p)
    return get_icon_counter_value(p.icon_counters["predator"]) .. " appeal"
  end,
  ["release of patents"] = function(p)
    return release_of_patents_cp(p) .. " cp"
  end,
  ["basic research"] = function(p)
    return basic_research_cp(p) .. " cp"
  end,
  ["management rep"] = function(p)
    return management_rep_amount(p) .. " rep"
  end,
}

local LIVE_PAYOUT_NAMES = {
  ["pack"] = "Pack",
  ["management rep"] = function(player, payout)
    local icons = get_icon_counter_value(player.icon_counters.research)
    return string.format("%d Research %s:\n%s",
      icons, icons == 1 and "Icon" or "Icons", payout)
  end,
}

local SETTLED_AT_CLAIM = {
  ["explorer money"] = function(p)
    return explorer_money_amount(p) .. " money"
  end,
  ["diversity researcher money"] = function(p)
    return diversity_researcher_money_amount(p) .. " money"
  end,
  ["geologist appeal"] = function(p)
    return math.floor(get_icon_counter_value(p.icon_counters["rock"]) / 2) * 3
      .. " appeal"
  end,
  ["hydrologist appeal"] = function(p)
    return get_icon_counter_value(p.icon_counters["water"]) .. " appeal"
  end,

  ["farm cat"] = function(p)
    return farm_cat_appeal(p) .. " appeal"
  end,
  ["new world monkeys"] = function(p)
    local _, adjacent = p.map:countUnclaimedRewards()
    return adjacent .. " appeal"
  end,
  ["native farm animals"] = function(p)
    return p.map:countUnoccupiedBorderAdjacentToTile() .. " appeal"
  end,
  ["native seabirds"] = function(p)
    return p.map:countUncoveredTerrainAdjacentToTile("water") .. " appeal"
  end,
  ["native lizards"] = function(p)
    return p.map:countUncoveredTerrainAdjacentToTile("rock") .. " appeal"
  end,
}

function settled_reward_string(player, reward)
  if player == nil or reward == nil then return nil end
  local settle = SETTLED_AT_CLAIM[reward]
  if settle == nil then return nil end
  return settle(player)
end

local VARIABLE_ICON_COUNT = {
  ["hunter"] = function(p)
    return get_icon_counter_value(p.icon_counters["predator"])
  end,
  ["scuba dive"] = function(p) return scuba_dive_count(p) end,
}

function source_label(source)
  return cnsts.source_labels[source] or source
end

function reward_button_text(reward, player, source, show_source)
  reward = effective_reward(reward)
  if show_source then
    return reward_button_text(reward, player) .. "\n(" .. source_label(source) .. ")"
  end

  local combined_first, combined_second = split_combined_reward(reward)
  if combined_first ~= nil then
    return reward_button_text(combined_first, player) .. " + " ..
      reward_button_text(combined_second, player)
  end

  local prefix, unprefixed = split_reward_prefix(reward)
  if prefix == "TOKEN: " then
    local spec = cnsts.bonus_tokens[unprefixed]
    if spec ~= nil and spec.label ~= nil then return spec.label end
    return reward_button_text(unprefixed, player) .. " Token"
  end
  if unprefixed ~= reward then
    return reward_button_text(unprefixed, player)
  end

  local inventive_arg = reward:match("^inventive (%S+)$")
  if inventive_arg then
    local tokens = tonumber(inventive_arg)
    if inventive_arg == "bear" then
      tokens = inventive_bear_count()
    elseif inventive_arg == "primate" and player ~= nil then
      tokens = inventive_primate_count(player)
    end
    if tokens ~= nil then
      return reward_button_text(tokens .. " x_token")
    end
  end

  local draw_count = reward:match("^draw (%d+)$")
  if draw_count then
    return "Draw " .. draw_count .. " (rep-range/deck)"
  end

  if reward == "draw t1 unlock" then
    return reward_button_text("draw 1")
  end

  if reward == "card flip b" then
    return reward_button_text("card flip")
  end

  local variable_name, variable_count = reward:match("^(.-) (%d+)$")
  local live_count = variable_count == "0" and VARIABLE_ICON_COUNT[variable_name]
  if live_count then
    local label = reward_button_text(variable_name)
    if player == nil then return label .. " X" end
    return label .. " " .. live_count(player)
  end

  if reward == "clever 1" then
    return "Clever"
  end

  if reward == "paid clever" then
    return "Pay 2 Money for Clever"
  end

  if reward == "donate" and player ~= nil then
    return "Donate (" .. donation_cost(player) .. " Money)"
  end

  local pouch_count = reward:match("^pouch (%d+)$")
  if pouch_count ~= nil and source ~= nil then
    return "Pouch " .. pouch_count .. "\n(" .. source_label(source) .. ")"
  end

  if source == cnsts.landscape_gardener_name and reward:match("^%d+ x_token$") then
    return reward_button_text(reward, player) .. "\n(" .. source .. ")"
  end

  if reward == "trade" then
    return "Trade: X-token \u{2194} 5 Money"
  end

  local keyword, action_name = reward:match("^(action) (%S+)$")
  if keyword == nil then
    keyword, action_name = reward:match("^(boost) (%S+)$")
  end
  if keyword == nil then
    keyword, action_name = reward:match("^(multiplier) (%S+)$")
  end
  if keyword ~= nil then
    return reward_button_text(keyword) .. ": " .. reward_button_text(action_name)
  end

  if reward == "multiplier_token" then
    return "Place a Multiplier Token"
  end

  local payout = LIVE_PAYOUT[reward]
  if payout ~= nil and player ~= nil then
    local text = reward_button_text(payout(player))
    local name = LIVE_PAYOUT_NAMES[reward]
    if type(name) == "function" then return name(player, text) end
    if name ~= nil then return name .. " (" .. text .. ")" end
    return text
  end

  local iconic_habitat = reward:match("^iconic (%S+)$")
  if iconic_habitat then
    return "Iconic Animal: " .. reward_button_text(iconic_count(iconic_habitat) .. " appeal")
  end

  if reward == "reptile house or aviary" then
    return "Reptile House or\nLarge Bird Aviary"
  end

  local count, unit = reward:match("^(%d+) (%S+)$")
  if count then
    local forms = cnsts.reward_units[unit]
    if forms then
      return count .. " " .. (tonumber(count) == 1 and forms.one or forms.many)
    end
  end

  local words = {}
  for word in reward:gmatch("%S+") do
    if word == "cp" then
      words[#words + 1] = "conservation"
      words[#words + 1] = "point"
    else
      words[#words + 1] = word
    end
  end

  for i, word in ipairs(words) do
    local first = word:sub(1, 1)
    if first:match("%a") then
      words[i] = first:upper() .. word:sub(2)
    end
  end
  return table.concat(words, " ")
end

function is_reward_optional(reward)
  local prefix, rest = split_reward_prefix(reward)

  if prefix == "TOKEN: " then return false end

  return rest:match("^digging %d+$") ~= nil
    or rest:match("^glide %d+$") ~= nil
    or rest:match("^pouch %d+$") ~= nil
    or rest:match("^sunbathing %d+$") ~= nil
    or rest:match("^posturing %d+$") ~= nil
    or rest:match("^free %S+$") ~= nil
    or rest == "peacocking"
    or rest == "marketing"
    or rest == "play person sponsor"
    or rest == "trade"
    or rest == "cut down"
    or rest == "reconstruction"
    or rest == "expand enclosure"
    or rest == "donate"
    or rest == "extra shift"
end

function is_reward_sync(reward)
  local combined_first, combined_second = split_combined_reward(reward)
  if combined_first ~= nil then
    return is_reward_sync(combined_first) and is_reward_sync(combined_second)
  end

  local prefix, rest = split_reward_prefix(reward)

  if prefix == "TOKEN: " then return false end

  return rest:match("^%d+ appeal$") ~= nil
    or rest:match("^%d+ money$") ~= nil
    or rest:match("^%d+ x_token$") ~= nil
    or rest:match("^inventive %S+$") ~= nil
    or rest:match("^multiplier %S+$") ~= nil
    or rest:match("^jumping %d+$") ~= nil
    or rest:match("^venom %d+$") ~= nil
    or rest == "constriction"
    or rest == "pack"
    or is_absorbed_reward(rest)
    or rest:match("^iconic %S+$") ~= nil
end

function counter_value_for_reward_key(player, key)
  for _, icon in ipairs(cnsts.icons.all) do
    if icon == key then
      return get_icon_counter_value(player.icon_counters[key])
    end
  end
  if key == "university" then
    return #player.acquired_universities
  end
  if key == "small_animals" then
    return count_played_animals(player, function(card) return card.size <= 2 end)
  end
  if key == "large_animals" then
    return count_played_animals(player, function(card) return card.size >= 4 end)
  end
  if key == "pavilion" then
    return #player.map:tilesWithTag("pavilion")
  end
  if key == "projects_supported" then
    return projects_supported(player)
  end
  if key == "x_token" then
    return #player.x_tokens
  end
  if key == "rock_water_pairs" then
    return math.min(get_icon_counter_value(player.icon_counters["rock"]),
                    get_icon_counter_value(player.icon_counters["water"]))
  end
  error("counter_value_for_reward_key: no counter named '" .. tostring(key) .. "'", 2)
end

function count_played_animals(player, matches)
  local count = 0
  for _, guid in ipairs(player.played_animals) do
    if matches(card_data_for(getObjectFromGUID(guid).getName())) then
      count = count + 1
    end
  end
  for _, data in ipairs(rescued_animals(player)) do
    if matches(data) then count = count + 1 end
  end
  return count
end

function projects_supported(player)
  local count = 0
  for i = 1, cnsts.project_cube_count do
    if player.project_cubes[i] == nil then count = count + 1 end
  end
  return count
end

function project_cubes_left(player)
  return cnsts.project_cube_count - projects_supported(player)
end

function effective_reward(reward)
  if reward == nil or interactive_effects ~= false then return reward end

  local head, number = reward:match("^(%a+) (%d+)$")
  if head == nil then head, number = reward:match("^(%a+)$"), nil end
  local mapped = head ~= nil and cnsts.non_interactive_rewards[head] or nil
  if mapped == nil then return reward end

  if mapped.count == "drop" then return mapped.head end
  if mapped.count == "one" then return mapped.head .. " 1" end
  return mapped.head .. " " .. tostring(number)
end

function reward_string_from_key(player, reward_key, reward_value)
  return effective_reward(
    raw_reward_string_from_key(player, reward_key, reward_value))
end

function raw_reward_string_from_key(player, reward_key, reward_value)
  if type(reward_key) == "number" then
    if reward_value == "okapi stable marketing" then
      return #player.okapi_stable > 0 and "marketing" or nil
    end
    return reward_value
  end
  local index = counter_value_for_reward_key(player, reward_key)
  if index == nil or index == 0 then
    return nil
  end
  return reward_value[math.min(index, #reward_value)]
end

function move_post_action_reward(player, reward, source)
  local clever_num = reward:match("^clever (%d+)$")
  if clever_num then
    for _ = 1, tonumber(clever_num) do
      table.insert(player.post_action_rewards, { "clever", source })
    end
    return true
  end

  if reward:match("^action %S+$") or reward:match("^boost %S+$")
     or reward == "determination" or reward == "mark" then
    table.insert(player.post_action_rewards, { reward, source })
    return true
  end

  return false
end

function is_post_action_reward(reward)
  return reward:match("^clever %d+$") ~= nil
    or reward:match("^action %S+$") ~= nil
    or reward:match("^boost %S+$") ~= nil
    or reward == "determination"
    or reward == "mark"
end

function banks_post_action_reward(reward)
  if income_phase_order == nil then return true end
  return reward:match("^clever %d+$") == nil and reward ~= "mark"
end

function reward_offers(reward)
  local count = tonumber(reward:match("^clever (%d+)$") or "")
  if count == nil then return { reward } end
  local out = {}
  for _ = 1, count do out[#out + 1] = "clever 1" end
  return out
end

function partial_reward_base(reward)
  local last_word = reward:match("%S+$")
  local last_num = tonumber(last_word or "")
  if last_num == nil or last_num % 1 == 0 then return nil end
  return (reward:sub(1, #reward - #last_word - 1):gsub(" ", "_"))
end

function bank_partial_reward(player, base)
  local whole = (base:gsub("_", " "))
  if player.partial_rewards[base] then
    player.partial_rewards[base] = nil
    return whole
  end
  player.partial_rewards[base] = true
  return nil
end

function absorb_reward(player, reward, source)
  if reward == "camouflage" then
    player.camouflage = (player.camouflage or 0) + 1
    return true
  end

  if reward == "artificial intelligence" then
    artificial_intelligence(player, source)
    return true
  end

  local base = partial_reward_base(reward)
  if base ~= nil then
    return true, bank_partial_reward(player, base)
  end

  if not banks_post_action_reward(reward) then return false end
  return move_post_action_reward(player, reward, source)
end

function is_absorbed_reward(reward)
  return reward == "camouflage"
    or reward == "artificial intelligence"
    or partial_reward_base(reward) ~= nil
    or (banks_post_action_reward(reward) and is_post_action_reward(reward))
end

function place_card_cubes(player, card, spots)
  local guids = {}
  for i, spot in ipairs(spots) do
    local pos = card_relative_world_position(card, spot)
    guids[i] = take_player_cube(player,
      { x = pos.x, y = pos.y + cnsts.drop_height, z = pos.z }).getGUID()
  end
  return guids
end

function process_effects(player, effect_string, remove, card)
  if cnsts.board_read_specials[effect_string] then return nil end

  local granted

  if effect_string == "commercial harbor" then
    player.persistent_rewards.commercial_harbor_effect = (remove == nil) or nil
  elseif effect_string == "artificial intelligence" then
    if remove == nil then
      add_ai_cube(player, 4)
    else
      getObjectFromGUID(table.remove(player.map_artificial_intelligence)).destruct()
    end
  elseif cnsts.incremental_effects[effect_string] then
    local spec = cnsts.incremental_effects[effect_string]
    local before = player[spec.attr_name] or 0
    local after = remove == nil and math.min(before + 1, spec.cap)
                                or math.max(before - 1, 0)
    player[spec.attr_name] = after
    local source = label_from_key(effect_string)

    if spec.reward == nil then
    elseif remove == nil then
      local pays = spec.on_cap and (before < spec.cap and after == spec.cap)
                or (not spec.on_cap)
      if pays and not (spec.blocked_by_reconstruction and player.reconstruction) then
        granted = spec.reward
        if spec.income then add_income(player, spec.reward, source) end
      end
    elseif spec.income and before == spec.cap and after < spec.cap then
      remove_income(player, spec.reward, source)
    end
  elseif cnsts.card_cube_effects[effect_string] then
    local attr = to_attribute_name(effect_string)
    if remove == nil then
      player[attr] = place_card_cubes(player, card,
        cnsts.card_cube_effects[effect_string])
    else
      for _, guid in ipairs(player[attr] or {}) do
        getObjectFromGUID(guid).destruct()
      end
      player[attr] = nil
    end
  elseif cnsts.record_effects[effect_string] then
    player[to_attribute_name(effect_string)] = (remove == nil) and {} or nil
  elseif cnsts.remapped_effects[effect_string] then
    player[cnsts.remapped_effects[effect_string]] = (remove == nil) or nil
  else
    player[to_attribute_name(effect_string)] = (remove == nil) or nil
  end

  refresh_map_income(player)
  return granted
end

function add_remove_hooks(player, source, self_hooks, all_hooks, remove)
  if self_hooks then
    for icon_type, reward in pairs(self_hooks) do
      local entry_table = player.hooks[icon_type] or {}
      if not remove then
        table.insert(entry_table, {reward, source})
      else
        local index_to_remove = nil
        for i, reward_source_pair in ipairs(entry_table) do
          if reward_source_pair[2] == source then
            index_to_remove = i
            break
          end
        end
        if index_to_remove then table.remove(entry_table, index_to_remove) end
      end
      player.hooks[icon_type] = entry_table
    end
  end

  if all_hooks then
    for icon_type, reward in pairs(all_hooks) do
      if not remove then
        all_zoo_hooks[icon_type] = {player.color, reward, source}
      else
        all_zoo_hooks[icon_type] = nil
      end
    end
  end
end

function apply_hooks(player, icon_table)
  local reward_table = {}
  for _,icon_str in ipairs(icon_table) do
    if all_zoo_hooks[icon_str] ~= nil then
      for _, p in ipairs(players) do
        if p.color == all_zoo_hooks[icon_str][1] then
          apply_reward_string(p, all_zoo_hooks[icon_str][2], all_zoo_hooks[icon_str][3])
          break
        end
      end
    end

    if player.hooks[icon_str] ~= nil then
      for _, hook_source in ipairs(player.hooks[icon_str]) do
        table.insert(reward_table, {hook_source[1], hook_source[2]})
      end
    end
  end
  return reward_table
end

function add_remove_icons(player, icon_table, remove)
  local function icon_style(icon_type)
    return (icon_type == "rock" or icon_type == "water") and cnsts.counter_style.icon_terrain or cnsts.counter_style.icon
  end

  if remove then
    for _, icon_str in ipairs(icon_table) do
      local prev = get_icon_counter_value(player.icon_counters[icon_str])
      set_icon_counter(player.icon_counters[icon_str], prev - 1, icon_style(icon_str))
      adjust_sponsorship_income(player, icon_str, prev, prev - 1)
    end
    return
  end

  local reward_table = {}
  local explorer_exclude = {rock=true, water=true, research=true}
  for _, icon_str in ipairs(icon_table) do
    local counter_prev_val = get_icon_counter_value(player.icon_counters[icon_str])
    if player.explorer and not explorer_exclude[icon_str] and counter_prev_val == 0 then
      table.insert(reward_table, {"2 money + 1 appeal", "Explorer"})
    end
    set_icon_counter(player.icon_counters[icon_str], counter_prev_val + 1, icon_style(icon_str))
    adjust_sponsorship_income(player, icon_str, counter_prev_val, counter_prev_val + 1)
  end

  for _, r in ipairs(apply_hooks(player, icon_table)) do
    table.insert(reward_table, r)
  end
  return reward_table
end

function append_icon_groups(groups, player, icons)
  for _, entry in ipairs(add_remove_icons(player, icons or {})) do
    groups[#groups + 1] =
      { rewards = { entry[1] }, source = entry[2], show_source = true }
  end
  return groups
end

function append_reward_claims(sub_table, player, rewards, source, grouped, show_source)
  for reward_key, reward_value in pairs(rewards) do
    if reward_value ~= "" then
      local initial_reward = reward_string_from_key(player, reward_key, reward_value)

      local settled = settled_reward_string(player, initial_reward)
      if settled ~= nil then initial_reward = settled end

      local diverted, completed = false, nil
      if initial_reward ~= nil and not grouped then
        diverted, completed = absorb_reward(player, initial_reward, source)
      end

      if completed ~= nil then
        append_reward_claims(sub_table, player, { completed }, source, grouped,
                             show_source)
      end

      if not diverted then
        table.insert(sub_table, {
          button_text = function()
            local reward = settled or reward_string_from_key(player, reward_key, reward_value)
            return reward and reward_button_text(reward, player, source, show_source)
          end,
          source = source,
          optional = initial_reward ~= nil and is_reward_optional(initial_reward),
          async = initial_reward == nil or not is_reward_sync(initial_reward),
          valid = function()
            return settled ~= nil
              or reward_string_from_key(player, reward_key, reward_value) ~= nil
          end,
          function_call = function()
            apply_reward_string(player,
              settled or reward_string_from_key(player, reward_key, reward_value), source)
          end
        })
      end
    end
  end

end

function create_claims_from_reward_groups(player, groups, grouped, extra_claims)
  local sub_table = {}
  for _, group in ipairs(groups) do
    append_reward_claims(sub_table, player, group.rewards, group.source, grouped,
                         group.show_source)
  end
  for _, claim in ipairs(extra_claims or {}) do
    table.insert(sub_table, claim)
  end

  sub_table.from_persistent = persistent_origin or nil
  sub_table.grouped = grouped
  table.insert(player.claims, sub_table)
  render_claims_table(player)
end

function create_claims_from_rewards(player, rewards, source, grouped)
  create_claims_from_reward_groups(player, { { rewards = rewards, source = source } }, grouped)
end

function revealed_cards_line(names, what)
  local count = #names
  local subject = (count == 1) and "1 card was " or (count .. " cards were ")
  if count == 0 then
    return subject .. what .. "."
  end
  return subject .. what .. ": " .. table.concat(names, ", ") .. "."
end

function card_matches_search_key(card_data, key)
  if card_data == nil then return false end

  if key == "person_sponsor" then return card_data.person == true end
  if key == "sponsor" then return card_data.type == "sponsor" end
  if key == "small_animal" then
    return card_data.type == "animal" and card_data.size <= 2
  end
  if key == "large_animal" then
    return card_data.type == "animal" and card_data.size >= 4
  end

  for _, icon in ipairs(card_data.icons or {}) do
    if icon == key then return true end
  end
  return false
end

function bottom_revealed_card(top_info)
  zoo_deck.takeObject({ guid = top_info.guid, position = zoo_deck.getPosition(), smooth = false })
end

function discard_revealed_card(top_info)
  local discard_pos = getObjectFromGUID(cnsts.discard_pile_zone).getPosition()
  zoo_deck.takeObject({
    guid = top_info.guid,
    position = {
      x = discard_pos.x,
      y = discard_pos.y + cnsts.discard_drop_height,
      z = discard_pos.z,
    },
    rotation = discard_face_down and { 0, 180, 180 } or { 0, 180, 0 },
    smooth = false,
  })
end

function run_search(player, key, dispose, disposal, callback)
  local revealed = {}
  while true do
    local top_info = zoo_deck.getObjects()[1]
    local number = tonumber(string.sub(top_info.name, 2, 4))
    local card_data = (marine_worlds_enabled and cnsts.cards.mw[number]) or cnsts.cards.base[number]

    if card_matches_search_key(card_data, key) then
      local card = deal_tagged_card(zoo_deck, top_info.guid, player.color, 1, "zoo_card")
      printToAll(revealed_cards_line(revealed, disposal))
      printToAll(player.steam_name .. " has found the card "
        .. string.sub(top_info.name, 7) .. ".")
      if callback ~= nil then
        wait_for_cards_in_hand(player, 1, { card }, callback)
      end
      return
    end

    dispose(top_info)
    table.insert(revealed, string.sub(top_info.name, 7))
  end
end

function search(player, key, source, callback)
  local message = player.steam_name .. " searches for a " .. label_from_key(key) .. " card"
  if source ~= nil then message = message .. " from " .. source end
  printToAll(message .. ".")

  run_search(player, key, bottom_revealed_card,
    "placed on the bottom of the deck", callback)
end

function discard_search(player, key, source, callback)
  local message = player.steam_name .. " searches for a " .. label_from_key(key) .. " card"
  if source ~= nil then message = message .. " from " .. source end
  printToAll(message .. ".")

  run_search(player, key, discard_revealed_card, "discarded", callback)
end

function sponsor_search(player, source)
  local message = player.steam_name .. " searches for a sponsor card"
  if source ~= nil then message = message .. " with the " .. source .. " effect" end
  printToAll(message .. ".")

  run_search(player, "sponsor", discard_revealed_card, "discarded", function()
    render_claims_table(player)
  end)
end

function monkey_gang(player, source)
  search(player, "primate", (source and source .. "'s " or "") .. "Monkey Gang", function()
    render_claims_table(player)
  end)
end

function report_discard(player, cards, reveal)
  if discard_face_down and not reveal then
    printToAll(player.steam_name .. " has discarded " .. #cards .. " cards.")
  else
    local names = {}
    for _, card in ipairs(cards) do
      table.insert(names, string.sub(card.getName(), 7))
    end
    printToAll(player.steam_name .. " has discarded " .. table.concat(names, ", ") .. ".")
  end
end

function move_cards_to_discard(cards)
  for _, card in ipairs(cards) do
    discard_pile.putObject(card)
  end
end

function discard_cards(player, cards, callback, reveal)
  report_discard(player, cards, reveal)
  move_cards_to_discard(cards)

  if callback ~= nil then
    wait_for_cards_out_of_hand(player, 1, cards, callback)
  end
end

function discard_cards_to_new_pile(player, cards, pile)
  report_discard(player, cards)
  local rot = discard_face_down and { 0, 180, 180 } or { 0, 180, 0 }
  for _, card in ipairs(cards) do
    if pile == nil then
      pile = card
    elseif pile.tag == "Card" then
      pile = pile.putObject(card)
      pile.setPosition(getObjectFromGUID(cnsts.discard_pile_zone).getPosition())
      pile.setRotation(rot)
    else
      pile = pile.putObject(card)
    end
  end
  return pile
end

function discard_final_scoring_cards(player, cards)
  local remaining = #Player[player.color].getHandObjects(2) - #cards
  for _, card in ipairs(cards) do
    card.removeTag("final_scoring")
  end

  wait_for_hand_count(player, 2, remaining, function()
    local zone = getObjectFromGUID(cnsts.final_scoring_discard_zone)
    local target = zone.getPosition()
    local rot = { 0, 180, 180 }

    local pile = getDeck(zone)
    local before = 0
    if pile ~= nil then
      before = (pile.tag == "Deck") and pile.getQuantity() or 1
    end

    local rest = cards
    if pile == nil then
      pile = cards[1]
      rest = {}
      for i = 2, #cards do table.insert(rest, cards[i]) end
    end

    for _, card in ipairs(rest) do
      pile = pile.putObject(card)
    end
    pile.setPosition(target)
    pile.setRotation(rot)

    local expected = before + #cards
    if expected == 1 then
      Wait.condition(
        function() pile.interactable = false end,
        function() return not pile.isSmoothMoving() end
      )
      return
    end

    Wait.condition(
      function() getByType(zone, "Deck").interactable = false end,
      function()
        local deck = getByType(zone, "Deck")
        return deck ~= nil and deck.getQuantity() == expected
      end
    )
  end)
end

function player_map_tiles(player)
  local bounds = player.player_board.getBoundsNormalized()
  local min_x, max_x = bounds.center.x - bounds.size.x / 2, bounds.center.x + bounds.size.x / 2
  local min_z, max_z = bounds.center.z - bounds.size.z / 2, bounds.center.z + bounds.size.z / 2

  local tiles = {}
  for _, obj in ipairs(getObjectsWithTag("zoo_map")) do
    local pos = obj.getPosition()
    if pos.x >= min_x and pos.x <= max_x and pos.z >= min_z and pos.z <= max_z then
      table.insert(tiles, obj)
    end
  end
  return tiles
end

function count_player_maps(player)
  return #player_map_tiles(player)
end

function to_attribute_name(name)
  return (string.lower(name):gsub(" ", "_"))
end

local SHARED_MAP_KEYS = { map_0 = true, map_A = true, map_T1 = true }

function player_map_attribute_name(tile_name, canonical_key)
  if SHARED_MAP_KEYS[canonical_key] then
    return canonical_key
  end
  return "map_" .. to_attribute_name(tile_name)
end

function map_tile_name_for(canonical_key)
  for name, keys in pairs(cnsts.map_keys) do
    if keys.top == canonical_key or keys.bottom == canonical_key then
      return name
    end
  end
end

function apply_player_map(player)
  for _, obj in ipairs(player_map_tiles(player)) do
    local keys = player.classic_map_choice or cnsts.map_keys[obj.getName()]
    local canonical_key = obj.is_face_down and keys.bottom or keys.top

    local tile_custom = obj.getCustomObject()
    local map_image = obj.is_face_down and tile_custom.image_bottom or tile_custom.image
    if map_image == nil or map_image == "" then
      broadcastToAll("Could not read a map image off " .. obj.getName() ..
        (obj.is_face_down and " (back)." or " (front)."), "Red")
    end

    apply_map_choice(player, canonical_key, map_image)
    break
  end
end

function apply_map_choice(player, canonical_key, map_image)
  local board_pos = player.player_board.getPosition()
  local tile_name = map_tile_name_for(canonical_key)
  local data = cnsts.map_data[canonical_key]

  local board_obj = player.player_board.getCustomObject()
  board_obj.image = map_image
  player.player_board.setCustomObject(board_obj)
  player.player_board = player.player_board.reload()
  player.map = HexBoard.Board.new(data.cells)
  player.building_tiles = {}
  player.project_cubes = {}
  player.hooks = {}
  player.played_animals = {}
  player.played_sponsors = {}
  player.map_key = canonical_key
  local map_attribute_name = player_map_attribute_name(tile_name, canonical_key)
  if cnsts.listed_map_attributes[map_attribute_name] then
    player[map_attribute_name] = {}
  elseif cnsts.counted_map_attributes[map_attribute_name] then
    player[map_attribute_name] = 0
  else
    player[map_attribute_name] = true
  end
  spawn_player_starting_tiles(player, board_pos)
  spawn_player_project_bonus_cubes(player, board_pos, data.project_rewards)
  if player.map_geographical_zoo then
    spawn_player_geographical_cubes(player, board_pos)
  end
  spawn_player_workers(player, board_pos)
end

function spawn_player_starting_tiles(player, board_pos)
  for _, tile in pairs(player.map.tiles) do
    local tag = tile.tags.type
    if tag ~= nil then
      spawn_starting_tile(tag, tile, board_pos, player.building_tiles)
    end
  end
end

function take_cube(position)
  local cube = bags.cubes.takeObject({ position = position, smooth = false })
  cube.interactable = false
  return cube
end

function take_player_cube(player, position)
  local cube = take_cube(position)
  cube.setColorTint(Color.fromString(player.color))
  cube.addTag(player.color)
  return cube
end

function cube_owner_color(cube)
  for _, tag in ipairs(cube.getTags()) do
    if tag ~= "cube" then return tag end
  end
  return nil
end

function spawn_player_project_bonus_cubes(player, board_pos, project_rewards)
  local pos = board_relative_world_position(board_pos, "project_bonus_1")
  for i = 1, cnsts.project_cube_count do
    if i > 1 then
      local same_color = project_rewards[i][2] == project_rewards[i - 1][2]
      local step = same_color and cnsts.board_relative_positions.project_bonus_z_step_same_color
        or cnsts.board_relative_positions.project_bonus_z_step_diff_color
      pos = pos + step
    end
    player.project_cubes[i] = take_player_cube(player, pos).getGUID()
  end
end

function add_ai_cube(player, cap)
  local cubes = player.map_artificial_intelligence
  if #cubes >= cap then return end

  local pos = board_relative_world_position(player.player_board.getPosition(), "ai_cube_1_pos")
  for _ = 1, cnsts.ai_cube_steps[#cubes + 1] do
    pos = pos + cnsts.board_relative_positions.ai_cube_x_step
  end

  cubes[#cubes + 1] = take_player_cube(player, pos).getGUID()
end

function artificial_intelligence(player, source)
  process_effects(player, "artificial intelligence")
end

function spawn_player_geographical_cubes(player, board_pos)
  player.geographical_cubes = {}
  for _, location in ipairs(cnsts.icons.habitat) do
    player.geographical_cubes[location] = take_player_cube(player,
      board_relative_world_position(board_pos, "geographical_" .. location)).getGUID()
  end
end

function geographical_zoo_reward(player, card, options)
  if player.geographical_cubes == nil then return nil end

  for _, icon in ipairs(card.icons or {}) do
    if player.geographical_cubes[icon] ~= nil then
      for _, option in ipairs(options) do
        if player.map:tileCoversSpecial(option.id, "geographical " .. icon) then
          spend_geographical_cube(player, icon)
          return icon
        end
      end
    end
  end

  return nil
end

function spend_geographical_cube(player, habitat)
  getObjectFromGUID(player.geographical_cubes[habitat]).destruct()
  player.geographical_cubes[habitat] = nil
end

function geographical_cube_groups(player, habitat, source)
  local groups = { { rewards = { "geographical " .. habitat }, source = source } }
  if next(player.geographical_cubes) == nil then
    groups[#groups + 1] =
      { rewards = { "1 cp" }, source = "collecting all Geographical Zoo cubes" }
  end
  return groups
end

geographical_cube_picks = {}

function geographical_cube_panel_xml(color, state)
  local body = [[<Text fontSize="18" color="#FFFFFF">Choose a Geographical Zoo cube to remove:</Text>
    <Text fontSize="18" color="#FFFFFF"></Text>]]
  local height = 16 + 50 + 30 + 12

  for _, habitat in ipairs(cnsts.icons.habitat) do
    if state.player.geographical_cubes[habitat] ~= nil then
      body = body .. string.format([[
        <Button id="geographicalCubeButton_%s_%s" onClick="on_geographical_cube_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">%s</Button>
      ]], color, habitat, color .. "|" .. habitat, habitat_label(habitat))
      height = height + 40
    end
  end

  return string.format([[
    <Panel id="geographicalCubePanel_%s" visibility="%s" rectAlignment="MiddleRight" width="280" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="UpperCenter" childForceExpandHeight="false">
        %s
      </VerticalLayout>
    </Panel>
  ]], color, color, height, body)
end

function render_geographical_cube_panel(player)
  set_player_panel(player.color,
    geographical_cube_panel_xml(player.color, geographical_cube_picks[player.color]))
end

function geographical_zoo_cube(player, source)
  if next(player.geographical_cubes) == nil then
    broadcastToColor("You have no Geographical Zoo cubes left!", player.color, "Red")
    render_claims_table(player)
    return
  end

  geographical_cube_picks[player.color] = { player = player, source = source }
  render_geographical_cube_panel(player)
end

function on_geographical_cube_clicked(_, value, _)
  local color, habitat = value:match("^(%a+)|(%a+)$")
  local state = geographical_cube_picks[color]
  if state == nil then return end

  local player = state.player
  geographical_cube_picks[color] = nil
  clear_player_panel(color)

  spend_geographical_cube(player, habitat)
  create_claims_from_reward_groups(player,
    geographical_cube_groups(player, habitat, state.source), false)
end

function geographical(player, habitat, source)
  create_claims_from_rewards(player,
    { "1 rep", "4 money", "clever 1", "2 appeal", "posturing 1" },
    (source and (source .. "'s ") or "") .. "Geographical " .. habitat_label(habitat),
    true)
end

function geographical_africa(player, source)    geographical(player, "africa", source) end
function geographical_america(player, source)   geographical(player, "america", source) end
function geographical_asia(player, source)      geographical(player, "asia", source) end
function geographical_australia(player, source) geographical(player, "australia", source) end
function geographical_europe(player, source)    geographical(player, "europe", source) end

function player_worker(player, n)
  return getObjectFromGUID(player.workers[n])
end

function partner_zoo_capacity(player)
  return player.association_flipped and 4 or 2
end

function partner_zoo_position(player, index)
  local pos = board_relative_world_position(
    player.player_board.getPosition(), "partner_zoo_1")
  for i = 2, index do
    pos = pos + cnsts.board_relative_positions[
      (i == 3) and "partner_zoo_big_step" or "partner_zoo_small_step"]
  end
  return pos
end

function partner_zoo_label(owner)
  return habitat_label(owner) .. " Partner Zoo"
end

function available_partner_zoos(player, supply)
  local held = {}
  if not supply then
    for _, zoo in ipairs(player.acquired_partner_zoos) do held[zoo] = true end
  end

  local out = {}
  for _, owner in ipairs(cnsts.icons.habitat) do
    local there
    if supply then
      there = #bags[owner .. "_partner"].getObjects() > 0
    else
      there = tile_in_zone(board_tile_zone(owner .. "_partner"), "partner") ~= nil
    end
    if there and not held[owner] then out[#out + 1] = owner end
  end
  return out
end

function can_take_partner_zoo(player, supply)
  return #player.acquired_partner_zoos < partner_zoo_capacity(player)
    and #available_partner_zoos(player, supply) > 0
end

function get_partner_zoo(player, source, supply)
  if not can_take_partner_zoo(player, supply) then
    broadcastToColor("You cannot take any more partner zoos!", player.color, "Red")
    render_claims_table(player)
    return
  end

  local claims = {}
  for _, owner in ipairs(available_partner_zoos(player, supply)) do
    claims[#claims + 1] = {
      button_text = partner_zoo_label(owner),
      source = source,
      async = true,
      function_call = function() take_partner_zoo(player, owner, supply) end
    }
  end
  create_claims_from_reward_groups(player, {}, true, claims)
end

function take_partner_zoo(player, owner, supply)
  player.acquired_partner_zoos[#player.acquired_partner_zoos + 1] = owner
  local index = #player.acquired_partner_zoos
  local pos = partner_zoo_position(player, index)

  if supply then
    local tile = bags[owner .. "_partner"].takeObject(
      { position = pos, smooth = false })
    tile.interactable = false
  else
    tile_in_zone(board_tile_zone(owner .. "_partner"), "partner")
      .setPositionSmooth(pos, false, false)
  end
  printToAll(player.steam_name .. " acquires the " ..
    partner_zoo_label(owner) .. ".")

  local data = cnsts.map_data[player.map_key]
  local groups = { {
    rewards = (data and data.partner_zoo_rewards
               and data.partner_zoo_rewards[index]) or {},
    source = "acquiring a partner zoo"
  } }
  append_icon_groups(groups, player, { owner })
  create_claims_from_reward_groups(player, groups, false)
end

function university_position(player, index)
  local pos = board_relative_world_position(
    player.player_board.getPosition(), "university_1")
  for _ = 2, index do
    pos = pos + cnsts.board_relative_positions.university_step
  end
  return pos
end

function species_universities_remaining()
  local zone = getObjectFromGUID(cnsts.species_university_zone)
  local out = {}
  for _, obj in pairs(zone.getObjects(true)) do
    if obj.hasTag("university") then
      local name = cnsts.species_university_guids[obj.getGUID()]
      if name ~= nil then out[name] = obj end
    end
  end
  return out
end

function has_species_university(player)
  for _, uni in ipairs(player.acquired_universities) do
    local spec = cnsts.universities[uni]
    if spec ~= nil and spec.species then return true end
  end
  return false
end

function available_universities(player, supply)
  local held = {}
  if not supply then
    for _, uni in ipairs(player.acquired_universities) do held[uni] = true end
  end

  local species_open = marine_worlds_enabled
    and (supply or (not tile_missing(board_tile_zone("generic_university"), "university")
                    and not has_species_university(player)))
  local remaining = species_open and species_universities_remaining() or {}

  local out = {}
  for _, name in ipairs(cnsts.university_order) do
    local available
    if cnsts.universities[name].species then
      available = remaining[name] ~= nil
    elseif supply then
      available = #bags[name .. "_university"].getObjects() > 0
    else
      available = tile_in_zone(board_tile_zone(name .. "_university"), "university") ~= nil
    end
    if available and not held[name] then out[#out + 1] = name end
  end
  return out
end

function can_take_university(player, supply)
  return #player.acquired_universities < 3
    and #available_universities(player, supply) > 0
end

function get_university(player, source, supply)
  if not can_take_university(player, supply) then
    broadcastToColor("You cannot take any more universities!", player.color, "Red")
    render_claims_table(player)
    return
  end

  local claims = {}
  for _, name in ipairs(available_universities(player, supply)) do
    claims[#claims + 1] = {
      button_text = cnsts.universities[name].label,
      source = source,
      async = true,
      function_call = function() take_university(player, name, supply) end
    }
  end
  create_claims_from_reward_groups(player, {}, true, claims)
end

function take_university(player, name, supply)
  local spec = cnsts.universities[name]
  player.acquired_universities[#player.acquired_universities + 1] = name
  local index = #player.acquired_universities
  local pos = university_position(player, index)

  if spec.species then
    species_universities_remaining()[name].setPositionSmooth(pos, false, false)
    if not supply then
      generic_university.tile.setPositionSmooth(
        generic_university.home_pos, false, false)
    end
  elseif supply then
    local tile = bags[name .. "_university"].takeObject(
      { position = pos, smooth = false })
    tile.interactable = false
  else
    tile_in_zone(board_tile_zone(name .. "_university"), "university")
      .setPositionSmooth(pos, false, false)
  end
  printToAll(player.steam_name .. " acquires the " .. spec.label .. ".")

  local data = cnsts.map_data[player.map_key]
  local groups = {
    { rewards = (data and data.university_rewards
                 and data.university_rewards[index]) or {},
      source = "acquiring a university" },
    { rewards = spec.rewards or {}, source = spec.label },
  }
  append_icon_groups(groups, player, spec.icons)
  create_claims_from_reward_groups(player, groups, false)
end

function unlock_worker(player, source)
  if player.worker_count >= 4 then
    broadcastToColor("You cannot unlock anymore workers!", player.color, "Red")
    render_claims_table(player)
    return
  end

  player.worker_count = player.worker_count + 1
  local n = player.worker_count
  local worker = player_worker(player, n)
  worker.setPosition(board_relative_world_position(
    player.player_board.getPosition(), "worker_" .. n .. "_home"))
  worker.setRotation(cnsts.worker_rotation)

  printToAll(player.steam_name .. " has unlocked their " ..
    cnsts.worker_ordinals[n] .. " worker".. (source and " from " .. source or "") ..".")

  local data = cnsts.map_data[player.map_key]
  local rewards = (data and data.worker_rewards and data.worker_rewards[n - 1]) or {}
  create_claims_from_rewards(player, rewards, "the worker unlock", false)
end

function full_throated(player, source)
  unlock_worker(player, source and (source .. "'s Full-throated") or nil)
end

function spawn_player_workers(player, board_pos)
  local mother = token_clone_source("Association Worker")
  local tint = Color.fromString(player.color)

  player.workers = {}
  local pos = board_relative_world_position(board_pos, "worker_1_home")
  for n = 1, 4 do
    local worker = mother.clone({ position = pos })
    worker.setRotation(cnsts.worker_rotation)
    worker.setColorTint(tint)
    worker.addTag(player.color)
    worker.interactable = false
    player.workers[n] = worker.getGUID()

    if n == 1 then
      pos = board_relative_world_position(board_pos, "locked_worker_1")
    else
      pos = pos + cnsts.board_relative_positions.locked_worker_z_step
    end
  end
end

function starting_hand_size(player)
  return cnsts.starting_hand_size + (player.map_lagoon and 1 or 0)
end

function finish_player_action_cards(player)
  deal_tagged_cards(zoo_deck, cnsts.starting_hand_size, player.color, 1, "zoo_card")
  deal_tagged_cards(final_scoring_deck, 2, player.color, 2, "final_scoring")
  if player.map_lagoon then
    search(player, "person_sponsor")
  end
end

function destruct_action_card_decks()
  for _, zones in pairs(cnsts.action_card_init_zones) do
    for _, guid in pairs(zones) do
      getDeck(getObjectFromGUID(guid)).destruct()
    end
  end
end

function distribute_action_cards()
  local zones = marine_worlds_enabled and cnsts.action_card_init_zones.mw or cnsts.action_card_init_zones.base
  for _, player in ipairs(players) do
    deal_action_cards(player, zones[player.color])
    finish_player_action_cards(player)
  end
  destruct_action_card_decks()
  wait_for_all_hand_counts(1, starting_hand_size, start_setup_discard)
end

function action_card_object(player, slot)
  return getObjectFromGUID(player.action_cards[slot].guid)
end

function action_card_tokens(player, slot)
  return player.action_cards[slot].tokens
end

function action_card_has_token(player, slot, kind)
  return action_card_tokens(player, slot)[kind] ~= nil
end

function spawn_action_card_token(player, slot, kind, x_offset)
  local spec = cnsts.action_card_tokens[kind]
  local card = action_card_object(player, slot)
  local source = token_clone_source(spec.name)

  local pos = card.getPosition()
  local token = source.clone({ position = {
    x = pos.x + (x_offset or 0),
    y = pos.y + cnsts.drop_height,
    z = pos.z + spec.z,
  } })
  token.interactable = false

  return token.getGUID()
end

function place_now(guid, position)
  local obj = getObjectFromGUID(guid)
  if obj ~= nil then obj.setPosition(position) end
end

function move_when_settled(guid, position)
  Wait.frames(function()
    Wait.condition(
      function()
        local obj = getObjectFromGUID(guid)
        if obj ~= nil then obj.setPositionSmooth(position, false, false) end
      end,
      function()
        local obj = getObjectFromGUID(guid)
        return obj == nil or not obj.isSmoothMoving()
      end)
  end, 2)
end

function seat_action_card_tokens(player, slot, card_pos, place)
  place = place or move_when_settled
  local tokens = action_card_tokens(player, slot)
  if next(tokens) == nil then return end

  local card_half = action_card_object(player, slot).getBounds().size.y / 2
  for kind, value in pairs(tokens) do
    local spec = cnsts.action_card_tokens[kind]
    local listed = (type(value) == "table")
    local guids = listed and value or { value }
    for i, guid in ipairs(guids) do
      place(guid, {
        x = card_pos.x + (listed and multiplier_token_offset(i) or 0),
        y = card_pos.y + card_half
            + getObjectFromGUID(guid).getBounds().size.y / 2,
        z = card_pos.z + (spec and spec.z or 0),
      })
    end
  end
end

function action_card_token_guids(record)
  local guids = {}
  for _, value in pairs(record.tokens) do
    if type(value) == "table" then
      for _, guid in ipairs(value) do guids[#guids + 1] = guid end
    else
      guids[#guids + 1] = value
    end
  end
  return guids
end

function discard_action_card_token(token)
  if token == nil then return end

  local pos = token.getPosition()
  token.setPositionSmooth({ x = pos.x, y = pos.y + 10, z = pos.z + 30 }, false, false)

  Wait.frames(function()
    Wait.condition(function() token.destruct() end,
                   function() return not token.isSmoothMoving() end)
  end, 2)
end

function remove_action_card_token(player, slot, kind)
  local tokens = action_card_tokens(player, slot)
  if tokens[kind] == nil then return false end

  local token = getObjectFromGUID(tokens[kind])
  if token ~= nil then token.destruct() end
  tokens[kind] = nil
  return true
end

function multiplier_token_count(player, slot)
  local list = action_card_tokens(player, slot).multiplier
  return list ~= nil and #list or 0
end

function remove_multiplier_token(player, slot)
  local tokens = action_card_tokens(player, slot)
  local list = tokens.multiplier
  if list == nil or #list == 0 then return false end

  local token = getObjectFromGUID(table.remove(list))
  if token ~= nil then token.destruct() end
  if #list == 0 then tokens.multiplier = nil end
  return true
end

function multiplier_token_offset(n)
  local side = (n % 2 == 0) and 1 or -1
  return cnsts.multiplier_token_spread * (math.floor(n / 2) * side)
end

function add_multiplier_token(player, slot)
  local tokens = action_card_tokens(player, slot)
  tokens.multiplier = tokens.multiplier or {}

  local index = #tokens.multiplier + 1
  tokens.multiplier[index] = spawn_action_card_token(player, slot, "multiplier",
    multiplier_token_offset(index))
end

function multiplier(player, action_name, source)
  add_multiplier_token(player, action_card_slot_named(player, action_name))
  printToAll(string.format("%s places a Multiplier Token on their %s action card%s.",
    player.steam_name, string.upper(action_name),
    source and (" from " .. source) or ""))
end

function multiplier_association(player, source) multiplier(player, "association", source) end
function multiplier_build(player, source)       multiplier(player, "build", source) end
function multiplier_cards(player, source)       multiplier(player, "cards", source) end
function multiplier_sponsors(player, source)    multiplier(player, "sponsors", source) end

multiplier_placements = {}

function multiplier_token(player, source)
  multiplier_placements[player.color] = { player = player, source = source }
  render_multiplier_placement_panel(player)
end

function multiplier_placement_panel_xml(color, player)
  local rows = ""
  for slot = 1, 5 do
    rows = rows .. string.format([[
      <HorizontalLayout spacing="6" minHeight="34" childAlignment="MiddleLeft" childForceExpandHeight="false">
        <Text fontSize="20" color="#FFFFFF" width="20" alignment="MiddleRight">%d:</Text>
        <Button id="multiplierPlaceButton_%s_%d" onClick="on_multiplier_place_clicked(%s)" fontSize="14" width="220" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">%s</Button>
      </HorizontalLayout>
    ]], slot, color, slot, color .. "_" .. slot,
        string.sub(action_card_object(player, slot).getName(), 1, -3))
  end

  local height = 16 + 75 + 24 + 5 * 34 + 6 * 6
  return string.format([[
    <Panel id="multiplierPlacePanel_%s" visibility="%s" rectAlignment="MiddleRight" width="280" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        <Text fontSize="18" color="#FFFFFF">Choose an action card to place a Multiplier Token on:</Text>
        <Text fontSize="18" color="#FFFFFF"></Text>
        %s
      </VerticalLayout>
    </Panel>
  ]], color, color, height, rows)
end

function render_multiplier_placement_panel(player)
  set_player_panel(player.color,
    multiplier_placement_panel_xml(player.color, player))
end

function on_multiplier_place_clicked(_, value, _)
  local color, slot_str = value:match("^(%a+)_(%d+)$")
  local state = multiplier_placements[color]
  if state == nil then return end

  local player, slot = state.player, tonumber(slot_str)
  multiplier_placements[color] = nil
  clear_player_panel(color)

  multiplier(player, string.lower(
    string.sub(action_card_object(player, slot).getName(), 1, -3)), state.source)
  render_claims_table(player)
end

function arm_multiplier_offer(player, slot, x_token)
  if multiplier_token_count(player, slot) == 0 then
    player.offer_multiplier = nil
    return
  end
  player.offer_multiplier = {
    action = string.sub(action_card_object(player, slot).getName(), 1, -3),
    x_token = x_token or nil,
  }
end

function meets_target_minimum(other, counter)
  return get_counter_value(other[counter]) >= cnsts.target_minimums[counter]
end

function targetable(other)
  return not other.quarantine_lab
     and meets_target_minimum(other, "appeal_counter")
end

function constriction(player, source)
  local appeal = get_counter_value(player.appeal_counter)
  local cp = get_counter_value(player.cp_counter)

  local hit = {}
  for _, other in ipairs(players) do
    if other.color ~= player.color and targetable(other) then
      local their_appeal = get_counter_value(other.appeal_counter)
      local their_cp = get_counter_value(other.cp_counter)

      local by_appeal = their_appeal >= appeal
      local by_cp = their_cp >= cp and meets_target_minimum(other, "cp_counter")

      local slots = nil
      if by_appeal and by_cp then
        slots = { 4, 5 }
      elseif by_appeal or by_cp then
        slots = { 5 }
      end

      if slots ~= nil then
        for _, slot in ipairs(slots) do
          if not action_card_has_token(other, slot, "constriction") then
            action_card_tokens(other, slot).constriction =
              spawn_action_card_token(other, slot, "constriction")
          end
        end
        hit[#hit + 1] = other.steam_name
      end
    end
  end

  local from = source and (" from " .. source) or ""
  if #hit == 0 then
    printToAll(player.steam_name .. " constricts" .. from .. ", but no rival is level with them.")
  else
    printToAll(player.steam_name .. " constricts " .. table.concat(hit, ", ") .. from .. ".")
  end
end

function venom(player, count, source)
  local appeal = get_counter_value(player.appeal_counter)

  local hit = {}
  for _, other in ipairs(players) do
    if other.color ~= player.color and targetable(other) then
      local their_appeal = get_counter_value(other.appeal_counter)
      if their_appeal >= appeal then
        for slot = 1, count do
          if not action_card_has_token(other, slot, "venom") then
            action_card_tokens(other, slot).venom =
              spawn_action_card_token(other, slot, "venom")
          end
        end
        hit[#hit + 1] = other.steam_name
      end
    end
  end

  local from = source and (" from " .. source) or ""
  if #hit == 0 then
    printToAll(player.steam_name .. " envenoms" .. from .. ", but no rival is level with them.")
  else
    printToAll(player.steam_name .. " envenoms " .. table.concat(hit, ", ") .. from .. ".")
  end
end

function settle_venom_fee(player)
  player.venom_unpaid = nil
  player.persistent_rewards.venom_fee = nil
end

function pay_venom_fee(player)
  if get_counter_value(player.money_counter) < 2 then
    broadcastToColor("Insufficient money! (Need 2)", player.color, "Red")
    return false
  end

  update_money(player, -2, "venom fee")
  settle_venom_fee(player)
  return true
end

function deal_action_cards(player, zone_guid)
  local board_pos = player.player_board.getPosition()
  local zone = getObjectFromGUID(zone_guid)
  local deck = getDeck(zone)
  local rot = { 0, 180, 0 }

  local animals_guid = nil
  for _, obj_info in ipairs(deck.getObjects()) do
    if string.upper(string.sub(obj_info.name, 1, 7)) == "ANIMALS" then
      animals_guid = obj_info.guid
      break
    end
  end

  local cards = {}

  local pos = board_relative_world_position(board_pos, "action_card_slot_1")
  cards[1] = deck.takeObject({ guid = animals_guid, position = pos, rotation = rot, smooth = false })

  getDeck(zone).shuffle()
  for i = 2, 5 do
    pos = pos + cnsts.board_relative_positions.action_card_step
    local remaining = getDeck(zone)
    if remaining.tag == "Deck" then
      cards[i] = remaining.takeObject({ position = pos, rotation = rot, smooth = false })
    else
      remaining.setPosition(pos)
      remaining.setRotation(rot)
      cards[i] = remaining
    end
  end

  player.action_cards = {}
  for i, card in ipairs(cards) do
    card.locked = true
    player.action_cards[i] = { guid = card.getGUID(), tokens = {} }
  end
end

local DRAFT_UNSELECTED_INDEX = 3
local DRAFT_SELECTED_INDEX = 4

local DRAFT_KEEP_INDEX = DRAFT_UNSELECTED_INDEX

function start_action_card_draft()
  draft_round = 1
  draft_state = {}
  draft_transition_pending = false

  local solo = #players == 1
  local dest_index = solo and DRAFT_SELECTED_INDEX or DRAFT_UNSELECTED_INDEX
  local prompt = solo and "Choose 2 action cards to play"
                      or "Choose an action card to keep"
  local dealt = {}

  local draft_deck = getDeck(getObjectFromGUID(cnsts.draft_deck_zone))
  draft_deck.shuffle()

  local panels = ""
  for _, player in ipairs(players) do
    local color = player.color

    local pool = {}
    dealt[color] = {}
    for _ = 1, 3 do
      local card = draft_deck.takeObject({ smooth = false })
      card.deal(1, color, dest_index)
      pool[card.getGUID()] = true
      dealt[color][#dealt[color] + 1] = card.getGUID()
    end

    draft_state[color] = {
      phase = solo and "final_pick" or "round1",
      pool = solo and {} or pool,
      locked = {},
      selected_guid = nil,
      confirmed = false,
      chosen = {}
    }

    panels = panels .. string.format([[
      <Panel id="draftPanel_%s" visibility="%s" rectAlignment="MiddleRight" width="300" height="160" color="#222222DD">
        <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="MiddleCenter">
          <Text id="draftText_%s" fontSize="18" color="#FFFFFF">%s</Text>
          <Text id="draftCheck_%s" fontSize="26" color="#00FF00" active="false">✓</Text>
          <Button id="draftButton_%s" active="false" onClick="on_draft_confirm_clicked(%s)" fontSize="18" width="120" height="36" color="#4A90D9" textColor="#FFFFFF">Confirm</Button>
        </VerticalLayout>
      </Panel>
    ]], color, color, color, prompt, color, color, color)
  end
  UI.setXml(panels)

  if not solo then return end

  local color = players[1].color
  Wait.condition(setup_final_pick_phase, function()
    return hand_holds_guids(color, DRAFT_SELECTED_INDEX, dealt[color])
  end)
end

function reset_single_pick_panel(color)
  UI.setAttribute("draftText_" .. color, "text", "Choose an action card to keep")
  UI.setAttribute("draftButton_" .. color, "active", "false")
  UI.setAttribute("draftCheck_" .. color, "active", "false")
end

function onObjectPickUp(player_color, obj)
  local state = draft_state and draft_state[player_color]
  if state ~= nil then
    local guid = obj.getGUID()

    if state.locked[guid] then
      broadcastToColor("You cannot return a previously drafted card", player_color)
      obj.deal(1, player_color, DRAFT_SELECTED_INDEX)
      return
    end

    if not state.pool[guid] then return end

    if state.phase == "final_pick" then
      handle_final_pick_pickup(player_color, obj)
    else
      handle_single_pick_pickup(player_color, obj)
    end
    return
  end

  local selection = selection_panels and selection_panels[player_color]
  if selection ~= nil and selection.pool_lookup[obj.getGUID()] then
    handle_card_selection_pickup(player_color, obj)
    return
  end

  local setup_discard = setup_discard_state and setup_discard_state[player_color]
  if setup_discard ~= nil and setup_discard.pool_lookup[obj.getGUID()] then
    handle_setup_discard_pickup(player_color, obj)
    return
  end

  local display_slot = nil
  if display_cards ~= nil then
    for i = 1, 6 do
      if display_cards[i] == obj then
        display_slot = i
        break
      end
    end
  end

  if display_slot ~= nil then
    return_display_card(display_slot)
    local guid = obj.getGUID()

    if snap_player ~= nil and player_color == snap_player.color
       and snappable_display_card(display_slot) then
      handle_snap_pickup(display_slot)
      return
    end

    if rep_draw_player ~= nil and player_color == rep_draw_player.color
       and rep_draw_lookup[guid] then
      handle_rep_draw_pickup(display_slot)
      return
    end

    if mark_state ~= nil and player_color == mark_state.player.color
       and mark_state.slots[display_slot] then
      handle_mark_pickup(display_slot)
      return
    end

    if shark_attack_state ~= nil and player_color == shark_attack_state.player.color
       and shark_attack_state.lookup[guid] then
      handle_shark_attack_pickup(display_slot)
      return
    end

    if digging_player ~= nil and player_color == digging_player.color then
      handle_digging_pickup(obj, display_slot)
      return
    end

  end

  local animal_action = animal_actions and animal_actions[player_color]
  if animal_action ~= nil and animal_action.phase == "pick"
     and animal_action.offers[obj.getGUID()] ~= nil then
    handle_animal_pickup(player_color, obj)
    return
  end

  local sponsor_action = sponsor_actions and sponsor_actions[player_color]
  if sponsor_action ~= nil and sponsor_action.offers[obj.getGUID()] ~= nil then
    handle_sponsor_pickup(player_color, obj)
    return
  end

  local marketing_play = marketing_plays and marketing_plays[player_color]
  if marketing_play ~= nil and marketing_play.offers[obj.getGUID()] then
    handle_marketing_pickup(player_color, obj)
    return
  end

  if digging_player ~= nil and player_color == digging_player.color
     and digging_hand_lookup[obj.getGUID()] then
    handle_digging_pickup(obj, nil)
    return
  end
end

function onObjectLeaveZone(zone, obj)
  local color = cnsts.store_params.hand_zones[zone.getGUID()]
  if color == nil then return end

  unstore_card(find_player_by_color(color), obj)
end

function handle_single_pick_pickup(color, obj)
  local state = draft_state[color]
  local guid = obj.getGUID()

  if state.confirmed then
    obj.deal(1, color, (state.selected_guid == guid)
      and DRAFT_SELECTED_INDEX or DRAFT_UNSELECTED_INDEX)
    return
  end

  if state.selected_guid == guid then
    obj.deal(1, color, DRAFT_UNSELECTED_INDEX)
    state.selected_guid = nil
    reset_single_pick_panel(color)
    return
  end

  if state.selected_guid ~= nil then
    getObjectFromGUID(state.selected_guid).deal(1, color, DRAFT_UNSELECTED_INDEX)
  end

  state.selected_guid = guid
  obj.deal(1, color, DRAFT_SELECTED_INDEX)

  UI.setAttribute("draftText_" .. color, "text", "You have selected:\n\n" .. obj.getName())
  UI.setAttribute("draftButton_" .. color, "active", "true")
  UI.setAttribute("draftButton_" .. color, "text", "Confirm")
  UI.setAttribute("draftButton_" .. color, "color", "#4A90D9")
  UI.setAttribute("draftCheck_" .. color, "active", "false")
end

function handle_final_pick_pickup(color, obj)
  local state = draft_state[color]
  local guid = obj.getGUID()

  for i, chosen_guid in ipairs(state.chosen) do
    if chosen_guid == guid then
      if state.confirmed then
        obj.deal(1, color, DRAFT_KEEP_INDEX)
        return
      end
      table.remove(state.chosen, i)
      obj.deal(1, color, DRAFT_SELECTED_INDEX)
      update_final_pick_panel(color)
      return
    end
  end

  if state.confirmed or #state.chosen >= 2 then
    obj.deal(1, color, DRAFT_SELECTED_INDEX)
    return
  end

  if #state.chosen == 1 then
    local other = getObjectFromGUID(state.chosen[1])
    if string.sub(obj.getName(), 1, 4) == string.sub(other.getName(), 1, 4) then
      broadcastToColor("You cannot pick two cards of the same action", color)
      obj.deal(1, color, DRAFT_SELECTED_INDEX)
      return
    end
  end

  table.insert(state.chosen, guid)
  obj.deal(1, color, DRAFT_KEEP_INDEX)
  update_final_pick_panel(color)
end

function update_final_pick_panel(color)
  local state = draft_state[color]
  if #state.chosen == 0 then
    UI.setAttribute("draftText_" .. color, "text", "Choose 2 action cards to play")
    UI.setAttribute("draftButton_" .. color, "active", "false")
  elseif #state.chosen == 1 then
    local name = getObjectFromGUID(state.chosen[1]).getName()
    UI.setAttribute("draftText_" .. color, "text", "You have chosen:\n" .. name .. "\n\nChoose one more card")
    UI.setAttribute("draftButton_" .. color, "active", "false")
  else
    local name1 = getObjectFromGUID(state.chosen[1]).getName()
    local name2 = getObjectFromGUID(state.chosen[2]).getName()
    UI.setAttribute("draftText_" .. color, "text", "You have chosen:\n" .. name1 .. "\n" .. name2)
    UI.setAttribute("draftButton_" .. color, "text", "Confirm")
    UI.setAttribute("draftButton_" .. color, "color", "#4A90D9")
    UI.setAttribute("draftButton_" .. color, "active", "true")
  end
end

function on_draft_confirm_clicked(_, color, _)
  local state = draft_state and draft_state[color]
  if state == nil or draft_transition_pending then return end

  if state.confirmed then
    cancel_draft_choice(color)
    return
  end

  if state.phase == "final_pick" then
    if #state.chosen ~= 2 then return end
  elseif state.selected_guid == nil then
    return
  end

  state.confirmed = true
  UI.setAttribute("draftButton_" .. color, "text", "Cancel")
  UI.setAttribute("draftButton_" .. color, "color", "#E54848")
  UI.setAttribute("draftCheck_" .. color, "active", "true")

  for _, player in ipairs(players) do
    if not draft_state[player.color].confirmed then return end
  end

  if state.phase == "final_pick" then
    draft_transition_pending = true
    wait_for_all_hand_counts(DRAFT_KEEP_INDEX, 2, finish_drafting)
  else
    advance_draft_round()
  end
end

function cancel_draft_choice(color)
  local state = draft_state[color]
  state.confirmed = false
  UI.setAttribute("draftCheck_" .. color, "active", "false")

  if state.phase == "final_pick" then
    for _, guid in ipairs(state.chosen) do
      getObjectFromGUID(guid).deal(1, color, DRAFT_SELECTED_INDEX)
    end
    state.chosen = {}
    UI.setAttribute("draftButton_" .. color, "active", "false")
    UI.setAttribute("draftText_" .. color, "text", "Choose 2 action cards to play")
  else
    getObjectFromGUID(state.selected_guid).deal(1, color, DRAFT_UNSELECTED_INDEX)
    state.selected_guid = nil
    UI.setAttribute("draftButton_" .. color, "active", "false")
    UI.setAttribute("draftText_" .. color, "text", "Choose an action card to keep")
  end
end

function advance_draft_round()
  draft_transition_pending = true
  for _, player in ipairs(players) do
    UI.setAttribute("draftButton_" .. player.color, "active", "false")
  end

  local leftovers = {}
  local next_color = {}
  for i, player in ipairs(players) do
    local state = draft_state[player.color]
    state.locked[state.selected_guid] = true

    local remaining = {}
    for guid in pairs(state.pool) do
      if guid ~= state.selected_guid then
        table.insert(remaining, guid)
      end
    end
    leftovers[player.color] = remaining
    next_color[player.color] = players[(i % #players) + 1].color
  end

  local incoming = {}
  for _, player in ipairs(players) do incoming[player.color] = {} end

  local to_selected = (draft_round == 2)
  local dest_index = to_selected and DRAFT_SELECTED_INDEX or DRAFT_UNSELECTED_INDEX
  for _, player in ipairs(players) do
    local dest_color = next_color[player.color]
    for _, guid in ipairs(leftovers[player.color]) do
      getObjectFromGUID(guid).deal(1, dest_color, dest_index)
      table.insert(incoming[dest_color], guid)
    end
  end

  draft_round = draft_round + 1

  Wait.condition(function()
    if to_selected then
      setup_final_pick_phase()
    else
      for _, player in ipairs(players) do
        local state = draft_state[player.color]
        state.pool = {}
        for _, guid in ipairs(incoming[player.color]) do
          state.pool[guid] = true
        end
        state.selected_guid = nil
        state.confirmed = false
        reset_single_pick_panel(player.color)
      end
    end
    draft_transition_pending = false
  end, function()
    for _, player in ipairs(players) do
      if not hand_holds_guids(player.color, dest_index, incoming[player.color]) then
        return false
      end
    end
    return true
  end)
end

function setup_final_pick_phase()
  local draft_deck = getDeck(getObjectFromGUID(cnsts.draft_deck_zone))

  for _, player in ipairs(players) do
    local color = player.color
    local cards = Player[color].getHandObjects(DRAFT_SELECTED_INDEX)

    local prefix = string.sub(cards[1].getName(), 1, 4)
    local all_match = true
    for i = 2, #cards do
      if string.sub(cards[i].getName(), 1, 4) ~= prefix then
        all_match = false
        break
      end
    end

    if all_match then
      draft_deck.shuffle()
      local chosen_guid = nil
      for _, obj_info in ipairs(draft_deck.getObjects()) do
        if string.sub(obj_info.name, 1, 4) ~= prefix then
          chosen_guid = obj_info.guid
          break
        end
      end
      local extra_card = draft_deck.takeObject({ guid = chosen_guid, smooth = false })
      extra_card.deal(1, color, DRAFT_SELECTED_INDEX)
      table.insert(cards, extra_card)
    end

    local state = draft_state[color]
    state.phase = "final_pick"
    state.pool = {}
    for _, card in ipairs(cards) do
      state.pool[card.getGUID()] = true
    end
    state.locked = {}
    state.chosen = {}
    state.confirmed = false

    UI.setAttribute("draftText_" .. color, "text", "Choose 2 action cards to play")
    UI.setAttribute("draftButton_" .. color, "active", "false")
    UI.setAttribute("draftCheck_" .. color, "active", "false")
  end
end

function finish_drafting()
  local draft_deck = getDeck(getObjectFromGUID(cnsts.draft_deck_zone))

  for _, player in ipairs(players) do
    local color = player.color
    local state = draft_state[color]

    local chosen_lookup = {}
    for _, guid in ipairs(state.chosen) do
      chosen_lookup[guid] = true
    end

    local to_return = {}
    for guid in pairs(state.pool) do
      if not chosen_lookup[guid] then to_return[#to_return + 1] = guid end
    end
    table.sort(to_return)
    for _, guid in ipairs(to_return) do
      draft_deck.putObject(getObjectFromGUID(guid))
    end

    local mw_zone_guid = cnsts.action_card_init_zones.mw[color]
    local mw_deck = getDeck(getObjectFromGUID(mw_zone_guid))

    local chosen_cards = { getObjectFromGUID(state.chosen[1]), getObjectFromGUID(state.chosen[2]) }
    for _, card in ipairs(chosen_cards) do
      player[to_attribute_name(card.getName())] = true
    end

    local prefix1 = string.sub(chosen_cards[1].getName(), 1, 4)
    local prefix2 = string.sub(chosen_cards[2].getName(), 1, 4)

    local to_remove = {}
    for _, obj_info in ipairs(mw_deck.getObjects()) do
      local prefix = string.sub(obj_info.name, 1, 4)
      if prefix == prefix1 or prefix == prefix2 then
        table.insert(to_remove, obj_info.guid)
      end
    end
    for _, guid in ipairs(to_remove) do
      mw_deck.takeObject({ guid = guid, position = { 39.5, 1, 27 }, smooth = false })
    end

    for _, card in ipairs(chosen_cards) do
      mw_deck.putObject(card)
    end

    getObjectFromGUID(cnsts.drafting_boxes[color]).destruct()
  end

  UI.setXml("")
  draft_state = nil
  distribute_action_cards()
end

active_panels = {}

panel_render_pending = false

function render_active_panels()
  local parts = {}
  for _, panel_xml in pairs(active_panels) do
    parts[#parts + 1] = panel_xml
  end
  UI.setXml(table.concat(parts))
end

function schedule_panel_render()
  if panel_render_pending then return end
  panel_render_pending = true
  Wait.frames(function()
    panel_render_pending = false
    render_active_panels()
  end, 1)
end

function set_ui_attributes(id, attributes)
  attributes.textColor = attributes.textColor or cnsts.panel_text_color
  UI.setAttributes(id, attributes)
end

function set_active_panel(color, xml)
  active_panels[color] = xml
  schedule_panel_render()
end

function clear_active_panel(color)
  active_panels[color] = nil
  schedule_panel_render()
end

player_prompted = {}
player_status = {}
player_panel_refresh = {}

function status_panel_height(text)
  local lines = 1
  for _ in text:gmatch("\n") do lines = lines + 1 end
  return math.max(90, 16 + lines * 2 * 30)
end

function status_panel_xml(color, text)
  return string.format([[
    <Panel id="statusPanel_%s" visibility="%s" rectAlignment="MiddleRight" width="280" height="%d" color="#222222DD">
      <VerticalLayout padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        <Text fontSize="18" color="#FFFFFF">%s</Text>
      </VerticalLayout>
    </Panel>
  ]], color, color, status_panel_height(text), text)
end

function status_panel_text(player)
  if player_status[player.color] ~= nil then
    return player_status[player.color]
  end
  if current_player ~= nil and player.color ~= current_player.color then
    return current_player.steam_name .. " is playing their turn"
  end
  return nil
end

function set_player_panel(color, xml, refresh)
  player_prompted[color] = true
  player_panel_refresh[color] = refresh
  set_active_panel(color, xml)
end

function refresh_open_panel(color)
  local refresh = player_panel_refresh[color]
  if refresh ~= nil then refresh() end
end

function clear_player_panel(color)
  player_prompted[color] = nil
  player_panel_refresh[color] = nil

  local player = find_player_by_color(color)
  local text = player ~= nil and status_panel_text(player) or nil
  if text == nil then
    clear_active_panel(color)
  else
    set_active_panel(color, status_panel_xml(color, text))
  end
end

function refresh_status_panels()
  for _, player in ipairs(players) do
    if not player_prompted[player.color] then
      clear_player_panel(player.color)
    end
  end
end

function set_waiting_status(player, text)
  player_status[player.color] = text
  clear_player_panel(player.color)
end

function clear_waiting_status()
  for _, player in ipairs(players) do
    player_status[player.color] = nil
  end
  refresh_status_panels()
end

selection_panels = {}

function selection_ready(state)
  if state.action == "sell" or state.action == "pouch"
     or state.action == "glide discard" then
    return #state.selected >= 1
  end
  return #state.selected == state.num
end

function selection_prompt_text(state)
  local plural = (state.num == 1) and "" or "s"
  local text
  if state.action == "sell" then
    text = string.format("Choose up to %d card%s to sell.\n\n", state.num, plural)
  elseif state.action == "pouch" then
    text = string.format("Choose up to %d card%s to pouch in %s.\n\n", state.num, plural, state.source)
  elseif state.action == "optional discard" then
    text = string.format("Choose %d card%s to discard.\n\n", state.num, plural)
  elseif state.action == "glide discard" then
    text = string.format(
      "Discard up to %d card%s from your hand: For every Sea Animal icon, gain 1 of these 3 effects:\n1 Reputation / 2 Appeal / Free Kiosk\n\n",
      state.num, plural)
  elseif state.action == "final scoring discard" then
    text = string.format("Choose %d final scoring card%s to discard.\n\n", state.num, plural)
  else
    text = string.format("Choose %d card%s to %s.\n\n", state.num, plural, state.action)
  end
  if #state.selected > 0 then
    local names = {}
    for _, card in ipairs(state.selected) do
      table.insert(names, string.sub(card.getName(), 7))
    end
    text = text .. "You have selected:\n\n" .. table.concat(names, "\n")
  end
  return text
end

local SELECTION_BAIL_LABEL = { ["glide discard"] = "Pass" }

function selection_panel_xml(color, state)
  local ready = tostring(selection_ready(state))

  local cancel_button = ""
  local height = 300
  if state.action == "sell" or state.action == "pouch"
     or state.action == "optional discard" or state.action == "glide discard" then
    cancel_button = string.format([[
      <Button id="selectionCancelButton_%s" onClick="on_card_selection_cancel_clicked(%s)" fontSize="18" width="120" height="36" minHeight="36" color="#C61715" textColor="#FFFFFF">%s</Button>
    ]], color, color, SELECTION_BAIL_LABEL[state.action] or "Cancel")
    height = 350
  end

  if state.action == "glide discard" then height = 420 end

  return string.format([[
    <Panel id="selectionPanel_%s" visibility="%s" rectAlignment="MiddleRight" width="300" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        <Text id="selectionText_%s" fontSize="18" color="#FFFFFF">%s</Text>
        <Button id="selectionButton_%s" active="%s" onClick="on_card_selection_confirm_clicked(%s)" fontSize="18" width="120" height="36" minHeight="36" color="#4A90D9" textColor="#FFFFFF">Confirm</Button>
        %s
      </VerticalLayout>
    </Panel>
  ]], color, color, height, color, selection_prompt_text(state), color, ready, color, cancel_button)
end

function create_card_selection_panel(player, pool, num, action, callback, sell_value, source, reveal, silent, confirm_check)
  local pool_source = type(pool) == "function" and pool or nil
  local num_source = type(num) == "function" and num or nil
  if pool_source ~= nil then pool = pool_source() end
  if num_source ~= nil then num = num_source() end

  local state = {
    player = player,
    pool = pool,
    pool_lookup = selection_pool_lookup(pool),
    pool_source = pool_source,
    num = num,
    num_source = num_source,
    action = action,
    callback = callback,
    sell_value = sell_value,
    source = source,
    reveal = reveal,
    silent = silent,
    confirm_check = confirm_check,
    selected = {}
  }
  selection_panels[player.color] = state
  render_selection_panel(player.color)
end

function selection_pool_lookup(pool)
  local lookup = {}
  for _, card in ipairs(pool) do
    lookup[card.getGUID()] = true
  end
  return lookup
end

function render_selection_panel(color)
  set_player_panel(color, selection_panel_xml(color, selection_panels[color]),
                   function() refresh_selection_panel(color) end)
end

function refresh_selection_panel(color)
  local state = selection_panels[color]
  if state == nil or state.pool_source == nil then return end

  state.pool = state.pool_source()
  state.pool_lookup = selection_pool_lookup(state.pool)
  if state.num_source ~= nil then state.num = state.num_source() end

  render_selection_panel(color)
end

function handle_card_selection_pickup(color, obj)
  local state = selection_panels[color]
  local guid = obj.getGUID()

  for i, card in ipairs(state.selected) do
    if card.getGUID() == guid then
      table.remove(state.selected, i)
      UI.setAttribute("selectionText_" .. color, "text", selection_prompt_text(state))
      UI.setAttribute("selectionButton_" .. color, "active", tostring(selection_ready(state)))
      active_panels[color] = selection_panel_xml(color, state)
      return
    end
  end

  if #state.selected >= state.num then return end

  table.insert(state.selected, obj)
  UI.setAttribute("selectionText_" .. color, "text", selection_prompt_text(state))
  UI.setAttribute("selectionButton_" .. color, "active", tostring(selection_ready(state)))
  active_panels[color] = selection_panel_xml(color, state)
end

function close_selection_panel(color)
  selection_panels[color] = nil
  clear_player_panel(color)
end

function on_card_selection_confirm_clicked(_, color, _)
  local state = selection_panels[color]
  if state == nil or not selection_ready(state) then return end

  if state.confirm_check ~= nil then
    local reason = state.confirm_check(state.selected)
    if reason ~= nil then
      broadcastToColor(reason, color, "Red")
      return
    end
  end

  local player, action, callback = state.player, state.action, state.callback
  local cards
  local kept

  if action == "keep" then
    local selected_lookup = {}
    for _, card in ipairs(state.selected) do
      selected_lookup[card.getGUID()] = true
    end
    kept = state.selected
    cards = {}
    for _, card in ipairs(state.pool) do
      if not selected_lookup[card.getGUID()] then
        table.insert(cards, card)
      end
    end
  elseif action == "play" or action == "store" then
    cards = state.selected[1]
  else
    cards = state.selected
  end

  close_selection_panel(color)

  if action == "play" then
    play_card(player, cards.getName())
  elseif action == "store" then
    store_card(player, cards)
  elseif action == "sell" then
    discard_cards(player, cards, function()
      local total = state.sell_value * #cards
      update_money(player, total)
      local message = string.format("%s sells %d card%s for %d money",
        player.steam_name, #cards, #cards == 1 and "" or "s", total)
      if state.source ~= nil then
        message = message .. ", using " .. state.source
      end
      printToAll(message .. ".")
      callback(true)
    end, state.reveal)
  elseif action == "optional discard" then
    discard_cards(player, cards, function() callback(true) end, state.reveal)
  elseif action == "glide discard" then
    local names = {}
    for _, card in ipairs(cards) do names[#names + 1] = card.getName() end
    discard_cards(player, cards, function() callback(names) end, state.reveal)
  elseif action == "pouch" then
    printToAll(string.format("%s pouches %d card%s in %s.",
      player.steam_name, #cards, #cards == 1 and "" or "s", state.source))
    update_appeal(player, 2 * #cards, "pouching")
    pouch_cards(player, cards, state.source, function() callback(true) end)
  else
    if action == "final scoring discard" then
      discard_final_scoring_cards(player, cards)
      if callback then callback(kept) end
    else
      if not state.silent then report_discard(player, cards) end
      move_cards_to_discard(cards)
      if callback then
        wait_for_cards_out_of_hand(player, 1, cards, function() callback(kept) end)
      end
    end
  end
end

function on_card_selection_cancel_clicked(_, color, _)
  local state = selection_panels[color]
  if state == nil then return end

  local callback = state.callback
  close_selection_panel(color)
  callback(false)
end

setup_discard_state = {}

function setup_discard_panel_xml(color, state)
  local ready = tostring(#state.selected == state.num or state.confirmed)
  local button_color = state.confirmed and "#E54848" or "#4A90D9"
  return string.format([[
    <Panel id="setupDiscardPanel_%s" visibility="%s" rectAlignment="MiddleRight" width="300" height="300" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        <Text id="setupDiscardText_%s" fontSize="18" color="#FFFFFF">%s</Text>
        <Text id="setupDiscardCheck_%s" fontSize="26" color="#00FF00" active="%s" minHeight="36">✓</Text>
        <Button id="setupDiscardButton_%s" active="%s" onClick="on_setup_discard_clicked(%s)" fontSize="18" width="120" height="36" minHeight="36" color="%s" textColor="#FFFFFF">%s</Button>
      </VerticalLayout>
    </Panel>
  ]], color, color, color, selection_prompt_text(state), color, tostring(state.confirmed), color, ready, color, button_color, state.confirmed and "Cancel" or "Confirm")
end

function start_setup_discard()
  setup_discard_state = {}
  local panels = ""
  for _, player in ipairs(players) do
    local pool = Player[player.color].getHandObjects(1)
    local pool_lookup = {}
    for _, card in ipairs(pool) do
      pool_lookup[card.getGUID()] = true
    end

    local state = {
      player = player,
      pool = pool,
      pool_lookup = pool_lookup,
      num = 4,
      action = "discard",
      selected = {},
      confirmed = false
    }
    setup_discard_state[player.color] = state
    panels = panels .. setup_discard_panel_xml(player.color, state)
  end
  UI.setXml(panels)
end

function update_setup_discard_panel(color)
  local state = setup_discard_state[color]
  UI.setAttribute("setupDiscardText_" .. color, "text", selection_prompt_text(state))
  UI.setAttribute("setupDiscardButton_" .. color, "active", tostring(#state.selected == state.num))
end

function handle_setup_discard_pickup(color, obj)
  local state = setup_discard_state[color]
  if state.confirmed then return end

  local guid = obj.getGUID()
  for i, card in ipairs(state.selected) do
    if card.getGUID() == guid then
      table.remove(state.selected, i)
      update_setup_discard_panel(color)
      return
    end
  end

  if #state.selected >= state.num then return end

  table.insert(state.selected, obj)
  update_setup_discard_panel(color)
end

function on_setup_discard_clicked(_, color, _)
  local state = setup_discard_state and setup_discard_state[color]
  if state == nil then return end
  if not state.confirmed and #state.selected ~= state.num then return end

  state.confirmed = not state.confirmed
  UI.setAttribute("setupDiscardCheck_" .. color, "active", tostring(state.confirmed))
  UI.setAttribute("setupDiscardButton_" .. color, "text", state.confirmed and "Cancel" or "Confirm")
  UI.setAttribute("setupDiscardButton_" .. color, "color", state.confirmed and "#E54848" or "#4A90D9")

  for _, player in ipairs(players) do
    if not setup_discard_state[player.color].confirmed then
      return
    end
  end

  UI.setXml("")
  local pile = nil
  for _, player in ipairs(players) do
    pile = discard_cards_to_new_pile(player, setup_discard_state[player.color].selected, pile)
  end
  setup_discard_state = nil
  start_game()
end

function start_game()
  for i = 1, 6 do
    local card = display_cards[i]
    if card ~= nil then
      card.locked = false
      card.setRotationSmooth({ 0, 180, 0 }, false, false)
    end
  end

  Wait.frames(function()
    Wait.condition(lock_display_cards, function()
      for i = 1, 6 do
        local card = display_cards[i]
        if card ~= nil and card.isSmoothMoving() then return false end
      end
      return true
    end)
  end, 2)

  local expected_discards = 4 * #players
  Wait.condition(
    function()
      discard_pile = getByType(getObjectFromGUID(cnsts.discard_pile_zone), "Deck")
      discard_pile.interactable = false

      all_zoo_hooks = {}
      printToAll("----- Game Start -----")
      game_started = true

      start_player_turn(players[1])
    end,
    function()
      local deck = getByType(getObjectFromGUID(cnsts.discard_pile_zone), "Deck")
      return deck ~= nil and deck.getQuantity() == expected_discards
    end
  )
end

function start_player_turn(player)
  current_player = player

  take_checkpoint("turn", player)

  player.turns_taken = player.turns_taken + 1

  printToAll("--- " .. player.steam_name .. "'s turn ---")
  refresh_status_panels()
  for key, value in pairs(player.persistent_rewards) do
    if value == false then
      player.persistent_rewards[key] = true
    end
  end
  if player.t1_effect == "claimed" then player.t1_effect = "ready" end

  player.venom_unpaid = nil
  player.persistent_rewards.venom_fee = nil
  for slot = 1, 5 do
    if action_card_has_token(player, slot, "venom") then
      player.venom_unpaid = true
      player.persistent_rewards.venom_fee = true
      break
    end
  end

  create_action_selection_panel(player)
end

function persistent_rewards_host(player, source)
  if source == "claims" then
    return player.color, function() render_claims_table(player) end
  end
  return player.color, function() create_action_selection_panel(player) end
end

function resume_action_panel_after_claims(player, host)
  if host ~= "action" then return end
  player.on_claims_empty = function()
    player.on_claims_empty = nil
    create_action_selection_panel(player)
  end
end

function build_extra_reward(key)
  for _, extra in ipairs(cnsts.build_extra_rewards) do
    if extra.key == key then return extra end
  end
  return nil
end

function use_token_label(name)
  return "Use: " .. reward_button_text("TOKEN: " .. name)
end

function handle_persistent_rewards(player, source)
  local color = player.color
  local buttons = ""
  local count = 0

  if player.income_pending ~= nil then return buttons, count, 0 end

  local extra = 0

  local function add_button(text, reward_name, height)
    height = height or 34
    extra = extra + (height - 34)
    count = count + 1
    buttons = buttons .. string.format([[
      <Button id="persistentRewardButton_%s_%d" onClick="on_persistent_reward_button_clicked(%s)" fontSize="16" width="240" height="%d" minHeight="%d" color="#4A90D9" textColor="#FFFFFF">%s</Button>
    ]], color, count, color .. "|" .. reward_name .. "|" .. source, height, height, text)
  end

  if player.persistent_rewards.commercial_harbor_effect then
    add_button("Sell a card for " .. cnsts.commercial_harbor_sell_value .. " Money",
      "commercial_harbor_effect")
  end
  if player.persistent_rewards.sponsor_1_trade then
    if sponsors_upgraded(player) then
      add_button("Trade: X-token \u{2194} 5 Money\nor either \u{2192} 1 Reputation", "sponsor_1_trade", 52)
    else
      add_button("Trade: X-token \u{2194} 5 Money", "sponsor_1_trade")
    end
  end
  if player.persistent_rewards.sponsor_3_discard then
    if sponsors_upgraded(player) then
      add_button("Discard a card for " .. cnsts.sponsor_3_discard_value .. " Money", "sponsor_3_discard")
    else
      add_button("Discard a Sponsor\ncard for " .. cnsts.sponsor_3_discard_value .. " Money",
        "sponsor_3_discard", 52)
    end
  end
  if player.persistent_rewards.sponsor_4_snap then
    add_button("Discard 1 Sponsor,\nSnap 1 Sponsor", "sponsor_4_snap", 52)
  end
  if player.persistent_rewards.venom_fee then
    add_button("Pay Venom Fee: 2 Money", "venom_fee")
  end
  for _, extra in ipairs(cnsts.build_extra_rewards) do
    if player.persistent_rewards[extra.key] then
      add_button(extra.text, extra.key)
    end
  end
  for _, extra in ipairs(player.engineer_builds) do
    if player.persistent_rewards[extra.key] then
      add_button(extra.text, extra.key, 52)
    end
  end
  if source == "action" and player.t1_effect == "ready" then
    add_button("Discard 1 card for\n+1 action strength", "t1_effect", 52)
  end
  if player.persistent_rewards.marketing_token then
    add_button(use_token_label("marketing"), "marketing_token")
  end
  if player.persistent_rewards.extra_shift_token then
    add_button(use_token_label("extra shift"), "extra_shift_token")
  end

  return buttons, count, extra
end

function on_persistent_reward_button_clicked(_, value, _)
  local color, reward_name, source = value:match("^(%a+)|([%w_]+)|(%a+)$")
  local player = find_player_by_color(color)

  local panel_key, callback = persistent_rewards_host(player, source)
  clear_player_panel(panel_key)

  persistent_origin = true

  if reward_name == "commercial_harbor_effect" then
    create_card_selection_panel(player,
      function() return Player[color].getHandObjects(1) end, 1, "sell", function(sold)
      if sold then
        player.persistent_rewards.commercial_harbor_effect = false
      end
      callback()
    end, cnsts.commercial_harbor_sell_value, "Commercial Harbor")
  elseif reward_name == "venom_fee" then
    pay_venom_fee(player)
    callback()
  elseif reward_name == "sponsor_1_trade" then
    show_trade_panel(player, source, "sponsor1")
  elseif reward_name == "sponsor_3_discard" then
    create_card_selection_panel(player, function() return sponsor_3_discard_pool(player) end,
      1, "sell",
      function(sold)
        if sold then player.persistent_rewards.sponsor_3_discard = nil end
        callback()
      end, cnsts.sponsor_3_discard_value, "Sponsors 3")
  elseif reward_name == "sponsor_4_snap" then
    start_sponsor_4_swap(player, source)
  elseif reward_name == "marketing_token" then
    start_marketing_token(player, source)
  elseif reward_name == "extra_shift_token" then
    start_extra_shift_token(player, source)
  elseif reward_name == "t1_effect" then
    create_card_selection_panel(player,
      function() return Player[color].getHandObjects(1) end, 1, "optional discard",
      function(discarded)
        if discarded then
          player.t1_effect = "active"
        end
        callback()
      end)
  else
    local extra = build_extra_reward(reward_name) or engineer_build(player, reward_name)
    if extra ~= nil then start_bonus_build(player, extra) end
  end
end

action_selection_state = {}

function action_strength(player, slot, x_tokens_used, card_owner)
  card_owner = card_owner or player

  local ai_level = card_owner.map_artificial_intelligence
    and #card_owner.map_artificial_intelligence or 0
  local strength = cnsts.action_strengths[ai_level][slot]
  if player.t1_effect == "active" then
    strength = strength + 1
  end
  if action_card_has_token(card_owner, slot, "constriction") then
    strength = strength - 2
  end
  return strength + (x_tokens_used or 0)
end

function action_performable(player, slot, x_tokens_used, card_owner)
  return action_strength(player, slot, x_tokens_used, card_owner) >= 1
end

function max_action_strength(player, slot, card_owner)
  local strength = action_strength(player, slot, #player.x_tokens, card_owner)
  if player.t1_effect == "ready" then strength = strength + 1 end
  return strength
end

function action_selection_row_text(player, slot, extra, card_owner)
  return tostring(action_strength(player, slot, extra, card_owner)) .. ":"
end

function action_row_available(player, owner, slot, strength)
  if strength < 1 then return false end

  local card = action_card_object(owner, slot)
  local prefix = string.sub(card.getName(), 1, 2)
  local num = string.sub(card.getName(), -1)

  if prefix == "BU" then return build_action_available(player) end
  if prefix == "AN" then return animals_action_available(player, strength, num) end
  if prefix == "AS" then return association_action_available(player, strength, num) end
  return true
end


function action_flip_attribute(owner, slot)
  return cnsts.action_flip_attributes[
    string.sub(action_card_object(owner, slot).getName(), 1, 2)]
end

function with_borrowed_upgrade(player, target, slot, body)
  local attribute = action_flip_attribute(target, slot)
  if attribute == nil then return body() end

  local saved = player[attribute]
  player[attribute] = target[attribute]
  local answer = body()
  player[attribute] = saved
  return answer
end

function action_row_availability(player, state)
  local hypnosis = state.hypnosis
  local owner = hypnosis ~= nil and hypnosis.target or player

  local out = {}
  for slot = 1, 5 do
    local strength = action_strength(player, slot, state.x_tokens_used, owner)
    local function ask()
      return action_row_available(player, owner, slot, strength)
    end
    if hypnosis == nil then
      out[slot] = ask()
    else
      out[slot] = with_borrowed_upgrade(player, owner, slot, ask)
    end
  end
  return out
end

function leader_candidates(player, counter)
  local tiers, values = {}, {}
  for _, other in ipairs(players) do
    local value = get_counter_value(other[counter])
    if tiers[value] == nil then
      tiers[value] = {}
      values[#values + 1] = value
    end
    table.insert(tiers[value], other)
  end
  table.sort(values, function(a, b) return a > b end)

  for _, value in ipairs(values) do
    local candidates, includes_self = {}, false
    for _, other in ipairs(tiers[value]) do
      if other.color == player.color then
        includes_self = true
      elseif targetable(other) and meets_target_minimum(other, counter) then
        candidates[#candidates + 1] = other
      end
    end
    if #candidates > 0 then return candidates end
    if includes_self then return {} end
  end
  return {}
end

function hypnosis_candidates(player)
  return leader_candidates(player, "appeal_counter")
end

function bank_hypnosis(player, target, count, source)
  printToAll(string.format("%s will hypnotize %s at the end of this action.",
    player.steam_name, target.steam_name))
  table.insert(player.post_action_rewards,
    { "hypnosis " .. count, source, target.color })
end

player_picks = {}

function offer_player_pick(player, candidates, prompt, kind, extra)
  local state = { player = player, candidates = candidates,
                  prompt = prompt, kind = kind }
  for key, value in pairs(extra or {}) do state[key] = value end
  player_picks[player.color] = state
  render_player_pick_panel(player)
end

function player_pick_panel_xml(color, state)
  local body = string.format([[<Text fontSize="18" color="#FFFFFF">%s</Text>
    <Text fontSize="18" color="#FFFFFF"></Text>]], state.prompt)
  local height = 16 + 50 + 30 + 12

  for i, candidate in ipairs(state.candidates) do
    body = body .. string.format([[
      <Button id="playerPickButton_%s_%d" onClick="on_player_pick_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">%s</Button>
    ]], color, i, color .. "|" .. i, candidate.steam_name)
    height = height + 40
  end

  return string.format([[
    <Panel id="playerPickPanel_%s" visibility="%s" rectAlignment="MiddleRight" width="280" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="UpperCenter" childForceExpandHeight="false">
        %s
      </VerticalLayout>
    </Panel>
  ]], color, color, height, body)
end

function render_player_pick_panel(player)
  set_player_panel(player.color,
    player_pick_panel_xml(player.color, player_picks[player.color]))
end

function on_player_pick_clicked(_, value, _)
  local color, index = value:match("^(%a+)|(%d+)$")
  local state = player_picks[color]
  if state == nil then return end

  local player = state.player
  local chosen = state.candidates[tonumber(index)]
  player_picks[color] = nil
  clear_player_panel(color)

  if state.kind == "pilfer" then
    start_pilfer(player, chosen)
  else
    bank_hypnosis(player, chosen, state.count, state.source)
    render_claims_table(player)
  end
end

function hypnosis(player, count, source)
  local candidates = hypnosis_candidates(player)

  if #candidates == 0 then
    printToAll(player.steam_name .. " hypnotizes"
      .. (source and (" from " .. source) or "")
      .. ", but no rival is within reach.")
    render_claims_table(player)
    return
  end

  if #candidates == 1 then
    bank_hypnosis(player, candidates[1], count, source)
    render_claims_table(player)
    return
  end

  offer_player_pick(player, candidates, "Choose a player to hypnotize:",
    "hypnosis", { count = count, source = source })
end


pilfers = {}

function pilfering(player, count, source)
  local claims = {}
  for i = 1, count do
    local track = cnsts.pilfer_tracks[i]
    claims[#claims + 1] = {
      button_text = "Pilfer\n(" .. track.label .. ")",
      source = source,
      optional = false,
      async = true,
      function_call = function() start_pilfer_from_track(player, track) end,
    }
  end

  create_claims_from_reward_groups(player, {}, false, claims)
end

function start_pilfer_from_track(player, track)
  local candidates = leader_candidates(player, track.counter)

  if #candidates == 0 then
    printToAll(player.steam_name .. " finds nobody to pilfer from on the "
      .. track.label .. ".")
    render_claims_table(player)
    return
  end

  if #candidates == 1 then
    start_pilfer(player, candidates[1])
    return
  end

  offer_player_pick(player, candidates, "Choose a player to pilfer from:", "pilfer")
end

function start_pilfer(player, target)
  local money = get_counter_value(target.money_counter)
  local cards = player_hand_cards(target)

  if money == 0 and #cards == 0 then
    broadcastToColor(target.steam_name ..
      " neither has any money nor any cards to be pilfered!", player.color, "Red")
    render_claims_table(player)
    return
  end

  if #cards == 0 then
    pilfer_money(player, target, math.min(5, money))
    return
  end

  if money < 5 and not has_stored_cards(target) then
    pilfer_card(player, target)
    return
  end

  pilfers[target.color] = { player = player, target = target }
  set_waiting_status(player, "Pilfering from " .. target.steam_name .. "...")
  render_pilfer_panel(player, target)
end

function render_pilfer_panel(pilferer, target)
  set_player_panel(target.color, pilfer_panel_xml(pilferer, target),
    function() render_pilfer_panel(pilferer, target) end)
end

function pilfer_panel_xml(pilferer, target)
  local color = target.color
  local money_option = get_counter_value(target.money_counter) >= 5

  local prompt = pilferer.steam_name .. " is pilfering from you!"
  local money_button = ""
  local height = 16 + 75 + 30 + 58
  if money_option then
    prompt = prompt .. " Choose one of the following:"
    money_button = string.format([[
        <Button id="pilferMoneyButton_%s" onClick="on_pilfer_money_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">Give 5 Money</Button>
    ]], color, color)
    height = height + 40
  end

  local note = ""
  if has_stored_cards(target) then
    note = string.format([[
        <Text id="pilferNote_%s" fontSize="16" color="#FFFFFF">(If you want to unstore a card to your hand before the pilfer, do it now)</Text>
    ]], color)
    height = height + 58
  end

  return string.format([[
    <Panel id="pilferPanel_%s" visibility="%s" rectAlignment="MiddleRight" width="280" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="UpperCenter" childForceExpandHeight="false">
        <Text id="pilferPrompt_%s" fontSize="18" color="#FFFFFF">%s</Text>
        <Text fontSize="18" color="#FFFFFF"></Text>
        %s
        <Button id="pilferCardButton_%s" onClick="on_pilfer_card_clicked(%s)" fontSize="16" width="240" height="52" minHeight="52" color="#4A90D9" textColor="#FFFFFF">%s</Button>
        %s
      </VerticalLayout>
    </Panel>
  ]], color, color, height, color, prompt, money_button,
      color, color, "Give 1 random card\nfrom your hand", note)
end

function on_pilfer_money_clicked(_, color, _)
  local state = pilfers[color]
  if state == nil then return end

  pilfers[color] = nil
  clear_player_panel(color)
  pilfer_money(state.player, state.target, 5)
end

function on_pilfer_card_clicked(_, color, _)
  local state = pilfers[color]
  if state == nil then return end

  pilfers[color] = nil
  clear_player_panel(color)
  pilfer_card(state.player, state.target)
end

function pilfer_money(player, target, amount)
  update_money(target, -amount, "being pilfered by " .. player.steam_name)
  update_money(player, amount, "pilfering " .. target.steam_name)
  finish_pilfer(player)
end

function pilfer_card(player, target)
  local cards = player_hand_cards(target)
  local card = cards[math.random(#cards)]
  card.deal(1, player.color, 1)

  printToAll(string.format("%s pilfers a card from %s's hand.",
    player.steam_name, target.steam_name))
  wait_for_cards_in_hand(player, 1, { card }, function()
    finish_pilfer(player)
  end)
end

function finish_pilfer(player)
  clear_waiting_status()
  render_claims_table(player)
end

function adopt_flipped_for(player, target, slot)
  local attribute = action_flip_attribute(target, slot)
  if attribute ~= nil then
    player[attribute] = target[attribute]
  end
end

function borrowed_flip_attribute(player)
  if not player.hypnotize_action then return nil end
  local target = find_player_by_color(player.hypnotize_action)
  return action_flip_attribute(target, target.current_action)
end

function restore_flipped_from_cards(player, done)
  local cards = {}
  for slot = 1, 5 do cards[#cards + 1] = action_card_object(player, slot) end

  Wait.condition(function()
    for _, card in ipairs(cards) do
      local attribute = cnsts.action_flip_attributes[string.sub(card.getName(), 1, 2)]
      if attribute ~= nil then player[attribute] = action_card_upgraded(card) end
    end
    if done ~= nil then done() end
  end, function()
    for _, card in ipairs(cards) do
      if card.isSmoothMoving() then return false end
    end
    return true
  end)
end

function start_hypnotized_action(player, target_color, slots)
  post_action_panels[player.color] = nil
  create_action_selection_panel(player, nil, nil,
    { target = find_player_by_color(target_color), slots = slots })
end


function finish_hypnotized_action(player, done)
  local target = find_player_by_color(player.hypnotize_action)
  player.hypnotize_action = false

  restore_flipped_from_cards(player, function()
    move_action_card_to_front(target)
    target.current_action = nil
    done()
  end)
end


function available_workers(player)
  return player.worker_count - #player.deployed_workers
end

function worker_is_deployed(player, guid)
  for _, entry in ipairs(player.deployed_workers) do
    if entry.guid == guid then return true end
  end
  return false
end

function workers_on_task(player, task)
  local n = 0
  for _, entry in ipairs(player.deployed_workers) do
    if entry.task == task then n = n + 1 end
  end
  return n
end

function workers_standing_on_task(task)
  local n = 0
  for _, player in ipairs(players) do
    n = n + workers_on_task(player, task)
  end
  return n
end

function task_worker_cost(player, task)
  local mine = workers_on_task(player, task)
  if mine > 1 then return nil end
  return mine + 1
end


added_projects = {}

function added_project_capacity()
  return math.max(2, #players)
end

function added_project_position(index, total)
  return cnsts.absolute_positions.added_project
    + cnsts.absolute_positions.project_step * (total - index)
end

function add_project_to_row(obj)
  added_projects[#added_projects + 1] = { obj.getGUID(), {} }

  if #added_projects > added_project_capacity() then
    local oldest = table.remove(added_projects, 1)
    for _, cube_guid in pairs(oldest[2]) do
      getObjectFromGUID(cube_guid).destruct()
    end
    local card = getObjectFromGUID(oldest[1])
    card.locked = false
    discard_pile.putObject(card)
  end

  local total = #added_projects
  for i, entry in ipairs(added_projects) do
    local card = getObjectFromGUID(entry[1])
    local pos = added_project_position(i, total)
    card.locked = true
    card.setRotation({ 0, 180, 0 })
    if i == total then
      card.setPosition(pos)
    else
      card.setPositionSmooth(pos, false, false)
    end
    move_project_cubes(entry, pos, card_data_for(card.getName()).project)
  end
end

function move_project_cubes(entry, card_pos, project)
  for slot, cube_guid in pairs(entry[2]) do
    local target = card_pos + project_slot_offset(project, slot)
    getObjectFromGUID(cube_guid).setPositionSmooth(
      { x = target.x, y = target.y + cnsts.drop_height, z = target.z },
      false, false)
  end
end

function each_table_project(fn)
  for _, entry in ipairs(base_projects) do fn(entry[1], entry[2], true) end
  for _, entry in ipairs(added_projects) do fn(entry[1], entry[2], false) end
end

function project_match_count(player, match)
  if match == "species" or match == "habitat" then
    local n = 0
    for _, icon in ipairs(cnsts.icons[match]) do
      if get_icon_counter_value(player.icon_counters[icon]) > 0 then n = n + 1 end
    end
    return n
  end
  if match == "large" then
    return count_played_animals(player, function(card) return card.size >= 4 end)
  end
  if match == "small" then
    return count_played_animals(player, function(card) return card.size <= 2 end)
  end
  return get_icon_counter_value(player.icon_counters[match])
end

function project_boost_available(player)
  local n = player.wildcard and 1 or 0
  for _, attr in ipairs(cnsts.breeding_helper_attrs) do
    local cubes = player[attr]
    if cubes ~= nil and #cubes > 0 then n = n + 1 end
  end
  return n
end

function project_already_supported(player, cubes)
  for slot = 1, 3 do
    local guid = cubes[slot]
    if guid ~= nil then
      local cube = getObjectFromGUID(guid)
      if cube ~= nil and cube_owner_color(cube) == player.color then
        return true
      end
    end
  end
  return false
end

function release_slot_takes_size(slot, size)
  local spec = cnsts.release_project_sizes[slot]
  return (spec.min == nil or size >= spec.min)
     and (spec.max == nil or size <= spec.max)
end

function played_animal_with_icon(player, icon, size_ok)
  for _, guid in ipairs(player.played_animals) do
    local obj = getObjectFromGUID(guid)
    local data = obj ~= nil and card_data_for(obj.getName()) or nil
    if data ~= nil and card_matches_search_key(data, icon)
       and (size_ok == nil or size_ok(data.size)) then
      return data, obj
    end
  end
  return nil
end

function breeding_project_met(player, card)
  local function qualifies(data)
    if data == nil or not card_matches_search_key(data, card.match) then
      return false
    end
    for _, zoo in ipairs(player.acquired_partner_zoos) do
      if card_matches_search_key(data, zoo) then return true end
    end
    return false
  end

  for _, guid in ipairs(player.played_animals) do
    local obj = getObjectFromGUID(guid)
    if qualifies(obj ~= nil and card_data_for(obj.getName()) or nil) then
      return true
    end
  end
  for _, data in ipairs(rescued_animals(player)) do
    if qualifies(data) then return true end
  end
  return false
end

function rescued_animals(player)
  local out = {}
  for _, guid in ipairs(player.map_rescue_station or {}) do
    local obj = getObjectFromGUID(guid)
    local data = obj ~= nil and card_data_for(obj.getName()) or nil
    if data ~= nil then out[#out + 1] = data end
  end
  return out
end

function rescued_animal_with_icon(player, icon, size_ok)
  for _, data in ipairs(rescued_animals(player)) do
    if card_matches_search_key(data, icon)
       and (size_ok == nil or size_ok(data.size)) then
      return data
    end
  end
  return nil
end

function supportable_project_slots(player, card, cubes, boostable)
  local once_only =
    not (card.project == "release" and player.migration_recording)
  if once_only and project_already_supported(player, cubes) then return {} end

  local out = {}

  if card.project == "icons" then
    local have = project_match_count(player, card.match)
    local boost = boostable and project_boost_available(player) or 0
    for slot = 1, 3 do
      local need = card.thresholds[slot] - have
      if cubes[slot] == nil and need <= boost then
        out[#out + 1] = { slot = slot, boost = math.max(0, need) }
      end
    end
    return out
  end

  if card.project == "release" then
    for slot = 1, 3 do
      if cubes[slot] == nil and played_animal_with_icon(player, card.match,
           function(size) return release_slot_takes_size(slot, size) end) ~= nil then
        out[#out + 1] = { slot = slot, boost = 0 }
      end
    end
    return out
  end

  local met
  if card.project == "breeding" then
    met = breeding_project_met(player, card)
  else
    met = project_match_count(player, card.match) >= 2
  end
  if not met then return out end

  for slot = 1, 3 do
    if cubes[slot] == nil then out[#out + 1] = { slot = slot, boost = 0 } end
  end
  return out
end

function supportable_projects(player)
  local out = {}
  each_table_project(function(guid, cubes, boostable)
    local obj = getObjectFromGUID(guid)
    local card = obj ~= nil and card_data_for(obj.getName()) or nil
    if card ~= nil then
      local slots = supportable_project_slots(player, card, cubes, boostable)
      if #slots > 0 then
        out[#out + 1] = { obj = obj, guid = guid, card = card, cubes = cubes,
                          slots = slots, boostable = boostable,
                          name = string.sub(obj.getName(), 7) }
      end
    end
  end)
  return out
end

function project_support_offers(player, upgd)
  local out = supportable_projects(player)
  for _, cand in ipairs(playable_project_candidates(player, upgd)) do
    local cubes = {}
    out[#out + 1] = {
      obj = cand.obj, card = cand.card, cubes = cubes,
      slots = supportable_project_slots(player, cand.card, cubes, false),
      boostable = false, played = true, display_pos = cand.display_pos,
      name = string.sub(cand.obj.getName(), 7),
    }
  end
  return out
end

function playable_project_candidates(player, upgd)
  local candidates = {}

  for _, obj in ipairs(player_hand_cards(player)) do
    local card = card_data_for(obj.getName())
    if card.type == "project"
       and #supportable_project_slots(player, card, {}, false) > 0 then
      candidates[#candidates + 1] = { obj = obj, card = card }
    end
  end

  if upgd then
    local rep = get_counter_value(player.rep_counter)
    local money = get_counter_value(player.money_counter)
    for i, threshold in ipairs(cnsts.rep_range_thresholds) do
      if rep >= threshold and display_cards[i] ~= nil and money >= i then
        local card = card_data_for(display_cards[i].getName())
        if card.type == "project"
           and #supportable_project_slots(player, card, {}, false) > 0 then
          candidates[#candidates + 1] =
            { obj = display_cards[i], card = card, display_pos = i }
        end
      end
    end
  end

  return candidates
end


project_supports = {}

function project_slot_offset(project, slot)
  return cnsts.card_relative_positions[cnsts.project_slot_positions[project]][slot]
end

function project_slot_world_position(card_obj, project, slot)
  return card_obj.getPosition() + project_slot_offset(project, slot)
end

function seat_project_cube(card_obj, project, slot, cube_guid)
  local target = project_slot_world_position(card_obj, project, slot)
  getObjectFromGUID(cube_guid).setPositionSmooth(
    { x = target.x, y = target.y + cnsts.drop_height, z = target.z }, false, false)
end

function project_slot_awards(player, card, slot)
  if card.project == "icons" then
    return { card.awards[slot] .. " cp" }
  end
  if card.project == "management" then
    if slot == 1 then return { "2 cp", card.first_award } end
    if slot == 2 then return { "2 cp", "management rep" } end
    return { "2 cp", "search " .. card.match }
  end
  return cnsts.project_slot_awards[card.project][slot]
end

function available_project_boosts(player)
  local out = {}
  for _, spec in ipairs(cnsts.project_boosts) do
    local held = player[spec.attr]
    if held == true or (type(held) == "table" and #held > 0) then
      out[#out + 1] = spec
    end
  end
  return out
end

function project_boosts_on(state)
  local n = 0
  for _ in pairs(state.boosts) do n = n + 1 end
  return n
end

function project_slot_live(state, slot)
  for _, entry in ipairs(state.chosen.slots) do
    if entry.slot == slot then return entry.boost <= project_boosts_on(state) end
  end
  return false
end

function spend_project_boosts(player, boosts)
  for _, spec in ipairs(cnsts.project_boosts) do
    if boosts[spec.attr] then
      if spec.token ~= nil then
        player[spec.attr] = nil
        spend_bonus_token(player, spec.token)
      else
        getObjectFromGUID(table.remove(player[spec.attr])).destruct()
      end
    end
  end
end

function project_support_panel_xml(color, state)
  local body, height = "", 16 + 12
  local function text(s)
    body = body .. string.format(
      [[<Text fontSize="18" color="#FFFFFF">%s</Text>]], s)
    height = height + 30
  end
  local function button(handler, value, label, fill, ink, live)
    local wrapped = label:find("\n") ~= nil
    body = body .. string.format([[
      <Button onClick="%s(%s)" interactable="%s" fontSize="16" width="260" height="%d" minHeight="%d" color="%s" textColor="%s">%s</Button>
    ]], handler, value, tostring(live ~= false), wrapped and 52 or 34,
        wrapped and 52 or 34, fill or "#4A90D9", ink or "#FFFFFF", label)
    height = height + (wrapped and 58 or 40)
  end
  local function cancel()
    text("")
    button("on_project_support_cancel_clicked", color, "Cancel", "#C61715")
  end

  if state.chosen == nil then
    text("Choose a Conservation Project to support:")
    text("")
    for i, offer in ipairs(state.offers) do
      button("on_project_support_project_clicked", color .. "|" .. i,
        offer.name)
    end
    cancel()

  elseif state.chosen.card.project == "release" and state.slot == nil then
    text("Choose an animal to release:")
    text("")
    for i, entry in ipairs(releasable_animals(state.player, state.chosen)) do
      button("on_project_support_animal_clicked", color .. "|" .. i,
        string.format("%s\n(Size %d  /  %d Appeal)",
          entry.name, entry.card.size, entry.appeal))
    end
    cancel()

  elseif state.slot == nil then
    text("Choose a slot to support: ")
    text("")
    for slot = 1, 3 do
      button("on_project_support_slot_clicked", color .. "|" .. slot,
        cnsts.project_slot_labels[slot], nil, nil,
        project_slot_live(state, slot))
    end
    if state.chosen.boostable then
      local boosts = available_project_boosts(state.player)
      if #boosts > 0 then text("") end
      for _, spec in ipairs(boosts) do
        button("on_project_support_boost_clicked", color .. "|" .. spec.attr,
          spec.label,
          state.boosts[spec.attr] and cnsts.toggle_colors.on
                                   or cnsts.toggle_colors.off)
      end
    end
    cancel()

  else
    text("Choose project cube to use:")
    text("")
    local rewards = cnsts.map_data[state.player.map_key].project_rewards
    for i = 1, cnsts.project_cube_count do
      if state.player.project_cubes[i] ~= nil then
        local spec = cnsts.project_bonus_colors[rewards[i][2]]
        button("on_project_support_cube_clicked", color .. "|" .. i,
          reward_button_text(rewards[i][1], state.player),
          spec.button, spec.text)
      end
    end
    cancel()
  end

  return string.format([[
    <Panel id="projectSupportPanel_%s" visibility="%s" rectAlignment="MiddleRight" width="380" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        %s
      </VerticalLayout>
    </Panel>
  ]], color, color, height, body)
end

function releasable_animals(player, offer)
  local open = {}
  for _, entry in ipairs(offer.slots) do open[entry.slot] = true end

  local out = {}
  for _, guid in ipairs(player.played_animals) do
    local obj = getObjectFromGUID(guid)
    local name = obj.getName()
    local card = card_data_for(name)
    if card_matches_search_key(card, offer.card.match) then
      for slot = 1, 3 do
        if open[slot] and release_slot_takes_size(slot, card.size) then
          out[#out + 1] = { guid = guid, obj = obj, card = card, slot = slot,
                            name = string.sub(name, 7),
                            appeal = animal_card_appeal(name) }
          break
        end
      end
    end
  end
  return out
end

function render_project_support_panel(player)
  set_player_panel(player.color,
    project_support_panel_xml(player.color, project_supports[player.color]))
end

function start_project_support(player, origin, upgd)
  project_supports[player.color] = {
    player = player,
    origin = origin,
    offers = project_support_offers(player, upgd),
    boosts = {},
  }
  render_project_support_panel(player)
end

function on_project_support_project_clicked(_, value, _)
  local color, index = value:match("^(%a+)|(%d+)$")
  local state = project_supports[color]
  state.chosen = state.offers[tonumber(index)]
  render_project_support_panel(state.player)
end

function on_project_support_boost_clicked(_, value, _)
  local color, attr = value:match("^(%a+)|([%w_]+)$")
  local state = project_supports[color]
  state.boosts[attr] = not state.boosts[attr] or nil
  render_project_support_panel(state.player)
end

function on_project_support_animal_clicked(_, value, _)
  local color, index = value:match("^(%a+)|(%d+)$")
  local state = project_supports[color]
  local pick = releasable_animals(state.player, state.chosen)[tonumber(index)]

  state.animal = pick
  state.slot = pick.slot
  render_project_support_panel(state.player)
end

function on_project_support_slot_clicked(_, value, _)
  local color, slot = value:match("^(%a+)|(%d+)$")
  local state = project_supports[color]
  state.slot = tonumber(slot)
  render_project_support_panel(state.player)
end

function on_project_support_cancel_clicked(_, color, _)
  local state = project_supports[color]
  project_supports[color] = nil
  clear_player_panel(color)
  render_claims_table(state.player)
end

function on_project_support_cube_clicked(_, value, _)
  local color, index = value:match("^(%a+)|(%d+)$")
  commit_project_support(project_supports[color], tonumber(index))
end

function release_animal_for_project(player, pick, vacated)
  update_appeal(player, -pick.appeal, "releasing " .. pick.name)
  add_remove_icons(player, pick.card.icons or {}, true)

  printToAll(player.steam_name .. " releases " .. pick.name ..
    vacate_report(vacated) .. ".")

  local index
  for i, guid in ipairs(player.played_animals) do
    if guid == pick.guid then index = i break end
  end
  table.remove(player.played_animals, index)

  pick.obj.locked = false
  discard_pile.putObject(pick.obj)

  local board_pos = player.player_board.getPosition()
  for i = index, #player.played_animals do
    getObjectFromGUID(player.played_animals[i])
      .setPositionSmooth(played_animal_position(board_pos, i), false, false)
  end

  discard_pouched_cards(player, pick.name)
end

function commit_project_support(state, index)
  local player, offer, slot = state.player, state.chosen, state.slot
  project_supports[player.color] = nil
  clear_player_panel(player.color)

  local card_obj = offer.obj
  if offer.played then
    if offer.display_pos ~= nil then
      update_money(player, -offer.display_pos,
        "taking " .. offer.name .. " from the display")
      display_cards[offer.display_pos] = nil
    end
    add_project_to_row(card_obj)
    offer.cubes = added_projects[#added_projects][2]
    printToAll(player.steam_name .. " plays " .. offer.name .. ".")
  end
  local cube_guid = player.project_cubes[index]
  seat_project_cube(card_obj, offer.card.project, slot, cube_guid)
  offer.cubes[slot] = cube_guid
  player.project_cubes[index] = nil

  spend_project_boosts(player, state.boosts)

  retire_claim_record(state.origin)
  commit_association_task(player, 5)

  local groups = {}
  if offer.played and (offer.card.project == "release"
                       or offer.card.project == "management") then
    groups[#groups + 1] = { rewards = offer.card.rewards or {},
                            source = "playing " .. offer.name }
  end
  groups[#groups + 1] = {
    rewards = project_slot_awards(player, offer.card, slot),
    source = "supporting the " .. offer.name .. " project" }

  local bonus = cnsts.map_data[player.map_key].project_rewards[index]
  groups[#groups + 1] = { rewards = { bonus[1] },
                          source = "their map project bonus" }
  if cnsts.project_bonus_colors[bonus[2]].income then
    add_income(player, income_reward_string(bonus[1]), "their map project bonus")
  end

  if offer.card.project == "release" and player.migration_recording then
    groups[#groups + 1] = { rewards = { "1 cp" }, source = "Migration Recording",
                            show_source = true }
  end

  if association_x_token_owed(player, 5) then
    groups[#groups + 1] = { rewards = { "1 x_token" },
                            source = cnsts.association_3_source }
  end

  local function finish()
    printToAll(string.format("%s supports the %s project, %s.",
      player.steam_name, offer.name,
      cnsts.project_slot_labels[slot]:lower()))
    create_claims_from_reward_groups(player, groups, false)
  end

  if state.animal == nil then
    finish()
    return
  end
  start_enclosure_vacate(player, state.animal.card, state.animal.name, nil,
    function(vacated)
      release_animal_for_project(player, state.animal, vacated)
      finish()
    end)
end

function can_support_conservation_project(player, upgd)
  if project_cubes_left(player) == 0 then return false end
  return #project_support_offers(player, upgd) > 0
end

function task_strength(player, task)
  local spec = cnsts.association_tasks[task]
  if spec.veterinarian ~= nil and player.veterinarian then
    return spec.veterinarian
  end
  return task
end

function task_performable(player, task, upgd, supply)
  if task == 3 then return can_take_partner_zoo(player, supply) end
  if task == 4 then return can_take_university(player, supply) end
  if task == 5 then return can_support_conservation_project(player, upgd) end
  return true
end


function association_from_supply(num, upgd, task)
  if num ~= "1" then return false end
  if task == 3 then return true end
  return task == 4 and upgd
end

function association_extra_task(num, upgd)
  if upgd then return nil end
  return cnsts.association_extra_tasks[num]
end

function association_extra_task_open(player, extra)
  if extra.zone == nil then return true end
  if player.worker_count >= 4 then return false end
  local cost = task_worker_cost(player, extra.zone)
  return cost ~= nil and cost <= available_workers(player)
end

function association_extra_worker_allowed(num, upgd)
  return num == "2" and upgd
end

function association_task_value(player, task, extra)
  local value = task_strength(player, task)
  if extra then value = value - cnsts.association_extra_worker.discount end
  return math.max(0, value)
end

function association_task_cost(player, task, extra)
  local cost = task_worker_cost(player, task)
  if cost == nil then return nil end
  return cost + (extra and 1 or 0)
end

function association_task_open(player, task, budget, num, upgd, extra)
  local cost = association_task_cost(player, task, extra)
  return cost ~= nil
    and cost <= available_workers(player)
    and association_task_value(player, task, extra) <= budget
    and task_performable(player, task, upgd,
                         association_from_supply(num, upgd, task))
end

function association_action_available(player, strength, num)
  local upgd = player.association_flipped

  local extra = association_extra_task(num, upgd)
  if extra ~= nil and strength >= extra.strength
     and association_extra_task_open(player, extra) then
    return true
  end

  local buyable = association_extra_worker_allowed(num, upgd)
  for task = 2, 5 do
    if association_task_open(player, task, strength, num, upgd, false)
       or (buyable
           and association_task_open(player, task, strength, num, upgd, true)) then
      return true
    end
  end
  return false
end

function association_action_reachable(player)
  local slot = action_card_slot_named(player, "association")
  local strength = max_action_strength(player, slot)
  local num = string.sub(action_card_object(player, slot).getName(), -1)
  return strength >= 1 and association_action_available(player, strength, num)
end

association_actions = {}

function task_worker_position(task, n)
  local base = cnsts.absolute_positions["task_" .. task .. "_worker"]
  if task == 3 or task == 4 then
    local side = (n % 2 == 0) and 1 or -1
    return base + cnsts.association_worker_spread * (math.floor(n / 2) * side)
  end
  return base + cnsts.association_worker_step * (n - 1)
end

function deploy_workers_to_task(player, task, count)
  assert(count <= available_workers(player), string.format(
    "%s needs %d workers for task %s and has %d free",
    player.color, count, tostring(task), available_workers(player)))

  local standing = workers_standing_on_task(task)

  local placed = 0
  for n = 1, player.worker_count do
    if placed == count then break end
    local guid = player.workers[n]
    if not worker_is_deployed(player, guid) then
      standing = standing + 1
      send_worker_to_task(player, guid, task, standing)
      placed = placed + 1
    end
  end
  return standing
end

function send_worker_to_task(player, guid, task, spot)
  local worker = getObjectFromGUID(guid)
  worker.setPositionSmooth(task_worker_position(task, spot), false, false)
  worker.setRotation(cnsts.association_worker_rotations[task])
  player.deployed_workers[#player.deployed_workers + 1] =
    { guid = guid, task = task }
end

function association_task_claims(player)
  local state = association_actions[player.color]
  local claims = {}
  for task = 2, 5 do
    local function open()
      return not state.taken[task]
        and association_task_open(player, task, state.remaining,
                                  state.num, state.upgd, state.extra_worker)
    end
    if open() then
      claims[#claims + 1] = {
        button_text = cnsts.association_tasks[task].label,
        source = "the ASSOCIATION action",
        async = true,
        optional = task == 5 or nil,
        valid = open,
        function_call = function() take_association_task(player, task) end
      }
    end
  end

  local extra = association_extra_task(state.num, state.upgd)
  if extra ~= nil then
    local function open()
      return not state.taken[extra.key]
        and extra.strength <= state.remaining
        and association_extra_task_open(player, extra)
    end
    if open() then
      claims[#claims + 1] = {
        button_text = extra.label,
        source = "the ASSOCIATION action",
        async = true,
        valid = open,
        function_call = function() take_association_extra_task(player) end
      }
    end
  end

  if association_extra_worker_allowed(state.num, state.upgd)
     and (state.extra_worker or available_workers(player) > 1) then
    claims[#claims + 1] = {
      button_text = cnsts.association_extra_worker.label,
      source = "the ASSOCIATION action",
      optional = true,
      async = true,
      color = state.extra_worker and cnsts.toggle_colors.on
                                  or cnsts.toggle_colors.off,
      function_call = function() toggle_association_extra_worker(player) end
    }
  end

  return claims
end

function association_offer_claims(player)
  local state = association_actions[player.color]
  local claims = association_task_claims(player)
  if #claims > 0 and next(state.taken) ~= nil then
    claims[#claims + 1] = {
      button_text = "Finish the ASSOCIATION action",
      source = "the ASSOCIATION action",
      function_call = null_func
    }
  end
  claims.grouped = true
  return claims
end

function toggle_association_extra_worker(player)
  local state = association_actions[player.color]
  state.extra_worker = not state.extra_worker or nil

  player.claims[#player.claims] = association_offer_claims(player)
  render_claims_table(player)
end

function start_association_action(player, strength, num)
  local upgd = player.association_flipped
  printToAll(player.steam_name .. " takes the ASSOCIATION " ..
    (upgd and "II" or "I") .. " action at strength " .. strength .. ".")

  association_actions[player.color] = {
    player = player,
    strength = strength,
    remaining = strength,
    upgd = upgd,
    num = num,
    taken = {},
  }

  create_claims_from_reward_groups(player, {}, true, association_task_claims(player))
end

function commit_association_task(player, task)
  local state = association_actions[player.color]
  local extra = state.extra_worker

  deploy_workers_to_task(player, task, association_task_cost(player, task, extra))
  state.taken[task] = true
  state.remaining = state.remaining - association_task_value(player, task, extra)
  state.extra_worker = nil

  if state.upgd and not state.donation_offered then
    state.donation_offered = true
    table.insert(player.claims, 1, association_donation_claims(player))
  end

  if state.upgd then
    table.insert(player.claims, {
      grouped = true,
      refresh = function(sub_table)
        for _, claim in ipairs(association_offer_claims(player)) do
          sub_table[#sub_table + 1] = claim
        end
      end
    })
  end
end

function association_x_token_owed(player, task)
  local state = association_actions[player.color]
  return state ~= nil and state.num == "3" and not state.upgd
    and state.strength > task_strength(player, task)
end

function take_association_task(player, task)
  local state = association_actions[player.color]
  local bonus = association_x_token_owed(player, task)

  if task == 5 then
    start_project_support(player, active_claim, state.upgd)
    return
  end

  commit_association_task(player, task)

  if task == 2 then
    local groups = { { rewards = { "2 rep" }, source = "the ASSOCIATION action" } }
    if bonus then
      groups[#groups + 1] = { rewards = { "1 x_token" },
                              source = cnsts.association_3_source }
    end
    create_claims_from_reward_groups(player, groups, false)
    return
  end

  if bonus then
    local sub_table = {}
    append_reward_claims(sub_table, player, { "1 x_token" },
      cnsts.association_3_source)
    table.insert(player.claims, sub_table)
  end

  local supply = association_from_supply(state.num, state.upgd, task)
  if task == 3 then
    get_partner_zoo(player, "the ASSOCIATION action", supply)
  else
    get_university(player, "the ASSOCIATION action", supply)
  end
end

function take_association_extra_task(player)
  local state = association_actions[player.color]
  local extra = association_extra_task(state.num, state.upgd)

  state.taken[extra.key] = true
  state.remaining = state.remaining - extra.strength

  if extra.key == "hire" then
    local cost = task_worker_cost(player, extra.zone)
    local standing = deploy_workers_to_task(player, extra.zone, cost)
    hire_association_worker(player, extra.zone, standing + 1)
    return
  end

  create_claims_from_rewards(player, { "determination" },
    cnsts.association_4_source, false)
end

function hire_association_worker(player, task, spot)
  player.worker_count = player.worker_count + 1
  local n = player.worker_count
  send_worker_to_task(player, player.workers[n], task, spot)

  printToAll(player.steam_name .. " hires their " ..
    cnsts.worker_ordinals[n] .. " worker.")

  local data = cnsts.map_data[player.map_key]
  create_claims_from_rewards(player,
    (data and data.worker_rewards and data.worker_rewards[n - 1]) or {},
    "the worker unlock", false)
end

function association_donation_claims(player)
  local state = association_actions[player.color]
  local claims = { {
    button_text = function()
      return "Donate (" .. donation_cost(player, true) .. " Money)"
    end,
    source = "the ASSOCIATION action",
    optional = true,
    async = true,
    function_call = function()
      donate(player, "the ASSOCIATION action", true)
    end
  } }

  if state.num == "4" then
    append_reward_claims(claims, player, { "draw 1" }, cnsts.association_4_source)
    claims.grouped = true
  end
  return claims
end

function clear_association_action_state(player)
  association_actions[player.color] = nil
end


function recall_worker_from_task(player, task)
  local recalled = nil
  for i, entry in ipairs(player.deployed_workers) do
    if entry.task == task then
      recalled = entry.guid
      table.remove(player.deployed_workers, i)
      break
    end
  end
  assert(recalled ~= nil, string.format(
    "%s has no worker on task %s to recall", player.color, tostring(task)))

  send_worker_home(player, recalled)

  local spot = 0
  for _, other in ipairs(players) do
    for _, entry in ipairs(other.deployed_workers) do
      if entry.task == task then
        spot = spot + 1
        getObjectFromGUID(entry.guid).setPositionSmooth(
          task_worker_position(task, spot), false, false)
      end
    end
  end

  printToAll(string.format("%s returns a worker from \"%s\".",
    player.steam_name, cnsts.association_tasks[task].label))
end

extra_shifts = {}

function extra_shift_panel_xml(color, state)
  local body = [[<Text fontSize="18" color="#FFFFFF">Recall a worker from:</Text>
    <Text fontSize="18" color="#FFFFFF"></Text>]]
  local height = 16 + 30 + 30 + 12

  for task = 2, 5 do
    if workers_on_task(state.player, task) > 0 then
      body = body .. string.format([[
        <Button id="extraShiftZoneButton_%s_%d" onClick="on_extra_shift_zone_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">%s</Button>
      ]], color, task, color .. "|" .. task, cnsts.association_tasks[task].label)
      height = height + 40
    end
  end

  body = body .. string.format([[
    <Text fontSize="18" color="#FFFFFF"></Text>
    <Button id="extraShiftCancelButton_%s" onClick="on_extra_shift_cancel_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#C61715" textColor="#FFFFFF">Cancel</Button>
  ]], color, color)
  height = height + 30 + 40

  return string.format([[
    <Panel id="extraShiftPanel_%s" visibility="%s" rectAlignment="MiddleRight" width="280" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="UpperCenter" childForceExpandHeight="false">
        %s
      </VerticalLayout>
    </Panel>
  ]], color, color, height, body)
end

function render_extra_shift_panel(player)
  set_player_panel(player.color,
    extra_shift_panel_xml(player.color, extra_shifts[player.color]))
end

function offer_extra_shift(player, opts)
  opts = opts or {}
  local host = opts.host or "claims"

  if #player.deployed_workers == 0 then
    broadcastToColor("You have no workers on the association board!",
      player.color, "Red")
    local _, callback = persistent_rewards_host(player, host)
    callback()
    return
  end

  extra_shifts[player.color] = {
    player = player, source = opts.source, host = host,
    token = opts.token or false,
  }
  render_extra_shift_panel(player)
end

function on_extra_shift_cancel_clicked(_, color, _)
  local state = extra_shifts[color]
  if state == nil then return end

  local player = state.player
  extra_shifts[color] = nil
  clear_player_panel(color)

  local _, callback = persistent_rewards_host(player, state.host)
  callback()
end

function on_extra_shift_zone_clicked(_, value, _)
  local color, task = value:match("^(%a+)|(%d+)$")
  local state = extra_shifts[color]
  if state == nil then return end

  local player = state.player
  extra_shifts[color] = nil
  clear_player_panel(color)

  if state.token then
    player.persistent_rewards.extra_shift_token = nil
    spend_bonus_token(player, "TOKEN: extra shift")
  else
    retire_active_claim()
  end

  recall_worker_from_task(player, tonumber(task))

  local _, callback = persistent_rewards_host(player, state.host)
  callback()
end

function extra_shift(player, source)
  offer_extra_shift(player, { source = source })
end

function start_extra_shift_token(player, host)
  offer_extra_shift(player,
    { source = "their Extra Shift token", token = true, host = host })
end


function donation_slot()
  for _, key in ipairs(cnsts.donation_zones) do
    if tile_missing(zones[key], "cube") then
      return tonumber(key:match("^donation_(%d+)")), key
    end
  end
  return cnsts.donation_overflow_cost, nil
end

function donation_cost(player, association)
  local cost, key = donation_slot()
  if player.publications then
    cost = math.max(0,
      cost - get_icon_counter_value(player.icon_counters.research))
  end
  local state = association_actions[player.color]
  if association and state ~= nil and state.num == "3" and state.upgd then
    cost = math.max(0, cost - #player.x_tokens)
  end
  return cost, key
end

function donation_12_count()
  local n = 0
  for _, obj in pairs(zones.donation_12.getObjects(true)) do
    if obj.hasTag("cube") then n = n + 1 end
  end
  return n
end

function donation_12_position(n)
  local spots = #cnsts.donation_12_offsets
  local layer = math.floor((n - 1) / spots)
  local spot = cnsts.donation_12_offsets[((n - 1) % spots) + 1]
  return cnsts.absolute_positions.donation_12_cube
    + cnsts.absolute_positions.donation_12_dx * spot[1]
    + cnsts.absolute_positions.donation_12_dz * spot[2]
    + Vector(0, layer, 0)
end

function donate(player, source, association)
  local cost, key = donation_cost(player, association)
  if get_counter_value(player.money_counter) < cost then
    broadcastToColor("You don't have enough money to donate! (Need " .. cost .. ")",
      player.color, "Red")
    render_claims_table(player)
    return false
  end

  retire_active_claim()

  update_money(player, -cost, "a donation")

  if key ~= nil then
    take_player_cube(player, zones[key].getPosition() + Vector(0, 1, 0))
  else
    take_player_cube(player, donation_12_position(donation_12_count() + 1))
  end

  create_claims_from_rewards(player, { "1 cp" }, "the donation", false)
  return true
end

function action_selection_panel_xml(color, state, persistent_buttons, persistent_count, persistent_extra)
  local player = state.player
  local hypnosis = state.hypnosis
  local cards_player = hypnosis ~= nil and hypnosis.target or player
  local button_color = state.x_token_active and "#888888" or "#4A90D9"

  local row_available = action_row_availability(player, state)

  local rows = ""
  for slot = 1, 5 do
    local card = action_card_object(cards_player, slot)
    local available = row_available[slot]
    local usable
    if state.x_token_active then
      usable = #player.x_tokens < 5
    else
      usable = available
    end
    local interactable = usable
      and (state.only_slot == nil or slot == state.only_slot)
      and (hypnosis == nil or slot <= hypnosis.slots)
    rows = rows .. string.format([[
      <HorizontalLayout spacing="6" minHeight="34" childAlignment="MiddleLeft" childForceExpandHeight="false">
        <Text id="actionRowLabel_%s_%d" fontSize="20" color="#FFFFFF" width="30" alignment="MiddleRight">%s</Text>
        <Button id="actionButton_%s_%d" interactable="%s" onClick="on_action_card_button_clicked(%s)" fontSize="14" width="208" height="34" minHeight="34" color="%s" textColor="#FFFFFF">%s</Button>
      </HorizontalLayout>
    ]], color, slot,
        action_selection_row_text(player, slot, state.x_tokens_used, cards_player),
        color, slot, tostring(interactable), color .. "_" .. slot, button_color,
        string.sub(card.getName(), 1, -3))
  end

  local persistent_section = ""
  local separator_height = 0
  if persistent_count > 0 then
    persistent_section = [[<Text fontSize="18" color="#FFFFFF"></Text>]] .. persistent_buttons
    separator_height = 30
  end

  local multiplier = state.multiplier ~= nil
  local pass_section = ""
  local pass_height = 0
  if multiplier then
    pass_section = string.format([[
      <Text fontSize="18" color="#FFFFFF"></Text>
      <Button id="multiplierPassButton_%s" onClick="on_multiplier_pass_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#C61715" textColor="#FFFFFF">Pass</Button>
    ]], color, color)
    pass_height = 30 + 40
  end

  local height = 370 + separator_height + persistent_count * 40 + persistent_extra
    + pass_height
  return string.format([[
    <Panel id="actionSelectionPanel_%s" visibility="%s" rectAlignment="MiddleRight" offsetXY="-60 0" width="260" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="UpperCenter" childForceExpandHeight="false">
        <Text fontSize="18" color="#FFFFFF">%s</Text>
        <Text fontSize="18" color="#FFFFFF"></Text>
        <HorizontalLayout spacing="0" padding="35 35 0 0" childAlignment="MiddleCenter" childForceExpandHeight="false">
          <Button id="xTokenButton_%s" interactable="%s" onClick="on_take_x_token_clicked(%s)" fontSize="16" width="260" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">Take an X-token</Button>
        </HorizontalLayout>
        %s
        <HorizontalLayout spacing="6" childAlignment="MiddleLeft" childForceExpandHeight="false">
          <Text fontSize="16" color="#FFFFFF">Use X-tokens:</Text>
          <Button id="xTokenSpinDown_%s" onClick="on_x_token_spin_clicked(%s)" fontSize="16" width="30" height="30" minHeight="30" color="#4A90D9" textColor="#FFFFFF">-</Button>
          <Text id="xTokenSpinValue_%s" fontSize="16" color="#FFFFFF" width="24" alignment="MiddleCenter">%d</Text>
          <Button id="xTokenSpinUp_%s" onClick="on_x_token_spin_clicked(%s)" fontSize="16" width="30" height="30" minHeight="30" color="#4A90D9" textColor="#FFFFFF">+</Button>
        </HorizontalLayout>
        %s
        %s
      </VerticalLayout>
    </Panel>
  ]], color, color, height,
      hypnosis ~= nil and "Hypnotize an action:"
        or (multiplier and "Use multiplier token:" or "Choose an action to perform:"),
      color,
      tostring(state.only_slot == nil and not multiplier and #player.x_tokens < 5),
      color, rows, color, color .. "_down", color, state.x_tokens_used, color, color .. "_up",
      persistent_section, pass_section)
end

function create_action_selection_panel(player, only_action, multiplier, hypnosis)
  local state = {
    player = player,
    x_tokens_used = 0,
    x_token_active = (multiplier ~= nil and multiplier.x_token == true),
    only_slot = only_action ~= nil and action_card_slot_named(player, only_action) or nil,
    multiplier = multiplier,
    hypnosis = hypnosis,
  }
  action_selection_state[player.color] = state
  render_action_selection_panel(player)
end

function offer_multiplier_action(player)
  local offer = player.offer_multiplier
  create_action_selection_panel(player, offer.action, offer)
end

function on_multiplier_pass_clicked(_, color, _)
  local state = action_selection_state[color]
  if state == nil or state.multiplier == nil then return end

  local player = state.player
  action_selection_state[color] = nil
  clear_player_panel(color)

  player.offer_multiplier = nil
  resume_end_player_turn(player)
end

function render_action_selection_panel(player)
  local state = action_selection_state[player.color]
  if state == nil then return end
  local buttons, count, extra = handle_persistent_rewards(player, "action")
  set_player_panel(player.color,
    action_selection_panel_xml(player.color, state, buttons, count, extra),
    function() render_action_selection_panel(player) end)
end

function on_take_x_token_clicked(_, color, _)
  local state = action_selection_state[color]
  if state == nil then return end
  if state.only_slot ~= nil or state.multiplier ~= nil then return end
  if not state.x_token_active and #state.player.x_tokens >= 5 then return end

  state.x_token_active = not state.x_token_active
  render_action_selection_panel(state.player)
end

function on_x_token_spin_clicked(_, value, _)
  local color, direction = value:match("^(%a+)_(%a+)$")
  local state = action_selection_state[color]
  if state == nil then return end

  local max_tokens = #state.player.x_tokens
  if direction == "up" then
    state.x_tokens_used = math.min(state.x_tokens_used + 1, max_tokens)
  else
    state.x_tokens_used = math.max(state.x_tokens_used - 1, 0)
  end

  render_action_selection_panel(state.player)
end

function card_data_for(name)
  local number = card_number_of(name)
  return (marine_worlds_enabled and cnsts.cards.mw[number]) or cnsts.cards.base[number]
end

function card_number_of(name)
  return tonumber(string.sub(name, 2, 4))
end

function card_has_wave(name)
  return card_data_for(name).wave == true
end

function animal_terrain_needs(card)
  local need = { rock = 0, water = 0 }
  for _, icon in ipairs(card.icons or {}) do
    if need[icon] ~= nil then need[icon] = need[icon] + 1 end
  end
  return need
end

function tile_meets_terrain(map, id, need, allowed, ignore_water)
  if need.rock > 0 and not allowed.rock
     and map:countTouchingBlocked(id, "rock") < need.rock then
    return false
  end
  if not ignore_water and need.water > 0 and not allowed.water
     and map:countTouchingBlocked(id, "water") < need.water then
    return false
  end
  return true
end

function tile_slots(map, id)
  return map.tiles[id].tags.slots or 0
end

function animal_play_cost(card, player, display_pos)
  local cost = card.cost + (display_pos or 0)

  if player.expert_in_small_animals and card.size <= 2 then
    cost = cost - 3
  end
  if player.expert_in_large_animals and card.size >= 4 then
    cost = cost - 4
  end

  for _, zoo in ipairs(player.acquired_partner_zoos) do
    for _, icon in ipairs(card.icons or {}) do
      if icon == zoo then cost = cost - 3 end
    end
  end

  return cost
end

function enclosure_capacity_opts(player)
  return { expansion_area = player.expansion_area }
end

function valid_animal_enclosures(card, player)
  local map = player.map
  local need = animal_terrain_needs(card)
  local allowed = buildable_terrain(player)
  local out = {}

  for _, icon in ipairs(card.icons or {}) do
    if icon == "petting" then
      for _, id in ipairs(map:tilesWithTag("petting_zoo")) do
        if tile_slots(map, id) >= 1 then
          out[#out + 1] = { id = id, kind = "petting_zoo", slots = 1 }
        end
      end
      return out
    end
  end

  if not card.no_std_enc then
    local capacity_opts = enclosure_capacity_opts(player)
    for id, tile in pairs(map.tiles) do
      local capacity = map:enclosureCapacity(id, capacity_opts)
      if capacity ~= nil and capacity >= card.size and tile.tags.occupied == false
         and tile_meets_terrain(map, id, need, allowed, false) then
        out[#out + 1] = { id = id, kind = "size" }
      end
    end
  end

  if card.enclosure then
    for key, required in pairs(card.enclosure) do
      local ignore_water = (key == "aquarium")
      local matches, available = {}, 0
      for _, type_name in ipairs(cnsts.animal_enclosure_types[key]) do
        for _, id in ipairs(map:tilesWithTag(type_name)) do
          if tile_slots(map, id) >= 1
             and tile_meets_terrain(map, id, need, allowed, ignore_water) then
            matches[#matches + 1] = id
            available = available + tile_slots(map, id)
          end
        end
      end
      if available >= required then
        for _, id in ipairs(matches) do
          out[#out + 1] = { id = id, kind = key, slots = required }
        end
      end
    end
  end

  return out
end

function animal_fits_enclosure(card, player)
  return #valid_animal_enclosures(card, player) > 0
end

function flock_size(card)
  return tonumber((card.effect or ""):match("^flock (%d+)$") or "")
end

function flock_available(card, player)
  local size = flock_size(card)
  if size == nil then return false end
  local function big_enough(s) return s >= size end
  return played_animal_with_icon(player, "herbivore", big_enough) ~= nil
    or rescued_animal_with_icon(player, "herbivore", big_enough) ~= nil
end

function player_condition_supply(player, condition, card_type)
  if condition == "upgrade" then
    if card_type == "sponsor" then
      return player.sponsors_flipped and 1 or 0
    end
    return player.animals_flipped and 1 or 0
  end

  if condition == "university" then
    return #player.acquired_universities
  end

  if condition == "partner zoo" then
    return #player.acquired_partner_zoos
  end

  if condition == "kiosk" then
    return #player.map:tilesWithTag("kiosk")
  end

  local rep_needed = condition:match("^(%d+) rep$")
  if rep_needed then
    return get_counter_value(player.rep_counter) >= tonumber(rep_needed) and 1 or 0
  end

  local appeal_cap = condition:match("^max (%d+) appeal$")
  if appeal_cap then
    return get_counter_value(player.appeal_counter) <= tonumber(appeal_cap) and 1 or 0
  end

  local partner = condition:match("^(%S+) partner$")
  if partner then
    local n = 0
    for _, zoo in ipairs(player.acquired_partner_zoos) do
      if zoo == partner then n = n + 1 end
    end
    return n
  end

  return get_icon_counter_value(player.icon_counters[condition])
end

function conditions_unmet(card, player)
  local required = {}
  for _, condition in ipairs(card.conditions or {}) do
    required[condition] = (required[condition] or 0) + 1
  end

  local unmet = 0
  for condition, count in pairs(required) do
    local have = player_condition_supply(player, condition, card.type)
    if have < count then unmet = unmet + (count - have) end
  end
  return unmet
end

function first_unmet_condition(card, player)
  local seen = {}
  for _, condition in ipairs(card.conditions or {}) do
    if not seen[condition] then
      seen[condition] = true
      local needed = 0
      for _, c in ipairs(card.conditions) do
        if c == condition then needed = needed + 1 end
      end
      if player_condition_supply(player, condition, card.type) < needed then
        return condition
      end
    end
  end
  return nil
end

function animal_conditions_unmet(card, player, ignore_camouflage)
  local unmet = conditions_unmet(card, player)
  if player.waza_large_animal_program and card.size >= 4 then unmet = unmet - 1 end
  if player.research_institute_effect then unmet = unmet - 1 end
  if not ignore_camouflage then unmet = unmet - (player.camouflage or 0) end
  return unmet
end

function waza_assignment_type(player)
  return player.waza_special ~= nil and player.waza_special.type or nil
end

function waza_assignment_blocks(card, player)
  local taken = waza_assignment_type(player)
  if taken == "large" and card.size <= 2 then return true end
  if taken == "small" and card.size >= 4 then return true end
  return false
end

function waza_assignment_appeal(card, player)
  local taken = waza_assignment_type(player)
  if taken == "large" and card.size >= 4 then return 4 end
  if taken == "small" and card.size <= 2 then return 2 end
  return 0
end

function waza_special_assignment(player, source)
  local function option(which, label)
    return {
      button_text = label,
      source = source,
      async = true,
      function_call = function() take_waza_special_assignment(player, source, which) end
    }
  end

  create_claims_from_reward_groups(player, {}, true, {
    option("small", "Choose Small Animals\n(no longer play large animals)"),
    option("large", "Choose Large Animals\n(no longer play small animals)"),
  })
end

function played_sponsor_named(player, name)
  for _, guid in ipairs(player.played_sponsors) do
    local obj = getObjectFromGUID(guid)
    if obj ~= nil and string.sub(obj.getName(), 7) == name then return obj end
  end
  return nil
end

function take_waza_special_assignment(player, source, which)
  player.waza_special.type = which

  printToAll(string.format("%s takes the %s Animals assignment.",
    player.steam_name, which == "small" and "Small" or "Large"))

  local card = played_sponsor_named(player, source)
  local at = card_relative_world_position(card, "waza_special_" .. which)
  player.waza_special.cube = take_player_cube(player,
    { x = at.x, y = at.y + cnsts.drop_height, z = at.z }).getGUID()

  local finder = marine_worlds_enabled and search or discard_search
  finder(player, which .. "_animal", source, function()
    render_claims_table(player)
  end)
end

function is_animal_playable(card_name, player, display_pos, discounts)
  local card = card_data_for(card_name)
  discounts = discounts or {}

  if waza_assignment_blocks(card, player) then
    return false
  end

  local cost = animal_play_cost(card, player, display_pos) - (discounts.money or 0)
  if get_counter_value(player.money_counter) < cost then
    return false
  end
  if not animal_fits_enclosure(card, player)
     and not flock_available(card, player) then
    return false
  end
  return animal_conditions_unmet(card, player) - (discounts.condition or 0) <= 0
end

function animal_offerable(card_name, restrict)
  local data = card_data_for(card_name)
  if data.type ~= "animal" then return false end
  return restrict.max_size == nil or data.size <= restrict.max_size
end

function playable_animal_candidates(player, restrict, lookahead)
  restrict = restrict or {}
  local candidates = {}

  for _, card in ipairs(player_hand_cards(player)) do
    local name = card.getName()
    if animal_offerable(name, restrict) then
      table.insert(candidates, { name = name })
    end
  end

  if not restrict.hand_only and animals_upgraded(player) then
    local rep = get_counter_value(player.rep_counter) + (lookahead and lookahead.rep or 0)
    local free = (lookahead ~= nil and lookahead.draw) or nil
    for i, threshold in ipairs(cnsts.rep_range_thresholds) do
      if rep >= threshold and display_cards[i] ~= nil then
        local name = display_cards[i].getName()
        if animal_offerable(name, restrict) then
          table.insert(candidates, { name = name, display_pos = i, free = free })
        end
      end
    end
  end

  return candidates
end

function wait_for_hand_count(player, index, count, callback)
  Wait.condition(callback, function()
    return #Player[player.color].getHandObjects(index) == count
  end)
end

function wait_for_all_hand_counts(index, count, callback)
  Wait.condition(callback, function()
    for _, player in ipairs(players) do
      local want = (type(count) == "function") and count(player) or count
      if #Player[player.color].getHandObjects(index) ~= want then return false end
    end
    return true
  end)
end

function hand_holds_guids(color, index, guids)
  local present = {}
  for _, card in ipairs(Player[color].getHandObjects(index)) do
    present[card.getGUID()] = true
  end
  for _, guid in ipairs(guids) do
    if not present[guid] then return false end
  end
  return true
end

function other_hand_counts(color, index)
  local counts = {}
  for _, player in ipairs(players) do
    if player.color ~= color then
      counts[player.color] = #Player[player.color].getHandObjects(index)
    end
  end
  return counts
end

function other_hands_unchanged(counts, index)
  for color, want in pairs(counts) do
    if #Player[color].getHandObjects(index) ~= want then return false end
  end
  return true
end

function wait_for_cards_in_hand(player, index, cards, callback)
  local guids = {}
  for _, card in ipairs(cards) do guids[#guids + 1] = card.getGUID() end
  local others = other_hand_counts(player.color, index)

  Wait.condition(function() callback(cards) end, function()
    return hand_holds_guids(player.color, index, guids)
      and other_hands_unchanged(others, index)
  end)
end

function deal_cards_to_hand(deck, count, player, index, tag, callback)
  local dealt = {}
  for _ = 1, count do
    dealt[#dealt + 1] = deal_tagged_card(deck, nil, player.color, index, tag)
  end
  wait_for_cards_in_hand(player, index, dealt, callback)
end

function hands_released_guids(index, guids)
  local watched = {}
  for _, guid in ipairs(guids) do watched[guid] = true end
  for _, player in ipairs(players) do
    for _, card in ipairs(Player[player.color].getHandObjects(index)) do
      if watched[card.getGUID()] then return false end
    end
  end
  return true
end

function card_settled_in_hand(color, index, guid)
  for _, player in ipairs(players) do
    local holds = false
    for _, card in ipairs(Player[player.color].getHandObjects(index)) do
      if card.getGUID() == guid then holds = true break end
    end
    if holds ~= (player.color == color) then return false end
  end
  return true
end

function wait_for_cards_out_of_hand(player, index, cards, callback)
  local guids = {}
  for _, card in ipairs(cards) do guids[#guids + 1] = card.getGUID() end

  Wait.condition(callback, function()
    return hands_released_guids(index, guids)
  end)
end

function player_hand_cards(player)
  local played = {}
  for _, guid in ipairs(player.played_animals) do played[guid] = true end
  for _, guid in ipairs(player.played_sponsors) do played[guid] = true end
  for _, guid in ipairs(player.map_rescue_station or {}) do
    played[guid] = true
  end

  local cards = {}
  for _, card in ipairs(Player[player.color].getHandObjects(1)) do
    if not played[card.getGUID()] and not card.hasTag("store") then
      cards[#cards + 1] = card
    end
  end
  return cards
end

function player_has_animal_in_hand(player)
  for _, card in ipairs(player_hand_cards(player)) do
    if card_data_for(card.getName()).type == "animal" then return true end
  end
  return false
end

function deck_top_card_name()
  local top = zoo_deck.getObjects()[1]
  return top ~= nil and top.name or nil
end

function animals_rep_lookahead(player, strength, upgd, second)
  if second or not upgd or strength < 5 then return nil end

  local rep = get_counter_value(player.rep_counter)
  if rep >= max_reputation(player) then return nil end

  return { rep = 1, draw = cnsts.rep_rewards[rep + 1] == "draw 1" }
end

function rep_conditions_eased(card_name, player, lookahead)
  if lookahead == nil then return 0 end
  local rep = get_counter_value(player.rep_counter)
  local eased = 0
  for _, condition in ipairs(card_data_for(card_name).conditions or {}) do
    local needed = tonumber(condition:match("^(%d+) rep$") or "")
    if needed ~= nil and rep < needed and rep + lookahead.rep >= needed then
      eased = eased + 1
    end
  end
  return eased
end

function animals_action_available(player, strength, num, second)
  local upgd = animals_upgraded(player)
  if not upgd and strength <= 1 then return false end

  local discounts = { condition = 0, money = 0 }
  if not second and num == "1" and strength >= (upgd and 3 or 5) then
    discounts.condition = 1
  end
  if not second and num == "3" and not upgd then
    discounts.money = 2
  end
  if player.condition_3_discount then
    discounts.condition = discounts.condition + 3
  end

  local lookahead = animals_rep_lookahead(player, strength, upgd, second)

  local function playable(name, display_pos)
    local eased = discounts
    local relief = rep_conditions_eased(name, player, lookahead)
    if relief > 0 then
      eased = { condition = discounts.condition + relief, money = discounts.money }
    end
    return is_animal_playable(name, player, display_pos, eased)
  end

  for _, candidate in ipairs(playable_animal_candidates(player, nil, lookahead)) do
    local display_pos = candidate.display_pos
    if candidate.free then display_pos = nil end
    if playable(candidate.name, display_pos) then return true end
  end

  if lookahead ~= nil and lookahead.draw then
    local top = deck_top_card_name()
    if top ~= nil and animal_offerable(top, {}) and playable(top, nil) then
      return true
    end
  end

  return false
end


animal_actions = {}

function animal_bonus_threshold_met(state)
  return state.strength >= (state.upgd and 3 or 5)
end

function animal_discount_offered(state)
  return not state.second and state.num == "1" and animal_bonus_threshold_met(state)
end

function animal_second_offered(state)
  if state.second or not animal_bonus_threshold_met(state) then return false end
  return not (state.num == "1" and state.discount_on)
end

function animal_condition_token_offered(state)
  return state.player.condition_3_discount == true
end

function animal_action_discounts(state)
  local condition = (state.discount_on and animal_discount_offered(state)) and 1 or 0
  if state.condition_token_on and animal_condition_token_offered(state) then
    condition = condition + 3
  end
  return {
    condition = condition,
    money = (state.num == "3" and not state.upgd and not state.second) and 2 or 0,
  }
end

function animal_panel_xml(color, state)
  local body, height = "", 16 + 50 + 12

  if state.phase == "pick" then
    if state.restrict ~= nil then
      body = [[<Text fontSize="18" color="#FFFFFF">Select a small animal to play from your hand.
</Text>
      <Text fontSize="18" color="#FFFFFF"></Text>]]
      height = height + 30
    else
      body = [[<Text fontSize="18" color="#FFFFFF">Select an animal to play.
</Text>
      <Text fontSize="18" color="#FFFFFF"></Text>]]
    end
    height = height + 30
    if state.selected ~= nil then
      body = body .. string.format([[
        <Text fontSize="18" color="#FFFFFF">%s</Text>
        <Button id="animalConfirmButton_%s" onClick="on_animal_confirm_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">Confirm</Button>
        <Text fontSize="18" color="#FFFFFF"></Text>
      ]], "You have selected:\n" .. string.sub(state.selected.getName(), 7), color, color)
      height = height + 70 + 40 + 30
    end
    if animal_discount_offered(state) then
      body = body .. string.format([[
        <Button id="animalDiscountButton_%s" onClick="on_animal_discount_clicked(%s)" fontSize="16" width="240" height="52" minHeight="52" color="%s" textColor="#FFFFFF">%s</Button>
      ]], color, color, state.discount_on and "#3FA34D" or "#4A90D9",
          "Use -1 Condition\n(no second animal)")
      height = height + 58
    end
    if animal_condition_token_offered(state) then
      body = body .. string.format([[
        <Button id="animalConditionTokenButton_%s" onClick="on_animal_condition_token_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="%s" textColor="#FFFFFF">Use -3 Conditions Token</Button>
      ]], color, color, state.condition_token_on and "#3FA34D" or "#4A90D9")
      height = height + 40
    end
    if state.second then
      body = body .. string.format([[
        <Button id="animalPassButton_%s" onClick="on_animal_pass_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#C61715" textColor="#FFFFFF">Pass</Button>
      ]], color, color)
      height = height + 40
    end
  elseif state.phase == "enclosure" then
    body = [[<Text fontSize="18" color="#FFFFFF">Select an enclosure for this animal.</Text>]]
    height = height + 20
    if state.chosen ~= nil then
      body = body .. string.format([[
        <Button id="animalEnclosureConfirmButton_%s" onClick="on_animal_enclosure_confirm_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">Confirm</Button>
      ]], color, color)
      height = height + 40
    end
    if state.flock ~= nil then
      body = body .. string.format([[
        <Text fontSize="18" color="#FFFFFF"></Text>
        <Button id="animalFlockButton_%s" onClick="on_animal_flock_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">Use Flock effect</Button>
      ]], color, color)
      height = height + 30 + 40
    end
  else
    body = string.format([[<Text fontSize="18" color="#FFFFFF">Allocate the cubes for this animal (Total: %d).
</Text>]], state.allocate_total)
    height = height + 40
    local total = 0
    for _, row in ipairs(state.allocate_rows) do
      total = total + state.allocation[row.id]
      body = body .. string.format([[
        <HorizontalLayout spacing="6" minHeight="30" childAlignment="MiddleLeft" childForceExpandHeight="false">
          <Text fontSize="16" color="#FFFFFF" width="150" alignment="MiddleLeft">%s</Text>
          <Button onClick="on_animal_allocate_spin(%s)" fontSize="16" width="30" height="30" minHeight="30" color="#4A90D9" textColor="#FFFFFF">-</Button>
          <Text fontSize="16" color="#FFFFFF" width="24" alignment="MiddleCenter">%d</Text>
          <Button onClick="on_animal_allocate_spin(%s)" fontSize="16" width="30" height="30" minHeight="30" color="#4A90D9" textColor="#FFFFFF">+</Button>
        </HorizontalLayout>
      ]], row.label, color .. "|" .. row.id .. "|down", state.allocation[row.id],
          color .. "|" .. row.id .. "|up")
      height = height + 36
    end
    if total == state.allocate_total then
      body = body .. string.format([[
        <Button id="animalAllocateConfirmButton_%s" onClick="on_animal_allocate_confirm_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">Confirm</Button>
      ]], color, color)
      height = height + 40
    end
  end

  return string.format([[
    <Panel id="animalPanel_%s" visibility="%s" rectAlignment="MiddleRight" width="300" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        %s
      </VerticalLayout>
    </Panel>
  ]], color, color, height, body)
end

function clear_animal_action_state(player)
  animal_actions[player.color] = nil
  player.waza_small_run = nil
end

function offer_waza_small_animal_program(player)
  if not player.waza_small_run then return false end
  player.waza_small_run = nil

  table.insert(player.claims, { {
    button_text = "Snap 1 small animal",
    async = true,
    function_call = function() start_waza_small_snap(player) end
  } })

  table.insert(player.claims, { {
    button_text = "Play a small animal",
    optional = true,
    async = true,
    function_call = function() start_waza_small_play(player) end
  } })

  return true
end

function waza_small_play_available(player)
  for _, candidate in ipairs(playable_animal_candidates(player, cnsts.waza_small_play)) do
    if is_animal_playable(candidate.name, player, candidate.display_pos) then
      return true
    end
  end
  return false
end

function start_waza_small_play(player)
  retire_active_claim()

  if not waza_small_play_available(player) then
    broadcastToColor("You have no playable small animals!", player.color, "Red")
    render_claims_table(player)
    return
  end

  local action = animal_actions[player.color]
  set_animal_action(player, action.strength, action.num, true, cnsts.waza_small_play)
  open_animal_panel(player)
end

function waza_small_display_slots()
  local slots = {}
  for i = 1, 6 do
    local card = display_cards[i]
    if card ~= nil and animal_offerable(card.getName(), cnsts.waza_small_play) then
      slots[#slots + 1] = i
    end
  end
  return slots
end

function start_waza_small_snap(player)
  local slots = waza_small_display_slots()

  if #slots == 0 then
    broadcastToColor("There are no small animals on the display.", player.color, "Red")
    render_claims_table(player)
    return
  end

  if #slots == 1 then
    arm_snap(player, 1, false, nil, nil, cnsts.waza_small_play.max_size)
    handle_snap_pickup(slots[1])
    return
  end

  start_snap(player, 1, false, nil, nil, cnsts.waza_small_play.max_size)
end

function render_animal_panel(player)
  local state = animal_actions[player.color]
  set_player_panel(player.color, animal_panel_xml(player.color, state),
    function()
      local current = animal_actions[player.color]
      if current == nil then return end
      if current.phase == "pick" then add_animal_hand_offers(player) end
      render_animal_panel(player)
    end)
end

function set_animal_action(player, strength, num, second, restrict)
  local existing = animal_actions[player.color]
  local upgd = (second and existing ~= nil) and existing.upgd or player.animals_flipped

  if not second and player.waza_small_animal_program then
    player.waza_small_run = true
  end

  animal_actions[player.color] = {
    player = player,
    num = num,
    strength = strength,
    second = second,
    upgd = upgd,
    restrict = restrict,
    offers = {},
    selected = nil,
    discount_on = false,
    phase = "pick",
  }
end

function add_animal_hand_offers(player)
  local state = animal_actions[player.color]
  local restrict = state.restrict or {}
  for _, card in ipairs(player_hand_cards(player)) do
    if animal_offerable(card.getName(), restrict) then
      state.offers[card.getGUID()] = false
    end
  end
end

function open_animal_panel(player)
  local state = animal_actions[player.color]
  local restrict = state.restrict or {}

  for _, candidate in ipairs(playable_animal_candidates(player, state.restrict)) do
    if candidate.display_pos ~= nil then
      display_cards[candidate.display_pos].locked = false
    end
  end
  add_animal_hand_offers(player)
  if not restrict.hand_only and animals_upgraded(player) then
    local rep = get_counter_value(player.rep_counter)
    for i, threshold in ipairs(cnsts.rep_range_thresholds) do
      if rep >= threshold and display_cards[i] ~= nil
         and animal_offerable(display_cards[i].getName(), restrict) then
        state.offers[display_cards[i].getGUID()] = i
      end
    end
  end

  render_animal_panel(player)
end

function start_animals_action(player, strength, num)
  local upgd = player.animals_flipped
  printToAll(player.steam_name .. " takes the ANIMALS " .. (upgd and "II" or "I") ..
    " action at strength " .. strength .. ".")

  if num == "4" then
    table.insert(player.post_action_rewards, { "mark", "Animals 4" })
  end

  set_animal_action(player, strength, num, false)

  local hunter_count = (num == "2") and (upgd and 6 or 4) or nil

  if hunter_count ~= nil then
    table.insert(player.claims, { {
      button_text = "Hunter " .. hunter_count .. " (reveal hand)",
      optional = true,
      async = true,
      valid = function() return not player_has_animal_in_hand(player) end,
      function_call = function()
        retire_active_claim()
        local names = {}
        for _, card in ipairs(player_hand_cards(player)) do
          names[#names + 1] = string.sub(card.getName(), 7)
        end
        if #names == 0 then
          printToAll(player.steam_name .. " has no cards in hand.")
        else
          printToAll(player.steam_name .. " has no Animal cards in hand: " ..
            table.concat(names, ", ") .. ".")
        end
        hunter(player, hunter_count, "ANIMALS 2 effect")
      end
    } })
  end

  table.insert(player.claims, { {
    button_text = "Play an animal",
    async = true,
    function_call = function() open_animal_panel(player) end
  } })

  if upgd and strength >= 5 then
    update_rep(player, 1)
  else
    render_claims_table(player)
  end
end

function handle_animal_pickup(color, obj)
  local state = animal_actions[color]
  state.selected = obj

  render_animal_panel(state.player)
end

function on_animal_discount_clicked(_, color, _)
  local state = animal_actions[color]
  if state == nil or state.phase ~= "pick" then return end
  state.discount_on = not state.discount_on
  render_animal_panel(state.player)
end

function on_animal_condition_token_clicked(_, color, _)
  local state = animal_actions[color]
  if state == nil or state.phase ~= "pick" then return end
  if not animal_condition_token_offered(state) then return end
  state.condition_token_on = not state.condition_token_on
  render_animal_panel(state.player)
end

function on_animal_pass_clicked(_, color, _)
  local state = animal_actions[color]
  if state == nil or state.phase ~= "pick" or not state.second then return end

  state.phase = "done"
  state.offers = {}
  lock_display_cards()
  clear_player_panel(color)
  render_claims_table(state.player)
end

function on_animal_confirm_clicked(_, color, _)
  local state = animal_actions[color]
  if state == nil or state.phase ~= "pick" or state.selected == nil then return end

  local player = state.player
  local card = card_data_for(state.selected.getName())
  local discounts = animal_action_discounts(state)
  local display_pos = state.offers[state.selected.getGUID()] or nil

  if waza_assignment_blocks(card, player) then
    broadcastToColor("You cannot play that animal! (Waza Special Assignment)",
      color, "Red")
    return
  end

  local cost = animal_play_cost(card, player, display_pos) - discounts.money
  if get_counter_value(player.money_counter) < cost then
    broadcastToColor("You cannot play that animal! (Insufficient money: need " ..
      cost .. ")", color, "Red")
    return
  end

  local options = valid_animal_enclosures(card, player)
  local flock = flock_available(card, player) and flock_size(card) or nil
  if #options == 0 and flock == nil then
    broadcastToColor("You cannot play that animal! (No valid enclosure)", color, "Red")
    return
  end

  local unmet = animal_conditions_unmet(card, player) - discounts.condition
  if unmet > 0 then
    broadcastToColor("You cannot play that animal! (Unmet conditions: " .. unmet .. ")",
      color, "Red")
    return
  end

  state.cost = cost
  state.card = card
  state.options = options
  state.flock = flock

  if #options == 1 and flock == nil then
    state.chosen = { options[1] }
    apply_animal_to_enclosure(player, options[1], options[1].slots or 0)
    finish_animal_play(player)
  else
    start_enclosure_selection(player)
  end
end


function animal_pooled_group(state)
  if #state.options < 2 then return nil end
  local group = {}
  for _, option in ipairs(state.options) do
    if option.kind == "aquarium" and (option.slots or 0) > 1 then
      group[#group + 1] = option
    end
  end
  if #group < 2 then return nil end
  return group
end

function start_enclosure_selection(player)
  local state = animal_actions[player.color]
  state.phase = "enclosure"
  state.highlighted = {}
  state.chosen = nil

  for _, option in ipairs(state.options) do
    local tile = player.building_tiles[option.id]
    if tile ~= nil then tile.interactable = true end
  end

  render_animal_highlights(player, state)
  render_animal_panel(player)
end

function render_animal_highlights(player, state)
  local chosen = {}
  for _, option in ipairs(state.chosen or {}) do chosen[option.id] = true end

  state.highlighted = {}
  for _, option in ipairs(state.options) do
    local tile = player.building_tiles[option.id]
    if tile ~= nil then
      tile.highlightOn(chosen[option.id] and { 0, 1, 0 } or { 1, 0, 0 })
      state.highlighted[#state.highlighted + 1] = option.id
    end
  end
end

function clear_animal_highlights(player, state)
  for _, id in ipairs(state.highlighted) do
    local tile = player.building_tiles[id]
    if tile ~= nil then tile.highlightOff() end
  end
  state.highlighted = {}
end

function select_animal_enclosure(player, state, id)
  local picked = nil
  for _, option in ipairs(state.options) do
    if option.id == id then picked = option break end
  end
  if picked == nil then return end

  local group = animal_pooled_group(state)
  if group ~= nil and picked.kind == "aquarium" then
    state.chosen = group
  else
    state.chosen = { picked }
  end

  render_animal_highlights(player, state)
  render_animal_panel(player)
end

function on_animal_enclosure_confirm_clicked(_, color, _)
  local state = animal_actions[color]
  if state == nil or state.phase ~= "enclosure" or state.chosen == nil then return end

  local player = state.player
  clear_animal_highlights(player, state)
  for _, option in ipairs(state.options) do
    local tile = player.building_tiles[option.id]
    if tile ~= nil then tile.interactable = false end
  end

  if #state.chosen > 1 then
    start_cube_allocation(player)
    return
  end

  local option = state.chosen[1]
  apply_animal_to_enclosure(player, option, option.slots or 0)
  finish_animal_play(player)
end

function on_animal_flock_clicked(_, color, _)
  local state = animal_actions[color]
  if state == nil or state.phase ~= "enclosure" or state.flock == nil then return end

  local player = state.player
  clear_animal_highlights(player, state)
  for _, option in ipairs(state.options) do
    local tile = player.building_tiles[option.id]
    if tile ~= nil then tile.interactable = false end
  end

  printToAll(string.format("%s plays %s in a flock, with no enclosure.",
    player.steam_name, string.sub(state.selected.getName(), 7)))

  state.chosen = {}
  finish_animal_play(player)
end

function label_from_key(key)
  local words = {}
  for word in key:gmatch("[^_%s]+") do
    words[#words + 1] = word:sub(1, 1):upper() .. word:sub(2)
  end
  return table.concat(words, " ")
end

function habitat_label(habitat)
  if habitat == "america" then return "Americas" end
  return label_from_key(habitat)
end

function start_cube_allocation(player)
  local state = animal_actions[player.color]
  state.phase = "allocate"
  state.allocate_total = state.chosen[1].slots
  state.allocate_rows = {}
  state.allocation = {}

  for i, option in ipairs(state.chosen) do
    state.allocation[option.id] = 0
    state.allocate_rows[i] = {
      id = option.id,
      label = label_from_key(player.map.tiles[option.id].tags.type),
    }
  end

  render_animal_panel(player)
end

function on_animal_allocate_spin(_, value, _)
  local color, id, direction = value:match("^(%a+)|(%d+)|(%a+)$")
  local state = animal_actions[color]
  if state == nil or state.phase ~= "allocate" then return end

  id = tonumber(id)
  local current = state.allocation[id]
  if direction == "up" then
    local assigned = 0
    for _, count in pairs(state.allocation) do assigned = assigned + count end
    if assigned < state.allocate_total then
      state.allocation[id] = math.min(current + 1, tile_slots(state.player.map, id))
    end
  else
    state.allocation[id] = math.max(current - 1, 0)
  end

  render_animal_panel(state.player)
end

function on_animal_allocate_confirm_clicked(_, color, _)
  local state = animal_actions[color]
  if state == nil or state.phase ~= "allocate" then return end

  local total = 0
  for _, count in pairs(state.allocation) do total = total + count end
  if total ~= state.allocate_total then return end

  local player = state.player
  for _, option in ipairs(state.chosen) do
    local count = state.allocation[option.id]
    if count > 0 then
      apply_animal_to_enclosure(player, option, count)
    end
  end
  finish_animal_play(player)
end

function apply_animal_to_enclosure(player, option, count)
  local map = player.map
  local tile = map.tiles[option.id]
  local obj = player.building_tiles[option.id]

  if option.kind == "size" then
    tile.tags.occupied = true
    set_tile_face(obj, true)

    if map:tileTouchesSpecial(option.id, "observation tower") then
      update_appeal(player, 2, "Observation Tower")
    end

    refresh_map_income(player)
    return
  end

  place_enclosure_cubes(player, option.id, count)
  tile.tags.slots = tile.tags.slots - count
end

function place_enclosure_cubes(player, id, count)
  local map = player.map
  local obj = player.building_tiles[id]
  local points = obj.getSnapPoints()
  local tags = map.tiles[id].tags
  local total = #map.tiles[id].cells
  local filled = total - tags.slots

  tags.cubes = tags.cubes or {}

  for k = 1, count do
    local sp = points[filled + k]
    local pos = obj.positionToWorld(sp.position)
    local cube = take_player_cube(player, { x = pos.x, y = pos.y + 0.3, z = pos.z })
    cube.jointTo(obj, { type = "Fixed", collision = false })
    tags.cubes[#tags.cubes + 1] = cube.getGUID()
  end
end

function remove_enclosure_cubes(player, id, count)
  local cubes = player.map.tiles[id].tags.cubes or {}
  local removed = 0

  for _ = 1, count do
    local guid = table.remove(cubes)
    if guid == nil then break end
    local cube = getObjectFromGUID(guid)
    if cube ~= nil then cube.destruct() end
    removed = removed + 1
  end

  return removed
end

function enclosure_cube_count(player, id)
  return #(player.map.tiles[id].tags.cubes or {})
end


animal_moves = {}

function movable_animals(player, state)
  local map = player.map
  local allowed = buildable_terrain(player)
  local free = tile_slots(map, state.id)
  local out = {}

  for _, guid in ipairs(player.played_animals) do
    if not state.moved[guid] then
      local obj = getObjectFromGUID(guid)
      if obj ~= nil then
        local card = card_data_for(obj.getName())
        local required = card.enclosure and card.enclosure[state.key]
        if required ~= nil and required <= free
           and tile_meets_terrain(map, state.id, animal_terrain_needs(card),
                                  allowed, state.key == "aquarium") then
          local _, blocked = enclosure_vacate_plan(player, card, state.key)
          if not blocked then
            out[#out + 1] = { guid = guid, card = card, required = required,
                              name = string.sub(obj.getName(), 7) }
          end
        end
      end
    end
  end

  return out
end

function vacate_terrain_passes(card)
  local need = animal_terrain_needs(card)
  if need.rock > 0 or need.water > 0 then return { true, false } end
  return { false }
end

function animal_special_keys(card)
  local out = {}
  for _, key in ipairs(cnsts.special_enclosure_order) do
    if card.enclosure ~= nil and card.enclosure[key] ~= nil then
      out[#out + 1] = key
    end
  end
  return out
end

function special_enclosure_buildings(player, card, key, honour_terrain)
  local map = player.map
  local need = animal_terrain_needs(card)
  local allowed = buildable_terrain(player)
  local ignore_water = (key == "aquarium")
  local out = {}

  for _, type_name in ipairs(cnsts.animal_enclosure_types[key]) do
    for _, id in ipairs(map:tilesWithTag(type_name)) do
      if not honour_terrain
         or tile_meets_terrain(map, id, need, allowed, ignore_water) then
        out[#out + 1] = id
      end
    end
  end

  table.sort(out)
  return out
end

function smallest_standard_enclosures(player, card, honour_terrain)
  local map = player.map
  local need = animal_terrain_needs(card)
  local allowed = buildable_terrain(player)
  local capacity_opts = enclosure_capacity_opts(player)

  local smallest, out = nil, {}
  for id, tile in pairs(map.tiles) do
    local capacity = map:enclosureCapacity(id, capacity_opts)
    if capacity ~= nil and tile.tags.occupied == true
       and capacity >= card.size
       and (not honour_terrain
            or tile_meets_terrain(map, id, need, allowed, false)) then
      if smallest == nil or capacity < smallest then
        smallest, out = capacity, { id }
      elseif capacity == smallest then
        out[#out + 1] = id
      end
    end
  end

  table.sort(out)
  return out
end

function enclosure_vacate_plan(player, card, forbid)
  for _, honour_terrain in ipairs(vacate_terrain_passes(card)) do
    local hits = {}
    for _, key in ipairs(animal_special_keys(card)) do
      local required = card.enclosure[key]
      local ids = special_enclosure_buildings(player, card, key, honour_terrain)
      local total = 0
      for _, id in ipairs(ids) do
        total = total + enclosure_cube_count(player, id)
      end
      if #ids > 0 and total >= required then
        hits[#hits + 1] = { key = key, ids = ids, required = required, total = total }
      end
    end

    if #hits > 0 then
      local legal = {}
      for _, hit in ipairs(hits) do
        if hit.key ~= forbid then legal[#legal + 1] = hit end
      end
      if #legal == 0 then return nil, true end
      return { kind = "special", hits = legal }
    end

    if not card.no_std_enc then
      local ids = smallest_standard_enclosures(player, card, honour_terrain)
      if #ids > 0 then return { kind = "standard", ids = ids } end
    end
  end

  return nil, false
end

enclosure_vacates = {}

function start_enclosure_vacate(player, card, name, forbid, on_done)
  local plan = enclosure_vacate_plan(player, card, forbid)
  if plan == nil then
    on_done(nil)
    return
  end

  enclosure_vacates[player.color] = {
    player = player, card = card, name = name, forbid = forbid,
    on_done = on_done, highlighted = {},
  }

  if plan.kind == "standard" then
    begin_vacate_standard(player, plan.ids)
  elseif #plan.hits > 1 then
    begin_vacate_type_choice(player, plan.hits)
  else
    begin_vacate_special(player, plan.hits[1])
  end
end

function finish_enclosure_vacate(player, result)
  local state = enclosure_vacates[player.color]
  enclosure_vacates[player.color] = nil
  clear_player_panel(player.color)
  state.on_done(result)
end


function begin_vacate_type_choice(player, hits)
  local state = enclosure_vacates[player.color]
  state.phase = "type"
  state.hits = hits
  render_enclosure_vacate_panel(player)
end

function on_enclosure_vacate_type_clicked(_, value, _)
  local color, index = value:match("^(%a+)|(%d+)$")
  local state = enclosure_vacates[color]
  if state == nil or state.phase ~= "type" then return end

  local hit = state.hits[tonumber(index)]
  if hit == nil then return end
  begin_vacate_special(state.player, hit)
end


function begin_vacate_special(player, hit)
  local state = enclosure_vacates[player.color]
  state.key, state.required = hit.key, hit.required

  local holders = {}
  for _, id in ipairs(hit.ids) do
    if enclosure_cube_count(player, id) > 0 then holders[#holders + 1] = id end
  end

  if #holders > 1 and hit.total > hit.required then
    state.phase = "allocate"
    state.ids = holders
    state.allocation = {}
    for _, id in ipairs(holders) do state.allocation[id] = 0 end
    render_enclosure_vacate_panel(player)
    return
  end

  local allocation, left = {}, hit.required
  for _, id in ipairs(holders) do
    local take = math.min(left, enclosure_cube_count(player, id))
    allocation[id] = take
    left = left - take
    if left == 0 then break end
  end
  commit_vacate_special(player, allocation)
end

function on_enclosure_vacate_allocate_spin(_, value, _)
  local color, id, direction = value:match("^(%a+)|(%d+)|(%a+)$")
  local state = enclosure_vacates[color]
  if state == nil or state.phase ~= "allocate" then return end

  id = tonumber(id)
  local current = state.allocation[id]
  if direction == "up" then
    local assigned = 0
    for _, n in pairs(state.allocation) do assigned = assigned + n end
    if assigned < state.required then
      state.allocation[id] =
        math.min(current + 1, enclosure_cube_count(state.player, id))
    end
  else
    state.allocation[id] = math.max(current - 1, 0)
  end

  render_enclosure_vacate_panel(state.player)
end

function on_enclosure_vacate_allocate_confirm_clicked(_, color, _)
  local state = enclosure_vacates[color]
  if state == nil or state.phase ~= "allocate" then return end

  local total = 0
  for _, n in pairs(state.allocation) do total = total + n end
  if total ~= state.required then return end

  commit_vacate_special(state.player, state.allocation)
end

function commit_vacate_special(player, allocation)
  local state = enclosure_vacates[player.color]
  local removals, freed = {}, 0

  local ids = {}
  for id in pairs(allocation) do ids[#ids + 1] = id end
  table.sort(ids)

  for _, id in ipairs(ids) do
    local count = allocation[id]
    if count > 0 then
      local removed = remove_enclosure_cubes(player, id, count)
      player.map.tiles[id].tags.slots = player.map.tiles[id].tags.slots + removed
      freed = freed + removed
      removals[#removals + 1] = { id = id, count = removed }
    end
  end

  finish_enclosure_vacate(player, {
    kind = "special", key = state.key, removals = removals, freed = freed,
    label = cnsts.special_enclosure_labels[state.key],
  })
end


function begin_vacate_standard(player, ids)
  local state = enclosure_vacates[player.color]

  if #ids == 1 then
    commit_vacate_standard(player, ids[1])
    return
  end

  state.phase = "standard"
  state.options = ids
  state.chosen = nil
  for _, id in ipairs(ids) do
    local tile = player.building_tiles[id]
    if tile ~= nil then tile.interactable = true end
  end
  render_enclosure_vacate_highlights(player, state)
  render_enclosure_vacate_panel(player)
end

function render_enclosure_vacate_highlights(player, state)
  state.highlighted = {}
  for _, id in ipairs(state.options or {}) do
    local tile = player.building_tiles[id]
    if tile ~= nil then
      tile.highlightOn(state.chosen == id and { 0, 1, 0 } or { 1, 0, 0 })
      state.highlighted[#state.highlighted + 1] = id
    end
  end
end

function clear_enclosure_vacate_highlights(player, state)
  for _, id in ipairs(state.highlighted or {}) do
    local tile = player.building_tiles[id]
    if tile ~= nil then tile.highlightOff() end
  end
  state.highlighted = {}
  for _, id in ipairs(state.options or {}) do
    local tile = player.building_tiles[id]
    if tile ~= nil then tile.interactable = false end
  end
end

function select_enclosure_to_vacate(player, state, id)
  for _, option in ipairs(state.options or {}) do
    if option == id then
      state.chosen = id
      render_enclosure_vacate_highlights(player, state)
      render_enclosure_vacate_panel(player)
      return
    end
  end
end

function on_enclosure_vacate_confirm_clicked(_, color, _)
  local state = enclosure_vacates[color]
  if state == nil or state.phase ~= "standard" or state.chosen == nil then return end

  local player, id = state.player, state.chosen
  clear_enclosure_vacate_highlights(player, state)
  commit_vacate_standard(player, id)
end

function commit_vacate_standard(player, id)
  local tile = player.map.tiles[id]
  local printed = tile.tags.type:match("^size_(%d)$")

  tile.tags.occupied = false
  set_tile_face(player.building_tiles[id], false)
  refresh_map_income(player)

  finish_enclosure_vacate(player, { kind = "standard", id = id, printed = printed })
end


function vacate_report(result)
  if result == nil then return "" end
  if result.kind == "standard" then
    return ", freeing a size-" .. result.printed .. " enclosure"
  end
  return string.format(", freeing %d slot%s in their %s",
    result.freed, result.freed == 1 and "" or "s", result.label)
end

function enclosure_vacate_panel_xml(color, state)
  local body, height = "", 16 + 50 + 12

  if state.phase == "type" then
    body = string.format([[<Text fontSize="18" color="#FFFFFF">Release %s from which enclosure?</Text>
      <Text fontSize="18" color="#FFFFFF"></Text>]], state.name)
    height = height + 50 + 30
    for i, hit in ipairs(state.hits) do
      body = body .. string.format([[
        <Button id="animalReleaseTypeButton_%s_%d" onClick="on_enclosure_vacate_type_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">%s</Button>
      ]], color, i, color .. "|" .. i, cnsts.special_enclosure_labels[hit.key])
      height = height + 40
    end
  elseif state.phase == "allocate" then
    body = string.format([[<Text fontSize="18" color="#FFFFFF">Take %d cubes off your Aquariums.
</Text>]], state.required)
    height = height + 40
    local total = 0
    for _, id in ipairs(state.ids) do
      total = total + state.allocation[id]
      body = body .. string.format([[
        <HorizontalLayout spacing="6" minHeight="30" childAlignment="MiddleLeft" childForceExpandHeight="false">
          <Text fontSize="16" color="#FFFFFF" width="150" alignment="MiddleLeft">%s</Text>
          <Button onClick="on_enclosure_vacate_allocate_spin(%s)" fontSize="16" width="30" height="30" minHeight="30" color="#4A90D9" textColor="#FFFFFF">-</Button>
          <Text fontSize="16" color="#FFFFFF" width="24" alignment="MiddleCenter">%d</Text>
          <Button onClick="on_enclosure_vacate_allocate_spin(%s)" fontSize="16" width="30" height="30" minHeight="30" color="#4A90D9" textColor="#FFFFFF">+</Button>
        </HorizontalLayout>
      ]], label_from_key(state.player.map.tiles[id].tags.type),
          color .. "|" .. id .. "|down", state.allocation[id],
          color .. "|" .. id .. "|up")
      height = height + 36
    end
    if total == state.required then
      body = body .. string.format([[
        <Button id="animalReleaseAllocateConfirmButton_%s" onClick="on_enclosure_vacate_allocate_confirm_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">Confirm</Button>
      ]], color, color)
      height = height + 40
    end
  else
    body = [[<Text fontSize="18" color="#FFFFFF">Select an enclosure to free up.</Text>]]
    height = height + 20
    if state.chosen ~= nil then
      body = body .. string.format([[
        <Button id="animalReleaseEnclosureConfirmButton_%s" onClick="on_enclosure_vacate_confirm_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">Confirm</Button>
      ]], color, color)
      height = height + 40
    end
  end

  return string.format([[
    <Panel id="animalReleasePanel_%s" visibility="%s" rectAlignment="MiddleRight" width="300" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        %s
      </VerticalLayout>
    </Panel>
  ]], color, color, height, body)
end

function render_enclosure_vacate_panel(player)
  set_player_panel(player.color,
    enclosure_vacate_panel_xml(player.color, enclosure_vacates[player.color]))
end

function animal_move_panel_xml(color, state)
  local body, height = "", 16 + 50 + 12

  body = string.format([[<Text fontSize="18" color="#FFFFFF">Choose animal to place in the %s.
(Remaining slots: %d)</Text>
    <Text fontSize="18" color="#FFFFFF"></Text>]],
    state.label, tile_slots(state.player.map, state.id))
  height = height + 70 + 30

  for i, offer in ipairs(state.offers) do
    body = body .. string.format([[
      <Button id="animalMoveButton_%s_%d" onClick="on_animal_move_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">%s</Button>
    ]], color, i, color .. "|" .. i, offer.name)
    height = height + 40
  end

  body = body .. string.format([[
    <Text fontSize="18" color="#FFFFFF"></Text>
    <Button id="animalMovePassButton_%s" onClick="on_animal_move_pass_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#C61715" textColor="#FFFFFF">Pass</Button>
  ]], color, color)
  height = height + 30 + 40

  return string.format([[
    <Panel id="animalMovePanel_%s" visibility="%s" rectAlignment="MiddleRight" width="300" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        %s
      </VerticalLayout>
    </Panel>
  ]], color, color, height, body)
end

function render_animal_move_panel(player)
  local state = animal_moves[player.color]
  state.offers = movable_animals(player, state)
  set_player_panel(player.color, animal_move_panel_xml(player.color, state))
end

function start_animal_move(player, id, tag)
  animal_moves[player.color] = {
    player = player,
    id = id,
    key = cnsts.rehousing_enclosures[tag],
    label = label_from_key(tag),
    moved = {},
    offers = {},
  }
  render_animal_move_panel(player)
end

function on_animal_move_clicked(_, value, _)
  local color, index = value:match("^(%a+)|(%d+)$")
  local state = animal_moves[color]
  if state == nil then return end

  local offer = state.offers[tonumber(index)]
  if offer == nil then return end

  local player = state.player
  state.animal, state.card, state.required = offer.guid, offer.card, offer.required

  clear_player_panel(player.color)
  start_enclosure_vacate(player, offer.card, offer.name, state.key,
    function(result) finish_animal_move(player, result) end)
end

function finish_animal_move(player, result)
  local state = animal_moves[player.color]
  local name = string.sub(getObjectFromGUID(state.animal).getName(), 7)

  apply_animal_to_enclosure(player, { id = state.id, kind = state.key },
    state.required)
  state.moved[state.animal] = true

  printToAll(string.format("%s moves %s into their %s%s.",
    player.steam_name, name, state.label, vacate_report(result)))

  state.animal, state.card, state.required = nil, nil, nil
  state.phase = "pick"

  if tile_slots(player.map, state.id) > 0 and #movable_animals(player, state) > 0 then
    render_animal_move_panel(player)
    return
  end

  close_animal_move(player)
end

function on_animal_move_pass_clicked(_, color, _)
  local state = animal_moves[color]
  if state == nil then return end
  close_animal_move(state.player)
end

function close_animal_move(player)
  animal_moves[player.color] = nil
  clear_player_panel(player.color)
  render_claims_table(player)
end

function animal_move_claim(player, tag, id)
  if tag == nil or cnsts.rehousing_enclosures[tag] == nil then return nil end

  local probe = { player = player, id = id,
                  key = cnsts.rehousing_enclosures[tag], moved = {} }
  if #movable_animals(player, probe) == 0 then return nil end

  return {
    button_text = "Move animals to this enclosure",
    optional = true,
    async = true,
    valid = function() return #movable_animals(player, probe) > 0 end,
    function_call = function()
      retire_active_claim()
      start_animal_move(player, id, tag)
    end
  }
end


function played_animal_position(board_pos, index)
  local pos = board_relative_world_position(board_pos, "played_cards_col_1")
  for _ = 1, math.floor((index - 1) / 2) do
    pos = pos + cnsts.board_relative_positions.played_cards_row_offset
  end
  for _ = 1, (index - 1) % 2 do
    pos = pos + cnsts.board_relative_positions.played_cards_col_offset
  end
  return pos
end

function finish_animal_play(player)
  local state = animal_actions[player.color]
  local obj = state.selected
  local name = string.sub(obj.getName(), 7)

  update_money(player, -state.cost, name)

  local display_pos = state.offers[obj.getGUID()]
  local own_mark = false
  if display_pos and display_marks[display_pos] ~= nil then
    own_mark =
      cube_owner_color(getObjectFromGUID(display_marks[display_pos])) == player.color
  end
  if display_pos then
    resolve_display_mark(display_pos, false)
    display_cards[display_pos] = nil
  end

  table.insert(player.played_animals, obj.getGUID())
  local index = #player.played_animals
  obj.setPosition(played_animal_position(player.player_board.getPosition(), index))
  obj.setRotation({ 0, 180, 0 })
  obj.locked = true

  lock_display_cards()
  clear_player_panel(player.color)

  local card = state.card
  local strength, num = state.strength, state.num
  local second_offered = animal_second_offered(state)

  local waza_appeal = waza_assignment_appeal(card, player)
  if waza_appeal > 0 then
    update_appeal(player, waza_appeal, "Waza Special Assignment")
  end

  if card.size > 2 then
    player.waza_small_run = nil
  end

  local shortfall = animal_conditions_unmet(card, player, true)
    - animal_action_discounts(state).condition
  local camouflage_used = math.min(math.max(shortfall, 0), player.camouflage or 0)
  if camouflage_used > 0 then
    player.camouflage = player.camouflage - camouflage_used
  end

  if state.condition_token_on and player.condition_3_discount then
    player.condition_3_discount = nil
    spend_bonus_token(player, "TOKEN: -3 conditions")
  end

  state.phase = "done"
  state.offers = {}
  if second_offered then
    set_animal_action(player, strength, num, true)
  end

  if second_offered then
    table.insert(player.claims, { {
      button_text = "Play second animal",
      optional = true,
      async = true,
      valid = function() return animals_action_available(player, strength, num, true) end,
      function_call = function()
        retire_active_claim()
        open_animal_panel(player)
      end
    } })
  end

  local groups = { { rewards = card.rewards or {}, source = name } }

  if own_mark and num == "4" and animals_upgraded(player) then
    groups[#groups + 1] = { rewards = { "1 rep" }, source = "playing their marked animal" }
  end

  local habitat = geographical_zoo_reward(player, card, state.chosen or {})
  if habitat ~= nil then
    for _, group in ipairs(geographical_cube_groups(player, habitat, name)) do
      groups[#groups + 1] = group
    end
  end

  if card.reef ~= nil then
    for _, guid in ipairs(player.played_animals) do
      local played = getObjectFromGUID(guid)
      local data = played ~= nil and card_data_for(played.getName()) or nil
      if data ~= nil and data.reef ~= nil and data.reef ~= "" then
        groups[#groups + 1] = {
          rewards = { data.reef },
          source = string.sub(played.getName(), 7) .. "'s reef effect"
        }
      end
    end
  end

  append_icon_groups(groups, player, card.icons)

  local extra = nil
  if num == "3" and animals_upgraded(player) then
    extra = { {
      button_text = "Pay 2 Money for 1 Appeal",
      optional = true,
      valid = function() return get_counter_value(player.money_counter) >= 2 end,
      function_call = function()
        update_money(player, -2)
        update_appeal(player, 1, "Animals 3")
        return true
      end
    } }
  end

  wait_for_cards_out_of_hand(player, 1, { obj }, function()
    create_claims_from_reward_groups(player, groups, nil, extra)
  end)
end

function container_holds_guid(container, guid)
  for _, entry in ipairs(container.getObjects()) do
    if entry.guid == guid then return true end
  end
  return false
end

function departures_landed(leaving)
  for _, entry in ipairs(leaving) do
    if entry.color == nil then
      if not container_holds_guid(discard_pile, entry.guid) then return false end
    elseif not card_settled_in_hand(entry.color, 1, entry.guid) then
      return false
    end
  end
  return true
end

function wait_for_departures(leaving, done)
  if done == nil then return end
  if departures_landed(leaving) then
    done()
    return
  end
  Wait.condition(done, function() return departures_landed(leaving) end)
end

function refill_display(done, leaving)
  leaving = leaving or {}

  local virtual = {}
  for i = 1, 6 do
    if display_cards[i] ~= nil then
      table.insert(virtual, { card = display_cards[i], mark = display_marks[i], slot = i })
    end
  end

  local deck_objects = zoo_deck.getObjects()
  local drawn = 0
  local washed = {}
  local washed_by = {}

  while #virtual < 6 do
    drawn = drawn + 1
    local info = deck_objects[drawn]
    table.insert(virtual, { guid = info.guid })

    if card_has_wave(info.name) then
      local removed = table.remove(virtual, 1)
      if removed.card ~= nil then
        table.insert(washed, removed)
        washed_by[info.guid] = removed.card
      end
    end
  end

  for _, entry in ipairs(washed) do
    local card = entry.card
    local guid = card.getGUID()
    local marker = redirect_marked_discard(entry.slot, card)
    if marker then
      leaving[#leaving + 1] = { guid = guid, color = marker.color }
    else
      leaving[#leaving + 1] = { guid = guid }
      Wait.condition(function() card.locked=false discard_pile.putObject(card) end,
                     function() return not card.isSmoothMoving() end)
    end
  end

  display_marks = {}
  for i, entry in ipairs(virtual) do
    if entry.card ~= nil then
      display_cards[i] = entry.card
      display_marks[i] = entry.mark
      entry.card.setPositionSmooth(cnsts.display_locs[i], false, false)
      move_display_mark(i, cnsts.display_locs[i])
    else
      local card = zoo_deck.takeObject({
        guid = entry.guid,
        position = cnsts.display_locs[i],
        rotation = { 0, 180, 0 },
        smooth = true
      })
      card.addTag("zoo_card")
      card.locked = true
      display_cards[i] = card
      printToAll("The display is replenished with " .. string.sub(card.getName(), 7) .. ".")

      local victim = washed_by[entry.guid]
      if victim ~= nil then
        printToAll(string.sub(victim.getName(), 7) .. " was washed away by the wave!")
      end
    end
  end

  wait_for_departures(leaving, done)
end

break_phase_resume = nil

local BREAK_RESUMES = {
  after_turn = function(resume)
    local player = find_player_by_color(resume.color)
    if game_end_triggered and not resume.last_round_owed
       and final_turn_player.color == player.color then
      start_final_scoring()
      return
    end

    start_player_turn(next_player(player))
  end
}

function run_break_resume(resume)
  BREAK_RESUMES[resume.handler](resume)
end

function solo_turn_track_active()
  return #players == 1 and solo_turn_cubes ~= nil and #solo_turn_cubes > 0
end

function solo_break_due()
  return solo_turn_track_active()
    and solo_cubes_advanced >= #solo_turn_cubes
end

function check_break_trigger(resume)
  local due
  if #players == 1 then
    due = solo_break_due()
  else
    due = break_current_val == 0
  end

  if not due then
    run_break_resume(resume)
    return
  end

  broadcastToAll(current_player.steam_name .. " has triggered a break!")
  break_phase_resume = resume

  break_phase_discard()
end

function break_phase_discard()
  local discarders = {}
  for _, player in ipairs(players) do
    local limit = 3 + (player.hand_size_plus_1 and 1 or 0)
    for _, uni in ipairs(player.acquired_universities) do
      if uni == "hand_size" then
        limit = limit + 2
        break
      end
    end

    local hand = Player[player.color].getHandObjects(1)
    if #hand > limit then
      table.insert(discarders, { player = player, limit = limit })
    end
  end

  if #discarders == 0 then
    break_phase_card_tokens()
    return
  end

  local pending = #discarders

  local discarding = {}
  for _, d in ipairs(discarders) do discarding[d.player.color] = true end
  for _, p in ipairs(players) do
    if not discarding[p.color] then
      set_waiting_status(p, cnsts.waiting_to_discard)
    end
  end

  for _, d in ipairs(discarders) do
    create_card_selection_panel(d.player,
      function() return Player[d.player.color].getHandObjects(1) end,
      function() return #Player[d.player.color].getHandObjects(1) - d.limit end,
      "discard", function()
      pending = pending - 1
      if pending == 0 then
        clear_waiting_status()
        break_phase_card_tokens()
      else
        set_waiting_status(d.player, cnsts.waiting_to_discard)
      end
    end)
  end
end

function break_phase_card_tokens()
  for _, player in ipairs(players) do
    for slot = 1, 5 do
      local record = player.action_cards[slot]
      if record ~= nil then
        for _, guid in ipairs(action_card_token_guids(record)) do
          discard_action_card_token(getObjectFromGUID(guid))
        end
        record.tokens = {}
      end
    end
  end

  break_phase_association()
end

function worker_home_index(player, guid)
  for n, g in ipairs(player.workers) do
    if g == guid then return n end
  end
  return nil
end

function send_worker_home(player, guid)
  local worker = getObjectFromGUID(guid)
  worker.setPositionSmooth(board_relative_world_position(
    player.player_board.getPosition(),
    "worker_" .. worker_home_index(player, guid) .. "_home"), false, false)
  worker.setRotation(cnsts.worker_rotation)
end

function break_phase_association()
  refill_association_board()

  for _, player in ipairs(players) do
    for _, entry in ipairs(player.deployed_workers) do
      send_worker_home(player, entry.guid)
    end
    player.deployed_workers = {}
  end

  break_phase_display()
end

function break_phase_display()
  local discarded = {}
  local leaving = {}
  for slot = 1, 2 do
    local card = display_cards[slot]
    if card ~= nil then
      local guid, name = card.getGUID(), string.sub(card.getName(), 7)
      local marker = redirect_marked_discard(slot, card)
      if marker then
        leaving[#leaving + 1] = { guid = guid, color = marker.color }
      else
        discarded[#discarded + 1] = name
        leaving[#leaving + 1] = { guid = guid }
        card.locked = false
        discard_pile.putObject(card)
      end
    end
    display_cards[slot] = nil
  end

  if #discarded > 0 then
    printToAll(string.format("%s %s discarded from the display.",
      table.concat(discarded, " and "), #discarded == 1 and "was" or "were"))
  end

  refill_display(break_phase_income, leaving)
end

function break_phase_income()
  start_income_phase()
end

function finish_break_trigger()
  if #players == 1 then
    reset_solo_turn_track()
  else
    break_current_val = break_init_val
    move_break_token(break_current_val)
  end

  if not game_end_triggered and any_player_at_game_end_score() then
    trigger_game_end(current_player)
    break_phase_resume.last_round_owed = true
  end

  local resume = break_phase_resume
  break_phase_resume = nil
  run_break_resume(resume)
end


income_players = {}

income_phase_order = nil
income_phase_index = 0

function start_income_phase()
  local start = 1
  for i, p in ipairs(players) do
    if p.color == current_player.color then start = i break end
  end

  income_phase_order = {}
  for i = 0, #players - 1 do
    income_phase_order[#income_phase_order + 1] = players[((start - 1 + i) % #players) + 1]
  end
  income_phase_index = 0

  advance_income_phase()
end

function advance_income_phase()
  if income_phase_index >= 1 then
    refill_display(continue_income_phase)
    return
  end
  continue_income_phase()
end

function continue_income_phase()
  income_phase_index = income_phase_index + 1

  if income_phase_index > #income_phase_order then
    clear_waiting_status()
    income_phase_order, income_phase_index = nil, 0
    finish_break_trigger()
    return
  end

  local player = income_phase_order[income_phase_index]

  rearm_effect(player, "landscape_gardener")

  for _, p in ipairs(players) do
    if p.color == player.color then
      player_status[p.color] = nil
    else
      set_waiting_status(p, player.steam_name .. " is collecting their income...")
    end
  end

  start_player_income(player)
end

function start_player_income(player)
  take_checkpoint("income", player)

  player.income_pending = {}
  for _, item in ipairs(player.income) do
    for _, reward in ipairs(reward_offers(item.reward)) do
      player.income_pending[#player.income_pending + 1] =
        { reward = reward, source = item.source }
    end
  end

  table.insert(player.income_pending, { collect = true })

  render_income_table(player)
end

function add_income(player, income, source)
  if type(income) == "function" then income = income(player) end
  if income == nil or income == "" then return end

  local amount = income:match("^(%d+) money$")
  if amount ~= nil then
    set_counter(player.income_counter,
      get_counter_value(player.income_counter) + tonumber(amount),
      cnsts.counter_style.income)
    return
  end

  table.insert(player.income, { reward = income, source = source })
end

function remove_income(player, income, source)
  if type(income) == "function" then income = income(player) end
  if income == nil or income == "" then return false end

  local amount = income:match("^(%d+) money$")
  if amount ~= nil then
    set_counter(player.income_counter,
      get_counter_value(player.income_counter) - tonumber(amount),
      cnsts.counter_style.income)
    return true
  end

  return remove_income_reward(player, income, source)
end

function remove_income_reward(player, reward, source)
  local removed = false
  for _, list in ipairs({ player.income, player.income_pending }) do
    for i, item in ipairs(list) do
      if item.reward == reward and item.source == source then
        table.remove(list, i)
        removed = true
        break
      end
    end
  end
  return removed
end

function income_item_text(player, item)
  if item.collect then
    return "Collect Income: " .. get_counter_value(player.income_counter) .. " Money"
  end
  return reward_button_text(item.reward, player, item.source)
end

function income_item_async(item)
  return not item.collect and not is_reward_sync(item.reward)
end

function income_all_optional(income)
  if #income == 0 then return false end
  for _, item in ipairs(income) do
    if item.collect or not is_reward_optional(item.reward) then return false end
  end
  return true
end

function income_item_apply(player, item)
  if item.collect then
    update_money(player, get_counter_value(player.income_counter), "income")
    return
  end
  apply_reward_string(player, item.reward, item.source)
end

function income_panel_xml(player, income)
  local color = player.color
  local buttons, rows = "", 0
  for i, item in ipairs(income) do
    local text = income_item_text(player, item)
    local button_height = text:find("\n") and 52 or 34
    rows = rows + button_height
    buttons = buttons .. string.format([[
      <Button id="incomeButton_%s_%d" onClick="on_income_button_clicked(%s)" fontSize="16" width="240" height="%d" minHeight="%d" color="#4A90D9" textColor="#FFFFFF">%s</Button>
    ]], color, i, color .. "_" .. i, button_height, button_height, text)
  end

  local extra = 0
  if income_all_optional(income) then
    buttons = buttons .. [[<Text fontSize="18" color="#FFFFFF"></Text>]]
    buttons = buttons .. string.format([[
      <Button id="incomePassButton_%s" onClick="on_income_pass_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#C61715" textColor="#FFFFFF">Pass</Button>
    ]], color, color)
    extra = 30 + 34 + 6
  end

  local height = 16 + 30 + rows + (#income - 1) * 6 + extra
  return string.format([[
    <Panel id="incomePanel_%s" visibility="%s" rectAlignment="MiddleRight" width="280" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        <Text fontSize="18" color="#FFFFFF">Collect your income:</Text>
        %s
      </VerticalLayout>
    </Panel>
  ]], color, color, height, buttons)
end

function render_income_table(player)
  local color = player.color
  income_players[color] = nil
  clear_player_panel(color)

  if #player.income_pending == 0 then
    player.income_pending = nil
    advance_income_phase()
    return
  end

  income_players[color] = player
  set_player_panel(color, income_panel_xml(player, player.income_pending))
end

function on_income_button_clicked(_, value, _)
  local color, idx_str = value:match("^(%a+)_(%d+)$")
  local player = income_players[color]
  if player == nil then return end

  local idx = tonumber(idx_str)
  local item = player.income_pending[idx]
  if item == nil then return end

  clear_player_panel(color)

  table.remove(player.income_pending, idx)
  local is_async = income_item_async(item)

  if is_async then
    player.on_claims_empty = function()
      player.on_claims_empty = nil
      render_income_table(player)
    end
  end

  income_item_apply(player, item)

  if not is_async then
    render_income_table(player)
  end
end

function on_income_pass_clicked(_, color, _)
  local player = income_players[color]
  if player == nil then return end
  if not income_all_optional(player.income_pending) then return end

  player.income_pending = {}
  render_income_table(player)
end

function end_turn_prompts_player(player)
  if player.offer_multiplier ~= nil then return true end
  if #player.post_action_rewards > 0 then return true end
  if player.venom_unpaid then return true end
  return false
end

function end_player_turn(player)
  if end_turn_prompts_player(player) then
    take_checkpoint("end_turn", player)
  end

  if player.offer_multiplier ~= nil then
    offer_multiplier_action(player)
    return
  end
  resume_end_player_turn(player)
end

function resume_end_player_turn(player)
  if player.hypnotize_action then
    finish_hypnotized_action(player, function()
      finish_end_player_turn(player)
    end)
    return
  end

  move_action_card_to_front(player)
  finish_end_player_turn(player)
end

function finish_end_player_turn(player)
  player.current_action = nil

  if offer_post_action_rewards(player) then return end

  if check_venom_fee(player) then return end

  finish_player_turn(player)
end


post_action_panels = {}

function offer_post_action_rewards(player)
  if #player.post_action_rewards == 0 then return false end
  set_player_panel(player.color, post_action_panel_xml(player.color, player))
  return true
end

function post_action_panel_xml(color, player)
  local buttons = ""
  for i, entry in ipairs(player.post_action_rewards) do
    buttons = buttons .. string.format([[
      <Button id="postActionButton_%s_%d" onClick="on_post_action_button_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">%s</Button>
    ]], color, i, color .. "_" .. i, reward_button_text(entry[1], player, entry[2]))
  end

  local count = #player.post_action_rewards
  local height = 16 + 30 + 30 + (count + 1) * 34 + count * 6
  return string.format([[
    <Panel id="postActionPanel_%s" visibility="%s" rectAlignment="MiddleRight" width="280" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        <Text fontSize="18" color="#FFFFFF">Before ending your turn:</Text>
        %s
        <Text fontSize="18" color="#FFFFFF"></Text>
        <Button id="postActionPassButton_%s" onClick="on_post_action_pass_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#C61715" textColor="#FFFFFF">Pass</Button>
      </VerticalLayout>
    </Panel>
  ]], color, color, height, buttons, color, color)
end

function resume_post_action_rewards(player)
  local state = post_action_panels[player.color]
  post_action_panels[player.color] = nil

  if state ~= nil and state.resume ~= nil then
    state.resume()
    return
  end

  if offer_post_action_rewards(player) then return end

  clear_player_panel(player.color)
  if check_venom_fee(player) then return end
  finish_player_turn(player)
end

function open_post_action_panel(player, reward, source, resume)
  post_action_panels[player.color] =
    { player = player, reward = reward, source = source, resume = resume }
end

function clever(player, count, source)
  assert(count == 1,
    "clever: " .. tostring(count) .. " offers arrived unsplit; see reward_offers")
  open_post_action_panel(player, "clever", source,
    function() render_claims_table(player) end)
  set_player_panel(player.color, clever_panel_xml(player.color, player))
end

function mark(player, source)
  open_post_action_panel(player, "mark", source,
    function() render_claims_table(player) end)
  start_mark(player, source)
end

function on_post_action_pass_clicked(_, color, _)
  local player = find_player_by_color(color)

  player.post_action_rewards = {}
  post_action_panels[color] = nil
  clear_player_panel(color)

  if check_venom_fee(player) then return end
  finish_player_turn(player)
end

function action_reward_refusal(player, action_name)
  if max_action_strength(player, action_card_slot_named(player, action_name)) < 1 then
    return "Your " .. string.upper(action_name) .. " action is not strong enough to take!"
  end
  if action_name == "build" and not build_action_available(player) then
    return "You don't have enough money to build!"
  end
  if action_name == "association" and not association_action_reachable(player) then
    return "You have no Association task you could take!"
  end
  return nil
end

function on_post_action_button_clicked(_, value, _)
  local color, index = value:match("^(%a+)_(%d+)$")
  local player = find_player_by_color(color)

  local idx = tonumber(index)
  if idx > #player.post_action_rewards then return end
  local entry = table.remove(player.post_action_rewards, idx)

  local reward, source = entry[1], entry[2]
  clear_player_panel(color)
  open_post_action_panel(player, reward, source)

  if reward == "determination" then
    printToAll(string.format("%s takes another action with %s Determination.",
      player.steam_name, source and (source .. "'s") or "their"))
    post_action_panels[color] = nil
    create_action_selection_panel(player)
    return
  end

  local action_name = reward:match("^action (%S+)$")
  if action_name then
    local refusal = action_reward_refusal(player, action_name)
    if refusal ~= nil then
      broadcastToColor(refusal, color, "Red")
      resume_post_action_rewards(player)
      return
    end
    post_action_panels[color] = nil
    create_action_selection_panel(player, action_name)
    return
  end

  if reward == "clever" or reward == "paid clever" then
    if reward == "paid clever" and get_counter_value(player.money_counter) < 2 then
      broadcastToColor("You don't have enough money!", color, "Red")
      resume_post_action_rewards(player)
      return
    end
    set_player_panel(color, clever_panel_xml(color, player))
    return
  end

  local boost_name = reward:match("^boost (%S+)$")
  if boost_name then
    set_player_panel(color, boost_panel_xml(color, player, boost_name))
    return
  end

  if reward == "mark" then
    start_mark(player, source)
    return
  end

  local hypnosis_slots = reward:match("^hypnosis (%d+)$")
  if hypnosis_slots then
    start_hypnotized_action(player, entry[3], tonumber(hypnosis_slots))
    return
  end

  resume_post_action_rewards(player)
end

function clever_panel_xml(color, player)
  local rows = ""
  for slot = 1, 5 do
    rows = rows .. string.format([[
      <HorizontalLayout spacing="6" minHeight="34" childAlignment="MiddleLeft" childForceExpandHeight="false">
        <Text fontSize="20" color="#FFFFFF" width="20" alignment="MiddleRight">%d:</Text>
        <Button id="cleverButton_%s_%d" onClick="on_clever_slot_clicked(%s)" fontSize="14" width="220" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">%s</Button>
      </HorizontalLayout>
    ]], slot, color, slot, color .. "_" .. slot,
        string.sub(action_card_object(player, slot).getName(), 1, -3))
  end

  local height = 16 + 50 + 24 + 5 * 34 + 24 + 34 + 8 * 6
  return string.format([[
    <Panel id="cleverPanel_%s" visibility="%s" rectAlignment="MiddleRight" width="280" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        <Text fontSize="18" color="#FFFFFF">Set an action card back to position 1:</Text>
        <Text fontSize="18" color="#FFFFFF"></Text>
        %s
        <Text fontSize="18" color="#FFFFFF"></Text>
        <Button id="cleverPassButton_%s" onClick="on_clever_pass_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#C61715" textColor="#FFFFFF">Pass</Button>
      </VerticalLayout>
    </Panel>
  ]], color, color, height, rows, color, color)
end

function on_clever_slot_clicked(_, value, _)
  local color, slot_str = value:match("^(%a+)_(%d+)$")
  local state = post_action_panels[color]
  if state == nil then return end

  local player, slot = state.player, tonumber(slot_str)
  if slot > 1 then
    if state.reward == "paid clever" then
      update_money(player, -2, "Clever")
    end
    printToAll(player.steam_name .. " sets back their " .. string.sub(action_card_object(player, slot).getName(), 1, -3) .. " action card using Clever" .. (state.source and (" from " .. state.source) or "") .. ".")
    move_action_card(player, slot, 1)
  end

  resume_post_action_rewards(player)
end

function on_clever_pass_clicked(_, color, _)
  local state = post_action_panels[color]
  if state == nil then return end
  resume_post_action_rewards(state.player)
end

function boost_panel_xml(color, player, action_name)
  local boosted = action_card_slot_named(player, action_name)

  local rows = ""
  for slot = 1, 5 do
    local live = (slot == 1 or slot == 5)
    local label = string.sub(action_card_object(player, slot).getName(), 1, -3)
    if slot == boosted then label = label .. " \u{25C4}" end
    rows = rows .. string.format([[
      <HorizontalLayout spacing="6" minHeight="34" childAlignment="MiddleLeft" childForceExpandHeight="false" childForceExpandWidth="false">
        <Button id="boostButton_%s_%d" interactable="%s" onClick="on_boost_position_clicked(%s)" fontSize="20" width="34" minWidth="34" height="34" minHeight="34" color="%s" textColor="#FFFFFF">%d:</Button>
        <Text fontSize="16" color="%s" width="200" minWidth="200" alignment="MiddleLeft">%s</Text>
      </HorizontalLayout>
    ]], color, slot, tostring(live), color .. "_" .. slot,
        live and "#4A90D9" or "#888888", slot,
        (slot == boosted) and "#E54848" or "#FFFFFF",
        label)
  end

  local height = 16 + 50 + 24 + 5 * 34 + 24 + 34 + 8 * 6
  return string.format([[
    <Panel id="boostPanel_%s" visibility="%s" rectAlignment="MiddleRight" width="280" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        <Text fontSize="18" color="#FFFFFF">Place your %s action card on position 1 or 5.</Text>
        <Text fontSize="18" color="#FFFFFF"></Text>
        %s
        <Text fontSize="18" color="#FFFFFF"></Text>
        <Button id="boostPassButton_%s" onClick="on_boost_pass_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#C61715" textColor="#FFFFFF">Pass</Button>
      </VerticalLayout>
    </Panel>
  ]], color, color, height, string.upper(action_name), rows, color, color)
end

function on_boost_position_clicked(_, value, _)
  local color, target_str = value:match("^(%a+)_(%d+)$")
  local state = post_action_panels[color]
  if state == nil then return end

  local player = state.player
  local action_name = state.reward:match("^boost (%S+)$")
  local slot = action_card_slot_named(player, action_name)
  local target = tonumber(target_str)
  assert(target == 1 or target == 5,
    "on_boost_position_clicked: position " .. tostring(target) .. " was never offered")

  printToAll(string.format("%s moves their %s action card to position %d, using %s boost.",
    player.steam_name, string.upper(action_name), target,
    state.source and (state.source .. "'s") or "their"))
  move_action_card(player, slot, target)

  resume_post_action_rewards(player)
end

function on_boost_pass_clicked(_, color, _)
  local state = post_action_panels[color]
  if state == nil then return end
  resume_post_action_rewards(state.player)
end

function player_index(player)
  for i, p in ipairs(players) do
    if p.color == player.color then return i end
  end
end

function next_player(player)
  return players[(player_index(player) % #players) + 1]
end

function previous_player(player)
  local i = player_index(player)
  return players[i == 1 and #players or i - 1]
end

function right_neighbour(player)
  if left_to_right_order then return next_player(player) end
  return previous_player(player)
end

game_end_triggered = false
final_turn_player = nil

function trigger_game_end(last_player)
  game_end_triggered = true
  final_turn_player = last_player
  broadcastToAll("The end of the game has been triggered! " ..
    last_player.steam_name .. " will take the last turn.")
end

function any_player_at_game_end_score()
  if #players == 1 then return false end
  for _, p in ipairs(players) do
    if get_counter_value(p.score_counter) >= cnsts.game_end_score then return true end
  end
  return false
end

function finish_player_turn(player)
  player.camouflage = nil

  if not game_end_triggered and #players > 1
     and get_counter_value(player.score_counter) >= cnsts.game_end_score then
    trigger_game_end(previous_player(player))
  end

  refill_display(function()
    if solo_turn_track_active() and advance_solo_turn_cube() == "game_end" then
      start_final_scoring()
      return
    end

    check_break_trigger({ handler = "after_turn", color = player.color })
  end)
end

function advance_solo_turn_cube()
  solo_cubes_advanced = solo_cubes_advanced + 1
  local cube = getObjectFromGUID(solo_turn_cubes[solo_cubes_advanced])
  local at = cube.getPosition()
  cube.setPosition({ x = at.x + cnsts.solo.cube_advance, y = at.y, z = at.z })

  if solo_cubes_advanced < #solo_turn_cubes then return nil end
  if #solo_turn_cubes <= cnsts.solo.final_cubes then return "game_end" end
  return nil
end

function reset_solo_turn_track()
  local retiring = getObjectFromGUID(table.remove(solo_turn_cubes, 1))
  retiring.setPosition(solo_donation_position())

  solo_cubes_advanced = 0
  for _, guid in ipairs(solo_turn_cubes) do
    local cube = getObjectFromGUID(guid)
    local at = cube.getPosition()
    cube.setPosition({ x = at.x - cnsts.solo.cube_advance, y = at.y, z = at.z })
  end
end

function solo_donation_position()
  local _, key = donation_slot()
  if key ~= nil then return zones[key].getPosition() end
  return donation_12_position(donation_12_count() + 1)
end

function check_venom_fee(player)
  player.persistent_rewards.venom_fee = nil

  if not player.venom_unpaid then return false end

  show_venom_fee_panel(player)
  return true
end

function show_venom_fee_panel(player)
  local color = player.color
  set_player_panel(color, string.format([[
    <Panel id="venomFeePanel_%s" visibility="%s" rectAlignment="MiddleRight" width="280" height="50" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        <Button id="venomFeeButton_%s" onClick="on_venom_fee_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">Pay Venom Fee: 2 Money</Button>
      </VerticalLayout>
    </Panel>
  ]], color, color, color, color))
end

function on_venom_fee_clicked(_, color, _)
  local player = find_player_by_color(color)
  if player == nil or not player.venom_unpaid then return end
  if not pay_venom_fee(player) then return end

  clear_player_panel(color)
  finish_player_turn(player)
end



local FINAL_SCORE_TESTS, FINAL_SCORE_COUNTS
local SCORE_CONDITIONS, SCORE_COUNTS, SCORE_PAYOUTS, SCORE_ICON_NAMES
local SCORE_DEFERRED

function start_final_scoring()
  broadcastToAll("The last turn is over. Final scoring begins.")

  if final_scoring_discard_triggered then
    score_all_players()
    return
  end

  final_scoring_discard_triggered = true
  broadcastToAll(
    "No player reached 10 Conservation Points. All players discard 1 Final Scoring card.")

  local held = {}
  for _, p in ipairs(players) do
    held[p.color] = #Player[p.color].getHandObjects(2)
  end

  local remaining = #players
  for _, p in ipairs(players) do
    prompt_final_scoring_discard(p, 1, nil, function()
      remaining = remaining - 1
      if remaining == 0 then
        clear_waiting_status()
        wait_for_all_hand_counts(2, function(q) return held[q.color] - 1 end,
                                 score_all_players)
      else
        set_waiting_status(p, cnsts.waiting_to_discard)
      end
    end)
  end
end

function score_all_players()
  for _, player in ipairs(players) do
    printToAll("--- Final scoring for " .. player.steam_name .. " ---")
    score_final_scoring_cards(player)
    score_played_sponsors(player)
  end
  score_deferred_sponsor_keys()

  Wait.time(function()
    announce_winner()
    stop_rewind_checkpoints()
  end, cnsts.winner_panel_delay)
end

function game_winners()
  local best, winners = nil, {}
  for _, player in ipairs(players) do
    local score = get_counter_value(player.score_counter)
    local supported = projects_supported(player)
    if best == nil or score > best.score
       or (score == best.score and supported > best.supported) then
      best = { score = score, supported = supported }
      winners = { player }
    elseif score == best.score and supported == best.supported then
      winners[#winners + 1] = player
    end
  end
  return winners
end

function join_names(names)
  if #names <= 2 then return table.concat(names, " and ") end
  local head = {}
  for i = 1, #names - 1 do head[i] = names[i] end
  return table.concat(head, ", ") .. " and " .. names[#names]
end

function winner_text(winners)
  if #winners == 1 then
    return winners[1].steam_name .. " is the winner!"
  end
  local names = {}
  for _, player in ipairs(winners) do names[#names + 1] = player.steam_name end
  return "The game ends in a tie between " .. join_names(names) .. "!"
end

function turn_count_text()
  local parts = {}
  for _, player in ipairs(players) do
    parts[#parts + 1] = player.steam_name .. " " .. player.turns_taken
  end
  return "Turns taken: " .. table.concat(parts, ", ") .. "."
end

function solo_result_text(player)
  local score = get_counter_value(player.score_counter)
  if score >= cnsts.solo.pass_score then
    return string.format(
      "You have scored %d points and have passed the solo challenge!", score)
  end
  return string.format(
    "You have scored %d points, short of the %d needed to pass the solo challenge.",
    score, cnsts.solo.pass_score)
end

function announce_winner()
  local text, lines
  if #players == 1 then
    text, lines = solo_result_text(players[1]), 2
  else
    local winners = game_winners()
    text, lines = winner_text(winners), (#winners == 1) and 1 or 3
  end

  printToAll(turn_count_text())
  printToAll(text)
  for _, player in ipairs(players) do
    show_winner_panel(player.color, text, lines)
  end
end

function winner_key(color)
  return "winner_" .. color
end

function show_winner_panel(color, text, lines)
  set_active_panel(winner_key(color), string.format([[
    <Panel id="winnerPanel_%s" visibility="%s" rectAlignment="MiddleCenter" width="520" height="%d" color="#222222FF">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        <Text id="winnerText_%s" fontSize="18" color="#FFFFFF">%s</Text>
        <Text fontSize="18" color="#FFFFFF"></Text>
        <Button id="winnerOkButton_%s" onClick="on_winner_ok_clicked(%s)" fontSize="16" width="120" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">OK</Button>
      </VerticalLayout>
    </Panel>
  ]], color, color, 16 + lines * 30 + 30 + 34 + 18, color, text, color, color))
end

function on_winner_ok_clicked(_, color, _)
  clear_active_panel(winner_key(color))
end

function score_deferred_sponsor_keys()
  for _, player in ipairs(players) do
    for _, guid in ipairs(player.played_sponsors) do
      local obj = getObjectFromGUID(guid)
      for key, value in pairs(card_data_for(obj.getName()).score or {}) do
        if score_key_deferred(key, value) then
          pay_sponsor_score(player, key, value, string.sub(obj.getName(), 7))
        end
      end
    end
  end
end

function score_key_deferred(key, value)
  return type(key) == "number" and SCORE_DEFERRED[value] == true
end

function score_played_sponsors(player)
  for _, guid in ipairs(player.played_sponsors) do
    local obj = getObjectFromGUID(guid)
    for key, value in pairs(card_data_for(obj.getName()).score or {}) do
      if not score_key_deferred(key, value) then
        pay_sponsor_score(player, key, value, string.sub(obj.getName(), 7))
      end
    end
  end
end

function pay_sponsor_score(player, key, value, source)
  local reward = sponsor_score_reward(player, key, value)
  if reward == nil or reward == "" then return end

  local amount, unit = reward:match("^(%d+) (%S+)$")
  amount = tonumber(amount)
  if amount > 0 then award_final_score(player, amount, unit, source) end
end

function sponsor_score_reward(player, key, value)
  if type(key) == "number" then
    local payout = SCORE_PAYOUTS[value]
    if payout == nil then
      error("sponsor score: no rule named '" .. tostring(value) .. "'", 2)
    end
    return payout(player)
  end

  if type(value) == "table" then
    return reward_string_from_key(player, key, value)
  end

  return score_condition_met(player, key) and value or nil
end

function score_condition_met(player, key)
  local named = SCORE_CONDITIONS[key]
  if named ~= nil then return named(player) end

  local name, threshold = key:match("^(.+)_(%d+)$")
  if name == nil then
    error("sponsor score: no condition named '" .. tostring(key) .. "'", 2)
  end
  threshold = tonumber(threshold)
  return score_count(player, name, threshold) >= threshold
end

function score_count(player, name, want)
  local measure = SCORE_COUNTS[name]
  if measure ~= nil then return measure(player, want) end

  if name == "species" or name == "habitat" or SCORE_ICON_NAMES[name] then
    return project_match_count(player, name)
  end
  error("sponsor score: nothing counts '" .. tostring(name) .. "'", 2)
end


function final_scoring_cards(player)
  return Player[player.color].getHandObjects(2)
end

function final_scoring_data_for(number)
  return (marine_worlds_enabled and cnsts.final_scoring_cards.mw[number])
    or cnsts.final_scoring_cards.base[number]
end

function score_final_scoring_cards(player)
  for _, card in ipairs(final_scoring_cards(player)) do
    local name = card.getName()
    local rule = final_scoring_data_for(card_number_of(name))
    award_final_score(player, final_score_award(player, rule), "cp",
                      string.sub(name, 7))
  end
end

function award_final_score(player, amount, unit, source)
  local applied = 0
  if amount > 0 then
    if unit == "cp" then
      applied = apply_cp(player, amount)
    else
      applied = apply_appeal(player, amount)
    end
  end
  printToAll(string.format("%s gains %s from %s%s.", player.steam_name,
    reward_button_text(applied .. " " .. unit), source,
    applied < amount and " (capped)" or ""))
end

function final_score_award(player, rule)
  local cp
  if rule.tests ~= nil then
    cp = 0
    for _, test in ipairs(rule.tests) do
      if FINAL_SCORE_TESTS[test](player) then cp = cp + 1 end
    end
  elseif rule.compare ~= nil then
    cp = final_score_majorities(player, rule)
  else
    local count = final_score_count(player, rule.count)
    if rule.bands ~= nil then
      cp = 0
      for _, band in ipairs(rule.bands) do
        if count >= band[1] then cp = band[2] break end
      end
    elseif rule.divisor ~= nil then
      cp = math.floor(count / rule.divisor)
    elseif rule.per then
      cp = count
    else
      cp = count - rule.offset
    end
  end
  return math.max(0, math.min(4, cp))
end

function final_score_water_connected(player)
  return player.map:countUncoveredTerrain("water")
      == player.map:countUncoveredTerrainAdjacentToTile("water")
end

function final_score_rock_connected(player)
  return player.map:countUncoveredTerrain("rock")
      == player.map:countUncoveredTerrainAdjacentToTile("rock")
end

function final_score_border_covered(player)
  return player.map:countUnoccupiedBorder() == 0
end

function final_score_map_covered(player)
  return player.map:countUnoccupied() == 0
end

FINAL_SCORE_TESTS = {
  water_connected = final_score_water_connected,
  rock_connected  = final_score_rock_connected,
  border_covered  = final_score_border_covered,
  map_covered     = final_score_map_covered
}

FINAL_SCORE_COUNTS = {
  large_animals = function(p)
    return count_played_animals(p, function(card) return card.size >= 4 end)
  end,
  small_animals = function(p)
    return count_played_animals(p, function(card) return card.size <= 2 end)
  end,
  research_icons = function(p)
    return get_icon_counter_value(p.icon_counters["research"])
  end,
  rock_icons = function(p)
    return get_icon_counter_value(p.icon_counters["rock"])
  end,
  water_icons = function(p)
    return get_icon_counter_value(p.icon_counters["water"])
  end,
  projects_supported = function(p) return projects_supported(p) end,
  unoccupied_cells = function(p) return p.map:countUnoccupied() end,
  reputation = function(p) return get_counter_value(p.rep_counter) end,
  played_sponsors = function(p) return #p.played_sponsors end,
  distinct_tile_shapes = function(p) return p.map:countDistinctTileShapes() end,
  kiosk_pavilion_pairs = function(p)
    return math.min(#p.map:tilesWithTag("kiosk"), #p.map:tilesWithTag("pavilion"))
  end,
  played_conditions = function(p) return played_condition_count(p) end,
  best_unsupported_habitat = function(p)
    return best_unsupported_icon(p, cnsts.icons.habitat)
  end,
  best_unsupported_species = function(p)
    return best_unsupported_icon(p, cnsts.icons.species)
  end
}

function final_score_count(player, key)
  local measure = FINAL_SCORE_COUNTS[key]
  if measure == nil then
    error("final_score_count: nothing counts '" .. tostring(key) .. "'", 2)
  end
  return measure(player)
end

function played_condition_count(player)
  local count = 0
  for _, list in ipairs({ player.played_animals, player.played_sponsors }) do
    for _, guid in ipairs(list) do
      local data = card_data_for(getObjectFromGUID(guid).getName())
      count = count + #(data.conditions or {})
    end
  end
  return count
end

function best_unsupported_icon(player, group)
  local supported = supported_base_project_icons(player)
  local best = 0
  for _, icon in ipairs(group) do
    if not supported[icon] then
      best = math.max(best, get_icon_counter_value(player.icon_counters[icon]))
    end
  end
  return best
end

function supported_base_project_icons(player)
  local supported = {}
  for _, entry in ipairs(base_projects) do
    local card = card_data_for(getObjectFromGUID(entry[1]).getName())
    for _, cube_guid in pairs(entry[2]) do
      local cube = getObjectFromGUID(cube_guid)
      if cube ~= nil and cube_owner_color(cube) == player.color then
        supported[card.match] = true
      end
    end
  end
  return supported
end

function final_score_majorities(player, rule)
  local group = cnsts.icons[rule.compare]
  local mine = final_score_icon_counts(player, group, rule.with_partner_zoos)
  local theirs = final_score_icon_counts(right_neighbour(player), group, false)

  local won = 0
  for _, icon in ipairs(group) do
    if mine[icon] > theirs[icon] then won = won + 1 end
  end
  return won
end

function final_score_icon_counts(player, group, with_partner_zoos)
  local counts = {}
  for _, icon in ipairs(group) do
    counts[icon] = get_icon_counter_value(player.icon_counters[icon])
  end
  if with_partner_zoos then
    for _, zoo in ipairs(player.acquired_partner_zoos) do
      if counts[zoo] ~= nil then counts[zoo] = counts[zoo] + 1 end
    end
  end
  return counts
end


SCORE_ICON_NAMES = {}
for _, icon in ipairs(cnsts.icons.all) do SCORE_ICON_NAMES[icon] = true end

local DONATION_AREAS = {}
for _, key in ipairs(cnsts.donation_zones) do
  DONATION_AREAS[#DONATION_AREAS + 1] = key
end
DONATION_AREAS[#DONATION_AREAS + 1] = "donation_12"

SCORE_DEFERRED = { ["mascot statue"] = true }

function donation_cube_count(player, want)
  local n = 0
  for _, key in ipairs(DONATION_AREAS) do
    for _, obj in pairs(zones[key].getObjects(true)) do
      if obj.hasTag("cube") and obj.hasTag(player.color) then
        n = n + 1
        if want ~= nil and n >= want then return n end
      end
    end
  end
  return n
end

function flipped_size_1_count(player)
  local n = 0
  for _, id in ipairs(player.map:tilesWithTag("size_1")) do
    if player.map:hasTag(id, "occupied") then n = n + 1 end
  end
  return n
end

function kiosks_with_open_space(player)
  local n = 0
  for _, id in ipairs(player.map:tilesWithTag("kiosk")) do
    if player.map:countUnoccupiedAdjacentToTile(id) >= 3 then n = n + 1 end
  end
  return n
end

function isolated_terrain_cells(player, tag)
  return player.map:countUncoveredTerrain(tag)
       - player.map:countUncoveredTerrainAdjacentToTile(tag)
end

function underwater_tunnel_appeal(player)
  local best = 0
  for _, id in ipairs(player.map:tilesWithTag("underwater_tunnel")) do
    local kinds = 0
    for _, kind in ipairs({ "small_aquarium", "large_aquarium" }) do
      for _, other in ipairs(player.map:touchingTiles(id)) do
        if player.map:hasTag(other, kind) then kinds = kinds + 1 break end
      end
    end
    if kinds > 0 then best = math.max(best, kinds == 2 and 5 or 3) end
  end
  return best .. " appeal"
end

SCORE_CONDITIONS = {
  border_covered  = final_score_border_covered,
  map_covered     = final_score_map_covered,
  rock_connected  = final_score_rock_connected,
  water_connected = final_score_water_connected,
  placement_covered = function(p) return p.map:countUnclaimedRewards() == 0 end
}

SCORE_COUNTS = {
  rep = function(p) return get_counter_value(p.rep_counter) end,
  size_1_flipped = function(p) return flipped_size_1_count(p) end,
  kiosks = function(p) return #p.map:tilesWithTag("kiosk") end,
  university = function(p) return #p.acquired_universities end,
  projects_supported = function(p) return projects_supported(p) end,
  donation = function(p, want) return donation_cube_count(p, want) end
}

SCORE_PAYOUTS = {
  ["conference on australia"] = function(p)
    return math.min(5, (pouch_counter_lines(p))) .. " appeal"
  end,
  ["farm cat"] = function(p)
    return math.min(3, kiosks_with_open_space(p)) .. " cp"
  end,
  ["native farm animals"] = function(p)
    return p.map:countGroupsOfSix() .. " cp"
  end,
  ["native lizards"] = function(p)
    return math.floor(isolated_terrain_cells(p, "rock") / 2) .. " cp"
  end,
  ["native seabirds"] = function(p)
    return math.floor(isolated_terrain_cells(p, "water") / 2) .. " cp"
  end,
  ["new world monkeys"] = function(p)
    local total, adjacent = p.map:countUnclaimedRewards()
    return math.floor((total - adjacent) / 2) .. " cp"
  end,
  ["underwater tunnel"] = underwater_tunnel_appeal,
  ["mascot statue"] = function(p)
    local mine = get_counter_value(p.appeal_counter)
    local ahead = 0
    for _, other in ipairs(players) do
      if other.color ~= p.color
         and get_counter_value(other.appeal_counter) > mine then
        ahead = ahead + 1
      end
    end
    return (2 * ahead) .. " appeal"
  end
}

claims_players = {}

function resolve_claim_text(claim)
  if type(claim.button_text) == "function" then
    return claim.button_text(table.unpack(claim.text_args or {}))
  end
  return claim.button_text
end

function pop_claim(sub_table, idx)
  table.remove(sub_table, idx)

  if sub_table.grouped then
    for i = #sub_table, 1, -1 do
      table.remove(sub_table, i)
    end
  end
end

function pop_first_invalid_claim(sub_table)
  for i, claim in ipairs(sub_table) do
    if claim.valid and not claim.valid() then
      pop_claim(sub_table, i)
      return true
    end
  end
  return false
end

function grouped_source(sub_table)
  if sub_table[1] == nil then return nil end
  local source = sub_table[1].source
  if source == nil then return nil end
  for _, claim in ipairs(sub_table) do
    if claim.source ~= source then return nil end
  end
  return source
end

function claims_panel_xml(color, sub_table, persistent_buttons, persistent_count)
  local buttons = ""
  local grouped_extra_height = 0

  local or_separators = sub_table.grouped and #sub_table <= 3

  if sub_table.grouped and #sub_table > 0 then
    local source = grouped_source(sub_table)
    local heading = "Choose one of the following:"
    if source ~= nil then
      heading = "Choose one of the following\nfor " .. source_label(source) .. ":"
    end
    buttons = buttons .. string.format(
      [[<Text fontSize="18" color="#FFFFFF">%s</Text>]], heading)
    grouped_extra_height = grouped_extra_height + (source ~= nil and 52 or 30)
  end

  if #sub_table > 0 and sub_table.note ~= nil then
    local note = sub_table.note
    buttons = buttons .. string.format([[
      <Text fontSize="16" color="#FFFFFF">%s</Text>
    ]], type(note) == "function" and note() or note)
    grouped_extra_height = grouped_extra_height + 26
  end

  local all_optional = true
  local wrapped_extra = 0
  for i, claim in ipairs(sub_table) do
    if or_separators and i > 1 then
      buttons = buttons .. [[<Text fontSize="16" color="#FFFFFF" alignment="MiddleCenter">or</Text>]]
      grouped_extra_height = grouped_extra_height + 30
    end
    local text = resolve_claim_text(claim)
    local button_height = text:find("\n") and 52 or 34
    wrapped_extra = wrapped_extra + button_height - 34
    buttons = buttons .. string.format([[
      <Button id="claimButton_%s_%d" onClick="on_claim_button_clicked(%s)" fontSize="16" width="240" height="%d" minHeight="%d" color="%s" textColor="#FFFFFF">%s</Button>
    ]], color, i, color .. "_" .. i, button_height, button_height,
        claim.color or "#4A90D9", text)
    if not claim.optional then
      all_optional = false
    end
  end
  local button_count = #sub_table

  local separator_height = grouped_extra_height
  if persistent_count > 0 and #sub_table > 0 then
    buttons = buttons .. [[
      <Panel color="#FFFFFF66" height="2" minHeight="2"></Panel>
      <Text fontSize="18" color="#FFFFFF">Optional choices:</Text>
    ]]
    separator_height = separator_height + 38
  end
  buttons = buttons .. persistent_buttons
  button_count = button_count + persistent_count

  if all_optional then
    buttons = buttons .. [[<Text fontSize="18" color="#FFFFFF"></Text>]]
    separator_height = separator_height + 30
    buttons = buttons .. string.format([[
      <Button id="claimPassButton_%s" onClick="on_claim_pass_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#C61715" textColor="#FFFFFF">%s</Button>
    ]], color, color, sub_table.cancel and "Cancel" or "Pass")
    button_count = button_count + 1
  end

  local height = 16 + separator_height + wrapped_extra + button_count * 34 + (button_count - 1) * 6
  return string.format([[
    <Panel id="claimsPanel_%s" visibility="%s" rectAlignment="MiddleRight" width="280" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        %s
      </VerticalLayout>
    </Panel>
  ]], color, color, height, buttons)
end

function render_claims_table(player)
  local color = player.color
  claims_players[color] = nil
  clear_player_panel(color)

  if #player.claims == 0 then
    local resume = player.on_claims_empty
    if resume ~= nil then
      resume()
      return
    end

    if offer_waza_small_animal_program(player) then
      render_claims_table(player)
      return
    end

    clear_build_action_state(player)
    clear_sponsor_action_state(player)
    clear_animal_action_state(player)
    clear_association_action_state(player)
    end_player_turn(player)
    return
  end

  local sub_table = player.claims[#player.claims]

  if sub_table.refresh ~= nil then
    local refresh = sub_table.refresh
    sub_table.refresh = nil
    refresh(sub_table)
    if #sub_table == 0 then
      table.remove(player.claims)
      render_claims_table(player)
      return
    end
  end

  while pop_first_invalid_claim(sub_table) do end

  local persistent_buttons, persistent_count = handle_persistent_rewards(player, "claims")

  if #sub_table == 0 and persistent_count == 0 then
    table.remove(player.claims)
    render_claims_table(player)
    return
  end

  if #sub_table == 1 and not sub_table[1].optional and persistent_count == 0
     and not sub_table.grouped then
    local claim = sub_table[1]
    pop_claim(sub_table, 1)
    persistent_origin = sub_table.from_persistent or false
    claim.function_call(resolve_claim_text(claim))
    if not claim.async then
      render_claims_table(player)
    end
    return
  end

  persistent_origin = false

  claims_players[color] = player
  set_player_panel(color, claims_panel_xml(color, sub_table, persistent_buttons, persistent_count),
                   function() render_claims_table(player) end)
end

active_claim = nil

persistent_origin = false

function retire_claim_record(record)
  if record == nil then return end
  for i, entry in ipairs(record.sub_table) do
    if entry == record.claim then
      pop_claim(record.sub_table, i)
      return
    end
  end
end

function retire_active_claim()
  if active_claim == nil then return end
  retire_claim_record(active_claim)
  active_claim = nil
end

function on_claim_button_clicked(_, value, _)
  local color, idx_str = value:match("^(%a+)_(%d+)$")
  local idx = tonumber(idx_str)
  local player = claims_players[color]
  local sub_table = player.claims[#player.claims]
  local claim = sub_table[idx]

  clear_player_panel(color)

  active_claim = { player = player, sub_table = sub_table, claim = claim }
  persistent_origin = sub_table.from_persistent or false

  if not claim.optional then
    pop_claim(sub_table, idx)
    active_claim = nil
  end

  local result = claim.function_call(resolve_claim_text(claim))
  if active_claim ~= nil and result == true then
    pop_claim(sub_table, idx)
    active_claim = nil
  end

  if not claim.async then
    render_claims_table(player)
  end
end

function on_claim_pass_clicked(_, color, _)
  local player = claims_players[color]
  table.remove(player.claims)

  while #player.claims > 0 do
    local sub_table = player.claims[#player.claims]
    while pop_first_invalid_claim(sub_table) do end
    if #sub_table > 0 then break end
    table.remove(player.claims)
  end

  render_claims_table(player)
end

function action_card_slot_position(board_pos, slot)
  local pos = board_relative_world_position(board_pos, "action_card_slot_1")
  for _ = 2, slot do
    pos = pos + cnsts.board_relative_positions.action_card_step
  end
  return pos
end

function move_action_card(player, slot, target)
  assert(slot ~= nil and target ~= nil, "move_action_card: nil slot or target")
  if slot == target then return end

  local records = player.action_cards
  local was = {}
  for i, record in ipairs(records) do was[record] = i end

  table.insert(records, target, table.remove(records, slot))

  for i, record in ipairs(records) do
    if was[record] ~= i then seat_action_card(player, i) end
  end
end

function seat_action_card(player, slot, place)
  place = place or move_when_settled
  local home = action_card_slot_position(player.player_board.getPosition(), slot)
  place(player.action_cards[slot].guid, home)
  seat_action_card_tokens(player, slot, home, place)
end

function action_card_slot_named(player, name)
  local want = string.upper(name)
  for slot = 1, 5 do
    local card = action_card_object(player, slot)
    if card ~= nil and string.sub(card.getName(), 1, -3) == want then return slot end
  end
  return nil
end

function move_action_card_to_front(player)
  local slot = player.current_action
  remove_action_card_token(player, slot, "constriction")

  move_action_card(player, slot, 1)
  seat_action_card(player, 1)
end

function set_current_action(player, slot)
  player.current_action = slot
  local card = action_card_object(player, slot)
  local pos = card.getPosition()
  local lifted = { x = pos.x, y = pos.y + 1, z = pos.z + 0.5 }
  card.setPositionSmooth(lifted)
  seat_action_card_tokens(player, slot, lifted)
end

function use_action_card(player, slot, x_tokens_used, card_owner)
  card_owner = card_owner or player
  set_current_action(card_owner, slot)

  local strength = action_strength(player, slot, x_tokens_used, card_owner)

  local poisoned = remove_action_card_token(card_owner, slot, "venom")
  if poisoned and card_owner == player then
    settle_venom_fee(player)
  end

  if player.t1_effect ~= nil then
    player.t1_effect = "claimed"
  end

  return strength
end

function x_token_action(player, slot, card_owner)
  card_owner = card_owner or player
  local action_name = string.sub(action_card_object(card_owner, slot).getName(), 1, -3)
  local whose = card_owner == player and "their "
    or (card_owner.steam_name .. "'s ")
  use_action_card(player, slot, 0, card_owner)

  create_claims_from_rewards(player, { "1 x_token" },
    "setting back " .. whose .. action_name .. " action")
end

function on_action_card_button_clicked(_, value, _)
  local color, slot = value:match("^(%a+)_(%d+)$")
  slot = tonumber(slot)
  local state = action_selection_state[color]
  if state == nil then return end

  local player = state.player
  local hypnosis = state.hypnosis
  local owner = hypnosis ~= nil and hypnosis.target or player
  local card = action_card_object(owner, slot)

  rearm_effect(player, "landscape_gardener")

  if state.multiplier ~= nil then
    remove_multiplier_token(player, slot)
  end

  if state.x_token_active then
    action_selection_state[color] = nil
    clear_player_panel(color)
    if hypnosis == nil then
      arm_multiplier_offer(player, slot, true)
    else
      player.hypnotize_action = owner.color
    end

    x_token_action(player, slot, owner)
    return
  end

  if state.x_tokens_used > 0 then
    update_x_token(player, -state.x_tokens_used,
      "their " .. string.sub(card.getName(), 1, -3) .. " action")
  end

  if hypnosis ~= nil then
    adopt_flipped_for(player, owner, slot)
    player.hypnotize_action = owner.color
  end

  local strength = use_action_card(player, slot, state.x_tokens_used, owner)

  if hypnosis == nil then
    arm_multiplier_offer(player, slot, false)
  end

  if hypnosis ~= nil then
    printToAll(string.format("%s hypnotizes %s.",
      player.steam_name, owner.steam_name))
  end

  local prefix = string.sub(card.getName(), 1, 2)

  action_selection_state[color] = nil
  clear_player_panel(color)

  if prefix == "CA" then
    cards_action(player, strength, string.sub(card.getName(), -1))
  elseif prefix == "BU" then
    build_action(player, strength, string.sub(card.getName(), -1))
  elseif prefix == "AN" then
    start_animals_action(player, strength, string.sub(card.getName(), -1))
  elseif prefix == "SP" then
    start_sponsors_action(player, strength, string.sub(card.getName(), -1))
  elseif prefix == "AS" then
    start_association_action(player, strength, string.sub(card.getName(), -1))
  end
end


sponsor_actions = {}

function sponsor_level(card, player)
  return math.max(0, (card.level or 0) - sponsor_level_discount(player))
end

function sponsor_level_discount(player)
  local discount = 0
  if player.map_hollywood_hills == 3 then discount = discount + 1 end
  if player.sponsor_3_level_discount then discount = discount + 2 end
  return discount
end

function sponsor_3_discard_pool(player)
  if sponsors_upgraded(player) then return player_hand_cards(player) end

  local pool = {}
  for _, obj in ipairs(player_hand_cards(player)) do
    if card_data_for(obj.getName()).type == "sponsor" then
      pool[#pool + 1] = obj
    end
  end
  return pool
end

function sponsor_hand_cards(player)
  local cards = {}
  for _, obj in ipairs(player_hand_cards(player)) do
    if card_data_for(obj.getName()).type == "sponsor" then
      cards[#cards + 1] = obj
    end
  end
  return cards
end

function start_sponsor_4_swap(player, host)
  local _, callback = persistent_rewards_host(player, host)

  create_card_selection_panel(player, function() return sponsor_hand_cards(player) end,
    1, "optional discard",
    function(discarded)
      if not discarded then
        callback()
        return
      end

      player.persistent_rewards.sponsor_4_snap = nil
      start_snap(player, 1, false, "sponsor", offer_sponsor_choices)
    end, nil, nil, true)
end

function sponsor_play_cost(display_pos)
  return display_pos or 0
end

function clear_sponsor_action_state(player)
  player.persistent_rewards.sponsor_1_trade = nil
  player.persistent_rewards.sponsor_3_discard = nil
  player.persistent_rewards.sponsor_4_snap = nil
  player.sponsor_2_active = nil
  player.sponsor_3_level_discount = nil
  sponsor_actions[player.color] = nil
end

function trade_offer_upgraded(player, offer)
  return offer == "sponsor1" and sponsors_upgraded(player)
end

function trade_rows(player, offer)
  local money = get_counter_value(player.money_counter)
  local tokens = #player.x_tokens

  local rows = {
    { key = "token_to_money", text = "1 X-token \u{2192} 5 Money",
      enabled = tokens >= 1 },
    { key = "money_to_token", text = "5 Money \u{2192} 1 X-token",
      enabled = money >= 5 and tokens < 5 },
  }

  if trade_offer_upgraded(player, offer) then
    rows[#rows + 1] = { key = "token_to_rep", text = "1 X-token \u{2192} 1 Reputation",
                        enabled = tokens >= 1 }
    rows[#rows + 1] = { key = "money_to_rep", text = "5 Money \u{2192} 1 Reputation",
                        enabled = money >= 5 }
  end

  return rows
end

function trade(player, _)
  show_trade_panel(player, "claims", "reef")
end

function show_trade_panel(player, host, offer)
  local color = player.color
  local upgraded = trade_offer_upgraded(player, offer)

  local prompt = upgraded
    and "You may trade 1 X-token for 5 Money or vice versa, or pay either for 1 Reputation."
    or "You may trade 1 X-token for 5 Money or vice versa."

  local parts = { string.format([[<Text fontSize="18" color="#FFFFFF">%s</Text>]], prompt) }
  local height = 16 + (upgraded and 90 or 70)

  parts[#parts + 1] = [[<Text fontSize="18" color="#FFFFFF"></Text>]]
  height = height + 26

  for _, row in ipairs(trade_rows(player, offer)) do
    parts[#parts + 1] = string.format([[
      <Button id="tradeButton_%s_%s" interactable="%s" onClick="on_trade_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">%s</Button>
    ]], color, row.key, tostring(row.enabled),
        color .. "|" .. row.key .. "|" .. host .. "|" .. offer, row.text)
    height = height + 40
  end

  parts[#parts + 1] = [[<Text fontSize="18" color="#FFFFFF"></Text>]]
  parts[#parts + 1] = string.format([[
    <Button id="tradeCancelButton_%s" onClick="on_trade_cancel_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#C61715" textColor="#FFFFFF">Cancel</Button>
  ]], color, color .. "|" .. host)
  height = height + 26 + 40

  set_player_panel(color, string.format([[
    <Panel id="tradePanel_%s" visibility="%s" rectAlignment="MiddleRight" width="280" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="UpperCenter" childForceExpandHeight="false">
        %s
      </VerticalLayout>
    </Panel>
  ]], color, color, height, table.concat(parts, "\n")))
end

function on_trade_cancel_clicked(_, value, _)
  local color, host = value:match("^(%a+)|(%a+)$")
  local player = find_player_by_color(color)

  local panel_key, callback = persistent_rewards_host(player, host)
  clear_player_panel(panel_key)
  callback()
end

function on_trade_clicked(_, value, _)
  local color, key, host, offer = value:match("^(%a+)|([%w_]+)|(%a+)|(%w+)$")
  local player = find_player_by_color(color)
  if offer == "sponsor1" and not player.persistent_rewards.sponsor_1_trade then
    return
  end

  local allowed = false
  for _, row in ipairs(trade_rows(player, offer)) do
    if row.key == key then allowed = row.enabled break end
  end
  if not allowed then return end

  local source
  if offer == "sponsor1" then
    player.persistent_rewards.sponsor_1_trade = nil
    source = "Sponsor 1 Trade"
  else
    source = active_claim.claim.source
    retire_active_claim()
  end

  local panel_key, callback = persistent_rewards_host(player, host)
  clear_player_panel(panel_key)

  if key == "token_to_money" then
    update_x_token(player, -1, source)
    update_money(player, 5, source)
  elseif key == "money_to_token" then
    update_money(player, -5, source)
    update_x_token(player, 1, source)
  elseif key == "token_to_rep" or key == "money_to_rep" then
    resume_action_panel_after_claims(player, host)
    if key == "token_to_rep" then
      update_x_token(player, -1, source)
    else
      update_money(player, -5, source)
    end
    update_rep(player, 1, source)
    return
  end

  callback()
end

function sponsor_search_name(card_name)
  return string.upper(string.sub(card_name, 7))
end

function sponsor_building_opts(player, card)
  local opts = { allowed = buildable_terrain(player) }
  opts.allowed.cover = 0

  local building = card.building or {}
  opts.min_border_cells = building.min_border_cells
  opts.ignore_touch_rule = building.ignore_touch_rule
  opts.double_placement_bonus = building.double_placement_bonus

  if building.water_cells_only then
    opts.water_cells_only = true
    opts.allowed.water = true
  end

  local needed = {}
  for _, icon in ipairs(card.icons or {}) do
    if icon == "rock" or icon == "water" then
      needed[icon] = (needed[icon] or 0) + 1
    end
  end
  for tag, min in pairs(needed) do
    opts.terrain_requirements = opts.terrain_requirements or {}
    table.insert(opts.terrain_requirements, { tag = tag, min = min })
  end

  return opts
end

function sponsor_card_blocked_reason(card_name, player)
  local card = card_data_for(card_name)

  local unmet = first_unmet_condition(card, player)
  if unmet ~= nil then
    return "Unmet condition: " .. unmet
  end

  if card.building ~= nil then
    local shape = cnsts.build_tile_shapes[sponsor_search_name(card_name)]
    if shape == nil
       or not player.map:hasValidPlacement(shape, sponsor_building_opts(player, card)) then
      return "Cannot place building"
    end
  end

  return nil
end

marketing_plays = {}

function sponsor_play_mode(mode)
  return cnsts.sponsor_play_modes[mode or "marketing"]
end

function marketing_play_cost(card, player, mode)
  if sponsor_play_mode(mode).free then return 0 end
  return sponsor_level(card, player)
end

function marketing_unplayable_reason(card_name, player, mode)
  local card = card_data_for(card_name)

  if sponsor_play_mode(mode).person_only
     and not card_matches_search_key(card, "person_sponsor") then
    return "Not a Person Sponsor"
  end

  local cost = marketing_play_cost(card, player, mode)
  if cost > get_counter_value(player.money_counter) then
    return "Insufficient money: need " .. cost
  end
  return sponsor_card_blocked_reason(card_name, player)
end

function playable_marketing_candidates(player, mode)
  local candidates = {}
  for _, obj in ipairs(player_hand_cards(player)) do
    local name = obj.getName()
    if card_data_for(name).type == "sponsor"
       and marketing_unplayable_reason(name, player, mode) == nil then
      candidates[#candidates + 1] = obj
    end
  end
  return candidates
end

function marketing_candidates_after_discard(player, discarded)
  local going = {}
  for _, obj in ipairs(discarded) do going[obj.getGUID()] = true end

  local left = 0
  for _, obj in ipairs(playable_marketing_candidates(player)) do
    if not going[obj.getGUID()] then left = left + 1 end
  end
  return left
end

function marketing_panel_xml(color, state)
  local height = 16 + 50 + 12 + 30
  local body = string.format([[<Text fontSize="18" color="#FFFFFF">%s
</Text>
    <Text fontSize="18" color="#FFFFFF"></Text>]], sponsor_play_mode(state.mode).prompt)

  if state.selected ~= nil then
    body = body .. string.format([[
      <Text fontSize="18" color="#FFFFFF">%s</Text>
      <Button id="marketingConfirmButton_%s" onClick="on_marketing_confirm_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">Confirm</Button>
    ]], "You have selected:\n" .. string.sub(state.selected.getName(), 7), color, color)
    height = height + 70 + 40
  end

  if state.cancellable then
    body = body .. string.format([[
      <Button id="marketingCancelButton_%s" onClick="on_marketing_cancel_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#C61715" textColor="#FFFFFF">Cancel</Button>
    ]], color, color)
    height = height + 40
  end

  return string.format([[
    <Panel id="marketingPanel_%s" visibility="%s" rectAlignment="MiddleRight" width="280" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="UpperCenter" childForceExpandHeight="false">
        %s
      </VerticalLayout>
    </Panel>
  ]], color, color, height, body)
end

function add_sponsor_hand_offers(state, player, value)
  for _, obj in ipairs(player_hand_cards(player)) do
    if card_data_for(obj.getName()).type == "sponsor" then
      state.offers[obj.getGUID()] = value
    end
  end
end

function render_marketing_panel(player)
  set_player_panel(player.color, marketing_panel_xml(player.color, marketing_plays[player.color]),
    function()
      local state = marketing_plays[player.color]
      if state == nil then return end
      add_sponsor_hand_offers(state, player, true)
      render_marketing_panel(player)
    end)
end

function open_marketing_panel(player, source, opts)
  opts = opts or {}
  local state = { player = player, source = source,
                  host = opts.host or "claims",
                  cancellable = opts.cancellable ~= false,
                  token = opts.token or false,
                  mode = opts.mode,
                  offers = {}, selected = nil }
  marketing_plays[player.color] = state

  add_sponsor_hand_offers(state, player, true)
  render_marketing_panel(player)
end

function start_marketing(player, source, opts)
  opts = opts or {}
  if #playable_marketing_candidates(player, opts.mode) == 0 then
    broadcastToColor("You have no playable sponsor cards in hand!", player.color, "Red")
    local _, callback = persistent_rewards_host(player, opts.host or "claims")
    callback()
    return
  end
  open_marketing_panel(player, source, opts)
end

function on_marketing_cancel_clicked(_, color, _)
  local state = marketing_plays[color]
  if state == nil or not state.cancellable then return end

  local player, host = state.player, state.host
  marketing_plays[color] = nil
  clear_player_panel(color)

  local _, callback = persistent_rewards_host(player, host)
  callback()
end

function start_marketing_token(player, host)
  start_marketing(player, "their Marketing token", { host = host, token = true })
end

function handle_marketing_pickup(color, obj)
  local state = marketing_plays[color]
  state.selected = obj
  render_marketing_panel(state.player)
end

function spend_okapi_stable(player, source)
  if source ~= cnsts.okapi_stable_name then return end
  getObjectFromGUID(table.remove(player.okapi_stable)).destruct()
end

function on_marketing_confirm_clicked(_, color, _)
  local state = marketing_plays[color]
  if state == nil or state.selected == nil then return end

  local player, obj = state.player, state.selected
  local reason = marketing_unplayable_reason(obj.getName(), player, state.mode)
  if reason ~= nil then
    broadcastToColor("You cannot play that Sponsor! (" .. reason .. ")", color, "Red")
    return
  end

  marketing_plays[color] = nil
  clear_player_panel(color)

  if state.token then
    player.persistent_rewards.marketing_token = nil
    spend_bonus_token(player, "TOKEN: marketing")
  else
    retire_active_claim()
    spend_okapi_stable(player, state.source)
  end

  resume_action_panel_after_claims(player, state.host)

  finish_sponsor_play(player, obj, nil, state.mode or "marketing")
end

function marketing(player, source)
  start_marketing(player, source)
end

function play_person_sponsor(player, source)
  start_marketing(player, source, { mode = "person" })
end

function sponsor_unplayable_reason(card_name, player, budget, display_pos)
  local card = card_data_for(card_name)

  if sponsor_level(card, player) > budget then
    return "Insufficient strength"
  end

  local cost = sponsor_play_cost(display_pos)
  if cost > get_counter_value(player.money_counter) then
    return "Insufficient money: need " .. cost
  end

  return sponsor_card_blocked_reason(card_name, player)
end

function playable_sponsor_candidates(player, budget)
  local candidates = {}

  for _, obj in ipairs(player_hand_cards(player)) do
    local name = obj.getName()
    if card_data_for(name).type == "sponsor"
       and sponsor_unplayable_reason(name, player, budget, nil) == nil then
      candidates[#candidates + 1] = { obj = obj }
    end
  end

  if sponsors_upgraded(player) then
    local rep = get_counter_value(player.rep_counter)
    for i, threshold in ipairs(cnsts.rep_range_thresholds) do
      if rep >= threshold and display_cards[i] ~= nil then
        local name = display_cards[i].getName()
        if card_data_for(name).type == "sponsor"
           and sponsor_unplayable_reason(name, player, budget, i) == nil then
          candidates[#candidates + 1] = { obj = display_cards[i], display_pos = i }
        end
      end
    end
  end

  return candidates
end

function sponsor_panel_xml(color, state)
  local height = 16 + 50 + 12 + 30
  local body = [[<Text fontSize="18" color="#FFFFFF">Select a Sponsor card to play.
</Text>
    <Text fontSize="18" color="#FFFFFF"></Text>]]

  if sponsors_upgraded(state.player) then
    local discount = sponsor_level_discount(state.player)
    local line = "Remaining strength: " .. state.remaining
    if discount > 0 then line = line .. "\n(-" .. discount .. " card level)" end

    body = body .. string.format([[
      <Text fontSize="16" color="#FFFFFF">%s</Text>
    ]], line)
    height = height + (discount > 0 and 48 or 26)
  end

  if state.selected ~= nil then
    body = body .. string.format([[
      <Text fontSize="18" color="#FFFFFF">%s</Text>
      <Button id="sponsorConfirmButton_%s" onClick="on_sponsor_confirm_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">Confirm</Button>
    ]], "You have selected:\n" .. string.sub(state.selected.getName(), 7), color, color)
    height = height + 70 + 40
  end

  if sponsors_upgraded(state.player)
     and state.player.persistent_rewards.sponsor_3_discard then
    body = body .. string.format([[
      <Text fontSize="18" color="#FFFFFF"></Text>
      <Button id="sponsorLevelDiscountButton_%s" onClick="on_sponsor_level_discount_clicked(%s)" fontSize="16" width="240" height="52" minHeight="52" color="#4A90D9" textColor="#FFFFFF">%s</Button>
    ]], color, color, "Discard 1 card:\n-2 played card level")
    height = height + 30 + 58
  end

  if state.additional then
    body = body .. string.format([[
      <Text fontSize="18" color="#FFFFFF"></Text>
      <Button id="sponsorPassButton_%s" onClick="on_sponsor_pass_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#C61715" textColor="#FFFFFF">Pass</Button>
    ]], color, color)
    height = height + 30 + 40
  end

  return string.format([[
    <Panel id="sponsorPanel_%s" visibility="%s" rectAlignment="MiddleRight" width="280" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="UpperCenter" childForceExpandHeight="false">
        %s
      </VerticalLayout>
    </Panel>
  ]], color, color, height, body)
end

function render_sponsor_panel(player)
  set_player_panel(player.color, sponsor_panel_xml(player.color, sponsor_actions[player.color]),
    function()
      local state = sponsor_actions[player.color]
      if state == nil then return end
      add_sponsor_hand_offers(state, player, false)
      render_sponsor_panel(player)
    end)
end

function open_sponsor_panel(player, additional)
  local state = sponsor_actions[player.color]
  if state == nil then return end

  state.additional = additional
  state.selected = nil
  state.offers = {}

  add_sponsor_hand_offers(state, player, false)

  if sponsors_upgraded(player) then
    local rep = get_counter_value(player.rep_counter)
    for i, threshold in ipairs(cnsts.rep_range_thresholds) do
      if rep >= threshold and display_cards[i] ~= nil
         and card_data_for(display_cards[i].getName()).type == "sponsor" then
        display_cards[i].locked = false
        state.offers[display_cards[i].getGUID()] = i
      end
    end
  end

  render_sponsor_panel(player)
end

function handle_sponsor_pickup(color, obj)
  local state = sponsor_actions[color]
  state.selected = obj

  render_sponsor_panel(state.player)
end

function on_sponsor_level_discount_clicked(_, color, _)
  local state = sponsor_actions[color]
  if state == nil or not state.player.persistent_rewards.sponsor_3_discard then return end

  local player = state.player
  clear_player_panel(color)

  create_card_selection_panel(player, function() return player_hand_cards(player) end,
    1, "optional discard",
    function(discarded)
      if discarded then
        player.persistent_rewards.sponsor_3_discard = nil
        player.sponsor_3_level_discount = true
      end
      open_sponsor_panel(player, state.additional)
    end)
end

function on_sponsor_pass_clicked(_, color, _)
  local state = sponsor_actions[color]
  if state == nil or not state.additional then return end

  lock_display_cards()
  state.selected = nil
  state.offers = {}
  clear_player_panel(color)
  render_claims_table(state.player)
end

function on_sponsor_confirm_clicked(_, color, _)
  local state = sponsor_actions[color]
  if state == nil or state.selected == nil then return end

  local player, obj = state.player, state.selected
  local display_pos = state.offers[obj.getGUID()] or nil

  local reason = sponsor_unplayable_reason(obj.getName(), player, state.remaining, display_pos)
  if reason ~= nil then
    broadcastToColor("You cannot play that Sponsor! (" .. reason .. ")", color, "Red")
    return
  end

  lock_display_cards()
  state.selected = nil
  state.offers = {}
  clear_player_panel(color)

  finish_sponsor_play(player, obj, display_pos)
end

function played_sponsor_position(board_pos, index)
  local pos = board_relative_world_position(board_pos, "played_cards_col_1")
  for _ = 1, 3 do
    pos = pos + cnsts.board_relative_positions.played_cards_col_offset
  end
  for _ = 1, math.floor((index - 1) / 2) do
    pos = pos + cnsts.board_relative_positions.played_cards_row_offset
  end
  for _ = 1, (index - 1) % 2 do
    pos = pos + cnsts.board_relative_positions.played_cards_col_offset
  end
  return pos
end

function start_sponsor_building_placement(player, card, label, kind)
  start_tile_placement(player, {
    kinds = { kind },
    opts_for = function() return sponsor_building_opts(player, card) end,
    bag = bags.sponsor_buildings,
    clone = false,
    force_face_up = true,
    prompt = "Place " .. label .. " on your zoo map.",
    prompt_height = 75,
    full_message = "No space on your map!",
    allow_pass = false,
    on_confirm = function(p, tag, id, reward)
      credit_building_added(p, tag, id)
      claim_placement_rewards(p, reward, label .. "'s placement", tag, id)
    end,
  })
end

function offer_another_sponsor(player)
  local state = sponsor_actions[player.color]
  if state == nil then return end

  table.insert(player.claims, {
    {
      button_text = "Play an additional Sponsor card",
      optional = true,
      async = true,
      valid = function()
        return #playable_sponsor_candidates(player, state.remaining) > 0
      end,
      function_call = function()
        retire_claim_record(active_claim)
        active_claim = nil
        open_sponsor_panel(player, true)
      end
    }
  })
end

function finish_sponsor_play(player, obj, display_pos, mode)
  local full_name = obj.getName()
  local name = string.sub(full_name, 7)
  local card = card_data_for(full_name)
  local state = (mode == nil) and sponsor_actions[player.color] or nil

  if mode ~= nil and not sponsor_play_mode(mode).free then
    update_money(player, -marketing_play_cost(card, player, mode),
                 "playing " .. name .. " with Marketing")
  elseif display_pos ~= nil then
    update_money(player, -sponsor_play_cost(display_pos),
                 "playing " .. name .. " from the display")
  else
    printToAll(player.steam_name .. " plays " .. name .. ".")
  end

  if state ~= nil then
    state.remaining = state.remaining - sponsor_level(card, player)
  end

  player.sponsor_3_level_discount = nil

  if display_pos ~= nil then
    resolve_display_mark(display_pos, false)
    display_cards[display_pos] = nil
  end

  table.insert(player.played_sponsors, obj.getGUID())
  obj.setPosition(played_sponsor_position(player.player_board.getPosition(),
                                          #player.played_sponsors))
  obj.setRotation({ 0, 180, 0 })
  obj.locked = true

  refresh_pouch_counter(player)

  if card.effect ~= nil then process_effects(player, card.effect, nil, obj) end
  add_remove_hooks(player, name, card.hook_self, card.hook_all)
  add_income(player, card.income, name)

  if sponsors_upgraded(player) and mode == nil then
    offer_another_sponsor(player)
  end

  local groups = { { rewards = card.rewards or {}, source = name } }
  append_icon_groups(groups, player, card.icons)

  local extra = {}
  if card.building ~= nil then
    extra[1] = {
      button_text = "Place building",
      source = name,
      optional = false,
      async = true,
      function_call = function()
        start_sponsor_building_placement(player, card, name, sponsor_search_name(full_name))
      end
    }
  end

  wait_for_cards_out_of_hand(player, 1, { obj }, function()
    create_claims_from_reward_groups(player, groups, false, extra)
  end)
end

function start_sponsors_action(player, strength, num)
  local upgd = player.sponsors_flipped
  printToAll(player.steam_name .. " takes the SPONSORS " .. (upgd and "II" or "I") ..
    " action at strength " .. strength .. ".")

  local budget = strength + (upgd and 1 or 0)

  sponsor_actions[player.color] = {
    player = player,
    num = num,
    strength = strength,
    remaining = budget,
    upgd = upgd,
    offers = {},
    selected = nil,
  }

  if num == "1" then
    player.persistent_rewards.sponsor_1_trade = true
  end

  if num == "2" then
    player.sponsor_2_active = true
  end

  if num == "3" then
    player.persistent_rewards.sponsor_3_discard = true
  end

  if num == "4" and not upgd then
    player.persistent_rewards.sponsor_4_snap = true
  end

  offer_sponsor_choices(player)
  render_claims_table(player)
end

function offer_sponsor_choices(player)
  local state = sponsor_actions[player.color]
  if state == nil then return end
  if state.opening_resolved then return end

  local upgd = state.upgd
  local strength = state.strength
  local money = upgd and (2 * strength) or strength

  for i = #player.claims, 1, -1 do
    if player.claims[i].sponsor_choice then table.remove(player.claims, i) end
  end

  local sub_table = { grouped = true, sponsor_choice = true }

  table.insert(sub_table, {
    button_text = "Break " .. strength .. ", Gain " .. money .. " Money",
    optional = false,
    function_call = function()
      state.opening_resolved = true
      break_x(strength, player)
      update_money(player, money)
      if upgd and state.num == "4" then
        offer_sponsor_4_marketing(player)
      end
    end
  })

  if #playable_sponsor_candidates(player, state.remaining) > 0 then
    table.insert(sub_table, {
      button_text = upgd and "Play Sponsor Cards" or "Play a Sponsor Card",
      optional = false,
      async = true,
      function_call = function()
        state.opening_resolved = true
        open_sponsor_panel(player)
      end
    })
  end

  table.insert(player.claims, sub_table)
end

function offer_sponsor_4_marketing(player)
  table.insert(player.claims, {
    {
      button_text = "Discard 1 card for Marketing",
      optional = true,
      async = true,
      valid = function()
        return #player_hand_cards(player) >= 2
           and #playable_marketing_candidates(player) > 0
      end,
      function_call = function()
        local record = active_claim
        active_claim = nil

        create_card_selection_panel(player, function() return player_hand_cards(player) end,
          1, "optional discard",
          function(discarded)
            if not discarded then
              render_claims_table(player)
              return
            end
            retire_claim_record(record)
            start_marketing(player, "Sponsors 4", { cancellable = false })
          end, nil, nil, nil, nil,
          function(selected)
            if marketing_candidates_after_discard(player, selected) == 0 then
              return "You must keep a playable Sponsor card to use Marketing!"
            end
            return nil
          end)
      end
    }
  })
end


card_flips = {}

function action_card_upgraded(card)
  return card ~= nil and card.is_face_down
end

function animals_upgraded(player)
  local state = animal_actions[player.color]
  if state ~= nil then return state.upgd end
  return player.animals_flipped
end

function sponsors_upgraded(player)
  local state = sponsor_actions[player.color]
  if state ~= nil then return state.upgd end
  return player.sponsors_flipped
end

function build_upgraded(player)
  local state = build_actions[player.color]
  if state ~= nil then return state.upgd end
  return player.build_flipped
end

function render_card_flip_panel(player)
  local color = player.color

  local parts = {
    [[<Text fontSize="18" color="#FFFFFF">Choose an action card to upgrade:</Text>]],
    [[<Text fontSize="18" color="#FFFFFF"></Text>]],
  }

  for slot = 1, 5 do
    local card = action_card_object(player, slot)
    parts[#parts + 1] = string.format([[
      <HorizontalLayout spacing="6" minHeight="34" childAlignment="MiddleLeft" childForceExpandHeight="false">
        <Text fontSize="20" color="#FFFFFF" width="20" alignment="MiddleRight">%d:</Text>
        <Button id="cardFlipButton_%s_%d" interactable="%s" onClick="on_card_flip_clicked(%s)" fontSize="14" width="220" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">%s</Button>
      </HorizontalLayout>
    ]], slot, color, slot, tostring(not action_card_upgraded(card)), color .. "_" .. slot,
        string.sub(card.getName(), 1, -3))
  end

  local height = 16 + 50 + 24 + 5 * 34 + 6 * 6

  set_player_panel(color, string.format([[
    <Panel id="cardFlipPanel_%s" visibility="%s" rectAlignment="MiddleRight" width="280" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="UpperCenter" childForceExpandHeight="false">
        %s
      </VerticalLayout>
    </Panel>
  ]], color, color, height, table.concat(parts, "\n")))
end

function card_flip(player, source)
  card_flips[player.color] = { player = player, source = source }
  render_card_flip_panel(player)
end

function card_flip_b(player, source)
  card_flip(player, source)
end

function on_card_flip_clicked(_, value, _)
  local color, slot = value:match("^(%a+)_(%d+)$")
  local state = card_flips[color]
  if state == nil then return end

  local player = state.player
  local card = action_card_object(player, tonumber(slot))
  if action_card_upgraded(card) then return end

  local label = string.sub(card.getName(), 1, -3)
  local message = player.steam_name .. " upgrades their " .. label .. " action card"
  if state.source ~= nil then
    message = message .. " from " .. state.source .. "'s card flip"
  end
  printToAll(message .. ".")

  set_tile_face(card, true)

  local attribute = cnsts.action_flip_attributes[string.sub(card.getName(), 1, 2)]
  if attribute ~= nil and attribute ~= borrowed_flip_attribute(player) then
    player[attribute] = true
  end

  card_flips[color] = nil
  clear_player_panel(color)
  render_claims_table(player)
end


display_marks = {}

function move_display_mark(slot, loc)
  local mark = display_marks[slot]
  if mark == nil then return end

  local above = { x = loc[1], y = loc[2] + cnsts.drop_height, z = loc[3] }
  local cube = getObjectFromGUID(mark)
  cube.setPositionSmooth(above, false, false)
end

function resolve_display_mark(slot, to_discard)
  local cube_guid = display_marks[slot]
  if cube_guid == nil then return nil end
  display_marks[slot] = nil

  local cube = getObjectFromGUID(cube_guid)
  local marker = find_player_by_color(cube_owner_color(cube))
  cube.destruct()

  if to_discard then return marker end
  update_money(marker, 2, "their marked card")
  return nil
end

mark_state = nil

function markable_display_slots()
  local out = {}
  for i = 1, 6 do
    local card = display_cards[i]
    if card ~= nil and display_marks[i] == nil
       and card_data_for(card.getName()).type == "animal" then
      out[#out + 1] = i
    end
  end
  return out
end

function start_mark(player, source)
  local slots = markable_display_slots()

  if #slots == 0 then
    broadcastToColor("There are no animals on the display available to be marked!",
      player.color, "Red")
    resume_post_action_rewards(player)
    return
  end

  if #slots == 1 then
    apply_mark(player, slots[1])
    resume_post_action_rewards(player)
    return
  end

  mark_state = { player = player, source = source, slots = {}, selected = nil }
  for _, slot in ipairs(slots) do
    mark_state.slots[slot] = true
    display_cards[slot].locked = false
  end
  render_mark_panel()
end

function mark_panel_xml()
  local player = mark_state.player
  local color = player.color

  local selection, height = "", 16 + 50 + 24 + 6
  if mark_state.selected ~= nil then
    selection = string.format([[
      <Text fontSize="18" color="#FFFFFF">You have selected:</Text>
      <Text fontSize="18" color="#FFFFFF">%s</Text>
      <Button id="markConfirmButton_%s" onClick="on_mark_confirm_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#3FA34D" textColor="#FFFFFF">Confirm</Button>
    ]], string.sub(display_cards[mark_state.selected].getName(), 7), color, color)
    height = height + 24 + 24 + 34 + 6 * 3
  end

  return string.format([[
    <Panel id="markPanel_%s" visibility="%s" rectAlignment="MiddleRight" width="280" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        <Text fontSize="18" color="#FFFFFF">Click on an animal card on the display to mark it.</Text>
        <Text fontSize="18" color="#FFFFFF"></Text>
        %s
      </VerticalLayout>
    </Panel>
  ]], color, color, height, selection)
end

function render_mark_panel()
  set_player_panel(mark_state.player.color, mark_panel_xml())
end

function return_display_card(slot)
  local card = display_cards[slot]
  card.drop()
  card.setPosition(cnsts.display_locs[slot])
  card.setRotation(cnsts.display_card_rotation)
  move_display_mark(slot, cnsts.display_locs[slot])
end

function handle_mark_pickup(slot)
  return_display_card(slot)
  mark_state.selected = slot
  render_mark_panel()
end

function on_mark_confirm_clicked(_, color, _)
  if mark_state == nil or mark_state.selected == nil then return end
  if mark_state.player.color ~= color then return end

  local player, slot = mark_state.player, mark_state.selected
  apply_mark(player, slot)

  mark_state = nil
  lock_display_cards()
  resume_post_action_rewards(player)
end

function apply_mark(player, slot)
  local card = display_cards[slot]
  printToAll(string.format("%s marks %s.", player.steam_name,
    string.sub(card.getName(), 7)))

  local pos = card.getPosition()
  local cube = take_player_cube(player,
    { x = pos.x, y = pos.y + cnsts.drop_height, z = pos.z })
  display_marks[slot] = cube.getGUID()
end

function redirect_marked_discard(slot, card)
  local marker = resolve_display_mark(slot, true)
  if marker == nil then return false end

  card.locked = false
  card.deal(1, marker.color, 1)
  printToAll(string.format("%s gets their marked %s card.",
    marker.steam_name, string.sub(card.getName(), 7)))
  return marker
end

function unlock_display_cards()
  for i = 1, 6 do
    if display_cards[i] ~= nil then display_cards[i].locked = false end
  end
end

function lock_display_cards()
  for i = 1, 6 do
    if display_cards[i] ~= nil then display_cards[i].locked = true end
  end
end

snap_player = nil
snap_remaining = 0
snap_refill = false
snap_card_type = nil
snap_max_size = nil
snap_callback = nil

function show_snap_prompt(player)
  local xml = string.format([[
    <Panel id="snapPrompt" visibility="%s" rectAlignment="MiddleRight" width="280" height="110" color="#222222DD">
      <VerticalLayout padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        <Text fontSize="18" color="#FFFFFF">Click on a card to snap from the display (%d remaining).</Text>
      </VerticalLayout>
    </Panel>
  ]], player.color, snap_remaining)
  set_player_panel(player.color, xml)
end

function arm_snap(player, num, refill, card_type, on_done, max_size)
  snap_player = player
  snap_remaining = num
  snap_refill = refill
  snap_card_type = card_type
  snap_max_size = max_size
  snap_callback = on_done

  unlock_snappable_display_cards()
end

function start_snap(player, num, refill, card_type, on_done, max_size)
  arm_snap(player, num, refill, card_type, on_done, max_size)
  show_snap_prompt(player)
end

function snappable_display_card(slot)
  local card = display_cards[slot]
  if card == nil then return false end

  local data = card_data_for(card.getName())
  if snap_card_type ~= nil and data.type ~= snap_card_type then return false end
  if snap_max_size ~= nil
     and (data.type ~= "animal" or data.size > snap_max_size) then
    return false
  end
  return true
end

function unlock_snappable_display_cards()
  for i = 1, 6 do
    if display_cards[i] ~= nil then
      display_cards[i].locked = not snappable_display_card(i)
    end
  end
end

function handle_snap_pickup(slot)
  local player = snap_player
  local card = display_cards[slot]

  card.deal(1, player.color, 1)
  printToAll(player.steam_name .. " snaps " .. string.sub(card.getName(), 7) .. " from the display.")
  resolve_display_mark(slot, false)
  display_cards[slot] = nil

  snap_remaining = snap_remaining - 1

  wait_for_cards_in_hand(player, 1, { card }, function()
    if snap_remaining > 0 then
      if snap_refill then
        refill_display()
        unlock_snappable_display_cards()
      end
      show_snap_prompt(player)
      return
    end

    lock_display_cards()
    clear_player_panel(player.color)
    snap_player = nil
    snap_card_type = nil
    snap_max_size = nil

    local done = snap_callback
    snap_callback = nil
    if done ~= nil then done(player) end

    render_claims_table(player)
  end)
end

function cards_in_rep_range(player)
  local rep = get_counter_value(player.rep_counter)
  local cards = {}
  for i, threshold in ipairs(cnsts.rep_range_thresholds) do
    if rep >= threshold and display_cards[i] ~= nil then
      table.insert(cards, display_cards[i])
    end
  end
  return cards
end

rep_draw_player = nil
rep_draw_remaining = 0
rep_draw_callback = nil
rep_draw_lookup = nil

function show_rep_draw_prompt(player)
  local xml = string.format([[
    <Panel id="repDrawPrompt" visibility="%s" rectAlignment="MiddleRight" width="280" height="140" color="#222222DD">
      <VerticalLayout padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        <Text fontSize="18" color="#FFFFFF">Click on a card to draw from within reputation range, or from the deck (%d remaining).</Text>
      </VerticalLayout>
    </Panel>
  ]], player.color, rep_draw_remaining)
  set_player_panel(player.color, xml)
end

function draw_from_rep_range(player, count, callback)
  rep_draw_player = player
  rep_draw_remaining = count or 1
  rep_draw_callback = callback
  rep_draw_lookup = {}

  for _, card in ipairs(cards_in_rep_range(player)) do
    card.locked = false
    rep_draw_lookup[card.getGUID()] = true
  end
  placeholder_card.interactable = true
  show_rep_draw_prompt(player)
end

function handle_rep_draw_pickup(slot)
  local player = rep_draw_player
  local card = display_cards[slot]

  card.deal(1, player.color, 1)
  printToAll(player.steam_name .. " draws " .. string.sub(card.getName(), 7) .. " from the display.")
  resolve_display_mark(slot, false)
  display_cards[slot] = nil

  wait_for_cards_in_hand(player, 1, { card }, advance_rep_draw)
end

function handle_rep_draw_deck_pickup()
  local player = rep_draw_player

  deal_cards_to_hand(zoo_deck, 1, player, 1, "zoo_card", function()
    printToAll(player.steam_name .. " draws a card from the deck.")
    advance_rep_draw()
  end)
end

function advance_rep_draw()
  rep_draw_remaining = rep_draw_remaining - 1
  if rep_draw_remaining > 0 then
    show_rep_draw_prompt(rep_draw_player)
    return
  end

  lock_display_cards()
  placeholder_card.interactable = false

  local player = rep_draw_player
  clear_player_panel(player.color)

  local callback = rep_draw_callback
  rep_draw_player = nil
  rep_draw_lookup = nil
  rep_draw_callback = nil

  if callback ~= nil then
    callback()
  else
    render_claims_table(player)
  end
end


shark_attack_state = nil

function animal_card_appeal(name)
  for _, reward in ipairs(card_data_for(name).rewards or {}) do
    if type(reward) == "string" then
      local appeal = reward:match("^(%d+) appeal$")
      if appeal then return tonumber(appeal) end
    end
  end
  return 0
end

function shark_attack_candidates(player)
  local rep = get_counter_value(player.rep_counter)
  local out = {}
  for i, threshold in ipairs(cnsts.rep_range_thresholds) do
    if rep >= threshold and display_cards[i] ~= nil
       and card_data_for(display_cards[i].getName()).type == "animal" then
      out[#out + 1] = { card = display_cards[i], slot = i }
    end
  end
  return out
end

function shark_attack(player, count, source)
  local candidates = shark_attack_candidates(player)

  if #candidates == 0 then
    broadcastToColor("There are no Animal cards within your reputation range!",
      player.color, "Red")
    render_claims_table(player)
    return
  end

  if #candidates <= count then
    finish_shark_attack(player, candidates, source)
    return
  end

  shark_attack_state = {
    player = player,
    remaining = count,
    source = source,
    taken = {},
    lookup = {}
  }
  for _, entry in ipairs(candidates) do
    shark_attack_state.lookup[entry.card.getGUID()] = true
    entry.card.locked = false
  end
  show_shark_attack_prompt(player)
end

function show_shark_attack_prompt(player)
  local xml = string.format([[
    <Panel id="sharkAttackPrompt" visibility="%s" rectAlignment="MiddleRight" width="280" height="140" color="#222222DD">
      <VerticalLayout padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        <Text fontSize="18" color="#FFFFFF">Click on an Animal card within your reputation range to attack (%d remaining).</Text>
      </VerticalLayout>
    </Panel>
  ]], player.color, shark_attack_state.remaining)
  set_player_panel(player.color, xml)
end

function handle_shark_attack_pickup(slot)
  local state = shark_attack_state
  local card = display_cards[slot]

  state.lookup[card.getGUID()] = nil
  table.insert(state.taken, { card = card, slot = slot })
  state.remaining = state.remaining - 1

  if state.remaining > 0 then
    show_shark_attack_prompt(state.player)
    return
  end

  shark_attack_state = nil
  clear_player_panel(state.player.color)
  finish_shark_attack(state.player, state.taken, state.source)
end

function finish_shark_attack(player, entries, source)
  local names, appeal = {}, 0
  for _, entry in ipairs(entries) do
    local name = entry.card.getName()
    names[#names + 1] = string.sub(name, 7)
    appeal = appeal + animal_card_appeal(name)
  end

  printToAll(player.steam_name .. " attacks " .. table.concat(names, " and ") ..
    " with " .. (source and (source .. "'s ") or "") .. "Shark Attack!")

  for _, entry in ipairs(entries) do
    entry.card.drop()
    if not redirect_marked_discard(entry.slot, entry.card) then
      entry.card.locked = false
      discard_pile.putObject(entry.card)
    end
    display_cards[entry.slot] = nil
  end

  lock_display_cards()

  update_appeal(player, math.floor(appeal / 2))
  render_claims_table(player)
end

digging_player = nil
digging_remaining = 0
digging_selected = nil
digging_selected_slot = nil
digging_hand_lookup = nil
digging_rescue = nil

function refresh_digging_hand_lookup()
  digging_hand_lookup = {}
  for _, card in ipairs(Player[digging_player.color].getHandObjects(1)) do
    digging_hand_lookup[card.getGUID()] = true
  end
end

function show_digging_prompt()
  local color = digging_player.color

  local selection = ""
  local height = 16 + 50 + 26 + 34 + 12
  if digging_selected ~= nil then
    local selected_text = "You have selected:\n" ..
      string.sub(digging_selected.getName(), 7) .. "\n"
    selection = string.format([[
      <Text fontSize="18" color="#FFFFFF">%s</Text>
      <Button id="diggingConfirmButton" onClick="on_digging_confirm_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">Confirm</Button>
    ]], selected_text, color)
    height = height + 70 + 34 + 12
  end

  set_player_panel(color, string.format([[
    <Panel id="diggingPanel" visibility="%s" rectAlignment="MiddleRight" width="280" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        <Text fontSize="18" color="#FFFFFF">Dig up to %d cards from your hand or the display.</Text>
        <Text fontSize="18" color="#FFFFFF"></Text>
        %s
        <Button id="diggingPassButton" onClick="on_digging_pass_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#C61715" textColor="#FFFFFF">Pass</Button>
      </VerticalLayout>
    </Panel>
  ]], color, height, digging_remaining, selection, color),
    function()
      if digging_player == nil then return end
      refresh_digging_hand_lookup()
      show_digging_prompt()
    end)
end

function digging(player, count)
  retire_active_claim()

  digging_player = player
  digging_remaining = count
  digging_selected = nil
  digging_selected_slot = nil
  digging_rescue = nil

  unlock_display_cards()
  refresh_digging_hand_lookup()
  show_digging_prompt()
end

function handle_digging_pickup(card, slot)
  digging_selected = card
  digging_selected_slot = slot

  show_digging_prompt()
end

function on_digging_confirm_clicked(_, color, _)
  if digging_player == nil or color ~= digging_player.color then return end
  if digging_selected == nil then return end

  if digging_rescue and rescuable_card(digging_selected) then
    show_rescue_prompt()
    return
  end

  discard_digging_pick()
end

function discard_digging_pick()
  local player = digging_player
  local card = digging_selected
  local slot = digging_selected_slot
  digging_selected = nil
  digging_selected_slot = nil

  local card_name = string.sub(card.getName(), 7)
  if slot ~= nil then
    printToAll(string.format("%s digs %s from the display.", player.steam_name, card_name))
    local guid = card.getGUID()
    local marker = redirect_marked_discard(slot, card)
    display_cards[slot] = nil
    local leaving
    if marker then
      leaving = { { guid = guid, color = marker.color } }
    else
      leaving = { { guid = guid } }
      move_cards_to_discard({ card })
    end

    refill_display(function()
      unlock_display_cards()
      continue_digging_pick(player)
    end, leaving)
    return
  end

  if discard_face_down then
    printToAll(string.format("%s digs a card from their hand.", player.steam_name))
  else
    printToAll(string.format("%s digs %s from their hand.", player.steam_name, card_name))
  end
  move_cards_to_discard({ card })
  deal_tagged_card(zoo_deck, nil, player.color, 1, "zoo_card")
  continue_digging_pick(player, card.getGUID(),
                        #Player[player.color].getHandObjects(1))
end

function continue_digging_pick(player, dug_guid, hand_before)
  if digging_player == nil then return end

  digging_remaining = digging_remaining - 1
  if digging_remaining <= 0 then
    end_digging()
    return
  end

  show_digging_prompt()
  if dug_guid == nil then return end
  Wait.condition(
    function()
      if digging_player ~= nil then refresh_digging_hand_lookup() end
    end,
    function()
      return getObjectFromGUID(dug_guid) == nil
        and #Player[player.color].getHandObjects(1) == hand_before
    end
  )
end

function on_digging_pass_clicked(_, color, _)
  if digging_player == nil or color ~= digging_player.color then return end
  end_digging()
end

function close_digging()
  lock_display_cards()

  local player = digging_player
  clear_player_panel(player.color)

  digging_player = nil
  digging_remaining = 0
  digging_selected = nil
  digging_selected_slot = nil
  digging_hand_lookup = nil
  digging_rescue = nil

  return player
end

function end_digging()
  render_claims_table(close_digging())
end


function rescuable_card(obj)
  local data = card_data_for(obj.getName())
  return data.type == "animal" and not card_matches_search_key(data, "petting")
end

function rescue_station_position(board_pos, index)
  local pos = board_pos + cnsts.rescue_params.first_relative_pos
  for _ = 1, index - 1 do
    pos = pos + cnsts.rescue_params.step
  end
  return pos
end

function show_rescue_prompt()
  local color = digging_player.color
  local name = string.sub(digging_selected.getName(), 7)

  set_player_panel(color, string.format([[
    <Panel id="rescuePanel" visibility="%s" rectAlignment="MiddleRight" width="280" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        <Text fontSize="18" color="#FFFFFF">%s</Text>
        <Text fontSize="18" color="#FFFFFF"></Text>
        <Button id="rescueConfirmButton" onClick="on_rescue_confirm_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">Rescue this animal</Button>
        <Button id="rescueDiscardButton" onClick="on_rescue_discard_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#C61715" textColor="#FFFFFF">Discard this animal</Button>
      </VerticalLayout>
    </Panel>
  ]], color, 16 + 70 + 26 + 34 + 34 + 18,
      "You have selected:\n" .. name .. "\n", color, color))
end

function on_rescue_discard_clicked(_, color, _)
  if digging_player == nil or color ~= digging_player.color then return end
  if digging_selected == nil then return end
  discard_digging_pick()
end

function on_rescue_confirm_clicked(_, color, _)
  if digging_player == nil or color ~= digging_player.color then return end
  if digging_selected == nil then return end

  local player = digging_player
  local card = digging_selected
  local slot = digging_selected_slot
  local data = card_data_for(card.getName())
  local name = string.sub(card.getName(), 7)

  printToAll(string.format("%s rescues %s.", player.steam_name, name))

  table.insert(player.map_rescue_station, card.getGUID())
  card.setPosition(rescue_station_position(player.player_board.getPosition(),
                                           #player.map_rescue_station))
  card.setRotation(cnsts.rescue_params.rotation)
  card.locked = true

  if slot ~= nil then
    resolve_display_mark(slot, false)
    display_cards[slot] = nil
    refill_display()
  else
    deal_tagged_card(zoo_deck, nil, player.color, 1, "zoo_card")
  end

  local groups = append_icon_groups({}, player, data.icons)
  local waza = waza_assignment_appeal(data, player)
  if waza > 0 then
    groups[#groups + 1] =
      { rewards = { waza .. " appeal" }, source = "Waza Special Assignment" }
  end

  close_digging()
  if #groups > 0 then
    create_claims_from_reward_groups(player, groups, false)
  else
    render_claims_table(player)
  end
end

function rescue(player, source)
  digging(player, 1)
  if #player.map_rescue_station < cnsts.rescue_params.capacity then
    digging_rescue = true
  end
end


function cave_position(board_pos, index)
  local pos = board_pos + cnsts.store_params.first_relative_pos
  for _ = 1, index - 1 do
    pos = pos + cnsts.store_params.step
  end
  return pos
end

function has_stored_cards(player)
  return player.map_caves ~= nil and #player.map_caves > 0
end

function store(player, source)
  if #player.map_caves >= cnsts.store_params.capacity then
    broadcastToColor("You cannot store any more cards!", player.color, "Red")
    render_claims_table(player)
    return
  end

  local hand = player_hand_cards(player)
  if #hand == 0 then
    broadcastToColor("You have no cards in hand to store!", player.color, "Red")
    render_claims_table(player)
    return
  end

  create_card_selection_panel(player, function() return player_hand_cards(player) end,
    1, "store")
end

function store_card(player, card)
  local slot = #player.map_caves + 1
  local marker = placeholder_card.clone({
    rotation = cnsts.store_params.rotation
  })
  marker.setPosition(cave_position(player.player_board.getPosition(), slot))
  marker.setScale(cnsts.store_params.scale)
  marker.interactable = false
  marker.locked = true
  player.map_caves[slot] = marker.getGUID()

  card.removeTag("zoo_card")
  card.addTag("store")
  card.deal(1, player.color, cnsts.store_params.hand_index)

  add_income(player, "2 money", "a stored card")
  printToAll(player.steam_name .. " stores a card.")

  if not player.store_info_shown then
    player.store_info_shown = true
    show_store_info(player.color)
  end

  render_claims_table(player)
end

function store_info_key(color)
  return "store_info_" .. color
end

function show_store_info(color)
  local text = "Your stored cards are shown in the row below your final scoring cards.\n" ..
    "You can unstore them at any time by dragging them out of that row, which will automatically move them back into your hand.\n\n" ..
    "NOTE: Unstoring cannot be undone except with a rewind, so make sure that is what you want to do. You will not be able to simply drag cards back into that row to store them again!"

  set_active_panel(store_info_key(color), string.format([[
    <Panel id="storeInfoPanel_%s" visibility="%s" rectAlignment="MiddleCenter" width="520" height="%d" color="#222222FF">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        <Text id="storeInfoText_%s" fontSize="18" color="#FFFFFF">%s</Text>
        <Text fontSize="18" color="#FFFFFF"></Text>
        <Button id="storeInfoOkButton_%s" onClick="on_store_info_ok_clicked(%s)" fontSize="16" width="120" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">OK</Button>
      </VerticalLayout>
    </Panel>
  ]], color, color, 16 + 8 * 30 + 30 + 34 + 18, color, text, color, color))
end

function on_store_info_ok_clicked(_, color, _)
  clear_active_panel(store_info_key(color))
end

function unstore_card(player, card)
  card.removeTag("store")
  card.addTag("zoo_card")
  card.deal(1, player.color, 1)

  local marker = getObjectFromGUID(table.remove(player.map_caves))
  marker.destruct()

  remove_income(player, "2 money", "a stored card")
  printToAll(player.steam_name .. " unstores a card.")

  wait_for_cards_in_hand(player, 1, { card }, function()
    refresh_open_panel(player.color)
  end)
end

function on_placeholder_card_picked_up(params)
  if rep_draw_player == nil then return end
  if params.color ~= rep_draw_player.color then return end

  handle_rep_draw_deck_pickup()
end

function cards_action_draw(player, deal_count, discard_count)
  deal_cards_to_hand(zoo_deck, deal_count, player, 1, "zoo_card", function()
    printToAll(player.steam_name .. " draws " .. deal_count .. " cards from the deck.")
    if discard_count > 0 then
      prompt_discard(player, discard_count)
    else
      render_claims_table(player)
    end
  end)
end

function prompt_discard(player, count, callback)
  if count == nil or count <= 0 then return end

  create_card_selection_panel(player,
    function() return Player[player.color].getHandObjects(1) end, count, "discard",
    callback or function() render_claims_table(player) end)
end

function prompt_final_scoring_discard(player, count, pool, callback)
  if count == nil or count <= 0 then return end

  create_card_selection_panel(player, pool or Player[player.color].getHandObjects(2),
    count, "final scoring discard", callback or function() render_claims_table(player) end)
end

function prompt_keep(player, pool, count, callback, silent)
  create_card_selection_panel(player, pool, count, "keep",
    callback or function() render_claims_table(player) end, nil, nil, nil, silent)
end

function cards_action(player, strength, num)
  local upgd = player.cards_flipped
  printToAll(player.steam_name .. " takes the CARDS " .. (upgd and "II" or "I") .. " action at strength " .. strength .. ".")

  break_x(2, player)

  if num == "4" then
    table.insert(player.post_action_rewards,
      { upgd and "clever" or "paid clever", "Cards 4" })
  end

  local draws = {1, 1, 2, 2, 3}
  local discards = {1, 0, 1, 0, 1}
  local snaps = {0, 0, 0, 0, 1}

  if upgd then
    draws = {1, 2, 2, 3, 4}
    discards = {0, 1, 0, 1, 1}
    if num == "3" then
      snaps = {0, 1, 1, 1, 2}
    else
      snaps = {0, 0, 1, 1, 1}
    end
  elseif num == "3" then
      snaps = {0, 0, 1, 1, 1}
  end

  local effective_strength = math.min(strength, 5)
  local deal_count = draws[effective_strength]
  local discard_count = (num == "1") and 0 or discards[effective_strength]
  local snap_count = snaps[effective_strength]
  local cards_claims = {grouped = true}

  if snap_count > 0 then
    table.insert(cards_claims,
    {button_text = (snap_count == 1) and "Snap a card" or "Snap two cards",
     async = true,
     function_call = function() start_snap(player, snap_count, false) end
    })
  end

  local draw_button_text = "Draw " .. deal_count .. " cards"
  if discard_count > 0 then
    draw_button_text = draw_button_text .. ", discard " .. discard_count
  end

  if upgd then
    local after_draw = nil
    if discard_count > 0 then
      after_draw = function() prompt_discard(player, discard_count) end
    end

    table.insert(cards_claims,
      {button_text = draw_button_text,
      async = true,
      function_call = function() draw_from_rep_range(player, deal_count, after_draw) end
      })
  else
    table.insert(cards_claims,
      {button_text = draw_button_text,
      async = true,
      function_call = function() cards_action_draw(player, deal_count, discard_count) end
      })
  end

  table.insert(player.claims, cards_claims)

  if num == "2" then
    create_claims_from_rewards(player, { "digging " .. (upgd and 2 or 1) }, "the CARDS-2 action")
  else
    render_claims_table(player)
  end
end

function buildable_terrain(player)
  return {
    upgd = player.build_flipped,
    rock = player.diversity_researcher,
    water = player.diversity_researcher,
    cover = player.build_4_effect and 1 or 0,
  }
end

function build_action_available(player)
  return get_counter_value(player.money_counter) >= 2
end

function build_tile_search_name(button_text)
  local name = button_text:match("^Build a (.+)$")
  name = name:gsub(" Enclosure$", "")
  name = name:gsub("%-", " ")
  return string.upper(name)
end

local BUILD_OPTIONS = {
  { text = "Build a Kiosk" },
  { text = "Build a Pavilion" },
  { text = "Build a Size-1 Enclosure" },
  { text = "Build a Size-2 Enclosure" },
  { text = "Build a Small Aquarium",    tag = "small_aquarium", requires_mw = true },
  { text = "Build a Size-3 Enclosure" },
  { text = "Build a Petting Zoo",       tag = "petting_zoo" },
  { text = "Build a Size-4 Enclosure" },
  { text = "Build a Size-5 Enclosure" },
  { text = "Build a Large Aquarium",    tag = "large_aquarium", requires_mw = true },
  { text = "Build a Large Bird Aviary", tag = "large_bird_aviary", requires_upgd = true },
  { text = "Build a Reptile House",     tag = "reptile_house", requires_upgd = true },
}

local UNIQUE_BUILDS = {}
for _, option in ipairs(BUILD_OPTIONS) do
  if option.tag ~= nil then
    UNIQUE_BUILDS[build_tile_search_name(option.text)] = true
  end
end

build_actions = {}

function build_placement_opts(player, search_name)
  local map = player.map
  local opts = { allowed = buildable_terrain(player) }

  if (search_name == "SMALL AQUARIUM" or search_name == "LARGE AQUARIUM")
     and not opts.allowed.water then
    opts.terrain_requirements = { { tag = "water", min = 1 } }
  end

  if search_name == "KIOSK" then
    opts.extra_check = function(candidate_cells)
      for _, id in ipairs(map:tilesWithTag("kiosk")) do
        for _, c in ipairs(candidate_cells) do
          for _, kc in ipairs(map:cellsOf(id)) do
            if map:cellDistance(c, kc) < 3 then return false end
          end
        end
      end
      return true
    end
  end

  return opts
end

function fresh_build_placement(player, option)
  if option.size * 2 > get_counter_value(player.money_counter) then return nil end

  local opts = build_placement_opts(player, option.search_name)
  local cells = player.map:findValidPlacement(option.shape, opts)
  if cells == nil then return nil end

  return { option = option, cells = cells, opts = opts }
end

function build_candidates(player, state)
  local upgd = state.upgd
  local out = {}

  for _, option in ipairs(BUILD_OPTIONS) do
    local search_name = build_tile_search_name(option.text)
    local shape = cnsts.build_tile_shapes[search_name]
    local size = shape and #shape or 0

    local repeatable = (state.num == "3" and search_name:match("^SIZE %d+$") ~= nil)

    if shape ~= nil
       and (not option.requires_mw or marine_worlds_enabled)
       and (not option.requires_upgd or upgd)
       and (option.tag == nil or #player.map:tilesWithTag(option.tag) == 0)
       and (repeatable or not state.built[search_name])
       and size <= state.remaining then
      local candidate = fresh_build_placement(player, {
        text = option.text, search_name = search_name, shape = shape, size = size
      })
      if candidate ~= nil then out[#out + 1] = candidate end
    end
  end

  return out
end

function offer_build_choices(player)
  local state = build_actions[player.color]
  if state == nil then return false end

  local sub_table = { grouped = true }

  if state.upgd then
    sub_table.note = function()
      return "Remaining strength: " .. state.remaining
    end
  end

  for _, candidate in ipairs(build_candidates(player, state)) do
    table.insert(sub_table, {
      button_text = candidate.option.text,
      optional = not state.first,
      async = true,
      function_call = function()
        local record = active_claim
        active_claim = nil

        local fresh = fresh_build_placement(player, candidate.option)
        if fresh == nil then
          local label = candidate.option.text:gsub("^Build ", "")
          broadcastToColor("Cannot place " .. label .. "!", player.color, "Red")
          retire_claim_record(record)
          offer_build_choices(player)
          render_claims_table(player)
          return
        end

        spawn_pending_building(player, fresh, record)
      end
    })
  end

  if #sub_table == 0 then return false end
  table.insert(player.claims, sub_table)
  return true
end

function offer_another_build(player)
  local state = build_actions[player.color]
  if state == nil then return false end

  table.insert(player.claims, {
    {
      button_text = "Build another building",
      optional = true,
      async = true,
      valid = function() return #build_candidates(player, state) > 0 end,
      function_call = function()
        retire_claim_record(active_claim)
        active_claim = nil
        offer_build_choices(player)
        render_claims_table(player)
      end
    }
  })
  return true
end

function build_action(player, strength, num)
  local upgd = player.build_flipped
  printToAll(player.steam_name .. " takes the BUILD " .. (upgd and "II" or "I") ..
    " action at strength " .. strength .. ".")

  rearm_effect(player, "engineer")

  if num == "4" then player.build_4_effect = true end

  if num == "1" then
    player.persistent_rewards[upgd and "build_1up_effect" or "build_1_effect"] = true
  elseif num == "2" then
    player.persistent_rewards[upgd and "build_2up_effect" or "build_2_effect"] = true
  end

  local effective = strength + (num == "3" and 1 or 0)

  build_actions[player.color] = {
    num = num,
    strength = effective,
    remaining = effective,
    upgd = upgd,
    first = true,
    built = {}
  }

  if not offer_build_choices(player) then
    printToAll(player.steam_name .. " has nowhere to build.")
    set_player_panel(player.color, build_dead_end_xml(player.color))
    for _, p in ipairs(players) do
      if p.color ~= player.color then
        set_waiting_status(p, player.steam_name .. " has nowhere to build."
          .. "\nUse rewind to undo their action.")
      end
    end
    return
  end

  render_claims_table(player)
end

function build_dead_end_xml(color)
  return string.format([[
    <Panel id="buildDeadEndPanel_%s" visibility="%s" rectAlignment="MiddleRight" width="280" height="106" color="#222222DD">
      <VerticalLayout padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        <Text fontSize="18" color="#FFFFFF">You have nowhere left to build.
Use rewind to undo this action.</Text>
      </VerticalLayout>
    </Panel>
  ]], color, color)
end

function spawn_pending_building(player, candidate, claim)
  building_clone_source(candidate.option.search_name,
    function(obj)
      local board_pos = player.player_board.getPosition()
      local transform = tile_object_transform_for_cells(obj, board_pos, candidate.cells)
      local drop_position = { x = transform.position.x, y = transform.position.y + 2, z = transform.position.z }
      local placed = obj.clone({ position = drop_position, rotation = transform.rotation })

      placed.setLuaScript(cnsts.building_tile_script)
      placed = placed.reload()

      player.pending_building = {
        tile_guid = placed.getGUID(),
        option = candidate.option,
        opts = candidate.opts,
        price = candidate.price,
        bonus = candidate.bonus,
        money_source = candidate.money_source,
        claim = claim
      }
      show_building_placement_panel(player, false)
    end)
end

function start_bonus_build(player, extra)
  if get_counter_value(player.money_counter) < extra.price then
    broadcastToColor("Insufficient money! (Need " .. extra.price .. ")", player.color, "Red")
    render_claims_table(player)
    return
  end

  local opts = build_placement_opts(player, extra.search_name)
  local shape = cnsts.build_tile_shapes[extra.search_name]
  local cells = player.map:findValidPlacement(shape, opts)
  if cells == nil then
    broadcastToColor("Cannot place " .. label_from_key(extra.search_name:lower()) .. "!",
      player.color, "Red")
    render_claims_table(player)
    return
  end

  player.persistent_rewards[extra.key] = nil
  spawn_pending_building(player, {
    option = { text = extra.text, search_name = extra.search_name, shape = shape, size = #shape },
    cells = cells,
    opts = opts,
    price = extra.price,
    bonus = extra.key,
    money_source = extra.money_source
  })
end

function grant_engineer_build(player, building_name, search_name, cells)
  if UNIQUE_BUILDS[search_name] then return end

  local key = "engineer_" .. (#player.engineer_builds + 1)

  player.engineer_builds[#player.engineer_builds + 1] = {
    key = key,
    text = "Build a " .. building_name .. "\n(Engineer)",
    search_name = search_name,
    price = 2 * #cells,
    money_source = building_name .. " (Engineer bonus build)",
  }
  player.persistent_rewards[key] = true
end

function engineer_build(player, key)
  for _, extra in ipairs(player.engineer_builds) do
    if extra.key == key then return extra end
  end
  return nil
end

function spend_engineer(player)
  for _, extra in ipairs(player.engineer_builds) do
    player.persistent_rewards[extra.key] = nil
  end
  player.engineer = false
end

function clear_build_action_state(player)
  for _, extra in ipairs(cnsts.build_extra_rewards) do
    player.persistent_rewards[extra.key] = nil
  end
  for _, extra in ipairs(player.engineer_builds) do
    player.persistent_rewards[extra.key] = nil
  end
  player.engineer_builds = {}
  player.build_4_effect = nil
  build_actions[player.color] = nil
end


tile_placements = {}

function tile_placement_opts(player, search_name)
  local opts = build_placement_opts(player, search_name)
  opts.allowed.cover = 0
  return opts
end

function start_tile_placement(player, config)
  local opts_for = config.opts_for or tile_placement_opts
  for _, kind in ipairs(config.kinds) do
    local opts = opts_for(player, kind)
    local cells = player.map:findValidPlacement(cnsts.build_tile_shapes[kind], opts)
    if cells ~= nil then
      tile_placements[player.color] =
        { player = player, config = config, kind = kind, opts = opts }
      spawn_placement_tile(player, 2, function(obj)
        return tile_object_transform_for_cells(obj, player.player_board.getPosition(), cells)
      end)
      return
    end
  end

  broadcastToColor(config.full_message, player.color, "Red")
  render_claims_table(player)
end

function spawn_placement_tile(player, lift, transform_for)
  local state = tile_placements[player.color]
  local cloning = state.config.clone ~= false

  local function place(obj)
    local transform = transform_for(obj)
    local position = { x = transform.position.x,
                       y = transform.position.y + lift,
                       z = transform.position.z }

    local placed
    if cloning then
      placed = obj.clone({ position = position, rotation = transform.rotation })
    else
      obj.setPosition(position)
      obj.setRotation(transform.rotation)
      placed = obj
    end
    placed.setLuaScript(cnsts.building_tile_script)
    placed = placed.reload()
    state.tile_guid = placed.getGUID()

    refresh_placement_validity(player, placed)
    render_tile_placement_panel(player)
  end

  if cloning then
    building_clone_source(state.kind, place)
    return
  end

  local bag = state.config.bag
  local guid = tile_guid_in_bag(bag, state.kind)
  if guid == nil then
    error("no " .. tostring(state.kind) .. " left in the sponsor building bag")
  end
  bag.takeObject({
    guid = guid,
    position = bag.getPosition() + Vector(0, 1, 0),
    smooth = false,
    callback_function = place
  })
end

function refresh_placement_validity(player, tile)
  local state = tile_placements[player.color]
  local cells = tile_cells_from_object(tile, player.player_board.getPosition())
  state.can_confirm = cells ~= nil
    and player.map:canPlace(cells, state.opts.allowed, state.opts)
    and placement_meets_requirements(player.map, cells, state.opts)
end

function render_tile_placement_panel(player)
  local state = tile_placements[player.color]
  if state == nil then return end
  local color, config = player.color, state.config

  local prompt = config.prompt
  if type(prompt) == "function" then prompt = prompt() end

  local parts, heights = {}, {}
  local function add(xml, h)
    parts[#parts + 1] = xml
    heights[#heights + 1] = h
  end
  local function blank()
    add([[<Text fontSize="18" color="#FFFFFF"></Text>]], 26)
  end

  add(string.format([[<Text fontSize="18" color="#FFFFFF">%s</Text>]], prompt),
    config.prompt_height or 50)
  blank()

  if #config.kinds > 1 then
    for i, kind in ipairs(config.kinds) do
      add(string.format([[
        <Button id="tilePlacementKindButton_%s_%d" onClick="on_tile_placement_kind_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="%s" textColor="#FFFFFF">%s</Button>
      ]], color, i, color .. "|" .. i,
          (state.kind == kind) and "#3FA34D" or "#4A90D9",
          label_from_key(kind:lower())), 34)
    end
  end

  if state.can_confirm then
    blank()
    add(string.format([[
      <Button id="tilePlacementConfirmButton_%s" onClick="on_tile_placement_confirm_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#3FA34D" textColor="#FFFFFF">Confirm</Button>
    ]], color, color), 34)
  end

  if config.allow_pass then
    blank()
    add(string.format([[
      <Button id="tilePlacementPassButton_%s" onClick="on_tile_placement_pass_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#C61715" textColor="#FFFFFF">Pass</Button>
    ]], color, color), 34)
  end

  local height = 16 + 6 * (#parts - 1)
  for _, h in ipairs(heights) do height = height + h end

  set_player_panel(color, string.format([[
    <Panel id="tilePlacementPanel_%s" visibility="%s" rectAlignment="MiddleRight" width="280" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        %s
      </VerticalLayout>
    </Panel>
  ]], color, color, height, table.concat(parts, "\n")))
end

function on_tile_placement_kind_clicked(_, value, _)
  local color, index = value:match("^(%a+)|(%d+)$")
  local state = tile_placements[color]
  if state == nil or state.tile_guid == nil then return end

  local kind = state.config.kinds[tonumber(index)]
  if kind == nil or kind == state.kind then return end

  local old = getObjectFromGUID(state.tile_guid)
  local position, rotation = old.getPosition(), old.getRotation()
  old.destruct()

  local player = state.player
  state.kind = kind
  state.opts = (state.config.opts_for or tile_placement_opts)(player, kind)
  state.tile_guid = nil

  spawn_placement_tile(player, 0.5,
    function() return { position = position, rotation = rotation } end)
end

function on_tile_placement_confirm_clicked(_, color, _)
  local state = tile_placements[color]
  if state == nil or not state.can_confirm or state.tile_guid == nil then return end

  local player = state.player
  local tile = getObjectFromGUID(state.tile_guid)
  local board_pos = player.player_board.getPosition()
  local cells = tile_cells_from_object(tile, board_pos)

  if cells == nil
     or not player.map:canPlace(cells, state.opts.allowed, state.opts)
     or not placement_meets_requirements(player.map, cells, state.opts) then
    return
  end

  local tag = string.lower(state.kind):gsub(" ", "_")
  local id, reward = player.map:place(cells, { tag }, state.opts.allowed, state.opts)

  player.map.tiles[id].tags.placement = building_placement_rules(state.opts)

  player.building_tiles[id] = tile
  tile.interactable = false

  local transform = tile_object_transform_for_cells(tile, board_pos, cells)
  if transform ~= nil then
    tile.setPosition(transform.position)
    tile.setRotation(transform.rotation)
  end

  clear_player_panel(color)
  tile_placements[color] = nil

  state.config.on_confirm(player, tag, id, reward)
end

function on_tile_placement_pass_clicked(_, color, _)
  local state = tile_placements[color]
  if state == nil then return end
  local player, on_pass = state.player, state.config.on_pass
  close_tile_placement(player)
  on_pass(player)
end

function close_tile_placement(player)
  local state = tile_placements[player.color]
  if state == nil then return end

  if state.tile_guid ~= nil then
    local tile = getObjectFromGUID(state.tile_guid)
    if tile ~= nil then tile.destruct() end
  end

  tile_placements[player.color] = nil
  clear_player_panel(player.color)
end


function posturing(player, count, source)
  retire_active_claim()

  local remaining = count
  local config

  config = {
    kinds = { "PAVILION", "KIOSK" },
    prompt = function()
      return string.format(
        "Posturing %d\nPlace a kiosk/pavilion on your map (Remaining: %d).",
        count, remaining)
    end,
    full_message = "Your map is full!",
    allow_pass = true,
    on_pass = function(p) render_claims_table(p) end,
    on_confirm = function(p, tag, id, reward)
      printToAll(string.format("%s adds a %s from %s Posturing.", p.steam_name,
        label_from_key(tag), source and (source .. "'s") or "their"))
      credit_building_added(p, tag, id)

      remaining = remaining - 1

      if remaining > 0 then
        table.insert(p.claims, { {
          button_text = "Continue Posturing",
          async = true,
          function_call = function() start_tile_placement(p, config) end
        } })
      end

      claim_placement_rewards(p, reward, "placement bonus", tag, id)
    end
  }

  start_tile_placement(player, config)
end

function reptile_house_or_aviary(player, source)
  local kinds = {}
  for _, kind in ipairs({ "REPTILE HOUSE", "LARGE BIRD AVIARY" }) do
    if #player.map:tilesWithTag((kind:lower():gsub(" ", "_"))) == 0 then
      kinds[#kinds + 1] = kind
    end
  end

  start_tile_placement(player, {
    kinds = kinds,
    prompt = "Place a Reptile House or Large Bird Aviary on your zoo map.",
    prompt_height = 75,
    full_message = "No space on your map!",
    allow_pass = false,
    on_confirm = function(p, tag, id, reward)
      printToAll(string.format("%s adds a %s from %s.", p.steam_name,
        label_from_key(tag), source or "a card"))
      credit_building_added(p, tag, id)

      claim_placement_rewards(p, reward, "placement bonus", tag, id)
    end
  })
end

function free_building(player, building, source)
  retire_active_claim()

  local kind = building:upper():gsub("_", " ")
  local label = label_from_key(building)

  start_tile_placement(player, {
    kinds = { kind },
    prompt = "Place a free " .. label .. " on your zoo map.",
    full_message = "Your map has no space for this building!",
    allow_pass = true,
    on_pass = function(p) render_claims_table(p) end,
    on_confirm = function(p, tag, id, reward)
      printToAll(string.format("%s places a free %s with %s.", p.steam_name,
        label, source or "a card"))
      credit_building_added(p, tag, id)

      claim_placement_rewards(p, reward, "placement bonus", tag, id)
    end
  })
end

function peacocking(player, source)
  free_building(player, "large bird aviary", source)
end


expand_actions = {}

function board_without_tile(player, omit_id)
  local scratch = HexBoard.Board.new(cnsts.map_data[player.map_key].cells)
  for id in pairs(scratch.tiles) do scratch:remove(id) end

  local ANY = { upgd = true, rock = true, water = true, cover = 0 }
  for id, tile in pairs(player.map.tiles) do
    if id ~= omit_id then
      scratch:placeUnchecked(tile.cells, { tile.tags.type }, ANY)
    end
  end
  return scratch
end

function expand_terrain(board, player, old_cells)
  local allowed = buildable_terrain(player)
  allowed.cover = board:coverBudgetUsed(old_cells, allowed)
  return allowed
end

function expandable_enclosures(player)
  local out = {}

  for id, tile in pairs(player.map.tiles) do
    local size = tile.tags.type and tile.tags.type:match("^size_(%d)$")
    size = size and tonumber(size)
    local shape = size and cnsts.build_tile_shapes["SIZE " .. (size + 1)]

    if shape ~= nil then
      local needed = {}
      for _, cell in ipairs(tile.cells) do needed[cell] = true end

      local scratch = board_without_tile(player, id)
      local target = scratch:findValidPlacement(shape, {
        allowed = expand_terrain(scratch, player, tile.cells),
        extra_check = function(cells)
          local covered = 0
          for _, cell in ipairs(cells) do
            if needed[cell] then covered = covered + 1 end
          end
          return covered == #tile.cells
        end,
      })

      if target ~= nil then
        out[#out + 1] = { id = id, size = size, cells = tile.cells, target = target }
      end
    end
  end

  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

function expand_extra_cell(old_cells, cells)
  if #cells ~= #old_cells + 1 then return nil end

  local needed, extra = {}, nil
  for _, cell in ipairs(old_cells) do needed[cell] = true end
  for _, cell in ipairs(cells) do
    if not needed[cell] then
      if extra ~= nil then return nil end
      extra = cell
    end
  end
  return extra
end

function expand_enclosure(player, source)
  retire_active_claim()

  local options = expandable_enclosures(player)
  if #options == 0 then
    broadcastToColor("None of your enclosures has room to grow!", player.color, "Red")
    render_claims_table(player)
    return
  end

  expand_actions[player.color] = {
    player = player, source = source, phase = "select",
    options = options, chosen = nil,
  }
  for _, option in ipairs(options) do
    player.building_tiles[option.id].interactable = true
  end

  render_expand_highlights(player)
  render_expand_panel(player)
end

function render_expand_highlights(player)
  local state = expand_actions[player.color]
  for _, option in ipairs(state.options) do
    local tile = player.building_tiles[option.id]
    tile.highlightOn(state.chosen == option.id and { 0, 1, 0 } or { 1, 0, 0 })
  end
end

function select_expand_target(player, state, id)
  for _, option in ipairs(state.options) do
    if option.id == id then
      state.chosen = id
      render_expand_highlights(player)
      render_expand_panel(player)
      return
    end
  end
end

function render_expand_panel(player)
  set_player_panel(player.color,
    expand_panel_xml(player.color, expand_actions[player.color]))
end

function expand_panel_xml(color, state)
  local blank = [[<Text fontSize="18" color="#FFFFFF"></Text>]]
  local parts, height = {}, 16 + 12

  if state.phase == "select" then
    parts[#parts + 1] =
      [[<Text fontSize="18" color="#FFFFFF">Select an enclosure to expand by 1.</Text>]]
    parts[#parts + 1] = blank
    height = height + 60 + 26

    if state.chosen ~= nil then
      parts[#parts + 1] = string.format([[
        <Button id="expandSelectConfirm_%s" onClick="on_expand_select_confirm_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">Confirm</Button>
      ]], color, color)
      parts[#parts + 1] = blank
      height = height + 40 + 26
    end

    parts[#parts + 1] = string.format([[
      <Button id="expandSelectPass_%s" onClick="on_expand_select_pass_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#C61715" textColor="#FFFFFF">Pass</Button>
    ]], color, color)
    height = height + 40
  else
    parts[#parts + 1] =
      [[<Text fontSize="18" color="#FFFFFF">Place the larger enclosure over the old one.</Text>]]
    parts[#parts + 1] = blank
    height = height + 60 + 26

    if state.valid then
      parts[#parts + 1] = string.format([[
        <Button id="expandConfirm_%s" onClick="on_expand_confirm_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">Confirm</Button>
      ]], color, color)
      height = height + 40
    end
  end

  return string.format([[
    <Panel id="expandPanel_%s" visibility="%s" rectAlignment="MiddleRight" width="280" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="UpperCenter" childForceExpandHeight="false">
        %s
      </VerticalLayout>
    </Panel>
  ]], color, color, height, table.concat(parts, "\n"))
end

function clear_expand_highlights(player, state)
  for _, option in ipairs(state.options) do
    local tile = player.building_tiles[option.id]
    if tile ~= nil then
      tile.highlightOff()
      tile.interactable = false
    end
  end
end

function on_expand_select_pass_clicked(_, color, _)
  local state = expand_actions[color]
  if state == nil or state.phase ~= "select" then return end
  local player = state.player
  clear_expand_highlights(player, state)
  expand_actions[color] = nil
  clear_player_panel(color)
  render_claims_table(player)
end

function on_expand_select_confirm_clicked(_, color, _)
  local state = expand_actions[color]
  if state == nil or state.phase ~= "select" or state.chosen == nil then return end
  local player = state.player

  local option = nil
  for _, candidate in ipairs(state.options) do
    if candidate.id == state.chosen then option = candidate end
  end

  clear_expand_highlights(player, state)
  state.phase, state.option, state.valid = "position", option, true

  player.building_tiles[option.id].destruct()
  player.building_tiles[option.id] = nil

  spawn_expand_tile(player, option)
end

function spawn_expand_tile(player, option)
  local state = expand_actions[player.color]
  building_clone_source("SIZE " .. (option.size + 1),
    function(obj)
      local board_pos = player.player_board.getPosition()
      local transform = tile_object_transform_for_cells(obj, board_pos, option.target)
      local rot = transform.rotation
      local occupied = player.map.tiles[option.id].tags.occupied
      local placed = obj.clone({
        position = { x = transform.position.x, y = transform.position.y + 2,
                     z = transform.position.z },
        rotation = { rot[1], rot[2], occupied and 180 or 0 },
      })
      placed.setLuaScript(cnsts.building_tile_script)
      placed = placed.reload()
      placed.interactable = true

      state.tile = placed
      render_expand_panel(player)
    end)
end

function refresh_expand_validity(player)
  local state = expand_actions[player.color]
  local board_pos = player.player_board.getPosition()
  local cells = tile_cells_from_object(state.tile, board_pos)

  state.valid = false
  if cells ~= nil and expand_extra_cell(state.option.cells, cells) ~= nil then
    local scratch = board_without_tile(player, state.option.id)
    local opts = { allowed = expand_terrain(scratch, player, state.option.cells) }
    state.valid = scratch:canPlace(cells, opts.allowed, opts)
      and placement_meets_requirements(scratch, cells, opts)
  end

  render_expand_panel(player)
end

function on_expand_confirm_clicked(_, color, _)
  local state = expand_actions[color]
  if state == nil or state.phase ~= "position" or not state.valid then return end

  local player, option = state.player, state.option
  local board_pos = player.player_board.getPosition()
  local cells = tile_cells_from_object(state.tile, board_pos)
  local extra = expand_extra_cell(option.cells, cells)
  if extra == nil then return end

  local occupied = player.map.tiles[option.id].tags.occupied
  local tag = "size_" .. (option.size + 1)

  printToAll(string.format("%s expands their size-%d enclosure with %s.",
    player.steam_name, option.size, state.source or "Conference on Australia"))

  player.map:remove(option.id)
  local id, reward = player.map:place(cells, { tag },
    expand_terrain(player.map, player, option.cells), {})

  player.map.tiles[id].tags.occupied = occupied
  player.building_tiles[id] = state.tile
  state.tile.interactable = false
  reassert_board_tile(player, id)
  refresh_map_income(player)

  expand_actions[color] = nil
  clear_player_panel(color)

  if occupied then
    update_appeal(player, 2, state.source or "Conference on Australia")
  end

  claim_placement_rewards(player, expand_gain(reward, extra),
    "expanding their enclosure")
end

function expand_gain(reward, cell)
  local gain = { tags = {}, count = 0, borderTags = {}, borderCount = 0,
                 cells = {}, specials = {}, clearedBoard = reward.clearedBoard }

  for _, entry in ipairs(reward.cells) do
    if entry.cell == cell then
      gain.count = gain.count + 1
      gain.tags[gain.count] = entry.tag
      gain.cells[gain.count] = entry
      if entry.border then
        gain.borderCount = gain.borderCount + 1
        gain.borderTags[gain.borderCount] = entry.tag
      end
    end
  end
  for _, special in ipairs(reward.specials) do
    if special.cell == cell then gain.specials[#gain.specials + 1] = special end
  end

  return gain
end


reconstruction_actions = {}

function reconstruction_options(player)
  local out = {}
  for id in pairs(player.map.tiles) do out[#out + 1] = id end
  table.sort(out)
  return out
end

function reconstruction(player, source)
  retire_active_claim()

  local ids = reconstruction_options(player)
  reconstruction_actions[player.color] = {
    player = player, source = source, phase = "select",
    all = ids, selected = {}, order = {}, added = {}, valid = true,
  }
  for _, id in ipairs(ids) do
    player.building_tiles[id].interactable = true
  end

  render_reconstruction_highlights(player)
  render_reconstruction_panel(player)
end

function render_reconstruction_highlights(player)
  local state = reconstruction_actions[player.color]
  for _, id in ipairs(state.all) do
    local tile = player.building_tiles[id]
    if state.selected[id] then
      tile.highlightOn({ 0, 1, 0 })
    else
      tile.highlightOff()
    end
  end
end

function select_reconstruction_tile(player, state, id)
  if state.selected[id] then
    state.selected[id] = nil
    for i, chosen in ipairs(state.order) do
      if chosen == id then table.remove(state.order, i) break end
    end
  else
    if #state.order >= cnsts.reconstruction_max_tiles then
      broadcastToColor("You may only reposition "
        .. cnsts.reconstruction_max_tiles .. " buildings!", player.color, "Red")
      return
    end
    state.selected[id] = true
    state.order[#state.order + 1] = id
  end

  render_reconstruction_highlights(player)
  render_reconstruction_panel(player)
end

function render_reconstruction_panel(player)
  set_player_panel(player.color,
    reconstruction_panel_xml(player.color, reconstruction_actions[player.color]))
end

function reconstruction_panel_xml(color, state)
  local blank = [[<Text fontSize="18" color="#FFFFFF"></Text>]]
  local parts, height = {}, 16 + 12

  if state.phase == "select" then
    parts[#parts + 1] = string.format(
      [[<Text fontSize="18" color="#FFFFFF">Select up to %d buildings to reposition.</Text>]],
      cnsts.reconstruction_max_tiles)
    parts[#parts + 1] = blank
    height = height + 60 + 26

    if #state.order > 0 then
      parts[#parts + 1] = string.format([[
        <Button id="reconSelectConfirm_%s" onClick="on_reconstruction_select_confirm_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">Confirm</Button>
      ]], color, color)
      parts[#parts + 1] = blank
      height = height + 40 + 26
    end

    parts[#parts + 1] = string.format([[
      <Button id="reconSelectPass_%s" onClick="on_reconstruction_select_pass_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#C61715" textColor="#FFFFFF">Pass</Button>
    ]], color, color)
    height = height + 40
  else
    parts[#parts + 1] =
      [[<Text fontSize="18" color="#FFFFFF">Confirm the new positions of these buildings.</Text>]]
    parts[#parts + 1] = blank
    height = height + 60 + 26

    for _, kind in ipairs({ "Kiosk", "Pavilion" }) do
      local on = state.added[string.lower(kind)] ~= nil
      parts[#parts + 1] = string.format([[
        <Button id="reconAdd%s_%s" onClick="on_reconstruction_toggle_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="%s" textColor="#FFFFFF">Add a %s</Button>
      ]], kind, color, color .. "|" .. string.lower(kind),
          on and "#888888" or "#3FA34D", kind)
      height = height + 40
    end

    parts[#parts + 1] = blank
    height = height + 26

    if state.valid then
      parts[#parts + 1] = string.format([[
        <Button id="reconConfirm_%s" onClick="on_reconstruction_confirm_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">Confirm</Button>
      ]], color, color)
      height = height + 40
    end

    parts[#parts + 1] = string.format([[
      <Button id="reconPass_%s" onClick="on_reconstruction_pass_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#C61715" textColor="#FFFFFF">Pass</Button>
    ]], color, color)
    height = height + 40
  end

  return string.format([[
    <Panel id="reconstructionPanel_%s" visibility="%s" rectAlignment="MiddleRight" width="280" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="UpperCenter" childForceExpandHeight="false">
        %s
      </VerticalLayout>
    </Panel>
  ]], color, color, height, table.concat(parts, "\n"))
end

function on_reconstruction_select_confirm_clicked(_, color, _)
  local state = reconstruction_actions[color]
  if state == nil or state.phase ~= "select" then return end
  for _, id in ipairs(state.all) do
    if not state.selected[id] then
      state.player.building_tiles[id].interactable = false
    end
  end
  start_reconstruction_positioning(state.player)
end

function on_reconstruction_select_pass_clicked(_, color, _)
  local state = reconstruction_actions[color]
  if state == nil or state.phase ~= "select" then return end
  for _, id in ipairs(state.all) do
    state.player.building_tiles[id].interactable = false
  end
  state.selected, state.order = {}, {}
  render_reconstruction_highlights(state.player)
  start_reconstruction_positioning(state.player)
end

function start_reconstruction_positioning(player)
  local state = reconstruction_actions[player.color]
  state.phase = "position"
  state.valid = true
  render_reconstruction_panel(player)
end

function reconstruction_owns_tile(player, state, guid)
  for _, id in ipairs(state.order) do
    if player.building_tiles[id].getGUID() == guid then return true end
  end
  for _, obj in pairs(state.added) do
    if obj.getGUID() == guid then return true end
  end
  return false
end

function reconstruction_moves(player, state)
  local board_pos = player.player_board.getPosition()
  local moves = {}

  for _, id in ipairs(state.order) do
    local tile = player.map.tiles[id]
    local cells = tile_cells_from_object(player.building_tiles[id], board_pos)
    if cells == nil then return nil end
    moves[#moves + 1] =
      { id = id, cells = cells, type = tile.tags.type, rules = tile.tags.placement }
  end

  for kind, obj in pairs(state.added) do
    local cells = tile_cells_from_object(obj, board_pos)
    if cells == nil then return nil end
    moves[#moves + 1] = { cells = cells, type = kind }
  end

  return moves
end

function refresh_reconstruction_validity(player)
  local state = reconstruction_actions[player.color]
  local moves = reconstruction_moves(player, state)
  state.valid = moves ~= nil and reposition_is_valid(player, moves)
  render_reconstruction_panel(player)
end

function on_reconstruction_toggle_clicked(_, value, _)
  local color, kind = value:match("^(%a+)|(%a+)$")
  local state = reconstruction_actions[color]
  if state == nil or state.phase ~= "position" then return end
  local player = state.player

  if state.added[kind] ~= nil then
    state.added[kind].destruct()
    state.added[kind] = nil
    refresh_reconstruction_validity(player)
    return
  end

  building_clone_source(string.upper(kind),
    function(obj)
      local board_pos = player.player_board.getPosition()
      local transform = tile_object_transform_for_cells(obj, board_pos,
        { cnsts.reconstruction_drop_cell })
      local placed = obj.clone({
        position = { x = transform.position.x, y = transform.position.y + 2,
                     z = transform.position.z },
        rotation = transform.rotation,
      })
      placed.setLuaScript(cnsts.building_tile_script)
      placed = placed.reload()
      placed.interactable = true

      state.added[kind] = placed
      refresh_reconstruction_validity(player)
    end)
end

function clear_reconstruction(player, restore)
  local state = reconstruction_actions[player.color]

  for _, id in ipairs(state.all) do
    local tile = player.building_tiles[id]
    if tile ~= nil then
      tile.highlightOff()
      tile.interactable = false
    end
  end
  if restore then
    for _, id in ipairs(state.order) do reassert_board_tile(player, id) end
    for _, obj in pairs(state.added) do obj.destruct() end
  end

  reconstruction_actions[player.color] = nil
  clear_player_panel(player.color)
end

function on_reconstruction_pass_clicked(_, color, _)
  local state = reconstruction_actions[color]
  if state == nil or state.phase ~= "position" then return end
  local player = state.player
  printToAll(player.steam_name .. " repositions nothing.")
  clear_reconstruction(player, true)
  render_claims_table(player)
end

function on_reconstruction_confirm_clicked(_, color, _)
  local state = reconstruction_actions[color]
  if state == nil or state.phase ~= "position" or not state.valid then return end

  local player = state.player
  local moves = reconstruction_moves(player, state)
  if moves == nil or not reposition_is_valid(player, moves) then return end

  local delta = {}
  local function tally(specials, by)
    for _, special in ipairs(specials) do
      delta[special.tag] = (delta[special.tag] or 0) + by
    end
  end

  local objects = {}
  for _, move in ipairs(moves) do
    if move.id ~= nil then
      objects[move] = player.building_tiles[move.id]
      player.building_tiles[move.id] = nil
      local _, restored = player.map:remove(move.id)
      tally(restored.specials, -1)
    end
  end

  local remaining = {}
  for i, move in ipairs(moves) do remaining[i] = move end
  local board_pos = player.player_board.getPosition()

  local progress = true
  while progress and #remaining > 0 do
    progress = false
    for i = #remaining, 1, -1 do
      local move = remaining[i]
      local opts = reposition_opts(player, move.rules)
      if player.map:canPlace(move.cells, opts.allowed, opts)
         and placement_meets_requirements(player.map, move.cells, opts) then
        local id, reward = player.map:place(move.cells, { move.type }, opts.allowed, opts)
        tally(reward.specials, 1)
        player.map.tiles[id].tags.placement = move.rules
        move.placed_id = id

        local obj = objects[move] or state.added[move.type]
        player.building_tiles[id] = obj
        obj.interactable = false
        obj.highlightOff()
        reassert_board_tile(player, id)

        table.remove(remaining, i)
        progress = true
      end
    end
  end

  printToAll(string.format("%s repositions %d building(s).",
    player.steam_name, #moves))

  for _, p in ipairs(players) do refresh_map_income(p) end

  local groups = {}
  for _, move in ipairs(moves) do
    if move.id == nil then
      credit_building_added(player, move.type, move.placed_id)
      local gardener = landscape_gardener_group(player, move.type)
      if gardener ~= nil then groups[#groups + 1] = gardener end
    end
  end

  for tag, n in pairs(delta) do
    for _ = 1, math.abs(n) do
      local granted = process_effects(player, tag, n < 0 or nil)
      if granted ~= nil then
        groups[#groups + 1] =
          { rewards = { granted }, source = label_from_key(tag) }
      end
    end
  end

  state.added = {}
  clear_reconstruction(player, false)

  if #groups > 0 then
    create_claims_from_reward_groups(player, groups, false)
  else
    render_claims_table(player)
  end
end


cut_down_actions = {}

function cut_down_options(player)
  local out = {}
  for id, tile in pairs(player.map.tiles) do
    local size = tile.tags.type and tile.tags.type:match("^size_(%d)$")
    if size ~= nil and not tile.tags.occupied then
      out[#out + 1] = { id = id, size = tonumber(size), cells = #tile.cells }
    end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

function cut_down_refund(option)
  return option.cells * 2
end

function cut_down(player, source)
  local options = cut_down_options(player)
  if #options == 0 then
    broadcastToColor("You have no empty enclosures to cut down!", player.color, "Red")
    render_claims_table(player)
    return
  end

  cut_down_actions[player.color] = {
    player = player, source = source, options = options,
    chosen = nil, highlighted = {},
  }
  for _, option in ipairs(options) do
    player.building_tiles[option.id].interactable = true
  end

  render_cut_down_highlights(player)
  render_cut_down_panel(player)
end

function render_cut_down_highlights(player)
  local state = cut_down_actions[player.color]
  state.highlighted = {}
  for _, option in ipairs(state.options) do
    local tile = player.building_tiles[option.id]
    tile.highlightOn(state.chosen == option.id and { 0, 1, 0 } or { 1, 0, 0 })
    state.highlighted[#state.highlighted + 1] = option.id
  end
end

function clear_cut_down_selection(player)
  local state = cut_down_actions[player.color]
  for _, id in ipairs(state.highlighted) do
    player.building_tiles[id].highlightOff()
  end
  for _, option in ipairs(state.options) do
    player.building_tiles[option.id].interactable = false
  end
  cut_down_actions[player.color] = nil
end

function cut_down_panel_xml(color, state)
  local parts = {
    [[<Text fontSize="18" color="#FFFFFF">Pick up an empty enclosure to cut it down.</Text>]]
  }
  local height = 16 + 50 + 12

  if state.chosen ~= nil then
    local refund = 0
    for _, option in ipairs(state.options) do
      if option.id == state.chosen then refund = cut_down_refund(option) end
    end
    parts[#parts + 1] = string.format([[
      <Text fontSize="18" color="#FFFFFF"></Text>
      <Button id="cutDownConfirmButton_%s" onClick="on_cut_down_confirm_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#4A90D9" textColor="#FFFFFF">Cut it down for %d Money</Button>
    ]], color, color, refund)
    height = height + 26 + 40
  end

  parts[#parts + 1] = string.format([[
    <Text fontSize="18" color="#FFFFFF"></Text>
    <Button id="cutDownCancelButton_%s" onClick="on_cut_down_cancel_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#C61715" textColor="#FFFFFF">Cancel</Button>
  ]], color, color)
  height = height + 26 + 40

  return string.format([[
    <Panel id="cutDownPanel_%s" visibility="%s" rectAlignment="MiddleRight" width="280" height="%d" color="#222222DD">
      <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="UpperCenter" childForceExpandHeight="false">
        %s
      </VerticalLayout>
    </Panel>
  ]], color, color, height, table.concat(parts, "\n"))
end

function render_cut_down_panel(player)
  set_player_panel(player.color,
    cut_down_panel_xml(player.color, cut_down_actions[player.color]))
end

function select_cut_down_tile(player, state, id)
  for _, option in ipairs(state.options) do
    if option.id == id then
      state.chosen = id
      render_cut_down_highlights(player)
      render_cut_down_panel(player)
      return
    end
  end
end

function on_cut_down_cancel_clicked(_, color, _)
  local player = cut_down_actions[color].player
  clear_cut_down_selection(player)
  clear_player_panel(color)
  render_claims_table(player)
end

function on_cut_down_confirm_clicked(_, color, _)
  local state = cut_down_actions[color]
  if state == nil or state.chosen == nil then return end

  local player, id, source = state.player, state.chosen, state.source
  local refund, size = 0, 0
  for _, option in ipairs(state.options) do
    if option.id == id then
      refund, size = cut_down_refund(option), option.size
    end
  end

  clear_cut_down_selection(player)
  clear_player_panel(color)

  local tile = player.building_tiles[id]
  player.building_tiles[id] = nil

  local _, restored = player.map:remove(id)
  tile.destruct()

  for _, special in ipairs(restored.specials) do
    process_effects(player, special.tag, true)
  end

  refresh_map_income(player)

  update_money(player, refund, string.format("cutting down a size-%d enclosure with %s", size, source))

  retire_active_claim()
  render_claims_table(player)
end

function find_player_by_color(color)
  for _, p in ipairs(players) do
    if p.color == color then return p end
  end
  return nil
end

function show_building_placement_panel(player, can_confirm)
  local color = player.color
  local confirm_button = ""
  if can_confirm then
    confirm_button = string.format([[
        <Button id="buildingPlacementConfirmButton_%s" onClick="on_building_placement_confirm_clicked(%s)" fontSize="16" width="240" height="34" minHeight="34" color="#3FA34D" textColor="#FFFFFF">Confirm</Button>
    ]], color, color)
  end

  local go_back_label = "Go back to\nbuilding selection"

  local xml = string.format([[
    <Panel id="buildingPlacementPanel_%s" visibility="%s" rectAlignment="MiddleRight" width="280" height="%d" color="#222222DD">
      <VerticalLayout spacing="8" padding="8 8 8 8" childAlignment="MiddleCenter" childForceExpandHeight="false">
        <Text fontSize="18" color="#FFFFFF">Place the building on your map.</Text>
        %s
        <Button id="buildingPlacementGoBackButton_%s" onClick="on_building_placement_go_back(%s)" fontSize="16" width="240" height="52" minHeight="52" color="#C61715" textColor="#FFFFFF">%s</Button>
      </VerticalLayout>
    </Panel>
  ]], color, color, can_confirm and 162 or 120, confirm_button, color, color, go_back_label)
  set_player_panel(color, xml)
end

function find_board_tile(guid)
  for _, p in ipairs(players) do
    for id, obj in pairs(p.building_tiles) do
      if obj ~= nil and obj.getGUID() == guid then return p, id end
    end
  end
  return nil
end

function tile_face_rotation(obj, face_down)
  return { 0, obj.getRotation().y, face_down and 180 or 0 }
end

function set_tile_face_now(obj, face_down)
  if obj == nil then return end
  obj.setRotation(tile_face_rotation(obj, face_down))
end

function set_tile_face(obj, face_down)
  if obj == nil then return end

  local was_locked = obj.locked
  obj.setRotationSmooth(tile_face_rotation(obj, face_down), false, false)

  if was_locked then
    Wait.frames(function()
      Wait.condition(function() obj.locked = true end,
                     function() return not obj.isSmoothMoving() end)
    end, 2)
  end
end

function reassert_board_tiles()
  for _, player in ipairs(players) do
    for id in pairs(player.map.tiles) do
      reassert_board_tile(player, id)
    end
  end
end

function reassert_board_tile(player, id)
  local obj = player.building_tiles[id]
  local tile = player.map.tiles[id]

  local transform =
    tile_object_transform_for_cells(obj, player.player_board.getPosition(), tile.cells)
  assert(transform ~= nil,
    "reassert_board_tile: no grid-aligned transform for tile " .. tostring(id))

  local rot = transform.rotation
  obj.setPosition(transform.position)
  obj.setRotation({ rot[1], rot[2], tile.tags.occupied and 180 or 0 })
end

function on_building_tile_picked_up(params)
  local tile = params.tile
  local guid = tile.getGUID()

  for _, p in ipairs(players) do
    local placement = tile_placements[p.color]
    if placement ~= nil and placement.tile_guid == guid then
      placement.can_confirm = false
      render_tile_placement_panel(p)
      return
    end
    if p.pending_building ~= nil and p.pending_building.tile_guid == guid then
      show_building_placement_panel(p, false)
      return
    end
  end

  local owner, id = find_board_tile(guid)
  if owner == nil then return end

  local recon = reconstruction_actions[owner.color]
  if recon ~= nil and recon.phase == "position" and recon.selected[id] then
    return
  end

  tile.drop()
  reassert_board_tile(owner, id)

  local state = animal_actions[owner.color]
  if state ~= nil and state.phase == "enclosure" and params.color == owner.color then
    select_animal_enclosure(owner, state, id)
  end

  local release = enclosure_vacates[owner.color]
  if release ~= nil and release.phase == "standard" and params.color == owner.color then
    select_enclosure_to_vacate(owner, release, id)
  end

  local cut = cut_down_actions[owner.color]
  if cut ~= nil and params.color == owner.color then
    select_cut_down_tile(owner, cut, id)
  end

  local recon = reconstruction_actions[owner.color]
  if recon ~= nil and recon.phase == "select" and params.color == owner.color then
    select_reconstruction_tile(owner, recon, id)
  end

  local expand = expand_actions[owner.color]
  if expand ~= nil and expand.phase == "select" and params.color == owner.color then
    select_expand_target(owner, expand, id)
  end
end

function building_placement_rules(opts)
  if opts.min_border_cells == nil and opts.ignore_touch_rule == nil
     and opts.water_cells_only == nil and opts.terrain_requirements == nil then
    return nil
  end
  return {
    min_border_cells = opts.min_border_cells,
    ignore_touch_rule = opts.ignore_touch_rule,
    water_cells_only = opts.water_cells_only,
    terrain_requirements = opts.terrain_requirements,
  }
end

function reposition_opts(player, rules)
  rules = rules or {}
  local opts = { allowed = buildable_terrain(player) }
  opts.allowed.cover = 0

  opts.min_border_cells = rules.min_border_cells
  opts.ignore_touch_rule = rules.ignore_touch_rule
  opts.water_cells_only = rules.water_cells_only
  opts.terrain_requirements = rules.terrain_requirements
  if rules.water_cells_only then opts.allowed.water = true end

  return opts
end

function placement_meets_requirements(map, cells, opts)
  if map:countBorderCells(cells) < (opts.min_border_cells or 0) then
    return false
  end
  if opts.water_cells_only and not map:cellsAllTerrain(cells, "water") then
    return false
  end
  for _, req in ipairs(opts.terrain_requirements or {}) do
    if map:countTerrainFor(cells, req.tag) < req.min then
      return false
    end
  end
  if opts.extra_check and not opts.extra_check(cells) then
    return false
  end
  return true
end

function reposition_is_valid(player, moves)
  local scratch = HexBoard.Board.new(cnsts.map_data[player.map_key].cells)
  for id in pairs(scratch.tiles) do scratch:remove(id) end

  local ANY = { upgd = true, rock = true, water = true, cover = 0 }
  local moving = {}
  for _, move in ipairs(moves) do
    if move.id ~= nil then moving[move.id] = true end
  end
  for id, tile in pairs(player.map.tiles) do
    if not moving[id] then
      scratch:placeUnchecked(tile.cells, { tile.tags.type }, ANY)
    end
  end

  local remaining = {}
  for i, move in ipairs(moves) do remaining[i] = move end

  local progress = true
  while progress and #remaining > 0 do
    progress = false
    for i = #remaining, 1, -1 do
      local move = remaining[i]
      local opts = reposition_opts(player, move.rules)
      if scratch:canPlace(move.cells, opts.allowed, opts)
         and placement_meets_requirements(scratch, move.cells, opts) then
        scratch:placeUnchecked(move.cells, { move.type }, opts.allowed, opts)
        table.remove(remaining, i)
        progress = true
      end
    end
  end

  return #remaining == 0
end

function build_placement_cost(player, cells, pending)
  local covers = player.map:coverBudgetUsed(cells, pending.opts.allowed)
  local cost = pending.price or (#cells * 2)
  if covers > 0 then
    cost = cost + (build_upgraded(player) and -2 or 2)
  end
  return cost, covers
end

function archaeologist_pick_count(reward)
  local seen, n = {}, 0
  for _, entry in ipairs(reward.cells) do
    if entry.border and not seen[entry.cell] then
      seen[entry.cell] = true
      n = n + 1
    end
  end
  return n
end

function archaeologist_picks(player, reward)
  local claims = {}
  if not player.archaeologist then return claims end

  for _ = 1, archaeologist_pick_count(reward) do
    claims[#claims + 1] = {
      button_text = "Archaeologist's Pick",
      optional = false,
      async = true,
      function_call = function() offer_archaeologist_pick(player) end
    }
  end
  return claims
end

function offer_archaeologist_pick(player)
  local rewards = {}
  for _, entry in ipairs(player.map:unclaimedRewards()) do
    rewards[#rewards + 1] = entry.tag
  end

  if #rewards == 0 then
    broadcastToColor("No uncovered rewards left on your map!", player.color, "Red")
    render_claims_table(player)
    return
  end

  create_claims_from_rewards(player, rewards, "Archaeologist", true)
end

function claim_placement_rewards(player, reward, source, tag, id)
  if reward.clearedBoard and not player.map_drawing_board then
    update_appeal(player, cnsts.map_filled_appeal, "filling their map")
  end

  local groups, picks = {}, {}
  if not player.reconstruction then
    groups[1] = { rewards = reward.tags, source = source }
    picks = archaeologist_picks(player, reward)
  end

  for _, special in ipairs(reward.specials) do
    local granted = process_effects(player, special.tag)
    if granted ~= nil then
      groups[#groups + 1] =
        { rewards = { granted }, source = label_from_key(special.tag) }
    end
  end

  local icons = cnsts.building_icons[tag]
  if icons ~= nil then
    append_icon_groups(groups, player, icons)
  end

  local gardener = landscape_gardener_group(player, tag)
  if gardener ~= nil then groups[#groups + 1] = gardener end

  local move = animal_move_claim(player, tag, id)
  if move ~= nil then picks[#picks + 1] = move end

  create_claims_from_reward_groups(player, groups, false, picks)
end

function landscape_gardener_group(player, tag)
  if tag ~= "pavilion" or not player.landscape_gardener then return nil end
  player.landscape_gardener = false
  return { rewards = { "1 x_token" }, source = cnsts.landscape_gardener_name }
end

function rearm_effect(player, attr)
  if player[attr] == false then player[attr] = true end
end

function credit_building_added(player, tag, id)
  if tag == "pavilion" then
    update_appeal(player, 1)
  end

  local cells = id ~= nil and player.map:cellsOf(id) or nil
  if cells ~= nil then
    if player.geologist then
      local n = player.map:countPlacementCellsBesideTerrain(cells, "rock")
      if n > 0 then update_money(player, n, "Geologist") end
    end
    if player.hydrologist then
      local n = player.map:countPlacementCellsBesideTerrain(cells, "water")
      if n > 0 then update_money(player, n, "Hydrologist") end
    end
  end

  for _, p in ipairs(players) do
    refresh_map_income(p)
  end
end

function map_income(player)
  local map = player.map

  local total = map:kioskIncome() + map:sideEntranceIncome()
    + map:countCoveredAdjacentToSpecial("park restaurant")

  if (player.map_ice_cream_parlors or 0) >= 3 then
    total = total + #map:tilesWithTag("kiosk")
  end

  if player.franchise_business then
    for _, other in ipairs(players) do
      if other ~= player then
        total = total + #other.map:tilesWithTag("kiosk")
      end
    end
  end

  return total
end

function refresh_map_income(player)
  local total = map_income(player)
  local delta = total - (player.map_income or 0)
  if delta == 0 then return end

  player.map_income = total
  set_counter(player.income_counter,
    get_counter_value(player.income_counter) + delta, cnsts.counter_style.income)
end

function on_building_tile_settled(params)
  local tile = params.tile
  local guid = tile.getGUID()

  for _, p in ipairs(players) do
    local placement = tile_placements[p.color]
    if placement ~= nil and placement.tile_guid == guid then
      if placement.config.force_face_up and tile.is_face_down then
        local rot = tile.getRotation()
        tile.setRotation({ 0, rot.y, 0 })
      end
      refresh_placement_validity(p, tile)
      render_tile_placement_panel(p)
      return
    end
  end

  for _, p in ipairs(players) do
    local expand = expand_actions[p.color]
    if expand ~= nil and expand.phase == "position" and expand.tile ~= nil
       and expand.tile.getGUID() == guid then
      refresh_expand_validity(p)
      return
    end
  end

  for _, p in ipairs(players) do
    local recon = reconstruction_actions[p.color]
    if recon ~= nil and recon.phase == "position"
       and reconstruction_owns_tile(p, recon, guid) then
      refresh_reconstruction_validity(p)
      return
    end
  end

  local player = nil
  for _, p in ipairs(players) do
    if p.pending_building ~= nil and p.pending_building.tile_guid == guid then
      player = p
      break
    end
  end
  if player == nil then return end

  local board_pos = player.player_board.getPosition()
  local cells = tile_cells_from_object(tile, board_pos)
  local pending = player.pending_building
  local can_place = cells ~= nil
    and player.map:canPlace(cells, pending.opts.allowed, pending.opts)
    and placement_meets_requirements(player.map, cells, pending.opts)
    and build_placement_cost(player, cells, pending) <= get_counter_value(player.money_counter)

  show_building_placement_panel(player, can_place)
end

function on_building_placement_confirm_clicked(_, color, _)
  local player = find_player_by_color(color)
  if player.pending_building == nil then return end

  local tile = getObjectFromGUID(player.pending_building.tile_guid)
  local board_pos = player.player_board.getPosition()
  local cells = tile_cells_from_object(tile, board_pos)

  local pending = player.pending_building
  if cells == nil or not placement_meets_requirements(player.map, cells, pending.opts) then
    return
  end

  local cost, covers = build_placement_cost(player, cells, pending)
  if cost > get_counter_value(player.money_counter) then return end

  local raw_name = tile.getName()
  local tag = string.lower(raw_name):gsub(" ", "_")
  local id, reward = player.map:place(cells, { tag }, pending.opts.allowed, pending.opts)
  if id == nil then return end

  player.map.tiles[id].tags.placement = building_placement_rules(pending.opts)

  if covers > 0 then player.build_4_effect = nil end

  local building_name = raw_name:gsub("(%a)([%w']*)", function(first, rest) return first:upper() .. rest:lower() end)
  if raw_name:match("^SIZE %d+$") then
    building_name = building_name .. " Enclosure"
  end

  update_money(player, -cost, pending.money_source or ("a " .. building_name))
  credit_building_added(player, tag, id)

  player.building_tiles[id] = tile
  tile.interactable = false

  local transform = tile_object_transform_for_cells(tile, board_pos, cells)
  if transform ~= nil then
    tile.setPosition({transform.position.x, transform.position.y, transform.position.z})
    tile.setRotation(transform.rotation)
  else
    set_tile_face(tile, false)
  end

  clear_player_panel(color)
  player.pending_building = nil

  retire_claim_record(pending.claim)

  local state = build_actions[color]
  if not pending.bonus and state ~= nil then
    state.remaining = state.remaining - #cells
    state.first = false
    state.built[pending.option.search_name] = true
    if state.upgd and state.remaining > 0 then
      offer_another_build(player)
    end
  end

  if pending.bonus ~= nil and engineer_build(player, pending.bonus) ~= nil then
    spend_engineer(player)
  elseif player.engineer and state ~= nil then
    grant_engineer_build(player, building_name, pending.option.search_name, cells)
  end

  claim_placement_rewards(player, reward, "placement bonus", tag, id)
end

function on_building_placement_go_back(_, color, _)
  local player = find_player_by_color(color)
  if player.pending_building == nil then return end

  local pending = player.pending_building
  player.pending_building = nil

  local tile = getObjectFromGUID(pending.tile_guid)
  if tile ~= nil then tile.destruct() end

  clear_player_panel(color)

  if pending.bonus then
    player.persistent_rewards[pending.bonus] = true
  else
    retire_claim_record(pending.claim)
    offer_build_choices(player)
  end
  render_claims_table(player)
end

function spawn_starting_tile(tag, tile, board_pos, building_tiles)
  building_clone_source(string.upper((tag:gsub("_", " "))),
    function(obj)
      local transform = tile_object_transform_for_cells(obj, board_pos, tile.cells)
      if transform ~= nil then
        local placed = obj.clone({ position = transform.position, rotation = transform.rotation, snap_to_grid = true })
        placed.setLuaScript(cnsts.building_tile_script)
        placed = placed.reload()
        placed.interactable = false
        building_tiles[tile.id] = placed
      end
    end)
end

function cell_local_position(cell)
  local col, v = HexBoard.coordOf(cell)
  local o = cnsts.cell_offsets
  return { x = o.x0 + col * o.cx, y = o.y, z = o.z0 + v * o.vz }
end

function local_position_to_cell(offset)
  local o = cnsts.cell_offsets
  local col = math.floor((offset.x - o.x0) / o.cx + 0.5)
  local v_raw = (offset.z - o.z0) / o.vz
  local v = math.floor(v_raw + 0.5)
  if (col + v) % 2 ~= 1 then
    local v_down, v_up = v - 1, v + 1
    if math.abs(v_raw - v_down) <= math.abs(v_raw - v_up) then
      v = v_down
    else
      v = v_up
    end
  end
  return HexBoard.cellAt(col, v)
end

function cell_world_position(board_pos, cell)
  return board_pos + cell_local_position(cell)
end

function world_position_to_cell(board_pos, world_pos)
  return local_position_to_cell(Vector(world_pos) - board_pos)
end

function board_relative_world_position(board_pos, name)
  return board_pos + cnsts.board_relative_positions[name]
end

function card_relative_world_position(obj, name)
  return obj.getPosition() + cnsts.card_relative_positions[name]
end

function rotate_local_offset(lx, lz, y_rotation)
  local rad = math.rad(y_rotation)
  local cos_r, sin_r = math.cos(rad), math.sin(rad)
  return lx * cos_r + lz * sin_r, -lx * sin_r + lz * cos_r
end

function building_shape_snap_points(obj)
  local points = {}
  for _, sp in ipairs(obj.getSnapPoints()) do
    if sp.tags then
      for _, tag in ipairs(sp.tags) do
        if tag == "building_shape" then
          points[#points + 1] = sp
          break
        end
      end
    end
  end
  return points
end

function tile_cells_from_object(obj, board_pos)
  local pos = obj.getPosition()
  local snap_points = building_shape_snap_points(obj)

  if #snap_points == 0 then
    local cell = world_position_to_cell(board_pos, pos)
    if cell == nil then return nil end
    return { cell }
  end

  local rot = obj.getRotation()
  local scale = obj.getScale()
  local cells = {}
  for _, sp in ipairs(snap_points) do
    local wx, wz = rotate_local_offset(sp.position.x * scale.x, sp.position.z * scale.z, rot.y)
    local cell = world_position_to_cell(board_pos, { x = pos.x + wx, y = pos.y, z = pos.z + wz })
    if cell == nil then return nil end
    cells[#cells + 1] = cell
  end
  return cells
end

function tile_shape_from_object(obj)
  local snap_points = building_shape_snap_points(obj)
  if #snap_points == 0 then
    return { 1 }
  end

  local rot = obj.getRotation()
  local scale = obj.getScale()
  local cells = {}
  for _, sp in ipairs(snap_points) do
    local wx, wz = rotate_local_offset(sp.position.x * scale.x, sp.position.z * scale.z, rot.y)
    cells[#cells + 1] = local_position_to_cell({ x = wx, y = 0, z = wz })
  end
  return cells
end

function tile_object_transform_for_cells(obj, board_pos, cells)
  local snap_points = building_shape_snap_points(obj)

  if #snap_points == 0 then
    return { position = cell_world_position(board_pos, cells[1]), rotation = { 0, 180, 0 } }
  end

  local scale = obj.getScale()

  local locals = {}
  for i, sp in ipairs(snap_points) do
    locals[i] = { x = sp.position.x * scale.x, z = sp.position.z * scale.z }
  end
  local snap_centroid = { x = 0, z = 0 }
  for _, p in ipairs(locals) do
    snap_centroid.x = snap_centroid.x + p.x
    snap_centroid.z = snap_centroid.z + p.z
  end
  snap_centroid.x = snap_centroid.x / #locals
  snap_centroid.z = snap_centroid.z / #locals

  local ref_vec, ref_dist = nil, -1
  for _, p in ipairs(locals) do
    local dx, dz = p.x - snap_centroid.x, p.z - snap_centroid.z
    local dist = dx * dx + dz * dz
    if dist > ref_dist then ref_dist, ref_vec = dist, { x = dx, z = dz } end
  end
  local snap_angle = math.deg(math.atan2(ref_vec.z, ref_vec.x))

  local targets = {}
  for i, c in ipairs(cells) do targets[i] = cell_local_position(c) end
  local target_centroid = { x = 0, y = targets[1].y, z = 0 }
  for _, p in ipairs(targets) do
    target_centroid.x = target_centroid.x + p.x
    target_centroid.z = target_centroid.z + p.z
  end
  target_centroid.x = target_centroid.x / #targets
  target_centroid.z = target_centroid.z / #targets

  local target_cells = {}
  for _, c in ipairs(cells) do target_cells[c] = true end

  local best, best_error = nil, nil
  for _, tp in ipairs(targets) do
    local tvx, tvz = tp.x - target_centroid.x, tp.z - target_centroid.z
    if tvx * tvx + tvz * tvz > 1e-6 then
      local target_angle = math.deg(math.atan2(tvz, tvx))
      local rotation_y = (snap_angle - target_angle) % 360

      local wx, wz = rotate_local_offset(snap_centroid.x, snap_centroid.z, rotation_y)
      local pivot = {
        x = board_pos.x + target_centroid.x - wx,
        y = board_pos.y + target_centroid.y,
        z = board_pos.z + target_centroid.z - wz
      }

      local resulting, matched, error_sq = {}, true, 0
      for _, sp in ipairs(snap_points) do
        local wx2, wz2 = rotate_local_offset(sp.position.x * scale.x, sp.position.z * scale.z, rotation_y)
        local world_x, world_z = pivot.x + wx2, pivot.z + wz2
        local cell = world_position_to_cell(board_pos, { x = world_x, y = pivot.y, z = world_z })
        if not target_cells[cell] then
          matched = false
          break
        end
        local exact = cell_local_position(cell)
        local dx, dz = world_x - (board_pos.x + exact.x), world_z - (board_pos.z + exact.z)
        error_sq = error_sq + dx * dx + dz * dz
        resulting[cell] = true
      end

      if matched then
        local count = 0
        for _ in pairs(resulting) do count = count + 1 end
        if count == #cells and (best == nil or error_sq < best_error) then
          best, best_error = { position = pivot, rotation = { 0, rotation_y, 0 } }, error_sq
        end
      end
    end
  end

  return best
end

map_setup_checked = {}

function map_setup_label(key)
  return "Map " .. string.sub(key, 5)
end

function map_setup_pool()
  local pool = {}
  for _, row in ipairs(cnsts.map_setup_rows) do
    for _, key in ipairs(row.keys) do
      if map_setup_checked[key] then pool[#pool + 1] = key end
    end
  end
  return pool
end

function classic_match_available()
  return #map_setup_pool() >= #players * 2
end

function show_map_setup_panel()
  map_setup_checked = {}
  for _, row in ipairs(cnsts.map_setup_rows) do
    for _, key in ipairs(row.keys) do
      map_setup_checked[key] = row.default
    end
  end
  UI.setXml(map_setup_panel_xml())
end

function map_setup_panel_xml()
  local rows = ""
  for _, row in ipairs(cnsts.map_setup_rows) do
    local boxes = ""
    for _, key in ipairs(row.keys) do
      boxes = boxes .. string.format(
        '<Toggle id="mapCheck_%s" isOn="%s" onValueChanged="on_map_check_changed" fontSize="15" textColor="#FFFFFF">%s</Toggle>',
        key, tostring(map_setup_checked[key] == true), map_setup_label(key))
    end
    rows = rows .. string.format([[
        <HorizontalLayout spacing="4" minHeight="30" preferredHeight="30" childAlignment="MiddleCenter">%s</HorizontalLayout>
]], boxes)
  end

  local mirror_on = #map_setup_pool() > 0
  local classic_on = classic_match_available()

  return string.format([[
    <Panel id="mapSetupPanel" rectAlignment="MiddleCenter" width="720" height="570" color="#222222FF">
      <VerticalLayout spacing="6" padding="16 16 16 16" childAlignment="MiddleCenter" childForceExpandHeight="false">
        <Text fontSize="26" color="#FFFFFF" minHeight="34">Map Setup</Text>
        <Text fontSize="18" color="#FFFFFF" minHeight="18"></Text>
        <Panel color="#FFFFFF" minHeight="2" preferredHeight="2"></Panel>
        <Text fontSize="18" color="#FFFFFF" minHeight="18"></Text>
%s        <HorizontalLayout spacing="10" minHeight="84" preferredHeight="84" childForceExpandWidth="false" childAlignment="MiddleLeft">
          <Button id="mapMirrorButton" onClick="on_map_mirror_clicked" interactable="%s" fontSize="16" minHeight="44" width="200" preferredWidth="200" flexibleWidth="0" color="%s" textColor="#FFFFFF">Start Mirror Match</Button>
          <Text id="mapMirrorText" fontSize="18" color="#CCCCCC" alignment="MiddleLeft" width="458" preferredWidth="458" flexibleWidth="0">Starts a game with all players using the same map randomly chosen from the pool as selected by the checkboxes above.</Text>
        </HorizontalLayout>
        <HorizontalLayout spacing="10" minHeight="84" preferredHeight="84" childForceExpandWidth="false" childAlignment="MiddleLeft">
          <Button id="mapClassicButton" onClick="on_map_classic_clicked" interactable="%s" fontSize="16" minHeight="44" width="200" preferredWidth="200" flexibleWidth="0" color="%s" textColor="#FFFFFF">Start Classic Match</Button>
          <Text id="mapClassicText" fontSize="18" color="#CCCCCC" alignment="MiddleLeft" width="458" preferredWidth="458" flexibleWidth="0">Each player will be given 2 different maps to pick from, out of the pool as selected by the checkboxes above.</Text>
        </HorizontalLayout>
        <Text fontSize="18" color="#FFFFFF" minHeight="18"></Text>
        <Panel color="#FFFFFF" minHeight="2" preferredHeight="2"></Panel>
        <HorizontalLayout spacing="10" minHeight="112" preferredHeight="112" childForceExpandWidth="false" childAlignment="MiddleLeft">
          <Button id="mapCustomButton" onClick="on_map_custom_clicked" fontSize="16" minHeight="44" width="200" preferredWidth="200" flexibleWidth="0" color="#4A90D9" textColor="#FFFFFF">Start Custom Setup</Button>
          <Text id="mapCustomText" fontSize="18" color="#CCCCCC" alignment="MiddleLeft" width="458" preferredWidth="458" flexibleWidth="0">Use the map tiles in the 'MAPS' container to begin a custom map setup. Map tiles can be duplicated as necessary. You will need to choose this option if you want to use Map 0 or Map A.</Text>
        </HorizontalLayout>
      </VerticalLayout>
    </Panel>
  ]], rows,
  tostring(mirror_on), mirror_on and "#4A90D9" or "#555555",
  tostring(classic_on), classic_on and "#4A90D9" or "#555555")
end

function on_map_check_changed(_, value, id)
  local key = string.match(tostring(id), "^mapCheck_(.+)$")
  if key == nil then return end
  local checked = (string.lower(tostring(value)) == "true")
  map_setup_checked[key] = checked

  set_ui_attributes("mapCheck_" .. key, { isOn = tostring(checked) })

  for _, option in ipairs({
    { id = "mapMirrorButton", on = #map_setup_pool() > 0 },
    { id = "mapClassicButton", on = classic_match_available() }
  }) do
    set_ui_attributes(option.id, {
      interactable = tostring(option.on),
      color = option.on and "#4A90D9" or "#555555"
    })
  end
end

function destruct_map_tiles()
  for _, obj in ipairs(getObjectsWithTag("zoo_map")) do
    obj.destruct()
  end
  if map_bag ~= nil then
    map_bag.destruct()
    map_bag = nil
  end
end

function on_map_custom_clicked()
  UI.setXml("")
  show_map_ready_panels()
end

function on_map_mirror_clicked()
  local pool = map_setup_pool()
  if #pool == 0 then return end
  UI.setXml("")
  destruct_map_tiles()

  local key = pool[math.random(#pool)]
  broadcastToAll("Mirror match: every player is on " .. map_setup_label(key) .. ".")
  for _, player in ipairs(players) do
    apply_map_choice(player, key, cnsts.map_data[key].image)
  end
  finish_map_setup()
end

function on_map_classic_clicked()
  if not classic_match_available() then return end
  UI.setXml("")
  destruct_map_tiles()

  local pool = map_setup_pool()
  for _, player in ipairs(players) do
    local pair = {}
    for _ = 1, 2 do
      pair[#pair + 1] = table.remove(pool, math.random(#pool))
    end
    player.classic_map_choice = { top = pair[1], bottom = pair[2] }
    spawn_classic_map_tile(player, pair[1], pair[2])
  end

  show_map_ready_panels(true)
end

function spawn_classic_map_tile(player, top_key, bottom_key)
  local at = player.player_board.getPosition()
  local tile = spawnObject({
    type = "Custom_Tile",
    position = { x = at.x, y = at.y + 2, z = at.z },
    rotation = {0, 180, 0},
    scale = cnsts.classic_map_tile.scale
  })
  tile.setCustomObject({
    type = 0,
    thickness = cnsts.classic_map_tile.thickness,
    image = cnsts.map_data[top_key].image,
    image_bottom = cnsts.map_data[bottom_key].image
  })
  tile = tile.reload()
  tile.setName(map_setup_label(top_key) .. " / " .. map_setup_label(bottom_key))
  tile.addTag("zoo_map")
  return tile
end

function setup_player_maps()
  local all_ready = true
  for _, player in ipairs(players) do
    if count_player_maps(player) ~= 1 then
      all_ready = false
      break
    end
  end

  if all_ready then
    for _, player in ipairs(players) do
      apply_player_map(player)
    end
    destruct_map_tiles()
    finish_map_setup()
    return
  end

  show_map_setup_panel()
end

function finish_map_setup()
  if marine_worlds_enabled then
    start_action_card_draft()
  else
    distribute_action_cards()
  end
end

function show_map_ready_panels(classic)
  local prompt = classic
    and "Flip the tile on your board to the map you want to play, then click Ready."
    or "Place exactly one map tile on your board (clone tiles if needed), then click Ready."

  map_ready = {}
  local panels = ""
  for _, player in ipairs(players) do
    map_ready[player.color] = false
    panels = panels .. string.format([[
      <Panel id="mapReadyPanel_%s" visibility="%s" rectAlignment="MiddleRight" width="300" height="160" color="#222222DD">
        <VerticalLayout spacing="6" padding="8 8 8 8" childAlignment="MiddleCenter">
          <Text fontSize="18" color="#FFFFFF">%s</Text>
          <Text id="mapReadyCheck_%s" fontSize="26" color="#00FF00" active="false">✓</Text>
          <Button id="mapReadyButton_%s" onClick="on_map_ready_clicked(%s)" fontSize="18" width="120" height="36" color="#4A90D9" textColor="#FFFFFF">Ready</Button>
        </VerticalLayout>
      </Panel>
    ]], player.color, player.color, prompt, player.color, player.color, player.color)
  end
  UI.setXml(panels)
end

function on_map_ready_clicked(_, color, _)
  local clicking_player = find_player_by_color(color)

  if not map_ready[color] and count_player_maps(clicking_player) ~= 1 then
    broadcastToColor("You must have exactly one map tile on your board before readying up.", color)
    return
  end

  map_ready[color] = not map_ready[color]
  UI.setAttribute("mapReadyCheck_" .. color, "active", tostring(map_ready[color]))
  UI.setAttribute("mapReadyButton_" .. color, "text", map_ready[color] and "Cancel" or "Ready")
  UI.setAttribute("mapReadyButton_" .. color, "color", map_ready[color] and "#E54848" or "#4A90D9")

  for _, player in ipairs(players) do
    if not map_ready[player.color] then
      return
    end
  end

  local invalid_names = {}
  for _, player in ipairs(players) do
    if count_player_maps(player) ~= 1 then
      table.insert(invalid_names, player.steam_name)
      map_ready[player.color] = false
      UI.setAttribute("mapReadyCheck_" .. player.color, "active", "false")
      UI.setAttribute("mapReadyButton_" .. player.color, "text", "Ready")
      UI.setAttribute("mapReadyButton_" .. player.color, "color", "#4A90D9")
    end
  end

  if #invalid_names > 0 then
    broadcastToAll(table.concat(invalid_names, ", ") .. " must have exactly one map tile on their board. Setup cannot proceed yet.")
    return
  end

  UI.setXml("")
  for _, player in ipairs(players) do
    apply_player_map(player)
  end
  destruct_map_tiles()
  finish_map_setup()
end

local handler_names = {}
for name, value in pairs(_G) do
  if type(value) == "function" and string.sub(name, 1, 3) == "on_" then
    handler_names[#handler_names + 1] = name
  end
end

for _, name in ipairs(handler_names) do
  local handler = _G[name]
  _G[name] = function(...)
    note_player_interaction()
    return handler(...)
  end
end
