-- In-game check of the map's own Pokemon in this mod's art (lib/static_mons.lua), run like
-- tests/drivers/smoke.lua:
--   POKEPORT_DRIVER=<this> POKEPORT_VERSION=red|crystal VWOG_SHOT_DIR=<dir> lovec .
-- (pre-create <dir>/<version>-static.) Visits a few of them (Mewtwo, Zapdos, Snorlax on Red;
-- Lugia, the Red Gyarados, Gold's big Snorlax, Azalea's Slowpoke on Crystal), checks each wears
-- our sprite for the right species, and takes a screenshot of each.
local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local VERSION = tostring(GameVersion.get())
local GEN = GameVersion.generation and GameVersion.generation() or 1
local SHOT = (os.getenv("VWOG_SHOT_DIR") or "shots") .. "/" .. VERSION .. "-static"

-- map, object index, the art it should get (dex key), shiny
local VISITS = GEN == 1 and {
  { "CERULEAN_CAVE_B1F", 1, "150" }, { "POWER_PLANT", 9, "145" }, { "ROUTE_12", 1, "143" },
  { "POWER_PLANT", 1, "100" },
} or {
  { "WHIRL_ISLAND_LUGIA_CHAMBER", 1, "249" }, { "LAKE_OF_RAGE", 9, "130", true },
  { "VERMILION_CITY", 5, "143" }, { "AZALEA_TOWN", 5, "079" }, { "BURNED_TOWER_B1F", 3, "244" },
  -- a borrowed sheet (Rhydon's) under its own script's cry (Kangaskhan)
  { "CERULEAN_TRADE_SPEECH_HOUSE", 3, "115" }, { "ROUTE_39", 4, "241" },
}

return function(game)
  local fails = 0
  local function say(line) print("[vwog-static] " .. line) end
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
  local opts = game.mods.modOptions
  opts.vivid_worlds_og = opts.vivid_worlds_og or {}
  opts.vivid_worlds_og.classic_enc = false
  local EP, sm = ex.enginePatch, ex.staticMons
  -- Lugia only rises for a player carrying the Silver Wing (its chamber's map callback)
  if GEN == 2 then say("Silver Wing given: " .. tostring(EP.bagAdd("SILVER_WING", 1))) end

  for n, visit in ipairs(VISITS) do
    local mapId, index, wantDex, wantShiny = visit[1], visit[2], visit[3], visit[4] == true
    local maps = GEN == 1 and game.data.maps or (game.world and game.world.maps)
    local def = maps and maps[mapId]
    local obj
    for _, o in ipairs(def and def.objects or {}) do if o.index == index then obj = o end end
    if ok(obj ~= nil, mapId .. " #" .. index .. " is on the map data") then
      -- out whatever the story says (Lugia waits for the Silver Wing, Azalea's Slowpoke for the
      -- Well): its hide flag cleared, as if the scene had run
      local events = GEN == 2 and game.world and game.world.events
      if events and obj.eventFlag and obj.eventFlag >= 0 then events:set(obj.eventFlag, false) end
      -- stood two cells below it, facing it
      if GEN == 1 then U.teleport(game, mapId, obj.x, obj.y + 2, "up")
      else game.world:warpToMapId(mapId, obj.x, obj.y + 2, "up") end
      U.wait(90)
      local npc
      for _, p in ipairs(EP.mapNpcs() or {}) do
        local d = p.def
        if d and d.index == index and (p.mapId == nil or p.mapId == mapId) then npc = p end
      end
      local r = npc and type(npc.sprite) == "table" and rawget(npc.sprite, "renderer")
      if npc and os.getenv("VWOG_DEBUG") then
        local f = {}
        EP.npcFacts(npc, f)
        local ops = {}
        for _, op in ipairs(type(f.script) == "table" and f.script or {}) do
          ops[#ops + 1] = tostring(op.op) .. (op.args and ("(" .. tostring(op.args[1]) .. "," .. tostring(op.args[2]) .. ")") or "")
        end
        say(string.format("facts: map %s index %s sprite %s script %s: %s", tostring(f.mapId), tostring(f.index),
          tostring(f.sprite), tostring(npc.def and npc.def.scriptKey), table.concat(ops, " ")))
      end
      say(string.format("%s #%d: npc %s, art %s shiny %s pose %s; %d shown on the map", mapId, index,
        tostring(npc ~= nil), tostring(r and r.dex), tostring(r and r.shiny), tostring(r and r.poseOverride), sm:count()))
      if ok(npc ~= nil, mapId .. " #" .. index .. " is out on the map") then
        ok(r ~= nil and tonumber(r.dex) == tonumber(wantDex), mapId .. " #" .. index .. " wears our art for " .. wantDex)
        ok(r ~= nil and r.shiny == wantShiny, mapId .. " #" .. index .. (wantShiny and " is shiny" or " is not shiny"))
      end
      U.still(game, SHOT .. "/" .. n .. "_" .. mapId:lower() .. ".png")
    end
  end
  say(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
