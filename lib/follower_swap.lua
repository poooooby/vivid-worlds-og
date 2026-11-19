-- The "trainer swaps Pokemon" scene: when the companion changes, the player raises their
-- arm and a Poke Ball drops (lib/ball_drop.lua).
--
--   change phase  another Pokemon for the one out (the party menu): arm up once; after
--                 `sendDelay` ticks one ball drops at the old one's feet and pops, the old
--                 one gone in the pop and the new one growing out of it (and crying)
--   recall phase  only a recall: arm up; after `recallDelay` ticks the ball takes it in
--   send phase    only a send-out (nothing was out): arm up; after `sendDelay` ticks a
--                 ball drops, and the new one pops out of it (and cries as it does)
--
-- recall / send run their ball when `want` flips; change asks for its "swap" run with `drop`.
--
-- Pure: a tick-driven timeline. The adapter (lib/follower_adapter.lua) mirrors
-- each tick's state onto the player pose, the ball actor and the renderer.
--
--   local swap = FollowerSwap.new({ hasOld = true, hasNew = true })
--   local s = swap:step()   -- once per tick; nil when the scene is over
--
-- `s` = {
--   phase   "change" | "recall" | "send"
--   pose    true on the first tick of a phase: raise the player's arm now
--   want    1 = the displayed companion should be out, 0 = inside the player
--   drop    change only: true on the tick its one ball starts falling (BallDrop "swap")
--   switch  true on the tick the displayed companion becomes the new one
--   cry     true on the tick the new companion appears
-- }
local V = ...
local Config = V.require("config")
local BallDrop = V.require("ball_drop")

local FollowerSwap = {}
FollowerSwap.__index = FollowerSwap

function FollowerSwap.new(ctx)
  ctx = ctx or {}
  local cfg = ctx.cfg or Config.SWAP
  local self = setmetatable({ cfg = cfg, t = 0, finished = false, phases = {} }, FollowerSwap)
  local len = math.max(cfg.poseTicks, cfg.recallDelay + BallDrop.length("in") + 2)
  local lenIn = math.max(cfg.poseTicks, cfg.sendDelay + BallDrop.length("out") + 2)
  if ctx.hasOld and ctx.hasNew then
    self.phases[1] = { name = "change", len = lenIn } -- one ball, popping the new one out
  elseif ctx.hasOld then
    self.phases[1] = { name = "recall", len = len }
  elseif ctx.hasNew then
    self.phases[1] = { name = "send", len = lenIn }
  end
  self.index, self.phaseT = 1, 0
  if #self.phases == 0 then self.finished = true end
  return self
end

function FollowerSwap:isFinished()
  return self.finished
end

--- True when the new companion grows out in this run (a send or a change).
function FollowerSwap:hasSend()
  for _, p in ipairs(self.phases) do
    if p.name == "send" or p.name == "change" then return true end
  end
  return false
end

function FollowerSwap:step()
  if self.finished then return nil end
  self.t = self.t + 1
  if self.t > self.cfg.maxTicks then
    self.finished = true
    return nil
  end
  local phase = self.phases[self.index]
  if self.phaseT >= phase.len then
    self.index, self.phaseT = self.index + 1, 0
    phase = self.phases[self.index]
    if not phase then
      self.finished = true
      return nil
    end
  end
  local first = self.phaseT == 0
  self.phaseT = self.phaseT + 1
  local pt = self.phaseT
  local state = { phase = phase.name, pose = first }
  local popAt = self.cfg.sendDelay + BallDrop.popAt("out")
  if phase.name == "change" then
    -- the old one stands until the ball pops; the new one then grows out of it
    state.want = 1
    state.drop = pt == self.cfg.sendDelay + 1
    state.switch = pt == popAt
    state.cry = state.switch
  elseif phase.name == "recall" then
    state.want = pt <= self.cfg.recallDelay and 1 or 0
  else
    state.want = pt <= self.cfg.sendDelay and 0 or 1
    state.switch = first
    -- the ball's run starts the tick `want` turns 1; the new one cries as it pops out
    state.cry = pt == popAt
  end
  return state
end

return FollowerSwap
