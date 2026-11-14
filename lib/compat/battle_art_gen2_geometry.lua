-- Battle Art Gen 2 (Gold / Silver / Crystal; manifest id BATTLE_ART_VOXEL_GEN2): our voxel
-- sheets get cards of their own size, at their Species Sizes size, centred on their tile.
--
-- Battle Art Gen 2 already builds a frameWidth x frameHeight card (SpriteBillboards.mesh), but
-- it places a card from x + halfWidth(def) = frameWidth / 2 (VoxelScene / Voxel3D.casterMatrix:
-- the 2 x 2 "big doll" placement), so a 48 px sheet would stand 16 px right of and behind its
-- tile, and it never reads the display size. So for OUR sheets only (def.wohVoxel) the shared
-- adapter (compat/voxel_sprite_billboards_adapter) builds the card -- display size, anchor on
-- the pivot -- and answers halfWidth 8. Every other def, the game's big Snorlax / Lapras dolls
-- included, keeps Battle Art Gen 2's own card and placement.
local V = ...
local Factory = V.require("compat/voxel_sprite_billboards_adapter")

local Adapter = Factory.create({
  providerId = "BATTLE_ART_VOXEL_GEN2",
  displayName = "Battle Art Gen2",
  failLog = "Battle Art Gen2 variable geometry unavailable; using Classic",
  okInstalled = "Battle Art Gen2 variable sprite adapter installed",
  handles = function(def) return def.wohVoxel == true end,
  centreHalfWidth = true,
})
Adapter.BATTLE_ART_GEN2_ID = Adapter.PROVIDER_ID

return Adapter
