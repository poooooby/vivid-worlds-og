-- Run: lua tests/reach_mover_unit_test.lua
-- The reachable-area step functions (lib/gb/gen1.lua / lib/gb/gen2.lua reachMover) over small
-- fake maps, driven through the real flood fill (lib/reachability.lua): one-way ledges, the
-- Gen 1 tile-pair edges, warp holes, Surf, and Gold's one-way collision edges.
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then failures = failures + 1; io.stderr:write("FAIL: " .. tostring(msg) .. "\n") else print("ok  " .. tostring(msg)) end
end

local V = { path = "." }
local modules = {}
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  modules[name] = assert(loadfile("lib/" .. name .. ".lua"))(V)
  return modules[name]
end
local Reachability = V.require("reachability")

local function reach(move, sx, sy, state)
  return Reachability.build({ startX = sx, startY = sy, startState = state or {}, move = move })
end
local has = Reachability.has

-- ------------------------------------------------------------------ Gen 1
do
  -- rows of single characters: . floor, # wall, ~ water, L ledge (hop down), W warp, a/b tile-pair edge
  local rows = {
    ". . . . .",
    ". . . . .",
    "L L L L L",
    ". . . . .",
    ". a b W .",
    "~ ~ ~ ~ ~",
    ". . . . .",
  }
  local grid = {}
  for y, row in ipairs(rows) do
    grid[y - 1] = {}
    local x = 0
    for c in row:gmatch("%S") do grid[y - 1][x] = c x = x + 1 end
  end
  local map = {
    def = { tileset = "OVERWORLD" },
    inBounds = function(_, x, y) return grid[y] ~= nil and grid[y][x] ~= nil end,
    cellTile = function(_, x, y) return grid[y][x] end,
    isWalkableCell = function(_, x, y) local c = grid[y][x] return c == "." or c == "a" or c == "b" or c == "W" end,
    isWaterCell = function(_, x, y) return grid[y][x] == "~" end,
    warpAtCell = function(_, x, y) return grid[y][x] == "W" end,
  }
  local fakes = {
    ["src.core.Game"] = { data = { field = { ledges = {
      { tileset = "OVERWORLD", facing = "down", input = "down", standingTile = ".", ledgeTile = "L" },
    } } } },
    ["src.world.Collision"] = { pairBlocked = function(_, _, sx, sy, tx, ty)
      local a, b = grid[sy][sx], grid[ty][tx]
      return (a == "a" and b == "b") or (a == "b" and b == "a")
    end },
  }
  local Gen1 = assert(loadfile("lib/gb/gen1.lua"))(V)
  Gen1.init(function(path) return fakes[path] end)
  local move = Gen1.reachMover({ map = map })
  check(type(move) == "function", "Gen 1: a step function for the live map")

  local set = reach(move, 0, 0)
  check(has(set, 4, 1), "Gen 1: walking reaches the far side of the top field")
  check(has(set, 0, 3), "Gen 1: a ledge hops two cells down")
  check(not has(set, 0, 2), "...without standing on the ledge")
  check(has(set, 1, 4), "Gen 1: beyond the ledge is reached")
  check(move(1, 4, "right", {}) == nil, "Gen 1: a blocked tile pair (cave edge) is not crossed")
  check(move(1, 3, "down", {}) == 1, "...while a plain step onto the same tile is fine")
  check(not has(set, 3, 4), "Gen 1: a warp cell is a hole")
  check(not has(set, 0, 6), "Gen 1: across the water needs Surf")

  local below = reach(move, 0, 3)
  check(not has(below, 0, 1), "Gen 1: a ledge is one-way (no way back up)")

  local surfing = reach(move, 0, 3, { surfing = true })
  check(has(surfing, 2, 6), "Gen 1: a surfer crosses the water to the far shore")
end

-- ------------------------------------------------------------------ Gen 2
do
  -- 5 x 4: (2,0)->(2,1) a one-way edge (down only); (0,2) a ledge hopping down over (0,3)?
  -- cells: . floor, # wall, H warp collision WITH an event, h warp collision WITHOUT one,
  -- J a ledge cell whose collision lets the player hop down
  local rows = {
    ". . . . .",
    "# # . # #",
    "J . h H .",
    "# . . . .",
    ". . . . .",
  }
  local grid = {}
  for y, row in ipairs(rows) do
    grid[y - 1] = {}
    local x = 0
    for c in row:gmatch("%S") do grid[y - 1][x] = c x = x + 1 end
  end
  local D = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  local map = {
    inBounds = function(_, x, y) return grid[y] ~= nil and grid[y][x] ~= nil end,
    cellCollision = function(_, x, y) return grid[y][x] end,
    warpAtCell = function(_, x, y) return grid[y][x] == "H" end,
    -- the one-way edge: from (2,1) up to (2,0) is refused; everything else follows walls
    stepPermitted = function(_, x, y, dir)
      if x == 2 and y == 1 and dir == "up" then return false end
      local nx, ny = x + D[dir][1], y + D[dir][2]
      return grid[ny] ~= nil and grid[ny][nx] ~= nil and grid[ny][nx] ~= "#" and grid[y][x] ~= "J"
    end,
  }
  local P = {
    isWalkable = function(c) return c ~= "#" end,
    isWarpCollision = function(c) return c == "H" or c == "h" end,
    carpetDirection = function() return nil end,
    ledgeFacings = function(c) if c == "J" then return { down = true } end return nil end,
  }
  local Gen2 = assert(loadfile("lib/gb/gen2.lua"))(V)
  Gen2.init(function(path) if path == "src.world.gen2.Permissions" then return P end end)
  local move = Gen2.reachMover({ map = map })
  check(type(move) == "function", "Gen 2: a step function for the live map")

  local top = reach(move, 0, 0)
  check(has(top, 2, 2), "Gen 2: down through the one-way gap")
  check(has(top, 2, 2) and has(top, 1, 4), "...and on to the bottom")
  check(not has(top, 3, 2), "Gen 2: a warp tile WITH a warp event is a hole")

  local bottom = reach(move, 1, 4)
  check(not has(bottom, 0, 0), "Gen 2: the one-way edge cannot be climbed back up")
  check(has(bottom, 2, 2), "Gen 2: a warp tile with no event is plain floor")
  local hop = reach(move, 0, 2)
  check(has(hop, 0, 4), "Gen 2: a ledge hops two cells in the direction it allows")

  check(Gen2.reachMover({ map = {} }) == nil, "Gen 2: no step function without the engine's movement rules")
end

if failures > 0 then io.stderr:write(failures .. " failure(s)\n") os.exit(1) end
print("reach_mover_unit_test: all passed")
