-- In-game check of the game-accurate extras (P4), run like tests/drivers/smoke.lua:
--   POKEPORT_DRIVER=<this> POKEPORT_VERSION=crystal|red VWOG_P4=<part> VWOG_SHOT_DIR=<dir> lovec .
-- (pre-create <dir>/<version>-p4.) Each part ends in a battle, so one part per run:
--   crystal roamer  a roaming beast on its route shows as a visible spawn, never twice, the Battler
--                   leaves it, Classic Enc off gates its step roll, it leaves with roamer.moved,
--                   and touching it opens the engine's own roaming battle
--   crystal unown   in the Ruins of Alph each visible Unown wears the letter its DVs make, and
--                   its battle is against that letter
--   red ghost       the Pokemon Tower without the Silph Scope: every spawn is the ghost, never a
--                   Battler target; with the scope they show as themselves; the battle is a ghost one
--   red safari      the Safari Zone: walking near, its Pokemon run at the game's own odds; none chases
local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local VERSION = tostring(GameVersion.get())
local GEN = GameVersion.generation and GameVersion.generation() or 1
local PART = os.getenv("VWOG_P4") or (GEN == 2 and "roamer" or "ghost")
local SHOT = (os.getenv("VWOG_SHOT_DIR") or "shots") .. "/" .. VERSION .. "-p4"

return function(game)
  local fails = 0
  local function say(line) print("[vwog-p4] " .. line) end
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

  local function list()
    local out = {}
    for _, id in ipairs(sm.order or {}) do
      local e = sm.entities[id]
      if e and e.state == "available" then out[#out + 1] = e end
    end
    return out
  end
  local function refill(mapId)
    sm:onMapExited()
    sm:onMapEntered(mapId, game)
    U.wait(2)
  end
  local function battleTop()
    for _ = 1, 600 do
      local t = game.stack and game.stack:top()
      if t and (t.battle or t.enemy) then return t end
      U.wait(1)
    end
    return nil
  end
  local function shots(prefix, n)
    for i = 1, n do
      U.wait(30)
      U.still(game, string.format("%s/%s_%02d.png", SHOT, prefix, i))
    end
  end

  if GEN == 2 then
    local Mon = require("src.battle.gen2.Mon")
    game.save.party = { Mon.new(game.data, "TYPHLOSION", 50) }
  else
    local Pokemon = require("src.pokemon.Pokemon")
    game.save.party = { Pokemon.new(game.data, "VENUSAUR", 40) }
  end

  -- ------------------------------------------------------------------ Gold: the roaming beasts
  if PART == "roamer" then
    local Roamers = require("src.core.gen2.Roamers")
    local save = game.save
    if not Roamers.list(save) then Roamers.init(save, {}) end
    local roster = Roamers.list(save)
    for i = 1, 2 do roster[i].map, roster[i].hp = "ROUTE_29", 0 end
    say(string.format("roster: %s, %s on Route 29", tostring(roster[1].species), tostring(roster[2].species)))
    game.world:warpToMapId("ROUTE_29", 17, 5, "down")
    U.wait(240)
    local beast
    for try = 1, 30 do
      local count = {}
      for _, e in ipairs(list()) do if e.roamer then count[e.roamer] = (count[e.roamer] or 0) + 1 beast = beast or e end end
      if beast then
        say(string.format("fill %d: beasts out %s / %s", try, tostring(count[1]), tostring(count[2])))
        ok((count[1] or 0) <= 1 and (count[2] or 0) <= 1, "never two of the same beast out")
        break
      end
      refill("ROUTE_29")
    end
    if not ok(beast ~= nil, "a roaming beast turns up among the route's spawns") then return finish() end
    local slot = roster[beast.roamer]
    ok(beast.species == slot.species and beast.level == slot.level, "...as itself: " .. tostring(beast.species) .. " Lv" .. tostring(beast.level))
    ok(beast.dex == EP.nationalFor(slot.species), "...in its own art (dex " .. tostring(beast.dex) .. ")")
    local targeted = false
    for _, e in ipairs(sm:fightTargets()) do if e == beast then targeted = true end end
    ok(not targeted, "the Battler never picks it")
    U.still(game, SHOT .. "/roamer_1_route.png")

    -- Classic Enc off: no beast on a step either (the engine rolls it before encounter.roll)
    local function one() return 1 end
    ok(Roamers.checkEncounter(save, "ROUTE_29", false, one) == nil, "Classic Enc off: the step roll is gated")
    opts.vivid_worlds_og.classic_enc = true
    ok(Roamers.checkEncounter(save, "ROUTE_29", false, one) ~= nil, "Classic Enc on: the game's own step roll")
    opts.vivid_worlds_og.classic_enc = false

    -- the beast moves on (JumpRoamMons, as after a Fly): its visible self leaves with it
    Roamers.jumpAll(save, "ROUTE_29", nil, game.world.encounters)
    U.wait(90)
    local still = 0
    for _, e in ipairs(list()) do if e.roamer then still = still + 1 end end
    ok(still == 0, string.format("roamer.moved: the visible beast left (now on %s / %s)", tostring(roster[1].map), tostring(roster[2].map)))

    -- back on the route: touching it opens the engine's roaming battle
    for i = 1, 2 do roster[i].map = "ROUTE_29" end
    beast = nil
    for _ = 1, 30 do
      for _, e in ipairs(list()) do if e.roamer and not beast then beast = e end end
      if beast then break end
      refill("ROUTE_29")
    end
    if not ok(beast ~= nil, "back on Route 29, a beast shows again") then return finish() end
    local started
    local world = game.world
    local origStart = world.startBattle
    world.startBattle = function(w, o, ...) started = o return origStart(w, o, ...) end
    ex.battleTrigger:onPlayerBumped(beast)
    local top = battleTop()
    world.startBattle = origStart
    ok(started ~= nil and started.roaming == beast.roamer, "the battle is the engine's roaming one (roaming = " .. tostring(started and started.roaming) .. ")")
    local foe = top and top.battle and top.battle.enemy
    ok(foe and foe.species == beast.species, "...against " .. tostring(foe and foe.species))
    ok((tonumber(roster[beast.roamer].hp) or 0) > 0, "...and the engine banked its HP at the first meeting")
    shots("roamer_2_battle", 4)
    return finish()
  end

  -- ------------------------------------------------------------------ Gold: Unown's letters
  if PART == "unown" then
    local Unown = require("src.core.gen2.Unown")
    local world = game.world
    local flags = world:engineFlags()
    for _, set in ipairs(Unown.UNLOCK_SETS) do flags[world:engineFlagId(set.name, set.flag)] = true end
    world:warpToMapId("RUINS_OF_ALPH_INNER_CHAMBER", 10, 11, "up")
    U.wait(240)
    local unowns, right, letters = 0, 0, {}
    local pick
    for try = 1, 6 do
      for _, e in ipairs(list()) do
        if e.species == "UNOWN" then
          unowns = unowns + 1
          local letter = Unown.letterFromDVs(e.dvs)
          local want = letter == 1 and 201 or string.format("201-%s", string.char(96 + letter))
          if e.dex == want then right = right + 1 end
          letters[#letters + 1] = Unown.name and Unown.name(letter) or tostring(letter)
          pick = pick or (letter ~= 1 and e or nil)
        end
      end
      if unowns >= 6 and pick then break end
      refill("RUINS_OF_ALPH_INNER_CHAMBER")
    end
    say("letters seen: " .. table.concat(letters, " "))
    ok(unowns > 0, "Unown spawn in the Ruins of Alph")
    ok(right == unowns, string.format("each wears the letter its DVs make (%d / %d)", right, unowns))
    U.still(game, SHOT .. "/unown_1_chamber.png")
    if not ok(pick ~= nil, "one that is not A, to battle") then return finish() end
    local want = Unown.letterFromDVs(pick.dvs)
    ex.battleTrigger:onPlayerBumped(pick)
    local top = battleTop()
    local foe = top and top.battle and top.battle.enemy
    ok(foe and foe.species == "UNOWN" and Unown.letterFromDVs(foe.dvs) == want,
      string.format("its battle is against the same letter (%s)", tostring(foe and Unown.letterFromDVs(foe.dvs))))
    shots("unown_2_battle", 4)
    return finish()
  end

  -- ------------------------------------------------------------------ Red: the Tower's ghosts
  if PART == "ghost" then
    local inv = game.save.inventory
    inv.SILPH_SCOPE = nil
    U.teleport(game, "POKEMON_TOWER_3F", 4, 9, "right")
    U.wait(240)
    local n, ghosts = 0, 0
    for try = 1, 5 do
      n, ghosts = 0, 0
      for _, e in ipairs(list()) do
        n = n + 1
        if e.masked and e.dex == "092-ghost" and not e.shiny then ghosts = ghosts + 1 end
      end
      if n > 0 then break end
      refill("POKEMON_TOWER_3F")
    end
    ok(n > 0, "wild Pokemon spawn in the Tower (" .. n .. ")")
    ok(ghosts == n, string.format("without the Silph Scope every one is the ghost (%d / %d)", ghosts, n))
    ok(#sm:fightTargets() == 0, "the Battler leaves them be")
    U.still(game, SHOT .. "/ghost_1_tower.png")

    inv.SILPH_SCOPE = 1
    refill("POKEMON_TOWER_3F")
    U.wait(30)
    local real, total = 0, 0
    for _, e in ipairs(list()) do
      total = total + 1
      if not e.masked and type(e.dex) == "number" then real = real + 1 end
    end
    ok(total > 0 and real == total, string.format("with the Silph Scope they show as themselves (%d / %d)", real, total))
    U.still(game, SHOT .. "/ghost_2_scope.png")

    inv.SILPH_SCOPE = nil
    refill("POKEMON_TOWER_3F")
    U.wait(30)
    local target = list()[1]
    if not ok(target ~= nil and target.masked, "a ghost to touch") then return finish() end
    ex.battleTrigger:onPlayerBumped(target)
    local top = battleTop()
    ok(top ~= nil and top.ghost ~= nil and top.ghost ~= false, "its battle is a ghost battle")
    ok(top and top.enemy and top.enemy.mon and top.enemy.mon.species == target.species,
      "...against the Pokemon underneath (" .. tostring(top and top.enemy and top.enemy.mon and top.enemy.mon.species) .. ")")
    shots("ghost_3_battle", 4)
    return finish()
  end

  -- ------------------------------------------------------------------ Red: the Safari Zone
  if PART == "safari" then
    game.save.safari = { balls = 30, steps = 500 }
    U.teleport(game, "SAFARI_ZONE_CENTER", 14, 22, "up")
    U.wait(240)
    ok(EP.safariActive(), "in a Safari Zone visit")
    say("wild Pokemon here: " .. #list())
    -- walk up to each of them in turn (each one in reach rolls its odds once, then rests)
    local seen, chased, shot = {}, 0, false
    local function watch()
      for _, e in ipairs(list()) do
        local r = e.react
        if r then
          if r.safari then seen[e.id] = e.species end
          if r.mode == "chase" or r.next == "chase" then chased = chased + 1 end
          if r.safari and r.mode == "flee" and not shot then
            shot = true
            U.still(game, SHOT .. "/safari_1_flee.png")
          end
        end
      end
    end
    for _ = 1, 40 do
      local p = EP.playerCell()
      local best, bestD
      for _, e in ipairs(list()) do
        local d = math.abs(e.cellX - p.x) + math.abs(e.cellY - p.y)
        if not e.react and (e.reactUntil or 0) <= sm.ticks and (not bestD or d < bestD) then best, bestD = e, d end
      end
      if best then
        local dx, dy = best.cellX - p.x, best.cellY - p.y
        local dir = math.abs(dx) > math.abs(dy) and (dx > 0 and "right" or "left") or (dy > 0 and "down" or "up")
        for _ = 1, 16 do
          table.insert(game.input.pressQueue, dir)
          game.input.state[dir] = true
          coroutine.yield()
          watch()
        end
        game.input.state[dir] = false
      end
      for _ = 1, 8 do U.wait(1) watch() end
    end
    local names = {}
    for _, sp in pairs(seen) do names[#names + 1] = sp end
    say("ran from the player: " .. table.concat(names, ", "))
    ok(#names > 0, "walking near, Safari Pokemon run off")
    ok(chased == 0, "none ever chases")
    for _, sp in ipairs({ "DODUO", "RHYHORN", "CHANSEY", "NIDORAN_M" }) do
      say(string.format("  flee odds Lv25 %s: %.0f%%", sp, EP.safariFleeChance(sp, 25)))
    end
    return finish()
  end

  say("unknown part " .. tostring(PART))
  finish()
end
