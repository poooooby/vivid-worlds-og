-- Battle Art (Red / Blue / Yellow; manifest id BATTLE_ART_VOXEL_FORK): our voxel sheets get
-- cards of their own size, at their Species Sizes size (displayWidth / displayHeight).
--
-- Battle Art builds every NPC card at 16 x 16 (SpriteBillboards.mesh, fy = frame * 16) and
-- pivots it at x + 8 (Mat4.billboard / Mat4.caster). Its exports.lib.require hands out the very
-- SpriteBillboards table its VoxelScene calls, so the shared adapter
-- (compat/voxel_sprite_billboards_adapter) wraps mesh there, re-points shadowQuad at it (body,
-- shadow and silhouette agree) and lands each sheet's anchor on that pivot. Battle Art passes
-- no feet `cut`, so that part of the shared adapter stays idle here. A 16 x 16 def keeps
-- Battle Art's own card. (Was Wilds of Kanto Revival's own copy of the same quad math, which
-- never read the display size: Species Sizes did nothing under Battle Art on these games.)
local V = ...
local Factory = V.require("compat/voxel_sprite_billboards_adapter")

local Adapter = Factory.create({
  providerId = "BATTLE_ART_VOXEL_FORK",
  displayName = "Battle Art",
  failLog = "Battle Art variable geometry unavailable; using Classic",
  okInstalled = "Battle Art variable sprite adapter installed",
  okNative = "Battle Art variable geometry: native",
})
Adapter.BATTLE_ART_ID = Adapter.PROVIDER_ID

return Adapter
