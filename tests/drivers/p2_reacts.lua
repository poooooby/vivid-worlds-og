-- In-game check of Wild Reacts (biking past wild Pokemon), run like tests/drivers/smoke.lua:
--   POKEPORT_DRIVER=<this> POKEPORT_VERSION=crystal|red lovec .
-- A strong lead, a few wild Pokemon placed close by, the player on a bike riding past them:
-- at least one should react (startled "!" and flee, or angry and chase).
local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local VERSION = tostring(GameVersion.get())
local GEN = GameVersion.generation and GameVersion.generation() or 1

return function(game)
  local fails = 0
  local function say(line) print("[vwog-react] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
    return cond
  end

  U.wait(60)
  local ex = game.mods and game.mods.exports and game.mods.exports.vivid_worlds_og
  if not ok(ex ~= nil and ex.engineReady, VERSION .. ": Vivid Worlds: OG installed") then
    love.event.quit(1) return
  end
  local EP, sm = ex.enginePatch, ex.spawnManager
  ok(EP.supports("wild_reacts"), "this generation carries the wild reactions")

  local species
  if GEN == 1 then
    local Pokemon = require("src.pokemon.Pokemon")
    game.save.party = { Pokemon.new(game.data, "VENUSAUR", 60) }
    U.teleport(game, "ROUTE_1", 14, 8, "down")
    species = "PIDGEY"
  else
    local Mon = require("src.battle.gen2.Mon")
    game.save.party = { Mon.new(game.data, "TYPHLOSION", 60) }
    game.world:warpToMapId("ROUTE_29", 17, 5, "down")
    species = "SENTRET"
  end
  U.wait(120)
  U.wait(60) -- the route's own spawns (placing extras next to the player boxes it in)

  -- on the bike: Gold's player state, Red's save flag
  local w = EP.world()
  if GEN == 2 then
    if w then w.playerState = "bike" end
  else
    if game.save then game.save.onBike = true end
    if w and w.player then w.player.onBike = true end
  end
  ok(EP.playerBiking(), "the player counts as biking")

  local ctx = sm._reactContext and sm:_reactContext()
  say("react context: " .. tostring(ctx ~= nil) .. "; wild_reacts option " .. tostring(ex.lib == nil and "?" or ""))
  local pc = EP.playerCell()
  for _, id in ipairs(sm.order or {}) do
    local e = sm.entities[id]
    if e then say(string.format("  %s at %d,%d (player %d,%d) lv%s", tostring(e.species), e.cellX, e.cellY, pc.x, pc.y, tostring(e.level))) end
  end
  local reacted = {}
  local function look()
    for _, id in ipairs(sm.order or {}) do
      local e = sm.entities[id]
      if e and e.react then reacted[id] = true end
    end
  end
  -- ride back and forth past them (each frame watched); a miss rests 5 s, so several passes
  for pass = 1, 6 do
    for _, dir in ipairs({ "left", "right" }) do
      for _ = 1, 48 do
        table.insert(game.input.pressQueue, dir)
        game.input.state[dir] = true
        coroutine.yield()
        look()
      end
      game.input.state[dir] = false
      U.wait(4)
    end
    local c = EP.playerCell()
    say(string.format("  pass %d: player %d,%d", pass, c.x, c.y))
    if next(reacted) then break end
  end
  local n = 0
  for _ in pairs(reacted) do n = n + 1 end
  say("wild Pokemon that reacted: " .. n)
  ok(n > 0, "biking past them, at least one reacted")
  say(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
