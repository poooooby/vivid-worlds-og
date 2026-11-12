-- In-game check of our effects in a 3D world mod (P2), run like tests/drivers/smoke.lua with a
-- world pipeline mod installed beside this one (TERRARIUM on Red, Battle Art Gen 2 on Crystal):
--   POKEPORT_DRIVER=<this> POKEPORT_VERSION=red|crystal VWOG_SHOT_DIR=<dir> lovec .
-- (pre-create <dir>/<version>-voxelfx.) Switches the world pipeline on, puts the partner in a mood
-- (its bubble) and checks it draws through the pipeline's own field-effects pass (ctx.drawFx)
-- instead of vanishing.
local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local VERSION = tostring(GameVersion.get())
local GEN = GameVersion.generation and GameVersion.generation() or 1
local SHOT = (os.getenv("VWOG_SHOT_DIR") or "shots") .. "/" .. VERSION .. "-voxelfx"

return function(game)
  local fails = 0
  local function say(line) print("[vwog-voxelfx] " .. line) end
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
  local EP, fi, sm = ex.enginePatch, ex.followerInteraction, ex.spawnManager
  local opts = game.mods.modOptions
  opts.vivid_worlds_og = opts.vivid_worlds_og or {}
  opts.vivid_worlds_og.classic_enc = false
  if GEN == 1 then
    local Pokemon = require("src.pokemon.Pokemon")
    game.save.party = { Pokemon.new(game.data, "BULBASAUR", 15) }
    U.teleport(game, "ROUTE_1", 14, 8, "down")
  else
    local Mon = require("src.battle.gen2.Mon")
    game.save.party = { Mon.new(game.data, "CYNDAQUIL", 15) }
    game.world:warpToMapId("ROUTE_29", 17, 5, "down")
  end
  U.wait(120)
  U.hold(game, "left", 40)
  U.wait(90)

  -- the world pipeline on
  local Pipelines = require("src.render.Pipelines")
  local world
  for _, entry in ipairs(Pipelines.list()) do
    if entry.def and entry.def.drawWorld then world = entry.id break end
  end
  if not ok(world ~= nil, "a world pipeline mod is installed (" .. tostring(world) .. ")") then return finish() end
  Pipelines.setLevel(world, 1)
  U.wait(60)
  ok(Pipelines.worldPipeline() == world and EP.pipelineActive(), "it draws the world now")

  -- count our effect draws through the frame's drawFx
  local realFx, counted = EP.drawFxActors, 0
  EP.drawFxActors = function(...)
    local n = realFx(...)
    counted = counted + n
    return n
  end
  fi.moodKind = function() return "hearts" end
  U.wait(40)
  local lf = EP._lastFrame or {}
  say(string.format("last frame: %s actors, %s effects, %s figures as cards", tostring(lf.actors), tostring(lf.fx),
    tostring(lf.proxies)))
  say("effect draws through drawFx in 40 frames: " .. counted)
  ok(counted > 0, "the partner's bubble draws in the 3D world")
  U.still(game, SHOT .. "/1_bubble.png")
  EP.drawFxActors = realFx
  Pipelines.setLevel(world, 0)
  finish()
end
