-- Run: lua tests/emote_art_unit_test.lua
-- lib/emote_art.lua: the partner's mood in the game's own emote bubbles, the drawn effect for a
-- mood the game has no bubble for.
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then failures = failures + 1 io.stderr:write("FAIL: " .. tostring(msg) .. "\n") else print("ok  " .. tostring(msg)) end
end
local function eq(a, b, msg)
  check(a == b, string.format("%s (got %s expected %s)", msg, tostring(a), tostring(b)))
end

-- the game's bubbles: Red / Blue have "!", "?" and the smile only
local have = { exclaim = true, question = true, happy = true }
local IMAGE = { img = true }
local fakeEngine = {
  emoteBubble = function(name) if have[name] then return IMAGE, { quad = name } end return nil end,
}
local modules = { engine_patch = fakeEngine }
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  modules[name] = assert(loadfile("lib/" .. name .. ".lua"))(V)
  return modules[name]
end
local EmoteArt = V.require("emote_art")

-- every mood the drawn kit has either maps to a bubble or is left to the kit
local MoodFx = V.require("mood_fx")
for kind in pairs(EmoteArt.BUBBLE_FOR) do
  check(#MoodFx.particles(kind, 30) > 0, "'" .. kind .. "' is a mood kind lib/mood_fx.lua knows")
end

eq(EmoteArt.bubbleFor("notes"), "happy", "Red / Blue: a happy partner shows the game's smile bubble")
eq(EmoteArt.bubbleFor("exclaim"), "exclaim", "...a surprised one the \"!\"")
eq(EmoteArt.bubbleFor("hearts"), nil, "...no heart bubble in Red / Blue: the drawn hearts")
eq(EmoteArt.bubbleFor("anger"), nil, "no game has an anger bubble: the drawn anger mark")
eq(EmoteArt.bubbleFor(nil), nil, "no mood, no bubble")
have = { exclaim = true, question = true, happy = true, sad = true, heart = true, bolt = true, sleep = true, fish = true, skull = true }
eq(EmoteArt.bubbleFor("hearts"), "heart", "Yellow / Gold: the heart bubble")
eq(EmoteArt.bubbleFor("love"), "heart", "...for love too")
eq(EmoteArt.bubbleFor("rain"), "sad", "a sad partner: the sad bubble")
eq(EmoteArt.bubbleFor("zzz"), "sleep", "an asleep one: the Zs")
eq(EmoteArt.bubbleFor("sparks"), "bolt", "a paralysed one: the bolt")
eq(EmoteArt.bubbleFor("bubbles"), "skull", "a poisoned one: Yellow's skull")
fakeEngine.emoteBubble = nil
eq(EmoteArt.bubbleFor("hearts"), nil, "an engine layer without bubbles: the drawn kit")
fakeEngine.emoteBubble = function(name) if have[name] then return IMAGE, { quad = name } end return nil end

-- drawing: the bubble's bottom on the head top, centred, popping up then holding
local drawn
love = { graphics = {
  getColor = function() return 1, 1, 1, 1 end,
  setColor = function() end,
  draw = function(img, quad, x, y) drawn = { img = img, quad = quad, x = x, y = y } end,
} }
local a = EmoteArt.actor("heart", 0, 100, 50, 60)
eq(a.sortY, 60, "the actor sorts where it is told (in front of the partner)")
a:draw(0, 0)
check(drawn and drawn.img == IMAGE and drawn.quad.quad == "heart", "it draws the game's heart bubble")
eq(drawn and drawn.x, 92, "...centred on the head")
eq(drawn and drawn.y, 38, "...starting 4 px low (popping up)")
EmoteArt.actor("heart", 10, 100, 50, 60):draw(10, 20)
eq(drawn and drawn.y, 50 - 16 - 20, "...then sitting on the head top (camera applied)")
eq(drawn and drawn.x, 92 - 10, "...camera x applied")
have = {}
drawn = nil
EmoteArt.actor("heart", 10, 100, 50, 60):draw(0, 0)
eq(drawn, nil, "a bubble the game lost draws nothing (never an error)")
love = nil

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("emote_art_unit_test: all passed")
