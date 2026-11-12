-- Boots vivid_worlds_og through gen1recomp's REAL mod-SDK harness (tests/modkit): the real
-- src.mods.Loader, real manifest validation, and EnginePatch.install() probing and wrapping
-- the REAL Gen 1 OverworldController / Gen 2 World (no fakes anywhere in this file).
--
-- Run from inside a gen1recomp checkout with this mod linked at mods/vivid_worlds_og
-- (scripts/bootstrap.sh), with luajit:
--   cd ../gen1recomp
--   luajit mods/vivid_worlds_og/tests/modkit_boot_test.lua
--
-- The modkit fixture dataset (tests/modkit/fixtures.lua) carries no extracted ROM data, so
-- no wild Pokemon are placed here -- real spawning is covered by the unit tests (faked
-- engine) and the in-game drivers (tests/drivers/).
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

love = love or require("tests.love_stub")
local GameVersion = require("src.core.GameVersion")
local Runtime = require("src.mods.Runtime")
local T = require("tests.modkit")

local CASES = {
  { game = "red", gen = 1, layout = "gen1", roles = true },
  { game = "yellow", gen = 1, layout = "gen1", roles = true },
  { game = "gold", gen = 2, layout = "gen2" },
  { game = "crystal", gen = 2, layout = "gen2" },
}

for _, case in ipairs(CASES) do
  GameVersion.set(case.game)
  local r = T.sdk.loadMod("mods/vivid_worlds_og", { data = T.fixtures.fresh(), generation = case.gen })
  eq(#r.errors, 0, case.game .. ": loads with no Loader errors")
  local m = r.loader.mods.vivid_worlds_og
  eq(m and m.state, "loaded", case.game .. ": the mod reaches loaded")
  local ex = r.loader.exports and r.loader.exports.vivid_worlds_og
  eq(ex and ex.layout, case.layout, case.game .. ": layout " .. case.layout)
  eq(ex and ex.engineReady, true, case.game .. ": engineReady (the real Gen " .. case.gen .. " probe passed)")
  eq(ex and ex.enginePatch and ex.enginePatch.isGb, true, case.game .. ": the Game Boy engine layer is in charge")
  check(ex and ex.spawnManager ~= nil and ex.battleTrigger ~= nil and ex.followerAdapter ~= nil,
    case.game .. ": spawns, battles and the partner are built")
  check(ex and ex.companion ~= nil and ex.forager ~= nil and ex.battler ~= nil,
    case.game .. ": the companion, Forager and Battler are built")
  eq(ex and ex.enginePatch and ex.enginePatch.supports("roles") == true, case.roles == true,
    case.game .. ": partner roles " .. (case.roles and "on" or "not yet"))
  local okE, errE = pcall(Runtime.emit, "map.entered", { mapId = "ROUTE_1" })
  check(okE, case.game .. ": a real map.entered does not throw (" .. tostring(errE) .. ")")
  eq(ex and ex.spawnManager and ex.spawnManager.mapId, "ROUTE_1", case.game .. ": the event reached the spawn manager")
  local steppedAt
  local realOnStepped = ex and ex.battleTrigger and ex.battleTrigger.onPlayerStepped
  if realOnStepped then
    ex.battleTrigger.onPlayerStepped = function(self, x, y)
      steppedAt = { x = x, y = y }
      return realOnStepped(self, x, y)
    end
  end
  local okS, errS = pcall(Runtime.emit, "world.stepped", { mapId = "ROUTE_1", x = 3, y = 4 })
  check(okS, case.game .. ": a real world.stepped does not throw (" .. tostring(errS) .. ")")
  check(steppedAt ~= nil and steppedAt.x == 3 and steppedAt.y == 4, case.game .. ": world.stepped reached the battle trigger")
  if realOnStepped then ex.battleTrigger.onPlayerStepped = realOnStepped end
  local okX = pcall(Runtime.emit, "map.exited", { mapId = "ROUTE_1" })
  check(okX, case.game .. ": a real map.exited does not throw")
  if ex and ex.enginePatch and ex.enginePatch.uninstall then ex.enginePatch.uninstall() end
  r.release()
end

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("modkit_boot_test: all passed")
