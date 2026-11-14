-- The one SpriteBillboards.mesh wrap for every 3D world mod that exposes Battle Art's public
-- module table (exports.lib.require): Battle Art (Gen 1 and Gen 2), TERRARIUM, Potato,
-- Dramaless, Stadium 2 -- each a thin Factory.create entry beside this file.
--
-- Our voxel sheets (lib/voxel_sheets.lua) carry their own frame size, anchor and display
-- (Species Sizes) size; the wrap builds their card at that size with the anchor on the
-- providers' pivot (x + 8), and re-points shadowQuad at it so body, shadow and silhouette
-- agree. A 16 x 16 def calls the provider's own mesh() unchanged; shadowBlob() (Potato) is
-- never wrapped. No provider source is copied or patched on disk.
local V = ...
-- (From Wilds of Kanto Revival's adapters, by way of Wilds of Hoenn: the log shim, the feet
-- `cut`, `handles` and `centreHalfWidth` are ours.)
local DebugLog = {
  info = function(mod, fmt, ...)
    if mod and mod.log and mod.log.info then mod.log:info("[vivid_worlds_og] " .. fmt, ...) end
  end,
}

local Factory = {}

local INSET_U = 0.02
local INSET_V = 0.05
-- Dramatic Shape-family billboard / caster matrices apply T(-8, 0, 0).
local PIVOT_X = 8

--- spec:
---   providerId, displayName
---   failLog, okInstalled  (log strings)
---   handles(def)     optional: only these defs get our card (others keep the provider's)
---   centreHalfWidth  optional: also wrap SpriteBillboards.halfWidth to answer 8 for the defs
---                    we build (a provider that places a card from x + halfWidth, Battle Art
---                    Gen 2, would otherwise set a wide card off-centre)
function Factory.create(spec)
  spec = spec or {}
  local Adapter = {}
  Adapter.PROVIDER_ID = spec.providerId
  Adapter.FAIL_LOG = spec.failLog
    or (tostring(spec.displayName or "Voxel")
      .. " variable geometry unavailable; using Classic")

  local _state = "idle" -- idle | installed | failed | absent
  local _reason = nil
  local _loggedFail = false
  local _loggedOk = false
  local _origMesh = nil
  local _origInvalidate = nil
  local _origShadowQuad = nil
  local _origHalfWidth = nil
  local _varMeshes = {}
  local _wrappedTable = nil
  local _Voxel3D = nil
  local _Assets = nil

  local function logFail(mod, why)
    if _loggedFail then return end
    _loggedFail = true
    local msg = Adapter.FAIL_LOG
    if why and why ~= "" then
      msg = msg .. " (" .. tostring(why) .. ")"
    end
    if DebugLog and DebugLog.info then
      DebugLog.info(mod, "%s", msg)
    end
  end

  local function logOk(mod, detail)
    if _loggedOk then return end
    _loggedOk = true
    local msg = spec.okInstalled
      or (tostring(spec.displayName or "Voxel") .. " variable geometry: adapter installed")
    if DebugLog and DebugLog.info then
      DebugLog.info(mod, "%s", msg)
    end
  end

  function Adapter.findProvider(mod)
    if not mod or type(mod.find) ~= "function" then return nil end
    local ok, hit = pcall(mod.find, mod, Adapter.PROVIDER_ID)
    if ok and hit then return hit end
    return nil
  end

  function Adapter.reset()
    if _wrappedTable and _origMesh then
      _wrappedTable.mesh = _origMesh
      if _origShadowQuad ~= nil then
        _wrappedTable.shadowQuad = _origShadowQuad
      else
        _wrappedTable.shadowQuad = _origMesh
      end
      if _origInvalidate then
        _wrappedTable.invalidate = _origInvalidate
      end
      if _origHalfWidth then
        _wrappedTable.halfWidth = _origHalfWidth
      end
      _wrappedTable._wildsVariableGeometryWrapped = nil
    end
    _state = "idle"
    _reason = nil
    _loggedFail = false
    _loggedOk = false
    _origMesh = nil
    _origInvalidate = nil
    _origShadowQuad = nil
    _origHalfWidth = nil
    _varMeshes = {}
    _wrappedTable = nil
    _Voxel3D = nil
    _Assets = nil
  end

  -- displayWidth/displayHeight/displayAnchorX/displayAnchorY let a caller
  -- request a billboard quad SMALLER or LARGER than the real frameWidth/
  -- frameHeight/anchorX/anchorY. They default to the real values, so every
  -- existing caller (Battle Art, Potato, Dramaless, Stadium2, Terrarium) is
  -- unaffected unless it sets them. Unlike a 2D canvas scale,
  -- this changes only the 3D quad's world-space size (Adapter.localQuad);
  -- Adapter.uvRect always slices the texture from the real frameWidth/
  -- frameHeight, so every source pixel is still sampled at native
  -- resolution — no resampling of the underlying image.
  function Adapter.needsVariableGeometry(def)
    if type(def) ~= "table" then return false end
    local fw = tonumber(def.frameWidth)
    local fh = tonumber(def.frameHeight)
    local ax = tonumber(def.anchorX)
    local ay = tonumber(def.anchorY)
    local dw = tonumber(def.displayWidth)
    local dh = tonumber(def.displayHeight)
    local dax = tonumber(def.displayAnchorX)
    local day = tonumber(def.displayAnchorY)
    if fw == nil and fh == nil and ax == nil and ay == nil
        and dw == nil and dh == nil and dax == nil and day == nil then
      return false
    end
    fw = fw or 16
    fh = fh or 16
    if ax == nil then ax = fw / 2 end
    if ay == nil then ay = fh end
    dw = dw or fw
    dh = dh or fh
    if dax == nil then dax = dw / 2 end
    if day == nil then day = dh end
    if fw == 16 and fh == 16 and ax == 8 and ay == 16
        and dw == 16 and dh == 16 and dax == 8 and day == 16 then
      return false
    end
    return fw > 0 and fh > 0 and dw > 0 and dh > 0
  end

  function Adapter.resolveGeometry(def)
    local fw = tonumber(def.frameWidth) or 16
    local fh = tonumber(def.frameHeight) or 16
    local ax = tonumber(def.anchorX)
    local ay = tonumber(def.anchorY)
    if ax == nil then ax = fw / 2 end
    if ay == nil then ay = fh end
    local dw = tonumber(def.displayWidth) or fw
    local dh = tonumber(def.displayHeight) or fh
    local dax = tonumber(def.displayAnchorX)
    local day = tonumber(def.displayAnchorY)
    local hasDisplay = def.displayWidth ~= nil or def.displayHeight ~= nil
      or def.displayAnchorX ~= nil or def.displayAnchorY ~= nil
    if hasDisplay then
      -- Quantize SIZE only (never a separately-computed anchor) to whole
      -- pixels: a fractional quad extent makes the rasterizer sample a
      -- different pixel column per frame (HGSS_SPRITES hit this at
      -- 0.6x/0.7x scales), which looks like the card pinching or
      -- stretching across the walk cycle. Only when a display override is
      -- actually set — otherwise this would round every plain (no
      -- override) real size too, for every caller that never opted in.
      dw = math.floor(dw + 0.5)
      dh = math.floor(dh + 0.5)
    end
    -- Default anchor: derive from the (already-quantized) display size as
    -- an exact proportion of the real anchor, rather than independently
    -- rounding a separately-computed anchor value. Two things break
    -- otherwise: (1) most species have ay == fh (anchor flush with the
    -- frame bottom) — but a species with real transparent padding below
    -- its feet (e.g. Onix: anchorY=36, frameHeight=38) needs that same 2px
    -- gap preserved at the display size, or its ground contact point
    -- shifts and it visibly floats/sinks. (2) for a centered real anchor
    -- (ax == fw/2, true for most species on X), deriving dax from the
    -- quantized dw guarantees dax == dw/2 exactly, however dw rounds —
    -- independently rounding dax can land it off-center by up to half a
    -- pixel when dw quantizes to an odd number, and since facing left/right
    -- mirrors the quad around the pivot, an off-center quad shifts one way
    -- when mirrored and the other way when not: too close facing one
    -- direction, too far facing the other. A fractional result here (e.g.
    -- dax = 10.5) is fine — a stable fractional offset never causes jitter,
    -- only a per-frame *varying* one does, which is what the dw/dh
    -- quantization above already prevents.
    if dax == nil then
      dax = (fw ~= 0) and (ax * (dw / fw)) or (dw / 2)
    elseif hasDisplay then
      dax = math.floor(dax + 0.5)
    end
    if day == nil then
      day = (fh ~= 0) and (ay * (dh / fh)) or dh
    elseif hasDisplay then
      day = math.floor(day + 0.5)
    end
    return fw, fh, ax, ay, dw, dh, dax, day
  end

  -- (one concatenation, no table: asked for every card every frame)
  function Adapter.cacheKey(def, frame, fw, fh, ax, ay, dw, dh, dax, day)
    return tostring(def.image) .. "#" .. tostring(frame or 0) .. "#" .. tostring(fw) .. "#" .. tostring(fh)
      .. "#" .. tostring(ax) .. "#" .. tostring(ay) .. "#" .. tostring(dw) .. "#" .. tostring(dh)
      .. "#" .. tostring(dax) .. "#" .. tostring(day)
  end

  function Adapter.localQuad(fw, fh, ax, ay)
    local x0 = PIVOT_X - ax
    local x1 = x0 + fw
    local y0 = ay - fh
    local y1 = ay
    return x0, y0, x1, y1
  end

  function Adapter.uvRect(fw, fh, frame, iw, ih)
    local fy = (tonumber(frame) or 0) * fh
    if fy + fh > ih then
      return nil, "frame_overflow"
    end
    local u0 = INSET_U / iw
    local u1 = (fw - INSET_U) / iw
    local v0 = (fy + INSET_V) / ih
    local v1 = (fy + fh - INSET_V) / ih
    return u0, v0, u1, v1, fy
  end

  local function getImageSize(imagePath)
    if _Assets and type(_Assets.image) == "function" then
      local ok, img = pcall(_Assets.image, imagePath)
      if ok and img and type(img.getDimensions) == "function" then
        return img:getDimensions()
      end
    end
    return nil, nil
  end

  local function buildVariableCard(def, frame, cut)
    local fw, fh, ax, ay, dw, dh, dax, day = Adapter.resolveGeometry(def)
    local iw, ih = getImageSize(def.image)
    if not iw or not ih or iw <= 0 or ih <= 0 then
      return nil, "image_unavailable"
    end
    local u0, v0, u1, v1, _fy = Adapter.uvRect(fw, fh, frame, iw, ih)
    if not u0 then
      return nil, v0 or "frame_overflow"
    end
    local x0, y0, x1, y1 = Adapter.localQuad(dw, dh, dax, day)
    -- `cut`: display px of the feet hidden (water, tall grass, snow -- TERRARIUM passes it
    -- as mesh()'s third argument). As in its own card, the cut edge becomes the card's
    -- origin and only the body above it is shown.
    if cut > 0 then
      local scale = fh / dh
      local fy = (tonumber(frame) or 0) * fh
      y0, y1 = 0, day - cut
      v1 = (fy + ay - cut * scale) / ih
    end
    local verts = {
      { x0, y0, 0, u0, v1, 1 }, { x1, y0, 0, u1, v1, 1 },
      { x1, y1, 0, u1, v0, 1 }, { x0, y1, 0, u0, v0, 1 },
    }
    local indices = {}
    _Voxel3D.pushQuad(indices, 0)
    local mesh = _Voxel3D.newMesh(verts, indices)
    if not mesh then
      return nil, "newMesh_nil"
    end
    return mesh
  end

  -- the defs this adapter builds the card for (spec.handles narrows them)
  local function ours(def)
    if type(def) ~= "table" or type(def.image) ~= "string" then return false end
    if spec.handles and not spec.handles(def) then return false end
    return Adapter.needsVariableGeometry(def)
  end
  Adapter.handles = ours

  local function wrappedMesh(def, frame, cut, ...)
    if not ours(def) then
      return _origMesh(def, frame, cut, ...)
    end
    local fw, fh, ax, ay, dw, dh, dax, day = Adapter.resolveGeometry(def)
    cut = math.floor(tonumber(cut) or 0)
    if cut < 0 then cut = 0 end
    local maxCut = math.floor(day * 0.75)
    if cut > maxCut then cut = maxCut end
    local key = Adapter.cacheKey(def, frame, fw, fh, ax, ay, dw, dh, dax, day) .. "#" .. cut
    if _varMeshes[key] == nil then
      local ok, meshOrErr = pcall(buildVariableCard, def, frame, cut)
      if ok and meshOrErr then
        _varMeshes[key] = meshOrErr
      else
        _varMeshes[key] = false
      end
    end
    if _varMeshes[key] then
      return _varMeshes[key]
    end
    return _origMesh(def, frame, cut, ...)
  end

  local function wrappedInvalidate()
    _varMeshes = {}
    if _origInvalidate then
      return _origInvalidate()
    end
  end

  local function wrapBillboards(SpriteBillboards, Voxel3D, Assets)
    if SpriteBillboards._wildsVariableGeometryWrapped then
      return true, "already_wrapped"
    end
    if type(SpriteBillboards.mesh) ~= "function" then
      return false, "SpriteBillboards.mesh missing"
    end
    if not Voxel3D or type(Voxel3D.newMesh) ~= "function"
        or type(Voxel3D.pushQuad) ~= "function" then
      return false, "Voxel3D.newMesh/pushQuad missing"
    end
    _origMesh = SpriteBillboards.mesh
    _origInvalidate = SpriteBillboards.invalidate
    _origShadowQuad = SpriteBillboards.shadowQuad
    _Voxel3D = Voxel3D
    _Assets = Assets
    _varMeshes = {}
    _wrappedTable = SpriteBillboards
    SpriteBillboards.mesh = wrappedMesh
    -- Re-point shadowQuad so solid / occlusion silhouette share geometry.
    -- Potato's dedicated shadowBlob() is a different function and is left
    -- on the table untouched.
    if type(SpriteBillboards.shadowQuad) == "function" then
      SpriteBillboards.shadowQuad = wrappedMesh
    end
    SpriteBillboards.invalidate = wrappedInvalidate
    if spec.centreHalfWidth and type(SpriteBillboards.halfWidth) == "function" then
      local orig = SpriteBillboards.halfWidth
      _origHalfWidth = orig
      SpriteBillboards.halfWidth = function(def, ...)
        if ours(def) then return PIVOT_X end
        return orig(def, ...)
      end
    end
    SpriteBillboards._wildsVariableGeometryWrapped = true
    if Assets and type(Assets.register) == "function" then
      pcall(Assets.register, wrappedInvalidate)
    end
    return true, "wrapped_mesh"
  end

  function Adapter.install(mod)
    if _state == "installed" then
      return true, _reason
    end
    if _state == "failed" then
      return false, _reason
    end

    local ok, err = pcall(function()
      local ds = Adapter.findProvider(mod)
      if not ds then
        _state = "absent"
        _reason = "provider_absent"
        return
      end
      local lib = ds.exports and ds.exports.lib
      if not (lib and type(lib.require) == "function") then
        error("exports.lib.require missing")
      end
      local okSB, SpriteBillboards = pcall(lib.require, "SpriteBillboards")
      if not (okSB and type(SpriteBillboards) == "table") then
        error("SpriteBillboards module missing")
      end
      local okV3, Voxel3D = pcall(lib.require, "Voxel3D")
      if not (okV3 and type(Voxel3D) == "table") then
        error("Voxel3D module missing")
      end
      local Assets = nil
      local okA, A = pcall(require, "src.render.Assets")
      if okA and type(A) == "table" then Assets = A end
      local wrapped, why = wrapBillboards(SpriteBillboards, Voxel3D, Assets)
      if not wrapped then
        error(why or "wrap failed")
      end
      _state = "installed"
      _reason = why
    end)

    if not ok then
      _state = "failed"
      _reason = tostring(err)
      logFail(mod, _reason)
      return false, _reason
    end
    if _state == "absent" then
      return false, _reason
    end
    if _state == "failed" then
      logFail(mod, _reason)
      return false, _reason
    end
    logOk(mod, _reason)
    return true, _reason
  end

  return Adapter
end

return Factory
