-- The partner going into or coming out of its Poke Ball on purpose (the party switch, the
-- Follower option, a Battler resting): a ball drops behind the player.
--
--   out  the ball falls onto the partner's spot, bounces once and opens; it pops (the Ball
--        Poof sound, a white ring), the Pokemon grows out of it, and the open ball fades
--   in   the ball falls at the Pokemon's feet, bounces once and opens; it pops, the Pokemon
--        shrinks into it, the ball closes, rests a moment and fades
--   swap "out" for a change of partner (lib/follower_swap.lua): the old one stands while the
--        ball falls and opens (recall 1), is gone in the pop, and the new one grows out
--
-- Pure: a tick-driven timeline (Config.BALL). lib/follower_adapter.lua copies each tick's
-- state onto the renderer (`recall`: 0 inside .. 1 out, scaled about its feet, which is where
-- the ball lands) and draws the ball (lib/follower_actions.lua ballActor).
--
--   local run = BallDrop.new("out")
--   local s = run:step()  -- once per tick; nil when it is over
--
-- `s` (one table per run, refilled every tick: read it, never keep it) = {
--   recall  the Pokemon's size, 0 = inside .. 1 = out
--   ball    { x, y, z, alpha, burst, open }: px from the centre of the partner's tile (y 8 =
--           its feet), the height above the ground, 0..1 opacity, the pop ring's 0..1 age
--           (nil: no ring), and how far its lid is open (0 shut .. 1 open)
--   poof    true on the tick the ball pops (play the sound)
-- }
local V = ...
local Config = V.require("config")
local RecallMath = V.require("recall_math")

local BallDrop = {}
BallDrop.__index = BallDrop

local function cfgOf(cfg) return cfg or Config.BALL end

--- How many ticks a run lasts.
function BallDrop.length(dir, cfg)
  local c = cfgOf(cfg)
  if dir == "in" then return c.fallIn + c.bounce + c.open + c.shrink + c.close + c.rest + c.fade end
  return c.fall + c.bounce + c.open + c.grow + c.fade -- "out" and "swap"
end

--- The tick the ball pops (the sound; for "out", the Pokemon's first frame out).
function BallDrop.popAt(dir, cfg)
  local c = cfgOf(cfg)
  if dir == "in" then return c.fallIn + c.bounce + c.open + 1 end
  return c.fall + c.bounce + c.open + 1
end

function BallDrop.new(dir, cfg)
  if dir ~= "in" and dir ~= "swap" then dir = "out" end
  local self = setmetatable({ dir = dir, cfg = cfgOf(cfg), t = 0 }, BallDrop)
  self.len = BallDrop.length(self.dir, self.cfg)
  self.ball = { x = 0, y = 8, z = 0, alpha = 1, burst = nil, open = 0 }
  self.state = { recall = self.dir == "out" and 0 or 1, ball = self.ball, poof = false }
  return self
end

function BallDrop:isFinished() return self.t >= self.len end

-- the pop ring's age at `since` ticks after the pop (1 = the pop tick), nil once it is gone
local function burstAt(c, since)
  local age = (since - 1) / math.max(1, c.burst)
  return age < 1 and age or nil
end

-- the ball's height `t` ticks into its drop: falling faster and faster from `from`, then one
-- small bounce; nil once it has settled
local function dropZ(c, t, fall, from)
  if t <= fall then
    local u = t / fall
    return from * (1 - u * u)
  elseif t <= fall + c.bounce then
    return c.bounceH * math.sin(math.pi * (t - fall) / c.bounce)
  end
  return nil
end

function BallDrop:step()
  if self.t >= self.len then return nil end
  self.t = self.t + 1
  local t, c, s, b = self.t, self.cfg, self.state, self.ball
  s.poof, b.alpha, b.burst, b.open = false, 1, nil, 0
  local fall = self.dir == "in" and c.fallIn or c.fall
  local z = dropZ(c, t, fall, self.dir == "in" and c.dropZIn or c.dropZ)
  b.z = z or 0
  if z then
    s.recall = self.dir == "out" and 0 or 1
    return s
  end
  local k = t - fall - c.bounce -- ticks since it settled
  if k <= c.open then
    -- the lid swings open; nothing has come out or gone in yet
    b.open = RecallMath.ease(k / c.open)
    s.recall = self.dir == "out" and 0 or 1
    return s
  end
  local g = k - c.open -- ticks since the pop (1 = the pop)
  b.burst = burstAt(c, g)
  s.poof = g == 1
  if self.dir ~= "in" then
    b.open = 1
    if g <= c.grow then
      s.recall = RecallMath.ease(g / c.grow)
    else
      s.recall = 1
      b.alpha = 1 - (g - c.grow) / c.fade
    end
    return s
  end
  if g <= c.shrink then
    b.open = 1
    s.recall = 1 - RecallMath.ease(g / c.shrink)
    return s
  end
  s.recall = 0
  local h = g - c.shrink -- ticks since it went in
  if h <= c.close then
    b.open = 1 - RecallMath.ease(h / c.close)
  else
    local f = h - c.close - c.rest
    if f > 0 then b.alpha = 1 - f / c.fade end
  end
  return s
end

return BallDrop
