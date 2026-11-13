-- Run: lua tests/follower_adapter_unit_test.lua
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

local fakeEngine = {}
local modules = {}
local optionStore = { follower = true }
local fakeImageWidth = 48 -- wide by default; set nil to simulate no loaded art
local mod = {
  options = { get = function(_, k) return optionStore[k] end },
  read = function(_, rel)
    local f = io.open(rel, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
  end,
  assets = {
    image = function(_, _path)
      if fakeImageWidth == nil then return nil end
      return { getDimensions = function() return fakeImageWidth, 864 end }
    end,
  },
}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  if name == "engine_patch" then
    modules[name] = fakeEngine
    return fakeEngine
  end
  local chunk = assert(loadfile("lib/" .. name .. ".lua"))
  local value = chunk(V)
  modules[name] = value
  return value
end

local npc = nil
fakeEngine.followerCurrent = function() return npc end
fakeEngine.leadPartySpecies = function() return 999 end
fakeEngine.nationalFor = function(id) if id == 999 then return 252 end return nil end
fakeEngine.isWater = function() return false end
fakeEngine.playerIsRunning = function() return false end
fakeEngine.isGrass = function() return false end
-- shiny by personality (the follower asks with its own trainer ids)
local shinyPersonalities, shinyAsked = {}, {}
fakeEngine.isShiny = function(personality, otId, otSecretId)
  shinyAsked[#shinyAsked + 1] = { personality, otId, otSecretId }
  return shinyPersonalities[personality] == true
end
fakeEngine.grassSheet = function() return nil end

local FollowerAdapter = V.require("follower_adapter")
-- these tests are about the Walk <-> Idle switch itself: no grace period (see the linger tests in pmd_renderer_unit_test.lua)
V.require("config").PMD_WALK_LINGER = 0
local fa = FollowerAdapter.new(mod)

-- ------- shouldSpawn: always (there is no Follower option; the party menu picks who is out)
eq(fa:shouldSpawn(), true, "shouldSpawn is always true")
optionStore.show_follower = false
eq(fa:shouldSpawn(), true, "...even with a stale saved Follower value")
optionStore.show_follower = true

-- ------- tick() with no follower spawned does nothing
fa:tick()
eq(fa.renderer, nil, "no renderer built when no follower is spawned")

-- ------- tick() with a follower spawned sets npc.sprite to a renderer
-- for the current party lead's national dex
npc = { sprite = nil }
fa:tick()
check(npc.sprite ~= nil, "npc.sprite is set once a follower exists")
check(fa.renderer == npc.sprite, "FollowerAdapter tracks the renderer it installed")
eq(fa.renderer.dex, 252, "renderer uses the party lead's NATIONAL dex, not the internal id")

-- ------- tick() does not rebuild the renderer every call for the same lead
local same = npc.sprite
fa:tick()
check(npc.sprite == same, "same lead species -> renderer is not rebuilt")

-- ------- a lead species change rebuilds the renderer
fakeEngine.leadPartySpecies = function() return 1 end
fakeEngine.nationalFor = function(id) if id == 1 then return 1 end if id == 999 then return 252 end return nil end
fa:tick()
check(npc.sprite ~= same, "a new lead species rebuilds the renderer")
eq(fa.renderer.dex, 1, "renderer now uses the new lead's national dex")

-- ------- a Sprite Style change rebuilds the renderer even with the same
-- lead species, and takes effect without waiting for a species change
npc = { sprite = nil }
fakeEngine.leadPartySpecies = function() return 999 end
fakeEngine.nationalFor = function(id) if id == 999 then return 252 end return nil end
-- a view of the mod with PMD art (a fake one-species index; hermetic: a dev
-- checkout may or may not have a real bake on disk)
local EARLY_INDEX = [[{"version":1,"dex":{"252":{
  "walk":{"cw":30,"ch":26,"cols":4,"durations":[6,10,6,10],"ax":15.5,"ay":19.5,"shiny":false},
  "idle":{"cw":29,"ch":31,"cols":3,"durations":[40,4,2],"ax":15.5,"ay":25.5,"shiny":false}}}}]]
local function withPmd(base)
  return setmetatable({
    read = function(self, rel)
      if rel == "assets/pmd/index.json" then return EARLY_INDEX end
      return base.read(self, rel)
    end,
  }, { __index = base })
end
optionStore.sprite_style = "pokemmo"
fa = FollowerAdapter.new(withPmd(mod))
fa:tick()
eq(fa.renderer.style, "pokemmo", "renderer starts in the HGSS / PokeMMO style")
optionStore.sprite_style = "pmd" -- a stale save from another mod's sprite style
fa:tick()
check(not fa.renderer.isPmd and fa.renderer.style == "pokemmo", "a saved 'pmd' never leaves HGSS / PokeMMO")
optionStore.sprite_style = "pokemmo"

-- ------- pose: not moving -> stand, and A/B alternates per step (edge, not
-- per tick), walking vs running picked by EnginePatch.playerIsRunning()
local ActorRenderer = V.require("actor_renderer")
npc = { sprite = nil, moving = false, cellX = 0, cellY = 0 }
fa = FollowerAdapter.new(mod)
fa:tick()
eq(fa.renderer.poseOverride, ActorRenderer.POSE_STAND, "not moving -> stand pose")

npc.moving = true
fa:tick()
local firstWalkPose = fa.renderer.poseOverride
check(firstWalkPose == ActorRenderer.POSE_WALK_A or firstWalkPose == ActorRenderer.POSE_WALK_B,
  "moving, not running -> a walk pose")

fa:tick() -- still moving, SAME step (no edge) -- parity must not flip
eq(fa.renderer.poseOverride, firstWalkPose, "pose does not alternate mid-step, only on a new step")

npc.moving = false
fa:tick()
npc.moving = true
fa:tick() -- a NEW step (edge) -- parity flips
check(fa.renderer.poseOverride ~= firstWalkPose, "a new step alternates walkA/walkB")

fakeEngine.playerIsRunning = function() return true end
npc.moving = false
fa:tick()
npc.moving = true
fa:tick()
local runPose = fa.renderer.poseOverride
check(runPose == ActorRenderer.POSE_RUN_A or runPose == ActorRenderer.POSE_RUN_B,
  "moving while the player is running -> a run pose")
fakeEngine.playerIsRunning = function() return false end

-- ------- presentation: follows EnginePatch.isWater(npc.cellX, npc.cellY)
eq(fa.renderer.presentation, "land", "land presentation when not over water")
fakeEngine.isWater = function() return true end
fa:tick()
eq(fa.renderer.presentation, "swimming", "water presentation defaults to swimming")
fakeEngine.isWater = function() return false end

-- ------- collectActors: no grass overlay of our own -- on the Game Boy field the engine's
-- own grass covers the follower's feet. A hidden follower, or none at all, adds nothing.
npc.cellX, npc.cellY, npc.py, npc.elevation = 2, 3, 3 * 16, 3
fakeEngine.isGrass = function() return true end
local followerActors = {}
fa:collectActors(followerActors)
for _, a in ipairs(followerActors) do
  check(a.kind ~= "field_effect_wild_grass", "no mod-drawn grass overlay (" .. tostring(a.kind) .. ")")
end
fakeEngine.isGrass = function() return false end
npc.hidden = true
local hiddenActors = {}
fa:collectActors(hiddenActors)
eq(#hiddenActors, 0, "a hidden follower adds nothing")
npc.hidden = nil
local savedNpc = npc
npc = nil
local noFollowerActors = {}
fa:collectActors(noFollowerActors)
eq(#noFollowerActors, 0, "no follower spawned -> nothing, no error")
npc = savedNpc

-- ------- "spacing out" a large (True Size) follower: lib/actor_renderer.lua's
-- largePushback gets sized from the renderer's own loaded art width, gated
-- on STYLE_POKEMMO (lib/actor_renderer.lua's frameWidth/behindOffset handle
-- the actual draw-time math; this just checks FollowerAdapter computes and
-- assigns the right value each tick).
fakeImageWidth = 48 -- wider than one tile (CELL=16): (48-16)/2 = 16
optionStore.sprite_style = "pokemmo"
fa = FollowerAdapter.new(mod)
fa:tick()
eq(fa.renderer.largePushback, 16, "a wide True Size sprite gets a nonzero pushback")

-- A True Size sprite no wider than one tile gets no pushback.
fakeImageWidth = 16
optionStore.sprite_style = "pokemmo"
fa = FollowerAdapter.new(mod)
fa:tick()
eq(fa.renderer.largePushback, 0, "a one-tile-wide True Size sprite gets no pushback")

-- Turning glides: the applied offset eases toward the new facing's target
-- (a full 180-degree swing = 2 * pushback = 32px over 16 ticks) instead of
-- flipping in one tick.
fakeImageWidth = 48
optionStore.sprite_style = "pokemmo"
fa = FollowerAdapter.new(mod)
npc.facing = "down"
fa:tick()
eq(fa.renderer.pushY, -16, "first tick snaps to the facing's offset (no glide from nothing)")
npc.facing = "up"
fa:tick()
eq(fa.renderer.pushY, -14, "a turn moves the offset by one eased step, not all 32px")
for _ = 1, 15 do fa:tick() end
eq(fa.renderer.pushY, 16, "the offset reaches the new target after one step's worth of ticks")
eq(fa.renderer.pushX, 0, "the untouched axis stays put")
fakeImageWidth = 16 -- fits in one tile: nothing to push back
fa = FollowerAdapter.new(mod)
fa:tick()
check(fa.renderer.pushX == nil and fa.renderer.pushY == nil, "no pushback -> no eased offset (draw falls back)")

-- No art loaded yet (frameWidth nil) -> no pushback, never throws.
fakeImageWidth = nil
fa = FollowerAdapter.new(mod)
fa:tick()
eq(fa.renderer.largePushback, 0, "no loaded art -> no pushback, no error")
fakeImageWidth = 48 -- restore for safety

-- ------- a floating/flying lead flaps slowly while standing still; a ground
-- lead stays on the stand pose; moving keeps the walk pose either way
local SS = V.require("sprite_source")
local realIsFloater = SS.isFloater
SS.isFloater = function() return true end
npc = { sprite = nil, moving = false }
fa = FollowerAdapter.new(mod)
local seen = {}
for _ = 1, 100 do fa:tick() seen[fa.renderer.poseOverride] = true end
check(seen.walkA and seen.walkB and seen.stand, "idle floater cycles walkA/stand/walkB")
npc.moving = true
fa:tick()
check(fa.renderer.poseOverride == "walkA" or fa.renderer.poseOverride == "walkB", "a moving floater uses the real walk pose")
SS.isFloater = function() return false end
npc = { sprite = nil, moving = false }
fa = FollowerAdapter.new(mod)
for _ = 1, 50 do fa:tick() end
eq(fa.renderer.poseOverride, "stand", "a ground lead stays on stand while idle")
SS.isFloater = realIsFloater

-- no PMD art in this mod: what used to run per style runs HGSS / PokeMMO only
local pmdMod = mod
V.mod = mod

-- ------- on a bike the follower rides in its ball, in both art styles, until the player gets off
do
  local biking = false
  local realBike, realPixel = fakeEngine.playerBiking, fakeEngine.playerPixel
  fakeEngine.playerBiking = function() return biking end
  fakeEngine.playerPixel = function() return 40, 48 end
  local T = V.require("config").PMD_RECALL_TICKS
  for _, style in ipairs({ "pokemmo" }) do
    optionStore.sprite_style = style
    V.mod = (style == "pmd") and pmdMod or V.mod
    npc = { sprite = nil, moving = false, cellX = 3, cellY = 3, facing = "down" }
    local fb = FollowerAdapter.new(V.mod)
    fb:tick()
    eq(fb.renderer.recall or 1, 1, style .. ": on foot it is out")
    biking = true
    fb:tick()
    check((fb.renderer.recall or 1) < 1, style .. ": getting on the bike starts the recall (not a snap)")
    for _ = 1, T do fb:tick() end
    eq(fb.renderer.recall, 0, style .. ": inside its ball while riding")
    check(fb:isRecalled(), style .. ": recalled (no menu, no role)")
    check(fb.surfRecall, style .. ": its role pauses while riding")
    biking = false
    for _ = 1, T + 1 do fb:tick() end
    eq(fb.renderer.recall, 1, style .. ": off the bike it comes back out")
  end
  fakeEngine.playerBiking, fakeEngine.playerPixel = realBike, realPixel
  optionStore.sprite_style = nil
end

-- ------- Fly / Teleport: in its ball from the take-off to the landing, both art styles
do
  local traveling = false
  local realTravel, realPixel = fakeEngine.playerTraveling, fakeEngine.playerPixel
  fakeEngine.playerTraveling = function() return traveling end
  fakeEngine.playerPixel = function() return 40, 48 end
  local T = V.require("config").PMD_RECALL_TICKS
  for _, style in ipairs({ "pokemmo" }) do
    optionStore.sprite_style = style
    V.mod = (style == "pmd") and pmdMod or mod
    npc = { sprite = nil, moving = false, cellX = 3, cellY = 3, facing = "down" }
    local ff = FollowerAdapter.new(V.mod)
    ff:tick()
    eq(ff.renderer.recall or 1, 1, style .. ": out before Fly")
    traveling = true
    for _ = 1, T do ff:tick() end
    eq(ff.renderer.recall, 0, style .. ": the bird takes off: it went into its ball")
    check(ff.surfRecall, style .. ": its role pauses while flying")
    -- the landing map: the engine makes a new follower npc on the player's cell
    npc = { sprite = nil, moving = false, cellX = 9, cellY = 9, facing = "down" }
    ff:tick()
    eq(ff.renderer.recall, 0, style .. ": still in its ball while the bird swoops down")
    traveling = false
    ff:tick()
    check(ff.renderer.recall > 0 and ff.renderer.recall < 1, style .. ": landed: it comes out (grows, not a pop)")
    for _ = 1, T do ff:tick() end
    eq(ff.renderer.recall, 1, style .. ": fully out after landing")
  end
  fakeEngine.playerTraveling, fakeEngine.playerPixel = realTravel, realPixel
  optionStore.sprite_style = nil
  V.mod = mod
end

-- ------- ripples: each pond tile the follower steps onto, never on appearing
do
  local ripples = {}
  local realAt, realStart = fakeEngine.ripplesAt, fakeEngine.startRipple
  fakeEngine.ripplesAt = function(x, y) return y == 5 end
  fakeEngine.startRipple = function(x, y) ripples[#ripples + 1] = x .. "," .. y end
  npc = { sprite = nil, moving = false, cellX = 1, cellY = 5, facing = "down" }
  local fp = FollowerAdapter.new(mod)
  fp:tick()
  eq(#ripples, 0, "appearing on pond water makes no ripple")
  npc.cellX = 2
  fp:tick()
  eq(ripples[1], "2,5", "stepping onto a pond tile ripples it")
  fp:tick()
  eq(#ripples, 1, "standing still does not")
  npc.cellY = 4
  fp:tick()
  eq(#ripples, 1, "a tile without ripples gets none")
  npc = { sprite = nil, moving = false, cellX = 7, cellY = 5, facing = "down" }
  fp:tick()
  eq(#ripples, 1, "a re-created follower (map change) is only noted")
  fakeEngine.ripplesAt, fakeEngine.startRipple = realAt, realStart
end

-- ------- the follower vanishing (map transition) clears the tracked state
npc = nil
fa:tick()
eq(fa.leadSpecies, nil, "leadSpecies cleared once the follower is gone")

-- ------- the follower is shiny when its Pokemon is (like the overworld spawns)
do
  optionStore.sprite_style = "pokemmo"
  shinyPersonalities[777] = true
  local party = {
    { species = 999, personality = 111, otId = 4321, otSecretId = 8765 },
    { species = 999, personality = 777, otId = 4321, otSecretId = 8765 },
  }
  local current = 1
  local companion = { resolve = function() return party[current], "follow" end }
  npc = { sprite = nil, moving = false, cellX = 4, cellY = 4, px = 64, py = 64, facing = "down", elevation = 3 }
  local fsh = FollowerAdapter.new(mod, companion)
  fakeEngine.partyMons = function() return party end
  fsh:tick()
  eq(fsh.renderer.shiny, false, "a normal Pokemon's follower is not shiny")
  local last = shinyAsked[#shinyAsked]
  eq(last[1], 111, "the shiny check is made on the Pokemon's own personality ...")
  eq(last[2], 4321, "... and its own trainer id")
  eq(last[3], 8765, "... and secret id")
  local before = fsh.renderer
  current = 2 -- another Pokemon of the same species, but shiny
  for _ = 1, 3 do fsh:tick() end
  check(fsh.renderer ~= before, "swapping to a shiny of the same species rebuilds the sprite")
  eq(fsh.renderer.shiny, true, "the shiny Pokemon's follower is drawn shiny")
  local sameRenderer = fsh.renderer
  fsh:tick()
  check(fsh.renderer == sameRenderer, "(and it is not rebuilt every tick)")
  current = 1
  for _ = 1, 3 do fsh:tick() end
  eq(fsh.renderer.shiny, false, "...and back to normal for a non-shiny one")
  -- a Pokemon without a personality (no data) is simply not shiny
  local bare = FollowerAdapter.new(mod, { resolve = function() return { species = 999 }, "follow" end })
  npc = { sprite = nil, moving = false, cellX = 4, cellY = 4, px = 64, py = 64, facing = "down", elevation = 3 }
  bare:tick()
  eq(bare.renderer.shiny, false, "a Pokemon with no personality is not shiny")
  optionStore.sprite_style = "pokemmo"
end

-- ------- scenes (lib/follower_actions.lua): the adapter drives them onto the renderer
do
  local cries = {}
  local ahead = 2
  fakeEngine.playerFacing = function() return "down" end
  fakeEngine.freeCellsAhead = function(_x, _y, _dir, _max) return ahead end
  fakeEngine.playCry = function(species) cries[#cries + 1] = species return true end
  fakeEngine.cryFinished = function() return true end
  optionStore.sprite_style = "pmd"
  npc = { sprite = nil, moving = false, cellX = 4, cellY = 4, px = 64, py = 64, facing = "down", elevation = 3 }
  local fs = FollowerAdapter.new(pmdMod)
  fs:tick()

  check(fs:startAction("play") ~= nil, "startAction returns the scene")
  check(fs:actionActive(), "...and it is active")
  local actors = {}
  fs:tick()
  check(fs.renderer.act ~= nil, "a running scene hands its offset to the renderer")
  fs:collectActors(actors)
  local ball
  for _, a in ipairs(actors) do if a.kind == "follower_action_ball" then ball = a end end
  check(ball ~= nil, "the thrown ball is collected as a field actor")
  eq(npc.moving, false, "the engine's own follower state is never touched")
  eq(npc.px, 64, "...nor its position")

  local sawWalk, sawSpin, maxDy = false, {}, 0
  for _ = 1, 400 do
    fs:tick()
    if fs.renderer.anim == "walk" then sawWalk = true end
    if fs.renderer.act then
      maxDy = math.max(maxDy, fs.renderer.act.dy or 0)
      if fs.renderer.act.facing then sawSpin[fs.renderer.act.facing] = true end
    end
    if not fs:actionActive() then break end
  end
  eq(maxDy, 32, "it runs the free distance (2 cells) down the throw line")
  check(sawSpin.down and sawSpin.left and sawSpin.up and sawSpin.right, "it faces all four ways while spinning")
  check(not fs:actionActive(), "the scene ends by itself")
  eq(fs.renderer.act, nil, "...and the renderer's offset is cleared")
  actors = {}
  fs:collectActors(actors)
  check(#actors == 0 or actors[1].kind ~= "follower_action_ball", "no ball once the scene is over")

  -- pet: quick idle (hold skipped, sped up), then a cry
  fs:startAction("pet")
  fs.renderer.idleHold = 300
  fs:tick()
  for _ = 1, 400 do fs:tick() if not fs:actionActive() then break end end
  eq(#cries, 1, "pet plays the cry once")
  eq(cries[1], 999, "...with the lead's own (internal) species id")
  fs:tick()

  -- talk: two cries
  cries = {}
  fs:startAction("talk")
  for _ = 1, 600 do fs:tick() if not fs:actionActive() then break end end
  eq(#cries, 2, "talk plays the cry twice")

  -- cancel clears everything at once
  fs:startAction("play")
  fs:tick()
  fs:cancelAction()
  check(not fs:actionActive() and fs.renderer.act == nil, "cancelAction stops a scene and clears the offset")

  -- no follower: nothing to animate
  local keep = npc
  npc = nil
  check(fs:startAction("play") == nil, "no follower -> no scene")
  npc = keep

  -- HGSS / PokeMMO: walks in place with the A/B pose; pet bounces
  optionStore.sprite_style = "pokemmo"
  npc = { sprite = nil, moving = false, cellX = 4, cellY = 4, px = 64, py = 64, facing = "down", elevation = 3 }
  local fh = FollowerAdapter.new(mod)
  fh:tick()
  fh:startAction("play")
  local poses = {}
  for _ = 1, 120 do
    fh:tick()
    if fh.renderer.poseOverride then poses[fh.renderer.poseOverride] = true end
  end
  check(poses[V.require("actor_renderer").POSE_WALK_A] and poses[V.require("actor_renderer").POSE_WALK_B],
    "HGSS walks in place alternating the A and B poses during Play")
  fh:cancelAction()
  fh:startAction("pet")
  local bounced = {}
  for _ = 1, 40 do
    fh:tick()
    bounced[fh.renderer.poseOverride] = true
  end
  check(bounced[V.require("actor_renderer").POSE_WALK_A] or bounced[V.require("actor_renderer").POSE_WALK_B],
    "HGSS Pet bounces through the idle-flap poses")
  optionStore.sprite_style = "pokemmo"
end

-- ------- a companion with a role: the role's behaviour drives the follower
do
  fakeEngine.partyMons = function() return {} end
  fakeEngine.playerCell = function() return { x = 5, y = 5, moving = false } end
  local role = "forage"
  local companion = { resolve = function() return { species = 999 }, role end }
  local resets, last, popupOn = 0, nil, false
  local behavior = {
    step = function(_, env)
      last = env
      if not env.still then return nil end
      local s = { dx = 16, dy = 0, facing = "right", moving = true }
      if popupOn then s.popup = { text = "Found Potion!", age = 3 } end
      return s
    end,
    isBusy = function() return last ~= nil and last.still end,
    reset = function() resets = resets + 1 end,
  }
  optionStore.sprite_style = "pmd"
  npc = { sprite = nil, moving = false, cellX = 4, cellY = 4, px = 64, py = 64, facing = "down", elevation = 3 }
  local fb = FollowerAdapter.new(pmdMod, companion)
  fb.behaviors.forage = behavior
  fb:tick()
  eq(fb.role, "forage", "the companion's role is read each tick")
  eq(fb.leadSpecies, 999, "...and its species decides the sprite")
  eq(last.fx, 4, "the behaviour is told where the follower stands")
  eq(last.px, 5, "...and where the player is")
  check(last.still, "...and whether everything is standing still")
  eq(fb.renderer.act.dx, 16, "its offset reaches the renderer")
  eq(fb.renderer.act.facing, "right", "...and its facing")
  check(fb:isBusy(), "the follower is busy while the behaviour is away")

  popupOn = true
  fb:tick()
  local actors = {}
  fb:collectActors(actors)
  local popup
  for _, a in ipairs(actors) do if a.kind == "follower_popup" then popup = a end end
  check(popup ~= nil, "a find's label becomes a field actor")
  eq(popup.x, 64 + 16 + 8, "...above the follower's offset position")
  local function liftWith(h)
    fb.renderer.headLift = function() return h end
    local acts = {}
    fb:collectActors(acts)
    for _, a in ipairs(acts) do if a.kind == "follower_popup" then return a.lift end end
  end
  eq(liftWith(30), 30 - 16 + 3, "...its tail just over the top of the head (3 px of air)")
  eq(liftWith(60), 60 - 16 + 3, "...higher over a tall Pokemon")
  eq(liftWith(12), 2, "...never down into a small one")
  fb.renderer.headLift = nil
  popupOn = false

  -- the behaviour is told whether foraging is allowed here (routes / caves only)
  fakeEngine.forageAllowed = function(set) fakeEngine.allowedAsked = set return false end
  fb:tick()
  eq(last.forageOk, false, "forageOk reaches the behaviour (false in a town / building / on water)")
  check(fakeEngine.allowedAsked and fakeEngine.allowedAsked[3] and fakeEngine.allowedAsked[4],
    "...asked with the routes-and-caves set from the config")
  fakeEngine.forageAllowed = function() return true end
  fb:tick()
  eq(last.forageOk, true, "...and true on a route")
  fakeEngine.forageAllowed = nil

  -- a map change: behaviours with a mapChanged hook keep their state, others reset
  local kept, wiped = 0, 0
  fb.behaviors.forage = { step = behavior.step, isBusy = behavior.isBusy,
    mapChanged = function() kept = kept + 1 end, reset = function() wiped = wiped + 1 end }
  fb:mapChanged()
  eq(kept, 1, "a map change calls the behaviour's mapChanged ...")
  eq(wiped, 0, "...instead of wiping it")
  fb.behaviors.forage = behavior
  local before = resets
  fb:mapChanged()
  eq(resets, before + 1, "a behaviour without one is reset")

  npc.moving = true
  fakeEngine.playerCell = function() return { x = 5, y = 5, moving = true } end
  fb:tick()
  check(not last.still, "a walking player/follower is reported as not still")
  eq(fb.renderer.act, nil, "a behaviour that returns nothing clears the offset")

  role = "follow"
  npc.moving = false
  fb:tick()
  check(resets >= 1, "changing role resets the old behaviour")
  fb:resetBehaviors()
  eq(fb.renderer.act, nil, "resetBehaviors clears the offset")

  -- a scene wins over a behaviour
  role = "forage"
  fakeEngine.playerCell = function() return { x = 5, y = 5, moving = false } end
  fb:tick()
  fakeEngine.playerFacing = function() return "down" end
  fakeEngine.freeCellsAhead = function() return 1 end
  fakeEngine.playCry = function() return true end
  fakeEngine.cryFinished = function() return true end
  fb:startAction("talk")
  fb:tick()
  check(fb:isBusy(), "a scene counts as busy too")
  fb:cancelAction()
  optionStore.sprite_style = "pokemmo"
end

-- ------- the Follower option off: in its ball all the time, both art styles
do
  local realPixel = fakeEngine.playerPixel
  fakeEngine.playerPixel = function() return 40, 48 end
  local T = V.require("config").PMD_RECALL_TICKS
  for _, style in ipairs({ "pokemmo" }) do
    optionStore.sprite_style = style
    V.mod = (style == "pmd") and pmdMod or mod
    npc = { sprite = nil, moving = false, cellX = 3, cellY = 3, facing = "down" }
    local fo = FollowerAdapter.new(V.mod)
    fo:tick()
    eq(fo.renderer.recall or 1, 1, style .. ": the Follower option on (default): it is out")
    optionStore.show_follower = false
    for _ = 1, T do fo:tick() end
    eq(fo.renderer.recall, 0, style .. ": option off: it goes into its ball")
    check(fo:isRecalled(), style .. ": ...recalled, so it cannot be talked to")
    check(fo.surfRecall, style .. ": ...and its job pauses (as on a bike)")
    for _ = 1, 60 do fo:tick() end
    eq(fo.renderer.recall, 0, style .. ": ...and it stays in")
    optionStore.show_follower = nil
    for _ = 1, T + 1 do fo:tick() end
    eq(fo.renderer.recall, 1, style .. ": option back on: it comes back out")
  end
  fakeEngine.playerPixel = realPixel
  optionStore.sprite_style = nil
  V.mod = mod
end

-- ------- the Follower option off: a new companion changes over unseen (no scene, no lock)
do
  optionStore.sprite_style = "pokemmo"
  local party = {
    { species = 999, personality = 111, hp = 20 },
    { species = 998, personality = 222, hp = 20 },
  }
  local saved = { personality = 111, role = "follow" }
  local comp = { resolve = function()
    for _, m in ipairs(party) do
      if m.personality == saved.personality then return m, saved.role end
    end
  end }
  local poses, locks, unlocks = 0, 0, 0
  local names = { "partyMons", "screenBusy", "canStartInteraction", "playerPose", "lockField",
    "unlockField", "playCry", "playerPixel", "playerElevation", "nationalFor" }
  local kept = {}
  for _, k in ipairs(names) do kept[k] = fakeEngine[k] end
  fakeEngine.partyMons = function() return party end
  fakeEngine.screenBusy = function() return false end
  fakeEngine.canStartInteraction = function() return true end
  fakeEngine.playerPose = function() poses = poses + 1 return true end
  fakeEngine.lockField = function() locks = locks + 1 return true end
  fakeEngine.unlockField = function() unlocks = unlocks + 1 return true end
  fakeEngine.playCry = function() return true end
  fakeEngine.playerPixel = function() return 40, 48 end
  fakeEngine.playerElevation = function() return 3 end
  fakeEngine.nationalFor = function(id) return id == 999 and 252 or (id == 998 and 255 or nil) end

  npc = { sprite = nil, moving = false, cellX = 3, cellY = 3, facing = "down" }
  optionStore.show_follower = false
  local fo = FollowerAdapter.new(mod, comp)
  fo:tick()
  eq(fo.renderer.recall, 0, "option off from the start: a fresh partner is already in its ball (no shrink)")
  saved = { personality = 222, role = "follow" } -- the party order changed
  for _ = 1, 30 do fo:tick() end
  eq(fo.renderer.dex, 255, "a new lead becomes the partner while it is off")
  eq(fo.renderer.recall, 0, "...still in its ball")
  eq(poses + locks, 0, "...with no ball scene and no field lock")
  check(not fo:isBusy(), "...nothing under way")

  -- switched off in the middle of a swap scene: the scene ends, the field is let go
  optionStore.show_follower = nil
  for _ = 1, 40 do fo:tick() end
  eq(fo.renderer.recall, 1, "option back on: the current partner comes out")
  saved = { personality = 111, role = "follow" }
  fo:tick()
  check(fo:isBusy() and locks == 1, "back on, a party change plays the swap scene again")
  optionStore.show_follower = false
  fo:tick()
  check(not fo:isBusy(), "switching the option off mid-scene ends it")
  eq(unlocks, locks, "...and releases the field")
  for _ = 1, 40 do fo:tick() end
  eq(fo.renderer.dex, 252, "...the new partner is the one in its ball")
  eq(fo.renderer.recall, 0, "...in its ball")

  optionStore.show_follower = nil
  for _, k in ipairs(names) do fakeEngine[k] = kept[k] end
end

-- ------- swapping the companion: ball scene, old goes in, new comes out
do
  optionStore.sprite_style = "pokemmo"
  V.mod = mod
  local party = {
    { species = 999, personality = 111, hp = 20 },
    { species = 998, personality = 222, hp = 20 },
  }
  local saved = { personality = 111, role = "follow" }
  local comp = { resolve = function()
    for _, m in ipairs(party) do
      if m.personality == saved.personality then return m, saved.role end
    end
  end }
  local busy, poses, locks, unlocks, cries = false, 0, 0, 0, {}
  local pixel = { 40, 48 }
  local names = { "partyMons", "screenBusy", "canStartInteraction", "playerPose", "lockField",
    "unlockField", "playCry", "playerPixel", "playerElevation", "nationalFor" }
  local kept = {}
  for _, k in ipairs(names) do kept[k] = fakeEngine[k] end
  fakeEngine.partyMons = function() return party end
  fakeEngine.screenBusy = function() return busy end
  fakeEngine.canStartInteraction = function() return not busy end
  fakeEngine.playerPose = function() poses = poses + 1 return true end
  fakeEngine.lockField = function() locks = locks + 1 return true end
  fakeEngine.unlockField = function() unlocks = unlocks + 1 return true end
  fakeEngine.playCry = function(sp) cries[#cries + 1] = sp return true end
  fakeEngine.playerPixel = function() return pixel[1], pixel[2] end
  fakeEngine.playerElevation = function() return 3 end
  fakeEngine.nationalFor = function(id) return id == 999 and 252 or (id == 998 and 255 or nil) end

  npc = { sprite = nil, moving = false, cellX = 3, cellY = 3, facing = "down" }
  local fs = FollowerAdapter.new(mod, comp)
  fs:tick()
  eq(fs.renderer.dex, 252, "the companion is out")
  eq(fs.renderer.recall, 1, "...fully out, with no scene on a plain load")
  check(not fs:isBusy(), "nothing is happening")

  -- changed in the party menu: nothing moves until the menu is closed
  saved = { personality = 222, role = "follow" }
  busy = true
  for _ = 1, 5 do fs:tick() end
  eq(fs.renderer.dex, 252, "the old companion stays out while the menu is open")
  eq(poses, 0, "...and the player has not raised the ball yet")

  busy = false
  fs:tick()
  check(fs:isBusy(), "the swap scene begins once the menu is closed")
  eq(locks, 1, "...and holds the field")
  eq(poses, 1, "the player raises the ball")
  local ball = false
  local actors = {}
  fs:collectActors(actors)
  for _, a in ipairs(actors) do if a.kind == "follower_action_ball" then ball = true end end
  check(ball, "a ball is drawn in the player's hand")

  local sawOut, sawIn = false, false
  for _ = 1, 200 do
    fs:tick()
    if fs.renderer.dex == 252 and fs.renderer.recall == 0 then sawOut = true end
    if fs.renderer.dex == 255 and fs.renderer.recall == 0 then sawIn = true end
    if not fs:isBusy() then break end
  end
  check(sawOut, "the old companion shrank all the way into the player first")
  check(sawIn, "the new one began inside the player")
  eq(fs.renderer.dex, 255, "the new companion is displayed")
  eq(fs.renderer.recall, 1, "...grown fully out")
  eq(poses, 2, "the ball went up once for each")
  eq(unlocks, 1, "the field is released")
  eq(cries[#cries], 998, "the new one cried as it came out")
  check(not fs:isBusy(), "the scene is over")

  -- it evolves (the same party mon, same personality, another species): the new art at once
  party[2].species = 999
  fs:tick()
  eq(fs.renderer.dex, 252, "an evolved companion shows its new species")
  eq(fs.disp.species, 999, "...its displayed species follows")
  check(not fs:isBusy(), "...with no ball scene")
  eq(poses, 2, "...and no ball raised")
  -- a fresh table for the same Pokemon (the engine rebuilt the party mon) after a battle too
  party[2] = { species = 998, personality = 222, hp = 20 }
  fs:tick()
  eq(fs.renderer.dex, 255, "a rebuilt party mon of another species is shown as it is")

  -- recall: the companion shrinks in and stays in
  saved = { personality = 222, role = "recall" }
  for _ = 1, 200 do fs:tick() if not fs:isBusy() and fs.renderer.recall == 0 then break end end
  eq(fs.renderer.recall, 0, "a recall leaves it inside the player")
  check(fs:isRecalled(), "isRecalled is true, so it cannot be talked to")
  for _ = 1, 30 do fs:tick() end
  eq(fs.renderer.recall, 0, "...and it stays in")

  -- sent back out: only the grow-out scene
  poses = 0
  saved = { personality = 222, role = "forage" }
  for _ = 1, 200 do fs:tick() if not fs:isBusy() and fs.renderer.recall == 1 then break end end
  eq(fs.renderer.recall, 1, "choosing a job brings it back out")
  eq(poses, 1, "...with one raise of the ball")

  -- a job change on the same Pokemon, already out: it just takes the new job, no ball
  poses = 0
  local lockedBefore = locks
  saved = { personality = 222, role = "follow" }
  busy = true -- even with the party menu still open
  fs:tick()
  busy = false
  local shrank = false
  for _ = 1, 60 do
    fs:tick()
    if fs:isBusy() and fs.swap then shrank = true end
    if (fs.renderer.recall or 1) < 1 then shrank = true end
  end
  eq(poses, 0, "changing the job of the Pokemon already out raises no ball")
  check(not shrank, "...it is never put away and sent out again")
  eq(locks, lockedBefore, "...and the field is not held")
  eq(fs.role, "follow", "...it simply has the new job")

  -- a map change drops a scene in progress, releasing the field
  saved = { personality = 111, role = "follow" }
  fs:tick()
  check(fs:isBusy(), "another swap is under way")
  fs:mapChanged()
  check(not fs:isBusy(), "a new map drops the scene")
  eq(unlocks, locks, "...and every lock was released")

  for _, k in ipairs(names) do fakeEngine[k] = kept[k] end
end

-- ------- its own touches (lib/partner_fx.lua): evolve sparkles, type puffs, Type Aura
do
  fakeEngine.speciesTypes = function() return 10, 10 end -- a Fire type
  fakeEngine.typeName = function(t) return t == 10 and "FIRE" or "NORMAL" end
  optionStore.sprite_style = "pokemmo"
  npc = { sprite = nil, moving = false, cellX = 4, cellY = 4, px = 64, py = 64, facing = "down", elevation = 3 }
  local f = FollowerAdapter.new(mod)
  f:tick()
  local function partsNow()
    local actors, out = {}, nil
    f:collectActors(actors)
    for _, a in ipairs(actors) do if a.kind == "ow_partner_fx" then out = a.parts end end
    return out
  end
  local function has(parts, shape)
    for _, p in ipairs(parts or {}) do if p[2] == shape then return true end end
    return false
  end
  f.fxClock = 10
  eq(partsNow(), nil, "nothing going on: no touches (Type Aura is off by default)")
  f.readyPending = { moves = {}, evolve = true }
  check(has(partsNow(), "sparkle"), "ready to evolve: sparkles drift up round it")
  f.readyPending = nil
  f.withYouAge = 8
  check(has(partsNow(), "ember"), "while you Pet / Play / Talk with a Fire type: embers (whatever its mood)")
  f.withYouAge = nil
  optionStore.type_aura = true
  check(has(partsNow(), "ember"), "with Type Aura on: an ember puff now and then")
  f.fxClock = 100
  eq(partsNow(), nil, "...with long rests in between")
  optionStore.type_aura = nil
  f.renderer.recall = 0
  f.readyPending = { evolve = true }
  f.fxClock = 10
  eq(partsNow(), nil, "nothing while it is inside the player")
  fakeEngine.speciesTypes, fakeEngine.typeName = nil, nil
end

-- ------- the "waiting to learn / evolve" label over the follower's head
do
  local asked = 0
  local waiting = { moves = { 40 }, evolve = false }
  local f = FollowerAdapter.new(mod)
  eq(f:readyLabel(), nil, "no level tracker: no label")
  f.levelReady = { pending = function() asked = asked + 1 return waiting end }
  local mon1 = { personality = 1 }
  f.mon = mon1
  f:_tickReady()
  eq(f:readyLabel(), "New move ready!", "a waiting move shows its label")
  for _ = 1, 20 do f:_tickReady() end
  eq(asked, 1, "the tracker is only asked now and then, not every tick")
  waiting = { moves = {}, evolve = true }
  for _ = 1, 40 do f:_tickReady() end
  eq(f:readyLabel(), "Ready to evolve!", "...and the label follows what it says")
  f.away = true
  eq(f:readyLabel(), nil, "nothing floats while it is inside the player")
  f.away = false
  f.mon = { personality = 2 }
  f:_tickReady()
  eq(asked, 4, "a different Pokemon is asked about at once")
  waiting = nil
  f:_tickReady() f.readyClock = 0 f:_tickReady()
  eq(f:readyLabel(), nil, "nothing waiting: no label")
end

-- ------- walking out of a doorway: hidden in it, fading in as it steps out
do
  local warps = { ["5,8"] = true }
  local realWarp = fakeEngine.isWarpCell
  fakeEngine.isWarpCell = function(x, y) return warps[x .. "," .. y] == true end
  local f = FollowerAdapter.new(mod)
  -- a fresh follower on the door tile (the engine makes one on the player's cell)
  npc = { sprite = nil, moving = false, cellX = 5, cellY = 8, px = 80, py = 128, facing = "down" }
  f:tick()
  check(f:isEmerging(), "a fresh follower on a warp tile is coming out of the doorway")
  eq(npc.hidden, true, "...and is not drawn while it stands in it")
  for _ = 1, 30 do f:tick() end
  eq(npc.hidden, true, "it stays hidden while the player is walked out")
  eq(f:startAction("pet"), nil, "no scene can start while it is in the doorway")
  -- it steps out: visible again, fading in over the step
  npc.moving, npc.progress, npc.stepFrames, npc.targetX, npc.targetY = true, 4, 16, 5, 9
  f:tick()
  eq(npc.hidden, false, "stepping out it is drawn again")
  eq(f.renderer.alpha, 0.25, "...fading in with the step (4 of 16)")
  npc.progress = 12
  f:tick()
  eq(f.renderer.alpha, 0.75, "...12 of 16")
  -- out of the doorway
  npc.moving, npc.cellX, npc.cellY = false, 5, 9
  f:tick()
  check(not f:isEmerging(), "once it is out of the doorway it is done")
  eq(f.renderer.alpha, nil, "...fully visible")
  eq(npc.hidden, false, "...and not hidden")
  -- the same follower later on a warp tile (walking over a door mat) does not re-trigger
  npc.cellX, npc.cellY = 5, 8
  f:tick()
  check(not f:isEmerging(), "only a FRESH follower on a warp tile walks out (not one that walks onto one)")

  -- a fresh follower on an ordinary tile (route border, Fly, a load): drawn as always
  npc = { sprite = nil, moving = false, cellX = 20, cellY = 20, px = 320, py = 320, facing = "down" }
  f:tick()
  check(not f:isEmerging(), "a fresh follower anywhere else is drawn at once")
  check(not npc.hidden, "...not hidden")

  -- the engine's own hiding is never undone by us
  local g = FollowerAdapter.new(mod)
  npc = { sprite = nil, moving = false, cellX = 5, cellY = 8, px = 80, py = 128, facing = "down", hidden = true }
  g:tick()
  npc.moving, npc.progress, npc.stepFrames = true, 8, 16
  g:tick()
  eq(npc.hidden, true, "a follower the engine hid stays hidden (we only undo our own)")

  -- a new map mid-way restores the old follower and starts over
  local h = FollowerAdapter.new(mod)
  local old = { sprite = nil, moving = false, cellX = 5, cellY = 8, px = 80, py = 128, facing = "down" }
  npc = old
  h:tick()
  eq(old.hidden, true, "sanity: hidden in the doorway")
  npc = { sprite = nil, moving = false, cellX = 30, cellY = 30, px = 480, py = 480, facing = "down" }
  h:tick()
  eq(old.hidden, false, "a new follower: the old one is not left hidden")
  check(not h:isEmerging(), "...and the new one (not on a warp) is drawn")
  npc = nil
  h:tick()
  check(not h:isEmerging(), "no follower at all clears it")
  fakeEngine.isWarpCell = realWarp
end

print("")
-- ------- drawn over water: its own tile, or where a behaviour has moved it
do
  local realIsWater = fakeEngine.isWater
  fakeEngine.isWater = function(x, y) return x >= 5 end
  local fw = FollowerAdapter.new(mod)
  fw.renderer = { pushX = 0, pushY = 0 }
  local n = { cellX = 3, cellY = 3, px = 48, py = 48 }
  fw.sceneNow = nil
  check(not fw:_drawnOnWater(n), "standing on its own land tile: not on water")
  fw.sceneNow = { dx = 32, dy = 0 }
  check(fw:_drawnOnWater(n), "the Battler swum out two tiles onto water: on water")
  fw.sceneNow = { dx = 8, dy = 0 }
  check(not fw:_drawnOnWater(n), "half a tile out is still its own tile")
  n.cellX, n.px = 6, 96
  fw.sceneNow = nil
  check(fw:_drawnOnWater(n), "a follower on a water tile (surfing) is on water")
  fakeEngine.isWater = realIsWater
end

-- ------- into its ball for the nurse's heal machine, and while the player walks with someone
do
  local healing, leading, busy = false, false, true
  local saved = { fakeEngine.healingActive, fakeEngine.leadingNpc, fakeEngine.fieldBusy, fakeEngine.playerPixel }
  fakeEngine.healingActive = function() return healing end
  fakeEngine.leadingNpc = function() return leading end
  fakeEngine.fieldBusy = function() return busy end
  fakeEngine.playerPixel = function() return 40, 48 end
  local T = V.require("config").PMD_RECALL_TICKS
  for _, style in ipairs({ "pokemmo" }) do
    optionStore.sprite_style = style
    V.mod = (style == "pmd") and pmdMod or V.mod
    npc = { sprite = nil, moving = false, cellX = 3, cellY = 3, facing = "down" }
    local fh = FollowerAdapter.new(V.mod)
    fh:tick()
    healing = true
    for _ = 1, T + 1 do fh:tick() end
    eq(fh.renderer.recall, 0, style .. ": the heal machine runs: inside its ball")
    healing = false
    for _ = 1, T + 1 do fh:tick() end
    eq(fh.renderer.recall, 1, style .. ": healed: back out")
    check(not fh:inCutscene(), style .. ": talking to someone (no one moved): it stays out")
    fh:onScriptMovement(3)
    check(fh:inCutscene(), style .. ": a script walking an NPC is a cutscene")
    fh:onScriptEnded()
    fh:onScriptMovement(0xFF)
    check(fh:inCutscene(), style .. ": ...so is one walking only the player")
    fh:onScriptMovement(3)
    for _ = 1, T + 1 do fh:tick() end
    eq(fh.renderer.recall, 0, style .. ": during the cutscene it keeps out of the way, in its ball")
    fh:onScriptEnded()
    for _ = 1, T + 1 do fh:tick() end
    eq(fh.renderer.recall, 1, style .. ": the script over: back out")
    fh:onScriptMovement(4)
    busy = false
    check(not fh:inCutscene(), style .. ": no script running any more (an end not heard): it lets go")
    busy = true
    leading = true
    for _ = 1, T + 1 do fh:tick() end
    eq(fh.renderer.recall, 0, style .. ": a character following the player (Gen 2 follow): inside its ball")
    leading = false
    for _ = 1, T + 1 do fh:tick() end
    eq(fh.renderer.recall, 1, style .. ": ...and out again after")
  end
  fakeEngine.healingActive, fakeEngine.leadingNpc, fakeEngine.fieldBusy, fakeEngine.playerPixel = saved[1], saved[2], saved[3], saved[4]
  optionStore.sprite_style = nil
end

-- ------- a notice (the Battler hotkey's label): up for NOTICE_TICKS, then gone
do
  local st = setmetatable({}, { __index = FollowerAdapter })
  st:notify("Battling!")
  eq(st.notice and st.notice.text, "Battling!", "notify puts up a label")
  check(FollowerAdapter.NOTICE_TICKS > 30, "...for a moment (" .. FollowerAdapter.NOTICE_TICKS .. " ticks)")
end

-- ------- called back from the field (its job taken away mid-way): it runs home, never pops back
do
  local st = setmetatable({ homeRun = { x = 10, y = -5 } }, { __index = FollowerAdapter })
  check(st:isBusy(), "running home: busy (no Pet / Play / Talk menu yet)")
  local s = st:_tickHomeRun()
  check(s and s.moving and s.dx < 10 and s.dx > 0 and s.dy == -5, "it closes the offset a step at a time (x first)")
  eq(s.facing, "left", "...facing the way it runs")
  local n = 1
  while st.homeRun and n < 100 do s = st:_tickHomeRun() n = n + 1 end
  eq(st.homeRun, nil, "home at last")
  check(n > 4, "...after a run, not at once (" .. n .. " ticks)")
  check(not st:isBusy(), "...and free again")
end

-- ------- voxel card strides (lib/voxel_sheets.lua): A and B by turns, one per step
do
  local st = { renderer = {} }
  local npc = { moving = false }
  FollowerAdapter._tickStride(st, npc)
  eq(st.renderer.voxelStride, "a", "standing: stride A")
  npc.moving, npc.targetX, npc.targetY = true, 5, 4
  FollowerAdapter._tickStride(st, npc)
  local first = st.renderer.voxelStride
  FollowerAdapter._tickStride(st, npc)
  eq(st.renderer.voxelStride, first, "the same step keeps its stride")
  npc.targetX = 4 -- the next step follows straight on, never stopping
  FollowerAdapter._tickStride(st, npc)
  check(st.renderer.voxelStride ~= first, "back-to-back steps: the next one takes the other stride")
  local second = st.renderer.voxelStride
  npc.moving, npc.targetX, npc.targetY = false, nil, nil
  FollowerAdapter._tickStride(st, npc)
  eq(st.renderer.voxelStride, second, "stopping keeps it")
  npc.moving = true -- an engine without target cells: the moving edge
  FollowerAdapter._tickStride(st, npc)
  check(st.renderer.voxelStride ~= second, "no target cell: a new step on the moving edge")
  FollowerAdapter._tickStride({}, npc) -- no renderer: nothing to do
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("follower_adapter_unit_test: all passed")
