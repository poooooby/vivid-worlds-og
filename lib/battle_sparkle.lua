-- A one-time shiny sparkle + chime in battle on Red / Blue / Yellow, which have no shiny
-- animation of their own (Gold / Silver / Crystal flash a shiny natively). Ported from Wilds of
-- Kanto Revival, which follows the battle sparkle intro of masterwebx's Shiny Pokemon mod (MIT,
-- https://github.com/masterwebx/gen1recomp-shiny-pokemon): the battle.overlay approach, waiting
-- for the intro, the spark burst and the "Dex Page Added" chime. See THIRD_PARTY_NOTICES.md.
--
-- The engine's draw-only `battle.overlay` hook (BattleState / WideBattle call it at the end of the
-- battle draw, in 160x144 Game Boy coordinates). When a shiny Pokemon appears -- the wild one, or
-- your own when it is sent out -- a short burst of sparks plays over it once, after the intro
-- (slide-in, send-out, grow-in), once per Pokemon per battle. Shininess comes from its DVs
-- (lib/shiny.lua); no recolour.
local V = ...

local BattleSparkle = {}

BattleSparkle.DURATION = 1.35 -- seconds
BattleSparkle.SFX = "Dex_Page_Added" -- a Gen 1 engine SFX key (src/core/Sound.lua)

-- where the burst is centred, in 160x144 battle coordinates (over the enemy pic / the player's back pic)
BattleSparkle.ANCHORS = {
  classic = { enemy = { 120, 32 }, player = { 40, 88 } },
  wide = { enemy = { 200, 40 }, player = { 60, 100 } },
}

local function nowSeconds()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

local function isShinyMon(mon)
  local EnginePatch = V.require("engine_patch")
  if EnginePatch.monShiny then return EnginePatch.monShiny(mon) == true end
  return type(mon) == "table" and mon.shiny == true
end

--- The battle intro for that side is over (slide-in done, no trainer / send-out / grow-in).
function BattleSparkle.ready(battle, isEnemy)
  if type(battle) ~= "table" then return false end
  if (battle.introSlide or 0) > 0 then return false end
  local growing = type(battle.growInScale) == "function"
  if isEnemy then
    if battle.showEnemyTrainer or battle.enemySendingOut then return false end
    if growing and battle:growInScale(battle.enemy) then return false end
  else
    if battle.showPlayerBack or battle.sendingOut then return false end
    if growing and battle:growInScale(battle.player) then return false end
  end
  return true
end

local function isWide(battle)
  if battle.wide then return true end
  if type(battle.wideLayout) == "function" then
    local ok, wide = pcall(battle.wideLayout, battle)
    return ok and wide == true
  end
  return false
end

local function playChime(battle)
  local data = (battle.game and battle.game.data) or battle.data
  if not data then return false end
  local ok, Sound = pcall(require, "src.core.Sound")
  if not (ok and Sound and type(Sound.play) == "function") then return false end
  return pcall(Sound.play, data, BattleSparkle.SFX)
end

-- battle -> { [mon] = { t0 } }, both weak: finished battles and swapped-out Pokemon are collected
local triggered = setmetatable({}, { __mode = "k" })

--- Advances the sparkle state for one overlay draw and returns the bursts to paint now:
--- { { side, progress (0..1), x, y, seed }, ... }. `deps` = { now, playSfx } for tests.
function BattleSparkle.step(battle, deps)
  local out = {}
  if type(battle) ~= "table" then return out end
  deps = deps or {}
  local t = (deps.now or nowSeconds)()
  local seen = triggered[battle]
  if not seen then
    seen = setmetatable({}, { __mode = "k" })
    triggered[battle] = seen
  end
  local anchors = isWide(battle) and BattleSparkle.ANCHORS.wide or BattleSparkle.ANCHORS.classic
  for _, side in ipairs({ "enemy", "player" }) do
    local isEnemy = side == "enemy"
    local battler = battle[side]
    local mon = type(battler) == "table" and battler.mon or nil
    local hidden = (not isEnemy) and (battle.safari or battle.demo)
    if mon and not hidden and not battler.fainted and isShinyMon(mon) then
      local entry = seen[mon]
      if not entry and BattleSparkle.ready(battle, isEnemy) then
        entry = { t0 = t }
        seen[mon] = entry
        pcall(deps.playSfx or playChime, battle)
      end
      if entry then
        local progress = (t - entry.t0) / BattleSparkle.DURATION
        if progress >= 0 and progress < 1 then
          local a = anchors[side]
          out[#out + 1] = { side = side, progress = progress, x = a[1], y = a[2],
            seed = (mon.level or 1) + (isEnemy and 3 or 7) }
        end
      end
    end
  end
  return out
end

--- One burst: eight sparks fly out from (x, y), shrinking and fading, with a brief centre flash.
--- Opaque colours only: alpha blending disappears under some of the engine's palette passes.
function BattleSparkle.drawBurst(x, y, progress, seed, scale)
  if not (love and love.graphics) then return end
  scale = scale or 1.25
  local burst = math.min(1, progress / 0.18)
  local fadingOut = progress > 0.65
  for i = 1, 8 do
    local angle = (i / 8) * math.pi * 2 + (seed or 0) * 0.2
    local radius = (4 + progress * 14 + (i % 3) * 2) * scale
    local sx = x + math.cos(angle) * radius * burst
    local sy = y + math.sin(angle * 1.05) * radius * 0.75 * burst - 2 * scale
    local size = math.max(2, math.floor((2.5 - progress) * scale + 0.5))
    love.graphics.setColor(1, 1, 0.35, 1)
    love.graphics.rectangle("fill", math.floor(sx), math.floor(sy), size, size)
    if not fadingOut then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", math.floor(sx) - 1, math.floor(sy), 1, size)
    end
  end
  if progress < 0.4 then
    local s = math.max(3, math.floor(3 * scale + 0.5))
    love.graphics.setColor(1, 1, 0.7, 1)
    love.graphics.rectangle("fill", math.floor(x) - math.floor(s / 2), math.floor(y) - math.floor(s / 2), s, s)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

--- The `battle.overlay` body: advance the state and paint whatever is active.
function BattleSparkle.draw(battle)
  for _, b in ipairs(BattleSparkle.step(battle)) do
    BattleSparkle.drawBurst(b.x, b.y, b.progress, b.seed)
  end
end

local installed = false

--- Registers the `battle.overlay` wrapper (once). Returns true, or false plus a reason. Never throws.
function BattleSparkle.install(mod)
  if installed then return true end
  if not (mod and mod.hooks and type(mod.hooks.wrap) == "function") then return false, "hooks unavailable" end
  local ok, err = pcall(mod.hooks.wrap, mod.hooks, "battle.overlay", function(next, battle)
    next(battle)
    pcall(BattleSparkle.draw, battle)
  end)
  if not ok then return false, tostring(err) end
  installed = true
  return true
end

return BattleSparkle
