-- The Pokemon that stand on the maps themselves (Gen 1 / Gen 2 map objects): the legendary
-- birds, Mewtwo, Snorlax, Lugia, Ho-Oh, the Red Gyarados, the beasts, the Rocket base's
-- Electrode, and the town and house Pokemon (Clefairy, Slowpoke, Miltank ...). The engine
-- draws them with a handful of generic Game Boy sheets (a "MONSTER" for Mewtwo, a "BIRD" for
-- Zapdos, Moltres' sheet for a Murkrow); here they get this mod's own art for their real
-- species, in the Sprite Style the wild Pokemon use.
--
-- Which species an object is comes from its own data (StaticMons.classify, pure):
--   Gen 1: its static battle's `pokemon`, else its name (CERULEANCAVEB1F_MEWTWO,
--          ROUTE12_SNORLAX, FUCHSIACITY_KANGASKHAN ...).
--   Gen 2: its script: the `loadwildmon` of its battle (with a FORCESHINY battle type it is
--          shiny: the Lake of Rage Gyarados), else the `cry` it gives when talked to; else
--          its sprite when that names a species (SPRITE_SUICUNE). The few that say nothing
--          and wear a generic sheet are in OVERRIDES2.
-- Only an object that LOOKS like a Pokemon is considered (a species' sheet, or a generic
-- MONSTER / BIRD / FAIRY / DRAGON / SURF / Poke Ball one), and only one something names:
-- never a person, an item ball, or a doll (Copycat's, the Fan Club's).
--
-- The engine's npc keeps everything it has (script, movement, collision, palette): only
-- its `sprite` is swapped for one of ours (EnginePatch.followerSprite, as the partner's).
-- When the engine hands it another sheet (a `variablesprite`), it is decided again.
local V = ...
local Config = V.require("config")
local EnginePatch = V.require("engine_patch")
local FormSource = V.require("form_source")
local SpriteSource = V.require("sprite_source")
local RendererFactory = V.require("renderer_factory")
local ActorRenderer = V.require("actor_renderer")

local StaticMons = {}
StaticMons.__index = StaticMons

-- the generic sheets a Pokemon object may wear (besides a species' own)
local GENERIC = { MONSTER = true, BIRD = true, FAIRY = true, DRAGON = true, SURF = true, POKE_BALL = true }

-- Gen 1 object names whose tail is no species id
local NAME_ALIAS = {
  NIDORAN = "NIDORAN_M", NIDORANF = "NIDORAN_F",
  -- Bill, fused with a Pokemon in his own teleporter: a Clefairy, as FireRed / LeafGreen show him
  BILL_POKEMON = "CLEFAIRY",
}

-- Gen 2 objects with no battle, no cry and a generic (or another species') sheet:
-- map -> { [object index] = species, [sheet] = species }
local OVERRIDES2 = {
  -- the three beasts asleep under the Burned Tower (Gold / Silver: one dog sheet for all)
  BURNED_TOWER_B1F = { [2] = "RAIKOU", [3] = "ENTEI", [4] = "SUICUNE", [5] = "RAIKOU", [6] = "ENTEI", [7] = "SUICUNE" },
  ILEX_FOREST = { BIRD = "FARFETCH_D" }, -- the lost Farfetch'd (Gold / Silver: one object per spot)
  MOUNT_MOON_SQUARE = { FAIRY = "CLEFAIRY" }, -- the Monday-night dance
  MAHOGANY_MART_1F = { DRAGON = "DRAGONITE" }, -- Lance's
  TEAM_ROCKET_BASE_B2F = { DRAGON = "DRAGONITE", VOLTORB = "ELECTRODE" },
  TEAM_ROCKET_BASE_B3F = { MOLTRES = "MURKROW" }, -- the password Murkrow
  ROUTE_30 = { MONSTER = "RATTATA" }, -- Joey's and Mikey's, mid-battle
  ROUTE_39_BARN = { TAUROS = "MILTANK" }, -- Moomoo
  OLIVINE_LIGHTHOUSE_6F = { MONSTER = "AMPHAROS" }, -- Amphy
}
StaticMons.OVERRIDES2 = OVERRIDES2

-- Gen 2's VAR_BATTLETYPE and BATTLETYPE_FORCESHINY (World.lua's BATTLETYPE)
local VAR_BATTLETYPE, FORCESHINY = 3, 7

local function sheetName(sprite)
  if type(sprite) ~= "string" then return nil end
  return (sprite:gsub("^SPRITE_", ""))
end

-- what a Gen 2 script says: its wild battle's species, the first cry, a forced shiny
local function scriptSays(script)
  if type(script) ~= "table" then return nil, nil, false end
  local wild, cry, shiny = nil, nil, false
  for i = 1, #script do
    local op = script[i]
    if type(op) == "table" then
      if op.op == "loadwildmon" and wild == nil then wild = op.species
      elseif op.op == "cry" and cry == nil then cry = op.id
      elseif op.op == "loadvar" and type(op.args) == "table"
          and op.args[1] == VAR_BATTLETYPE and op.args[2] == FORCESHINY then
        shiny = true
      end
    end
  end
  return wild, cry, shiny
end

local function gen1(f, isSpecies)
  local sheet = sheetName(f.sprite)
  if not (sheet and (GENERIC[sheet] or isSpecies(sheet))) then return nil end
  if f.pokemon ~= nil and isSpecies(f.pokemon) then return f.pokemon, false end
  local tail = type(f.name) == "string" and f.name:match("^[^_]+_(.+)$")
  if not tail then return nil end
  local species = NAME_ALIAS[tail]
  if not species then
    species = tail:gsub("%d+$", "")
    species = NAME_ALIAS[species] or species
  end
  if isSpecies(species) then return species, false end
  return nil
end

local function gen2(f, isSpecies, speciesOf)
  -- the Day-Care's two: the deposited species' own icon
  local kept = f.spriteSpecies ~= nil and speciesOf(f.spriteSpecies) or nil
  if kept ~= nil and isSpecies(kept) then return kept, false end
  local sheet = sheetName(f.sprite)
  if not sheet or sheet == "POKE_BALL" then return nil end -- Gold hides no Pokemon in a ball
  local own = sheet:gsub("^BIG_", "")
  if not (GENERIC[sheet] or isSpecies(own)) then return nil end
  local over = OVERRIDES2[f.mapId]
  if over and f.index ~= nil and over[f.index] then return over[f.index], false end
  local wild, cry, shiny = scriptSays(f.script)
  local said = wild or cry
  if said ~= nil then said = speciesOf(said) end
  if said ~= nil and isSpecies(said) then return said, shiny end
  if over and over[sheet] then return over[sheet], false end
  if not GENERIC[sheet] and isSpecies(own) then return own, false end
  return nil
end

--- The species a map object is, and whether it is shiny, from `facts`:
---   { gen, mapId, index, name, pokemon, sprite (SPRITE_*), spriteSpecies, script (op list) }
--- `isSpecies(id)` answers for an engine species id; `speciesOf(v)` turns a script's species
--- (a dex number on Gen 2) into one. nil = not a Pokemon (left as the engine draws it). Pure.
function StaticMons.classify(facts, isSpecies, speciesOf)
  if type(facts) ~= "table" or type(isSpecies) ~= "function" then return nil end
  speciesOf = speciesOf or function(v) return v end
  if facts.gen == 2 then return gen2(facts, isSpecies, speciesOf) end
  return gen1(facts, isSpecies)
end

-- ------------------------------------------------------------------ runtime

local function isSpecies(id)
  return type(id) == "string" and EnginePatch.nationalFor(id) ~= nil
end

local function speciesOf(v)
  if type(v) == "number" then return EnginePatch.speciesForNational(v) end
  return v
end

--- `mod`: the mod (art, options).
function StaticMons.new(mod)
  return setmetatable({
    mod = mod,
    -- npc -> { renderer, wrapper, species, shiny, style, clock }; npc -> the engine sprite
    -- it was found not to be a Pokemon with (so it is not asked again every tick)
    shown = setmetatable({}, { __mode = "k" }),
    plain = setmetatable({}, { __mode = "k" }),
    facts = {}, -- reused for every object (no garbage per tick)
  }, StaticMons)
end

-- a fresh renderer for an object (one per object: each keeps its own idle clock)
function StaticMons:_dress(npc, species, shiny, style)
  local dex = FormSource.artKeyFor(self.mod, species)
  if not dex then return nil end
  local r = RendererFactory.new(self.mod, dex, shiny, style)
  -- stood on its own cell: none of the partner's pushing behind the player
  r.pushX, r.pushY = 0, 0
  -- Gold's big objects (the Vermilion Snorlax) cover 2x2 cells from their top left one:
  -- stand it in the middle of them
  if npc.bigObject then r.pushX, r.pushY = 8, 16 end
  local rec = {
    renderer = r, species = species, shiny = shiny, style = style,
    floater = SpriteSource.isFloater(self.mod, dex) == true,
    clock = math.random(0, 239), -- not all in step
  }
  rec.wrapper = EnginePatch.followerSprite(r, npc)
  npc.sprite = rec.wrapper
  -- a big object draws itself from its sheet's own frames: through ours instead
  if npc.bigObject then npc.drawBig, npc.drawBigAsym = StaticMons._drawBig, StaticMons._drawBig end
  return rec
end

-- (a big object's NPC:draw calls self:drawBig(); one function for all, no closure)
function StaticMons._drawBig(npc)
  local s = npc.sprite
  if s and s.draw then s:draw(npc.px, npc.py, 0, 0, npc.facing or "down", 0, false) end
end

local function undress(npc)
  local base = EnginePatch.followerSprite(nil, npc)
  if base then npc.sprite = base end
  npc.drawBig, npc.drawBigAsym = nil, nil
end

-- the pose a shown object draws with: walking while it steps, its idle loop while it stands
-- if it floats or bounces in place (Gold's Pokemon objects), else standing
local function poseOf(rec, npc)
  if npc.moving then
    return npc.stepFlip and ActorRenderer.POSE_WALK_B or ActorRenderer.POSE_WALK_A
  end
  if rec.floater or npc.bouncing then
    return ActorRenderer.idleFlapPose(rec.clock, Config.IDLE_FLAP_TICKS)
  end
  return ActorRenderer.POSE_STAND
end

--- One field tick: dresses every Pokemon object on the map in our art, keeps its pose.
--- `still` (a draw, not a tick): the same, without moving the idle clocks on.
function StaticMons:tick(still)
  local list = EnginePatch.mapNpcs and EnginePatch.mapNpcs()
  if type(list) ~= "table" then return end
  local style = Config.spriteStyle(self.mod)
  local facts, gen = self.facts, EnginePatch.generation()
  for i = 1, #list do
    local npc = list[i]
    -- (never the partner, nor a wild Pokemon's draw proxy)
    if type(npc) == "table" and not npc.pikachuFollower and not rawget(npc, "_wilds") then
      local cur = npc.sprite
      local rec = self.shown[npc]
      if rec and cur == rec.wrapper then
        if rec.style ~= style then
          undress(npc)
          rec = self:_dress(npc, rec.species, rec.shiny, style)
          self.shown[npc] = rec
          if not rec then self.plain[npc] = npc.sprite end
        end
        if rec then
          if not still then rec.clock = rec.clock + 1 end
          rec.renderer.poseOverride = poseOf(rec, npc)
        end
      elseif type(cur) == "table" and not rawget(cur, "_wilds") and self.plain[npc] ~= cur then
        -- a sheet we have not judged yet (new on the map, or the engine just changed it)
        self.shown[npc] = nil
        local species, shiny
        if EnginePatch.npcFacts(npc, facts) then
          facts.gen = gen
          species, shiny = StaticMons.classify(facts, isSpecies, speciesOf)
        end
        rec = species and self:_dress(npc, species, shiny == true, style) or nil
        if rec then
          self.shown[npc] = rec
          self.plain[npc] = nil
          rec.renderer.poseOverride = poseOf(rec, npc)
        else
          self.plain[npc] = cur
        end
      end
    end
  end
end

--- Gives every object back its engine sheet (and forgets them all).
function StaticMons:restoreAll()
  for npc, rec in pairs(self.shown) do
    if npc.sprite == rec.wrapper then undress(npc) end
  end
  self.shown = setmetatable({}, { __mode = "k" })
  self.plain = setmetatable({}, { __mode = "k" })
end

--- How many of the map's objects are shown in our art right now (drivers / tests).
function StaticMons:count()
  local list = EnginePatch.mapNpcs and EnginePatch.mapNpcs()
  local n = 0
  for i = 1, type(list) == "table" and #list or 0 do
    local npc = list[i]
    local rec = type(npc) == "table" and self.shown[npc]
    if rec and npc.sprite == rec.wrapper then n = n + 1 end
  end
  return n
end

return StaticMons
