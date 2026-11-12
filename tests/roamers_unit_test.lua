-- Gold / Silver / Crystal's roaming beasts as visible spawns (lib/gb/roamers.lua).
-- Part 1: the module against a fake engine. Part 2: parity with the REAL engine's
-- Roamers.checkEncounter (../gen1recomp, skipped when absent).
-- Run: lua tests/roamers_unit_test.lua
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
local function fixed(v) return function() return v end end

local Roam = assert(loadfile("lib/gb/roamers.lua"))()

local function freshSave()
  return { roamers = {
    { species = "RAIKOU", level = 40, map = "ROUTE_42", hp = 0 },
    { species = "ENTEI", level = 40, map = "ROUTE_37", hp = 0 },
  } }
end

-- ------------------------------------------------------------ Part 1: fake engine
local E = {
  LEVEL = 40,
  list = function(save) return save and save.roamers end,
  active = function(slot) return type(slot) == "table" and slot.species ~= nil and slot.map ~= nil end,
}

do
  local save = freshSave()
  -- 1 -> slot 1 (Raikou), 2 -> slot 2 (Entei), low bits 0 = no beast, >= 100 = no beast
  local hit = Roam.pickForSpawn(E, save, "ROUTE_42", "land", fixed(1))
  eq(hit and hit.index, 1, "Raikou replaces a spawn on its own route (slot 1)")
  eq(hit and hit.species, "RAIKOU", "...the save's species")
  eq(hit and hit.level, 40, "...and level")
  eq(hit and hit.dvs, nil, "no DVs before the first meeting")
  eq(hit and hit.hp, nil, "...nor HP")
  eq(Roam.pickForSpawn(E, save, "ROUTE_42", "land", fixed(2)), nil, "Entei's roll fails while Entei is elsewhere")
  eq(Roam.pickForSpawn(E, save, "ROUTE_42", "land", fixed(0)), nil, "low bits 0 = no beast")
  eq(Roam.pickForSpawn(E, save, "ROUTE_42", "land", fixed(4)), nil, "low bits 0 = no beast (4)")
  eq(Roam.pickForSpawn(E, save, "ROUTE_42", "land", fixed(101)), nil, "100 and above = no beast")
  eq(Roam.pickForSpawn(E, save, "ROUTE_42", "water", fixed(1)), nil, "never on water")
  eq(Roam.pickForSpawn(E, save, "ROUTE_42", "land", fixed(3)), nil, "Crystal has no slot 3")
  eq((Roam.pickForSpawn(E, save, "ROUTE_37", "land", fixed(2)) or {}).species, "ENTEI", "Entei on Route 37")

  save.roamers[1].hp = 120
  save.roamers[1].dvs = { attack = 2, defense = 10, speed = 10, special = 10 }
  local met = Roam.pickForSpawn(E, save, "ROUTE_42", "land", fixed(1))
  check(met and met.dvs == save.roamers[1].dvs, "a beast met before carries its kept DVs")
  eq(met and met.hp, 120, "...and the HP it has left")

  eq(Roam.isRoaming(E, save, "RAIKOU"), true, "Raikou is still out")
  eq(Roam.isRoaming(E, save, "SUICUNE"), false, "Suicune is not on Crystal's roster")
  save.roamers[1].species, save.roamers[1].map = nil, nil
  eq(Roam.pickForSpawn(E, save, "ROUTE_42", "land", fixed(1)), nil, "a caught / beaten beast never spawns")
  eq(Roam.isRoaming(E, save, "RAIKOU"), false, "...nor counts as out")
  eq(Roam.pickForSpawn(E, {}, "ROUTE_42", "land", fixed(1)), nil, "no roster before the Burned Tower")
  eq(Roam.onMap(E, freshSave(), 2, "ROUTE_37").species, "ENTEI", "onMap: Entei is on Route 37")
  eq(Roam.onMap(E, freshSave(), 2, "ROUTE_42"), nil, "...not on Route 42")
end

do
  local save = freshSave()
  local began, started, ended = {}, {}, {}
  local engine = setmetatable({
    beginBattle = function(s, index, data)
      began[#began + 1] = { index = index, data = data }
      return { species = s.roamers[index].species, level = 40, hp = 150 }
    end,
  }, { __index = E })
  local game = { save = save, data = { tag = "data" } }
  local world = { game = game, map = { id = "ROUTE_37" },
    startBattle = function(_, opts, cb) started[#started + 1] = opts; cb("run") end }
  eq(Roam.startBattle(engine, world, 2, function(r) ended[#ended + 1] = r end), true, "the roaming battle starts")
  eq(began[1] and began[1].index, 2, "the engine's beginBattle, for the beast's own slot")
  check(began[1] and began[1].data == game.data, "...with the game's data")
  eq(started[1] and started[1].roaming, 2, "World:startBattle gets roaming = slot")
  eq(started[1] and started[1].wild and started[1].wild.species, "ENTEI", "the wild Pokemon is the beast")
  eq(save.pokedex.seen.ENTEI, true, "marked seen, as the step path does")
  eq(ended[1], "run", "the battle's end reaches the caller")
  local okMoved, why = Roam.startBattle(engine, world, 1)
  eq(okMoved, nil, "no battle with a beast on another route")
  check(why ~= nil, "...with a reason")
  eq(#began, 1, "...and no beginBattle for it")
end

do
  local calls = 0
  local engine = { checkEncounter = function() calls = calls + 1 return { index = 1 } end }
  local block = false
  local undo = Roam.installStepGate(engine, function() return block end)
  check(type(undo) == "function", "the step gate installs")
  check(engine.checkEncounter(nil, "ROUTE_42", false) ~= nil, "gate open: the engine's roll runs")
  block = true
  eq(engine.checkEncounter(nil, "ROUTE_42", false), nil, "gate shut: no beast on the step")
  eq(calls, 1, "...and the engine's roll is skipped")
  local wrapper = engine.checkEncounter
  local undo2 = Roam.installStepGate(engine, function() return false end)
  check(engine.checkEncounter == wrapper, "a reload swaps the gate, not a second wrapper")
  undo() -- an old load's undo must not remove the new gate
  check(type(engine._vwogStepGate) == "function", "an old load's undo leaves the new gate alone")
  undo2()
  eq(engine._vwogStepGate, nil, "undo removes the gate")
  local undoErr = Roam.installStepGate(engine, function() error("boom") end)
  check(engine.checkEncounter(nil, "ROUTE_42", false) ~= nil, "a gate that errors fails open")
  undoErr()
end

-- ------------------------------------------------------------ Part 2: the real engine module
do
  local path = "../gen1recomp/src/core/gen2/Roamers.lua"
  local f = io.open(path, "rb")
  if not f then
    print("skip the real-engine Roamers checks (no ../gen1recomp)")
  else
    f:close()
    package.loaded["src.battle.gen2.Mon"] = { new = function() return nil end }
    package.loaded["src.mods.Runtime"] = { wants = function() return false end, emit = function() end }
    package.loaded["src.core.GameVersion"] = { get = function() return "crystal" end,
      generation = function() return 2 end, isGold = function() return false end,
      isCrystal = function() return true end, engine = function() return "crystal" end }
    local Real = assert(loadfile(path))()
    local save = {}
    Real.init(save, {})
    check(type(save.roamers) == "table" and #save.roamers >= 2, "the real InitRoamMons roster")
    -- same byte, same answer, for every byte: the spawn roll IS the step roll
    for _, mapId in ipairs({ save.roamers[1].map, save.roamers[2].map, "ROUTE_29" }) do
      local mismatches = 0
      for v = 0, 255 do
        local step = Real.checkEncounter(save, mapId, false, fixed(v))
        local spawn = Roam.pickForSpawn(Real, save, mapId, "land", fixed(v))
        if (step and step.index) ~= (spawn and spawn.index) then mismatches = mismatches + 1 end
      end
      eq(mismatches, 0, "the spawn roll matches the engine's step roll for all 256 bytes on " .. tostring(mapId))
    end
    local undo = Roam.installStepGate(Real, function() return true end)
    eq(Real.checkEncounter(save, save.roamers[1].map, false, fixed(1)), nil, "the real checkEncounter gated shut")
    undo()
    check(Real.checkEncounter(save, save.roamers[1].map, false, fixed(1)) ~= nil, "...and vanilla again")
    package.loaded["src.battle.gen2.Mon"] = nil
    package.loaded["src.mods.Runtime"] = nil
    package.loaded["src.core.GameVersion"] = nil
  end
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("roamers_unit_test: all passed")
