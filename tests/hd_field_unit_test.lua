-- Run: lua tests/hd_field_unit_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local failures = 0
local function check(cond, msg)
  if not cond then failures = failures + 1; io.stderr:write("FAIL: " .. tostring(msg) .. "\n") else print("ok  " .. tostring(msg)) end
end
local function near(a, b) return math.abs(a - b) < 1e-9 end

local modules = {}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  modules[name] = assert(loadfile("lib/" .. name .. ".lua"))(V)
  return modules[name]
end
local HdField = V.require("hd_field")
local Sizes = V.require("HGSS_scale")

check(type(Sizes[25]) == "number", "HGSS_scale has Pikachu")
check(near(HdField.factorFor("hgss", 25), Sizes[25]), "a dex number reads its HGSS_scale size")
check(near(HdField.factorFor("hgss", "025"), Sizes[25]), "...and a zero-padded art key too")
check(near(HdField.factorFor("hgss", "201-b"), Sizes[201] or 1), "a form without its own entry is sized like its base")
check(HdField.factorFor("hgss", 99999) == 1, "an unknown species is drawn at 1")
check(HdField.factorFor("hgss", nil) == 1, "...and no key at all")
HdField.setSpeciesSizes(false)
check(HdField.factorFor("hgss", 25) == 1, "Species Sizes off: everything at 1")
HdField.setSpeciesSizes(true)
local Config = V.require("config")
local HGSS = "assets/wilds_generated/true_size18/hgss/025-normal.png"
local SWIM = "assets/wilds_generated/true_size18/swimming/131-shiny.png"
local GSC = "assets/wilds_generated/gsc/025-normal.png"
check(HdField.parse(HGSS).style == "hgss" and HdField.parse(HGSS).key == "025", "an HGSS land sheet is parsed")
check(HdField.parse(SWIM).style == "hgss" and HdField.parse(SWIM).dex == 131, "...and a swimming one")
check(HdField.parse(GSC).style == "gsc", "...and a GSC one")
check(HdField.parse("assets/ui/bubble.png") == nil, "anything else is not a sheet")
check(near(HdField.sizeOfPath(HGSS), Sizes[25] * Config.gbSizeRatio()), "an HGSS sheet: its species' size against the GB player")
check(HdField.sizeOfPath(GSC) == 1, "a GSC sheet keeps its size")
HdField.setSpeciesSizes(false)
check(HdField.sizeOfPath(HGSS) == 1, "Species Sizes off: the art's own size")
HdField.setSpeciesSizes(true)

check(HdField.tag({}, {}, HGSS) == false, "no WoobleView: nothing is tagged")
check(HdField.scaleOfPath({}, HGSS) == 1, "...and every sheet is drawn at its own size")

-- with WoobleView
local tagged = {}
local lib = { exports = {
  tag = function(img, spec) tagged[img] = spec end,
  untag = function(img) tagged[img] = nil end,
  isActive = function() return true end,
  enabled = function(pass) return pass == "field" end,
} }
local mod = { find = function(_, id) if id == "gen3-hd-sprites" then return lib end end }
local img, gimg, other = {}, {}, {}
check(HdField.tag(mod, img, HGSS, { 20, 30 }) == true, "WoobleView: an HGSS sheet is tagged")
check(tagged[img].lowPivot[2] == 30 and tagged[img].anchor == nil, "...about its real feet")
check(near(tagged[img].scale, HdField.sizeOfPath(HGSS)), "...at its size")
check(HdField.tag(mod, gimg, GSC) == true and tagged[gimg].anchor == "feet" and tagged[gimg].scale == 1,
  "a GSC sheet: at 1, about the frame's feet")
check(HdField.tag(mod, other, "assets/ui/bubble.png") == false and tagged[other] == nil, "anything else is not tagged")
check(near(HdField.scaleOfPath(mod, HGSS), HdField.sizeOfPath(HGSS)), "scaleOfPath: the size it is drawn at")
HdField.setSpeciesSizes(false)
check(tagged[img].scale == 1, "Species Sizes off re-sizes a sheet already tagged")
HdField.setSpeciesSizes(true)
HdField.setPlain(true)
check(tagged[img] == nil and tagged[gimg] == nil, "plain (Gen 1's grey modes): the sheets are untagged")
check(HdField.scaleOfPath(mod, HGSS) == 1, "...and drawn at their own size")
local late = {}
check(HdField.tag(mod, late, HGSS) == false and tagged[late] == nil, "...a sheet loaded meanwhile waits")
HdField.setPlain(false)
check(tagged[img] ~= nil and tagged[late] ~= nil, "back on: every sheet is tagged again")
lib.exports.enabled = function() return false end
check(HdField.scaleOfPath(mod, HGSS) == 1, "Field HD off: drawn at its own size")

if failures > 0 then io.stderr:write(failures .. " failure(s)\n") os.exit(1) end
print("hd_field_unit_test: all passed")
