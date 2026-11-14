-- In-game check of Wild Reacts (biking past wild Pokemon), run like tests/drivers/smoke.lua:
--   POKEPORT_DRIVER=<this> POKEPORT_VERSION=crystal|red lovec .
-- A strong lead, a few wild Pokemon placed close by, the player on a bike riding past them:
-- at least one should react (startled "!" and flee, or angry and chase). The reaction roll is
-- forced to hit and the riding row is cleared, so the outcome does not depend on luck.
local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local VERSION = tostring(GameVersion.get())
local GEN = GameVersion.generation and GameVersion.generation() or 1

return function(game)
  require("mods.vivid_worlds_og.tests.drivers.novsync")(game) -- full speed over RDP too
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
  -- no step encounters in the grass; and every reaction roll hits (Config.REACT tops out at
  -- maxChance %, one roll as the player comes in range): this checks that they react, not luck
  local opts = game.mods.modOptions
  opts.vivid_worlds_og = opts.vivid_worlds_og or {}
  opts.vivid_worlds_og.classic_enc = false
  local realCtx = sm._reactContext
  sm._reactContext = function(self)
    local c = realCtx(self)
    if c then c.rng = function(lo) return lo or 0 end end
    return c
  end

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
  say("react context: " .. tostring(ctx ~= nil))
  ok(ctx and ctx.lead and ctx.lead.bst ~= nil, "the lead's base stat total is known (" ..
    tostring(ctx and ctx.lead and ctx.lead.bst) .. ")")
  local pc = EP.playerCell()
  -- nobody on the row the bike rides along: running into one starts its battle
  for _, id in ipairs(sm.order or {}) do
    local e = sm.entities[id]
    if e and e.cellY == pc.y then sm:despawn(id) end
  end
  -- ...and a few beside it, within the bike's reach (the route's own spawns may all be far off):
  -- land Pokemon moved onto free grass one or two rows off the ride
  local spots = {}
  for dy = 1, 2 do
    for _, sy in ipairs({ pc.y - dy, pc.y + dy }) do
      for x = pc.x - 4, pc.x + 1 do
        if EP.terrainAt(x, sy) == "land" and not sm:entityAt(x, sy) then spots[#spots + 1] = { x = x, y = sy } end
      end
    end
  end
  local moved = 0
  for _, id in ipairs(sm.order or {}) do
    local e = sm.entities[id]
    local spot = spots[moved * 3 + 1]
    if e and spot and e.terrain == "land" and e.state == "available" and not e.moving then
      e.cellX, e.cellY, e.px, e.py = spot.x, spot.y, spot.x * 16, spot.y * 16
      moved = moved + 1
      if moved >= 3 then break end
    end
  end
  ok(moved > 0, "wild Pokemon beside the ride (" .. moved .. ")")
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
