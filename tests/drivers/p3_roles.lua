-- In-game check of the partner's Battler and Forager (P3), run like tests/drivers/smoke.lua:
--   POKEPORT_DRIVER=<this> POKEPORT_VERSION=crystal|red VWOG_SHOT_DIR=<dir> lovec .
-- (pre-create <dir>/<version>-roles.) Battle: the partner charges a wild Pokemon on the route,
-- knocks it out and gains EXP by the game's own formula. Forage: it digs up an item that lands
-- in the bag (Gold: in its own pocket).
local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local VERSION = tostring(GameVersion.get())
local GEN = GameVersion.generation and GameVersion.generation() or 1
local SHOT = (os.getenv("VWOG_SHOT_DIR") or "shots") .. "/" .. VERSION .. "-roles"

return function(game)
  local fails = 0
  local function say(line) print("[vwog-roles] " .. line) end
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
  local EP, sm, companion, battler, forager = ex.enginePatch, ex.spawnManager, ex.companion, ex.battler, ex.forager
  ok(EP.supports("roles"), "this generation carries the partner roles")
  local opts = game.mods.modOptions
  opts.vivid_worlds_og = opts.vivid_worlds_og or {}
  opts.vivid_worlds_og.classic_enc = false

  local lead, expOf
  if GEN == 1 then
    local Pokemon = require("src.pokemon.Pokemon")
    lead = Pokemon.new(game.data, "VENUSAUR", 40)
    game.save.party = { lead }
    expOf = function(m) return tonumber(m.exp) or 0 end
    U.teleport(game, "ROUTE_1", 14, 8, "down")
  else
    local Mon = require("src.battle.gen2.Mon")
    lead = Mon.new(game.data, "TYPHLOSION", 40)
    game.save.party = { lead }
    expOf = function(m) return tonumber(m.experience) or 0 end
    game.world:warpToMapId("ROUTE_29", 17, 5, "down")
  end
  U.wait(240)
  say("wild Pokemon on the route: " .. sm:count())
  -- no contact battles while the driver walks (as tests/drivers/p5_perf.lua): a wild Pokemon that
  -- wanders into the player's path would start a real battle nobody ends, and the field (with the
  -- partner's roles) stops ticking under it. The Battler's own skirmishes are not contact battles.
  local bt = ex.battleTrigger
  bt.onPlayerStepped, bt.onChaserContact, bt.onPlayerBumped = function() end, function() end, function() end

  -- walk left and right (the Battler looks for targets near the player as they go)
  local function walk(frames, watch)
    local dirs, t = { "left", "right" }, 0
    while t < frames do
      for _, dir in ipairs(dirs) do
        for _ = 1, 48 do
          table.insert(game.input.pressQueue, dir)
          game.input.state[dir] = true
          coroutine.yield()
          t = t + 1
          if watch and watch() then game.input.state[dir] = false return true end
        end
        game.input.state[dir] = false
        U.wait(4)
        t = t + 4
      end
    end
    return false
  end

  -- ---- the ROLE row in the game's own party menu (its submenu list, through ui.party.submenu)
  do
    local PM = require(GEN == 1 and "src.ui.PartyMenu" or "src.ui.gen2.PartyMenu")
    local okM, menu = pcall(PM.new, game, {})
    local rows = okM and menu and menu.submenuItems and select(2, pcall(menu.submenuItems, menu, lead))
    if GEN == 1 and not (type(rows) == "table") then rows = nil end
    local labels = {}
    for _, r in ipairs(type(rows) == "table" and rows or {}) do labels[#labels + 1] = tostring(r.label) end
    say("party submenu: " .. table.concat(labels, " / "))
    if GEN == 2 then
      local role
      for _, r in ipairs(rows or {}) do if r.label == "ROLE" then role = r end end
      ok(role ~= nil and type(role.onSelect) == "function", "Gold's party submenu has the ROLE row")
    end
  end

  -- ---- Battle
  ok(companion:set(lead, "battle"), "the partner takes the Battle role")
  -- a few targets within its reach (Config.OW_BATTLE.radius 3): the route's own may all sit
  -- where it cannot stand beside them (one in the player's path, next to a ledge)
  local placed = 0
  for _ = 1, 3 do
    if sm:spawnSpecies(GEN == 1 and "PIDGEY" or "SENTRET", 3, { radius = 3, terrain = "land" }) then placed = placed + 1 end
  end
  say("extra targets placed within reach: " .. placed)
  local exp0, count0 = expOf(lead), sm:count()
  local fought, hit = false, false
  local sawFight = walk(60 * 60, function()
    if battler.wild or battler.target then fought = true end
    if battler.hits and #battler.hits > 0 then hit = true end
    return expOf(lead) > exp0
  end)
  say(string.format("battle: fought %s, a hit landed %s, EXP %d -> %d", tostring(fought), tostring(hit), exp0, expOf(lead)))
  ok(fought, "it charged a wild Pokemon")
  ok(sawFight and expOf(lead) > exp0, "it knocked one out and gained EXP")
  U.wait(30)
  U.still(game, SHOT .. "/1_battle.png")

  -- ---- Forage
  ok(companion:set(lead, "forage"), "the partner takes the Forage role")
  local function bagCount()
    local n = 0
    for _, q in pairs(game.save.inventory or {}) do n = n + (tonumber(q) or 0) end
    return n
  end
  local bag0 = bagCount()
  local fa = ex.followerAdapter
  U.wait(60)
  say(string.format("forage state: adapter role %s, mode %s, steps %s, retry %s, allowed here %s, map type %s",
    tostring(fa.role), tostring(forager.mode), tostring(forager.steps), tostring(forager.retry),
    tostring(EP.forageAllowed and EP.forageAllowed({ [3] = true, [4] = true })), tostring(EP.mapType())))
  -- (harness, once the role switch has settled: a find is due now, not after 60 steps)
  forager.steps = 10 ^ 6
  local roll = ex.forageSource and ex.forageSource.roll and ex.forageSource:roll(70)
  say("a roll from the catalog: " .. tostring(roll and (roll.id or roll.name)))
  local found = walk(60 * 45, function() return bagCount() > bag0 end)
  say(string.format("after: mode %s, steps %s, retry %s", tostring(forager.mode), tostring(forager.steps), tostring(forager.retry)))
  local got
  for id, q in pairs(game.save.inventory or {}) do got = got or ((tonumber(q) or 0) > 0 and id) end
  say(string.format("forage: bag %d -> %d (%s)", bag0, bagCount(), tostring(got)))
  ok(found, "it dug up an item and it landed in the bag")
  U.wait(30)
  U.still(game, SHOT .. "/2_forage.png")
  companion:set(lead, "follow")
  finish()
end
