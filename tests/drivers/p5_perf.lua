-- Per-frame cost of the mod (P5), run like tests/drivers/smoke.lua:
--   POKEPORT_DRIVER=<this> POKEPORT_VERSION=red|crystal lovec .
-- Walks Route 1 / Route 29 with the partner out and the wild Pokemon about, the garbage
-- collector stopped, and reports per component: KB allocated and ms spent a frame. Then counts
-- the mod's ticks a frame with a dialogue box up and in a battle (each should be at most 1).
local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local VERSION = tostring(GameVersion.get())
local GEN = GameVersion.generation and GameVersion.generation() or 1
local FRAMES = tonumber(os.getenv("VWOG_PERF_FRAMES")) or 600

return function(game)
  local function say(line) print("[vwog-perf] " .. line) end
  U.wait(60)
  local ex = game.mods and game.mods.exports and game.mods.exports.vivid_worlds_og
  if not (ex and ex.engineReady) then say("FAIL: mod not ready") love.event.quit(1) return end
  local EP, sm, fa = ex.enginePatch, ex.spawnManager, ex.followerAdapter
  local opts = game.mods.modOptions
  opts.vivid_worlds_og = opts.vivid_worlds_og or {}
  opts.vivid_worlds_og.classic_enc = false

  if GEN == 1 then
    local Pokemon = require("src.pokemon.Pokemon")
    game.save.party = { Pokemon.new(game.data, "VENUSAUR", 40) }
    U.teleport(game, "ROUTE_1", 14, 8, "down")
  else
    local Mon = require("src.battle.gen2.Mon")
    game.save.party = { Mon.new(game.data, "TYPHLOSION", 40) }
    game.world:warpToMapId("ROUTE_29", 17, 5, "down")
  end
  U.wait(300)

  -- ---- instrument: instance fields shadow the class methods the hooks call
  local stats, order = {}, {}
  local measuring = false
  local function wrap(label, obj, name)
    local orig = obj and obj[name]
    if type(orig) ~= "function" then return end
    stats[label] = { kb = 0, ms = 0, calls = 0 }
    order[#order + 1] = label
    obj[name] = function(...)
      if not measuring then return orig(...) end
      local s = stats[label]
      local k0, t0 = collectgarbage("count"), love.timer.getTime()
      local r1, r2, r3 = orig(...)
      s.kb = s.kb + collectgarbage("count") - k0
      s.ms = s.ms + (love.timer.getTime() - t0) * 1000
      s.calls = s.calls + 1
      return r1, r2, r3
    end
  end
  wrap("spawn tick", sm, "tick")
  wrap("spawn collectActors", sm, "collectActors")
  wrap("partner tick", fa, "tick")
  wrap("partner collectActors", fa, "collectActors")
  wrap("talk tick", ex.followerInteraction, "tick")
  wrap("holder tick", ex.holderReady, "tick")
  wrap("battle trigger tick", ex.battleTrigger, "tick")
  wrap("contact check", ex.battleTrigger, "checkContact")
  -- the whole draw / logic wraps (engine work included), from outside the mod's wraps
  local a = GEN == 1 and { draw = { "src.world.OverworldController", "drawWorld" }, tick = { "src.world.OverworldController", "update" } }
    or { draw = { "src.world.gen2.World", "drawPeople" }, tick = { "src.world.gen2.World", "step" } }
  for key, t in pairs(a) do
    local M = require(t[1])
    wrap("ENGINE " .. key .. " (with mod)", M, t[2])
  end

  -- VWOG_PERF_DEEP=1: every EnginePatch function and every class method of the field objects
  -- too (inclusive: a caller's figure contains its callees')
  local deep = os.getenv("VWOG_PERF_DEEP") == "1"
  if deep then
    local seen = {}
    local function wrapAll(prefix, t)
      if type(t) ~= "table" or seen[t] then return end
      seen[t] = true
      local names = {}
      for k, v in pairs(t) do if type(k) == "string" and type(v) == "function" then names[#names + 1] = k end end
      for _, k in ipairs(names) do
        if not stats[prefix .. k] then wrap(prefix .. k, t, k) end
      end
    end
    wrapAll("EP.", EP)
    for label, obj in pairs({ sm = sm, fa = fa, bt = ex.battleTrigger, talk = ex.followerInteraction,
        companion = ex.companion, emote = ex.partnerEmote }) do
      local mt = getmetatable(obj)
      wrapAll(label .. ":", mt and mt.__index)
    end
  end

  local function walk(frames)
    local dirs, t = { "left", "right", "up", "down" }, 0
    while t < frames do
      for _, dir in ipairs(dirs) do
        for _ = 1, 40 do
          table.insert(game.input.pressQueue, dir)
          game.input.state[dir] = true
          coroutine.yield()
          t = t + 1
        end
        game.input.state[dir] = false
        U.wait(4)
        t = t + 4
      end
    end
    return t
  end

  -- no contact battles while measuring (the walk bumps into them): the field keeps ticking
  local bt = ex.battleTrigger
  local origStepped, origContact, origBump = bt.onPlayerStepped, bt.onChaserContact, bt.onPlayerBumped
  bt.onPlayerStepped, bt.onChaserContact, bt.onPlayerBumped = function() end, function() end, function() end
  local sawBattle = false
  local origBattle = EP.battleActive
  collectgarbage("collect")
  collectgarbage("stop")
  measuring = true
  local k0, t0 = collectgarbage("count"), love.timer.getTime()
  local frames = walk(FRAMES)
  local totalKb, totalS = collectgarbage("count") - k0, love.timer.getTime() - t0
  measuring = false
  collectgarbage("restart")
  sawBattle = origBattle()
  bt.onPlayerStepped, bt.onChaserContact, bt.onPlayerBumped = origStepped, origContact, origBump

  say(string.format("%s: %d frames, %d wild Pokemon, partner out %s, battle during the walk %s", VERSION,
    frames, sm:count(), tostring(EP.followerCurrent() ~= nil), tostring(sawBattle)))
  say(string.format("ALL (engine + mod): %.2f KB/frame, %.3f ms/frame", totalKb / frames, totalS * 1000 / frames))
  local modKb, modMs = 0, 0
  if deep then
    table.sort(order, function(x, y) return stats[x].kb > stats[y].kb end)
    for i = 31, #order do order[i] = nil end
  end
  for _, label in ipairs(order) do
    local s = stats[label]
    say(string.format("  %-26s %7.3f KB/frame %7.4f ms/frame  (%d calls)", label, s.kb / frames, s.ms / frames, s.calls))
    if not deep and not label:find("^ENGINE") then modKb, modMs = modKb + s.kb, modMs + s.ms end
  end
  say(string.format("  %-26s %7.3f KB/frame %7.4f ms/frame", "mod hooks total", modKb / frames, modMs / frames))

  -- ---- ticks a frame: the spawn tick runs once per mod tick
  local calls = 0
  local origTick = sm.tick
  sm.tick = function(...) calls = calls + 1 return origTick(...) end
  local function ticksPerFrame(n)
    local most, total = 0, 0
    for _ = 1, n do
      calls = 0
      coroutine.yield()
      most = math.max(most, calls)
      total = total + calls
    end
    return most, total / n
  end
  local m1, avg1 = ticksPerFrame(60)
  say(string.format("ticks a frame on the field: max %d, avg %.2f", m1, avg1))
  EP.showMessage("A test box for the tick count.", { stay = true })
  U.wait(10)
  local m2, avg2 = ticksPerFrame(60)
  say(string.format("ticks a frame with a dialogue box: max %d, avg %.2f (box open %s)", m2, avg2, tostring(EP.isMessageOpen())))
  for _ = 1, 6 do U.tap(game, "a") U.wait(10) end
  U.wait(30)
  -- a battle: any wild Pokemon's own, started the way a contact starts it
  local target
  for _, e in pairs(sm.entities or {}) do target = target or e end
  if target then pcall(ex.battleTrigger.onChaserContact, ex.battleTrigger, target) end
  U.wait(240)
  local m3, avg3 = ticksPerFrame(120)
  say(string.format("ticks a frame in a battle: max %d, avg %.2f (battle %s)", m3, avg3, tostring(EP.battleActive())))
  sm.tick = origTick
  love.event.quit(0)
end
