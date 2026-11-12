-- National-dex overworld sheet lookup, borrowed from Wilds of Kanto
-- Revival's assets (see tools/copy_wilds_assets.py -- a read-only copy, not
-- a shared runtime dependency) plus a new 18-frame bake of our own
-- (tools/generate_true_size_18frame.py) from Wilds' raw source grids.
--
-- Two independent dimensions: `style` (which art family: HGSS / PokeMMO, or Poke Followers /
-- GSC with HGSS for what it lacks) and
-- `presentation` (land vs water kind, from where the Pokemon is standing).
--
--   style = "pokemmo" (HGSS / PokeMMO, "True Size" -- native per-species
--   frame size). 18 frames (stand x3, walk-A/walk-B x3 directions,
--   run-base/run-A/run-B x3 directions -- see lib/actor_renderer.lua and
--   tools/generate_true_size_18frame.py for the exact layout and how the
--   run frames reuse walk art, since there is no dedicated running
--   source). Presentation selects which baked pack:
--     assets/wilds_generated/true_size18/hgss/%03d-{normal,shiny}.png       (land)
--     assets/wilds_generated/true_size18/swimming/%03d-{normal,shiny}.png   (water)
--     assets/wilds_generated/true_size18/levitates/%03d-{normal,shiny}.png  (water)
--   For water presentation, "swimming" is tried first and "levitates"
--   second -- confirmed against Wilds of Kanto Revival's own
--   water_sprite_registry.lua that this exact try-order IS the real
--   behaviour: its per-species preferredWaterKind override field exists
--   in the code but is unset on every single entry in the real mapping
--   data (checked directly), so "try swimming, fall back to levitates" is
--   not a simplification, it's what actually happens. If neither water
--   pack covers a dex (narrower coverage than land), falls through to
--   land art rather than drawing nothing.
--
-- Either way, a species with no genuine shiny source art falls back to
-- its own normal sheet -- never a guessed palette recolor.
--
-- MAX_DEX is 1025 (Wilds' own full National Dex coverage), not Gen 3's
-- native 386 -- a dex-expansion mod for Gen 3 (gen1recomp's
-- `national_dex_gen3`) can put species beyond 386 in a real RSE save, and
-- nationalFor()/speciesForNational() make no 386 assumption either, so
-- there is no reason to cap art lookup lower than the species the engine
-- could actually hand us. See tools/copy_wilds_assets.py.
--
-- Sprite identity is always the national dex number, never engine-internal
-- species id or display name -- see lib/engine_patch.lua's
-- nationalFor/speciesForNational.
--
-- Everything ships in the release ZIP as a baked atlas
-- (tools/generate_sprite_atlases.py, lib/sprite_atlas.lua), not as
-- thousands of individual files -- SpriteSource only ever resolves a
-- RELATIVE path; lib/actor_renderer.lua decides whether that path comes
-- from a real file or an atlas shard.

local V = ...

-- Which relative paths exist also depends on the sprite atlas: a release ZIP
-- ships the HGSS sheets only as atlas shards, never as loose files.
-- (V is nil in the standalone tests that load this file bare.)
local SpriteAtlas = V and V.require("sprite_atlas") or nil

local SpriteSource = {}

local TRUE_SIZE18_REL = "assets/wilds_generated/true_size18"
-- Poke Followers / GSC (style "followers"): 16x96 sheets, six 16x16 frames in the engine's
-- SpriteRenderer order (tools/copy_wilds_assets.py copies them in as <key>-<variant>.png)
local GSC_REL = "assets/wilds_generated/gsc"
SpriteSource.GSC_REL = GSC_REL
local MAX_DEX = 1025

SpriteSource.STYLE_POKEMMO = "pokemmo"
SpriteSource.STYLE_FOLLOWERS = "followers" -- Poke Followers / GSC, HGSS where it has no art
SpriteSource.DEFAULT_STYLE = SpriteSource.STYLE_POKEMMO

SpriteSource.PRESENTATION_LAND = "land"
SpriteSource.PRESENTATION_SWIMMING = "swimming"
SpriteSource.PRESENTATION_LEVITATES = "levitates"
SpriteSource.DEFAULT_PRESENTATION = SpriteSource.PRESENTATION_LAND

-- A caller that only knows "this entity is standing in water" (not which
-- water kind) should pass this -- see the module header for why "swimming
-- first, levitates second" is the real behaviour and not a simplification.
SpriteSource.DEFAULT_WATER_PRESENTATION = SpriteSource.PRESENTATION_SWIMMING

-- An ART KEY names one sheet: a plain national dex NUMBER for a base species,
-- or the string "%03d-<form>" for an alternate form ("413-sandy", "479-heat",
-- "670-eternal"; lib/form_source.lua builds it). Forms share their base's dex
-- number, so the key -- never the number -- is what tells them apart. A form
-- with no art of its own falls back to its base species' sheet.
--- "%03d" for a dex number, the string itself for a form key.
function SpriteSource.keyName(key)
  if type(key) == "number" then return string.format("%03d", key) end
  return tostring(key)
end

--- The base species' dex number behind an art key (nil when malformed).
function SpriteSource.baseOf(key)
  if type(key) == "number" then return key end
  if type(key) == "string" then return tonumber(key:match("^(%d+)")) end
  return nil
end

--- true for a form key ("413-sandy"), false for a plain dex number.
function SpriteSource.isForm(key)
  return type(key) == "string" and key:find("^%d+%-.") ~= nil
end

local function validKey(key)
  local base = SpriteSource.baseOf(key)
  return base ~= nil and base >= 1 and base <= 1025
end

local function fileExists(mod, rel)
  -- baked into the atlas (a release ZIP has no loose per-species sheets)
  if SpriteAtlas and SpriteAtlas.installed() and SpriteAtlas.has(rel) then return true end
  if mod and mod.assets and type(mod.assets.exists) == "function" then
    local ok, exists = pcall(mod.assets.exists, mod, rel)
    if ok then return exists == true end
  end
  -- Standalone unit tests: a fake mod.read/io.open probe. Real contract:
  -- mod:read returns file bytes or nil (see lib/config.lua's own use of
  -- it for options.lua), never a plain boolean.
  if mod and type(mod.read) == "function" then
    local ok, data = pcall(mod.read, mod, rel)
    return ok and data ~= nil
  end
  local f = io.open(rel, "rb")
  if f then f:close() return true end
  return false
end

-- presentation -> true_size18 folder name. Land art's baked folder is
-- "hgss" (tools/generate_true_size_18frame.py's KINDS, inherited from the
-- style name before `presentation` existed as its own dimension) -- NOT
-- "land" -- swimming/levitates match their presentation name exactly.
local TRUE_SIZE18_FOLDER = {
  [SpriteSource.PRESENTATION_LAND] = "hgss",
  [SpriteSource.PRESENTATION_SWIMMING] = "swimming",
  [SpriteSource.PRESENTATION_LEVITATES] = "levitates",
}

local function trueSize18Path(mod, dex, presentation, variant)
  local folder = TRUE_SIZE18_FOLDER[presentation]
  if not folder then return nil end
  local p = string.format("%s/%s/%s-%s.png", TRUE_SIZE18_REL, folder, SpriteSource.keyName(dex), variant)
  if fileExists(mod, p) then return p end
  return nil
end

local function pokemmoPath(mod, dex, presentation, variant)
  if presentation == SpriteSource.PRESENTATION_SWIMMING or presentation == SpriteSource.PRESENTATION_LEVITATES then
    local p = trueSize18Path(mod, dex, presentation, variant)
    if p then return p end
    -- That specific water kind has no art for this dex -- try the other
    -- water kind before giving up to land (narrower coverage than land
    -- is expected; see module header).
    local other = (presentation == SpriteSource.PRESENTATION_SWIMMING)
      and SpriteSource.PRESENTATION_LEVITATES or SpriteSource.PRESENTATION_SWIMMING
    p = trueSize18Path(mod, dex, other, variant)
    if p then return p end
    return trueSize18Path(mod, dex, SpriteSource.PRESENTATION_LAND, variant)
  end
  return trueSize18Path(mod, dex, SpriteSource.PRESENTATION_LAND, variant)
end

--- rel path for a dex's normal sheet in the given presentation ("land" |
--- "swimming" | "levitates"). `style` is accepted for the callers that
--- always pass it but there is only one baked family now (HGSS / PokeMMO,
--- 18 frames); an unknown or stale style (a saved "followers" option from
--- before that style was removed) draws it too. Returns nil if nothing at
--- all covers this dex.
function SpriteSource.normalPath(mod, dex, _style, presentation)
  if not validKey(dex) then return nil end
  return pokemmoPath(mod, dex, presentation or SpriteSource.DEFAULT_PRESENTATION, "normal")
end

--- rel path for a dex's shiny sheet, same style/presentation/fallback
--- rules as normalPath. Returns nil if no genuine shiny source art exists
--- (caller should fall back to normalPath, not synthesize a recolor).
function SpriteSource.shinyPath(mod, dex, _style, presentation)
  if not validKey(dex) then return nil end
  return pokemmoPath(mod, dex, presentation or SpriteSource.DEFAULT_PRESENTATION, "shiny")
end

--- The path this mod actually draws for (dex, shiny, style,
--- presentation): shiny art when it exists and shiny was asked for, the
--- normal sheet otherwise. Never nil for a dex 1..1025 with the asset
--- copy present (water falls through water -> water -> land, see
--- pokemmoPath).
function SpriteSource.pathFor(mod, dex, shiny, style, presentation)
  -- a form's own art first (shiny, then normal), then its base species'
  local keys = { dex }
  if SpriteSource.isForm(dex) then keys[2] = SpriteSource.baseOf(dex) end
  local gsc = style == SpriteSource.STYLE_FOLLOWERS
    and (presentation == nil or presentation == SpriteSource.PRESENTATION_LAND)
  for _, key in ipairs(keys) do
    -- Poke Followers / GSC on land: its own sheet, else HGSS -- a shiny with no GSC shiny
    -- art takes the HGSS shiny (a shiny is never shown plain); water is always HGSS
    if shiny then
      local p = (gsc and SpriteSource.gscPath(mod, key, "shiny")) or SpriteSource.shinyPath(mod, key, style, presentation)
      if p then return p end
    end
    local p = (gsc and SpriteSource.gscPath(mod, key, "normal")) or SpriteSource.normalPath(mod, key, style, presentation)
    if p then return p end
  end
  return nil
end

--- A Poke Followers / GSC sheet for art key `key` ("025", "201-b") and `variant`
--- ("normal" | "shiny"), or nil when that style has no art for it.
function SpriteSource.gscPath(mod, key, variant)
  if not validKey(key) then return nil end
  local p = string.format("%s/%s-%s.png", GSC_REL, SpriteSource.keyName(key), variant)
  if fileExists(mod, p) then return p end
  return nil
end

--- Is `path` a Poke Followers / GSC sheet?
function SpriteSource.isGsc(path)
  return type(path) == "string" and path:sub(1, #GSC_REL + 1) == GSC_REL .. "/"
end

--- How many frames the sheet at `path` stacks: 6 for a GSC sheet (the engine's own
--- SpriteRenderer layout), 18 for an HGSS / PokeMMO one.
function SpriteSource.frameCountOf(path)
  return SpriteSource.isGsc(path) and 6 or 18
end

--- Whether an art key (a form) has HGSS / PokeMMO art of its own on land.
function SpriteSource.hasOwnArt(mod, key)
  return validKey(key) and trueSize18Path(mod, key, SpriteSource.PRESENTATION_LAND, "normal") ~= nil
end

--- Whether a species floats/flies, for the idle wing-flap
--- (ActorRenderer.idleFlapPose). Uses the baked "levitates" pack purely as a
--- species REFERENCE -- membership means "hovers/flies"; that art is never
--- drawn for this (it is the water pack, see pokemmoPath). Independent of
--- Sprite Style and presentation, and memoized per dex (asset presence never
--- changes at runtime).
local floaterCache = {}
-- In the levitates pack but deliberately NOT given the idle flap.
local NOT_FLOATERS = {
  [6] = true, -- Charizard
}
function SpriteSource.isFloater(mod, dex)
  if not validKey(dex) then return false end
  if NOT_FLOATERS[dex] then return false end
  local hit = floaterCache[dex]
  if hit == nil then
    hit = trueSize18Path(mod, dex, SpriteSource.PRESENTATION_LEVITATES, "normal") ~= nil
    if not hit and SpriteSource.isForm(dex) then
      hit = SpriteSource.isFloater(mod, SpriteSource.baseOf(dex))
    end
    floaterCache[dex] = hit
  end
  return hit
end
function SpriteSource._resetFloaterCache() floaterCache = {} end


--- Transparent rows baked under the water packs' frames (swimming/levitates;
--- tools/generate_true_size_18frame.py's WATER_PAD). 0 for every other sheet.
--- ActorRenderer shifts such a frame down by this much so the creature's feet
--- stay flush with the tile instead of floating above it.
SpriteSource.WATER_BOTTOM_PAD = 2
function SpriteSource.bottomPadFor(path)
  if type(path) == "string" and (path:find("/true_size18/swimming/", 1, true)
      or path:find("/true_size18/levitates/", 1, true)) then
    return SpriteSource.WATER_BOTTOM_PAD
  end
  return 0
end

SpriteSource.MAX_DEX = MAX_DEX

return SpriteSource
