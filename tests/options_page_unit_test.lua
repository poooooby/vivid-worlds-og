-- Run: lua tests/options_page_unit_test.lua
-- The VIVID WORLDS page on the game's OPTION screen (lib/options_page.lua): its rows follow
-- options.lua, step through the setter, and the entry is added once.
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

-- a stand-in engine layer: records what the page asks of it
local pushed, stored = {}, {}
local modules = {
  engine_patch = {
    setModOption = function(game, modId, key, value)
      stored[#stored + 1] = { game = game, mod = modId, key = key, value = value }
      return true
    end,
    openOptionsPage = function(game, rows)
      pushed[#pushed + 1] = { game = game, rows = rows }
      return true
    end,
  },
}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end
local OptionsPage = V.require("options_page")
local schema = assert(loadfile("options.lua"))()

-- a mod whose options read from a table, as mod.options:get does
local values = {}
local mod = { id = "vivid_worlds_og", options = { get = function(_, key) return values[key] end } }
local game = { mods = { optionSchemas = { vivid_worlds_og = schema } } }

-- ---- the rows follow options.lua
local rows = OptionsPage.rows(mod, game)
eq(#rows, #schema, "one row per option")
for i, row in ipairs(rows) do
  eq(row.id, "vwog_" .. schema[i].key, "row " .. i .. " is " .. schema[i].key)
  eq(row.label, schema[i].label:upper(), "...labelled in capitals")
end
eq(#OptionsPage.rows(mod, { mods = {} }), 0, "no schema registered: no rows")

local function rowOf(key)
  for _, row in ipairs(rows) do if row.id == "vwog_" .. key then return row end end
end

-- ---- a toggle shows its default, and a step flips it through the setter
local follower = rowOf("show_follower")
eq(follower.value(game), "ON", "Follower shows its default (ON)")
check(follower.step(game, 1) == true, "a step reports a change")
eq(#stored, 1, "...stored once")
eq(stored[1].mod, "vivid_worlds_og", "...for this mod")
eq(stored[1].key, "show_follower", "...under its key")
eq(stored[1].value, false, "...turned off")
eq(stored[1].game, game, "...with the game handed in")
values.show_follower = false
eq(follower.value(game), "OFF", "a stored OFF shows")

-- ---- a choice cycles both ways and wraps
local amount = rowOf("spawn_amount")
eq(amount.value(game), "NORMAL", "Spawn Amount shows its default")
amount.step(game, 1)
eq(stored[#stored].value, "high", "right: the next choice")
amount.step(game, -1)
eq(stored[#stored].value, "low", "left: the one before")
values.spawn_amount = "high"
eq(amount.value(game), "HIGH", "a stored choice shows")
amount.step(game, 1)
eq(stored[#stored].value, "low", "right past the last wraps to the first")
values.spawn_amount = "nonsense"
eq(amount.value(game), "NORMAL", "an unknown stored value shows the default")

-- ---- the entry on the top page
local top = { { id = "mods", label = "MODS" } }
local out = OptionsPage.addEntry(mod, top, 1)
eq(#out, 2, "the entry is added")
eq(out[2].label, "VIVID WORLDS", "...labelled VIVID WORLDS")
eq(out[2].value(game), #schema .. " OPTIONS", "...with a count on Gen 1, like the game's groups")
OptionsPage.addEntry(mod, out, 1)
eq(#out, 2, "...and only once")
out[2].activate(game)
eq(#pushed, 1, "A on it opens the page")
eq(#pushed[1].rows, #schema, "...with every option on it")
local gen2 = OptionsPage.addEntry(mod, { { id = "frame" }, { id = "cancel", cancel = true } }, 2)
eq(gen2[2].id, "vwog_page", "Gen 2: the entry goes above BACK")
eq(gen2[3].id, "cancel", "...which stays last")
eq(gen2[2].value, nil, "...with no value line (its groups have none)")
eq(OptionsPage.addEntry(mod, nil, 1), nil, "a broken row list is handed back untouched")

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("all passed")
