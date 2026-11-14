-- In-memory compatibility adapter: STADIUM2_OVERWORLD_MODELS SpriteBillboards.mesh
-- consumes Wilds / Gen1Recomp variable SpriteDef geometry.
--
-- Stadium2 (manifest id STADIUM2_OVERWORLD_MODELS) is the Gen 2 voxel
-- renderer. Current versions expose exports.lib = V with V.require, the
-- same public SpriteBillboards / Voxel3D / VoxelScene contract as Battle
-- Art, Potato, and Dramaless. Wilds wraps mesh() and re-points shadowQuad
-- so body, occlusion silhouette, and sprite-mesh shadows agree.
-- Stadium2 source is not copied and is not patched on disk.
--
-- Pivot: VoxelScene billboard / caster matrices apply T(-8,0,0), same
-- convention as Battle Art. Variable quads land the SpriteDef anchor on
-- that pivot. Classic 16×16 + anchor 8,16 stays on the original mesh().
local V = ...
local Factory = V.require("compat/voxel_sprite_billboards_adapter")

local Adapter = Factory.create({
  providerId = "STADIUM2_OVERWORLD_MODELS",
  displayName = "Stadium2 Voxel",
  failLog = "Stadium2 Voxel variable geometry unavailable; using Classic",
  okInstalled = "Stadium2 Voxel variable geometry: adapter installed",
})

return Adapter
