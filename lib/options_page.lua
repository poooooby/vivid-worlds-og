-- VIVID WORLDS in the game's own OPTION menu: one entry on its top page that opens a page
-- of this mod's options, so they can be changed while playing without going through the
-- Mods menu. (Ported from Wilds of Hoenn's Gen 3 page.)
--
-- The rows are the schema options.lua registered (game.mods.optionSchemas), in the same
-- order. A change goes through EnginePatch.setModOption -- the Mod Manager's own setter --
-- so it is stored, persisted and announced (`mod.options_changed`) exactly like a Mod
-- Manager change, and everything reacts the same. The entry is added through the public
-- `ui.options.rows` hook (main.lua); EnginePatch.openOptionsPage pushes the page on the
-- running generation's OPTION screen.
local V = ...
local EnginePatch = V.require("engine_patch")

local OptionsPage = {}

OptionsPage.TITLE = "VIVID WORLDS"
OptionsPage.ENTRY_ID = "vwog_page"

local function schemaOf(mod, game)
  local loader = type(game) == "table" and game.mods
  local s = type(loader) == "table" and loader.optionSchemas and loader.optionSchemas[mod.id]
  return type(s) == "table" and s or nil
end

local function current(mod, row)
  local v = mod.options and mod.options:get(row.key)
  if v == nil then v = row.default end
  return v
end

local function choiceIndex(row, value)
  for i, c in ipairs(row.choices) do
    if c[2] == value then return i end
  end
  return nil
end

--- One page row for a schema row (toggle / choice), or nil for a kind this page cannot
--- show (Mods menu only). `set(game, key, value)` stores a change.
function OptionsPage.rowFor(mod, row, set)
  local label = tostring(row.label or row.key):upper()
  local id = "vwog_" .. row.key
  if row.type == "toggle" then
    return {
      id = id, label = label,
      value = function() return current(mod, row) == true and "ON" or "OFF" end,
      step = function(game)
        set(game, row.key, current(mod, row) ~= true)
        return true
      end,
    }
  end
  if row.type == "choice" and type(row.choices) == "table" and #row.choices > 0 then
    return {
      id = id, label = label,
      value = function()
        local i = choiceIndex(row, current(mod, row)) or choiceIndex(row, row.default) or 1
        return tostring(row.choices[i][1])
      end,
      step = function(game, dir)
        local n = #row.choices
        local i = choiceIndex(row, current(mod, row)) or choiceIndex(row, row.default) or 1
        i = ((i - 1 + ((dir and dir < 0) and -1 or 1)) % n) + 1
        set(game, row.key, row.choices[i][2])
        return true
      end,
    }
  end
  return nil
end

--- The page's rows for `game`.
function OptionsPage.rows(mod, game, set)
  set = set or function(g, key, value) return EnginePatch.setModOption(g, mod.id, key, value) end
  local out = {}
  for _, row in ipairs(schemaOf(mod, game) or {}) do
    if type(row) == "table" and type(row.key) == "string" then
      local r = OptionsPage.rowFor(mod, row, set)
      if r then out[#out + 1] = r end
    end
  end
  return out
end

--- The entry on the top OPTION page: opens the page. Gen 1 shows a value line like the
--- game's own groups ("12 OPTIONS"); Gen 2's groups have none, so neither does this one.
function OptionsPage.entry(mod, generation)
  local entry = {
    id = OptionsPage.ENTRY_ID, label = OptionsPage.TITLE,
    activate = function(game)
      local rows = OptionsPage.rows(mod, game)
      if #rows > 0 then EnginePatch.openOptionsPage(game, rows) end
    end,
  }
  if generation ~= 2 then
    entry.value = function(game) return #OptionsPage.rows(mod, game) .. " OPTIONS" end
  end
  return entry
end

--- The `ui.options.rows` hook body: the engine's rows with the entry added (once), last
--- but above BACK (Gold's BACK is a row of the list the hook gets; Red's comes after it).
function OptionsPage.addEntry(mod, rows, generation)
  if type(rows) ~= "table" then return rows end
  local at = #rows + 1
  for i, row in ipairs(rows) do
    if type(row) == "table" and row.id == OptionsPage.ENTRY_ID then return rows end
    if type(row) == "table" and row.cancel and i < at then at = i end
  end
  table.insert(rows, at, OptionsPage.entry(mod, generation))
  return rows
end

return OptionsPage
