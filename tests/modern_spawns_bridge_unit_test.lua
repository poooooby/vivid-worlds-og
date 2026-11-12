-- Run: lua tests/modern_spawns_bridge_unit_test.lua
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

local gen = 1
local roaming = {}
local views = {}
local DEX = { PIDGEY = 16, RATTATA = 19, MEWTWO = 150, SUICUNE = 245, UNOWN = 201, HOOTHOOT = 163 }
local fakeEngine = {
  generation = function() return gen end,
  nationalFor = function(id) return DEX[id] end,
  isRoamingSpecies = function(id) return roaming[id] == true end,
  setTableView = function(view) views[#views + 1] = view return true end,
}
local other -- what mod:find("modern_spawns") answers
local mod = { find = function(_, id) if id == "modern_spawns" then return other end end }
local V = { path = ".", mod = mod }
local modules = {}
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  if name == "engine_patch" then return fakeEngine end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end

local active, generation = true, 1
local legendary, chained
local draws = 0
local generated = {
  ROUTE_1 = { grass = { rate = 25, slots = { { species = "HOOTHOOT", level = 3 } } } },
}
local api = {
  apiVersion = 2,
  isActive = function() return active end,
  generation = function() return generation end,
  drawFor = function(mapId, terrain)
    draws = draws + 1
    return (generated[mapId] or {})[terrain]
  end,
  legendaryFor = function() return legendary end,
  chainSpeciesFor = function() return chained end,
  chainBonus = function(species) if species == "PIDGEY" then return { shiny = 0.5 } end end,
}
other = { exports = api }
local Bridge = V.require("modern_spawns_bridge")

-- ------- Gen 1: the map's definition with Modern Spawns' tables in place of the game's
do
  local raw = { grass = { rate = 25, slots = { { species = "PIDGEY", level = 3 } } }, music = "X" }
  local def = Bridge.gen1Def("ROUTE_1", raw)
  eq(def.grass.slots[1].species, "HOOTHOOT", "Gen 1: the grass table is Modern Spawns'")
  eq(def.music, "X", "...the rest of the definition is the game's")
  eq(raw.grass.slots[1].species, "PIDGEY", "...and the game's own table is untouched")
  check(Bridge.gen1Def("ROUTE_2", raw) == raw, "no generated table for the map: the game's")
  active = false
  check(Bridge.gen1Def("ROUTE_1", raw) == raw, "Modern Spawns OFF: the game's")
  active = true
  generation = 2
  check(Bridge.gen1Def("ROUTE_1", raw) == raw, "tables for another generation are never used")
  generation = 1
  other = nil
  check(Bridge.gen1Def("ROUTE_1", raw) == raw, "Modern Spawns absent: the game's")
  other = { exports = api }
  check(Bridge.install() == true and views[#views] == Bridge.gen1Def, "install hands Red / Blue / Yellow's roll the Gen 1 view")
end

-- ------- Gen 2: a read-only view over the kind-first tables, swarms kept
do
  gen, generation = 2, 2
  local route29 = { slots = { MORN = {}, DAY = {}, NITE = {} } }
  local swarm = { slots = { MORN = {}, DAY = {}, NITE = {} }, swarm = true }
  generated.ROUTE_29 = { grass = { slots = { DAY = { { species = "HOOTHOOT", level = 3 } } } } }
  generated.ROUTE_32 = { grass = { slots = { DAY = { { species = "RATTATA", level = 3 } } } } }
  local cart = { grass = { ROUTE_29 = route29, ROUTE_32 = route29 }, water = {} }
  local live = { grass = { ROUTE_29 = route29, ROUTE_32 = swarm }, water = {}, other = 7 }
  local view = Bridge.gen2Tables(live, cart)
  eq(view.grass.ROUTE_29.slots.DAY[1].species, "HOOTHOOT", "Gen 2: a map's grass list is Modern Spawns'")
  check(view.grass.ROUTE_32 == swarm, "...a swarm in progress is kept as it is")
  eq(view.grass.ROUTE_99, nil, "...a map with no table has none")
  eq(view.other, 7, "...everything else reads through")
  active = false
  check(Bridge.gen2Tables(live, cart) == live, "Modern Spawns OFF: the live tables themselves")
  active = true
  check(Bridge.install() == true and views[#views] == Bridge.gen2Tables, "install hands Gold's roll the Gen 2 view")
end

-- ------- after the roll: LEGENDARIES and the shiny chain replace the species, level kept
do
  local enc = { species = "PIDGEY", level = 7, dvs = { attack = 1 } }
  check(Bridge.apply("ROUTE_1", "land", enc) == enc, "nothing rolled: the encounter itself")
  legendary = "MEWTWO"
  local out = Bridge.apply("ROUTE_1", "land", enc)
  eq(out.species, "MEWTWO", "a LEGENDARIES roll takes the spawn")
  eq(out.level, 7, "...at the rolled level")
  eq(out.dvs, nil, "...its DVs drawn afresh (the Shiny Rate, when it is placed)")
  eq(enc.species, "PIDGEY", "...the roll itself is untouched")
  roaming.SUICUNE, legendary = true, "SUICUNE"
  eq(Bridge.apply("ROUTE_1", "land", enc).species, "PIDGEY", "a roaming beast still out is never offered twice")
  legendary = "MISSINGNO"
  eq(Bridge.apply("ROUTE_1", "land", enc).species, "PIDGEY", "a species this game lacks is ignored")
  legendary, chained = nil, "RATTATA"
  eq(Bridge.apply("ROUTE_1", "land", enc).species, "RATTATA", "the shiny chain's species takes the spawn")
  local beast = { species = "SUICUNE", level = 40, roamer = 3 }
  check(Bridge.apply("ROUTE_1", "land", beast) == beast, "a roaming beast is never replaced")
  chained = nil
  eq(Bridge.chainBonus("PIDGEY").shiny, 0.5, "chainBonus passes through")
  eq(Bridge.chainBonus("RATTATA"), nil, "...nil for a species not chained")
  active = false
  eq(Bridge.chainBonus("PIDGEY"), nil, "...and with Modern Spawns OFF")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("modern_spawns_bridge_unit_test: all passed")
