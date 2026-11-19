-- Run: lua tests/follower_swap_unit_test.lua
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

local modules = {}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end
local Swap = V.require("follower_swap")
local Cfg = V.require("config")

local function run(ctx)
  local swap = Swap.new(ctx)
  local states = {}
  while true do
    local s = swap:step()
    if not s then break end
    states[#states + 1] = s
  end
  return states
end

-- ------- a change of partner: one ball drops, the old one goes in its pop, the new one comes out
do
  local BallDrop = V.require("ball_drop")
  local st = run({ hasOld = true, hasNew = true })
  check(#st > 0, "the scene runs")
  local drops, switchAt, cryAt, pose = 0, nil, nil, 0
  for i, s in ipairs(st) do
    check(s.phase == "change", "one phase: " .. i)
    eq(s.want, 1, "never put away first: " .. i)
    if s.drop then drops = drops + 1 end
    if s.switch then switchAt = i end
    if s.cry then cryAt = i end
    if s.pose then pose = pose + 1 end
  end
  check(st[1].pose, "the arm goes up on the first tick")
  eq(pose, 1, "...once")
  eq(drops, 1, "one ball drops")
  check(st[Cfg.SWAP.sendDelay + 1].drop, "...after sendDelay ticks of the arm up")
  eq(switchAt, Cfg.SWAP.sendDelay + BallDrop.popAt("out"), "the new companion takes over as the ball pops")
  eq(cryAt, switchAt, "...and cries as it comes out")
  check(#st - Cfg.SWAP.sendDelay >= BallDrop.length("swap"), "the scene lasts the whole pop-out")
  check(Swap.new({ hasOld = true, hasNew = true }):hasSend(), "hasSend is true for a change")
  check(#st <= Cfg.SWAP.maxTicks, "within the hard cap")
end

-- ------- a recall: only the first phase
do
  local st = run({ hasOld = true, hasNew = false })
  for _, s in ipairs(st) do
    check(s.phase == "recall" and not s.switch, "a recall has no send phase") break
  end
  eq(st[#st].want, 0, "it ends inside the player")
  check(not Swap.new({ hasOld = true, hasNew = false }):hasSend(), "hasSend is false for a recall")
end

-- ------- sending out from a recall: only the second phase
do
  local st = run({ hasOld = false, hasNew = true })
  eq(st[1].phase, "send", "nothing to recall first")
  check(st[1].switch, "the new companion takes over at once")
  eq(st[1].want, 0, "...starting inside the ball")
  eq(st[#st].want, 1, "...and ends out")
end

-- ------- nothing to do
check(Swap.new({}):isFinished(), "no old and no new: finished at once")
check(Swap.new({}):step() == nil, "...and steps to nil")

-- ------- the hard cap ends a runaway scene
do
  local swap = Swap.new({ hasOld = true, hasNew = true, cfg = { poseTicks = 5000, recallDelay = 1, sendDelay = 1, ballLift = 1, ballX = 1, maxTicks = 10 } })
  local n = 0
  while swap:step() do n = n + 1 end
  eq(n, 10, "a scene stops at maxTicks")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("follower_swap_unit_test: all passed")
