-- Run: lua tests/voxel_sheets_unit_test.lua
-- lib/voxel_sheets.lua: the engine-shaped sprite a voxel world mod reads for our art, its
-- composed asset, its geometry, one per art / colour mode / silhouette.
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

love = { image = { newImageData = function() return { clone = function(s) return s end } end } }
local composed = {}
local Assets = { compose = function(path, build) composed[path] = build end, image = function(p) return { path = p } end }
local VS = V.require("voxel_sheets")
eq(VS.cellFor(20), 48, "a small Pokemon: a 48 px cell")
eq(VS.cellFor(1000), VS.MAX_CELL, "a giant one is capped")
eq(VS.cellFor(0), 32, "never under 32")
local sheets = VS.new({
  assets = Assets, poses = { STAND = 1, WALK_A = 2 },
  makeRenderer = function(key, shiny, style) return { dex = key, shiny = shiny, style = style, headLift = function() return 20 end } end,
})
local r = { dex = 25, shiny = false, style = "pokemmo", silhouette = false }
local s = sheets:spriteFor(r, false)
check(s and s.def and s.def.frames == 6 and s.def.walker, "a 6-frame walker def (Gen 1's SpriteRenderer layout)")
eq(s.def.trueColor, true, "colour mode: true colour")
eq(s.def.frameWidth, 48, "...its real frame size (what the adapters size the card by)")
eq(s.def.anchorX, 24, "...centred")
eq(s.def.anchorY, 48, "...feet on the frame's bottom edge")
check(composed[s.def.image] ~= nil, "its sheet is a composed asset")
eq(s:resolveImage().path, s.def.image, "resolveImage loads that asset")
check(sheets:spriteFor(r, false) == s, "one sprite per art")
local l = sheets:spriteFor(r, true)
check(l ~= s and l.def.trueColor == false, "the luminance sheet is its own, not true colour")
r.silhouette = true
check(sheets:spriteFor(r, false) ~= s, "a silhouette is its own sheet")
eq(sheets:spriteFor({ shiny = false }, false), nil, "no art key, no sprite")

-- Species Sizes: the card's display size is the frame times the species' factor
local HGSS = V.require("HGSS_scale")
local HdField = V.require("hd_field")
local pika = sheets:spriteFor({ dex = 25, shiny = false, style = "pokemmo" }, false)
check(math.abs(pika.def.displayWidth - 48 * HGSS[25] * 16 / 22) < 1e-9,
  "Species Sizes: a Pikachu card is its HGSS_scale size x 16 / 22 (the Game Boy player is 16 px, not 22)")
eq(pika.def.displayHeight, pika.def.displayWidth, "...scaled evenly")
eq(pika.def.frameWidth, 48, "...the sheet itself unscaled")
HdField.setSpeciesSizes(false)
local plain = sheets:spriteFor({ dex = 25, shiny = false, style = "pokemmo" }, false)
check(plain ~= pika and plain.def.displayWidth == nil, "Species Sizes off: the sheet's own size")
eq(plain.def.image, pika.def.image, "...the same baked sheet either way")
HdField.setSpeciesSizes(true)

-- WoobleView's Field HD on: the renderer's headLift is as drawn on the field, shrunk by
-- Species Sizes. The bake draws the art at its own size, so the cell comes from the art's own
-- height either way -- the same sheet on and off -- and a sheet baked at one cell is never
-- handed to a card of another (Scyther with Battle Art: frames sliced across two poses)
do
  local wv = { exports = { tag = function() end, isActive = function() return true end,
    enabled = function() return true end } }
  local mod = { find = function(_, id) if id == "gen3-hd-sprites" then return wv end end }
  local SCY = "assets/wilds_generated/true_size18/hgss/123-normal.png"
  local RAW = 40 -- the art's own reach above its feet: a 80 px cell (cellFor(40))
  local sheetsW = VS.new({
    assets = Assets, poses = { STAND = 1, WALK_A = 2 },
    makeRenderer = function(key, shiny, style)
      return { dex = key, shiny = shiny, style = style, mod = mod,
        imagePath = function() return SCY end,
        headLift = function() return RAW * HdField.scaleOfPath(mod, SCY) end }
    end,
  })
  local function scyther() return { dex = 123, shiny = false, style = "pokemmo", mod = mod, imagePath = function() return SCY end } end
  check(HdField.scaleOfPath(mod, SCY) < 0.9, "(WoobleView scales a Scyther sheet down with Species Sizes on)")
  local on = sheetsW:spriteFor(scyther(), false)
  eq(on.def.frameWidth, VS.cellFor(RAW), "Species Sizes on: the cell holds the art at its own size")
  HdField.setSpeciesSizes(false)
  local off = sheetsW:spriteFor(scyther(), false)
  HdField.setSpeciesSizes(true)
  check(off ~= on and off.def.displayWidth == nil, "Species Sizes off: its own card, at the sheet's size")
  eq(off.def.frameWidth, on.def.frameWidth, "...the same cell")
  eq(off.def.image, on.def.image, "...the same baked sheet")
  -- a card with another cell (a different art reach) gets a sheet and id of its own
  RAW = 20
  local small = VS.new({ assets = Assets, poses = { STAND = 1, WALK_A = 2 },
    makeRenderer = function(key, shiny, style)
      return { dex = key, shiny = shiny, style = style, headLift = function() return RAW end }
    end }):spriteFor(scyther(), false)
  check(small.def.frameWidth ~= on.def.frameWidth, "(another cell)")
  check(small.def.image ~= on.def.image and small.def.id ~= on.def.id,
    "another cell: its own sheet and id, never the one baked at the other cell")
end

-- the Game Boy player is one 16 px tile (the size table is tuned against a 22 px one)
local Config = V.require("config")
check(math.abs(Config.gbSizeRatio() - 16 / 22) < 1e-9, "always a Game Boy boot: 16 / 22")

-- strides: a renderer on its B step gets its own sheet (the walk rows hold stride B), so
-- a sideways walk is stand, A, stand, B instead of a bob between stand and A
local ra = { dex = 7, shiny = false, style = "pokemmo", voxelStride = "a" }
local sa = sheets:spriteFor(ra, false)
check(sheets:spriteFor({ dex = 7, shiny = false, style = "pokemmo" }, false) == sa, "no stride set: the A sheet")
ra.voxelStride = "b"
local sb = sheets:spriteFor(ra, false)
check(sb ~= sa and sb.def.image ~= sa.def.image, "stride B: its own sheet")
check(composed[sb.def.image] ~= nil, "...a composed asset too")
eq(sb.def.frameWidth, sa.def.frameWidth, "...the same cell")
check(sheets:spriteFor(ra, false) == sb, "...one per art")

-- the bake's canvas is 1:1 with the sheet's pixels: a phone's DPI scale (2 to 3) would make
-- it that many times the frame size, and the mod would slice a corner of each pose
local made
local function noop() end
love.graphics = {
  newCanvas = function(w, h, settings)
    made = { w = w, h = h, settings = settings }
    return { newImageData = function() return { clone = function(c) return c end, w = w, h = h } end, release = noop }
  end,
  push = noop, pop = noop, origin = noop, setCanvas = noop, clear = noop, setShader = noop,
  setColor = noop, setBlendMode = noop,
}
local drew = 0
local sheets2 = VS.new({
  assets = Assets, poses = { STAND = 1, WALK_A = 2 },
  makeRenderer = function(key, shiny, style)
    return { dex = key, shiny = shiny, style = style, headLift = function() return 20 end,
      draw = function() drew = drew + 1 end }
  end,
})
local baked = sheets2:spriteFor({ dex = 155, shiny = false, style = "pokemmo" }, false)
local img = composed[baked.def.image]()
check(made and made.settings and made.settings.dpiscale == 1, "the bake's canvas has dpiscale 1 (no DPI scaling)")
eq(made.w, baked.def.frameWidth, "...as wide as one frame")
eq(made.h, baked.def.frameHeight * VS.FRAMES, "...six frames tall")
eq(img.w, made.w, "...and the sheet read back is that size")
eq(drew, VS.FRAMES, "...each pose drawn once")
love.graphics = nil

-- the partner in its ball: a blank sheet (all transparent: the mods discard it)
local blank = sheets:blank()
check(blank and blank.def and blank.def.frames == 6 and blank.def.walker, "blank: a 6-frame walker def")
eq(blank.def.frameWidth, 16, "...one tile")
check(composed[blank.def.image] ~= nil, "...a composed asset")
check(sheets:blank() == blank, "...one of it")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("voxel_sheets_unit_test: all passed")
