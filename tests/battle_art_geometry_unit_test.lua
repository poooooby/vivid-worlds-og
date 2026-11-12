-- Run: lua tests/battle_art_geometry_unit_test.lua
-- lib/compat/battle_art_variable_geometry.lua (Battle Art, Red / Blue / Yellow) and
-- lib/compat/battle_art_gen2_geometry.lua (Battle Art Gen 2): Wilds of Kanto Revival's two
-- adapters. Each wraps its provider's SpriteBillboards so our voxel sheets (a def with its
-- own geometry) get a card of their own size, a classic 16x16 def keeps the provider's card,
-- and Gen 2's halfWidth places a sized card on the billboard pivot.
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then failures = failures + 1; io.stderr:write("FAIL: " .. tostring(msg) .. "\n") else print("ok  " .. tostring(msg)) end
end
local function eq(a, b, msg)
  check(a == b, string.format("%s (got %s expected %s)", msg, tostring(a), tostring(b)))
end

local modules = {}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  modules[name] = assert(loadfile("lib/" .. name .. ".lua"))(V)
  return modules[name]
end

local fakeAssets = {
  image = function() return { getDimensions = function() return 64, 384 end } end,
  register = function() end,
}
local realRequire = require
require = function(p) if p == "src.render.Assets" then return fakeAssets end return realRequire(p) end

local ours = { image = "vivid_worlds_og/voxel/x.png", frames = 6, frameWidth = 64, frameHeight = 64,
  anchorX = 32, anchorY = 64 }

for _, case in ipairs({
  { file = "compat/battle_art_variable_geometry", id = "BATTLE_ART_VOXEL_FORK", idField = "BATTLE_ART_ID" },
  { file = "compat/battle_art_gen2_geometry", id = "BATTLE_ART_VOXEL_GEN2", idField = "BATTLE_ART_GEN2_ID", gen2 = true },
}) do
  local made = 0
  local SB = {}
  SB.mesh = function(def) return "orig:" .. tostring(def.image) end
  SB.shadowQuad = SB.mesh
  SB.invalidate = function() end
  if case.gen2 then SB.halfWidth = function(def) return (tonumber(def.frameWidth) or 16) / 2 end end
  local Voxel3D = {
    pushQuad = function(ind) ind[#ind + 1] = 1 end,
    newMesh = function(verts) made = made + 1 return { verts = verts } end,
  }
  local provider = { exports = { lib = { require = function(n)
    if n == "SpriteBillboards" then return SB end
    if n == "Voxel3D" then return Voxel3D end
  end } } }
  local mod = { find = function(_, id) return id == case.id and provider or nil end,
    log = { info = function() end, warn = function() end } }
  local Adapter = V.require(case.file)
  eq(Adapter[case.idField], case.id, case.id .. ": the adapter is for that provider")
  check(Adapter.install(mod), case.id .. ": installs over its SpriteBillboards")
  local m = SB.mesh(ours, 3)
  check(type(m) == "table" and m.verts, case.id .. ": our sheet gets a card of its own")
  if type(m) == "table" and m.verts then
    local xs = {}
    for _, v in ipairs(m.verts) do xs[#xs + 1] = v[1] end
    table.sort(xs)
    eq(xs[#xs] - xs[1], 64, case.id .. ": 64 px wide")
  end
  check(SB.mesh(ours, 3) == m and made == 1, case.id .. ": cached")
  eq(SB.mesh({ image = "red.png" }, 0), "orig:red.png", case.id .. ": a classic 16x16 def keeps the provider's card")
  check(SB.shadowQuad(ours, 3) == m, case.id .. ": the shadow / silhouette pass gets the same card")
  if case.gen2 then
    eq(SB.halfWidth(ours), 8, case.id .. ": a sized card is placed on the billboard pivot (halfWidth 8)")
    eq(SB.halfWidth({ image = "red.png", frameWidth = 16 }), 8, case.id .. ": a classic def keeps Gen 2's own halfWidth")
  end
  Adapter.reset()
  eq(SB.mesh({ image = "a" }), "orig:a", case.id .. ": reset puts the provider's own back")
  check(not Adapter.install({ find = function() return nil end, log = { info = function() end } }),
    case.id .. ": no provider loaded, nothing installed")
  Adapter.reset()
end

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("battle_art_geometry_unit_test: all passed")
