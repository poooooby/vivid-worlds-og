-- Hands the overworld sprite sheets (wild Pokemon and the partner, both Sprite Styles) to
-- WoobleView (mod id gen3-hd-sprites) when it is installed with its Field HD on: the field
-- then draws them at the window's resolution instead of on the Game Boy's pixel grid, so an
-- HGSS sheet can be any size without lumpy pixels and walkers glide between pixels.
--
-- An HGSS sheet's size is its species' factor (lib/HGSS_scale.lua, Wilds of Kanto Revival's
-- hand-edited dex -> size table; a form key such as "201-b" sizes one form) against the
-- shorter Game Boy player (Config.gbSizeRatio), the size the 3D world mods' cards use too
-- (lib/voxel_sheets.lua); with Species Sizes off, the art's own size. A GSC sheet is already
-- drawn at the Game Boy's scale: it keeps its size and only moves smoothly.
--
-- Without that mod, or with its Field HD off, this does nothing and the sheets are drawn
-- exactly as before. In Gen 1's grey colour modes (the art drawn through the luminance shader
-- for the palette pass, lib/gb_color.lua) nothing is tagged either (HdField.setPlain): the
-- palette pass colours the field canvas, which a window-resolution sprite never reaches.
local V = ...

local HdField = {}

local function load(name)
  if V and V.require then
    local ok, value = pcall(V.require, name)
    if ok and type(value) == "table" then return value end
  end
  return nil
end
local SizeTable = load("HGSS_scale")
local Config = load("config")

HdField.speciesSizes = true -- the Species Sizes option
local MIN_SCALE, MAX_SCALE = 0.2, 2

local specs = setmetatable({}, { __mode = "k" }) -- image -> { scale, path, ... }
local plain = false   -- HdField.setPlain: nothing tagged right now
local lastMod         -- the mod a sheet was tagged for (setPlain re-tags through it)

local function library(mod)
  if not (mod and type(mod.find) == "function") then return nil end
  local ok, found = pcall(mod.find, mod, "gen3-hd-sprites")
  local ex = ok and found and found.exports
  if type(ex) ~= "table" or type(ex.tag) ~= "function" then return nil end
  return ex
end

-- path -> parsed info | false: the renderers ask for their sheet's size every frame, so a
-- path is matched once (a few hundred sheets at most); the info is shared -- read only
local parsed = {}

--- What a sprite sheet path is: style ("hgss" | "gsc"), art key ("025" or "201-b") and base
--- dex number. nil for anything else.
function HdField.parse(path)
  if type(path) ~= "string" then return nil end
  local hit = parsed[path]
  if hit ~= nil then return hit or nil end
  local info = false
  local key = path:match("/true_size18/%w+/(%d+[%w_%-]-)%-%a+%.png$")
  if key then
    info = { style = "hgss", key = key, dex = tonumber(key:match("^(%d+)")) }
  else
    local gkey = path:match("/wilds_generated/gsc/(%d+[%w_%-]-)%-%a+%.png$")
    if gkey then info = { style = "gsc", key = gkey, dex = tonumber(gkey:match("^(%d+)")) } end
  end
  parsed[path] = info
  return info or nil
end

local function lookup(key, dex)
  if type(SizeTable) ~= "table" then return nil end
  local v = SizeTable[key]
  if v == nil then v = SizeTable[tonumber(key)] end
  if v == nil and dex then v = SizeTable[dex] end
  if type(v) == "number" and v > 0 then return v end
  return nil
end

--- The size factor for art `key` ("25", "201-b", 25): 1 with Species Sizes off or no entry.
--- `style` is kept for the callers' shape; only "hgss" has sizes.
function HdField.factorFor(_style, key)
  if not HdField.speciesSizes or key == nil then return 1 end
  local k = tostring(key)
  return lookup(k, tonumber(k:match("^(%d+)"))) or 1
end

--- The size a sheet is drawn at on the field with WoobleView: an HGSS sheet its species'
--- factor against the Game Boy player (Species Sizes on; else 1), a GSC sheet 1.
function HdField.sizeOfPath(path)
  local info = HdField.parse(path)
  if not (info and info.style == "hgss" and HdField.speciesSizes) then return 1 end
  local ratio = Config and Config.gbSizeRatio and Config.gbSizeRatio() or 1
  local k = HdField.factorFor("hgss", info.key) * ratio
  return math.max(MIN_SCALE, math.min(MAX_SCALE, k))
end

--- Tag one sheet image (from ActorRenderer.loadImage) loaded from `path`; `feetPivot`
--- (optional) is the point in the frame its real feet stand on. Safe with no library. Only
--- the sprite sheets are tagged.
function HdField.tag(mod, image, path, feetPivot)
  if image == nil or not HdField.parse(path) then return false end
  local spec = { filter = "nearest", path = path }
  if feetPivot then
    spec.lowPivot = feetPivot
  else
    spec.anchor = "feet" -- a size change keeps a Pokemon standing on its spot
  end
  spec.scale = HdField.sizeOfPath(path)
  specs[image] = spec
  lastMod = mod
  if plain then return false end
  local ex = library(mod)
  if not ex then return false end
  return (pcall(ex.tag, image, spec))
end

--- Nothing tagged while `on` (Gen 1's grey colour modes, see the header): the sheets
--- already loaded are untagged, and tagged again when it goes off. Cheap when unchanged.
function HdField.setPlain(on)
  on = on == true
  if on == plain then return plain end
  plain = on
  local ex = library(lastMod)
  if ex then
    for image, spec in pairs(specs) do
      if on then
        if type(ex.untag) == "function" then pcall(ex.untag, image) end
      else
        pcall(ex.tag, image, spec)
      end
    end
  end
  return plain
end

--- The "Species Sizes" option (on / off): applies to the sheets already loaded too.
function HdField.setSpeciesSizes(on)
  HdField.speciesSizes = on ~= false
  for _, spec in pairs(specs) do spec.scale = HdField.sizeOfPath(spec.path) end
  return HdField.speciesSizes
end

--- Is the library there and drawing the field at full resolution right now?
function HdField.active(mod)
  if plain then return false end
  local ex = library(mod)
  if not ex then return false end
  if type(ex.isActive) == "function" then
    local ok, on = pcall(ex.isActive)
    if not (ok and on) then return false end
  end
  if type(ex.enabled) == "function" then
    local ok, on = pcall(ex.enabled, "field")
    if ok and on == false then return false end
  end
  return true
end

--- How big the sheet at `path` is actually drawn (1 without the library): what a caller
--- spacing sprites out by their width has to use instead of the sheet's.
function HdField.scaleOfPath(mod, path)
  if not HdField.active(mod) then return 1 end
  return HdField.sizeOfPath(path)
end

return HdField
