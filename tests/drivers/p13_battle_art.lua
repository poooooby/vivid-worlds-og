-- In-game check of the Battle Art adapters (lib/compat/battle_art_*), run like
-- tests/drivers/smoke.lua with ONE Battle Art mod installed beside this one (Battle Art 1.x
-- "BATTLE_ART_VOXEL_FORK" on Red, Battle Art Gen 2 "BATTLE_ART_VOXEL_GEN2" on Crystal):
--   POKEPORT_DRIVER=<this> POKEPORT_VERSION=red|crystal VWOG_SHOT_DIR=<dir> lovec .
-- (pre-create <dir>/<version>-battleart.) Switches its 3D world on with wild Pokemon and the
-- partner about, records every card Battle Art's SpriteBillboards.mesh builds for our sheets
-- (def.wohVoxel) and measures it: wider than the 16 x 16 native card, centred on the tile
-- (x around 8), feet on the ground (y from 0), the Species Sizes width when it applies; on
-- Gen 2 also halfWidth == 8 (its placement); and the pipeline still draws (no error retired it).
local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local VERSION = tostring(GameVersion.get())
local GEN = GameVersion.generation and GameVersion.generation() or 1
local SHOT = (os.getenv("VWOG_SHOT_DIR") or "shots") .. "/" .. VERSION .. "-battleart"
local BA_ID = GEN == 1 and "BATTLE_ART_VOXEL_FORK" or "BATTLE_ART_VOXEL_GEN2"

return function(game)
  require("mods.vivid_worlds_og.tests.drivers.novsync")(game) -- full speed over RDP too
  local fails = 0
  local function say(line) print("[vwog-battleart] " .. line) end
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
  local exports = game.mods and game.mods.exports or {}
  local ex, ba = exports.vivid_worlds_og, exports[BA_ID]
  if not ok(ex ~= nil and ex.engineReady, VERSION .. ": Vivid Worlds: OG installed") then return finish() end
  if not ok(ba ~= nil and ba.lib ~= nil, BA_ID .. " installed (" .. tostring(ba and ba.version) .. ")") then
    return finish()
  end
  local SB = ba.lib.require("SpriteBillboards")
  local EP, sm = ex.enginePatch, ex.spawnManager
  local opts = game.mods.modOptions
  opts.vivid_worlds_og = opts.vivid_worlds_og or {}
  opts.vivid_worlds_og.classic_enc = false
  opts.vivid_worlds_og.spawn_amount = "high"
  opts.vivid_worlds_og.wild_reacts = false
  if GEN == 1 then
    local Pokemon = require("src.pokemon.Pokemon")
    game.save.party = { Pokemon.new(game.data, "VENUSAUR", 40) }
    U.teleport(game, "ROUTE_1", 14, 8, "down")
  else
    local Mon = require("src.battle.gen2.Mon")
    game.save.party = { Mon.new(game.data, "TYPHLOSION", 40) }
    game.world:warpToMapId("ROUTE_29", 17, 5, "down")
  end
  U.wait(120)
  -- nobody on the row the player walks along (walking into one starts its battle)
  local pc = EP.playerCell()
  for _, id in ipairs(sm.order or {}) do
    local e = sm.entities[id]
    if e and pc and e.cellY == pc.y then sm:despawn(id) end
  end
  U.hold(game, "left", 40)
  U.wait(90)

  -- Battle Art's world pipeline on
  local Pipelines = require("src.render.Pipelines")
  local world
  for _, entry in ipairs(Pipelines.list()) do
    if entry.def and entry.def.drawWorld then world = entry.id break end
  end
  if not ok(world ~= nil, "its world pipeline is registered (" .. tostring(world) .. ")") then return finish() end
  Pipelines.setLevel(world, 1)
  U.wait(30)

  -- every card built for one of our sheets, measured (the adapters cache: wrap after they
  -- installed, and drop the cache so each sheet is built again under the watch)
  local cards, seen = {}, {}
  local realMesh = SB.mesh
  SB.mesh = function(def, frame, ...)
    local mesh = realMesh(def, frame, ...)
    if type(def) == "table" and def.wohVoxel and mesh and not seen[def.id] then
      seen[def.id] = true
      local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
      local okN, n = pcall(mesh.getVertexCount, mesh)
      for i = 1, okN and n or 0 do
        local x, y = mesh:getVertex(i)
        x0, x1, y0, y1 = math.min(x0, x), math.max(x1, x), math.min(y0, y), math.max(y1, y)
      end
      cards[#cards + 1] = { def = def, x0 = x0, x1 = x1, y0 = y0, y1 = y1,
        half = SB.halfWidth and SB.halfWidth(def) or nil }
    end
    return mesh
  end
  if SB.invalidate then pcall(SB.invalidate) end
  U.wait(120)
  ok(Pipelines.worldPipeline() == world and EP.pipelineActive(), "the 3D world draws (nothing retired it)")
  local lf = EP._lastFrame or {}
  say(string.format("last frame: %s actors, %s cards of ours, %s effects", tostring(lf.actors),
    tostring(lf.proxies), tostring(lf.fx)))
  ok((lf.proxies or 0) > 0, "our Pokemon go in as cards")
  ok(#cards > 0, "Battle Art built cards for our sheets (" .. #cards .. ")")

  local sized, centred, grounded, display, placed = 0, 0, 0, 0, 0
  for _, c in ipairs(cards) do
    local d = c.def
    local w, h = c.x1 - c.x0, c.y1 - c.y0
    local want = math.floor((d.displayWidth or d.frameWidth) + 0.5)
    say(string.format("  %s: cell %d, display %s -> card %.1f x %.1f, x %.1f..%.1f, y %.1f..%.1f, halfWidth %s",
      d.id, d.frameWidth, tostring(d.displayWidth and math.floor(d.displayWidth + 0.5)), w, h, c.x0, c.x1,
      c.y0, c.y1, tostring(c.half)))
    if w > 16.5 or d.frameWidth <= 16 then sized = sized + 1 end
    if math.abs((c.x0 + c.x1) / 2 - 8) <= 1 then centred = centred + 1 end
    if math.abs(c.y0) <= 0.5 then grounded = grounded + 1 end
    if math.abs(w - want) <= 1 then display = display + 1 end
    if c.half == nil or c.half == 8 then placed = placed + 1 end
  end
  local n = #cards
  ok(n > 0 and sized == n, "every card is its sheet's size, not the 16 x 16 native one")
  ok(n > 0 and centred == n, "...centred on its tile (x around 8)")
  ok(n > 0 and grounded == n, "...feet on the ground (y from 0)")
  ok(n > 0 and display == n, "...at its Species Sizes width (" .. display .. " of " .. n .. ")")
  if GEN == 2 then ok(n > 0 and placed == n, "...and halfWidth places it from the tile's centre (8)") end
  ok(not (EP.battleActive and EP.battleActive()), "no battle opened meanwhile (the shots show the field)")
  U.still(game, SHOT .. "/1_world.png")
  -- the partner up close
  U.hold(game, "right", 8)
  U.wait(40)
  U.still(game, SHOT .. "/2_partner.png")
  SB.mesh = realMesh
  Pipelines.setLevel(world, 0)
  finish()
end
