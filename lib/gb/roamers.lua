-- Gold / Silver / Crystal's roaming legendaries as visible spawns (ported from Wilds of Kanto
-- Revival's lib/gen2/roamers.lua).
--
-- Raikou and Entei (and Suicune in Gold / Silver) are in no map's wild table: the engine keeps
-- each beast in the save (save.roamers, src/core/gen2/Roamers.lua) on one route at a time, and
-- CheckEncounterRoamMon lets it REPLACE an ordinary step encounter on that route. A visible
-- spawn is picked the same way: on the beast's route the spawn's pick is replaced by the beast
-- at the game's own odds.
--
-- Everything else stays the engine's: which route each beast is on, and the battle itself
-- (Roamers.beginBattle + World:startBattle{ roaming = index }), so the saved HP and DVs, the
-- first-turn flee, the move to a new route afterwards and the slot clearing once it is caught or
-- beaten happen exactly as on a step.
--
-- With Classic Enc off the engine would still roll a beast on a step (CheckEncounterRoamMon runs
-- before the encounter.roll hook main.lua suppresses), so installStepGate puts a gate in front of
-- Roamers.checkEncounter. `E` below is that engine module (lib/gb/gen2.lua hands it in).
local Roam = {}

local function roster(save, E)
  if E and type(E.list) == "function" then return E.list(save) end
  return type(save) == "table" and save.roamers or nil
end

local function active(slot, E)
  if E and type(E.active) == "function" then return E.active(slot) == true end
  return type(slot) == "table" and slot.species ~= nil and slot.map ~= nil
end

-- 0 .. n-1, the convention the engine's Roamers uses for an injected random
local function rand(rng, n)
  if type(rng) == "function" then return rng(n) end
  return math.random(n) - 1
end

--- The roster slot `index` when that beast is still out there and standing on `mapId`, else nil.
function Roam.onMap(E, save, index, mapId)
  if index == nil or mapId == nil then return nil end
  local list = roster(save, E)
  local slot = type(list) == "table" and list[index] or nil
  if active(slot, E) and slot.map == mapId then return slot end
  return nil
end

--- Is `species` one of the beasts still out (not caught, not beaten)?
function Roam.isRoaming(E, save, species)
  local list = roster(save, E)
  for i = 1, 3 do
    local slot = type(list) == "table" and list[i] or nil
    if active(slot, E) and slot.species == species then return true end
  end
  return false
end

--- CheckEncounterRoamMon's roll for one visible spawn on `mapId`: { index, species, level, dvs,
--- hp } or nil. One random byte, three gates, as the engine rolls a step: below 100 of 256, the
--- low two bits pick slot 1-3 (0 = no beast), and that beast must be on this map -- about 1 spawn
--- in 10 per beast on its route. Water never rolls (the game refuses while surfing). DVs and HP
--- only once met (hp 0 = never met: the first battle rolls them).
function Roam.pickForSpawn(E, save, mapId, terrain, rng)
  if mapId == nil or terrain == "water" then return nil end
  local list = roster(save, E)
  if type(list) ~= "table" then return nil end
  local value = rand(rng, 256)
  if value >= 100 then return nil end
  local index = value % 4
  if index == 0 then return nil end
  local slot = list[index]
  if not (active(slot, E) and slot.map == mapId) then return nil end
  local met = (tonumber(slot.hp) or 0) > 0
  return { index = index, species = slot.species, level = tonumber(slot.level) or (E and tonumber(E.LEVEL)) or 40,
    dvs = met and slot.dvs or nil, hp = met and tonumber(slot.hp) or nil }
end

--- The engine's own roaming battle with beast `index` on the live World. `done(result)` runs
--- when it ends. Returns true, or nil plus a reason (moved on, no engine roamers, no world).
function Roam.startBattle(E, world, index, done)
  if not (E and type(E.beginBattle) == "function") then return nil, "engine roamers unavailable" end
  if not (world and type(world.startBattle) == "function") then return nil, "no world" end
  local game = world.game
  local save = game and game.save
  if not Roam.onMap(E, save, index, world.map and world.map.id) then return nil, "the beast is not on this map" end
  local beast = E.beginBattle(save, index, game.data)
  if not beast then return nil, "could not build the beast" end
  save.pokedex = save.pokedex or { seen = {}, caught = {} }
  save.pokedex.seen = save.pokedex.seen or {}
  save.pokedex.seen[beast.species] = true
  world:startBattle({ wild = beast, roaming = index }, function(result)
    if done then done(result) end
  end)
  return true
end

--- Puts `shouldBlock(save, mapId, onWater, random)` in front of Roamers.checkEncounter: when it
--- returns true no beast is rolled on that step. Installed once per process (engine modules
--- outlive a mod reload); the wrapper reads the CURRENT gate, so a reloaded mod just replaces it.
--- Returns a function that removes this gate, or nil plus a reason.
function Roam.installStepGate(E, shouldBlock)
  if not (E and type(E.checkEncounter) == "function") then return nil, "engine roamers unavailable" end
  if type(shouldBlock) ~= "function" then return nil, "the gate must be a function" end
  if not E._vwogStepGateInstalled then
    E._vwogOriginalCheckEncounter = E.checkEncounter
    E.checkEncounter = function(...)
      local gate = E._vwogStepGate
      if type(gate) == "function" then
        local ok, block = pcall(gate, ...)
        if ok and block == true then return nil end
      end
      return E._vwogOriginalCheckEncounter(...)
    end
    E._vwogStepGateInstalled = true
  end
  E._vwogStepGate = shouldBlock
  return function()
    if E._vwogStepGate == shouldBlock then E._vwogStepGate = nil end
  end
end

return Roam
