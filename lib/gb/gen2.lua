-- Gold / Silver / Crystal: the engine calls lib/engine_patch.lua needs, against Gen1Recomp's
-- Gen 2 overworld (src/world/gen2/World.lua, `world` = the World). Every call is guarded
-- by the caller; nothing here keeps state.
local V = ...
local Shared = V.require("gb/shared")
local Gen2 = { generation = 2, layout = "gen2" }

-- the optional systems main.lua may build on this generation (EnginePatch.supports)
Gen2.FEATURES = { interaction = true, wild_reacts = true, roles = true }

local load = function() return nil end
local liveWorld = function() return nil end
--- `currentWorld()`: the live World, for the calls that come without one (the roles).
function Gen2.init(loadModule, currentWorld)
  load = loadModule
  if currentWorld then liveWorld = currentWorld end
end

local WORLD = "src.world.gen2.World"

-- wrapped (lib/engine_patch.lua install): the people pass, the logic step, the input poll
Gen2.TARGETS = {
  draw = { mod = WORLD, field = "drawPeople" }, -- draws world.npcs y-sorted (World.lua:11727)
  tick = { mod = WORLD, field = "step" },       -- one logic frame (World.lua:11321)
  input = { mod = WORLD, field = "pollInput" }, -- the held direction (World.lua:11553)
  interact = { mod = WORLD, field = "interact" }, -- the A press (World.lua:8976): the partner menu goes first
  -- a box on the stack pauses World:step (Game2 runs the top state only): tick from the box
  -- too, so the interaction's state machine and the spawns keep moving mid-conversation
  messageTick = { mod = "src.render.TextBox", field = "update" },
}
-- optional: where a render pipeline mod (Stadium2) draws the world (World.lua:11864)
Gen2.PIPELINE = { mod = WORLD, field = "drawPipeline" }
-- read (Mon.new is wrapped only by Gen2.installShiny, the Shiny Rate)
Gen2.READONLY = {
  grassSlot = { mod = "src.battle.gen2.Encounter", field = "grassSlot" },
  waterSlot = { mod = "src.battle.gen2.Encounter", field = "waterSlot" },
  monNew = { mod = "src.battle.gen2.Mon", field = "new" },
  randomDVs = { mod = "src.battle.gen2.Mon", field = "randomDVs" },
  canEncounter = { mod = "src.world.gen2.FieldMoves", field = "canEncounterWildMon" },
  encounterTable = { mod = "src.world.gen2.FieldMoves", field = "encounterTable" },
  startBattle = { mod = WORLD, field = "startBattle" },
}

function Gen2.game(world)
  return world and world.game
end

function Gen2.data(world)
  local game = world and world.game
  return game and game.data
end

function Gen2.save(world)
  local game = world and world.game
  return game and game.save
end

function Gen2.camera(world)
  local cam = world and world.camera
  if not cam then return nil end
  return cam.x or 0, cam.y or 0
end

function Gen2.viewSize(world)
  return tonumber(world and world.viewW) or 160, tonumber(world and world.viewH) or 144
end

--- Is something other than the player's free walking in charge? World:busy() (a script,
--- text, a choice, a field move, Fly ...), a battle, or any screen on the game's stack:
--- Game2 only steps the world while the stack is empty (Game2.lua:1316).
function Gen2.busy(world)
  if not world then return true end
  local game = world.game
  if game then
    if game.phase ~= nil and game.phase ~= "play" then return true end
    local stack = game.stack
    if stack and stack.top then
      local ok, top = pcall(stack.top, stack)
      if ok and top ~= nil then return true end
    end
  end
  if world.battleActive or world.mapSetup ~= nil then return true end
  if world.busy then
    local ok, busy = pcall(world.busy, world)
    if ok and busy then return true end
  end
  return false
end

--- Gen 2's wild-encounter tiles (World:tryWildEncounter, World.lua:4498): the tile's
--- collision byte allows an encounter (grass and water; in a cave or dungeon any tile
--- but ice), and the table is water on a water tile. Returns "land" | "water" | nil.
function Gen2.terrainAt(world, x, y)
  local map = world and world.map
  if not (map and map.inBounds and map:inBounds(x, y)) then return nil end
  local FieldMoves = load("src.world.gen2.FieldMoves")
  if not (FieldMoves and FieldMoves.canEncounterWildMon and FieldMoves.encounterTable) then return nil end
  local coll = map:cellCollision(x, y)
  local env = map.def and map.def.environment
  local okE, can = pcall(FieldMoves.canEncounterWildMon, env, coll, world.noWildEncounters)
  if not (okE and can) then return nil end
  local okT, kind = pcall(FieldMoves.encounterTable, coll)
  if okT and kind == "water" then
    return map:isWaterCell(x, y) and "water" or nil
  end
  -- a cave allows every collision byte but ice: keep to the floor
  return map:isWalkableCell(x, y) and "land" or nil
end

-- Modern Spawns' tables in place of the game's (lib/modern_spawns_bridge.lua gen2Tables), or nil
local tableView = nil
function Gen2.setTableView(view) tableView = view end

local function wildTables(world)
  if not world then return nil end
  local t = world.encounters
  if world.wildTables then
    local ok, live = pcall(world.wildTables, world)
    if ok and type(live) == "table" then t = live end
  end
  if tableView and type(t) == "table" then
    -- the cart's own tables tell a swarm's entry (kept as is) from the map's usual one
    local ok, view = pcall(tableView, t, world.encounters)
    if ok and type(view) == "table" then return view end
  end
  return t
end

-- ------------------------------------------------------------------ roaming beasts
local Roam = V.require("gb/roamers")
local function roamers() return load("src.core.gen2.Roamers") end

--- Beast `index` as it is NOW when it is still on this map ({ species, level, dvs, hp, roamer }), else nil.
function Gen2.roamerNow(world, index)
  local save = Gen2.save(world)
  local slot = Roam.onMap(roamers(), save, index, world and world.map and world.map.id)
  if not slot then return nil end
  local met = (tonumber(slot.hp) or 0) > 0
  return { species = slot.species, level = tonumber(slot.level) or 40, roamer = index,
    dvs = met and slot.dvs or nil, hp = met and tonumber(slot.hp) or nil }
end

--- Is `species` a roaming beast still out there (Modern Spawns never offers a second one)?
function Gen2.isRoamingSpecies(world, species)
  return Roam.isRoaming(roamers(), Gen2.save(world), species)
end

--- With Classic Enc off no beast jumps the player on a step either (lib/gb/roamers.lua).
function Gen2.installRoamerGate(shouldBlock)
  return Roam.installStepGate(roamers(), shouldBlock)
end

--- Which Unown letter these DVs make (1 = A .. 26 = Z), or nil for any other species.
function Gen2.unownLetter(species, dvs)
  local Unown = load("src.core.gen2.Unown")
  if not (Unown and species == Unown.SPECIES and type(dvs) == "table") then return nil end
  local ok, letter = pcall(Unown.letterFromDVs, dvs)
  return ok and tonumber(letter) or nil
end

--- { land = bool, water = bool } for the map's encounter table.
function Gen2.tables(world, mapId)
  local t = wildTables(world)
  local grass = t and t.grass and t.grass[mapId]
  local water = t and t.water and t.water[mapId]
  return { land = type(grass) == "table" and grass.slots ~= nil, water = type(water) == "table" and water.slots ~= nil }
end

--- One encounter for `terrain` on `mapId` with the engine's own slot pick (the time of
--- day's grass list, or the water list), DVs rolled now so the Pokemon shown -- shiny,
--- Unown letter -- is the one met: { species, level, dvs } or nil. An Unown slot with no
--- Ruins of Alph puzzle solved is no encounter, as on the cart.
function Gen2.roll(world, mapId, terrain, _rng)
  local Encounter = load("src.battle.gen2.Encounter")
  local Mon = load("src.battle.gen2.Mon")
  local t = wildTables(world)
  if not (Encounter and Mon and t) then return nil end
  -- CheckEncounterRoamMon comes first: on its route a beast replaces the map's pick
  local beast = Roam.pickForSpawn(roamers(), Gen2.save(world), mapId, terrain)
  if beast then
    return { species = beast.species, level = beast.level, dvs = beast.dvs, hp = beast.hp, roamer = beast.index }
  end
  local ok, hit
  if terrain == "water" then
    ok, hit = pcall(Encounter.waterSlot, t, mapId, nil)
  else
    ok, hit = pcall(Encounter.grassSlot, t, mapId, world.tod, nil)
  end
  if not (ok and type(hit) == "table" and hit.species) then return nil end
  local enc = { species = hit.species, level = tonumber(hit.level) or 5 }
  local Unown = load("src.core.gen2.Unown")
  if Unown and hit.species == Unown.SPECIES then
    local flags = world.unownUnlockFlags and select(2, pcall(world.unownUnlockFlags, world))
    if not (type(flags) == "table" and Unown.anyUnlocked(flags)) then return nil end
    local okD, dvs = pcall(Unown.wildDVs, flags, Mon.randomDVs)
    enc.dvs = okD and dvs or nil
  else
    local okD, dvs = pcall(Mon.randomDVs)
    enc.dvs = okD and dvs or nil
  end
  return enc
end

--- CheckRepelEffect (World:repelSuppresses).
function Gen2.repelAllows(world, level)
  if not (world and world.repelSuppresses) then return true end
  local ok, suppressed = pcall(world.repelSuppresses, world, level)
  return not (ok and suppressed)
end

-- the Shiny Rate (Gen2.installShiny): the decider, the live World, and "this Mon.new is a visible
-- spawn's own battle" (its DVs were settled when it appeared)
local decideDvs, worldOf, ownBuild = nil, nil, false

--- The wild battle, the way World:tryWildEncounter starts one: Mon.new with the DVs the
--- spawn rolled (so its shininess) and the HP the Battler left it, seen in the Pokedex,
--- World:startBattle.
function Gen2.startWild(world, enc, done)
  local Mon = load("src.battle.gen2.Mon")
  local game = world and world.game
  if not (Mon and game and world.startBattle) then return nil, "Gen 2 battle unavailable" end
  -- a roaming beast: the engine's own roaming battle (its saved HP and DVs, banked afterwards)
  if enc.roamer then return Roam.startBattle(roamers(), world, enc.roamer, done) end
  local dvs
  if type(enc.dvs) == "table" then
    dvs = { attack = enc.dvs.attack, defense = enc.dvs.defense, speed = enc.dvs.speed, special = enc.dvs.special }
  end
  ownBuild = true
  local ok, wild = pcall(Mon.new, game.data, enc.species, tonumber(enc.level) or 5, { wild = true, dvs = dvs })
  ownBuild = false
  if not (ok and wild) then return nil, "Mon.new failed: " .. tostring(wild) end
  -- worn down by the partner's Battler: the HP it has left
  local hp = tonumber(enc.hp)
  if hp and hp > 0 then wild.hp = math.min(math.floor(hp), wild.maxHp or hp) end
  local save = game.save
  if save then
    save.pokedex = save.pokedex or { seen = {}, caught = {} }
    save.pokedex.seen = save.pokedex.seen or {}
    save.pokedex.seen[enc.species] = true
  end
  local okB, err = pcall(world.startBattle, world, { wild = wild }, function(result)
    if done then done(result) end
  end)
  if not okB then return nil, "startBattle failed: " .. tostring(err) end
  return true
end

local function playerState(world)
  local save = Gen2.save(world)
  return (world and world.playerState) or (save and save.playerState)
end

function Gen2.isSurfing(world)
  local FieldMoves = load("src.world.gen2.FieldMoves")
  local state = playerState(world)
  if FieldMoves and FieldMoves.isSurfing then
    local ok, yes = pcall(FieldMoves.isSurfing, state)
    if ok then return yes == true end
  end
  return state == "surf" or state == "surf_pika"
end

function Gen2.isBiking(world)
  local FieldMoves = load("src.world.gen2.FieldMoves")
  local state = playerState(world)
  if FieldMoves and FieldMoves.isBiking then
    local ok, yes = pcall(FieldMoves.isBiking, state)
    if ok then return yes == true end
  end
  return state == "bike"
end

function Gen2.isCaught(species, world)
  local save = Gen2.save(world)
  local dex = save and save.pokedex
  if not (dex and species) then return false end
  return (type(dex.caught) == "table" and dex.caught[species] == true)
    or (type(dex.owned) == "table" and dex.owned[species] == true)
end

--- Gen 2 shininess from DVs (Mon.isShiny: the classic pattern, or a mod's shiny.roll).
function Gen2.shinyDvs(dvs)
  local Mon = load("src.battle.gen2.Mon")
  if not (Mon and Mon.isShiny and type(dvs) == "table") then return false end
  local ok, yes = pcall(Mon.isShiny, dvs)
  return ok and yes == true
end

function Gen2.isShiny(mon)
  return type(mon) == "table" and (mon.shiny == true or Gen2.shinyDvs(mon.dvs))
end

--- ChooseWildEncounter's Unown rule: a wild Unown's letter is one the Ruins of Alph unlocked.
function Gen2.dvsAllowed(world, species, dvs)
  local Unown = load("src.core.gen2.Unown")
  if not (Unown and species == Unown.SPECIES) then return true end
  if not (world and world.unownUnlockFlags) then return true end
  local ok, flags = pcall(world.unownUnlockFlags, world)
  if not (ok and type(flags) == "table") then return true end
  local okL, yes = pcall(function() return Unown.letterUnlocked(Unown.letterFromDVs(dvs), flags) end)
  return not okL or yes == true
end

-- ------------------------------------------------------------------ shiny (lib/shiny.lua)
-- Gold builds every Pokemon with Mon.new and reads shininess from its DVs (CheckShininess). A wild
-- one (opts.wild: step, Surf, fishing, Headbutt, the contest, a script's, a roaming beast's first
-- meeting) gets the Shiny Rate's DVs; DVs the game fixed (a roaming beast met before, the red
-- Gyarados's FORCESHINY) and a forced shiny stand. An Unown's were only rolled within its
-- chamber's letters, so it is settled within them.

--- `decide(dvs, allowed, rng) -> dvs, shiny`; `currentWorld()` -> the live World. Once.
function Gen2.installShiny(decide, currentWorld)
  decideDvs, worldOf = decide, currentWorld
  local Mon = load("src.battle.gen2.Mon")
  if not (Mon and Mon.new) then return false, "Gen 2 builder unavailable" end
  if Mon._vwogShinyNew then return true end
  local Unown = load("src.core.gen2.Unown")
  local origNew = Mon.new
  Mon._vwogShinyNew = function(data, species, level, opts, ...)
    if ownBuild or not decideDvs or type(opts) ~= "table" or not opts.wild or opts.shiny then
      return origNew(data, species, level, opts, ...)
    end
    local unown = Unown ~= nil and species == Unown.SPECIES
    if type(opts.dvs) == "table" and not unown then return origNew(data, species, level, opts, ...) end
    local allowed = nil
    if unown then
      local world = worldOf and worldOf()
      allowed = function(d) return Gen2.dvsAllowed(world, species, d) end
    end
    local ok, dvs = pcall(decideDvs, opts.dvs, allowed)
    if ok and type(dvs) == "table" then
      local o = {}
      for k, v in pairs(opts) do o[k] = v end
      o.dvs = { attack = dvs.attack, defense = dvs.defense, speed = dvs.speed, special = dvs.special }
      opts = o
    end
    return origNew(data, species, level, opts, ...)
  end
  Mon.new = Mon._vwogShinyNew
  return true
end

function Gen2.isOutdoor(world)
  local Map = load("src.world.gen2.Map")
  local def = world and world.map and world.map.def
  if not (Map and Map.isOutdoor and def) then return true end
  local ok, out = pcall(Map.isOutdoor, def)
  return not ok or out == true
end

--- The input wrap: while `isHeld()` no direction is held this frame (the step reads
--- world.heldDir, which pollInput sets).
function Gen2.inputWrapper(original, isHeld)
  return function(self, ...)
    local a, b, c = original(self, ...)
    if isHeld() then self.heldDir = nil end
    return a, b, c
  end
end

--- The per-frame wrap's world: World:step()'s self.
function Gen2.tickWrapper(original, after)
  return function(self, ...)
    local a, b, c = original(self, ...)
    after(self, self.game)
    return a, b, c
  end
end

--- The engine's party follower (src/world/gen2/Follower.lua), flagged `pikachuFollower`.
function Gen2.follower(world)
  for _, npc in ipairs(world and world.npcs or {}) do
    if npc.pikachuFollower then return npc end
  end
  return nil
end

--- The world that has `map` loaded: Gold's one World (game.world).
function Gen2.liveWorld(game, map)
  local w = game and game.world
  if type(w) == "table" and w.map and (map == nil or w.map == map) then return w end
  return nil
end

function Gen2.party(world)
  local save = Gen2.save(world)
  return save and save.party
end

-- ------------------------------------------------------------------ talk / UI
-- The same text box as Gen 1 (src/render/TextBox.lua, shared), through lib/gb/ui.lua; the
-- choice menu is Gold's own ScriptMenu with a header built like the union room's
-- (src/ui/gen2/union/Dialog.lua menuHeader). On Gold the overworld runs while the game's
-- state stack is EMPTY: anything on it (a box, a menu, a battle) owns the screen.
local ui = V.require("gb/ui").new(function(world) return Gen2.game(world) end, function() return load end)

function Gen2.isMessageOpen(world) return ui.isMessageOpen(world) end
function Gen2.showMessage(world, text, opts) return ui.showMessage(world, text, opts) end
function Gen2.messageOnLastPage(world) return ui.messageOnLastPage(world) end
function Gen2.closeStayMessage(world) return ui.closeStayMessage(world) end
function Gen2.choiceActive(world) return ui.choiceActive(world) end

--- The menu for `options` (labels): `cb(index)` 0-based, B -> cb(127).
function Gen2.showChoice(world, options, defaultIdx, cb)
  local game = Gen2.game(world)
  local ScriptMenu = load("src.ui.gen2.ScriptMenu")
  local Dialog = load("src.ui.gen2.union.Dialog")
  if not (game and game.stack and ScriptMenu and ScriptMenu.new and Dialog and Dialog.menuHeader) then
    return false
  end
  local labels = {}
  for i, label in ipairs(options or {}) do labels[i] = tostring(label) end
  if #labels == 0 then return false end
  local okH, header = pcall(Dialog.menuHeader, labels)
  if not (okH and type(header) == "table") then return false end
  if tonumber(defaultIdx) and defaultIdx >= 1 and defaultIdx < #labels then header.cursor = defaultIdx + 1 end
  local menu
  local okM, m = pcall(ScriptMenu.new, game, {
    header = header, kind = "vivid_worlds_og_partner",
    onChoose = function(index)
      ui.trackChoice(nil)
      if game.stack:top() == menu then pcall(game.stack.pop, game.stack) end
      if cb then pcall(cb, (tonumber(index) or 0) >= 1 and index - 1 or 127) end
    end,
  })
  if not (okM and m) then return false end
  menu = m
  local okP = pcall(game.stack.push, game.stack, menu)
  if not okP then return false end
  ui.trackChoice(menu)
  return true
end

--- The dialogue box's place in 8 px tiles: the bottom six rows, as on Gen 1.
function Gen2.dialogueWindow(_world)
  return { left = 0, top = 12, width = 20, height = 6 }
end

--- Something owns the whole screen: anything on the state stack.
function Gen2.screenBusy(world)
  return ui.stackTop(world) ~= nil
end

--- The top of the engine's own A press: nothing on the stack, no script, the player still.
function Gen2.canStartInteraction(world)
  if not world or Gen2.busy(world) then return false end
  if world.scriptRunning then
    local ok, running = pcall(world.scriptRunning, world)
    if ok and running then return false end
  end
  local p = world.player
  return p ~= nil and not p.moving
end

--- Gold has no follower of its own to talk to: the partner's menu always answers.
function Gen2.nativeTalk(_world) return false end

function Gen2.displayName(mon)
  if type(mon) ~= "table" then return "POKeMON" end
  if type(mon.nickname) == "string" and mon.nickname ~= "" then return mon.nickname end
  if type(mon.name) == "string" and mon.name ~= "" then return mon.name end
  return type(mon.species) == "string" and mon.species or "POKeMON"
end

--- Width in px of `text` in the engine's font (shared with Gen 1).
function Gen2.measureText(text) return Shared.measureText(load("src.render.Font"), text) end

--- Draws `text` with the engine's font at (x, y), top-left, dark; returns the width.
function Gen2.drawText(text, x, y) return Shared.drawText(load("src.render.Font"), text, x, y) end

-- ------------------------------------------------------------------ emote art
-- the showemote bubbles (EMOTE_* order, menu_gfx.lua emotes) by the names lib/emote_art.lua reads
local EMOTES = { { "shock", "exclaim" }, { "question", "question" }, { "happy", "happy" }, { "sad", "sad" },
  { "heart", "heart" }, { "bolt", "bolt" }, { "sleep", "sleep" }, { "fish", "fish" } }

--- Gold's own showemote bubbles (menu_gfx.lua emotes, the art World:showEmote draws) as the
--- sheet shape the mod reads: `quads` frame 0 SHOCK and frame 1 QUESTION (lib/wild_emote.lua),
--- `named` all eight by name (lib/emote_art.lua). Shaded the way World:drawEmote colours them
--- (PAL_OW_EMOTE's silver row: white, white, RGB 13,13,13, black). Built once.
local emoteSheet
function Gen2.emoteSheet(world)
  if emoteSheet ~= nil then return emoteSheet or nil end
  if not (world and love and love.graphics and love.image and love.image.newImageData) then return nil end
  local Assets = load("src.render.Assets")
  local okT, gfx = false, nil
  if world.dataTable then okT, gfx = pcall(world.dataTable, world, "gen2MenuGfx", "data/generated/menu_gfx.lua") end
  local emotes = okT and type(gfx) == "table" and gfx.emotes or nil
  if not (Assets and Assets.imageData and emotes and emotes.shock and emotes.question) then
    emoteSheet = false
    return nil
  end
  local ok, sheet = pcall(function()
    local n = #EMOTES
    local out = love.image.newImageData(16 * n, 16)
    local present = {}
    for i, e in ipairs(EMOTES) do
      local okI, src = false, nil
      if emotes[e[1]] then okI, src = pcall(Assets.imageData, emotes[e[1]]) end
      if okI and src then
        present[i] = true
        local w, h = math.min(16, src:getWidth()), math.min(16, src:getHeight())
        for y = 0, h - 1 do
          for x = 0, w - 1 do
            local r, _, _, a = src:getPixel(x, y)
            local v = 0
            if r > 0.5 then v = 1 elseif r > 0.17 then v = 13 / 31 end
            out:setPixel((i - 1) * 16 + x, y, v, v, v, a)
          end
        end
      end
    end
    local img = love.graphics.newImage(out)
    if img.setFilter then img:setFilter("nearest", "nearest") end
    local quads, named = {}, {}
    for i, e in ipairs(EMOTES) do
      if present[i] then
        local q = love.graphics.newQuad((i - 1) * 16, 0, 16, 16, 16 * n, 16)
        named[e[2]] = q
        if i <= 2 then quads[i - 1] = q end
      end
    end
    return { image = img, quads = quads, named = named, fw = 16, fh = 16, frames = 2 }
  end)
  emoteSheet = (ok and sheet) or false
  return emoteSheet or nil
end

-- ------------------------------------------------------------------ friendship
-- Gold keeps a real happiness byte on every party mon (Mon.new: happiness, 70 for a wild one):
-- the partner's friendship IS it, so Pet / Play / Talk change what Return, Frustration and the
-- happiness evolutions read.
function Gen2.friendshipOf(mon)
  return type(mon) == "table" and tonumber(mon.happiness) or nil
end

function Gen2.setFriendship(mon, value)
  if type(mon) ~= "table" then return nil end
  local v = math.max(0, math.min(255, math.floor(tonumber(value) or 0)))
  mon.happiness = v
  return v
end

-- ------------------------------------------------------------------ species facts
--- The species' data row, by key ("PIKACHU") or national dex number.
function Gen2.speciesDef(species, world)
  local data = Gen2.data(world)
  local mons = data and data.pokemon
  if type(mons) ~= "table" or species == nil then return nil end
  if type(species) == "string" then return mons[species] end
  local n = tonumber(species)
  if not n then return nil end
  for _, def in pairs(mons) do
    if type(def) == "table" and tonumber(def.dex) == n then return def end
  end
  return nil
end

function Gen2.hasType(species, wanted, world)
  local def = Gen2.speciesDef(species, world)
  for _, t in ipairs(def and def.types or {}) do
    if t == wanted then return true end
  end
  return false
end

function Gen2.baseStatTotal(species, world)
  local def = Gen2.speciesDef(species, world)
  local b = def and def.baseStats
  if type(b) ~= "table" then return nil end
  local sum = 0
  for _, v in pairs(b) do sum = sum + (tonumber(v) or 0) end
  return sum > 0 and sum or nil
end

-- ------------------------------------------------------------------ Bug-Catching Contest
--- While the Bug-Catching Contest runs, the park's encounters are the contest's own (its table,
--- Park Balls, one catch kept): no visible spawns (they would be ordinary wild battles there).
function Gen2.spawnsPaused(world)
  local BugContest = load("src.core.gen2.BugContest")
  local save = Gen2.save(world)
  if not (BugContest and BugContest.isActive and save) then return false end
  local ok, active = pcall(BugContest.isActive, save)
  return ok and active == true
end

-- ------------------------------------------------------------------ reachable area
-- A step function for lib/reachability.lua over Gold / Silver / Crystal's own movement rules:
-- Gold keeps its one-way rules in the COLLISION bytes (one-way UP_WALL edges, ledges), so a
-- plain 4-neighbour fill fabricates most of a cave. Directed exactly like the engine's offline
-- model (tools/goldwalk/mapgraph.lua) and Wilds of Kanto Revival's cave fill:
--   * a step must pass `map:stepPermitted` and land on floor;
--   * a step refused off a ledge tile hops TWO cells in a direction the ledge allows;
--   * a cell is a HOLE only when it is BOTH a warp tile by collision AND has a warp event there
--     (a warp event on plain floor never fires; a warp-collision tile with no event does nothing).
-- Surf is not modelled (water is not floor); ice is plain floor (a real slide can only shrink it).
local GOLD_DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

function Gen2.reachMover(world)
  local map = world and world.map
  if not (map and type(map.stepPermitted) == "function" and type(map.cellCollision) == "function") then
    return nil
  end
  local P = load("src.world.gen2.Permissions")
  if not (P and P.isWalkable and P.ledgeFacings and P.isWarpCollision and P.carpetDirection) then return nil end
  local function floor(x, y)
    if map.inBounds and not map:inBounds(x, y) then return false end
    local coll = map:cellCollision(x, y)
    if not P.isWalkable(coll) then return false end
    if P.isWarpCollision(coll) or P.carpetDirection(coll) ~= nil then
      if type(map.warpAtCell) ~= "function" or map:warpAtCell(x, y) then return false end
    end
    return true
  end
  return function(x, y, dir, state)
    local d = GOLD_DIRS[dir]
    if not d then return nil end
    local nx, ny = x + d[1], y + d[2]
    if map:stepPermitted(x, y, dir) and floor(nx, ny) then return nx, ny, state end
    local hop = P.ledgeFacings(map:cellCollision(x, y))
    if hop and hop[dir] then
      local hx, hy = x + d[1] * 2, y + d[2] * 2
      if floor(hx, hy) then return hx, hy, state end
    end
    return nil
  end
end

-- ------------------------------------------------------------------ roles (Battler / Forager)
-- The partner's overworld battles and foraging (lib/overworld_battle.lua, lib/forager.lua,
-- lib/level_ready.lua) by Gold's own rules: Damage.calc with the type chart and the critical
-- ladder, Mon.new / gainExperience / learnMoveOn, Evolution.checkMon and the evolution screen,
-- the four-pocket bag. These calls come without a world: `liveWorld()`.
local function liveData() return Gen2.data(liveWorld()) end
local function liveGame() return Gen2.game(liveWorld()) end

Gen2.moveNumber = Shared.moveNumber
Gen2.knowsMove = Shared.knowsMove

local function moveDef(id)
  local data = liveData()
  local key = Shared.moveKey(id)
  local row = key and data and type(data.moves) == "table" and data.moves[key]
  return type(row) == "table" and row or nil, key
end

--- { power, accuracy (percent), type, pp } for an (interned) move id, or nil.
function Gen2.moveRow(id)
  local row = moveDef(id)
  if not row then return nil end
  return { power = tonumber(row.power) or 0, accuracy = tonumber(row.accuracy) or 0,
           type = row.type, pp = tonumber(row.pp) or 0 }
end

--- The battler the damage reads: the mon, its level, stats and types (`maxHp` mirrored).
function Gen2.battlerOf(mon)
  local def = Gen2.speciesDef(mon.species, liveWorld())
  if type(mon.stats) == "table" and tonumber(mon.stats.hp) then mon.maxHp = mon.maxHp or mon.stats.hp end
  return { mon = mon, def = def, name = Gen2.displayName(mon), level = mon.level, stages = {},
           curStats = type(mon.stats) == "table" and mon.stats or {},
           curTypes = mon.types or (def and def.types) or {}, curMoves = mon.moves }
end

--- Gold's damage between two battlers: the critical roll on its ladder (a high-crit move two
--- rungs up), then Damage.calc with the type chart. `rng(lo, hi)`. Returns damage,
--- { critical, effectiveness } (nil on any trouble).
function Gen2.moveDamage(attacker, defender, moveId, rng, noCrit)
  local Damage = load("src.battle.gen2.Damage")
  local data = liveData()
  local move, key = moveDef(moveId)
  local chart = data and data.type_chart
  if not (Damage and Damage.calc and move and chart) then return nil end
  rng = rng or math.random
  local function random(n) return rng(0, n - 1) end
  local rules = chart.battleRules or {}
  local critical = false
  if not noCrit and rules.criticalChances then
    local okC, crit = pcall(Damage.rollCritical, Damage.criticalLevel({
      highCritMove = rules.highCriticalMoves and rules.highCriticalMoves[key] == true }),
      random, rules.criticalChances)
    critical = okC and crit == true
  end
  local a, d = attacker.curStats or {}, defender.curStats or {}
  local ok, dmg, info = pcall(Damage.calc, {
    level = attacker.level or 1, power = tonumber(move.power) or 0, moveType = move.type,
    attacker = { attack = a.attack, specialAttack = a.specialAttack, types = attacker.curTypes },
    defender = { defense = d.defense, specialDefense = d.specialDefense, types = defender.curTypes },
    types = chart.types, matchups = chart.matchups, critical = critical, random = random,
  })
  if not ok then return nil end
  return tonumber(dmg), {
    critical = type(info) == "table" and info.critical or false,
    effectiveness = (type(info) == "table" and tonumber(info.effectiveness) or 10) / 10,
  }
end

--- The wild Pokemon of a skirmish: Mon.new with the spawn's own DVs (`dvs`, so it is the one
--- its real battle builds), moves from the learnset, full HP.
function Gen2.buildWildFighter(species, level, dvs)
  local data = liveData()
  local Mon = load("src.battle.gen2.Mon")
  if not (data and Mon and Mon.new and data.pokemon and data.pokemon[species]) then return nil end
  local opts = {}
  if type(dvs) == "table" then
    opts.dvs = { attack = dvs.attack, defense = dvs.defense, speed = dvs.speed, special = dvs.special }
  end
  local ok, mon = pcall(Mon.new, data, species, tonumber(level) or 5, opts)
  if not (ok and type(mon) == "table" and type(mon.moves) == "table" and #mon.moves > 0) then return nil end
  mon.maxHp = tonumber(mon.maxHp) or (type(mon.stats) == "table" and tonumber(mon.stats.hp)) or nil
  if not mon.maxHp or mon.maxHp <= 0 then return nil end
  mon.hp = mon.maxHp
  return mon
end

--- EXP a wild `species` at `level` is worth to one participant (Mon.experienceGain).
function Gen2.expGain(species, level)
  local data = liveData()
  local Mon = load("src.battle.gen2.Mon")
  local def = data and data.pokemon and data.pokemon[species]
  if not (def and Mon and Mon.experienceGain) then return 0 end
  local ok, n = pcall(Mon.experienceGain, def, tonumber(level) or 1, 1, false, {})
  return ok and tonumber(n) or 0
end

--- Mon.gainExperience: levels, stats, the HP gain carried, `pokemon.level_up` per level.
--- Returns { gained, fromLevel, toLevel } or nil.
function Gen2.expApply(mon, amount)
  local data = liveData()
  local Mon = load("src.battle.gen2.Mon")
  if not (data and Mon and Mon.gainExperience and type(mon) == "table") then return nil end
  local from = tonumber(mon.level) or 1
  amount = math.max(0, math.floor(tonumber(amount) or 0))
  if not pcall(Mon.gainExperience, mon, amount, data) then return nil end
  return { gained = amount, fromLevel = from, toLevel = tonumber(mon.level) or from }
end

--- The level-up moves of the species at exactly `level`.
function Gen2.movesLearnedAt(mon, level)
  local data = liveData()
  local def = type(mon) == "table" and data and data.pokemon and data.pokemon[mon.species]
  local out = {}
  for _, e in ipairs(def and def.levelMoves or {}) do
    if e.level == tonumber(level) then out[#out + 1] = e.move end
  end
  return out
end

-- Evolution.checkMon by level-up at this hour (an Everstone or unmet happiness refuses)
local function evolutionEntry(mon)
  local Evolution = load("src.core.gen2.Evolution")
  local Palettes = load("src.world.gen2.Palettes")
  local data = liveData()
  if not (Evolution and Evolution.checkMon and data and type(mon) == "table") then return nil end
  local okT, tod = false, nil
  if Palettes and Palettes.clockDaytime then okT, tod = pcall(Palettes.clockDaytime) end
  local ok, entry = pcall(Evolution.checkMon, data, mon, { timeOfDay = okT and tod or nil })
  return ok and type(entry) == "table" and entry or nil
end

function Gen2.evolutionTarget(mon)
  local entry = evolutionEntry(mon)
  return entry and entry.into or nil
end

--- The evolution screen Rare Candy and a battle use (Game2:afterRareCandy). False -- and
--- `onDone` never runs -- when nothing evolves.
function Gen2.startEvolution(mon, _target, onDone)
  local game = liveGame()
  local Screens = load("src.ui.Screens")
  local entry = evolutionEntry(mon)
  if not (game and game.stack and Screens and Screens.push and entry) then return false end
  local party = (game.save and game.save.party) or {}
  local index
  for i, m in ipairs(party) do if m == mon then index = i end end
  return (pcall(Screens.push, game, "Gen2EvolutionAnim", {
    mon = mon, entry = entry, index = index, party = party, save = game.save,
    onDone = function()
      pcall(game.stack.pop, game.stack)
      if game.restartMapMusicAfterEvolution then pcall(game.restartMapMusicAfterEvolution, game) end
      if onDone then onDone() end
    end,
  }))
end

--- Gold's own LearnMove for each of `moveIds` in turn (a full set asks which to forget);
--- `onDone(learnedAny)`. False -- and `onDone` never runs -- when there is nothing to learn.
function Gen2.startMoveLearn(mon, moveIds, onDone)
  local game = liveGame()
  if not (game and game.learnMoveOn and type(mon) == "table" and type(moveIds) == "table") then return false end
  local queue = {}
  for _, id in ipairs(moveIds) do
    local def, key = moveDef(id)
    if def and not Shared.knowsMove(mon, key) then queue[#queue + 1] = key end
  end
  if #queue == 0 then return false end
  local learnedAny, nextMove = false, nil
  nextMove = function()
    local key = table.remove(queue, 1)
    if not key then
      if onDone then pcall(onDone, learnedAny) end
      return
    end
    local ok = pcall(game.learnMoveOn, game, mon, key, function(learned)
      if learned then learnedAny = true end
      nextMove()
    end)
    if not ok then nextMove() end
  end
  nextMove()
  return true
end

-- Gold's pockets by the names lib/forage_items.lua reads
local POCKETS = { ITEM = "ITEMS", BALL = "POKE_BALLS", KEY_ITEM = "KEY_ITEMS", TM_HM = "TM_CASE" }

--- Every item the Forager may consider (lib/forage_items.lua's entry shape). No mail: it only
--- exists to be written on.
function Gen2.itemCatalog()
  local data = liveData()
  local out = {}
  for id, row in pairs(data and type(data.items) == "table" and data.items or {}) do
    local key = tostring(id)
    if type(row) == "table" and type(row.name) == "string" and row.name ~= "" and not key:match("_MAIL$") then
      out[#out + 1] = {
        id = id, name = row.name, pocket = POCKETS[row.pocket] or "ITEMS", price = tonumber(row.price) or 0,
        use = Shared.USE_OF[id] or "none", isEvo = Shared.EVO[id] == true,
        isHm = key:match("^HM_") ~= nil, isTm = key:match("^TM_") ~= nil,
      }
    end
  end
  table.sort(out, function(a, b) return tostring(a.id) < tostring(b.id) end)
  return out
end

function Gen2.bagAdd(id, qty)
  return Shared.bagAdd(load("src.inventory.Bag"), Gen2.save(liveWorld()), liveData(), id, qty)
end
function Gen2.bagCanAdd(id, qty)
  return Shared.bagCanAdd(load("src.inventory.Bag"), Gen2.save(liveWorld()), liveData(), id, qty)
end

-- Gold's own sound effects by name (World:playSfxNamed)
local function sfx(name)
  local world = liveWorld()
  if not (world and world.playSfxNamed) then return false end
  return (pcall(world.playSfxNamed, world, name))
end
function Gen2.playSuccess() return sfx("Sfx_Item") end
function Gen2.playSelect() return sfx("Sfx_ReadText2") end

-- the battle's own hit sounds (BattleState:effectivenessSfx) and faint, for EnginePatch.playSeNamed
Gen2.SFX = { SE_EFFECTIVE = "Sfx_Damage", SE_SUPER_EFFECTIVE = "Sfx_SuperEffective",
  SE_NOT_EFFECTIVE = "Sfx_NotVeryEffective", KO = "Sfx_Faint" }

function Gen2.holdsExpShare(mon)
  return type(mon) == "table" and mon.item == "EXP_SHARE"
end

--- Mon.wildItem: a wild Pokemon's held item by its species' own odds (or nil).
function Gen2.wildHeldItem(species)
  local data = liveData()
  local Mon = load("src.battle.gen2.Mon")
  local def = data and data.pokemon and data.pokemon[species]
  if not (def and Mon and Mon.wildItem) then return nil end
  local ok, item = pcall(Mon.wildItem, def)
  return ok and item or nil
end

--- Gen 3's map types as far as the mod reads them: 1 a town, 3 a route, 4 a cave / dungeon,
--- 8 indoors (a house, a gate). The Forager sets out on routes and in caves.
local MAP_TYPES = { TOWN = 1, ROUTE = 3, CAVE = 4, DUNGEON = 4, INDOOR = 8, GATE = 8 }
function Gen2.mapTypeOf(world)
  local env = world and world.map and world.map.def and world.map.def.environment
  return MAP_TYPES[env] or (Gen2.isOutdoor(world) and 3 or 8)
end

return Gen2
