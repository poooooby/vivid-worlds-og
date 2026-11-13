-- In-game check of the partner's Poke Ball (lib/ball_drop.lua), run like tests/drivers/smoke.lua:
--   POKEPORT_DRIVER=<this> POKEPORT_VERSION=red|crystal VWOG_SHOT_DIR=<dir> lovec .
-- (pre-create <dir>/<version>-ball.) Turns the Follower option off and on (a ball drops onto
-- it / behind the player, with the Ball Poof), checks the bike still uses the quick shrink
-- with no ball, and switches the lead Pokemon (the ball takes the old one in, the new one
-- pops out and cries as it does). Screenshots of the fall, the pop and the shrink.
local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local VERSION = tostring(GameVersion.get())
local GEN = GameVersion.generation and GameVersion.generation() or 1
local SHOT = (os.getenv("VWOG_SHOT_DIR") or "shots") .. "/" .. VERSION .. "-ball"

return function(game)
  local fails = 0
  local function say(line) print("[vwog-ball] " .. line) end
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
  opts.vivid_worlds_og.enabled = false -- no wild Pokemon about
  local a, b
  if GEN == 1 then
    local Pokemon = require("src.pokemon.Pokemon")
    a, b = Pokemon.new(game.data, "VENUSAUR", 40), Pokemon.new(game.data, "PIKACHU", 30)
    game.save.party = { a, b }
    U.teleport(game, "ROUTE_1", 14, 8, "down")
  else
    local Mon = require("src.battle.gen2.Mon")
    a, b = Mon.new(game.data, "TYPHLOSION", 40), Mon.new(game.data, "PIKACHU", 30)
    game.save.party = { a, b }
    game.world:warpToMapId("ROUTE_29", 17, 5, "down")
  end
  U.wait(240)
  -- a few steps, so the partner trails a tile behind the player (after a warp it stands on
  -- the player's own tile)
  for _ = 1, 40 do
    table.insert(game.input.pressQueue, "left")
    game.input.state.left = true
    coroutine.yield()
  end
  game.input.state.left = false
  U.wait(60)

  -- the Ball Poofs played, by tick
  local Sound = require("src.core.Sound")
  local realPlay = Sound.play
  local tick, poofs = 0, {}
  Sound.play = function(data, name, ...)
    if type(name) == "string" and name:find("Poof") then poofs[#poofs + 1] = tick end
    return realPlay(data, name, ...)
  end
  local cries = {}
  local realCry = EP.playCry
  EP.playCry = function(...)
    cries[#cries + 1] = tick
    return realCry(...)
  end

  -- runs `n` ticks; returns the ticks a ball was out, and the renderer's size each tick
  local function watch(n, shots)
    local balls, sizes = 0, {}
    for i = 1, n do
      coroutine.yield()
      tick = tick + 1
      if fa.ballState then balls = balls + 1 end
      sizes[i] = fa.renderer and fa.renderer.recall
      if shots and shots[i] then U.still(game, SHOT .. "/" .. shots[i] .. ".png") end
    end
    return balls, sizes
  end

  ok(fa.renderer ~= nil and (fa.renderer.recall or 1) == 1, "the partner is out")

  -- ---- Follower off: a ball drops onto it, it shrinks in, the ball fades
  local p0 = #poofs
  opts.vivid_worlds_og.show_follower = false
  local balls, sizes = watch(40, { [4] = "1-in-falling", [9] = "2-in-pop", [13] = "3-in-shrinking", [20] = "4-in-ball-rests" })
  say(string.format("off: ball out %d ticks, size at 1/9/16/40 = %s/%s/%s/%s", balls,
    tostring(sizes[1]), tostring(sizes[9]), tostring(sizes[16]), tostring(sizes[40])))
  ok(balls >= 20, "Follower off: a Poke Ball drops onto the partner")
  ok(sizes[1] == 1 and sizes[40] == 0, "...and it goes in")
  ok(#poofs == p0 + 1, "...with one Ball Poof")
  ok(fa.ballState == nil, "...and the ball is gone afterwards")

  -- ---- Follower on: a ball drops behind the player, bounces, it pops out
  p0 = #poofs
  opts.vivid_worlds_og.show_follower = true
  balls, sizes = watch(40, { [4] = "5-out-falling", [11] = "6-out-bounce", [15] = "7-out-pop", [19] = "8-out-growing" })
  say(string.format("on: ball out %d ticks, size at 1/13/18/40 = %s/%s/%s/%s", balls,
    tostring(sizes[1]), tostring(sizes[13]), tostring(sizes[18]), tostring(sizes[40])))
  ok(balls >= 18, "Follower on: a Poke Ball drops behind the player")
  ok(sizes[13] == 0, "...the partner stays inside while it lands and bounces")
  ok(sizes[40] == 1, "...then pops out")
  ok(#poofs == p0 + 1, "...with one Ball Poof")

  -- ---- the bike: the quick shrink into the player, no ball, no sound
  p0 = #poofs
  local realBike = EP.playerBiking
  EP.playerBiking = function() return true end
  balls, sizes = watch(40)
  ok(balls == 0 and sizes[40] == 0, "on the bike: it shrinks in with no ball")
  EP.playerBiking = realBike
  balls, sizes = watch(40)
  ok(balls == 0 and sizes[40] == 1, "off the bike: it comes back out with no ball")
  ok(#poofs == p0, "...and no Ball Poof for the bike")

  -- ---- a new lead: the old one goes into a ball, the new one pops out of another, crying
  p0 = #poofs
  local c0 = #cries
  game.save.party = { b, a }
  balls, sizes = watch(200)
  say(string.format("switch: ball out %d ticks, poofs at %s, cries at %s", balls,
    table.concat({ unpack(poofs, p0 + 1) }, ","), table.concat({ unpack(cries, c0 + 1) }, ",")))
  ok(#poofs == p0 + 2, "a new lead: two Ball Poofs (old in, new out)")
  ok(#cries == c0 + 1 and cries[c0 + 1] == poofs[p0 + 2], "...the new one cries as its ball pops")
  ok(fa.renderer and fa.renderer.recall == 1 and fa.ballState == nil, "...and ends out, the ball gone")
  U.still(game, SHOT .. "/9-new-lead.png")

  Sound.play, EP.playCry = realPlay, realCry
  say(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  love.event.quit(fails == 0 and 0 or 1)
end
