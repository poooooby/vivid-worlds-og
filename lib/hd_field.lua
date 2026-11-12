-- Species Sizes: each species' size next to the player, from lib/HGSS_scale.lua (Wilds of
-- Kanto Revival's hand-edited dex -> size table; a form key such as "201-b" sizes one form).
--
-- The flat 2D field draws every HGSS sheet at its own art size (the art already differs in
-- size per species). The factor only sizes the 3D world mods' cards (lib/voxel_sheets.lua).
-- tag / scaleOfPath are the no-ops of a field that is never redrawn at window resolution
-- (that is a Gen 3 sprite mod's job), kept so lib/actor_renderer.lua needs no branch.
local V = ...

local HdField = {}

local SizeTable
do
  local ok, value = pcall(V.require, "HGSS_scale")
  if ok and type(value) == "table" then SizeTable = value end
end

HdField.speciesSizes = true -- the Species Sizes option

local function lookup(key, dex)
  if type(SizeTable) ~= "table" then return nil end
  local v = SizeTable[key]
  if v == nil then v = SizeTable[tonumber(key)] end
  if v == nil and dex then v = SizeTable[dex] end
  if type(v) == "number" and v > 0 then return v end
  return nil
end

--- The size factor for art `key` ("25", "201-b", 25): 1 with Species Sizes off or no entry.
--- `style` is kept for the callers' shape; only "hgss" exists.
function HdField.factorFor(_style, key)
  if not HdField.speciesSizes or key == nil then return 1 end
  local k = tostring(key)
  return lookup(k, tonumber(k:match("^(%d+)"))) or 1
end

--- The Species Sizes option (on / off).
function HdField.setSpeciesSizes(on)
  HdField.speciesSizes = on ~= false
  return HdField.speciesSizes
end

--- No window-resolution field on Game Boy: nothing is tagged.
function HdField.tag() return false end

--- Every sheet draws at its own size on the flat field.
function HdField.scaleOfPath() return 1 end

return HdField
