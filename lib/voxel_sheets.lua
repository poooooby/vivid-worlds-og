-- Our Pokemon as sprites a voxel world mod can build cards from (Battle Art, TERRARIUM, Potato
-- Voxel, Dramaless, Stadium2 -- on Red / Blue / Yellow / Gold / Silver / Crystal: lib/engine_patch.lua,
-- lib/compat/).
--
-- A render pipeline mod draws the world itself, from each entity's ENGINE sprite: e:pose()
-- -> sprite, whose `def.image` it loads through src.render.Assets and slices with Gen 1's
-- SpriteRenderer layout (a vertical strip: STAND down / up / left = frames 0-2, WALK =
-- 3-5, right = left mirrored). Our renderers draw HGSS / GSC art of any size, so for
-- each (art key, shiny, style, silhouette, colour mode) this bakes such a strip once: the
-- renderer's own drawing of each pose, rendered into a canvas cell (feet on the cell's
-- bottom edge, centred), read back and registered as a COMPOSED asset
-- (Assets.compose(path, build)) -- so `Assets.image(def.image)` and the mod's palette bake
-- (Assets.imageData) both find it with nothing written to disk. The def carries the real
-- frame size and anchor (frameWidth / frameHeight / anchorX / anchorY, Gen1Recomp's own
-- SpriteDef geometry names) and `wohVoxel = true`; the adapters in lib/compat/ make the cards
-- that size.
--
-- Colour: in a mode that honours true colour the sheet keeps its colours (trueColor =
-- true); otherwise it is baked in the three luminance shades lib/gb_color.lua draws the 2D
-- path with (trueColor = false), so the mod colours it from the map's palette like any
-- vanilla sprite. A card shows one still frame per pose.
--
-- Strides: the strip has ONE walk frame per facing, and the pipelines show it alternating
-- with the stand frame -- up / down also mirror it every other step (a second stride for
-- free), but a mirrored side view would face the other way, so sideways the art only bobbed
-- (HGSS stand and stride A are nearly the same side pose): it glided. So each art gets a
-- second strip whose walk rows hold the OTHER stride (walk B), and
-- `spriteFor` hands out the one for the renderer's current step (`r.voxelStride`, "a" / "b",
-- set per step by lib/spawn_manager.lua and lib/follower_adapter.lua): stand, A, stand, B,
-- like the 2D game.
local V = ...
local GbColor = V.require("gb_color")
local HdField = V.require("hd_field")
local Config = V.require("config")
local SpriteSource = V.require("sprite_source")

local VoxelSheets = {}
VoxelSheets.__index = VoxelSheets

VoxelSheets.FRAMES = 6
-- SpriteRenderer.STAND / WALK (src/render/SpriteRenderer.lua)
VoxelSheets.ROWS = {
  { facing = "down", walk = false }, { facing = "up", walk = false }, { facing = "left", walk = false },
  { facing = "down", walk = true }, { facing = "up", walk = true }, { facing = "left", walk = true },
}
VoxelSheets.MIN_CELL, VoxelSheets.MAX_CELL = 32, 160

--- A square cell side (px, a multiple of 16) that holds art reaching `lift` px above its
--- feet: room for the height and for a wide body.
function VoxelSheets.cellFor(lift)
  lift = tonumber(lift) or 24
  local side = math.ceil(1.6 * (lift + 8) / 16) * 16
  if side < VoxelSheets.MIN_CELL then side = VoxelSheets.MIN_CELL end
  if side > VoxelSheets.MAX_CELL then side = VoxelSheets.MAX_CELL end
  return side
end

--- deps: makeRenderer(key, shiny, style) -> a fresh renderer, assets (src.render.Assets),
--- poses (the ActorRenderer POSE_* constants: STAND, WALK_A).
function VoxelSheets.new(deps)
  return setmetatable({ deps = deps or {}, sprites = {}, data = {} }, VoxelSheets)
end

local function styleOf(r)
  return r.style or "pokemmo"
end

-- draws one pose of `r` into the current canvas, its tile at (tx, ty); `b` = stride B
local function drawPose(r, row, tx, ty, poses, b)
  local walk = b and (poses.WALK_B or poses.WALK_A) or poses.WALK_A
  r:draw(tx, ty, 0, 0, row.facing, row.walk and walk or poses.STAND, false)
end

-- renders the six poses into an ImageData (cell x cell*6), or nil
local function bake(r, cell, luma, poses, b)
  local G = love.graphics
  if not (G and G.newCanvas) then return nil end
  -- 1:1 with the sheet's pixels: by default a canvas takes the screen's DPI scale (2 to 3 on
  -- a phone), and the sheet would come out that many times its frame size -- the mod then
  -- slices a cell x cell corner of each pose, pieces of the art (lib/popup_text.lua alike)
  local ok, canvas = pcall(G.newCanvas, cell, cell * VoxelSheets.FRAMES, { dpiscale = 1 })
  if not (ok and canvas) then
    ok, canvas = pcall(G.newCanvas, cell, cell * VoxelSheets.FRAMES) -- older LOVE: no settings
  end
  if not (ok and canvas) then return nil end
  G.push("all")
  G.origin()
  G.setCanvas(canvas)
  G.clear(0, 0, 0, 0)
  G.setShader()
  G.setColor(1, 1, 1, 1)
  G.setBlendMode("alpha")
  local okDraw, err = pcall(function()
    for i, row in ipairs(VoxelSheets.ROWS) do
      -- the renderer puts the art's feet on the tile's bottom edge, centred on it
      drawPose(r, row, cell / 2 - 8, (i - 1) * cell + cell - 16, poses, b)
    end
  end)
  G.setCanvas()
  G.pop()
  if not okDraw then error(err, 0) end
  local data = canvas:newImageData()
  canvas:release()
  if luma then
    data:mapPixel(function(_, _, cr, cg, cb, ca)
      if ca <= 0 then return 0, 0, 0, 0 end
      local s = GbColor.shadeOf(cr, cg, cb)
      return s, s, s, ca
    end)
  end
  return data
end

--- The engine-shaped sprite for a renderer's art, or nil (no art, no love). Cached per
--- art key / shiny / style / silhouette / colour mode / species size; the pixels are baked
--- the first time the mod asks for the image (Assets.compose's build), inside its own draw.
--- Species Sizes (HGSS_scale, lib/hd_field.lua): the card's display size
--- (displayWidth / displayHeight, which the adapters in lib/compat/ honour, the anchor
--- scaled with it) is the frame times the species' factor; the sheet itself is shared.
--- The size a renderer's card is shown at against its art (`path`, the art it draws): a
--- Poke Followers / GSC sheet keeps its own (1); HGSS art takes its species' Species Sizes
--- factor against the shorter Game Boy player, with the option on only.
function VoxelSheets.factorFor(r, path)
  if SpriteSource.isGsc(path) then return 1 end
  local factor = HdField.factorFor("hgss", r.dex)
  if HdField.speciesSizes then factor = factor * Config.gbSizeRatio() end
  return factor
end

function VoxelSheets:spriteFor(r, luma)
  if type(r) ~= "table" or r.dex == nil then return nil end
  local style = styleOf(r)
  local sil = r.silhouette and true or false
  local b = r.voxelStride == "b"
  -- (one concatenation, no table: this runs for every card every frame)
  local key = tostring(r.dex) .. "-" .. (r.shiny and "s" or "n") .. "-" .. tostring(style) .. "-"
    .. (sil and "sil" or "") .. "-" .. (luma and "luma" or "color") .. (b and "-b" or "")
  -- a Poke Followers / GSC sheet is already drawn at the Game Boy's own scale: its card
  -- keeps the sheet's size. HGSS art (including a GSC-style species that has no GSC art)
  -- is sized by Species Sizes against the shorter Game Boy player (Config.gbSizeRatio),
  -- with the option on only -- off, a card keeps its art's own size
  local path = r.imagePath and r:imagePath()
  local factor = VoxelSheets.factorFor(r, path)
  local spriteKey = key .. "@" .. factor
  local hit = self.sprites[spriteKey]
  if hit ~= nil then return hit or nil end
  local deps = self.deps
  local Assets = deps.assets
  local fresh = deps.makeRenderer and deps.makeRenderer(r.dex, r.shiny, style)
  if not (Assets and Assets.compose and fresh) then
    self.sprites[spriteKey] = false
    return nil
  end
  fresh.silhouette = sil
  local lift = fresh.headLift and fresh:headLift() or (fresh.visualHeight and fresh:visualHeight()) or 24
  local cell = VoxelSheets.cellFor(lift)
  local path = "vivid_worlds_og/voxel/" .. key .. ".png"
  local data = self.data
  if not self.composed then self.composed = {} end
  if not self.composed[path] then self.composed[path] = true Assets.compose(path, function()
    if data[path] == nil then
      local okB, img = pcall(bake, fresh, cell, luma, deps.poses or {}, b)
      data[path] = okB and img or false
    end
    local img = data[path]
    if not img then return love.image.newImageData(1, 1) end
    return img:clone() -- callers may change what they get
  end) end
  local def = {
    id = "VWOG_VOXEL_" .. key, image = path, frames = VoxelSheets.FRAMES, walker = true,
    trueColor = not luma, frameWidth = cell, frameHeight = cell, anchorX = cell / 2, anchorY = cell,
    wohVoxel = true,
  }
  if factor ~= 1 then
    def.displayWidth, def.displayHeight = cell * factor, cell * factor
  end
  local sprite = {
    def = def, frameWidth = cell, frameHeight = cell, anchorX = cell / 2, anchorY = cell,
    resolveImage = function() return Assets.image(path) end,
  }
  self.sprites[spriteKey] = sprite
  return sprite
end

--- An engine-shaped sprite with nothing on it (every texel transparent, which the mods'
--- shaders discard: no card, no shadow, no silhouette): the partner in its ball still walks
--- behind the player as the engine's follower, and a pipeline draws every entity it has.
function VoxelSheets:blank()
  if self.blankSprite ~= nil then return self.blankSprite or nil end
  local Assets = self.deps.assets
  if not (Assets and Assets.compose) then
    self.blankSprite = false
    return nil
  end
  local path = "vivid_worlds_og/voxel/blank.png"
  Assets.compose(path, function() return love.image.newImageData(16, 16 * VoxelSheets.FRAMES) end)
  local def = {
    id = "VWOG_VOXEL_blank", image = path, frames = VoxelSheets.FRAMES, walker = true,
    trueColor = true, frameWidth = 16, frameHeight = 16, anchorX = 8, anchorY = 16, wohVoxel = true,
  }
  self.blankSprite = {
    def = def, frameWidth = 16, frameHeight = 16, anchorX = 8, anchorY = 16,
    resolveImage = function() return Assets.image(path) end,
  }
  return self.blankSprite
end

return VoxelSheets
