-- Run: lua tests/ball_drop_unit_test.lua
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
local BallDrop = V.require("ball_drop")
local C = V.require("config").BALL

-- every tick's state, copied (the run refills one table)
local function run(dir)
  local r, out = BallDrop.new(dir), {}
  while true do
    local s = r:step()
    if not s then break end
    local b = s.ball
    out[#out + 1] = { recall = s.recall, poof = s.poof, z = b and b.z, alpha = b and b.alpha, burst = b and b.burst,
                      open = b and b.open }
  end
  check(r:isFinished(), dir .. ": the run reports finished")
  check(r:step() == nil, dir .. ": nothing after the end")
  return out
end

-- ------- out: falls, bounces, opens, pops, it grows out, then the open ball fades
do
  local st = run("out")
  eq(#st, BallDrop.length("out"), "out: lasts its length")
  check(#st <= 45, "out: quick (under 3/4 of a second at 60 ticks/s)")
  local pop = BallDrop.popAt("out")
  local landed = C.fall + C.bounce
  local poofs, poofAt = 0, nil
  for i, s in ipairs(st) do if s.poof then poofs, poofAt = poofs + 1, i end end
  eq(poofs, 1, "out: one Ball Poof")
  eq(poofAt, pop, "...on the pop tick")
  for i = 1, pop - 1 do
    if st[i].recall ~= 0 then check(false, "out: still inside before the pop (tick " .. i .. ")") end
  end
  check(st[1].z > st[C.fall - 1].z, "out: the ball falls")
  check(st[1].z <= C.dropZ, "...from at most its drop height")
  eq(st[C.fall].z, 0, "out: it lands on the ground")
  local peak = 0
  for i = C.fall + 1, landed do peak = math.max(peak, st[i].z) end
  check(peak > 0 and peak <= C.bounceH, "out: one small bounce")
  for i = 1, landed do
    if st[i].open ~= 0 then check(false, "out: shut while it falls and bounces (tick " .. i .. ")") end
  end
  check(st[landed + 1].open > 0 and st[landed + 1].open < 1, "out: it opens once it has landed")
  eq(st[pop - 1].open, 1, "...all the way before the pop")
  check(st[pop].recall > 0 and st[pop].recall < 1, "out: it starts growing on the pop")
  check(st[pop].burst ~= nil, "...with the pop ring")
  for i = pop + 1, #st do
    if st[i].recall < st[i - 1].recall then check(false, "out: it only grows (tick " .. i .. ")") end
  end
  local grown = pop + C.grow - 1
  eq(st[grown].recall, 1, "out: fully out after the grow")
  eq(st[grown].alpha, 1, "...the ball still there")
  for i = pop, #st do
    if st[i].open ~= 1 then check(false, "out: the ball stays open (tick " .. i .. ")") end
  end
  check(st[grown + 1].alpha < 1, "out: then the ball fades")
  eq(st[#st].alpha, 0, "...away")
end

-- ------- in: drops at its feet, opens, it shrinks in, the ball closes, rests and fades
do
  local st = run("in")
  eq(#st, BallDrop.length("in"), "in: lasts its length")
  check(#st <= 50, "in: quick (under a second at 60 ticks/s)")
  local pop = BallDrop.popAt("in")
  local landed = C.fallIn + C.bounce
  local poofs, poofAt = 0, nil
  for i, s in ipairs(st) do if s.poof then poofs, poofAt = poofs + 1, i end end
  eq(poofs, 1, "in: one Ball Poof")
  eq(poofAt, pop, "...once the ball is open")
  for i = 1, pop - 1 do
    if st[i].recall ~= 1 then check(false, "in: fully out until the pop (tick " .. i .. ")") end
  end
  check(st[1].z > st[C.fallIn - 1].z, "in: the ball falls")
  eq(st[C.fallIn].z, 0, "...to the ground at its feet")
  for i = 1, landed do
    if st[i].open ~= 0 then check(false, "in: shut while it falls (tick " .. i .. ")") end
  end
  eq(st[pop - 1].open, 1, "in: it opens before the pop")
  check(st[pop].recall < 1 and st[pop].burst ~= nil, "in: it starts shrinking on the pop, with the ring")
  local inside = pop + C.shrink - 1
  eq(st[inside].recall, 0, "in: fully inside once the shrink is done")
  eq(st[inside].open, 1, "...the ball still open")
  check(st[inside + 1].open < 1, "in: then it closes")
  local shut = inside + C.close
  eq(st[shut].open, 0, "...all the way")
  eq(st[shut].alpha, 1, "...and is still there")
  eq(st[shut + C.rest].alpha, 1, "in: the ball rests a moment")
  eq(st[#st].alpha, 0, "in: then it fades away")
  for i = landed + 1, #st do
    if st[i].z ~= 0 then check(false, "in: the ball stays on the ground (tick " .. i .. ")") end
  end
end

-- ------- swap: one ball for a change of partner, the old one standing until the pop
do
  local st, out = run("swap"), run("out")
  eq(#st, #out, "swap: as long as out")
  local pop = BallDrop.popAt("out")
  for i = 1, pop - 1 do
    if st[i].recall ~= 1 then check(false, "swap: the old one stands before the pop (tick " .. i .. ")") end
  end
  check(st[pop].poof, "swap: pops on out's tick")
  for i = pop, #st do
    if st[i].recall ~= out[i].recall or st[i].z ~= out[i].z or st[i].open ~= out[i].open then check(false, "swap: grows out like out (tick " .. i .. ")") end
  end
  eq(st[#st].recall, 1, "swap: ends fully out")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("all ball_drop tests passed")
