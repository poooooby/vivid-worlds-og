-- Red / Blue / Yellow: the engine calls lib/engine_patch.lua needs, against Gen1Recomp's
-- Gen 1 overworld (src/world/OverworldController.lua, `ow` = the OverworldState). Every
-- call is guarded by the caller; nothing here keeps state.
local V = ...
local Shared = V.require("gb/shared")
local Gen1 = { generation = 1, layout = "gen1" }

-- the optional systems main.lua may build on this generation (EnginePatch.supports)
-- (battle_sparkle: Gen 1 battles have no shiny animation of their own; Gen 2's do)
Gen1.FEATURES = { wild_reacts = true, interaction = true, roles = true, battle_sparkle = true }

local load = function() return nil end
function Gen1.init(loadModule) load = loadModule end

local OW = "src.world.OverworldController"

-- wrapped (lib/engine_patch.lua install): the world pass, the per-frame update, the input poll
Gen1.TARGETS = {
  draw = { mod = OW, field = "drawWorld" },   -- draws ow.entities y-sorted (OverworldController.lua:6473)
  tick = { mod = OW, field = "update" },      -- the overworld's frame (OverworldController.lua:1408)
  input = { mod = OW, field = "handleInput" }, -- where a held direction starts a step (:1791)
  interact = { mod = OW, field = "interact" }, -- the A press (:2651): the follower menu goes first
  messageDraw = { mod = "src.render.TextBox", field = "draw" }, -- the portrait paints after the box
  -- a box on the stack PAUSES the overworld's update (Game routes to the top state only),
  -- which would freeze the mod's tick mid-conversation: tick from the box too (only one
  -- of the two is ever the running state, so never twice a frame)
  messageTick = { mod = "src.render.TextBox", field = "update" },
}
-- read (newWild is wrapped only by Gen1.installShiny, the Shiny Rate)
Gen1.READONLY = {
  newWild = { mod = "src.battle.BattleState", field = "newWild" },
  indoor = { mod = OW, field = "rollsIndoorEncounters" },
  isOutdoor = { mod = "src.world.Map", field = "isOutdoor" },
}

function Gen1.game()
  return load("src.core.Game")
end

function Gen1.data()
  local Game = Gen1.game()
  return Game and Game.data
end

function Gen1.save()
  local Game = Gen1.game()
  return Game and Game.save
end

function Gen1.camera(ow)
  local cam = ow and ow.camera
  if not cam then return nil end
  return cam.x or 0, cam.y or 0
end

function Gen1.viewSize(_ow)
  local Game = Gen1.game()
  local r = Game and Game.renderer
  if r and r.worldViewSize then
    local ok, w, h = pcall(r.worldViewSize, r)
    if ok and tonumber(w) and tonumber(h) then return w, h end
  end
  return 160, 144
end

--- Is something other than the player's free walking in charge? The update's own
--- `scripted` gate (OverworldController.lua:1667), the animations that return early
--- before it, a warp, and any screen pushed over the overworld (text, menus, a battle).
function Gen1.busy(ow)
  if not ow then return true end
  local Game = Gen1.game()
  if Game and Game.stack and Game.stack.top then
    local ok, top = pcall(Game.stack.top, Game.stack)
    if ok and top ~= ow then return true end
  end
  local runner = ow.runner
  if runner and runner.isRunning then
    local ok, running = pcall(runner.isRunning, runner)
    if ok and running then return true end
  end
  if ow.scriptMoves and #ow.scriptMoves > 0 then return true end
  if (ow.hopLand or 0) > 0 or (ow.poisonFlash or 0) > 0 then return true end
  return (ow.engaging or ow.emote or ow.teleportOut or ow.flyAnim or ow.flyArrive or ow.flyFade
    or ow.spinArrive or ow.holeFall or ow.holeArrive or ow.cutAnim or ow.healAnim or ow.pikaHop
    or ow.transitioning or (ow.dustAnim and ow.dustAnim.boulder)) and true or false
end

--- Gen 1's wild-encounter tiles (OverworldController.lua:4920): tall grass, water, and
--- -- on an indoor map whose tileset is not FOREST (caves, towers, the Mansion) -- every
--- floor tile. Returns "land" | "water" | nil.
function Gen1.terrainAt(ow, x, y)
  local map = ow and ow.map
  if not (map and map.inBounds and map:inBounds(x, y)) then return nil end
  if map:isGrassCell(x, y) then return "land" end
  if map:isWaterCell(x, y) then return "water" end
  local O = load(OW)
  local data = Gen1.data()
  if O and O.rollsIndoorEncounters and data and data.field then
    local ok, indoor = pcall(O.rollsIndoorEncounters, map.def, data.field.indoorEncounters)
    if ok and indoor and map:isWalkableCell(x, y) then return "land" end
  end
  return nil
end

-- Modern Spawns' tables in place of the game's (lib/modern_spawns_bridge.lua gen1Def), or nil
local tableView = nil
function Gen1.setTableView(view) tableView = view end

local function encDef(mapId)
  local data = Gen1.data()
  local all = data and data.encounters
  local def = type(all) == "table" and all[mapId] or nil
  if tableView and def then
    local ok, view = pcall(tableView, mapId, def)
    if ok and type(view) == "table" then return view end
  end
  return def
end

local function hasSlots(t)
  return type(t) == "table" and (tonumber(t.rate) or 0) > 0 and type(t.slots) == "table" and #t.slots > 0
end

--- The species def for a string key ("MAGIKARP") or a national dex number.
local dexToKey -- [dex] = key, built once
function Gen1.speciesDef(species)
  local data = Gen1.data()
  local mons = data and data.pokemon
  if type(mons) ~= "table" or species == nil then return nil, nil end
  if type(species) == "string" then return mons[species], species end
  local n = tonumber(species)
  if not n then return nil, nil end
  if not dexToKey then
    dexToKey = {}
    for key, def in pairs(mons) do
      local dex = type(def) == "table" and tonumber(def.dex)
      if dex and type(key) == "string" and dexToKey[dex] == nil then dexToKey[dex] = key end
    end
  end
  local key = dexToKey[n]
  return key and mons[key] or nil, key
end

-- a slot list with its species as NATIONAL DEX numbers (the ambient systems -- the sky,
-- the water -- collect species with tonumber(); the string keys stay for battles)
local function dexSlots(slots)
  local out
  for _, s in ipairs(slots or {}) do
    local def = type(s) == "table" and Gen1.speciesDef(s.species)
    local dex = def and tonumber(def.dex)
    if dex then
      out = out or {}
      out[#out + 1] = { species = dex, level = tonumber(s.level) or 5 }
    end
  end
  return out
end

--- The map's encounter areas, with slot lists for the ambient systems: `land` / `water`
--- = { slots = {{species = dex, level}, ...} } (true-ish, as the presence checks read it),
--- `fishing` = the rods' pools (Super Rod per map, Good Rod's pool, Old Rod's Magikarp).
function Gen1.tables(_ow, mapId)
  local def = encDef(mapId)
  local out = {}
  if hasSlots(def and def.grass) then out.land = { slots = dexSlots(def.grass.slots) } end
  if hasSlots(def and def.water) then out.water = { slots = dexSlots(def.water.slots) } end
  local data = Gen1.data()
  local FD = load("src.world.FieldDefaults")
  if data and FD and FD.field then
    -- the rods (OverworldController.lua fishingPool): Old always Magikarp, Good a fixed
    -- pool, Super the per-map groups under field[perMap]
    local okF, rods = pcall(FD.field, data, "fishing")
    local fish = {}
    for _, rod in pairs(okF and type(rods) == "table" and rods or {}) do
      if type(rod) == "table" then
        if type(rod.always) == "table" then fish[#fish + 1] = rod.always end
        for _, s in ipairs(type(rod.pool) == "table" and rod.pool or {}) do fish[#fish + 1] = s end
        local groups = rod.perMap and data.field and data.field[rod.perMap]
        local per = type(groups) == "table" and groups[mapId]
        for _, s in ipairs(type(per) == "table" and per or {}) do fish[#fish + 1] = s end
      end
    end
    local slots = dexSlots(fish)
    if slots then out.fishing = { slots = slots } end
  end
  return out
end

--- One encounter for `terrain` on `mapId`, picked with the game's own slot buckets
--- (Encounter.roll without its per-step rate gate): { species, level } or nil.
function Gen1.roll(_ow, mapId, terrain, rng)
  local def = encDef(mapId)
  if not def then return nil end
  local t
  if terrain == "water" then t = def.water else t = def.grass end
  if not hasSlots(t) then return nil end
  rng = rng or math.random
  local buckets = t.buckets
  if not buckets then
    local FD = load("src.world.FieldDefaults")
    local data = Gen1.data()
    if FD and FD.constant then
      local ok, b = pcall(FD.constant, data, "encounterBuckets")
      if ok and type(b) == "table" then buckets = b end
    end
    buckets = buckets or (FD and FD.CONSTANTS and FD.CONSTANTS.encounterBuckets)
  end
  if type(buckets) ~= "table" then return nil end
  local pick = rng(0, 255)
  for i, threshold in ipairs(buckets) do
    if pick < threshold then
      local slot = t.slots[i]
      if slot and slot.species then return { species = slot.species, level = tonumber(slot.level) or 5 } end
      return nil
    end
  end
  return nil
end

--- REPEL (OverworldController.lua:4935): no wild Pokemon weaker than the lead while it lasts.
function Gen1.repelAllows(_ow, level)
  local save = Gen1.save()
  if not (save and (tonumber(save.repelSteps) or 0) > 0) then return true end
  local lead = save.party and save.party[1]
  return not (lead and tonumber(level) and tonumber(lead.level) and level < lead.level)
end

-- ------------------------------------------------------------------ shiny (lib/shiny.lua)
-- Gen 1 has no shininess in the ROM; the engine's "virtual shiny" (Stats.isShiny) reads it from
-- the DVs the way Gen 2 does. BattleState.newWild builds its wild Pokemon with Pokemon.new
-- (BattleState.lua:879): while it runs, that one Pokemon gets the DVs of the visible spawn being
-- fought (handOff, from Gen1.startWild) or the Shiny Rate's (decideDvs). Nothing else is touched.
local handOff, inNewWild, decideDvs = nil, false, nil

function Gen1.shinyDvs(dvs)
  local Stats = load("src.pokemon.Stats")
  if not (Stats and Stats.isShiny and type(dvs) == "table") then return false end
  local ok, yes = pcall(Stats.isShiny, dvs)
  return ok and yes == true
end

function Gen1.isShiny(mon)
  if type(mon) ~= "table" then return false end
  return mon.shiny == true or Gen1.shinyDvs(mon.dvs)
end

-- `mon`, just built, takes `dvs`: its stats rebuilt from them, at full HP
local function giveDvs(data, mon, dvs)
  local d = mon.dvs
  if type(d) == "table" and d.attack == dvs.attack and d.defense == dvs.defense and d.speed == dvs.speed
    and d.special == dvs.special then return end
  mon.dvs = { attack = dvs.attack, defense = dvs.defense, speed = dvs.speed, special = dvs.special,
    hp = (dvs.attack % 2) * 8 + (dvs.defense % 2) * 4 + (dvs.speed % 2) * 2 + (dvs.special % 2) }
  local Stats = load("src.pokemon.Stats")
  local def = data and data.pokemon and data.pokemon[mon.species]
  if not (Stats and Stats.calc and def) then return end
  local ok, stats = pcall(Stats.calc, def, mon.level or 1, mon.dvs, mon.statExp)
  if ok and type(stats) == "table" then mon.stats, mon.hp = stats, stats.hp end
end

--- `decide(dvs, allowed, rng) -> dvs, shiny` for every wild Pokemon newWild builds. Once.
function Gen1.installShiny(decide)
  decideDvs = decide
  local Pokemon = load("src.pokemon.Pokemon")
  local BattleState = load("src.battle.BattleState")
  if not (Pokemon and Pokemon.new and BattleState and BattleState.newWild) then
    return false, "Gen 1 builders unavailable"
  end
  if not Pokemon._vwogShinyNew then
    local origNew = Pokemon.new
    Pokemon._vwogShinyNew = function(data, species, level, rng, ...)
      local mon = origNew(data, species, level, rng, ...)
      if not inNewWild or type(mon) ~= "table" then return mon end
      inNewWild = false -- the wild Pokemon is the one newWild builds
      local given = handOff
      handOff = nil
      local dvs = given and given.dvs
      if not given and decideDvs then
        local ok, d = pcall(decideDvs, mon.dvs, nil, type(rng) == "function" and rng or nil)
        dvs = ok and d or nil
      end
      if type(dvs) == "table" then giveDvs(data, mon, dvs) end
      -- worn down by the partner's Battler: the HP it has left
      local hp = given and tonumber(given.hp)
      if hp and hp > 0 and type(mon.stats) == "table" then mon.hp = math.min(math.floor(hp), mon.stats.hp) end
      mon.shiny = Gen1.shinyDvs(mon.dvs) or nil
      return mon
    end
    Pokemon.new = Pokemon._vwogShinyNew
  end
  if not BattleState._vwogShinyNewWild then
    local origNewWild = BattleState.newWild
    BattleState._vwogShinyNewWild = function(...)
      inNewWild = true
      local ok, battle = pcall(origNewWild, ...)
      inNewWild, handOff = false, nil
      if not ok then error(battle, 0) end
      return battle
    end
    BattleState.newWild = BattleState._vwogShinyNewWild
  end
  return true
end

--- The wild battle, built the way the engine's own step encounter builds it
--- (OverworldController.lua:4940): the ghost of the Pokemon Tower without the Silph
--- Scope, a Safari battle in the Safari Zone, afterBattle on the way out. The Pokemon
--- fought has the DVs the spawn rolled (its shininess) and the HP the Battler left it.
function Gen1.startWild(ow, enc, done)
  local Game = Gen1.game()
  local BattleState = load("src.battle.BattleState")
  if not (Game and ow and BattleState and BattleState.newWild and ow.pushBattle) then
    return nil, "Gen 1 battle unavailable"
  end
  handOff = { dvs = type(enc.dvs) == "table" and enc.dvs or nil, hp = enc.hp }
  local ok, battle = pcall(BattleState.newWild, Game, enc.species, tonumber(enc.level) or 5)
  handOff = nil
  if not ok or not battle then return nil, "newWild failed: " .. tostring(battle) end
  battle.checkpointOrigin = { kind = "wild_encounter", map = ow.map and ow.map.id }
  local Map = load("src.world.Map")
  local def = ow.map and ow.map.def
  if Map and def then
    if Gen1.wildMasked(ow) and battle.makeGhost then pcall(battle.makeGhost, battle) end
    local okS, safari = pcall(Map.inRegion, def, "SAFARI", "SAFARI_ZONE")
    if Game.save and Game.save.safari and okS and safari and battle.makeSafari then
      pcall(battle.makeSafari, battle, Game.save.safari)
    end
  end
  battle.onFinish = function(result)
    if ow.afterBattle then ow:afterBattle(result, battle) end
    if done then done(result) end
  end
  local okP, err = pcall(ow.pushBattle, ow, battle)
  if not okP then return nil, "pushBattle failed: " .. tostring(err) end
  return true
end

--- The Pokemon Tower's rule (Map.ghostBattles, read fresh): without the Silph Scope every wild
--- Pokemon here is an unidentifiable GHOST -- on the field too (lib/form_source.lua's ghost art).
function Gen1.wildMasked(ow)
  local Map, Game = load("src.world.Map"), Gen1.game()
  local def = ow and ow.map and ow.map.def
  if not (Map and Map.ghostBattles and def) then return false end
  local ok, ghost = pcall(Map.ghostBattles, def)
  if not (ok and ghost) then return false end
  local item = type(ghost) == "table" and ghost.unlessItem or nil
  local inv = Game and Game.save and Game.save.inventory
  return not (item and type(inv) == "table" and inv[item])
end

function Gen1.isSurfing(ow)
  local p = ow and ow.player
  return p ~= nil and p.surfing == true
end

function Gen1.isBiking(ow)
  local save = Gen1.save()
  return (save and save.onBike == true) or (ow and ow.player and ow.player.onBike == true) or false
end

--- Owned in the Pokedex (BattleState.markOwned writes `owned`).
function Gen1.isCaught(species)
  local save = Gen1.save()
  local dex = save and save.pokedex
  if not (dex and species) then return false end
  return (type(dex.owned) == "table" and dex.owned[species] == true)
    or (type(dex.caught) == "table" and dex.caught[species] == true)
end


function Gen1.isOutdoor(ow)
  local Map = load("src.world.Map")
  local def = ow and ow.map and ow.map.def
  if not (Map and Map.isOutdoor and def) then return true end
  local ok, out = pcall(Map.isOutdoor, def)
  return not ok or out == true
end

--- A town or city (the maps the Fly list knows, Map.isFlyTown): where the sky's birds
--- may perch. 1 town, 3 route, 4 a cave / dungeon, 8 a building -- the Gen 3 map-type numbers
--- the mod reads (Gen 2's environments give the same). Gen 1 names no caves: an indoor map
--- with wild encounters (Mt. Moon, Viridian Forest, Pokemon Tower, the Mansion ...) is a
--- dungeon, any other (a house, a Mart, a Pokemon Center) a building.
function Gen1.mapTypeOf(ow)
  if not Gen1.isOutdoor(ow) then
    local def = encDef(ow and ow.map and ow.map.id)
    return (def and (hasSlots(def.grass) or hasSlots(def.water))) and 4 or 8
  end
  local Map = load("src.world.Map")
  local def = ow and ow.map and ow.map.def
  if Map and Map.isFlyTown and def then
    local ok, town = pcall(Map.isFlyTown, def)
    if ok and town then return 1 end
  end
  return 3
end

--- Does `species` (string key or national dex) have `wanted` among its types?
function Gen1.hasType(species, wanted)
  local def = Gen1.speciesDef(species)
  for _, t in ipairs(def and def.types or {}) do
    if t == wanted then return true end
  end
  return false
end

--- Pokedex height in decimetres (the dex entry's feet and inches).
function Gen1.heightDm(species)
  local def = Gen1.speciesDef(species)
  local e = def and def.dexEntry
  if not e then return nil end
  local ft, inch = tonumber(e.heightFt), tonumber(e.heightIn)
  if not (ft or inch) then return nil end
  local m = (ft or 0) * 0.3048 + (inch or 0) * 0.0254
  return math.floor(m * 10 + 0.5)
end

--- The sum of the base stats (Gen 1's five).
function Gen1.baseStatTotal(species)
  local def = Gen1.speciesDef(species)
  local b = def and def.baseStats
  if type(b) ~= "table" then return nil end
  local sum = 0
  for _, v in pairs(b) do sum = sum + (tonumber(v) or 0) end
  return sum > 0 and sum or nil
end

--- The ids of the maps joined to this one (the live neighbour list the engine draws).
function Gen1.neighbourIds(ow)
  local out = {}
  for _, n in ipairs(ow and ow.neighbors or {}) do
    local id = type(n) == "table" and type(n.map) == "table" and n.map.id
    if id then out[#out + 1] = id end
  end
  return out
end

--- Is an engine character (an NPC, the follower, a boulder) on cell (x, y)?
function Gen1.objectOn(ow, x, y)
  for _, npc in ipairs(ow and ow.npcs or {}) do
    if npc.cellX == x and npc.cellY == y then return true end
    if npc.moving and npc.targetX == x and npc.targetY == y then return true end
  end
  return false
end

--- The map's signposts, { {x, y}, ... } (map def signs).
function Gen1.signCells(ow)
  local out = {}
  for _, s in ipairs(ow and ow.map and ow.map.def and ow.map.def.signs or {}) do
    if tonumber(s.x) and tonumber(s.y) then out[#out + 1] = { x = s.x, y = s.y } end
  end
  return out
end

function Gen1.playCry(species)
  local data = Gen1.data()
  local Sound = load("src.core.Sound")
  local _, key = Gen1.speciesDef(species)
  if not (data and Sound and Sound.playCry and key) then return nil end
  pcall(Sound.playCry, data, key)
end

-- emotion_bubbles.asm's crops by the names lib/emote_art.lua reads (Red / Blue: the first
-- three; Yellow: all eight)
local BUBBLE_NAMES = {
  EXCLAMATION_BUBBLE = "exclaim", QUESTION_BUBBLE = "question", SMILE_BUBBLE = "happy",
  SKULL_BUBBLE = "skull", HEART_BUBBLE = "heart", BOLT_BUBBLE = "bolt", ZZZ_BUBBLE = "sleep",
  FISH_BUBBLE = "fish",
}

--- The engine's emote bubbles as the sheet shape the mod reads: `quads` "!" frame 0 and "?"
--- frame 1 (lib/wild_emote.lua), `named` every bubble this game has by name (lib/emote_art.lua);
--- the OBJ-palette art re-shaded the way the engine's own emote draw does
--- (OverworldController.lua obpEmoteImage), built once.
local emoteSheet
function Gen1.emoteSheet()
  if emoteSheet ~= nil then return emoteSheet or nil end
  emoteSheet = false
  local data = Gen1.data()
  local bubble = data and data.field and data.field.emotionBubbles
  if not (bubble and bubble.path and love and love.graphics) then return nil end
  local Assets = load("src.render.Assets")
  local ok, sheet = pcall(function()
    local img
    if love.image and love.image.newImageData and Assets and Assets.imageData then
      local id = Assets.imageData(bubble.path)
      id:mapPixel(function(_, _, r, _, _, a)
        local v = 0
        if r > 0.5 then v = 1
        elseif r > 0.17 then v = 170 / 255 end
        return v, v, v, a
      end)
      img = love.graphics.newImage(id)
    elseif Assets and Assets.resolve then
      img = love.graphics.newImage(Assets.resolve(bubble.path))
    end
    if not img then return nil end
    local quads, named = {}, {}
    -- frames 0 ("!") and 1 ("?") are the engine's crops 1 EXCLAMATION, 2 QUESTION
    -- (emotion_bubbles.asm order)
    for i, rect in ipairs(bubble.bubbles or {}) do
      if rect.w then
        local q = love.graphics.newQuad(rect.x, rect.y, rect.w, rect.h, img:getDimensions())
        if i <= 2 then quads[i - 1] = q end
        local name = BUBBLE_NAMES[rect.name]
        if name then named[name] = q end
      end
    end
    return { image = img, quads = quads, named = named, fw = 16, fh = 16, frames = 2 }
  end)
  if ok and sheet then emoteSheet = sheet end
  return emoteSheet or nil
end

--- The input wrap: while `isHeld()` the overworld reads no input this frame, so a held
--- direction cannot start a step (handleInput is where it does, :1689).
function Gen1.inputWrapper(original, isHeld)
  return function(self, ...)
    if isHeld() then return end
    return original(self, ...)
  end
end

--- The per-frame wrap's world: OverworldState:update(dt)'s self.
function Gen1.tickWrapper(original, after)
  return function(self, ...)
    local a, b, c = original(self, ...)
    after(self, Gen1.game())
    return a, b, c
  end
end

--- The engine's party follower (Yellow's Pikachu; any mod's companion in Red / Blue):
--- PikachuFollower's npc, flagged `pikachuFollower`.
function Gen1.follower(ow)
  for _, npc in ipairs(ow and ow.npcs or {}) do
    if npc.pikachuFollower then return npc end
  end
  return nil
end

--- A map object's facts for lib/static_mons.lua: its object_event's name (CERULEANCAVEB1F_MEWTWO),
--- its static battle's species (`pokemon`) and the sheet it wears now (NPC:setAppearance).
function Gen1.npcFacts(ow, npc, out)
  local def = type(npc) == "table" and npc.def
  if type(def) ~= "table" or type(def.name) ~= "string" then return false end
  out.mapId = ow and ow.map and ow.map.id
  out.index, out.name, out.pokemon = def.index, def.name, def.pokemon
  out.sprite = npc.appearance or def.sprite
  out.spriteSpecies, out.script = nil, nil
  return true
end

--- The overworld that has `map` loaded: the state on top of the game's stack (it is pushed
--- before it loads its map), else nil.
function Gen1.liveWorld(game, map)
  game = game or Gen1.game()
  local stack = game and game.stack
  if not (stack and stack.top) then return nil end
  local ok, top = pcall(stack.top, stack)
  if ok and type(top) == "table" and top.player and top.map and (map == nil or top.map == map) then return top end
  return nil
end

function Gen1.party()
  local save = Gen1.save()
  return save and save.party
end

-- ------------------------------------------------------------------ talk / UI
-- The dialogue box is src/render/TextBox.lua, a state on Game.stack. The mod's own boxes
-- are tracked here so isMessageOpen sees a "stay" box under a menu, the way Gen 3's
-- Message does.

local ui = V.require("gb/ui").new(function() return Gen1.game() end, function() return load end)
local function stackTop() return ui.stackTop() end

--- Any dialogue box up: the stack's top, or the mod's own "stay" box under a menu.
function Gen1.isMessageOpen(_ow) return ui.isMessageOpen() end
--- The engine's own dialogue box (lib/gb/ui.lua): `opts.stay`, `opts.done`.
function Gen1.showMessage(_ow, text, opts) return ui.showMessage(nil, text, opts) end
function Gen1.messageOnLastPage(_ow) return ui.messageOnLastPage() end
function Gen1.closeStayMessage(_ow) return ui.closeStayMessage() end

--- The engine's list menu as Gen 3's Choice.multi: `cb(index)` 0-based, B -> cb(127).
function Gen1.showChoice(_ow, options, defaultIdx, cb)
  local Game = Gen1.game()
  local ListMenu = load("src.ui.ListMenu")
  if not (Game and Game.stack and ListMenu and ListMenu.new) then return false end
  local items = {}
  for i, label in ipairs(options or {}) do
    items[i] = { label = tostring(label) }
  end
  if #items == 0 then return false end
  -- itemBox: the small windowed list (the PC's), not the full-screen menu -- the report
  -- box and the world stay visible under it
  local ok, menu = pcall(ListMenu.new, Game, "", items, {
    itemBox = true,
    onChoose = function(item, m)
      ui.trackChoice(nil)
      if m and m.close then pcall(m.close, m) end
      local idx = 0
      for i, it in ipairs(items) do if it == item then idx = i - 1 break end end
      if cb then pcall(cb, idx) end
    end,
    onCancel = function()
      ui.trackChoice(nil)
      if cb then pcall(cb, 127) end
    end,
  })
  if not (ok and menu) then return false end
  if tonumber(defaultIdx) and defaultIdx >= 1 and defaultIdx < #items then menu.index = defaultIdx + 1 end
  local okP = pcall(Game.stack.push, Game.stack, menu)
  if not okP then return false end
  ui.trackChoice(menu)
  return true
end

function Gen1.choiceActive(_ow) return ui.choiceActive() end

--- The dialogue box's place in 8 px tiles ({ left, top, width, height }): the Gen 1 box
--- fills the screen's bottom six tile rows (0,12 .. 19,17 on 160x144).
function Gen1.dialogueWindow(_ow)
  return { left = 0, top = 12, width = 20, height = 6 }
end

--- Something owns the whole screen (a menu, a battle, a box): the overworld is not on top.
function Gen1.screenBusy(ow)
  local top = stackTop()
  return top ~= nil and top ~= ow
end

--- Mirrors the top of the engine's own interact: the overworld on top, nothing scripted,
--- the player standing still.
function Gen1.canStartInteraction(ow)
  if not ow or Gen1.busy(ow) then return false end
  if stackTop() ~= ow then return false end
  local p = ow.player
  return p ~= nil and not p.moving and not p.inputLocked
end

--- Yellow's own Pikachu talk (happiness faces) answers when the companion IS the starter
--- Pikachu: the A press passes through to the engine untouched.
function Gen1.nativeTalk(ow)
  local GV = load("src.core.GameVersion")
  local okY, yellow = pcall(GV and GV.isYellow)
  if not (okY and yellow) then return false end
  local save = Gen1.save()
  local lead = save and save.party and save.party[1]
  if not (lead and lead.species == "PIKACHU") then return false end
  local p = ow and ow.player
  local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  local d = p and DELTA[p.facing]
  if not d then return false end
  local npc = Gen1.follower(ow)
  return npc ~= nil and npc.cellX == p.cellX + d[1] and npc.cellY == p.cellY + d[2]
end

--- An A press the partner menu passed on (mid-step, busy, cooling down) that the engine would
--- still hand to the partner's npc: OverworldState:interact sends any `pikachuFollower` npc to
--- PikachuFollower.talk, Yellow's Pikachu talk, which errors on Red / Blue (no field.pikachu)
--- and would put Pikachu's faces on any other partner in Yellow. True = drop the press.
function Gen1.partnerPressBlocked(ow)
  if not (ow and ow.player and ow.player.facingCell and ow.npcAtCell) then return false end
  if Gen1.nativeTalk(ow) then return false end
  local okF, fx, fy = pcall(ow.player.facingCell, ow.player)
  if not okF then return false end
  local okN, npc = pcall(ow.npcAtCell, ow, fx, fy)
  return okN and type(npc) == "table" and npc.pikachuFollower == true
end

-- ------------------------------------------------------------------ roles
-- The Battler's skirmish, the Forager's bag, level-ups and the learn / evolve screens:
-- the Gen 1 answers to the engine facts lib/ow_combat.lua, lib/forage_items.lua and
-- lib/level_ready.lua ask for (the same contracts lib/engine_patch.lua serves on Gen 3).

Gen1.moveNumber = Shared.moveNumber
local moveKeyOf = Shared.moveKey

local function moveDef(id)
  local data = Gen1.data()
  local key = moveKeyOf(id)
  local row = key and data and type(data.moves) == "table" and data.moves[key]
  return type(row) == "table" and row or nil
end

--- { power, accuracy, type, pp } for an (interned) move id, or nil. Gen 1 stores
--- accuracy as a percent already, the shape lib/ow_combat.lua rolls against.
function Gen1.moveRow(id)
  local row = moveDef(id)
  if not row then return nil end
  return { power = tonumber(row.power) or 0, accuracy = tonumber(row.accuracy) or 0,
           type = row.type, pp = tonumber(row.pp) or 0 }
end

-- the battle's own ruleset (the save's pick, else gen1_faithful): Damage.compute
-- reads its crit / random-factor / zero-damage rules
local function rulesetOf()
  local data = Gen1.data()
  local save = Gen1.save()
  local rulesets = data and data.rulesets
  local selected = save and save.options and save.options.ruleset
  local rs = rulesets and (selected and rulesets[selected] or rulesets.gen1_faithful)
  if type(rs) == "table" then return rs end
  local M = load("src.battle.rulesets.gen1_faithful")
  return type(M) == "table" and M or nil
end

--- The battler shape src/battle/Damage.compute reads: the mon, its species def,
--- fresh stages, current stats / types, the status registry (a real burn or
--- paralysis keeps its Gen 1 stat penalty). Mirrors `maxHp` onto the mon (the
--- health bars and lib/ow_combat.lua read it; Gen 1 mons carry only stats.hp).
function Gen1.battlerOf(mon)
  local data = Gen1.data()
  local def = Gen1.speciesDef(mon.species)
  local Stats = load("src.pokemon.Stats")
  if def and Stats and Stats.ensure then pcall(Stats.ensure, def, mon) end
  if type(mon.stats) == "table" and tonumber(mon.stats.hp) then mon.maxHp = mon.stats.hp end
  return {
    mon = mon,
    def = def,
    name = Gen1.displayName(mon),
    statuses = data and data.statuses,
    stages = {},
    curStats = type(mon.stats) == "table" and mon.stats or {},
    curTypes = def and def.types or {},
    curMoves = mon.moves,
    level = mon.level,
  }
end

--- The engine's damage formula between two battlers; `rng(lo, hi)`. Returns
--- damage, { critical, effectiveness } (nil on any trouble).
function Gen1.moveDamage(attacker, defender, moveId, rng, noCrit)
  local Damage = load("src.battle.Damage")
  local move = moveDef(moveId)
  local ruleset = rulesetOf()
  if not (Damage and Damage.compute and move and ruleset) then return nil end
  local opts = { rng = rng }
  if noCrit then opts.forceCrit = false end -- (`x and false or nil` would collapse to nil)
  local ok, dmg, info = pcall(Damage.compute, ruleset, attacker, defender, move, opts)
  if not ok then return nil end
  return tonumber(dmg), {
    critical = type(info) == "table" and info.crit or false,
    effectiveness = (type(info) == "table" and tonumber(info.typeMult) or 10) / 10,
  }
end

--- A wild Pokemon built for an overworld skirmish: the engine's own constructor
--- (moves and PP from the learnset, random DVs -- the same roll the engine's
--- step battle makes), hp full, `maxHp` set.
function Gen1.buildWildFighter(species, level, dvs)
  local data = Gen1.data()
  local Pokemon = load("src.pokemon.Pokemon")
  local def, key = Gen1.speciesDef(species)
  if not (data and Pokemon and Pokemon.new and def and key) then return nil end
  local ok, mon = pcall(Pokemon.new, data, key, tonumber(level) or 5)
  if not (ok and type(mon) == "table") then return nil end
  if not (type(mon.moves) == "table" and #mon.moves > 0) then return nil end
  if type(dvs) == "table" then giveDvs(data, mon, dvs) end -- the spawn's own (its real battle's)
  mon.maxHp = type(mon.stats) == "table" and tonumber(mon.stats.hp) or nil
  if not mon.maxHp or mon.maxHp <= 0 then return nil end
  mon.hp = mon.maxHp
  return mon
end

--- EXP a wild `species` at `level` is worth (one participant, the engine's formula).
function Gen1.expGain(species, level)
  local def = Gen1.speciesDef(species)
  local Experience = load("src.battle.Experience")
  local data = Gen1.data()
  if not (def and Experience and Experience.gainFor) then return 0 end
  local ok, n = pcall(Experience.gainFor, def, tonumber(level) or 1, false, 1, false,
    data and data.constants)
  return ok and tonumber(n) or 0
end

--- Gives `amount` EXP to a party mon, levelling it the way the engine's own
--- Experience.apply does (Growth curve, Stats.calc per level, the HP delta kept,
--- the `pokemon.level_up` event). Returns { gained, fromLevel, toLevel } or nil.
function Gen1.expApply(mon, amount)
  local data = Gen1.data()
  local def = Gen1.speciesDef(mon and mon.species)
  local Growth = load("src.pokemon.Growth")
  local Stats = load("src.pokemon.Stats")
  if not (data and def and Growth and Stats and type(mon) == "table") then return nil end
  amount = math.max(0, math.floor(tonumber(amount) or 0))
  local from = tonumber(mon.level) or 1
  local cap = (data.constants and tonumber(data.constants.levelCap)) or 100
  mon.exp = (tonumber(mon.exp) or 0) + amount
  local okTop, top = pcall(Growth.expForLevel, def.growthRate, cap, data.growth_rates)
  if okTop and tonumber(top) and mon.exp > top then mon.exp = top end
  local okL, newLevel = pcall(Growth.levelForExp, def.growthRate, mon.exp, cap, data.growth_rates)
  if not (okL and tonumber(newLevel)) then return { gained = amount, fromLevel = from, toLevel = from } end
  local Experience = load("src.battle.Experience")
  local Runtime = load("src.mods.Runtime")
  while (tonumber(mon.level) or cap) < math.min(newLevel, cap) do
    mon.level = mon.level + 1
    local old = mon.stats
    local okS, stats = pcall(Stats.calc, def, mon.level, mon.dvs or {}, mon.statExp)
    if okS and type(stats) == "table" then
      mon.stats = stats
      mon.hp = math.min(stats.hp, (tonumber(mon.hp) or 0) + (stats.hp - (type(old) == "table" and old.hp or stats.hp)))
      mon.maxHp = stats.hp
    end
    if Runtime and Runtime.wants and Runtime.emit and Runtime.wants("pokemon.level_up") then
      pcall(Runtime.emit, "pokemon.level_up", {
        mon = mon, level = mon.level, prevLevel = mon.level - 1,
        learnable = (Experience and Experience.movesLearnedAt) and Experience.movesLearnedAt(def, mon.level) or {},
      })
    end
  end
  return { gained = amount, fromLevel = from, toLevel = mon.level }
end

--- Moves the species learns at exactly `level` (string ids; the learnset rule the
--- engine's own level-up uses).
function Gen1.movesLearnedAt(mon, level)
  local def = Gen1.speciesDef(type(mon) == "table" and mon.species)
  local Experience = load("src.battle.Experience")
  if not (def and Experience and Experience.movesLearnedAt) then return {} end
  local ok, list = pcall(Experience.movesLearnedAt, def, tonumber(level) or 0)
  return (ok and type(list) == "table") and list or {}
end

Gen1.knowsMove = Shared.knowsMove

--- What `mon` evolves into right now by LEVEL (never a stone or a trade), or nil.
function Gen1.evolutionTarget(mon)
  local Game = Gen1.game()
  local Evolution = load("src.pokemon.Evolution")
  if not (Game and Evolution and Evolution.pendingFor and type(mon) == "table") then return nil end
  local ok, species = pcall(Evolution.pendingFor, Game, mon, { kind = "levelup" })
  if ok and species then return species end
  return nil
end

--- The engine's own evolution movie (the player may B-cancel it, as after a
--- battle). Returns false -- and never calls `onDone` -- when nothing can evolve.
function Gen1.startEvolution(mon, _target, onDone)
  local Game = Gen1.game()
  local Evolution = load("src.pokemon.Evolution")
  if not (Game and Evolution and Evolution.request) then return false end
  if Gen1.evolutionTarget(mon) == nil then return false end
  local ok, species = pcall(Evolution.request, Game, mon, { kind = "levelup" }, onDone)
  return ok and species ~= nil
end

--- The level-up learn flow for the recorded `moveIds`, one at a time, the way the
--- engine's own Evolution.learnEvolutionMoves runs it: a free slot learns with the
--- jingle box, a full moveset opens the engine's forget screen (MoveLearnMenu).
--- `onDone(learnedAny)` once the chain ends. Returns false -- and never calls
--- `onDone` -- when no move in the list can open anything.
function Gen1.startMoveLearn(mon, moveIds, onDone)
  local Game = Gen1.game()
  local data = Gen1.data()
  local TextBox = load("src.render.TextBox")
  local Screens = load("src.ui.Screens")
  if not (Game and Game.stack and data and TextBox and Screens
      and type(mon) == "table" and type(mon.moves) == "table"
      and type(moveIds) == "table" and #moveIds > 0) then return false end
  -- anything to do at all? (every id already known / unknown -> false, onDone never runs)
  local any = false
  for _, id in ipairs(moveIds) do
    if moveDef(id) and not Gen1.knowsMove(mon, id) then any = true break end
  end
  if not any then return false end
  local i, learnedAny = 0, false
  local function nextStep()
    i = i + 1
    if moveIds[i] == nil then
      if onDone then pcall(onDone, learnedAny) end
      return
    end
    local key = moveKeyOf(moveIds[i])
    local mdef = key and data.moves[key]
    if not mdef or Gen1.knowsMove(mon, key) then return nextStep() end
    if #mon.moves < 4 then
      table.insert(mon.moves, { id = key, pp = tonumber(mdef.pp) or 0 })
      local Pika = load("src.world.PikachuFollower")
      if Pika and Pika.onMoveLearned then pcall(Pika.onMoveLearned, Gen1.save(), mon, key) end
      local Runtime = load("src.mods.Runtime")
      if Runtime and Runtime.emit then pcall(Runtime.emit, "pokemon.move_learned", { mon = mon, moveId = key }) end
      learnedAny = true
      local text = string.format("%s learned\n%s!", Gen1.displayName(mon), mdef.name or key)
      local okB, box = pcall(TextBox.new, Game, text, nextStep,
        TextBox.soundOpts and TextBox.soundOpts(Game, "Get_Item1") or nil)
      if okB and box then
        pcall(Game.stack.push, Game.stack, box)
      else
        nextStep()
      end
    else
      local okP = pcall(Screens.push, Game, "MoveLearnMenu", mon, key, function(learned)
        if learned then learnedAny = true end
        nextStep()
      end)
      if not okP then nextStep() end
    end
  end
  nextStep()
  return true
end

--- Every item the Forager may consider, in the entry shape lib/forage_items.lua
--- reads. Gen 1's data carries only { id, name, price, keyItem }: the pocket, use
--- kind and TM / HM / stone flags are derived (key items -> KEY_ITEMS, a priced
--- "... BALL" -> POKE_BALLS, names "TM## / HM##", the five stones).
function Gen1.itemCatalog()
  local data = Gen1.data()
  local items = data and data.items
  local out = {}
  if type(items) ~= "table" then return out end
  for id, row in pairs(items) do
    if type(row) == "table" and type(row.name) == "string" and row.name ~= "" then
      local name = row.name
      local price = tonumber(row.price) or 0
      local pocket = "ITEMS"
      if row.keyItem then pocket = "KEY_ITEMS"
      elseif price > 0 and name:upper():match("BALL$") then pocket = "POKE_BALLS" end
      out[#out + 1] = {
        id = row.id or id, name = name, pocket = pocket, price = price,
        use = Shared.USE_OF[row.id or id] or "none",
        isHm = name:match("^HM%d") ~= nil, isTm = name:match("^TM%d") ~= nil,
        isEvo = Shared.EVO[row.id or id] == true,
      }
    end
  end
  table.sort(out, function(a, b) return tostring(a.id) < tostring(b.id) end)
  return out
end

--- The bag, by the game's own rules (Gen 1's single 20-slot bag, 99 a stack).
function Gen1.bagAdd(id, qty) return Shared.bagAdd(load("src.inventory.Bag"), Gen1.save(), Gen1.data(), id, qty) end
function Gen1.bagCanAdd(id, qty)
  return Shared.bagCanAdd(load("src.inventory.Bag"), Gen1.save(), Gen1.data(), id, qty)
end

-- the battle's own hit sounds (EffectRegistry) and faint thud, for EnginePatch.playSeNamed
Gen1.SFX = { SE_EFFECTIVE = "Damage", SE_SUPER_EFFECTIVE = "Super_Effective",
  SE_NOT_EFFECTIVE = "Not_Very_Effective", KO = "Faint_Thud", BALL_POOF = "Ball_Poof" }

--- EXP.ALL is a bag item in Gen 1: carried, every party Pokemon shares a win.
function Gen1.holdsExpShare(_mon)
  local save = Gen1.save()
  return save ~= nil and type(save.inventory) == "table" and (tonumber(save.inventory.EXP_ALL) or 0) > 0
end

--- The found-it jingle / the menu click (the engine's own sound effects).
function Gen1.playSuccess()
  local Sound = load("src.core.Sound")
  local data = Gen1.data()
  if not (Sound and Sound.play and data) then return false end
  pcall(Sound.play, data, "Get_Item1")
  return true
end

function Gen1.playSelect()
  local Sound = load("src.core.Sound")
  local data = Gen1.data()
  if not (Sound and Sound.play and data) then return false end
  pcall(Sound.play, data, "Press_AB")
  return true
end

--- Width in px of `text` in the engine's font (every glyph is 8 px in Gen 1's,
--- but pen codes make Font.width the one true answer).
function Gen1.measureText(text) return Shared.measureText(load("src.render.Font"), text) end

--- Draws `text` with the engine's font at (x, y), top-left, in the dark text colour the
--- engine's own menus use (a "+" as a drawn cross); returns the width.
function Gen1.drawText(text, x, y) return Shared.drawText(load("src.render.Font"), text, x, y) end

--- The engine's little dust puff (one 8x8 tile) as the sheet shape
--- lib/hit_effect.lua reads; its three frame indexes all land on the one frame.
local dustSheet
function Gen1.dustSheet()
  if dustSheet ~= nil then return dustSheet or nil end
  dustSheet = false
  local data = Gen1.data()
  local smoke = data and data.field and data.field.overworldFx and data.field.overworldFx.smoke
  if not (smoke and smoke.path and love and love.graphics) then return nil end
  local Assets = load("src.render.Assets")
  local ok, sheet = pcall(function()
    local path = Assets and Assets.resolve and Assets.resolve(smoke.path) or smoke.path
    local img = love.graphics.newImage(path)
    local iw, ih = img:getDimensions()
    local fh = tonumber(smoke.height) or 8
    local n = math.max(1, math.floor(ih / fh))
    local quads = {}
    for i = 0, 2 do
      local f = math.min(i, n - 1)
      quads[i] = love.graphics.newQuad(0, f * fh, iw, fh, iw, ih)
    end
    return { image = img, quads = quads, fw = iw, fh = fh, frames = 3 }
  end)
  if ok and sheet then dustSheet = sheet end
  return dustSheet or nil
end

--- The mon's display name: its nickname, else the species name.
function Gen1.displayName(mon)
  if type(mon) ~= "table" then return "POKeMON" end
  if type(mon.nickname) == "string" and mon.nickname ~= "" then return mon.nickname end
  local def = Gen1.speciesDef(mon.species)
  local name = def and def.name
  if type(name) == "string" and name ~= "" then return name end
  return type(mon.species) == "string" and mon.species or "POKeMON"
end

-- ------------------------------------------------------------------ Safari Zone
--- In a Safari Zone visit (the same test Gen1.startWild uses to make a battle a Safari one):
--- wild Pokemon still show and battle as Safari Pokemon, but the Battler leaves them be.
function Gen1.safariActive(ow)
  local Game = Gen1.game()
  local Map = load("src.world.Map")
  local def = ow and ow.map and ow.map.def
  if not (Game and Game.save and Game.save.safari and Map and Map.inRegion and def) then return false end
  local ok, inside = pcall(Map.inRegion, def, "SAFARI", "SAFARI_ZONE")
  return ok and inside == true
end

--- How likely (%) this Safari Pokemon is to run: the battle's own turn check
--- (BattleState:safariEnemyTurn, engine/battle/core.asm) -- always past Speed 127, else
--- 2 x Speed in 256 -- on the Speed it will have in its battle (its DVs, no stat exp).
function Gen1.safariFleeChance(species, level, dvs)
  local Stats, def = load("src.pokemon.Stats"), Gen1.speciesDef(species)
  if not (Stats and Stats.calc and def) then return 0 end
  dvs = type(dvs) == "table" and dvs or { attack = 8, defense = 8, speed = 8, special = 8 }
  local ok, stats = pcall(Stats.calc, def, tonumber(level) or 5, dvs, {})
  local speed = ok and type(stats) == "table" and tonumber(stats.speed)
  if not speed then return 0 end
  speed = speed % 256
  if speed > 127 then return 100 end
  return speed * 2 / 256 * 100
end

-- ------------------------------------------------------------------ reachable area
-- A step function for lib/reachability.lua over Red / Blue / Yellow's own movement rules
-- (Collision's verdict, minus the entities, and OverworldState:checkLedgeHop):
--   * a step lands on a walkable cell (water too while the player surfs) and does not cross a
--     blocked tile pair (the cave / forest elevation edges, Collision.pairBlocked);
--   * a step onto a ledge tile hops TWO cells, exactly where the engine's ledge table
--     (data.field.ledges: tileset, facing, standing tile, ledge tile) lets the player jump;
--   * a warp cell is a hole: stepping on it leaves the map, so nothing behind it is reached.
-- Surfing is the start state's: a player already on the water can cross it.
local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
-- the mover Collision.pairBlocked reads (only `.surfing`): two shared ones, not a new table for
-- every step the flood fill tries (4 a cell, thousands a re-measure)
local SURFER, WALKER = { surfing = true }, { surfing = false }

function Gen1.reachMover(ow)
  local map = ow and ow.map
  if not (map and map.inBounds and map.isWalkableCell and map.cellTile and map.def) then return nil end
  local Collision = load("src.world.Collision")
  local pairBlocked = Collision and Collision.pairBlocked
  local data = Gen1.data()
  local ledges = data and data.field and data.field.ledges or {}
  local tileset = map.def.tileset
  local function floor(x, y, surfing)
    if not map:inBounds(x, y) then return false end
    if map.warpAtCell and map:warpAtCell(x, y) then return false end
    if map:isWalkableCell(x, y) then return true end
    return surfing == true and map.isWaterCell ~= nil and map:isWaterCell(x, y)
  end
  return function(x, y, dir, state)
    local d = DELTA[dir]
    if not d then return nil end
    local surfing = state and state.surfing
    local tx, ty = x + d[1], y + d[2]
    if not map:inBounds(tx, ty) then return nil end
    local standing, front = map:cellTile(x, y), map:cellTile(tx, ty)
    for _, ledge in ipairs(ledges) do
      if (ledge.tileset or "OVERWORLD") == tileset and ledge.facing == dir and ledge.input == dir
          and ledge.standingTile == standing and ledge.ledgeTile == front then
        local lx, ly = tx + d[1], ty + d[2]
        if floor(lx, ly, false) then return lx, ly, state end
        return nil
      end
    end
    if not floor(tx, ty, surfing) then return nil end
    if pairBlocked and pairBlocked(map, surfing and SURFER or WALKER, x, y, tx, ty) then return nil end
    return tx, ty, state
  end
end

return Gen1
