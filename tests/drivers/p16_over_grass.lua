-- In-game check of the Over Grass option (EnginePatch.wildsOverGrass, lib/engine_patch.lua
-- buildProxies), on the flat 2D field and, with a 3D world mod installed (Battle Art on Red,
-- Battle Art Gen 2 on Crystal), in 3D:
--   POKEPORT_DRIVER=<this> POKEPORT_VERSION=red|crystal VWOG_SHOT_DIR=<dir> lovec .
-- (pre-create <dir>/<version>-overgrass.) Stands by tall grass with wild Pokemon about.
-- 2D: counts the engine's grass-over-feet draws for them -- Gen 1: map.renderer.feetStrip for
-- an entity with no sprite (in 2D only our proxies have none); Gen 2: World:drawGrassOver on a
-- proxy -- with the option off (some) and on (none). 3D: counts the cards stood up on the
-- grass tufts (EnginePatch.overGrassLift > 0) off (none) and on (some). A screenshot of each.
local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local VERSION = tostring(GameVersion.get())
local GEN = GameVersion.generation and GameVersion.generation() or 1
local SHOT = (os.getenv("VWOG_SHOT_DIR") or "shots") .. "/" .. VERSION .. "-overgrass"

return function(game)
  require("mods.vivid_worlds_og.tests.drivers.novsync")(game) -- full speed over RDP too
  local fails = 0
  local function say(line) print("[vwog-overgrass] " .. line) end
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
  local opts = game.mods.modOptions
  opts.vivid_worlds_og = opts.vivid_worlds_og or {}
  opts.vivid_worlds_og.classic_enc = false
  opts.vivid_worlds_og.spawn_amount = "high"
  opts.vivid_worlds_og.wild_reacts = false
  EP.setModOption(game, "vivid_worlds_og", "over_grass", false)
  if GEN == 1 then U.teleport(game, "ROUTE_1", 14, 8, "down")
  else game.world:warpToMapId("ROUTE_29", 17, 5, "down") end
  U.wait(240)
  -- the flat field: any 3D world off (after the warp: a 3D mod switches itself back on there),
  -- and off in the saved options too (Battle Art Gen 2 restores a saved level that reads > 0)
  local Pipelines = require("src.render.Pipelines")
  local world3d
  local function setWorld(level)
    for _, entry in ipairs(Pipelines.list()) do
      if entry.def and entry.def.drawWorld then
        world3d = world3d or entry.id
        pcall(Pipelines.setLevel, entry.id, level)
      end
    end
    for _, o in ipairs({ game.options, game.save and game.save.options }) do
      if type(o) == "table" and Pipelines.syncOptions then pcall(Pipelines.syncOptions, o) end
    end
  end
  setWorld(0)
  U.wait(30)
  if not ok(not (EP._lastFrame or {}).pipeline, "the flat 2D field draws (no 3D world)") then return finish() end

  -- the engine's grass over a wild Pokemon's feet, counted
  local covers = 0
  local undo
  if GEN == 1 then
    local r = game.overworld and game.overworld.map and game.overworld.map.renderer
      or (EP.world() and EP.world().map and EP.world().map.renderer)
    if r and r.feetStrip then
      local real = r.feetStrip
      r.feetStrip = function(px, py, sprite, ...)
        if sprite == nil then covers = covers + 1 end
        return real(px, py, sprite, ...)
      end
      undo = function() r.feetStrip = real end
    end
  else
    local World = require("src.world.gen2.World")
    local real = World.drawGrassOver
    World.drawGrassOver = function(self, entity, ...)
      if type(entity) == "table" and rawget(entity, "_wilds") then covers = covers + 1 end
      return real(self, entity, ...)
    end
    undo = function() World.drawGrassOver = real end
  end
  ok(undo ~= nil, "the engine's grass-over-feet draw is found")

  local pc = EP.playerCell()
  local inGrass = 0
  for _, id in ipairs(sm.order or {}) do
    local e = sm.entities[id]
    if e and e.cellX and EP.isGrass(e.cellX, e.cellY) and math.abs(e.cellX - pc.x) <= 4
        and math.abs(e.cellY - pc.y) <= 4 then
      inGrass = inGrass + 1
    end
  end
  ok(inGrass > 0, "wild Pokemon stand in tall grass in view (" .. inGrass .. ")")

  covers = 0
  U.wait(60)
  local off = covers
  ok(off > 0, "Over Grass off: the grass is drawn over their feet (" .. off .. " in 60 frames)")
  U.still(game, SHOT .. "/1_off.png")

  EP.setModOption(game, "vivid_worlds_og", "over_grass", true)
  U.wait(2)
  ok(EP.wildsOverGrass == true, "switching Over Grass on reaches the draw (mod.options_changed)")
  covers = 0
  U.wait(60)
  ok(covers == 0, "Over Grass on: no grass over a wild Pokemon's feet (" .. covers .. ")")
  U.still(game, SHOT .. "/2_on.png")

  EP.setModOption(game, "vivid_worlds_og", "over_grass", false)
  U.wait(2)
  covers = 0
  U.wait(60)
  ok(EP.wildsOverGrass == false and covers > 0, "...off again: covered again (" .. covers .. ")")
  if undo then undo() end

  -- 3D: the same option stands the cards up on the grass tufts
  if not world3d then
    say("no 3D world mod installed: 3D part skipped")
    return finish()
  end
  setWorld(1)
  U.wait(60)
  ok((EP._lastFrame or {}).pipeline == true, "3D: the world pipeline draws (" .. tostring(world3d) .. ")")
  local lifted = 0
  local realLift = EP.overGrassLift
  EP.overGrassLift = function(...)
    local v = realLift(...)
    if v > 0 then lifted = lifted + 1 end
    return v
  end
  U.wait(60)
  ok(lifted == 0, "3D, Over Grass off: no card is lifted (" .. lifted .. ")")
  U.still(game, SHOT .. "/3_3d_off.png")
  EP.setModOption(game, "vivid_worlds_og", "over_grass", true)
  lifted = 0
  U.wait(60)
  ok(lifted > 0, "3D, Over Grass on: the cards in grass stand on the tufts (" .. lifted .. " in 60 frames)")
  U.still(game, SHOT .. "/4_3d_on.png")
  EP.overGrassLift = realLift
  EP.setModOption(game, "vivid_worlds_og", "over_grass", false)
  setWorld(0)
  finish()
end
