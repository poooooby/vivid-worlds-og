-- The partner's mood over its head in the game's own emote bubbles: Red / Blue's smile, Yellow's
-- eight emotion bubbles (the ones Pikachu shows), Gold / Silver / Crystal's showemote set
-- (EnginePatch.emoteBubble). A mood whose bubble the game doesn't have keeps lib/mood_fx.lua's
-- drawn effect (anger marks, sweat, flames, snow ...).
--
-- The bubble sits on top of the head the way World:drawEmote / the Gen 1 emote place one over an
-- NPC, a plain field actor like lib/mood_fx.lua's.
local V = ...
local EnginePatch = V.require("engine_patch")

local EmoteArt = {}

-- mood_fx kind -> the bubble that says it (lib/mood_fx.lua MoodFx.kindFor)
EmoteArt.BUBBLE_FOR = {
  love = "heart", hearts = "heart", notes = "happy", sparkles = "happy", exclaim = "exclaim",
  rain = "sad", tears = "sad", zzz = "sleep", sparks = "bolt", bubbles = "skull",
}

--- The bubble name for mood `kind` when this game has that bubble, else nil.
function EmoteArt.bubbleFor(kind)
  local name = kind and EmoteArt.BUBBLE_FOR[kind]
  if not (name and EnginePatch.emoteBubble) then return nil end
  local image = EnginePatch.emoteBubble(name)
  return image and name or nil
end

--- The bubble as one field actor: its bottom edge on the head top at world (x, y), centred,
--- sorted at `sortY`; it pops up in its first few ticks and then holds, bobbing a pixel.
function EmoteArt.actor(name, age, x, y, sortY)
  age = math.max(0, math.floor(tonumber(age) or 0))
  return {
    kind = "ow_mood_fx", elevation = 3, oamPriority = 1, sortY = sortY, x = x, y = y,
    i = 99600,
    draw = function(_, camX, camY)
      if not (love and love.graphics and love.graphics.draw) then return end
      local image, quad = EnginePatch.emoteBubble(name)
      if not image then return end
      local rise = math.max(0, 4 - age) -- a 4-pixel pop up from the head
      local bob = (age % 40 < 20) and 0 or -1
      local g = love.graphics
      local r, gg, b, a = g.getColor()
      g.setColor(1, 1, 1, 1)
      g.draw(image, quad, math.floor(x - 8 - camX), math.floor(y - 16 + rise + bob - camY))
      g.setColor(r, gg, b, a)
    end,
  }
end

return EmoteArt
