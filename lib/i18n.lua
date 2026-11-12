-- This mod's own text, English only. The call sites keep the interface a translated build
-- would use (I18n.t("Found %s!", name), I18n.tc("party", "FIGHT"), I18n.list(...)), so a
-- language could be added later without touching them; today every call fills the English.
local V = ...

local I18n = {}

I18n.LANGUAGES = { "en" }
I18n.NAMES = { en = "ENGLISH" }
I18n.FONT_FALLBACK = {}

function I18n.setLanguage(_code) end
function I18n.language() return "en" end

local function fill(fmt, ...)
  if select("#", ...) == 0 then return fmt end
  return string.format(fmt, ...)
end

--- `english`, filled with the arguments.
function I18n.t(english, ...) return fill(english, ...) end

--- The format for `english` (unfilled): the English itself.
function I18n.format(english) return english end

--- I18n.t with a context (kept for the call sites; the context changes nothing in English).
function I18n.tc(_context, english, ...) return fill(english, ...) end

--- A list of English lines (call-out lists, dialogue pools): the list itself.
function I18n.list(_key, list) return list end

--- `s` in capitals; POKéMON keeps its small é, as the games write it.
function I18n.upper(s)
  return (tostring(s or ""):upper():gsub("POKÉMON", "POKéMON"))
end

function I18n._reset() end

return I18n
