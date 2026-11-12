-- The Shiny Rate option: how often a wild Pokemon is shiny, on Red / Blue / Yellow and on
-- Gold / Silver / Crystal. Ported from Wilds of Kanto Revival's shiny system, which follows the
-- design of masterwebx's Shiny Pokemon mod (MIT, https://github.com/masterwebx/gen1recomp-shiny-pokemon):
-- the rate steps, real shiny DVs on wild Pokemon and the hand-off into the battle builder.
-- See THIRD_PARTY_NOTICES.md.
--
-- On both generations a shiny is a matter of DVs: Defense, Speed and Special 10 and an Attack of
-- 2, 3, 6, 7, 10, 11, 14 or 15 (Gen 2's own rule; on Gen 1 the engine's "virtual shiny",
-- Stats.isShiny). So the answer is settled in the DVs and stays settled: the battle Pokemon is
-- built from them, a caught one keeps them, and every screen reads the same thing.
--   * a visible spawn rolls when it appears (its sprite shows it) and its battle is built from
--     those DVs (lib/gb/gen1.lua hands them to BattleState.newWild; lib/gb/gen2.lua to Mon.new);
--   * every other wild Pokemon -- step and Surf encounters, fishing, Headbutt, the Bug-Catching
--     Contest, a roaming beast's first meeting, a scripted one -- rolls as the engine builds it
--     (installed through EnginePatch.installShiny).
-- Off means none: a natural shiny spread (1 in 8192) is nudged out of the pattern. Trainers'
-- Pokemon, gifts, eggs and starters are never touched, and neither are DVs the game itself fixed
-- (a roaming beast met before, the red Gyarados).
local V = ...

local Shiny = {}

-- denominator per rate key (0 = always); "off" has none
Shiny.RATE_DENOMINATOR = {
  gen2 = 8192, modern = 4096, common = 1024, frequent = 512, often = 100, high = 10, always = 0,
}
Shiny.DEFAULT_RATE = "modern"
-- the Attack DVs of a shiny (Defense / Speed / Special 10)
Shiny.ATTACK_DVS = { 2, 3, 6, 7, 10, 11, 14, 15 }

local function rngFn(rng)
  if type(rng) == "function" then return rng end
  if love and love.math and love.math.random then return love.math.random end
  return math.random
end

-- ------------------------------------------------------------------ the rate
--- The Shiny Rate key ("off" | "gen2" | "modern" | ...); the default if the option can't be read.
function Shiny.rateKey(mod)
  local ok, Config = pcall(V.require, "config")
  if not (ok and Config and type(Config.shinyRate) == "function") then return Shiny.DEFAULT_RATE end
  local okRead, key = pcall(Config.shinyRate, mod)
  if okRead and (key == "off" or Shiny.RATE_DENOMINATOR[key] ~= nil) then return key end
  return Shiny.DEFAULT_RATE
end

--- true with the option's chance. `rng(lo, hi)` is an integer RNG (love.math.random by default).
function Shiny.roll(mod, rng)
  local denom = Shiny.RATE_DENOMINATOR[Shiny.rateKey(mod)]
  if denom == nil then return false end
  if denom <= 1 then return true end
  return rngFn(rng)(1, denom) == 1
end

-- ------------------------------------------------------------------ DVs
--- The HP DV: the low bit of each of the other four.
function Shiny.hpDv(dvs)
  return (dvs.attack % 2) * 8 + (dvs.defense % 2) * 4 + (dvs.speed % 2) * 2 + (dvs.special % 2)
end

local function withHp(dvs)
  dvs.hp = Shiny.hpDv(dvs)
  return dvs
end

--- Fresh DVs, each 0..15 (Stats.randomDVs / Mon.randomDVs).
function Shiny.randomDvs(rng)
  rng = rngFn(rng)
  return withHp({ attack = rng(0, 15), defense = rng(0, 15), speed = rng(0, 15), special = rng(0, 15) })
end

--- Shiny DVs with the given (or a random) shiny Attack.
function Shiny.makeDVs(rng, attack)
  attack = attack or Shiny.ATTACK_DVS[rngFn(rng)(1, #Shiny.ATTACK_DVS)]
  return withHp({ attack = attack, defense = 10, speed = 10, special = 10 })
end

--- The shiny DV pattern (Gen 2's CheckShininess, Gen 1's Stats.isShiny).
function Shiny.dvsAreShiny(dvs)
  if type(dvs) ~= "table" then return false end
  if dvs.defense ~= 10 or dvs.speed ~= 10 or dvs.special ~= 10 then return false end
  local a = tonumber(dvs.attack) or 0
  return a % 4 == 2 or a % 4 == 3
end

local function copyDvs(dvs)
  return withHp({ attack = dvs.attack, defense = dvs.defense, speed = dvs.speed, special = dvs.special })
end

-- A natural shiny spread nudged out of the pattern by one point.
local NUDGES = { { "special", 9 }, { "special", 11 }, { "speed", 9 }, { "speed", 11 } }

--- DVs that are shiny when `want`, otherwise not, starting from `dvs`. `allowed(dvs)` is the
--- game's own limit on a wild Pokemon's DVs (an Unown's letter must be one its chamber unlocked);
--- a shiny it allows none of stays as it is (not shiny). Returns dvs, shiny.
function Shiny.settle(dvs, want, allowed, rng)
  allowed = allowed or function() return true end
  if want then
    if Shiny.dvsAreShiny(dvs) and allowed(dvs) then return dvs, true end
    local n = #Shiny.ATTACK_DVS
    local start = rngFn(rng)(1, n)
    for i = 0, n - 1 do
      local d = Shiny.makeDVs(nil, Shiny.ATTACK_DVS[(start + i - 1) % n + 1])
      if allowed(d) then return d, true end
    end
  end
  if not Shiny.dvsAreShiny(dvs) then return dvs, false end
  for _, nudge in ipairs(NUDGES) do
    local d = copyDvs(dvs)
    d[nudge[1]] = nudge[2]
    d = withHp(d)
    if allowed(d) then return d, false end
  end
  return dvs, true -- nothing else the game allows: it keeps its natural shine
end

--- The DVs a wild Pokemon the engine is building ends up with: `dvs` (or fresh ones) settled by
--- the Shiny Rate. Returns dvs, shiny.
function Shiny.wildDvs(mod, dvs, allowed, rng)
  return Shiny.settle(type(dvs) == "table" and dvs or Shiny.randomDvs(rng), Shiny.roll(mod, rng), allowed, rng)
end

--- Settles a visible spawn's shininess: the Shiny Rate, plus a shiny chain's chance (`bonus`
--- from Modern Spawns' chainBonus, nil = none), written into `enc.dvs` (the DVs its battle is
--- built with). `wantShiny` true / false forces the answer (a developer's test spawn).
--- Mutates and returns `enc`; `enc.shiny` is always set.
function Shiny.rollForEncounter(mod, enc, bonus, rng, wantShiny)
  if type(enc) ~= "table" then return enc end
  local want = wantShiny
  if want == nil then
    want = Shiny.roll(mod, rng)
    local chance = type(bonus) == "table" and tonumber(bonus.shiny) or 0
    if not want and chance > 0 and (rngFn(rng)(1, 1000000) / 1000000) <= chance then want = true end
  end
  local EnginePatch = V.require("engine_patch")
  local function allowed(d)
    if not EnginePatch.dvsAllowed then return true end
    return EnginePatch.dvsAllowed(enc.species, d) ~= false
  end
  local dvs = type(enc.dvs) == "table" and enc.dvs or Shiny.randomDvs(rng)
  enc.dvs, enc.shiny = Shiny.settle(dvs, want == true, allowed, rng)
  return enc
end

--- Has every wild Pokemon the engine builds go through the Shiny Rate (once; safe to repeat).
function Shiny.install(mod)
  local EnginePatch = V.require("engine_patch")
  if not EnginePatch.installShiny then return false, "no engine seam" end
  return EnginePatch.installShiny(function(dvs, allowed, rng)
    return Shiny.wildDvs(mod, dvs, allowed, rng)
  end)
end

return Shiny
