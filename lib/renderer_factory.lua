-- The one place that builds the renderer that draws a Pokemon, so lib/spawn_manager.lua,
-- lib/follower_adapter.lua and lib/voxel_sheets.lua never pick a class themselves.
-- HGSS / PokeMMO only: lib/actor_renderer.lua, at each species' own size.
local V = ...
local ActorRenderer = V.require("actor_renderer")

local RendererFactory = {}

--- No sprite here is cut at a baked waterline (that was the PMDCollab style's).
function RendererFactory.pmdSwims() return false end

--- `dex` = an art key (a national dex number, or "%03d-<form>" for an alternate form;
--- see lib/sprite_source.lua); `presentation` picks land / swimming / levitating art.
function RendererFactory.new(mod, dex, shiny, style, presentation)
  return ActorRenderer.new(mod, dex, shiny, style, presentation)
end

return RendererFactory
