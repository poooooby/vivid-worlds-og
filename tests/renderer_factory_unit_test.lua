-- Run: lua tests/renderer_factory_unit_test.lua
-- lib/renderer_factory.lua: every Pokemon is an HGSS / PokeMMO ActorRenderer.
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  else
    print("ok  " .. tostring(msg))
  end
end
local function eq(a, b, msg)
  check(a == b, string.format("%s (got %s expected %s)", msg, tostring(a), tostring(b)))
end

local modules = {}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end
local mod = { read = function() return nil end }
V.mod = mod

local Factory = V.require("renderer_factory")

local r = Factory.new(mod, 252, false, "pokemmo")
check(not r.isPmd, "pokemmo style is an ActorRenderer")
eq(r.style, "pokemmo", "...in the HGSS / PokeMMO style")
eq(r.frameCount, 18, "...with the 18-frame layout")
local stale = Factory.new(mod, 252, false, "pmd")
check(not stale.isPmd and stale.frameCount == 18, "a stale 'pmd' style is still an 18-frame ActorRenderer")
eq(Factory.pmdSwims(252, "swimming"), false, "nothing is cut at a baked waterline")

if failures > 0 then io.stderr:write(failures .. " failure(s)\n") os.exit(1) end
print("renderer_factory_unit_test: all passed")
