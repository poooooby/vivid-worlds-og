-- In-game check of the map's own Pokemon (lib/static_mons.lua) in Battle Art's 3D world, run
-- like tests/drivers/p13_battle_art.lua with ONE Battle Art installed (Battle Art 1.x on Red,
-- Battle Art Gen 2 on Crystal):
--   POKEPORT_DRIVER=<this> POKEPORT_VERSION=red|crystal VWOG_SHOT_DIR=<dir> lovec .
-- (pre-create <dir>/<version>-static3d.) Visits a few of them (big ones too: Gold's big Snorlax,
-- Lugia; the red Gyarados on water), switches the 3D world on and checks each one's card is one
-- of our sheets (def.wohVoxel, so the Battle Art adapter builds it: Species Sizes, centred,
-- feet down), and lists any other sprite bigger than 16 x 16 that Battle Art draws on its own.
local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local VERSION = tostring(GameVersion.get())
local GEN = GameVersion.generation and GameVersion.generation() or 1
local SHOT = (os.getenv("VWOG_SHOT_DIR") or "shots") .. "/" .. VERSION .. "-static3d"
local BA_ID = GEN == 1 and "BATTLE_ART_VOXEL_FORK" or "BATTLE_ART_VOXEL_GEN2"

-- map, object index, the art it should get (dex)
local VISITS = GEN == 1 and {
  { "CERULEAN_CAVE_B1F", 1, 150 }, { "POWER_PLANT", 9, 145 }, { "ROUTE_12", 1, 143 },
} or {
  { "VERMILION_CITY", 5, 143 }, { "WHIRL_ISLAND_LUGIA_CHAMBER", 1, 249 }, { "LAKE_OF_RAGE", 9, 130 },
  { "BURNED_TOWER_B1F", 3, 244 }, { "AZALEA_TOWN", 5, 79 },
}

return function(game)
  require("mods.vivid_worlds_og.tests.drivers.novsync")(game) -- full speed over RDP too
  local fails = 0
  local function say(line) print("[vwog-static3d] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
    return cond
  end

  U.wait(60)
  local exports = game.mods and game.mods.exports or {}
  local ex, ba = exports.vivid_worlds_og, exports[BA_ID]
  if not ok(ex ~= nil and ex.engineReady, VERSION .. ": Vivid Worlds: OG installed") then
    love.event.quit(1) return
  end
  if not ok(ba ~= nil and ba.lib ~= nil, BA_ID .. " installed") then love.event.quit(1) return end
  local SB = ba.lib.require("SpriteBillboards")
  local EP = ex.enginePatch
  local opts = game.mods.modOptions
  opts.vivid_worlds_og = opts.vivid_worlds_og or {}
  opts.vivid_worlds_og.classic_enc = false
  opts.vivid_worlds_og.enabled = false -- only the map's own Pokemon in the shots
  if GEN == 2 then EP.bagAdd("SILVER_WING", 1) end

  local Pipelines = require("src.render.Pipelines")
  local world
  for _, entry in ipairs(Pipelines.list()) do
    if entry.def and entry.def.drawWorld then world = entry.id break end
  end
  if not ok(world ~= nil, "Battle Art's world pipeline is registered") then love.event.quit(1) return end

  -- every def Battle Art builds a card for: ours measured, any other sized one listed
  local cards, others = {}, {}
  local realMesh = SB.mesh
  SB.mesh = function(def, frame, ...)
    local mesh = realMesh(def, frame, ...)
    if type(def) == "table" and mesh then
      if def.wohVoxel then
        local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
        local okN, n = pcall(mesh.getVertexCount, mesh)
        for i = 1, okN and n or 0 do
          local x, y = mesh:getVertex(i)
          x0, x1, y0, y1 = math.min(x0, x), math.max(x1, x), math.min(y0, y), math.max(y1, y)
        end
        cards[def.id] = { x0 = x0, x1 = x1, y0 = y0, y1 = y1, def = def }
      elseif (tonumber(def.frameWidth) or 16) > 16 or (tonumber(def.frameHeight) or 16) > 16 or def.big then
        others[tostring(def.id or def.image)] = string.format("%sx%s%s", tostring(def.frameWidth),
          tostring(def.frameHeight), def.big and " big" or "")
      end
    end
    return mesh
  end

  for n, visit in ipairs(VISITS) do
    local mapId, index, wantDex = visit[1], visit[2], visit[3]
    local maps = GEN == 1 and game.data.maps or (game.world and game.world.maps)
    local def = maps and maps[mapId]
    local obj
    for _, o in ipairs(def and def.objects or {}) do if o.index == index then obj = o end end
    if ok(obj ~= nil, mapId .. " #" .. index .. " is on the map data") then
      local events = GEN == 2 and game.world and game.world.events
      if events and obj.eventFlag and obj.eventFlag >= 0 then events:set(obj.eventFlag, false) end
      Pipelines.setLevel(world, 0)
      if GEN == 1 then U.teleport(game, mapId, obj.x, obj.y + 2, "up")
      else game.world:warpToMapId(mapId, obj.x, obj.y + 2, "up") end
      U.wait(90)
      Pipelines.setLevel(world, 1)
      if SB.invalidate then pcall(SB.invalidate) end
      for k in pairs(cards) do cards[k] = nil end
      U.wait(60)
      local npc
      for _, p in ipairs(EP.mapNpcs() or {}) do
        local d = p.def
        if d and d.index == index and (p.mapId == nil or p.mapId == mapId) then npc = p end
      end
      local r = npc and type(npc.sprite) == "table" and rawget(npc.sprite, "renderer")
      -- what the 3D world reads from it while the pipeline draws
      EP._pipeline = true
      local sdef = npc and npc.sprite and npc.sprite.def
      EP._pipeline = nil
      local card = sdef and cards[sdef.id]
      say(string.format("%s #%d: dex %s, big object %s, 3D def %s (ours %s), card %s", mapId, index,
        tostring(r and r.dex), tostring(npc and npc.bigObject), tostring(sdef and sdef.id),
        tostring(sdef and sdef.wohVoxel), card and string.format("%.0f x %.0f, x %.1f..%.1f, y %.1f..%.1f",
          card.x1 - card.x0, card.y1 - card.y0, card.x0, card.x1, card.y0, card.y1) or "none"))
      if ok(npc ~= nil and r ~= nil and tonumber(r.dex) == wantDex, mapId .. ": our " .. wantDex .. " is out") then
        ok(sdef ~= nil and sdef.wohVoxel == true, "...its 3D card is one of our sheets (the adapter's)")
        ok(card ~= nil, "...Battle Art built that card")
        if card then
          local want = math.floor((sdef.displayWidth or sdef.frameWidth) + 0.5)
          ok(math.abs((card.x1 - card.x0) - want) <= 1, "...at its Species Sizes width (" .. want .. ")")
          ok(math.abs((card.x0 + card.x1) / 2 - 8) <= 1 and math.abs(card.y0) <= 0.5, "...centred, feet down")
          if GEN == 2 then ok(SB.halfWidth(sdef) == 8, "...placed from the tile's centre (halfWidth 8)") end
        end
      end
      U.still(game, SHOT .. "/" .. n .. "_" .. mapId:lower() .. ".png")
    end
  end
  local list = {}
  for id, size in pairs(others) do list[#list + 1] = id .. " " .. size end
  table.sort(list)
  say("other sprites over 16 x 16 Battle Art drew on its own: " .. (#list > 0 and table.concat(list, ", ") or "none"))
  SB.mesh = realMesh
  Pipelines.setLevel(world, 0)
  say(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
