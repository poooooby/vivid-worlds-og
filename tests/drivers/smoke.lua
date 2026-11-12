-- In-game smoke test for Vivid Worlds: OG on Red / Yellow / Gold / Crystal, run through the
-- engine's frame driver on a throwaway portable engine export with this repo junctioned at
-- mods/vivid_worlds_og (see DEVELOPMENT.md):
--   POKEPORT_DRIVER=<this> POKEPORT_VERSION=red VWOG_SHOT_DIR=<dir> [VWOG_STYLE=followers] lovec .
-- Checks: the mod loaded and installed; wild Pokemon spawn on the route; the partner is out;
-- bumping a wild Pokemon starts the engine's battle against that same species.
local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local VERSION = tostring(GameVersion.get())
local GEN = GameVersion.generation and GameVersion.generation() or 1
local STYLE = os.getenv("VWOG_STYLE") -- "pokemmo" | "followers" (Sprite Style), nil = the default
local SHOT = (os.getenv("VWOG_SHOT_DIR") or "shots") .. "/" .. VERSION .. (STYLE and ("-" .. STYLE) or "")

return function(game)
  local fails = 0
  local function say(line) print("[vwog] " .. line) end
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
  if not ok(ex ~= nil, VERSION .. ": Vivid Worlds: OG loaded (version " .. tostring(ex and ex.version) .. ")") then
    return finish()
  end
  ok(ex.engineReady == true, "the engine layer installed (layout " .. tostring(ex.layout) .. ")")

  if STYLE then
    local opts = game.mods.modOptions
    opts.vivid_worlds_og = opts.vivid_worlds_og or {}
    opts.vivid_worlds_og.sprite_style = STYLE
    say("Sprite Style set to " .. STYLE)
  end

  local routeId, nearSpecies
  if GEN == 1 then
    local Pokemon = require("src.pokemon.Pokemon")
    game.save.party = { Pokemon.new(game.data, "PIKACHU", 15) }
    routeId, nearSpecies = "ROUTE_1", "BULBASAUR"
    U.teleport(game, routeId, 14, 8, "down")
  else
    local Mon = require("src.battle.gen2.Mon")
    game.save.party = { Mon.new(game.data, "CYNDAQUIL", 15) }
    routeId, nearSpecies = "ROUTE_29", "CHIKORITA"
    game.world:warpToMapId(routeId, 17, 5, "down")
  end
  U.wait(360)

  local sm = ex.spawnManager
  local n = sm:count()
  local names = {}
  for _, id in ipairs(sm.order or {}) do
    local e = sm.entities[id]
    if e then names[#names + 1] = tostring(e.species) .. "@" .. tostring(e.cellX) .. "," .. tostring(e.cellY) end
  end
  say("spawns on " .. tostring(sm.mapId) .. ": " .. table.concat(names, " "))
  ok(sm.mapId == routeId, "the spawn manager is on " .. routeId .. " (" .. tostring(sm.mapId) .. ")")
  ok(n > 0, "wild Pokemon spawned (" .. n .. ")")
  local fa = ex.followerAdapter
  ok(fa and fa.renderer ~= nil, "the partner has its renderer (dex " .. tostring(fa and fa.renderer and fa.renderer.dex) .. ")")
  local function sheetOf(r)
    local path = r and r.imagePath and r:imagePath()
    return tostring(r and r.style) .. " -> " .. tostring(path) .. " (" .. tostring(r and r.frameCount) .. " frames)"
  end
  say("partner sheet: " .. sheetOf(fa and fa.renderer))
  local placed, where = sm:spawnSpecies(nearSpecies, 5, { radius = 4, terrain = "land" })
  say("placed " .. nearSpecies .. " next to the player: " .. tostring(placed) .. " " .. tostring(where and (where.x .. "," .. where.y) or where))
  U.wait(120)
  for _, id in ipairs(sm.order or {}) do
    local e = sm.entities[id]
    if e and e.renderer then say("wild sheet: " .. tostring(e.species) .. " " .. sheetOf(e.renderer)) break end
  end
  if STYLE == "followers" then
    local any
    for _, id in ipairs(sm.order or {}) do
      local e = sm.entities[id]
      if e and e.renderer and e.renderer.imagePath and tostring(e.renderer:imagePath()):find("/gsc/", 1, true) then any = e break end
    end
    ok(any ~= nil and any.renderer.frameCount == 6, "GSC style: wild Pokemon draw 6-frame GSC sheets")
  end
  U.still(game, SHOT .. "/1_route.png")

  -- bump the first live wild Pokemon: the engine's battle, same species
  local target
  for _, id in ipairs(sm.order or {}) do
    local e = sm.entities[id]
    if e and e.state == "available" and e.terrain ~= "water" then target = e break end
  end
  if not ok(target ~= nil, "a wild Pokemon to bump") then return finish() end
  local okBump, err = pcall(ex.battleTrigger.onPlayerBumped, ex.battleTrigger, target)
  ok(okBump, "bumping it does not error (" .. tostring(err) .. ")")
  local battle
  for _ = 1, 600 do
    local top = game.stack:top()
    if top and (top.battle or top.kind) then battle = top break end
    U.wait(1)
  end
  ok(battle ~= nil, "the engine's battle started")
  if battle then
    U.wait(200)
    local foe = (battle.battle and (battle.battle.enemy or battle.battle.wild)) or battle.enemy
      or (battle.enemyMon) or (battle.wild)
    say("battle foe: " .. tostring(foe and (foe.species or foe.name)) .. " Lv" .. tostring(foe and foe.level))
    U.still(game, SHOT .. "/2_battle.png")
  end
  finish()
end
