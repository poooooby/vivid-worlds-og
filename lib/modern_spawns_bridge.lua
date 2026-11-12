-- Modern Spawns bridge: visible spawns pick from the tables Modern Spawns generated, when that
-- mod is installed and active (ported from Wilds of Kanto Revival's lib/modern_spawns_bridge.lua).
--
-- The visible spawns pick their species straight from the encounter tables (lib/gb/gen1.lua,
-- lib/gb/gen2.lua roll), so Modern Spawns' encounter hooks never run for them. Modern Spawns
-- never rewrites the game's tables either; it publishes its own in each game's shape
-- (mod.exports.drawFor / tableFor, apiVersion >= 1). The adapters' rolls read through the views
-- below (EnginePatch.setTableView), so a map's visible Pokemon are the species Modern Spawns
-- would roll there. After the roll, apply() adds its LEGENDARIES roll and the shiny chain's
-- species, the same "keep the level, replace the species" Modern Spawns applies to a step.
--
-- Soft integration, no dependency: absent, OFF, another generation's tables or no table for a
-- map -> the game's own table passes through untouched.
local V = ...
local EnginePatch = V.require("engine_patch")

local Bridge = {}

-- Modern Spawns' exports when installed, active and answering for this generation, else nil.
function Bridge.api()
  local mod = V.mod
  if not (mod and type(mod.find) == "function") then return nil end
  local ok, other = pcall(mod.find, mod, "modern_spawns")
  local api = ok and other and other.exports
  if type(api) ~= "table" or (tonumber(api.apiVersion) or 0) < 1 then return nil end
  local okActive, active = pcall(api.isActive)
  if not (okActive and active) then return nil end
  local okGen, gen = pcall(api.generation)
  if not (okGen and gen ~= nil and gen == EnginePatch.generation()) then return nil end
  return api
end

-- One generated table for a map / terrain in the game's own shape, or nil. drawFor (Modern
-- Spawns 0.7.0+) answers RANDOM with a fresh draw per call: one call per pick.
function Bridge.table(mapId, terrain)
  local api = mapId ~= nil and Bridge.api() or nil
  if not api then return nil end
  local fn = api.drawFor or api.tableFor
  if type(fn) ~= "function" then return nil end
  local ok, t = pcall(fn, mapId, terrain)
  if ok and type(t) == "table" and type(t.slots) == "table" then return t end
  return nil
end

--- Red / Blue / Yellow: the map's definition { grass, water, ... } with Modern Spawns' tables
--- in place of the game's. The game's own table is never modified.
function Bridge.gen1Def(mapId, raw)
  if type(raw) ~= "table" then return raw end
  local grass = raw.grass and Bridge.table(mapId, "grass")
  local water = raw.water and Bridge.table(mapId, "water")
  if not (grass or water) then return raw end
  local def = {}
  for k, v in pairs(raw) do def[k] = v end
  if grass then def.grass = grass end
  if water then def.water = water end
  return def
end

-- Gold's kind-first tables, per map answered from Modern Spawns first: a read-only view the
-- engine's own Encounter.grassSlot / waterSlot index unchanged. An entry that differs from the
-- cart's (a swarm swapped in) is kept, as Modern Spawns does for steps.
local function kindView(rawKind, cartKind, terrain)
  return setmetatable({}, {
    __index = function(_, mapId)
      local base = rawKind and rawKind[mapId]
      if base == nil then return nil end
      if cartKind and cartKind[mapId] ~= base then return base end
      return Bridge.table(mapId, terrain) or base
    end,
  })
end

--- Gold / Silver / Crystal: `raw` (the live tables, swarms included) seen through Modern
--- Spawns; `cart` = the game's own. `raw` itself when Modern Spawns is not in play.
function Bridge.gen2Tables(raw, cart)
  if type(raw) ~= "table" or not Bridge.api() then return raw end
  cart = type(cart) == "table" and cart or raw
  return setmetatable({
    grass = kindView(raw.grass, cart.grass, "grass"),
    water = kindView(raw.water, cart.water, "water"),
  }, { __index = raw })
end

--- The view each generation's roll reads its tables through (EnginePatch.setTableView).
function Bridge.install()
  local gen = EnginePatch.generation()
  if gen == 1 then return EnginePatch.setTableView(Bridge.gen1Def) end
  if gen == 2 then return EnginePatch.setTableView(Bridge.gen2Tables) end
  return false
end

local function withSpecies(enc, species)
  local copy = {}
  for k, v in pairs(enc) do copy[k] = v end
  copy.species = species
  -- the DVs were drawn for the slot's species (Gold: an Unown's letter); the new one's
  -- come from the Shiny Rate when it is placed
  copy.dvs = nil
  return copy
end

-- a species id Modern Spawns names, when this game has it
local function known(id)
  return type(id) == "string" and EnginePatch.nationalFor(id) ~= nil and id or nil
end

--- `enc` (one visible spawn's roll) with Modern Spawns' LEGENDARIES roll or the shiny chain's
--- species in its place, or `enc` itself. A roaming beast is never replaced, and never offered
--- a second time while it is still out (caught, the Pokedex marks it owned and Modern Spawns
--- stops offering it). Never throws.
function Bridge.apply(mapId, terrain, enc)
  if type(enc) ~= "table" or enc.roamer or mapId == nil then return enc end
  local api = Bridge.api()
  if not api then return enc end
  local kind = terrain == "water" and "water" or "grass"
  if type(api.legendaryFor) == "function" then
    local ok, id = pcall(api.legendaryFor, mapId, kind)
    local species = ok and known(id) or nil
    if species and not EnginePatch.isRoamingSpecies(species) then return withSpecies(enc, species) end
  end
  if type(api.chainSpeciesFor) == "function" then
    local ok, id = pcall(api.chainSpeciesFor, mapId, kind)
    local species = ok and known(id) or nil
    if species then return withSpecies(enc, species) end
  end
  return enc
end

-- ------- shiny chains (Modern Spawns counts them; this mod makes the shinies)

--- What a shiny chain gives an encounter of `species`: { shiny = chance, perfectIvs = n }, or nil.
function Bridge.chainBonus(species)
  local api = Bridge.api()
  if not (api and type(api.chainBonus) == "function") then return nil end
  local ok, bonus = pcall(api.chainBonus, species)
  return (ok and type(bonus) == "table") and bonus or nil
end

--- A wild Pokemon beaten outside a real battle (the Battler's fights) counts like a battle won.
function Bridge.chainRecord(species, result)
  local api = Bridge.api()
  if api and type(api.chainRecord) == "function" then pcall(api.chainRecord, species, result) end
end

return Bridge
