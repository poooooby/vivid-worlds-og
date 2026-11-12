-- The partner's face while you talk to it, without a portrait: the mood that picks the
-- emote over its head (lib/follower_interaction.lua moodKind -> lib/mood_fx.lua), plus
-- the message itself. Same interface the interaction used to call on a portrait box:
--
--   partnerEmote:say("Hello!", { mon = mon, emotion = "Happy", stay = false, done = fn })
--   partnerEmote.emotion       -- the current mood (MonMood's emotion names)
--   partnerEmote:clear()
--
-- The emote clears when the message closes (unless `stay` keeps the box up for a menu).
local V = ...
local EnginePatch = V.require("engine_patch")
local MonMood = V.require("mon_mood")

local PartnerEmote = {}
PartnerEmote.__index = PartnerEmote

function PartnerEmote.new(mod)
  return setmetatable({ mod = mod, active = false, emotion = "Normal" }, PartnerEmote)
end

function PartnerEmote:setEmotion(emotion)
  self.emotion = emotion or "Normal"
end

--- Re-derive the mood from the same mon after its state changed (e.g. friendship went up).
function PartnerEmote:refreshMon(mon)
  if self.active and type(mon) == "table" then self:setEmotion(MonMood.emotionFor(mon)) end
end

function PartnerEmote:clear()
  self.active = false
end

function PartnerEmote:isActive()
  return self.active
end

--- Opens a message with the partner's mood up. opts: `mon` (its mood is derived from its
--- state), `emotion` (overrides it), `stay` (keep the box up, e.g. for a menu under it),
--- `done` (called when the message closes). Returns true when the message was shown.
function PartnerEmote:say(text, opts)
  opts = opts or {}
  if opts.emotion then
    self:setEmotion(opts.emotion)
  elseif type(opts.mon) == "table" then
    self:setEmotion(MonMood.emotionFor(opts.mon))
  end
  self.active = true
  local userDone = opts.done
  local shown = EnginePatch.showMessage(text, {
    stay = opts.stay,
    done = function(...)
      if not opts.stay then self:clear() end
      if userDone then return userDone(...) end
    end,
  })
  if not shown then self:clear() end
  return shown
end

return PartnerEmote
