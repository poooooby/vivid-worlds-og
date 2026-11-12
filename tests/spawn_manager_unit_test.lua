-- Run: lua tests/spawn_manager_unit_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  else
    print("ok  " .. tostring(msg))
  end
end
local function eq(a, b, msg)
  check(a == b, string.format("%s (got %s expected %s)", msg, tostring(a), tostring(b)))
end

math.randomseed(42)

local fakeEngine = {}
local modules = {}
local optionStore = { enabled = true }
local mod = {
  id = "vivid_worlds_og",
  options = { get = function(_, k) return optionStore[k] end },
  read = function(_, rel)
    local f = io.open(rel, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
  end,
}
local V = { path = ".", mod = mod }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  if name == "engine_patch" then
    modules[name] = fakeEngine
    return fakeEngine
  end
  local chunk = assert(loadfile("lib/" .. name .. ".lua"))
  local value = chunk(V)
  modules[name] = value
  return value
end

-- ------- fake engine: a 6x1 land strip, Treecko (national 252, internal
-- species id 999 to prove the national-dex conversion actually runs)
local tables = { ROUTE_1 = { land = { rate = 10, slots = {} } } }
fakeEngine.isSweetScentFacility = function() return false end
fakeEngine.safariActive = function() return false end
fakeEngine.ensureEncountersLoaded = function() return true end
fakeEngine.tableFor = function(mapId) return tables[mapId] end
fakeEngine.mapBounds = function() return 6, 1 end
fakeEngine.terrainAt = function(_x, _y) return "land" end
fakeEngine.canEnter = function() return true end
fakeEngine.isWater = function() return false end
fakeEngine.isGrass = function() return false end
fakeEngine.grassSheet = function() return nil end
fakeEngine.repelAllows = function() return true end
fakeEngine.trainerIds = function() return { otId = 1, otSecretId = 2 } end
fakeEngine.isShiny = function() return false end
fakeEngine.genderOf = function() return 0 end
fakeEngine.isCaught = function() return false end
fakeEngine.nationalFor = function(speciesId) if speciesId == 999 then return 252 end return nil end
fakeEngine.rollSweetScent = function(_mapId, terrain)
  return { species = 999, level = 5, personality = 123, terrainRolled = terrain }
end

local SpawnManager = V.require("spawn_manager")
-- these tests are about the Walk <-> Idle switch itself: no grace period (see the linger tests in pmd_renderer_unit_test.lua)
V.require("config").PMD_WALK_LINGER = 0

-- ------- targetCount: the density curve (Normal unless a Spawn Amount row is given)
eq(SpawnManager._targetCount(0), 0, "0 eligible cells -> 0 target")
eq(SpawnManager._targetCount(1), 1, "a handful of cells -> the floor (1)")
eq(SpawnManager._targetCount(1000), 8, "a huge area is capped at MAX_VISIBLE (8)")
do
  local C = V.require("config")
  local L, N, H = C.SPAWN_AMOUNT.low, C.SPAWN_AMOUNT.normal, C.SPAWN_AMOUNT.high
  -- Normal is exactly the curve before the option existed: 1 + one per 20 tiles, at most 8
  for _, n in ipairs({ 1, 19, 20, 39, 40, 99, 140, 141, 1000 }) do
    local old = math.min(8, math.max(1, 1 + math.floor(n / 20)))
    eq(SpawnManager._targetCount(n, N), old, "Normal = the old curve at " .. n .. " tiles")
  end
  eq(SpawnManager._targetCount(0, H), 0, "High: no tiles -> none")
  for _, n in ipairs({ 1, 20, 60, 100, 1000 }) do
    local l, m, h = SpawnManager._targetCount(n, L), SpawnManager._targetCount(n, N), SpawnManager._targetCount(n, H)
    check(l <= m and m <= h, ("Low <= Normal <= High at %d tiles (%d, %d, %d)"):format(n, l, m, h))
  end
  eq(SpawnManager._targetCount(1000, L), 4, "Low caps at 4")
  eq(SpawnManager._targetCount(1000, H), 12, "High caps at 12")
  eq(SpawnManager._targetCount(100, L), 3, "Low: 100 tiles -> 3 (Normal 6)")
  eq(SpawnManager._targetCount(100, H), 9, "High: 100 tiles -> 9 (Normal 6)")
  local _, name = C.spawnAmount({ options = { get = function() return "bogus" end } })
  eq(name, "normal", "an unknown saved value reads as Normal")
end

-- ------- Spawn Amount in play: High fills more, lowering trims the extras at once
do
  local realBounds = fakeEngine.mapBounds
  fakeEngine.mapBounds = function() return 40, 5 end -- 200 land tiles
  optionStore.spawn_amount = "high"
  local smA = SpawnManager.new(mod)
  smA:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  eq(smA:count(), 12, "High on 200 tiles: 12 out")
  optionStore.spawn_amount = "low"
  smA:trimToAmount()
  local leaving = 0
  for _, e in pairs(smA.entities) do if e.state == "leaving" then leaving = leaving + 1 end end
  eq(leaving, 8, "lowered to Low: the 8 extra start leaving at once")
  eq(smA:_activeCountFor("land"), 4, "...and no longer count")
  for _ = 1, V.require("config").SPAWN_FX.leaveTicks + 1 do smA:tick(smA.game) end
  eq(smA:count(), 4, "once they have left: 4, and refill keeps it there")
  optionStore.spawn_amount = "normal"
  smA:tick(smA.game)
  eq(smA:count(), 8, "raised to Normal: refill tops up to 8")
  optionStore.spawn_amount = nil
  fakeEngine.mapBounds = realBounds
end

-- ------- onMapEntered places visible wild Pokemon, converted to national dex
local sm = SpawnManager.new(mod)
sm:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
check(sm:count() > 0, "onMapEntered places at least one wild Pokemon")
local sampleId
for id, e in pairs(sm.entities) do
  sampleId = sampleId or id
  eq(e.dex, 252, "every entity's dex is the NATIONAL number, not the internal species id")
  eq(e.species, 999, "entity keeps the engine-internal species id for battle_trigger")
  eq(e.terrain, "land", "entity terrain matches the map (land-only in this fixture)")
  check(e.state == "available", "entity starts in the available state")
end

-- ------- floating/flying species flap while idle; ground species stay on
-- stand; a moving floater uses the walk pose
local SSrc = V.require("sprite_source")
local realIsFloater = SSrc.isFloater
SSrc.isFloater = function() return true end
local smF = SpawnManager.new(mod)
smF:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
local fe
for _, e in pairs(smF.entities) do fe = e break end
check(fe and fe.floater == true, "a floater species is flagged at spawn")
fe.behavior, fe.moving = "idle", false
fe.ticksUntilAction = 1e9
local poses = {}
for _ = 1, 100 do
  smF:tick(smF.game)
  local a = {}
  smF:collectActors(a)
  for _, actor in ipairs(a) do if actor.i == fe.id then poses[actor.walkPhase] = true end end
end
check(poses.walkA and poses.walkB and poses.stand, "an idle floater cycles walkA/stand/walkB")
fe.moving, fe.stepParity = true, true
local am = {}
smF:collectActors(am)
for _, actor in ipairs(am) do if actor.i == fe.id then eq(actor.walkPhase, "walkA", "a moving floater uses the walk pose") end end
SSrc.isFloater = function() return false end
local smG = SpawnManager.new(mod)
smG:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
local ge
for _, e in pairs(smG.entities) do ge = e break end
ge.behavior, ge.moving, ge.ticksUntilAction = "idle", false, 1e9
for _ = 1, 50 do smG:tick(smG.game) end
local ag = {}
smG:collectActors(ag)
for _, actor in ipairs(ag) do if actor.i == ge.id then eq(actor.walkPhase, "stand", "a ground species stays on stand") end end
SSrc.isFloater = realIsFloater

-- ------- _cellFree keeps spawns off the player's cell and the cell they are
-- stepping into
fakeEngine.playerCell = function() return { x = 2, y = 0, moving = true, targetX = 3, targetY = 0 } end
local smP = SpawnManager.new(mod)
check(not smP:_cellFree(2, 0), "no spawn on the cell the player stands on")
check(not smP:_cellFree(3, 0), "no spawn on the cell the player is stepping into")
check(smP:_cellFree(4, 0), "other cells stay free")
fakeEngine.playerCell = nil

-- ------- enabled=false spawns nothing
optionStore.enabled = false
local smOff = SpawnManager.new(mod)
smOff:onMapEntered("ROUTE_1", {})
eq(smOff:count(), 0, "Show Wild Mons off -> no spawns")
optionStore.enabled = true

-- ------- switched off mid-map, the clear stays cleared (the tick's refill must not undo it)
local smMid = SpawnManager.new(mod)
smMid:onMapEntered("ROUTE_1", {})
check(smMid:count() > 0, "spawns placed while on")
optionStore.enabled = false
smMid:onMapExited() -- what main.lua's options_changed handler does
smMid:tick({})
eq(smMid:count(), 0, "off mid-map: the next tick refills nothing")
optionStore.enabled = true
smMid:tick({})
check(smMid:count() > 0, "...and back on, it fills again")

-- ------- a species the engine can't convert to a national dex is skipped,
-- not spawned with a broken sprite lookup
fakeEngine.rollSweetScent = function() return { species = 111222, level = 5, personality = 1 } end
local smBad = SpawnManager.new(mod)
smBad:onMapEntered("ROUTE_1", {})
eq(smBad:count(), 0, "an unconvertible species id never gets spawned")
fakeEngine.rollSweetScent = function(_mapId, terrain)
  return { species = 999, level = 5, personality = 123, terrainRolled = terrain }
end

-- ------- entityAt / blocksCell
sm = SpawnManager.new(mod)
sm:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
local anyId, anyEntity
for id, e in pairs(sm.entities) do anyId, anyEntity = id, e break end
check(sm:entityAt(anyEntity.cellX, anyEntity.cellY) ~= nil, "entityAt finds the live entity on its cell")
check(sm:blocksCell(anyEntity.cellX, anyEntity.cellY), "blocksCell is true on an occupied cell")
check(not sm:blocksCell(-50, -50), "blocksCell is false off-map")

-- ------- markEncounterStarting removes it from entityAt (mid-battle mons
-- are not a collision target or a second trigger)
sm:markEncounterStarting(anyId)
check(sm:entityAt(anyEntity.cellX, anyEntity.cellY) == nil, "entityAt ignores an entity mid-battle")

-- ------- despawn removes it from both entities and order
sm:despawn(anyId)
check(sm.entities[anyId] == nil, "despawn removes the entity")
local stillInOrder = false
for _, id in ipairs(sm.order) do if id == anyId then stillInOrder = true end end
check(not stillInOrder, "despawn removes the id from draw order too")

-- ------- onMapExited clears everything
sm = SpawnManager.new(mod)
sm:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
check(sm:count() > 0, "sanity: something is spawned before exit")
sm:onMapExited()
eq(sm:count(), 0, "onMapExited clears all entities")
eq(#sm.order, 0, "onMapExited clears draw order")

-- ------- collectActors appends one actor per live entity with the shape
-- engine_patch's collectActors wrap expects
sm = SpawnManager.new(mod)
sm:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
local actors = {}
sm:collectActors(actors)
eq(#actors, sm:count(), "one actor per live entity")
for _, a in ipairs(actors) do
  eq(a.kind, "wild_mon", "actor kind is wild_mon")
  check(type(a.x) == "number" and type(a.y) == "number", "actor has world pixel coords")
  check(a.renderer ~= nil, "actor carries a renderer")
  check(a.elevation ~= nil, "actor has an elevation for applyDrawOrder")
end

-- ------- refill respects _cellFree: a fully-occupied strip refuses new spawns
tables.TINY = { land = { rate = 10, slots = {} } }
fakeEngine.mapBounds = function() return 1, 1 end
fakeEngine.terrainAt = function() return "land" end
local smTiny = SpawnManager.new(mod)
smTiny:onMapEntered("TINY", { world = { player = { cellX = -1, cellY = -1 } } })
eq(smTiny:count(), 1, "a 1x1 eligible area holds exactly one wild Pokemon")
smTiny:refill("land") -- should not error or duplicate on the same cell
eq(smTiny:count(), 1, "refill never double-occupies the only cell")
fakeEngine.mapBounds = function() return 6, 1 end -- restore for safety

-- ------- a fled Pokemon disappearing at the end of its run: into grass, or a cave's dark
do
  local sm = SpawnManager.new(mod)
  sm:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  local e = sm.entities[sm.order[1]]
  local realGrass, realType = fakeEngine.isGrass, fakeEngine.mapType
  fakeEngine.mapType = function() return 3 end
  fakeEngine.isGrass = function() return false end
  eq(sm:fleeVanish(e), false, "on a path out in the open it stays")
  e.isFlyer = true
  fakeEngine.isGrass = function() return true end
  eq(sm:fleeVanish(e), false, "a bird never does (it flies off instead)")
  e.isFlyer = nil
  e.terrain = "water"
  eq(sm:fleeVanish(e), false, "nor a swimmer")
  e.terrain = "land"
  eq(sm:fleeVanish(e), true, "in grass it shrinks into it")
  eq(e.state, V.require("config").STATE.LEAVING, "...leaving the animated way (its tile's fx)")
  local e2 = sm.entities[sm.order[2]]
  if e2 then
    fakeEngine.isGrass = function() return false end
    fakeEngine.mapType = function() return 4 end
    eq(sm:fleeVanish(e2), true, "in a cave it fades out")
  end
  fakeEngine.isGrass, fakeEngine.mapType = realGrass, realType
end

-- ------- Sprite Style: threaded into each entity's renderer at spawn
-- time, and a live option change re-points every live entity without
-- despawning anything
-- a view of the mod with no PMD art (hermetic: a dev checkout may have a real bake on disk)
local function withoutPmd(base)
  return setmetatable({
    read = function(self, rel)
      if type(rel) == "string" and rel:find("assets/pmd/", 1, true) then return nil end
      return base.read(self, rel)
    end,
  }, { __index = base })
end
optionStore.sprite_style = "pokemmo"
local smStyle = SpawnManager.new(withoutPmd(mod))
smStyle:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
local anyStyleEntity
for _, e in pairs(smStyle.entities) do anyStyleEntity = e break end
eq(anyStyleEntity.renderer.style, "pokemmo", "a new spawn uses the current Sprite Style")

-- a saved style that no longer exists ("followers" was Kanto-only) falls back
-- to the default and rebuilds cleanly -- here PMD has no art in this fake mod,
-- so the HGSS / PokeMMO renderer is what draws
optionStore.sprite_style = "followers"
smStyle:refreshSpriteStyle()
eq(anyStyleEntity.renderer.style, "pokemmo",
  "refreshSpriteStyle rebuilds an already-spawned entity's renderer on a stale style")
eq(smStyle:count(), 1, "refreshSpriteStyle never despawns anything")
optionStore.sprite_style = "pokemmo" -- restore for safety

-- ------- FireRed / LeafGreen encounters carry no personality: the spawn rolls
-- one from the engine, so the battle Pokemon is the one on screen
do
  local realRoll, realRand = fakeEngine.rollSweetScent, fakeEngine.randomPersonality
  fakeEngine.rollSweetScent = function() return { species = 999, level = 7 } end -- no personality, as FRLG
  fakeEngine.randomPersonality = function() return 424242 end
  local smFr = SpawnManager.new(mod)
  smFr:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  local fe
  for _, e in pairs(smFr.entities) do fe = e break end
  check(fe ~= nil, "an encounter without a personality still spawns")
  eq(fe.personality, 424242, "...with a personality rolled from the engine")
  fakeEngine.rollSweetScent = function() return { species = 999, level = 7, personality = 77 } end
  local smRse = SpawnManager.new(mod)
  smRse:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  for _, e in pairs(smRse.entities) do fe = e break end
  eq(fe.personality, 77, "an encounter that already has one keeps it (RSE)")
  fakeEngine.randomPersonality = function() return nil end -- the engine's rng is unusable
  fakeEngine.rollSweetScent = function() return { species = 999, level = 7 } end
  local smNone = SpawnManager.new(mod)
  check(pcall(function() smNone:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } }) end),
    "an engine whose rng returns nothing never errors (the battle then rolls its own)")
  fakeEngine.rollSweetScent, fakeEngine.randomPersonality = realRoll, realRand
end

-- ------- reachable-only spawns: nothing appears where the player can't go
do
  local Config = V.require("config")
  local R_GAME = { world = { player = { cellX = -1, cellY = -1 } } }
  -- the 6-cell land strip is split by a wall: cells 0-2 are the player's side
  local wallAt = 3
  local builds = 0
  local playerAt = { x = 0, y = 0, moving = false }
  fakeEngine.reachStart = function() return { x = playerAt.x, y = playerAt.y, state = {} } end
  fakeEngine.reachMover = function()
    builds = builds + 1
    return function(x, y, dir, state)
      local d = ({ left = -1, right = 1 })[dir]
      if not d then return nil end
      local nx = x + d
      if nx < 0 or nx > 5 or nx == wallAt then return nil end
      return nx, y, state
    end
  end
  fakeEngine.playerCell = function() return playerAt end

  local smR = SpawnManager.new(mod)
  smR:onMapEntered("ROUTE_1", R_GAME)
  check(smR:count() > 0, "reachable cells still spawn")
  local allReachable = true
  for _, e in pairs(smR.entities) do if e.cellX >= wallAt then allReachable = false end end
  check(allReachable, "every spawn is on the player's side of the wall")
  local eligible = smR.source:eligibleCells("land")
  eq(#eligible, 3, "the other side of the wall is not eligible")
  check(builds == 1 and smR.reachCount == 3, "the area was measured once, 3 cells")

  -- the player ends up on the far side (a warp / ledge): re-measure and prune
  local stranded = nil
  for _, e in pairs(smR.entities) do stranded = e break end
  playerAt.x = 5
  wallAt = 4 -- the player's new pocket is cells 5 only... and 0-3 are cut off from it
  smR:tick(R_GAME)
  eq(builds, 2, "a player standing outside the reachable area triggers a re-measure")
  check(smR.entities[stranded.id] and smR.entities[stranded.id].state == "leaving",
    "spawns now out of reach start leaving")
  for _ = 1, V.require("config").SPAWN_FX.leaveTicks + 1 do smR:tick(R_GAME) end
  check(smR.entities[stranded.id] == nil, "spawns now out of reach are removed")
  for _, e in pairs(smR.entities) do check(e.cellX == 5, "what remains is on the player's new side") end

  -- a moving player is never measured mid-step
  playerAt.moving = true
  playerAt.x = 0
  local before = builds
  smR:tick(R_GAME)
  eq(builds, before, "no re-measure while the player is mid-step")
  playerAt.moving = false

  -- the slow timer picks up a changed world (Surf learned, a tree cut)
  playerAt.x, wallAt = 0, 3
  smR:_rebuildReach()
  local b2 = builds
  for _ = 1, Config.REACH_REBUILD_TICKS do smR:tick(R_GAME) end
  check(builds > b2, "without a fingerprint, the area is re-measured on a timer")

  -- with a fingerprint: re-measured only when the world changed, once it settles
  local fp = 7
  fakeEngine.reachFingerprint = function() return fp end
  smR:_rebuildReach()
  local b3 = builds
  for _ = 1, Config.REACH_REBUILD_TICKS * 3 do smR:tick(R_GAME) end
  eq(builds, b3, "nothing changed: never re-measured, however long the player stands there")
  fp = 8 -- a tree cut
  for _ = 1, Config.REACH_CHECK_TICKS + Config.REACH_SETTLE_TICKS - 1 do smR:tick(R_GAME) end
  eq(builds, b3, "a change waits for the world to settle first")
  for _ = 1, Config.REACH_CHECK_TICKS * 2 do smR:tick(R_GAME) end
  eq(builds, b3 + 1, "...then re-measures exactly once")
  -- a boulder puzzle: a push every 2 s for 20 s, then a pause
  local b4 = builds
  for push = 1, 10 do
    fp = 100 + push
    for _ = 1, 120 do smR:tick(R_GAME) end
  end
  eq(builds, b4, "no re-measure while the boulders keep moving")
  for _ = 1, Config.REACH_CHECK_TICKS + Config.REACH_SETTLE_TICKS + Config.REACH_CHECK_TICKS do smR:tick(R_GAME) end
  eq(builds, b4 + 1, "one re-measure for the whole run of pushes, after the pause")
  -- pushed out and back again: nothing to do
  local b5 = builds
  fp = 999
  for _ = 1, Config.REACH_CHECK_TICKS do smR:tick(R_GAME) end
  fp = 110
  for _ = 1, Config.REACH_SETTLE_TICKS * 3 do smR:tick(R_GAME) end
  eq(builds, b5, "a change undone before it settled costs nothing")
  fakeEngine.reachFingerprint = nil

  -- the option off: no restriction at all
  Config.REACHABLE_SPAWNS = false
  local smOff2 = SpawnManager.new(mod)
  smOff2:onMapEntered("ROUTE_1", R_GAME)
  eq(#smOff2.source:eligibleCells("land"), 6, "REACHABLE_SPAWNS off: every land cell is eligible")
  Config.REACHABLE_SPAWNS = true

  -- no engine support (or no start): fail open, never an empty map
  fakeEngine.reachStart = function() return nil end
  local smOpen = SpawnManager.new(mod)
  smOpen:onMapEntered("ROUTE_1", R_GAME)
  eq(#smOpen.source:eligibleCells("land"), 6, "no start cell: no restriction")
  fakeEngine.reachStart, fakeEngine.reachMover, fakeEngine.playerCell = nil, nil, nil
  local smNone = SpawnManager.new(mod)
  smNone:onMapEntered("ROUTE_1", R_GAME)
  eq(#smNone.source:eligibleCells("land"), 6, "an engine without the reachability functions: no restriction")
  check(pcall(function() smNone:tick(R_GAME) end), "and ticking is safe")
end

-- ------- tooling: a chosen species on a tile near the player, or a battle with it
do
  fakeEngine.mapBounds = function() return 6, 1 end
  fakeEngine.terrainAt = function() return "land" end
  fakeEngine.randomPersonality = function() return 777 end
  fakeEngine.playerCell = function() return { x = 5, y = 0, moving = false } end
  local smT = SpawnManager.new(mod)
  smT:onMapEntered("ROUTE_1", { world = { player = { cellX = 5, cellY = 0 } } })
  smT:clearAll()
  local ok, cell = smT:spawnSpecies(999, 12)
  check(ok == true and cell ~= nil, "spawnSpecies places it")
  check(cell and math.abs(cell.x - 5) <= 3 and cell.x ~= 5, "...within 3 tiles of the player, never on their tile")
  local made
  for _, e in pairs(smT.entities) do made = e end
  eq(made and made.species, 999, "it is the species asked for")
  eq(made and made.level, 12, "...at the level asked for")
  eq(made and made.dex, 252, "...drawn through the usual national dex lookup")
  eq(made and made.shiny, false, "...not shiny unless asked")

  smT:clearAll()
  ok = smT:spawnSpecies(999, 5, { shiny = true })
  for _, e in pairs(smT.entities) do made = e end
  check(ok == true and made.shiny == true, "shiny = true makes it shiny")

  smT:clearAll()
  ok = smT:spawnSpecies(999, 5, { radius = 0 })
  eq(ok, nil, "a radius with no free eligible tile reports why")
  eq(select(2, smT:spawnSpecies(nil, 5)), "no species", "no species is refused")
  fakeEngine.playerCell = nil
  eq(select(2, smT:spawnSpecies(999, 5)), "no player", "no player cell is refused")

  local started
  fakeEngine.startWild = function(game, enc, opts) started = { game = game, enc = enc } return true end
  smT.game = { g = 1 }
  eq(smT:battleSpecies(999, 20, { shiny = true }), true, "battleSpecies starts a battle")
  check(started and started.enc.species == 999 and started.enc.level == 20 and started.enc.shiny == true,
    "...with that species, level and shininess")
  fakeEngine.startWild = function() return nil, "busy" end
  local bok, why = smT:battleSpecies(999, 20)
  check(bok == nil and why == "busy", "a battle that will not start says why")
end

-- ------- arriving / leaving (lib/spawn_fx.lua): rise out of the grass, surface, or fade
do
  local C = V.require("config")
  local realBounds, realGrass, realWater = fakeEngine.mapBounds, fakeEngine.isGrass, fakeEngine.isWater
  fakeEngine.mapBounds = function() return 40, 5 end
  local smF = SpawnManager.new(mod)
  smF:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  local anyFx = false
  for _, e in pairs(smF.entities) do if e.fx then anyFx = true end end
  check(not anyFx and smF.filled, "the map's first fill is instant (no effect)")

  -- after a battle a Pokemon is gone at once; its replacement fades in (no grass / water here)
  local first
  for id in pairs(smF.entities) do first = id break end
  smF:despawn(first)
  check(smF.entities[first] == nil, "despawn after a battle: gone at once")
  smF:tick(smF.game)
  local new
  for _, e in pairs(smF.entities) do if e.fx then new = e end end
  check(new and new.fx.kind == "appear" and new.fx.mode == "fade", "its replacement arrives (fade: not grass or water)")
  check(new.renderer.alpha ~= nil and new.renderer.alpha < 0.2, "...starting nearly invisible")
  check(smF:entityAt(new.cellX, new.cellY) == new, "an arriving Pokemon can already be met")
  local found = false
  for _, t in ipairs(smF:fightTargets()) do if t == new then found = true end end
  check(not found, "but the Battler does not pick it until it has arrived")
  local cx, cy = new.cellX, new.cellY
  new.behavior, new.ticksUntilAction = "roam", 0
  for _ = 1, C.SPAWN_FX.appearTicks do smF:tick(smF.game) end
  check(new.fx == nil and new.renderer.alpha == nil, "it finishes and the renderer is left as normal")
  check(new.cellX == cx and new.cellY == cy, "no wandering off while arriving")

  -- grass: rises (sink) with the rustle drawn on its tile
  fakeEngine.isGrass = function() return true end
  local rustled = 0
  fakeEngine.grassRustle = function() rustled = rustled + 1 return { quadsFront = { [1] = 1, [2] = 2, [3] = 3, [4] = 4 } }, { { 1, 10 }, { 2, 10 }, { 3, 10 }, { 4, 10 } } end
  local g
  for id in pairs(smF.entities) do g = id break end
  smF:despawn(g)
  smF:tick(smF.game)
  local ge
  for _, e in pairs(smF.entities) do if e.fx then ge = e end end
  check(ge and ge.fx.mode == "grass" and rustled >= 1, "in grass it rises, and the grass rustles")
  check(ge.renderer.act and ge.renderer.act.sink > 0.8, "...starting below the grass line")
  local acts = {}
  smF:collectActors(acts)
  local r = 0
  for _, a in ipairs(acts) do if a.kind == "ow_spawn_rustle" then r = r + 1 end end
  check(r == 1, "the rustle is drawn on its tile")
  for _ = 1, C.SPAWN_FX.appearTicks do smF:tick(smF.game) end
  check(ge.renderer.act == nil, "standing again: the renderer's act is cleared")

  -- water: surfaces with a ripple
  fakeEngine.isGrass = realGrass
  fakeEngine.isWater = function() return true end
  local ripples = 0
  fakeEngine.startRipple = function() ripples = ripples + 1 return true end
  local w
  for id in pairs(smF.entities) do w = id break end
  smF:despawn(w)
  smF:tick(smF.game)
  local we
  for _, e in pairs(smF.entities) do if e.fx then we = e end end
  check(we and we.fx.mode == "water" and we.rings ~= nil, "on water it surfaces inside growing rings")
  local wa = {}
  smF:collectActors(wa)
  local rings = 0
  for _, a in ipairs(wa) do if a.kind == "ow_spawn_rings" then rings = rings + 1 end end
  check(rings == 1, "the rings are drawn on its tile")
  for _ = 1, V.require("spawn_fx").ringsTicks() do smF:tick(smF.game) end
  check(we.rings == nil, "and are gone once all three have spread out")

  -- leaving: no longer met or counted, removed once it has sunk away
  for _ = 1, C.SPAWN_FX.appearTicks do smF:tick(smF.game) end
  local l
  for _, e in pairs(smF.entities) do l = e break end
  local before = smF:_activeCountFor("land")
  smF:despawn(l.id, { animate = true })
  check(l.state == "leaving" and l.fx.kind == "leave", "an animated despawn starts leaving")
  check(smF:entityAt(l.cellX, l.cellY) == nil, "a leaving Pokemon can no longer be met")
  check(smF:_activeCountFor("land") == before - 1, "and no longer counts")
  check(smF.entities[l.id] ~= nil, "it is still drawn while it goes")
  for _ = 1, C.SPAWN_FX.leaveTicks + 1 do smF:tick(smF.game) end
  check(smF.entities[l.id] == nil, "then it is gone")

  fakeEngine.mapBounds, fakeEngine.isGrass, fakeEngine.isWater = realBounds, realGrass, realWater
  fakeEngine.grassRustle, fakeEngine.startRipple = nil, nil
end

-- ------- the roaming legendary is one Pokemon: never more than one copy out
do
  local realRoll, realBounds = fakeEngine.rollSweetScent, fakeEngine.mapBounds
  fakeEngine.mapBounds = function() return 40, 5 end -- room for 8
  -- every roll wins the roamer (a FireRed player on Suicune's map got five of it)
  fakeEngine.rollSweetScent = function()
    return { species = 999, level = 50, personality = 77, roamer = true, hp = 40 }
  end
  local smR = SpawnManager.new(mod)
  smR:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  local roamers = 0
  for _, e in pairs(smR.entities) do if e.roamer then roamers = roamers + 1 end end
  eq(roamers, 1, "every roll wins the roamer: still only one out")
  local targets = smR:fightTargets()
  eq(#targets, 0, "the companion Battler never targets the roamer")
  fakeEngine.rollSweetScent, fakeEngine.mapBounds = realRoll, realBounds
end

-- ------- the Safari Zone: wild Pokemon show, but the companion Battler never fights them
do
  fakeEngine.safariActive = function() return true end
  local smS = SpawnManager.new(mod)
  smS:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  check(smS:count() > 0, "Safari Zone: wild Pokemon spawn")
  eq(#smS:fightTargets(), 0, "...but the Battler never targets them (Safari Balls only)")
  fakeEngine.safariActive = function() return false end
end

-- ------- off-screen wild Pokemon are not drawn (each draw takes a gen3-hd-sprites layer)
do
  fakeEngine.viewSize = function() return 240, 160 end
  local smV = SpawnManager.new(mod)
  smV:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  local n = smV:count()
  local all = {}
  smV:collectActors(all)
  local mons = 0
  for _, a in ipairs(all) do if a.kind == "wild_mon" then mons = mons + 1 end end
  eq(mons, n, "no camera: every wild Pokemon is drawn (older engine)")
  local seen = {}
  smV:collectActors(seen, 0, 0)
  mons = 0
  for _, a in ipairs(seen) do if a.kind == "wild_mon" then mons = mons + 1 end end
  eq(mons, n, "camera on the strip: all of them are in view")
  local far = {}
  smV:collectActors(far, 5000, 5000)
  mons = 0
  for _, a in ipairs(far) do if a.kind == "wild_mon" then mons = mons + 1 end end
  eq(mons, 0, "camera far away: none drawn")
  local I = SpawnManager._inView
  check(I({ px = 240 + 127, py = 0 }, 0, 0, 240, 160), "just inside the margin past the right edge: drawn")
  check(not I({ px = 240 + 128, py = 0 }, 0, 0, 240, 160), "at the margin: not drawn")
  check(I({ px = 0, py = -127 }, 0, 0, 240, 160), "a big sprite whose feet are just above the view: drawn")
  local refl = {}
  smV:reflections(refl, 5000, 5000)
  eq(#refl, 0, "no reflections for Pokemon out of view")
  fakeEngine.viewSize = nil
end

print("")
-- ------- an engaged wild Pokemon caught mid-step finishes the step, then stands still
do
  local smE = SpawnManager.new(mod)
  smE:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  local en
  for _, e in pairs(smE.entities) do en = e break end
  en.engaged = true
  en.fromX, en.fromY, en.targetX, en.targetY = en.cellX, en.cellY, en.cellX + 1, en.cellY
  en.progress, en.stepFrames, en.moving = 0, 4, true
  local tx = en.targetX
  for _ = 1, 6 do smE:tick(smE.game) end
  check(en.moving == false and en.cellX == tx, "it lands on the cell it was stepping into")
  local x, y = en.cellX, en.cellY
  for _ = 1, 30 do smE:tick(smE.game) end
  check(en.cellX == x and en.cellY == y and not en.moving, "...and then stands its ground")
end

-- ------- a shiny chain's bonus reaches the visible spawns (Modern Spawns)
do
  local MS = V.require("modern_spawns_bridge")
  local realBonus = MS.chainBonus
  local asked = {}
  MS.chainBonus = function(species) asked[#asked + 1] = species return { shiny = 0, perfectIvs = 6 } end
  local smC = SpawnManager.new(mod)
  smC:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  local ce
  for _, e in pairs(smC.entities) do ce = e break end
  check(ce ~= nil and #asked > 0 and asked[1] == ce.species, "each spawn asks for its species' chain bonus")
  local perfect = 0
  for _, v in pairs(ce and ce.ivs or {}) do if v == 31 then perfect = perfect + 1 end end
  eq(perfect, 6, "...and carries the perfect stats into its battle")
  MS.chainBonus = function() return nil end
  local smN = SpawnManager.new(mod)
  smN:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  local ne
  for _, e in pairs(smN.entities) do ne = e break end
  eq(ne and ne.ivs, nil, "no chain: IVs are left to the engine")
  MS.chainBonus = realBonus
end

-- ------- Wild Reacts: a running player close by startles them; one reacting is no Battler target
do
  local realCell, realBounds = fakeEngine.playerCell, fakeEngine.mapBounds
  fakeEngine.mapBounds = function() return 40, 5 end
  local smR = SpawnManager.new(mod)
  smR:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  local target
  for _, e in pairs(smR.entities) do target = target or e end
  local player = { x = target.cellX + 2, y = target.cellY, moving = true }
  fakeEngine.playerCell = function() return player end
  fakeEngine.playerIsRunning = function() return true end
  fakeEngine.leadPartyMon = function() return { level = 50, species = 1 } end -- they are all weak
  -- the wiring, not the odds (at most a coin flip in play): every roll hits here
  local REACT = V.require("config").REACT
  local odds = { REACT.minChance, REACT.maxChance }
  REACT.minChance, REACT.maxChance = 100, 100
  smR:tick(smR.game)
  check(target.react ~= nil, "running close by: it reacts")
  local isTarget = false
  for _, t in ipairs(smR:fightTargets()) do if t == target then isTarget = true end end
  check(not isTarget, "...and is no Battler target meanwhile")
  smR:calmReactions()
  eq(target.react, nil, "switching the option off calms everyone at once")
  optionStore.wild_reacts = false
  target.reactUntil = 0
  smR:tick(smR.game)
  eq(target.react, nil, "Wild Reacts off: nobody reacts")
  optionStore.wild_reacts = nil
  fakeEngine.playerCell, fakeEngine.mapBounds = realCell, realBounds
  fakeEngine.playerIsRunning, fakeEngine.leadPartyMon = nil, nil
  REACT.minChance, REACT.maxChance = odds[1], odds[2]
end

-- ------- the Battler's fight called off: a parting shot (cry + lunge), a run, gone; and a
-- knocked-out or running Pokemon can never be walked into for a fresh battle
do
  local realCell, realBounds, realCry = fakeEngine.playerCell, fakeEngine.mapBounds, fakeEngine.playCry
  fakeEngine.mapBounds = function() return 40, 5 end
  local smR = SpawnManager.new(mod)
  smR:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  local target
  for _, e in pairs(smR.entities) do target = target or e end
  local player = { x = target.cellX + 2, y = target.cellY, moving = false }
  fakeEngine.playerCell = function() return player end
  local cries = {}
  fakeEngine.playCry = function(species) cries[#cries + 1] = species end

  target.defeated = true
  eq(smR:entityAt(target.cellX, target.cellY), nil, "knocked out (0 HP, sinking): no longer met there")
  local inTargets = false
  for _, t in ipairs(smR:fightTargets()) do if t == target then inTargets = true end end
  check(not inTargets, "...nor fought")
  target.defeated = nil

  target.engaged = true
  check(smR:runAway(target), "the fight broken off: it sets off")
  eq(target.engaged, false, "...let go by the Battler")
  eq(smR:entityAt(target.cellX, target.cellY), nil, "running away: not met either")
  local startX = target.cellX
  smR:tick(smR.game)
  eq(target.facing, "right", "the parting shot: it turns to face the player")
  eq(#cries, 1, "...and cries")
  check(target.renderer == nil or (target.renderer.act and target.renderer.act.runLunge), "...lunging at them")
  local leaving = false
  for _ = 1, 400 do
    smR:tick(smR.game)
    if not smR.entities[target.id] or target.state == V.require("config").STATE.LEAVING then leaving = true break end
  end
  eq(#cries, 1, "one cry only")
  check(leaving, "then it runs off and leaves")
  check(target.cellX <= startX, "...away from the player (" .. startX .. " -> " .. target.cellX .. ")")
  fakeEngine.playerCell, fakeEngine.mapBounds, fakeEngine.playCry = realCell, realBounds, realCry
end

-- ------- a chaser left out on the path (its chase cut short) goes home; with Wild Reacts
-- off it fades away instead
do
  local saved = {}
  for _, k in ipairs({ "playerCell", "mapBounds", "terrainAt", "cellFree", "fieldBusy" }) do saved[k] = fakeEngine[k] end
  fakeEngine.mapBounds = function() return 40, 5 end
  -- grass x < 20, a path beyond it
  fakeEngine.terrainAt = function(x) if x < 20 then return "land" end return nil end
  fakeEngine.cellFree = function(x, y) return x >= 0 and y >= 0 and x < 40 and y < 5 end
  local player = { x = 39, y = 4, moving = false }
  fakeEngine.playerCell = function() return player end
  local smS = SpawnManager.new(mod)
  smS:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  local stray
  for _, e in pairs(smS.entities) do stray = stray or e end
  -- it chased out onto the path, then the chase was cut short (no reaction running)
  stray.cellX, stray.cellY, stray.px, stray.py = 23, 2, 23 * 16, 2 * 16
  stray.chaseHome, stray.react, stray.fx = { x = 15, y = 2 }, nil, nil
  smS:tick(smS.game)
  check(stray.react and stray.react.mode == "return", "a stray on the path is sent home")
  for _ = 1, 600 do
    if not stray.react then break end
    smS:tick(smS.game)
  end
  check(stray.cellX < 20, "...it walked back onto its grass (" .. stray.cellX .. ")")
  eq(stray.chaseHome, nil, "...and forgot the way")
  eq(smS:get(stray.id), stray, "...still there")

  -- Wild Reacts off: nothing walks it home, so it fades out (once the field is free)
  stray.cellX, stray.px, stray.chaseHome = 25, 25 * 16, { x = 15, y = 2 }
  optionStore.wild_reacts = false
  fakeEngine.fieldBusy = function() return true end
  smS:tick(smS.game)
  local STATE = V.require("config").STATE
  eq(stray.state, STATE.AVAILABLE, "Wild Reacts off, the field busy: it waits")
  fakeEngine.fieldBusy = function() return false end
  smS:tick(smS.game)
  eq(stray.state, STATE.LEAVING, "...then it fades away, never stuck on the path")
  optionStore.wild_reacts = nil
  for k, v in pairs(saved) do fakeEngine[k] = v end
end

-- ------- swimmers: they bob, leave a wake, and now and then dive and come up elsewhere
do
  local Config = V.require("config")
  local realT, realW, realPC = fakeEngine.terrainAt, fakeEngine.isWater, fakeEngine.playerCell
  local ripples = 0
  fakeEngine.startRipple = function() ripples = ripples + 1 end
  local smW = SpawnManager.new(mod)
  smW:onMapEntered("ROUTE_1", { world = { player = { cellX = -1, cellY = -1 } } })
  local e
  for _, x in pairs(smW.entities) do e = e or x end
  for id, x in pairs(smW.entities) do if x ~= e then smW:despawn(id) end end
  fakeEngine.terrainAt = function(_x, y) return y == 0 and "water" or "land" end
  fakeEngine.isWater = function() return true end
  fakeEngine.playerCell = function() return { x = 30, y = 30 } end
  e.terrain, e.cellX, e.cellY, e.px, e.py = "water", 2, 0, 32, 0

  -- the bob
  smW.ticks = 0
  e.diveIn = 9999
  smW:_swimLife(e)
  local b0 = e.renderer.bobDy
  smW.ticks = math.floor(Config.SWIM.bobTicks / 4)
  smW:_swimLife(e)
  check(b0 ~= e.renderer.bobDy and math.abs(e.renderer.bobDy) <= Config.SWIM.bobAmp, "a swimmer bobs, within bobAmp")

  -- a wake where a step set off
  e.moving, e.progress, e.fromX, e.fromY = true, 0, 2, 0
  smW:_wakeOnStep(e)
  eq(#e.wakes, 1, "a step on the water leaves a wake ring")
  eq(e.wakes[1].x, 32, "...on the tile it left")
  for _ = 1, Config.SWIM.wake.life do smW:_ageWakes(e) end
  eq(e.wakes, nil, "...which fades away")
  smW.underwater = true
  smW:_wakeOnStep(e)
  eq(e.wakes, nil, "under the sea: no wake (no surface)")
  smW.underwater, e.moving, e.progress = nil, false, nil

  -- the player right beside it: no dive yet
  fakeEngine.playerCell = function() return { x = 3, y = 0 } end
  e.diveIn = 1
  smW:_swimLife(e)
  eq(e.fx, nil, "it does not dive with the player right there")
  fakeEngine.playerCell = function() return { x = 30, y = 30 } end

  e.diveIn = 1
  smW:_swimLife(e)
  check(e.fx and e.fx.dive and e.fx.kind == "leave", "its time comes: it dives")
  check(e.rings ~= nil and ripples > 0, "...in rings and a ripple")
  eq(#smW:fightTargets(), 0, "a diving Pokemon is no Battler target")
  for _ = 1, Config.SWIM.dive.sinkTicks do smW:_stepDive(e) end
  check(e.fx.under and e.fx.under >= Config.SWIM.dive.underMin, "sunk: it stays under a while")
  eq(e.renderer.act and e.renderer.act.sink, 1, "...out of sight")
  eq(smW:entityAt(2, 0), nil, "...and nobody bumps into it there")
  e.fx.under = 1
  smW:_stepDive(e)
  check(e.fx and e.fx.kind == "appear" and not e.fx.dive, "then it surfaces like a new arrival")
  check(e.cellX ~= 2 and math.abs(e.cellX - 2) <= Config.SWIM.dive.hop and e.cellY == 0,
    "...on open water a few tiles off (" .. e.cellX .. "," .. e.cellY .. ")")
  eq(e.px, e.cellX * 16, "...drawn there")

  -- despawned while under: gone at once, nothing to watch leave
  e.fx = { kind = "leave", mode = "water", dive = true, under = 50, t = 0, n = 1 }
  smW:despawn(e.id, { animate = true })
  eq(smW.entities[e.id], nil, "despawned while under: removed at once")

  fakeEngine.terrainAt, fakeEngine.isWater, fakeEngine.playerCell = realT, realW, realPC
  fakeEngine.startRipple = nil
end
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("spawn_manager_unit_test: all passed")
