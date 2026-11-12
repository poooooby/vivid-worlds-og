-- In-game check of the Shiny Rate (P2), run like tests/drivers/smoke.lua:
--   POKEPORT_DRIVER=<this> POKEPORT_VERSION=red|crystal VWOG_SHOT_DIR=<dir> lovec .
-- Shiny Rate Always: every visible spawn is shiny (sprite and DVs), a classic wild Pokemon the
-- engine builds is shiny, a trainer's is not, the battle against a visible one is against that
-- shiny; a shiny partner shows its shiny sprite. Shiny Rate Off: none.
local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local VERSION = tostring(GameVersion.get())
local GEN = GameVersion.generation and GameVersion.generation() or 1
local SHOT = (os.getenv("VWOG_SHOT_DIR") or "shots") .. "/" .. VERSION .. "-shiny"

local function patternShiny(d)
  return type(d) == "table" and d.defense == 10 and d.speed == 10 and d.special == 10
    and (d.attack % 4 == 2 or d.attack % 4 == 3)
end

return function(game)
  local fails = 0
  local function say(line) print("[vwog-shiny] " .. line) end
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
  local EP, sm, fa = ex.enginePatch, ex.spawnManager, ex.followerAdapter
  local opts = game.mods.modOptions
  opts.vivid_worlds_og = opts.vivid_worlds_og or {}
  opts.vivid_worlds_og.shiny_rate = "always"

  local SHINY = { attack = 10, defense = 10, speed = 10, special = 10 }
  local buildWild, buildTrainer
  if GEN == 1 then
    local Pokemon = require("src.pokemon.Pokemon")
    local Stats = require("src.pokemon.Stats")
    local lead = Pokemon.new(game.data, "PIKACHU", 15)
    lead.dvs = { attack = 10, defense = 10, speed = 10, special = 10, hp = 0 }
    lead.stats = Stats.calc(game.data.pokemon.PIKACHU, 15, lead.dvs)
    lead.hp = lead.stats.hp
    game.save.party = { lead }
    local BattleState = require("src.battle.BattleState")
    buildWild = function() return BattleState.newWild(game, "PIDGEY", 3).enemy.mon end
    buildTrainer = function() return Pokemon.new(game.data, "PIDGEY", 3) end
    U.teleport(game, "ROUTE_1", 14, 8, "down")
  else
    local Mon = require("src.battle.gen2.Mon")
    game.save.party = { Mon.new(game.data, "CYNDAQUIL", 15, { dvs = SHINY }) }
    buildWild = function() return Mon.new(game.data, "PIDGEY", 3, { wild = true }) end
    buildTrainer = function() return Mon.new(game.data, "PIDGEY", 3, {}) end
    game.world:warpToMapId("ROUTE_29", 17, 5, "down")
  end
  U.wait(360)

  -- the visible spawns
  local n, shinyN = 0, 0
  for _, id in ipairs(sm.order or {}) do
    local e = sm.entities[id]
    if e then
      n = n + 1
      if e.shiny == true and patternShiny(e.dvs) and e.renderer and e.renderer.shiny then shinyN = shinyN + 1 end
    end
  end
  say(string.format("visible spawns: %d, shiny (flag + DVs + sprite): %d", n, shinyN))
  ok(n > 0 and shinyN == n, "Always: every visible spawn is shiny, in its DVs and its sprite")

  -- the partner
  ok(EP.monShiny(game.save.party[1]) == true, "the shiny lead reads as shiny")
  ok(fa and fa.leadShiny == true and fa.renderer and fa.renderer.shiny, "...and the partner shows its shiny sprite")

  -- the engine's own builders
  ok(patternShiny(buildWild().dvs), "Always: a classic wild Pokemon the engine builds is shiny")
  local trainerShiny = 0
  for _ = 1, 20 do if patternShiny(buildTrainer().dvs) then trainerShiny = trainerShiny + 1 end end
  ok(trainerShiny == 0, "...a trainer's / gift's Pokemon is not touched")
  opts.vivid_worlds_og.shiny_rate = "off"
  local offShiny = 0
  for _ = 1, 40 do if patternShiny(buildWild().dvs) then offShiny = offShiny + 1 end end
  ok(offShiny == 0, "Off: no classic wild Pokemon is shiny")
  opts.vivid_worlds_og.shiny_rate = "always"
  U.still(game, SHOT .. "/1_route.png")

  -- the battle against a visible one is against that shiny
  local target
  for _, id in ipairs(sm.order or {}) do
    local e = sm.entities[id]
    if e and e.state == "available" and e.terrain ~= "water" then target = e break end
  end
  if not ok(target ~= nil, "a wild Pokemon to bump") then return finish() end
  local want = target.dvs
  ex.battleTrigger:onPlayerBumped(target)
  local top
  for _ = 1, 600 do
    local t = game.stack and game.stack:top()
    if t and (t.battle or t.enemy) then top = t break end
    U.wait(1)
  end
  if not ok(top ~= nil, "the engine's battle started") then return finish() end
  local foe = (GEN == 1) and (top.enemy and top.enemy.mon) or (top.battle and top.battle.enemy)
  say(string.format("foe %s Lv%s DVs %s/%s/%s/%s (spawn %s/%s/%s/%s)", tostring(foe and foe.species),
    tostring(foe and foe.level), tostring(foe and foe.dvs.attack), tostring(foe and foe.dvs.defense),
    tostring(foe and foe.dvs.speed), tostring(foe and foe.dvs.special), tostring(want.attack), tostring(want.defense),
    tostring(want.speed), tostring(want.special)))
  ok(foe and foe.species == target.species and foe.dvs.attack == want.attack and patternShiny(foe.dvs),
    "the battle Pokemon is that spawn, with its shiny DVs")
  ok(foe and EP.monShiny(foe) == true, "...and the game reads it as shiny")
  -- the intro, then the sparkle (Gen 1) / the game's own shiny flash (Gen 2)
  for i = 1, 8 do
    U.wait(30)
    local t = game.stack and game.stack:top()
    local m = t and ((GEN == 1) and (t.enemy and t.enemy.mon) or (t.battle and t.battle.enemy))
    say(string.format("  frame %d: same battle %s, foe %s", i, tostring(t == top), tostring(m and m.species)))
    U.still(game, string.format("%s/2_battle_%02d.png", SHOT, i))
  end
  finish()
end
