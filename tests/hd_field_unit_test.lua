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
check(HdField.tag({}, {}, "x.png") == false, "nothing is tagged on the flat field")
check(HdField.scaleOfPath({}, "x.png") == 1, "...and every sheet is drawn at its own size")

if failures > 0 then io.stderr:write(failures .. " failure(s)\n") os.exit(1) end
print("hd_field_unit_test: all passed")
