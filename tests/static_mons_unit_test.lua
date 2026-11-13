-- Run: lua tests/static_mons_unit_test.lua
-- lib/static_mons.lua: which map objects are Pokemon (and which species), by hand-made facts
-- and over every map object of the six games' real data (../gen1recomp, skipped when absent),
-- and the runtime swap of an npc's sprite.
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

-- ---------------------------------------------------------------- fakes
local npcList, facts = {}, {}
local fakeEP = {
  generation = function() return facts.gen or 1 end,
  mapNpcs = function() return npcList end,
  npcFacts = function(npc, out)
    local f = npc._facts
    if not f then return false end
    for k in pairs(out) do out[k] = nil end
    for k, v in pairs(f) do out[k] = v end
    return true
  end,
  nationalFor = function(id)
    local nat = { MEWTWO = 150, SNORLAX = 143, CLEFAIRY = 35, GYARADOS = 130, MURKROW = 198, LUGIA = 249,
      NIDORAN_M = 32, NIDORAN_F = 29, ZAPDOS = 145, VOLTORB = 100, ELECTRODE = 101, RAIKOU = 243,
      ENTEI = 244, SUICUNE = 245, MOLTRES = 146, SLOWPOKE = 79, KANGASKHAN = 115, RHYDON = 112,
      FARFETCH_D = 83, GROWLITHE = 58, MILTANK = 241, TAUROS = 128, SEEL = 86, LAPRAS = 131, SUDOWOODO = 185 }
    return nat[id]
  end,
  speciesForNational = function(n)
    local by = { [130] = "GYARADOS", [249] = "LUGIA", [115] = "KANGASKHAN", [101] = "ELECTRODE",
      [79] = "SLOWPOKE", [241] = "MILTANK" }
    return by[n]
  end,
}
local wrappers = {}
fakeEP.followerSprite = function(renderer, npc)
  local cur = npc and npc.sprite
  if type(cur) == "table" and not rawget(cur, "_wilds") then npc._wildsBase = cur end
  if not renderer then return npc and npc._wildsBase end
  local s = wrappers[renderer] or { _wilds = true, renderer = renderer }
  wrappers[renderer] = s
  return s
end
local style = "pokemmo"
local modules = {
  engine_patch = fakeEP,
  config = { spriteStyle = function() return style end, IDLE_FLAP_TICKS = 20 },
  form_source = { artKeyFor = function(_mod, species) local n = fakeEP.nationalFor(species) return n and string.format("%03d", n) end },
  sprite_source = { isFloater = function(_mod, dex) return dex == "145" end },
  renderer_factory = { new = function(_mod, dex, shiny, st) return { dex = dex, shiny = shiny, style = st } end },
  actor_renderer = {
    POSE_STAND = "stand", POSE_WALK_A = "walkA", POSE_WALK_B = "walkB",
    idleFlapPose = function(clock) return (math.floor(clock / 20) % 2 == 0) and "walkA" or "stand" end,
  },
}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end
local StaticMons = V.require("static_mons")
local classify = StaticMons.classify

local function isSpecies(id) return fakeEP.nationalFor(id) ~= nil end
local speciesOf = function(v) if type(v) == "number" then return fakeEP.speciesForNational(v) end return v end

-- ---------------------------------------------------------------- Gen 1 by hand
local function g1(name, sprite, pokemon)
  return classify({ gen = 1, name = name, sprite = sprite, pokemon = pokemon }, isSpecies, speciesOf)
end
eq(g1("CERULEANCAVEB1F_MEWTWO", "SPRITE_MONSTER", "MEWTWO"), "MEWTWO", "Gen 1: a static battle's species")
eq(g1("ROUTE12_SNORLAX", "SPRITE_SNORLAX"), "SNORLAX", "Gen 1: the species in the object's name")
eq(g1("POWERPLANT_ELECTRODE2", "SPRITE_POKE_BALL", "ELECTRODE"), "ELECTRODE", "Gen 1: a Pokemon hidden as a Poke Ball")
eq(g1("CERULEANCAVEB1F_ULTRA_BALL", "SPRITE_POKE_BALL"), nil, "Gen 1: a real item ball stays")
eq(g1("PEWTERNIDORANHOUSE_NIDORAN", "SPRITE_MONSTER"), "NIDORAN_M", "Gen 1: NIDORAN is the male")
eq(g1("CELADONMANSION1F_NIDORANF", "SPRITE_MONSTER"), "NIDORAN_F", "Gen 1: NIDORANF the female")
eq(g1("BILLSHOUSE_BILL_POKEMON", "SPRITE_MONSTER"), "CLEFAIRY", "Gen 1: Bill fused with a Clefairy")
eq(g1("COPYCATSHOUSE2F_MONSTER", "SPRITE_MONSTER"), nil, "Gen 1: Copycat's doll stays")
eq(g1("FUCHSIACITY_LAPRAS", "SPRITE_SEEL"), "LAPRAS", "Gen 1: the name beats the sheet")
eq(g1("PIKACHU_FOLLOWER", "SPRITE_PIKACHU"), nil, "Gen 1: the follower's name is no species")
eq(g1("ROUTE12_SNORLAX", "SPRITE_HIKER"), nil, "Gen 1: a person's sheet is never a Pokemon")

-- ---------------------------------------------------------------- Gen 2 by hand
local function g2(mapId, index, sprite, script, spriteSpecies)
  return classify({ gen = 2, mapId = mapId, index = index, sprite = sprite, script = script,
    spriteSpecies = spriteSpecies }, isSpecies, speciesOf)
end
local lugia = { { op = "faceplayer" }, { op = "cry", id = 249 }, { op = "loadwildmon", species = 249, level = 60 } }
eq(g2("WHIRL_ISLAND_LUGIA_CHAMBER", 1, "SPRITE_LUGIA", lugia), "LUGIA", "Gen 2: the wild battle's species")
local redGyarados = { { op = "cry", id = 130 }, { op = "loadwildmon", species = 130 }, { op = "loadvar", args = { 3, 7 } } }
local sp, shiny = g2("LAKE_OF_RAGE", 9, "SPRITE_GYARADOS", redGyarados)
eq(sp, "GYARADOS", "Gen 2: the Lake of Rage Gyarados")
eq(shiny, true, "Gen 2: ...shiny by its FORCESHINY battle type")
eq(select(2, g2("WHIRL_ISLAND_LUGIA_CHAMBER", 1, "SPRITE_LUGIA", lugia)), false, "Gen 2: Lugia is not shiny")
eq(g2("CERULEAN_TRADE_SPEECH_HOUSE", 3, "SPRITE_RHYDON", { { op = "cry", id = 115 } }), "KANGASKHAN",
  "Gen 2: the cry beats a borrowed sheet")
eq(g2("TEAM_ROCKET_BASE_B3F", 3, "SPRITE_MOLTRES", { { op = "opentext" } }), "MURKROW", "Gen 2: the password Murkrow")
eq(g2("BURNED_TOWER_B1F", 3, "SPRITE_GROWLITHE", nil), "ENTEI", "Gen 2: Gold's beasts by their object")
eq(g2("TIN_TOWER_1F", 1, "SPRITE_SUICUNE", nil), "SUICUNE", "Gen 2: a species' own sheet")
eq(g2("ROUTE_36", 3, "SPRITE_SUDOWOODO", nil), "SUDOWOODO", "Gen 2: the variable-sprite Sudowoodo")
eq(g2("TEAM_ROCKET_BASE_B2F", 9, "SPRITE_VOLTORB", nil), "ELECTRODE", "Gen 2: the base's script-less Electrode")
eq(g2("COPYCATS_HOUSE_2F", 4, "SPRITE_MONSTER", { { op = "opentext" } }), nil, "Gen 2: Copycat's doll stays")
eq(g2("ROUTE_34", 2, "SPRITE_DAY_CARE_MON", nil, "MILTANK"), "MILTANK", "Gen 2: the Day-Care's own Pokemon")
eq(g2("ROUTE_36", 2, "SPRITE_YOUNGSTER", { { op = "cry", id = 130 } }), nil, "Gen 2: a person never")
eq(g2("ROUTE_36", 2, "SPRITE_POKE_BALL", { { op = "loadwildmon", species = 130 } }), nil, "Gen 2: an item ball never")
eq(g2("ROUTE_39_BARN", 3, "SPRITE_TAUROS", nil), "MILTANK", "Gen 2: Moomoo")

-- ---------------------------------------------------------------- runtime swap
local base = { name = "engine sheet" }
local mewtwo = { sprite = base, facing = "down", _facts = { gen = 1, name = "CERULEANCAVEB1F_MEWTWO",
  sprite = "SPRITE_MONSTER", pokemon = "MEWTWO" } }
local hiker = { sprite = { name = "hiker sheet" }, _facts = { gen = 1, name = "ROUTE3_HIKER", sprite = "SPRITE_HIKER" } }
local zapdos = { sprite = { name = "bird" }, _facts = { gen = 1, name = "POWERPLANT_ZAPDOS", sprite = "SPRITE_BIRD",
  pokemon = "ZAPDOS" } }
local partner = { sprite = { name = "pikachu" }, pikachuFollower = true,
  _facts = { gen = 1, name = "X_SNORLAX", sprite = "SPRITE_SNORLAX" } }
npcList = { mewtwo, hiker, zapdos, partner }
facts.gen = 1
local sm = StaticMons.new({})
sm:tick()
check(rawget(mewtwo.sprite, "_wilds") == true, "Mewtwo wears our sprite")
eq(mewtwo.sprite.renderer.dex, "150", "...drawn from Mewtwo's art")
eq(mewtwo.sprite.renderer.poseOverride, "stand", "...standing")
eq(hiker.sprite.name, "hiker sheet", "a Hiker keeps his")
eq(partner.sprite.name, "pikachu", "the partner is never touched")
eq(sm:count(), 2, "two Pokemon shown")
local zr = zapdos.sprite.renderer
sm:tick()
check(zapdos.sprite.renderer == zr, "a shown one is not rebuilt each tick")
for _ = 1, 20 do sm:tick() end
check(zr.poseOverride ~= nil, "a floater idles: " .. tostring(zr.poseOverride))
mewtwo.moving, mewtwo.stepFlip = true, true
sm:tick()
eq(mewtwo.sprite.renderer.poseOverride, "walkB", "a stepping one walks")
mewtwo.moving = false
-- the engine hands it another sheet: judged again
local other = { name = "new engine sheet" }
mewtwo.sprite = other
sm:tick()
check(rawget(mewtwo.sprite, "_wilds") == true, "a new engine sheet is dressed again")
-- a Sprite Style switch rebuilds
local before = mewtwo.sprite.renderer
style = "followers"
sm:tick()
check(mewtwo.sprite.renderer ~= before and mewtwo.sprite.renderer.style == "followers", "a style switch rebuilds the art")
-- the hiker is asked once only
local asked = 0
local orig = fakeEP.npcFacts
fakeEP.npcFacts = function(npc, out) if npc == hiker then asked = asked + 1 end return orig(npc, out) end
sm:tick() sm:tick()
eq(asked, 0, "a judged person is not asked again")
fakeEP.npcFacts = orig
sm:restoreAll()
eq(mewtwo.sprite, other, "restoreAll gives the engine sheet back")
eq(sm:count(), 0, "...and nothing is shown")
-- Gold's big Snorlax: drawn through ours, stood in the middle of its 2x2 cells
local snorlax = { sprite = { name = "big" }, bigObject = true, px = 160, py = 96,
  _facts = { gen = 2, mapId = "VERMILION_CITY", index = 5, sprite = "SPRITE_BIG_SNORLAX" } }
npcList, facts.gen = { snorlax }, 2
sm:tick()
eq(snorlax.sprite.renderer.dex, "143", "Gold's big Snorlax is a Snorlax")
eq(snorlax.drawBig, StaticMons._drawBig, "...drawn through ours")
eq(snorlax.sprite.renderer.pushX, 8, "...centred on its 2x2 cells")
sm:restoreAll()
eq(snorlax.drawBig, nil, "...and its own draw back after")

-- ---------------------------------------------------------------- the real games' data
local root = "../gen1recomp"
local function loadData(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local src = f:read("*a")
  f:close()
  local chunk = (loadstring or load)(src, path)
  return chunk and chunk() or nil
end
local probe = io.open(root .. "/red/data/generated/maps.lua", "rb")
if not probe then
  print("skip the real-data checks (no ../gen1recomp)")
else
  probe:close()
  local EXPECT = {
    red = {
      CERULEAN_CAVE_B1F = { [1] = "MEWTWO" }, POWER_PLANT = { [4] = "ELECTRODE", [9] = "ZAPDOS" },
      SEAFOAM_ISLANDS_B4F = { [3] = "ARTICUNO" }, VICTORY_ROAD_2F = { [6] = "MOLTRES" },
      ROUTE_12 = { [1] = "SNORLAX" }, ROUTE_16 = { [7] = "SNORLAX" }, FUCHSIA_CITY = { [9] = "LAPRAS" },
      COPYCATS_HOUSE_2F = { [2] = "DODUO", [3] = false }, CERULEAN_CAVE_1F = {},
    },
    yellow = { CERULEAN_CITY = { [8] = "ELECTRODE" }, VIRIDIAN_POKECENTER = { [5] = "CHANSEY" },
      SUMMER_BEACH_HOUSE = { [2] = "PIKACHU" } },
    gold = { BURNED_TOWER_B1F = { [2] = "RAIKOU", [4] = "SUICUNE" }, ILEX_FOREST = { [2] = "FARFETCH_D" },
      TIN_TOWER_ROOF = { [1] = "HO_OH" }, WHIRL_ISLAND_LUGIA_CHAMBER = { [1] = "LUGIA" } },
    crystal = {
      LAKE_OF_RAGE = { [9] = "GYARADOS*" }, TIN_TOWER_ROOF = { [1] = "HO_OH" },
      CERULEAN_TRADE_SPEECH_HOUSE = { [3] = "KANGASKHAN" }, VERMILION_CITY = { [5] = "SNORLAX" },
      UNION_CAVE_B2F = { [6] = "LAPRAS" }, TEAM_ROCKET_BASE_B2F = { [4] = "DRAGONITE", [8] = "ELECTRODE" },
      MOUNT_MOON_SQUARE = { [1] = "CLEFAIRY" }, ROUTE_30 = { [6] = "RATTATA" },
      OLIVINE_LIGHTHOUSE_6F = { [2] = "AMPHAROS" }, COPYCATS_HOUSE_2F = { [2] = "DODRIO", [4] = false },
      POKEMON_FAN_CLUB = { [5] = false, [6] = "BAYLEEF" },
    },
  }
  local PEOPLE = { HIKER = true, YOUNGSTER = true, LASS = true, NURSE = true, OAK = true }
  for _, version in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal" }) do
    local dir = root .. "/" .. version .. "/data/generated/"
    local maps = loadData(dir .. "maps.lua")
    local mons = loadData(dir .. "pokemon.lua")
    if maps and mons then
      local gen = loadData(dir .. "scripts.lua") and 2 or 1
      local scripts = gen == 2 and loadData(dir .. "scripts.lua") or nil
      local byDex = {}
      for key, d in pairs(mons) do if type(d) == "table" and tonumber(d.dex) then byDex[tonumber(d.dex)] = key end end
      local function realSpecies(id) return type(id) == "string" and mons[id] ~= nil end
      local function realOf(v) if type(v) == "number" then return byDex[v] end return v end
      local shown, peopleShown, unknown = 0, 0, {}
      local got = {}
      for mapId, m in pairs(maps) do
        for _, o in ipairs(m.objects or {}) do
          local f = { gen = gen, mapId = mapId, index = o.index, name = o.name, pokemon = o.pokemon,
            sprite = type(o.sprite) == "string" and o.sprite or nil,
            script = scripts and o.scriptKey and scripts[o.scriptKey] or nil }
          local s, sh = classify(f, realSpecies, realOf)
          if s then
            shown = shown + 1
            if not realSpecies(s) then unknown[#unknown + 1] = mapId .. ":" .. tostring(s) end
            local sheet = tostring(f.sprite):gsub("^SPRITE_", "")
            if PEOPLE[sheet] then peopleShown = peopleShown + 1 end
          end
          got[mapId .. "#" .. tostring(o.index)] = s and (s .. (sh and "*" or "")) or false
        end
      end
      check(shown > 20, version .. ": " .. shown .. " Pokemon objects on its maps")
      eq(peopleShown, 0, version .. ": no person dressed as a Pokemon")
      eq(#unknown, 0, version .. ": every species found is a real one " .. table.concat(unknown, " "))
      for mapId, objs in pairs(EXPECT[version] or {}) do
        for index, want in pairs(objs) do
          eq(got[mapId .. "#" .. index], want, version .. " " .. mapId .. " #" .. index)
        end
      end
    else
      print("skip " .. version .. " (no data)")
    end
  end
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("all static_mons checks passed")
