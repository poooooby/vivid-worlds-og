-- In-game check that wild Pokemon never share a tile, run like tests/drivers/smoke.lua:
--   POKEPORT_DRIVER=<this> POKEPORT_VERSION=red|crystal lovec .
-- Spawn Amount High, Classic Enc off, then 3600 frames with the player standing in the
-- grass: every frame, no two wild Pokemon may stand on (or step into) the same cell.
local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local VERSION = tostring(GameVersion.get())
local GEN = GameVersion.generation and GameVersion.generation() or 1

return function(game)
  require("mods.vivid_worlds_og.tests.drivers.novsync")(game) -- full speed over RDP too
  local fails = 0
  local function say(line) print("[vwog-overlap] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
    return cond
  end

  U.wait(60)
  local ex = game.mods and game.mods.exports and game.mods.exports.vivid_worlds_og
  if not ok(ex ~= nil and ex.engineReady, VERSION .. ": Vivid Worlds: OG installed") then
    love.event.quit(1)
    return
  end
  local sm = ex.spawnManager
  local opts = game.mods.modOptions
  opts.vivid_worlds_og = opts.vivid_worlds_og or {}
  opts.vivid_worlds_og.classic_enc = false
  opts.vivid_worlds_og.spawn_amount = "high"
  opts.vivid_worlds_og.wild_reacts = false -- nobody chases the player into a battle
  if GEN == 1 then
    U.teleport(game, "ROUTE_1", 14, 8, "down")
  else
    game.world:warpToMapId("ROUTE_29", 17, 5, "down")
  end
  U.wait(240)

  local steps, clashes, most = 0, 0, 0
  local prev = {}
  for _ = 1, 3600 do
    coroutine.yield()
    local seen, live = {}, 0
    for _, id in ipairs(sm.order) do
      local e = sm.entities[id]
      if e and e.state ~= "despawned" then
        live = live + 1
        local key = e.cellX .. "," .. e.cellY
        if seen[key] then clashes = clashes + 1 end
        seen[key] = true
        if e.moving and e.targetX then
          local t = e.targetX .. "," .. e.targetY
          if t ~= key then
            if seen[t] then clashes = clashes + 1 end
            seen[t] = true
          end
        end
        if prev[id] and prev[id] ~= key then steps = steps + 1 end
        prev[id] = key
      end
    end
    if live > most then most = live end
  end
  say(string.format("up to %d wild Pokemon, %d steps taken, %d frames with a shared cell", most, steps, clashes))
  ok(most >= 4, "a crowd to test with")
  ok(steps >= 20, "they wandered")
  ok(clashes == 0, "no two wild Pokemon ever on (or stepping into) the same cell")
  say(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  love.event.quit(fails == 0 and 0 or 1)
end
