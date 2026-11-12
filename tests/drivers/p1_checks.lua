-- In-game checks for the P1 core work (reachability, Safari, Bug-Catching Contest, type names),
-- run like tests/drivers/smoke.lua:
--   POKEPORT_DRIVER=<this> POKEPORT_VERSION=red|crystal VWOG_SHOT_DIR=<dir> lovec .
local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local VERSION = tostring(GameVersion.get())
local GEN = GameVersion.generation and GameVersion.generation() or 1

return function(game)
  local fails = 0
  local function say(line) print("[vwog-p1] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
    return cond
  end
  local function finish()
    say(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
    love.event.quit(fails == 0 and 0 or 1)
  end

  U.wait(60)
  local ex = game.mods and game.mods.exports and game.mods.exports.vivid_worlds_og
  if not ok(ex ~= nil and ex.engineReady, VERSION .. ": Vivid Worlds: OG installed") then return finish() end
  local EP, sm = ex.enginePatch, ex.spawnManager

  ok(EP.typeName("PSYCHIC_TYPE") == "PSYCHIC" and EP.typeName("WATER") == "WATER",
    "type names: PSYCHIC_TYPE reads as PSYCHIC")

  local function landCells()
    local all = 0
    for _, c in ipairs(sm.source.cells and sm.source.cells.land or {}) do if c then all = all + 1 end end
    return all, #sm.source:eligibleCells("land")
  end

  if GEN == 1 then
    local Pokemon = require("src.pokemon.Pokemon")
    game.save.party = { Pokemon.new(game.data, "PIKACHU", 15) }
    -- Route 1 from the south: its ledges only drop south, so the north half is reachable,
    -- the far side of each ledge from below is not
    U.teleport(game, "ROUTE_1", 14, 8, "down")
    U.wait(180)
    local all, reach = landCells()
    say(string.format("Route 1: %s reachable cells; land spawn cells %d of %d", tostring(sm.reachCount), reach, all))
    ok(sm.reach ~= nil and (sm.reachCount or 0) > 0, "Gen 1: the reachable area is measured")
    ok(sm:count() > 0, "Gen 1: wild Pokemon spawn inside it (" .. sm:count() .. ")")

    -- the Safari Zone: a running visit makes the Battler leave its Pokemon be
    game.save.safari = { balls = 30, steps = 500 }
    U.teleport(game, "SAFARI_ZONE_CENTER", 14, 22, "down")
    U.wait(180)
    ok(EP.safariActive() == true, "Gen 1: the Safari Zone visit is seen (" .. tostring(sm.mapId) .. ")")
    game.save.safari = nil
    U.teleport(game, "ROUTE_1", 14, 8, "down")
    U.wait(60)
    ok(EP.safariActive() == false, "Gen 1: and not outside it")
  else
    local Mon = require("src.battle.gen2.Mon")
    game.save.party = { Mon.new(game.data, "CYNDAQUIL", 15) }
    game.world:warpToMapId("ROUTE_29", 17, 5, "down")
    U.wait(180)
    local all, reach = landCells()
    say(string.format("Route 29: %s reachable cells; land spawn cells %d of %d", tostring(sm.reachCount), reach, all))
    ok(sm.reach ~= nil and (sm.reachCount or 0) > 0, "Gen 2: the reachable area is measured")
    ok(sm:count() > 0, "Gen 2: wild Pokemon spawn inside it (" .. sm:count() .. ")")

    -- Union Cave: Gold's one-way edges keep pockets out
    game.world:warpToMapId("UNION_CAVE_1F", 17, 31, "up")
    U.wait(180)
    local cAll, cReach = landCells()
    say(string.format("Union Cave 1F: %s reachable cells; land spawn cells %d of %d", tostring(sm.reachCount), cReach, cAll))
    ok(sm.reach ~= nil and cReach <= cAll, "Gen 2: a cave's spawn cells are limited to what can be reached")

    -- the Bug-Catching Contest: no visible spawns in the park while it runs
    local BugContest = require("src.core.gen2.BugContest")
    BugContest.start(game.save)
    game.world:warpToMapId("NATIONAL_PARK", 10, 20, "down")
    U.wait(240)
    ok(EP.spawnsPaused() == true, "Gen 2: the contest pauses visible spawns")
    ok(sm:count() == 0, "Gen 2: no visible spawns in the park during the contest (" .. sm:count() .. ")")
  end
  finish()
end
