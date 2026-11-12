-- Run: lua tests/shiny_unit_test.lua
-- lib/shiny.lua (the Shiny Rate, settled in DVs) and its two engine seams: lib/gb/gen1.lua
-- (BattleState.newWild's Pokemon.new) and lib/gb/gen2.lua (Mon.new for wild Pokemon).
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  else
    print("ok  " .. tostring(msg))
  end
end
local function eq(a, b, msg)
  check(a == b, string.format("%s (got %s expected %s)", msg, tostring(a), tostring(b)))
end

local fakeEngine = {}
local modules = {}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  if name == "engine_patch" then
    modules[name] = fakeEngine
    return fakeEngine
  end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end

local rate = "modern"
local mod = { options = { get = function(_, key) if key == "shiny_rate" then return rate end end } }
local Shiny = V.require("shiny")

-- the engine's own rule (src/pokemon/Stats.lua, src/battle/gen2/Mon.lua vanillaShiny)
local function engineShiny(d)
  if d.defense ~= 10 or d.speed ~= 10 or d.special ~= 10 then return false end
  return d.attack % 4 == 2 or d.attack % 4 == 3
end
local function hpOf(d) return (d.attack % 2) * 8 + (d.defense % 2) * 4 + (d.speed % 2) * 2 + (d.special % 2) end

-- ------- the DV pattern
do
  local same = true
  for a = 0, 15 do
    for _, s in ipairs({ 9, 10, 11 }) do
      local d = { attack = a, defense = 10, speed = 10, special = s }
      if Shiny.dvsAreShiny(d) ~= engineShiny(d) then same = false end
    end
  end
  check(same, "dvsAreShiny is the engine's rule (Attack 2/3/6/7/10/11/14/15, the rest 10)")
  for i = 1, 20 do
    local d = Shiny.makeDVs(math.random)
    if not (engineShiny(d) and d.hp == hpOf(d)) then same = false end
  end
  check(same, "makeDVs: always shiny, HP DV from the other four")
  local r = Shiny.randomDvs(function(lo, hi) return hi end)
  check(r.attack == 15 and r.special == 15 and r.hp == 15, "randomDvs: each 0..15 with its HP DV")
end

-- ------- the rate
do
  rate = "always"
  check(Shiny.roll(mod, function() return 2 end), "Always: every roll")
  rate = "off"
  check(not Shiny.roll(mod, function() return 1 end), "Off: never")
  rate = "gen2"
  local asked
  check(Shiny.roll(mod, function(lo, hi) asked = hi return 1 end), "1/8192: a 1 hits")
  eq(asked, 8192, "...out of 8192")
  check(not Shiny.roll(mod, function() return 2 end), "...anything else misses")
  rate = "nonsense"
  eq(Shiny.rateKey(mod), "modern", "an unknown saved value reads as the default (1/4096)")
  rate = "high"
  Shiny.roll(mod, function(lo, hi) asked = hi return 1 end)
  eq(asked, 10, "1/10 rolls out of 10")
end

-- ------- settle
do
  local plain = { attack = 1, defense = 2, speed = 3, special = 4, hp = 0 }
  local d, s = Shiny.settle(plain, true, nil, function() return 1 end)
  check(s == true and engineShiny(d), "want shiny: shiny DVs")
  d, s = Shiny.settle(plain, false)
  check(s == false and d == plain, "not wanted, not shiny: the DVs stand untouched")
  local natural = { attack = 6, defense = 10, speed = 10, special = 10, hp = 0 }
  d, s = Shiny.settle(natural, false)
  check(s == false and not engineShiny(d) and d.attack == 6 and d.defense == 10, "Off: a natural shiny is nudged out of the pattern")
  eq(d.hp, hpOf(d), "...with its HP DV redone")
  d, s = Shiny.settle(natural, true)
  check(s == true and d == natural, "a natural shiny that is wanted stays as it is")
  -- the game's limit: only Attack 14 allowed
  d, s = Shiny.settle(plain, true, function(x) return x.attack == 14 end, function() return 1 end)
  check(s == true and d.attack == 14, "a shiny within the game's limit (an Unown's letters)")
  d, s = Shiny.settle(plain, true, function(x) return not engineShiny(x) end, function() return 1 end)
  check(s == false and d == plain, "no shiny the game allows: it stays not shiny")
end

-- ------- a visible spawn's roll
do
  local askedAllowed = {}
  fakeEngine.dvsAllowed = function(species, d) askedAllowed[#askedAllowed + 1] = species return true end
  rate = "always"
  local enc = Shiny.rollForEncounter(mod, { species = "PIDGEY", level = 3 })
  check(enc.shiny == true and engineShiny(enc.dvs), "Always: the spawn is shiny, in its DVs")
  eq(askedAllowed[1], "PIDGEY", "...within what the game allows that species")
  rate = "off"
  enc = Shiny.rollForEncounter(mod, { species = "PIDGEY", level = 3 })
  check(enc.shiny == false and type(enc.dvs) == "table" and not engineShiny(enc.dvs), "Off: not shiny, DVs to battle with")
  local given = { attack = 1, defense = 2, speed = 3, special = 4, hp = 0 }
  enc = Shiny.rollForEncounter(mod, { species = "SENTRET", dvs = given })
  check(enc.dvs == given, "DVs the encounter already rolled (Gen 2) are kept when not shiny")
  enc = Shiny.rollForEncounter(mod, { species = "PIDGEY" }, { shiny = 1 }, math.random)
  check(enc.shiny == true, "a shiny chain's chance (Modern Spawns) can make it shiny with the rate Off")
  enc = Shiny.rollForEncounter(mod, { species = "PIDGEY" }, nil, nil, true)
  check(enc.shiny == true and engineShiny(enc.dvs), "a forced shiny (developer test spawn)")
  rate = "always"
  enc = Shiny.rollForEncounter(mod, { species = "PIDGEY" }, nil, nil, false)
  check(enc.shiny == false, "a forced plain one, whatever the rate")
  fakeEngine.dvsAllowed = function() return false end
  enc = Shiny.rollForEncounter(mod, { species = "UNOWN", dvs = { attack = 1, defense = 2, speed = 3, special = 4 } })
  check(enc.shiny == false, "no shiny the game allows: not shiny")
  fakeEngine.dvsAllowed = nil
end

-- ------- Gen 1 seam: BattleState.newWild's Pokemon.new
do
  local built = {}
  local Pokemon = {}
  function Pokemon.new(data, species, level)
    local mon = { species = species, level = level, dvs = { attack = 1, defense = 2, speed = 3, special = 4, hp = 0 },
      stats = { hp = 11 }, hp = 11 }
    built[#built + 1] = mon
    return mon
  end
  local BattleState = {}
  function BattleState.newWild(game, species, level)
    return { enemy = { mon = Pokemon.new(game.data, species, level) } }
  end
  local Stats = {
    isShiny = engineShiny,
    calc = function(def, level, dvs) return { hp = 100 + dvs.attack } end,
  }
  local fakeMods = { ["src.pokemon.Pokemon"] = Pokemon, ["src.battle.BattleState"] = BattleState,
    ["src.pokemon.Stats"] = Stats }
  local Gen1 = assert(loadfile("lib/gb/gen1.lua"))(V)
  Gen1.init(function(name) return fakeMods[name] end)
  local Shiny1 = Shiny
  rate = "always"
  check(Gen1.installShiny(function(dvs, allowed, rng) return Shiny1.wildDvs(mod, dvs, allowed, rng) end),
    "Gen 1: the seam installs")
  check(Gen1.installShiny(function(dvs, allowed, rng) return Shiny1.wildDvs(mod, dvs, allowed, rng) end),
    "...and installing again is harmless")
  local game = { data = { pokemon = { RATTATA = { baseStats = {} } } } }
  local battle = BattleState.newWild(game, "RATTATA", 3)
  local wild = battle.enemy.mon
  check(engineShiny(wild.dvs) and wild.shiny == true, "Gen 1, Always: a step encounter's Pokemon is shiny")
  eq(wild.hp, 100 + wild.dvs.attack, "...its stats rebuilt from its new DVs")
  check(Gen1.isShiny(wild), "...and reads as shiny (Stats.isShiny)")
  local trainerMon = Pokemon.new(game.data, "RATTATA", 3)
  check(not engineShiny(trainerMon.dvs) and trainerMon.shiny == nil, "a Pokemon built outside newWild is never touched")
  rate = "off"
  wild = BattleState.newWild(game, "RATTATA", 3).enemy.mon
  check(not Gen1.isShiny(wild), "Gen 1, Off: not shiny")
  -- a visible spawn's battle: its own DVs, whatever the rate
  rate = "always"
  local ow = { pushBattle = function() end, map = {} }
  Gen1.game = function() return game end
  local spawnDvs = { attack = 3, defense = 7, speed = 8, special = 9 }
  local pushed
  ow.pushBattle = function(_, b) pushed = b end
  check(Gen1.startWild(ow, { species = "RATTATA", level = 4, dvs = spawnDvs }), "Gen 1: a visible spawn's battle starts")
  local m = pushed and pushed.enemy.mon
  check(m and m.dvs.attack == 3 and m.dvs.special == 9 and not Gen1.isShiny(m),
    "...with the DVs it rolled when it appeared (not re-rolled at Always)")
  eq(m and m.hp, 103, "...and stats built from them")
end

-- ------- Gen 2 seam: Mon.new for wild Pokemon
do
  local Mon = {}
  local lastOpts
  function Mon.new(data, species, level, opts)
    lastOpts = opts
    local dvs = (opts and opts.dvs) or { attack = 1, defense = 2, speed = 3, special = 4 }
    return { species = species, level = level, dvs = dvs, shiny = (opts and opts.shiny) or engineShiny(dvs) }
  end
  Mon.isShiny = function(dvs) return engineShiny(dvs) end
  local unlocked = { [9] = true } -- only letter I
  local Unown = {
    SPECIES = "UNOWN",
    letterFromDVs = function(d) return (d.attack == 2 or d.attack == 3 or d.attack == 10 or d.attack == 11) and 9 or 22 end,
    letterUnlocked = function(letter) return unlocked[letter] == true end,
  }
  local fakeMods = { ["src.battle.gen2.Mon"] = Mon, ["src.core.gen2.Unown"] = Unown }
  local Gen2 = assert(loadfile("lib/gb/gen2.lua"))(V)
  Gen2.init(function(name) return fakeMods[name] end)
  local world = { unownUnlockFlags = function() return {} end }
  check(Gen2.installShiny(function(dvs, allowed, rng) return Shiny.wildDvs(mod, dvs, allowed, rng) end,
    function() return world end), "Gen 2: the seam installs")
  rate = "always"
  local wild = Mon.new({}, "SENTRET", 3, { wild = true })
  check(wild.shiny and engineShiny(wild.dvs), "Gen 2, Always: a wild Pokemon is shiny, in its DVs")
  local trainer = Mon.new({}, "SENTRET", 3, {})
  check(not trainer.shiny, "a trainer's / gift's Pokemon (no opts.wild) is never touched")
  local fixed = { attack = 5, defense = 5, speed = 5, special = 5 }
  local roamer = Mon.new({}, "RAIKOU", 40, { wild = true, dvs = fixed })
  check(roamer.dvs == fixed and not roamer.shiny, "DVs the game fixed (a roaming beast met before) stand")
  local opts = { wild = true }
  Mon.new({}, "SENTRET", 3, opts)
  eq(opts.dvs, nil, "the caller's own options table is left as it was")
  local unown = Mon.new({}, "UNOWN", 5, { wild = true, dvs = { attack = 0, defense = 0, speed = 0, special = 0 } })
  check(unown.shiny and Unown.letterFromDVs(unown.dvs) == 9, "an Unown is made shiny only with a letter its chamber unlocked")
  unlocked = { [1] = true } -- neither shiny letter unlocked
  unown = Mon.new({}, "UNOWN", 5, { wild = true, dvs = { attack = 0, defense = 0, speed = 0, special = 0 } })
  check(not unown.shiny, "...and stays plain when neither shiny letter is unlocked")
  rate = "off"
  wild = Mon.new({}, "SENTRET", 3, { wild = true, dvs = nil })
  check(not wild.shiny, "Gen 2, Off: not shiny")
  -- a visible spawn's battle keeps its own DVs
  rate = "always"
  local started
  local w = { game = { data = {}, save = {} }, startBattle = function(_, b) started = b end }
  check(Gen2.startWild(w, { species = "SENTRET", level = 3, dvs = { attack = 1, defense = 1, speed = 1, special = 1 } }),
    "Gen 2: a visible spawn's battle starts")
  check(started and started.wild.dvs.attack == 1 and not started.wild.shiny, "...with the DVs it rolled (not re-rolled)")
  rate = "off"
  local redGyarados = Mon.new({}, "GYARADOS", 30, { wild = true, dvs = { attack = 14, defense = 10, speed = 10, special = 10 } })
  check(redGyarados.shiny, "the red Gyarados (FORCESHINY DVs) stays shiny with the rate Off")
end

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("shiny_unit_test: all passed")
