-- In-game check that a partner in its ball leaves no grass rustle behind the player (Gold /
-- Silver / Crystal: the engine's follower keeps walking there, drawn as nothing), run like
-- tests/drivers/smoke.lua:
--   POKEPORT_DRIVER=<this> POKEPORT_VERSION=gold|crystal lovec .
-- Walks the grass of Route 29 with the Follower option on (the partner's rustle must show:
-- the walk does cross grass) and then off (no rustle drawn for it, while the engine's own
-- step still marks it as shaking the grass between draws).
local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local VERSION = tostring(GameVersion.get())

return function(game)
  local fails = 0
  local function say(line) print("[vwog-follower-off] " .. line) end
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
  local EP, fa = ex.enginePatch, ex.followerAdapter
  local opts = game.mods.modOptions
  opts.vivid_worlds_og = opts.vivid_worlds_og or {}
  opts.vivid_worlds_og.classic_enc = false
  opts.vivid_worlds_og.enabled = false -- no wild Pokemon to bump into
  local Mon = require("src.battle.gen2.Mon")
  game.save.party = { Mon.new(game.data, "TYPHLOSION", 40) }
  game.world:warpToMapId("ROUTE_29", 17, 5, "down")
  U.wait(240)

  -- the partner's rustles drawn (instance field: shadows World:drawGrassShake)
  local drawn = 0
  local world = game.world
  local orig = world.drawGrassShake
  world.drawGrassShake = function(self, entity, ...)
    if entity and entity == EP.followerCurrent() and entity.grassShake and entity.moving then
      drawn = drawn + 1
    end
    return orig(self, entity, ...)
  end

  local function walk(frames)
    local marked = 0 -- frames the engine's step had the follower shaking grass (between draws)
    local dirs, t = { "left", "right" }, 0
    while t < frames do
      for _, dir in ipairs(dirs) do
        for _ = 1, 64 do
          table.insert(game.input.pressQueue, dir)
          game.input.state[dir] = true
          coroutine.yield()
          t = t + 1
          local f = EP.followerCurrent()
          if f and f.grassShake and f.moving then marked = marked + 1 end
        end
        game.input.state[dir] = false
        U.wait(4)
        t = t + 4
      end
    end
    return marked
  end

  opts.vivid_worlds_og.show_follower = true
  U.wait(90)
  drawn = 0
  local markedOn = walk(600)
  say(string.format("Follower on: follower %s, recalled %s; rustle drawn %d frames, marked %d",
    tostring(EP.followerCurrent() ~= nil), tostring(fa:isRecalled()), drawn, markedOn))
  ok(drawn > 0, "Follower on: the partner rustles the grass it walks through")

  opts.vivid_worlds_og.show_follower = false
  U.wait(90)
  drawn = 0
  local markedOff = walk(600)
  say(string.format("Follower off: follower %s, recalled %s; rustle drawn %d frames, marked %d",
    tostring(EP.followerCurrent() ~= nil), tostring(fa:isRecalled()), drawn, markedOff))
  ok(fa:isRecalled(), "Follower off: the partner is in its ball")
  ok(markedOff > 0, "Follower off: the engine's follower still walks the grass (its step data kept)")
  ok(drawn == 0, "Follower off: no rustle drawn behind the player")

  world.drawGrassShake = nil
  say(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  love.event.quit(fails == 0 and 0 or 1)
end
