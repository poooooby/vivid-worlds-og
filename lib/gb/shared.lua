-- What the two Game Boy adapters (lib/gb/gen1.lua, lib/gb/gen2.lua) share for the partner's
-- Battler and Forager: move ids interned to numbers, the item use kinds the Forager weighs, and
-- the bag (src/inventory/Bag, one module on Red and on Gold: Gen 1's single bag, Gen 2's four
-- pockets).
local Shared = {}

-- ------------------------------------------------------------------ moves
-- Move ids are STRINGS on both ("TACKLE"); the combat code compares ids numerically
-- (`id > 0`), so each key is interned to a stable number for the session and translated
-- back at the data lookups.
local moveNums, moveKeys = {}, {}
function Shared.moveNumber(m)
  if type(m) == "table" then m = m.id or m.move or m.moveId end
  if type(m) == "number" then return m end
  if type(m) ~= "string" then return nil end
  local n = moveNums[m]
  if not n then
    n = #moveKeys + 1
    moveKeys[n] = m
    moveNums[m] = n
  end
  return n
end

function Shared.moveKey(id)
  if type(id) == "string" then return id end
  return moveKeys[tonumber(id) or 0]
end

function Shared.knowsMove(mon, moveId)
  local key = Shared.moveKey(moveId)
  if not key then return false end
  for _, mv in ipairs(type(mon) == "table" and mon.moves or {}) do
    if type(mv) == "table" and mv.id == key then return true end
  end
  return false
end

-- ------------------------------------------------------------------ text
-- The engine font (src/render/Font.lua, the same module on Red and on Gold) for the mod's
-- little labels. Neither Game Boy font has a "+" (the "+5 EXP" label): it takes one 8 px
-- glyph cell and is drawn as a small cross in the text colour.
local CELL = 8

local function plain(text) return (tostring(text or ""):gsub("%+", " ")) end

function Shared.measureText(Font, text)
  if not (Font and Font.width) then return 0 end
  local ok, w = pcall(Font.width, plain(text))
  return ok and tonumber(w) or 0
end

--- Draws `text` at (x, y), top-left, in the engine menus' dark text colour; returns its width.
function Shared.drawText(Font, text, x, y)
  local g = love and love.graphics
  if not (Font and Font.draw and g) then return 0 end
  text = tostring(text or "")
  local r, gr, b, a = g.getColor()
  g.setColor(0, 0, 0, 1)
  pcall(Font.draw, plain(text), x, y)
  local from = 1
  while true do
    local at = text:find("+", from, true)
    if not at then break end
    local px = x + Shared.measureText(Font, text:sub(1, at - 1))
    g.rectangle("fill", px + 1, y + 3, CELL - 2, 2)
    g.rectangle("fill", px + 3, y + 1, 2, CELL - 2)
    from = at + 1
  end
  g.setColor(r, gr, b, a)
  return Shared.measureText(Font, text)
end

-- ------------------------------------------------------------------ items
-- the item-use kinds lib/forage_items.lua weighs (neither generation's data carries them)
Shared.USE_OF = {
  POTION = "heal", SUPER_POTION = "heal", HYPER_POTION = "heal", MAX_POTION = "heal",
  FULL_RESTORE = "heal", FRESH_WATER = "heal", SODA_POP = "heal", LEMONADE = "heal",
  MOOMOO_MILK = "heal", BERRY_JUICE = "heal", ENERGYPOWDER = "heal", ENERGY_ROOT = "heal",
  ANTIDOTE = "status", BURN_HEAL = "status", ICE_HEAL = "status", AWAKENING = "status",
  PARLYZ_HEAL = "status", FULL_HEAL = "status", HEAL_POWDER = "status",
  REVIVE = "revive", MAX_REVIVE = "revive", REVIVAL_HERB = "revive",
  HP_UP = "vitamin", PROTEIN = "vitamin", IRON = "vitamin", CARBOS = "vitamin",
  CALCIUM = "vitamin", PP_UP = "vitamin",
}
-- evolution stones and Gold's trade-evolution items
Shared.EVO = { FIRE_STONE = true, WATER_STONE = true, THUNDER_STONE = true, LEAF_STONE = true,
  MOON_STONE = true, SUN_STONE = true, KINGS_ROCK = true, METAL_COAT = true, DRAGON_SCALE = true,
  UP_GRADE = true }

--- Puts `qty` of item `id` in the bag by the game's own rules; false when it does not fit.
function Shared.bagAdd(Bag, save, data, id, qty)
  if not (save and Bag and Bag.add) then return false end
  local ok, added = pcall(Bag.add, save, id, qty or 1, data)
  return ok and added == true
end

--- Would it fit right now? A dry run of the bag's own add against scratch copies
--- (Bag.addTo mutates nothing on failure, and the copies catch its successes).
function Shared.bagCanAdd(Bag, save, data, id, qty)
  if not (save and Bag and Bag.addTo and Bag.order and Bag.slots and Bag.capacity and Bag.pocketOf) then
    return false
  end
  local ok, fits = pcall(function()
    local inv = {}
    for k, v in pairs(save.inventory or {}) do inv[k] = v end
    local order = {}
    for i, v in ipairs(Bag.order(save, data)) do order[i] = v end
    local stacks = {}
    for k, v in pairs(type(save.bagStacks) == "table" and save.bagStacks or {}) do
      local list = {}
      if type(v) == "table" then for j, c in ipairs(v) do list[j] = c end end
      stacks[k] = list
    end
    local pocket = Bag.pocketOf(id, data)
    return Bag.addTo(inv, order, id, qty or 1, data,
      Bag.slots(save, data, pocket), Bag.capacity(data, pocket), stacks)
  end)
  return ok and fits == true
end

return Shared
