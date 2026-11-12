-- Run: lua tests/gb_roles_unit_test.lua
-- The partner roles' engine seams on Gold (lib/gb/gen2.lua) and what both Game Boy adapters
-- share (lib/gb/shared.lua), against fake Gen 2 engine modules: move ids, damage through
-- Damage.calc with the type chart, the skirmish fighter from the spawn's DVs, EXP, learning,
-- evolution, the item catalog, the bag, sounds, map types, the "+" label.
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then failures = failures + 1 io.stderr:write("FAIL: " .. tostring(msg) .. "\n") else print("ok  " .. tostring(msg)) end
end
local function eq(a, b, msg)
  check(a == b, string.format("%s (got %s expected %s)", msg, tostring(a), tostring(b)))
end

local modules = {}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  modules[name] = assert(loadfile("lib/" .. name .. ".lua"))(V)
  return modules[name]
end
local Shared = V.require("gb/shared")

-- ------- shared: move ids, the "+" label
local n = Shared.moveNumber("TACKLE")
check(type(n) == "number" and n > 0, "a move key is interned to a number")
eq(Shared.moveNumber("TACKLE"), n, "...the same one every time")
eq(Shared.moveKey(n), "TACKLE", "...and back")
eq(Shared.moveNumber({ id = "TACKLE" }), n, "a move slot reads by its id")
check(Shared.knowsMove({ moves = { { id = "TACKLE" } } }, n), "knowsMove by number")
check(not Shared.knowsMove({ moves = { { id = "GROWL" } } }, "TACKLE"), "...and not a move it lacks")
local Font = {}
Font.width = function(t) return #t * 8 end
Font.draw = function(t) Font.drawn = t end
eq(Shared.measureText(Font, "+5 EXP"), 48, "a \"+\" takes one glyph cell")
local rects = {}
love = { graphics = { getColor = function() return 1, 1, 1, 1 end, setColor = function() end,
  rectangle = function(_, x, y, w, h) rects[#rects + 1] = { x, y, w, h } end } }
Shared.drawText(Font, "+5 EXP", 10, 20)
eq(Font.drawn, " 5 EXP", "the font draws the rest (the \"+\" left blank) ...")
check(#rects == 2 and rects[1][1] == 11 and rects[2][2] == 21, "...and the \"+\" is a drawn cross in its cell")

-- ------- shared: the bag's dry run never touches the save
do
  local save = { inventory = { POTION = 3 } }
  local Bag = {
    add = function(s, id, q) s.inventory[id] = (s.inventory[id] or 0) + q return true end,
    addTo = function(inv, _order, id, q) inv[id] = (inv[id] or 0) + q return id ~= "FULL" end,
    order = function() return { "POTION" } end, slots = function() return 1 end,
    capacity = function() return 20 end, pocketOf = function() return "ITEM" end,
  }
  check(Shared.bagCanAdd(Bag, save, {}, "ANTIDOTE", 1), "it fits")
  eq(save.inventory.ANTIDOTE, nil, "...and the dry run left the save alone")
  check(not Shared.bagCanAdd(Bag, save, {}, "FULL", 1), "a full pocket says no")
  check(Shared.bagAdd(Bag, save, {}, "ANTIDOTE", 2) and save.inventory.ANTIDOTE == 2, "bagAdd puts it in")
end

-- ------- Gold's engine, faked
local calls = {}
local data = {
  moves = { TACKLE = { power = 35, accuracy = 95, type = "NORMAL", pp = 35 },
            SLASH = { power = 70, accuracy = 100, type = "NORMAL", pp = 20 },
            EMBER = { power = 40, accuracy = 100, type = "FIRE", pp = 25 } },
  type_chart = { types = { "NORMAL" }, matchups = { "m" },
    battleRules = { criticalChances = { [0] = 17, [2] = 200 }, highCriticalMoves = { SLASH = true } } },
  pokemon = { SENTRET = { baseExp = 57, levelMoves = { { level = 5, move = "DEFENSE_CURL" }, { level = 5, move = "QUICK_ATTACK" } },
                          types = { "NORMAL" } },
              CYNDAQUIL = { types = { "FIRE" } } },
  items = { POTION = { name = "POTION", pocket = "ITEM", price = 300 },
            POKE_BALL = { name = "POKE BALL", pocket = "BALL", price = 200 },
            TM_CURSE = { name = "TM03", pocket = "TM_HM", price = 3000 },
            HM_CUT = { name = "HM01", pocket = "TM_HM", price = 0 },
            BICYCLE = { name = "BICYCLE", pocket = "KEY_ITEM", price = 0 },
            FLOWER_MAIL = { name = "FLOWER MAIL", pocket = "ITEM", price = 50 },
            FIRE_STONE = { name = "FIRE STONE", pocket = "ITEM", price = 2100 } },
}
local Damage = {
  criticalLevel = function(o) return o.highCritMove and 2 or 0 end,
  rollCritical = function(level, random, chances) calls.critLevel = level calls.critRoll = random(256) return chances[level] > 100 end,
  calc = function(o) calls.calc = o return 12, { critical = o.critical, effectiveness = 20 } end,
}
local Mon = {
  new = function(_d, species, level, opts) calls.newOpts = opts
    return { species = species, level = level, dvs = opts and opts.dvs, moves = { { id = "TACKLE", pp = 35 } },
             stats = { hp = 30 }, maxHp = 30, hp = 30 } end,
  experienceGain = function(def, level, parts, trainer) return math.floor(def.baseExp * level / 7 / parts) end,
  gainExperience = function(mon, amount) mon.experience = (mon.experience or 0) + amount mon.level = mon.level + 1 end,
  wildItem = function(def) return def.item end,
}
local Evolution = { checkMon = function(_d, mon) return mon.ready and { into = "FURRET", method = "EVOLVE_LEVEL" } or nil end }
local pushed
local Screens = { push = function(_g, name, args) pushed = { name = name, args = args } end }
local fakeMods = { ["src.battle.gen2.Damage"] = Damage, ["src.battle.gen2.Mon"] = Mon,
  ["src.core.gen2.Evolution"] = Evolution, ["src.ui.Screens"] = Screens,
  ["src.world.gen2.Palettes"] = { clockDaytime = function() return "DAY" end } }
local sfx = {}
local learned = {}
local game = { data = data, save = { party = {} }, stack = { pop = function() calls.popped = true end },
  learnMoveOn = function(_g, mon, id, done) learned[#learned + 1] = id done(true) end }
local world = { game = game, map = { def = { environment = "ROUTE" } },
  playSfxNamed = function(_w, name) sfx[#sfx + 1] = name end }
local Gen2 = assert(loadfile("lib/gb/gen2.lua"))(V)
Gen2.init(function(name) return fakeMods[name] end, function() return world end)
Gen2.speciesDef = function(species) return data.pokemon[species] end
Gen2.displayName = function(mon) return mon.species end

check(Gen2.FEATURES.roles, "Gold carries the partner roles")
local row = Gen2.moveRow(Gen2.moveNumber("TACKLE"))
check(row and row.power == 35 and row.accuracy == 95 and row.type == "NORMAL" and row.pp == 35, "a move's row")
local ally = Gen2.battlerOf({ species = "CYNDAQUIL", level = 20, types = { "FIRE" },
  stats = { hp = 50, attack = 30, specialAttack = 40, defense = 20, specialDefense = 25 } })
local foe = Gen2.battlerOf({ species = "SENTRET", level = 5, stats = { hp = 20, defense = 9, specialDefense = 8 } })
eq(foe.curTypes[1], "NORMAL", "a battler's types come from its species when the mon has none")
local dmg, info = Gen2.moveDamage(ally, foe, Gen2.moveNumber("EMBER"), function(lo, hi) return lo end)
eq(dmg, 12, "the damage is Damage.calc's")
check(info.effectiveness == 2 and info.critical == false, "...its effectiveness x10 read as x1 / x2")
local o = calls.calc
check(o.level == 20 and o.power == 40 and o.moveType == "FIRE", "Damage.calc gets the level, power and type")
check(o.attacker.specialAttack == 40 and o.defender.specialDefense == 8, "...both sides' stats")
check(o.types == data.type_chart.types and o.matchups == data.type_chart.matchups, "...and Gold's type chart")
eq(o.random(256), 0, "its random(n) is the combat rng over 0..n-1")
Gen2.moveDamage(ally, foe, Gen2.moveNumber("SLASH"), function(lo) return lo end)
eq(calls.critLevel, 2, "a high-crit move rolls two rungs up the ladder")
check(calls.calc.critical == true, "...and a critical goes into the formula")
calls.critLevel = nil
Gen2.moveDamage(ally, foe, Gen2.moveNumber("SLASH"), function(lo) return lo end, true)
eq(calls.critLevel, nil, "noCrit: no critical roll at all")

local dvs = { attack = 3, defense = 4, speed = 5, special = 6 }
local fighter = Gen2.buildWildFighter("SENTRET", 5, dvs)
check(fighter and fighter.dvs.attack == 3 and fighter.dvs.special == 6, "the skirmish fighter has the spawn's own DVs")
check(calls.newOpts.wild == nil, "...built as no wild roll (the Shiny Rate leaves it alone)")
eq(fighter.hp, 30, "...at full HP")
eq(Gen2.expGain("SENTRET", 7), 57, "EXP: Mon.experienceGain for one participant")
local mon = { species = "SENTRET", level = 5, experience = 100 }
local res = Gen2.expApply(mon, 40)
check(res and res.gained == 40 and res.fromLevel == 5 and res.toLevel == 6, "expApply reports the levels")
local atFive = Gen2.movesLearnedAt({ species = "SENTRET" }, 5)
check(#atFive == 2 and atFive[1] == "DEFENSE_CURL", "the moves learned at exactly that level")
eq(Gen2.evolutionTarget({ species = "SENTRET" }), nil, "no evolution due: nothing")
local ready = { species = "SENTRET", ready = true }
game.save.party = { ready }
eq(Gen2.evolutionTarget(ready), "FURRET", "an evolution due: its species")
local evolved = false
check(Gen2.startEvolution(ready, "FURRET", function() evolved = true end), "the evolution screen opens")
check(pushed and pushed.name == "Gen2EvolutionAnim" and pushed.args.index == 1, "...Gold's own, for that party slot")
pushed.args.onDone()
check(evolved and calls.popped, "...and on its end the screen closes and onDone runs")
check(not Gen2.startEvolution({ species = "SENTRET" }, nil, function() error("never") end), "nothing to evolve: false")
local learnedAny
check(Gen2.startMoveLearn({ species = "SENTRET", moves = { { id = "TACKLE" } } },
  { "TACKLE", Gen2.moveNumber("EMBER") }, function(any) learnedAny = any end), "the learn flow starts")
check(#learned == 1 and learned[1] == "EMBER" and learnedAny == true, "...through Gold's LearnMove, a known move skipped")
check(not Gen2.startMoveLearn({ species = "SENTRET", moves = { { id = "TACKLE" } } }, { "TACKLE" }), "nothing new: false")

local cat, byId = Gen2.itemCatalog(), {}
for _, e in ipairs(cat) do byId[e.id] = e end
check(byId.POTION and byId.POTION.pocket == "ITEMS" and byId.POTION.use == "heal", "a Potion: the item pocket, a heal")
eq(byId.POKE_BALL and byId.POKE_BALL.pocket, "POKE_BALLS", "a ball: the ball pocket")
check(byId.TM_CURSE and byId.TM_CURSE.isTm and byId.TM_CURSE.pocket == "TM_CASE", "a TM: the TM pocket")
check(byId.HM_CUT and byId.HM_CUT.isHm, "an HM is flagged (the Forager never finds one)")
eq(byId.BICYCLE and byId.BICYCLE.pocket, "KEY_ITEMS", "a key item: the key pocket")
eq(byId.FLOWER_MAIL, nil, "no mail")
check(byId.FIRE_STONE and byId.FIRE_STONE.isEvo, "an evolution stone is flagged")

check(Gen2.playSuccess() and sfx[1] == "Sfx_Item", "the found-it sound is Gold's item sound")
Gen2.playSelect()
eq(sfx[2], "Sfx_ReadText2", "the menu click is Gold's")
eq(Gen2.SFX.SE_SUPER_EFFECTIVE, "Sfx_SuperEffective", "a super-effective hit sounds like Gold's battle")
check(Gen2.holdsExpShare({ item = "EXP_SHARE" }) and not Gen2.holdsExpShare({ item = "POTION" }), "Exp. Share: the holder")
eq(Gen2.wildHeldItem("SENTRET"), nil, "a wild Pokemon's held item: Mon.wildItem's roll")
eq(Gen2.mapTypeOf(world), 3, "a route is map type 3 (the Forager goes out)")
world.map.def.environment = "CAVE"
eq(Gen2.mapTypeOf(world), 4, "a cave is 4")
world.map.def.environment = "TOWN"
eq(Gen2.mapTypeOf(world), 1, "a town is 1 (no foraging)")
world.map.def.environment = "INDOOR"
eq(Gen2.mapTypeOf(world), 8, "indoors is 8 (no foraging)")
love = nil

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("gb_roles_unit_test: all passed")
