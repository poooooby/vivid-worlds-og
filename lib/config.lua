-- Tunables and option helpers for vivid_worlds_og.
local V = ...

local Config = {}

Config.DEFAULTS = {
  enabled = true,
  sprite_style = "pokemmo", -- HGSS / PokeMMO; "followers" = Poke Followers / GSC
  classic_enc = true,
  wild_silhouettes = "off",
  species_sizes = true,
  spawn_amount = "normal",
  smooth_follow = true,
  show_follower = true,
  wild_reacts = true,
  type_aura = false,
  role_pad = "off",
  role_key = "off",
}

Config.STATE = {
  AVAILABLE = "available",
  ENCOUNTER_STARTING = "encounter_starting",
  DESPAWNED = "despawned",
  -- on its way out (SpawnManager:despawn with animate): still drawn, sinking back
  -- into the grass / fading, but no longer met, counted or fought
  LEAVING = "leaving",
}

-- How wild Pokemon arrive and leave (lib/spawn_fx.lua): rising out of the grass with a
-- rustle, surfacing with a ripple on water, a fade anywhere else; the same reversed when
-- one leaves. Ticks at 60 per second.
Config.SPAWN_FX = { appearTicks = 26, leaveTicks = 22 }

-- Water spawns as live swimmers (lib/behavior.lua swim, lib/spawn_manager.lua):
--   runs   every one swims (none just float): a heading held for runMin..runMax tiles at
--          stepFrames a tile (16 = walking pace), a pause of pauseMin..pauseMax ticks between
--          runs; a blocked heading tries the other directions (turning back last)
--   bob    a gentle rise and fall at the surface, bobAmp px, one cycle every bobTicks
--   wake   a small ring left on each tile it swims off (r0 -> r1 px, life ticks)
--   dive   every diveMin..diveMax ticks (when more than clearRadius tiles from the player)
--          it sinks (sinkTicks), stays under underMin..underMax ticks, and surfaces in
--          rings 1..hop tiles away (the arrival effect); nobody can touch it while under
Config.SWIM = {
  stepFrames = 22, runMin = 2, runMax = 5, pauseMin = 180, pauseMax = 360,
  bobAmp = 1, bobTicks = 96,
  wake = { life = 28, r0 = 3, r1 = 10 },
  dive = { min = 600, max = 2700, sinkTicks = 22, underMin = 60, underMax = 180, hop = 3, clearRadius = 2 },
}

-- Density, per terrain (land and water each): MIN_VISIBLE plus one more Pokemon for
-- every TILES_PER_ADDITIONAL eligible tiles, at most MAX_VISIBLE. These are the
-- Normal values of the Spawn Amount option; SPAWN_AMOUNT holds Low and High.
Config.MIN_VISIBLE = 1
Config.MAX_VISIBLE = 8
Config.TILES_PER_ADDITIONAL = 20
Config.SPAWN_AMOUNT = {
  low = { min = 1, max = 4, tilesPer = 40 },     -- about half
  normal = { min = Config.MIN_VISIBLE, max = Config.MAX_VISIBLE, tilesPer = Config.TILES_PER_ADDITIONAL },
  high = { min = 2, max = 12, tilesPer = 13 },   -- about one and a half times
}

-- Wild Pokemon reacting to a player who runs or bikes close by (the Wild Reacts option,
-- lib/wild_reactions.lua). 60 Hz ticks; distances in steps (tiles across + tiles up / down,
-- so a diagonal counts as the steps it takes). Strength is level x base-stat total against the lead Pokemon's: under
-- `weakRatio` it is startled ("!") and flees (a bird takes off), over `strongRatio` it gets
-- angry and chases; an even match in between is not bothered.
Config.REACT = {
  radius = 2, bikeRadius = 4,     -- how close the running / biking player has to come
  aggroRadius = 1, bikeAggroRadius = 2, -- ...for a stronger one to get angry: right beside it
  weakRatio = 0.7, strongRatio = 1.3,
  -- how likely it reacts at all, by how far past its threshold the ratio is: `minChance` %
  -- just past it (close to the lead's strength), rising evenly to `maxChance` % at
  -- `weakSure` (fleeing) / `strongSure` (chasing). One roll as the player comes in range;
  -- a miss rests `missCooldown` ticks
  minChance = 10, maxChance = 50, weakSure = 0.4, strongSure = 2.0, missCooldown = 300,
  alertTicks = 24,                -- "!" before fleeing / taking off
  turnTicks = 22,                 -- a stronger one's pause before it turns to the player
  angerTicks = 36,                -- then the anger mark, then the chase
  emoteTicks = 50,                -- how long an emote stays up
  hopTicks = 12, hopPx = 3,       -- a startled little hop
  -- running pace; at the end of its run, `vanishChance` % of them disappear -- in grass
  -- shrinking into it with a rustle, in a cave fading out (lib/spawn_manager.lua fleeVanish)
  flee = { steps = { 1, 3 }, frames = 8, vanishChance = 30 },
  chase = { frames = 7,           -- a touch faster than a running player (8)
            leash = { 2, 4 },     -- tiles it follows before giving up: rolled every chase
            -- PMDCollab: it charges with its Attack animation while it chases and on until
            -- its battle opens; no battle within `chargeTicks` of catching up -> it calms down
            chargeTicks = 90,
            secondsPerTile = 1.2, -- the matching time limit (leash x this)
            noPathTicks = 60, returnSteps = { 2, 4 },
            -- a land chaser follows the player off its own grass onto any open ground
            -- (never water or a doorway); afterwards it walks home onto its terrain,
            -- planning up to `homeSearch` cells, or leaves with the fade if it can't
            anyGround = true, homeSearch = 24 },
  cooldown = 600, chaseCooldown = 900, -- before the same Pokemon reacts again
}

-- A wild Pokemon whose fight with the Battler is broken off (its job changed: lib/
-- spawn_manager.lua runAway): a parting shot first -- it faces the player, cries and lunges
-- `lungePx` toward them once over `partTicks` (PMD: its Attack animation) -- then runs
-- Config.REACT.flee's steps away and disappears.
Config.RUN_AWAY = { partTicks = 30, lungePx = 6 }

-- Idle wing-flap for floating/flying species: logic ticks each pose of the
-- walkA/stand/walkB/stand cycle is held (~1.3s per full cycle at 60 ticks/s).
Config.IDLE_FLAP_TICKS = 20

-- Follower action scenes (lib/follower_actions.lua), all in 60 Hz ticks / px.
-- Pet: its Idle loop (capped), then one cry. Talk: `cries` cries in a row.
-- Play: a thrown ball, the follower runs to it, spins, runs back.
Config.ACTIONS = {
  maxTicks = 900,           -- hard cap: no scene may hold the field lock longer
  play = {
    ballDist = 3,           -- cells the ball may fly (stops short of obstacles)
    throwTicks = 26,        -- ball flight; the player's arms-up pose lasts through it
    playerPoseTicks = 24,
    runSpeed = 1.6,         -- px per tick, out and back
    spinTicksPerFacing = 6, -- ticks per quarter turn
    spins = 2,              -- full circles
    arcHeight = 18,         -- px, peak of the ball's arc
  },
  pet = { idleSpeed = 1.5, maxIdleTicks = 90, minIdleTicks = 36 },
  talk = { cries = 2, gap = 8, cryTimeout = 90 },
}

-- Swapping the companion (lib/follower_swap.lua): all ticks / px.
Config.SWAP = {
  poseTicks = 26,    -- the player's arm-up pose, a Poke Ball in hand, per phase
  recallDelay = 10,  -- ticks of holding the ball up before the old one shrinks in
  sendDelay = 12,    -- ... before the new one grows out
  ballLift = 19,     -- px the ball is held above the player's feet
  ballX = 6,         -- px to the side: the raised hand
  maxTicks = 240,    -- hard cap: the scene may not hold the field lock longer
}

-- Battler role (lib/overworld_battle.lua): all ticks / px / cells.
Config.OW_BATTLE = {
  radius = 3,           -- a wild Pokemon this close to the PLAYER (cells) may be fought
  maxWalk = 8,          -- longest charge, in cells
  scanEvery = 12,       -- ticks between looks for a target (only while everything is still)
  cooldown = 90,        -- ticks of calm after a fight
  chainPause = 24,      -- after a win: ticks it stays put before going on to the next one in range
  chainSlack = 1,       -- a charge is called off once its target is radius + this from the player
  chaseSpeed = 2.4,     -- px per tick charging in / running back
  walkMul = 2,          -- how much faster its Walk animation plays while charging
  windup = 16,          -- ticks from the start of a turn to the blow landing
  turnTicks = 52,       -- one side's whole turn (1.5x the first pace: each attack reads clearly)
  fxScale = 1.75,       -- size of the move / hit / knockout effects (spread, rings, shapes, sheets)
  -- ...by the level of the Pokemon making them (straight lines between these points);
  -- fxScale above is the size when the level is not known
  fxScaleByLevel = { { 1, 1.15 }, { 15, 1.35 }, { 30, 1.5 }, { 50, 1.75 }, { 75, 2.0 }, { 100, 2.2 } },
  lunge = 7,            -- px the attacker leans toward its target
  flashTicks = 12,      -- red hit flash / hurt animation
  attackSpeed = 1.6,    -- animation rate of attack / hurt
  winPause = 36,        -- ticks the cry plays before the defeated Pokemon sinks
  sinkTicks = 40,       -- ... then it sinks into the ground over this long
  cryPause = 36,        -- the Battler's cry before it shrinks into the player
  recallTicks = 18,     -- shrinking in / growing back out (the PMD recall length)
  restCheck = 30,       -- ticks between "healed yet?" checks while resting
  popupTicks = 110,     -- "+EXP" label time
  expShare = 0.5,       -- fraction of the engine's EXP value a win is worth
  dropChance = 25,      -- % of knockouts that shake loose the wild Pokemon's held item (if it holds one)
  dropShowAt = 18,      -- ticks after the knockout before the dropped item glints on the ground
  resumeFrac = 0.25,    -- healed past this share of max HP (with PP) it may fight again
}

-- Forager role (lib/forager.lua, lib/forage_items.lua): all ticks / px / cells.
-- It only ever leaves the player's side for a find, and every trip finds something.
Config.FORAGE = {
  minSpread = 3,         -- the find is this many cells from the PLAYER ...
  maxSpread = 5,         -- ... to this many
  maxWalk = 12,          -- longest walk to it, in cells (round obstacles; the player keeps walking during the tell)
  -- one find per 1-3 minutes of WALKING (only counted where foraging is allowed). The wait
  -- leans long at low friendship and short at high: goal = min + (max - min) * r ^ e, with
  -- e = skewLow at friendship 0 rising to skewHigh at 255 (mean ~140 s -> ~90 s).
  intervalMin = 3600,
  intervalMax = 10800,
  skewLow = 0.5,
  skewHigh = 3.0,
  retryTicks = 60,       -- no spot / nothing that fits the bag yet: look again this much later
  -- map types it may forage on: 3 = route (outside), 4 = underground (caves). Towns,
  -- cities, buildings, water and secret bases are off limits.
  allowedMapTypes = { [3] = true, [4] = true },
  -- the tell: it stops and perks up (a sparkle shows where it is going), then dashes there;
  -- both get more eager with friendship
  perkMax = 45,          -- ticks of the tell at friendship 0 ...
  perkMin = 30,          -- ... down to this at 255
  forageSpeedMin = 2.2,  -- px per tick dashing out at friendship 0 ...
  forageSpeedMax = 3.0,  -- ... up to this at 255
  runSpeed = 2.8,        -- px per tick running back to the player
  digTicks = 90,         -- digging at the spot
  cryPause = 30,         -- after a common find: the cry, then this pause
  cryGap = 40,           -- a rare find cries twice, this far apart ...
  rarePause = 70,        -- ... and stays put this long (tier 3)
  rarePause4 = 90,       -- ... or this long (tier 4)
  popupTicks = 150,      -- the "Found X!" label (tiers 1-2) ...
  popupTicksRare = 240,  -- ... tier 3
  popupTicksTop = 300,   -- ... tier 4
  -- what it finds (lib/forage_items.lua): first a TIER by friendship, then an item in it.
  -- bands are MonMood.FRIENDSHIP_TIERS (0 Angry, 30 Sad, 70 Normal, 130 Happy, 200 Joyous,
  -- 255 Inspired); a tier below its gate never comes up.
  bands = { 0, 30, 70, 130, 200, 255 },
  tierBase = { 100, 35, 12, 3 },
  tierGate = { 0, 0, 130, 200 },
  tierMult = {             -- per band: { T1, T2, T3, T4 }
    { 1.00, 1.00, 0, 0 },  -- 0-29
    { 0.95, 1.10, 0, 0 },  -- 30-69
    { 0.90, 1.25, 0, 0 },  -- 70-129
    { 0.80, 1.35, 1.0, 0 },-- 130-199
    { 0.70, 1.40, 1.6, 1.0 }, -- 200-254
    { 0.60, 1.40, 2.6, 2.5 }, -- 255
  },
  evoTop = 3000,         -- an evolution item this dear (or dearer) is tier 4, else tier 3
  maxTmPrice = 3000,     -- TMs dearer than this are "high level" and never found
  blocklist = {},        -- extra item names to never find
}

-- The HGSS / PokeMMO swimming sheets are drawn SWIM_DROP px lower than usual, so they sit in
-- the water, not on it; PMD_SWIM_Y is the waterline a swimmer's effects (wakes, the recall)
-- measure from, PMD_SWIM_Y px below the tile's top edge.
Config.PMD_SWIM_Y = 18
Config.SWIM_DROP = 4
-- Ticks a walk keeps playing after movement stops, so the one-tick gaps between chained steps
-- do not flick the sprite to standing and back; PMD_WILD_IDLE_SPEED: how fast a wild
-- Pokemon's idle loop plays (0.75 = slowed down by 25%).
Config.PMD_WALK_LINGER = 8
Config.PMD_WILD_IDLE_SPEED = 0.75
-- Follower spacing (both sprite styles), from the art it shows the way it walks (px, as
-- drawn; lib/actor_renderer.lua followerPush). Walking down it trails ABOVE the player and its art
-- rises away from them: `down` px only. Walking up it trails below, drawn in front, its art
-- rising toward them: kept back until its top reaches at most `upOverlap` px above the
-- player's feet (it may cover their legs, never their head). Sideways: its overhang past
-- the tile, plus `side`.
Config.HGSS_FOLLOWER = { down = 0, upOverlap = 10, side = 0 }
-- Crouching (lib/follower_adapter.lua _tickDuck, never triggered on the Game Boy field, which
-- draws no eaves over characters): `ease` of the way each tick; while it crouches more than
-- `sweatFrom` it sweats (lib/sweat_drop.lua), up to `sweatMax` drops.
Config.FOLLOWER_DUCK = { nudge = 4, minScale = 0.5, widen = 0.15, ease = 0.2, sweatFrom = 0.03, sweatMax = 3 }

-- Follower interaction (lib/follower_interaction.lua, lib/interaction_limiter.lua).
-- All times are real seconds.
--   cooldown      gap needed since the last SUCCESSFUL use of that action
--   window / maxGains   at most `maxGains` successful interactions per rolling `window`
--   abuseWindow / abuseAttempts   this many selections (refused ones count)
--                 inside the window locks the menu
--   lockBase..lockMax   first lock length, doubled per repeat offence, capped
--   strikeReset   quiet time after which the repeat-offence count starts over
--   gain          friendship points for Play/Talk (Pet uses the engine's own
--                 MASSAGE friendship event, tier-aware, Soothe Bell etc. apply)
Config.INTERACT = {
  cooldown = { pet = 30, play = 45, talk = 15 },
  window = 600, maxGains = 6,
  abuseWindow = 45, abuseAttempts = 6,
  lockBase = 300, lockMax = 3600, strikeReset = 7200,
  gain = { play = 3, pet = 2, talk = 1 },
  petHealChance = 0.25, -- petting a Pokemon with a status condition: chance to cure it
}

-- Reachable-only spawns (lib/reachability.lua): visible wild Pokemon on LAND
-- appear only on cells the player can walk to from where they stand (ledges
-- hop one way; a Cut tree, rock or boulder blocks until the matching move is
-- usable). Surf plays no part: water Pokemon spawn on every lake and sea for
-- atmosphere, and land across the water fills in once the player is there.
-- The area is re-measured only when what it depends on changes (a tree cut, a
-- rock smashed, a boulder pushed, Cut / Rock Smash / Strength becoming usable):
-- checked every REACH_CHECK_TICKS, acted on once unchanged for REACH_SETTLE_TICKS
-- (a boulder puzzle's pushes cost one re-measure, after the player pauses).
-- REACH_REBUILD_TICKS: the plain timer used only if the engine hides its object
-- list (60 ticks = 1 s).
Config.REACHABLE_SPAWNS = true
Config.REACH_CHECK_TICKS = 60
Config.REACH_SETTLE_TICKS = 180
Config.REACH_REBUILD_TICKS = 900

-- PMDCollab follower while the player surfs (PMD has no swim art): it shrinks
-- into the player like a recall, and grows back out once on land. Duration of
-- the shrink/grow in ticks (60 = 1 s), and how far (px) it rises toward the
-- player's body as it goes in.
Config.PMD_RECALL_TICKS = 18
Config.PMD_RECALL_LIFT = 8


--- Reads and compiles options.lua fresh (not cached -- this only runs once
--- at boot) and hands the schema table to the Mod Manager. Same pattern as
--- Wilds of Kanto Revival's lib/config.lua: the manifest's
--- "options_schema" field is a hint for external tooling, not something
--- the engine auto-registers for a mod -- the mod must call
--- mod.options:define itself.
function Config.defineOptions(mod)
  local source = mod:read("options.lua")
  if not source then
    error("vivid_worlds_og: options.lua is missing", 0)
  end
  local loadcode = loadstring or load
  local chunk, err = loadcode(source, "@" .. mod.path .. "/options.lua")
  if not chunk then
    error(("vivid_worlds_og: options.lua did not compile: %s"):format(tostring(err)), 0)
  end
  local schema = chunk()
  Config.withoutUnsupported(schema)
  mod.options:define(schema)
end

-- Options whose systems the running generation's engine layer does not carry yet
-- (EnginePatch.supports; lib/gb/gen1.lua / lib/gb/gen2.lua FEATURES): main.lua lists them
-- before defining the options. A listed option is not offered and reads as off.
Config.UNSUPPORTED = {}
-- Always a Game Boy boot (Red / Blue / Yellow, Gold / Silver / Crystal).
Config.gbBoot = true

-- Species Sizes are tuned against the Gen 3 player (22 px from the ground to the top of
-- the head; the Scale Tool's PLAYER_PX). The Gen 1 / Gen 2 player is one 16 px tile, so a
-- Pokemon's size is scaled by 16 / 22 to keep the same size next to the player
-- (lib/voxel_sheets.lua: the 3D world mods' cards).
Config.GB_PLAYER_PX, Config.GEN3_PLAYER_PX = 16, 22

--- The size factor for the Game Boy player's height: 16 / 22.
function Config.gbSizeRatio()
  if not Config.gbBoot then return 1 end
  return Config.GB_PLAYER_PX / Config.GEN3_PLAYER_PX
end

--- Removes the rows of not-yet-supported systems from an option schema (in place).
function Config.withoutUnsupported(schema)
  for i = #schema, 1, -1 do
    if Config.UNSUPPORTED[schema[i].key] then table.remove(schema, i) end
  end
  return schema
end

local function optGet(mod, key)
  if Config.UNSUPPORTED[key] then return false end
  if mod and mod.options and type(mod.options.get) == "function" then
    local v = mod.options:get(key)
    if v ~= nil then return v end
  end
  return Config.DEFAULTS[key]
end

function Config.get(mod, key)
  return optGet(mod, key)
end

function Config.enabled(mod)
  return optGet(mod, "enabled") == true
end

--- The Sprite Style option: "pokemmo" (HGSS / PokeMMO at true size) or "followers" (Poke
--- Followers / GSC, with HGSS for any species it has no art for). Anything else (a stale
--- "pmd" from Wilds of Hoenn) reads as the default.
local VALID_SPRITE_STYLE = { pokemmo = true, followers = true }
function Config.spriteStyle(mod)
  local v = optGet(mod, "sprite_style")
  if VALID_SPRITE_STYLE[v] then return v end
  return Config.DEFAULTS.sprite_style
end

--- The Smooth Follow option: the follower is spaced out behind the player either way;
--- on, it glides to its place on a turn, off it snaps there. On unless switched off.
--- Removes the row `key` from an option schema (in place).
function Config.withoutRow(schema, key)
  for i = #schema, 1, -1 do
    if schema[i].key == key then table.remove(schema, i) end
  end
  return schema
end

--- The Type Aura option: a soft puff of your partner's type now and then (embers, droplets,
--- leaves ...). Off unless switched on.
function Config.typeAura(mod)
  return optGet(mod, "type_aura") == true
end

--- The Follower option: off keeps the partner in its ball (lib/follower_adapter.lua). Its
--- own key: the old "follower" toggle (removed in 1.2.0) may still be saved as false, and
--- reading it would hide the partner of a player who has had it out ever since.
function Config.followerOn(mod)
  return optGet(mod, "show_follower") ~= false
end

--- The controller button / keyboard key that switches the partner between Battle and
--- Follow in the overworld (lib/role_hotkey.lua): "l" / "r" / "off" and "q" / "e" / "r" /
--- "off". Anything else reads as its default.
local VALID_ROLE_PAD = { l = true, r = true, off = true }
local VALID_ROLE_KEY = { q = true, e = true, r = true, off = true }
function Config.rolePad(mod)
  local v = optGet(mod, "role_pad")
  return VALID_ROLE_PAD[v] and v or Config.DEFAULTS.role_pad
end
function Config.roleKey(mod)
  local v = optGet(mod, "role_key")
  return VALID_ROLE_KEY[v] and v or Config.DEFAULTS.role_key
end

function Config.smoothFollow(mod)
  return optGet(mod, "smooth_follow") ~= false
end

--- The Wild Reacts option: wild Pokemon flee from / chase a player running or biking
--- close by. On unless switched off.
function Config.wildReacts(mod)
  return optGet(mod, "wild_reacts") ~= false
end

--- The Water Life option: fish leaping, whales surfacing (lib/water_life.lua). On unless
--- switched off.
function Config.waterLife(mod)
  return optGet(mod, "water_life") ~= false
end

--- The Local Scenes option: little moments tied to a place (lib/local_scenes.lua). On
--- unless switched off.
function Config.localScenes(mod)
  return optGet(mod, "local_scenes") ~= false
end

function Config.classicEncEnabled(mod)
  return optGet(mod, "classic_enc") == true
end

--- The Spawn Amount option's density row ({ min, max, tilesPer }); Normal for
--- anything unknown.
function Config.spawnAmount(mod)
  local v = optGet(mod, "spawn_amount")
  return Config.SPAWN_AMOUNT[v] or Config.SPAWN_AMOUNT.normal, Config.SPAWN_AMOUNT[v] and v or "normal"
end

--- The Flying Mons option: birds in the sky, perching, and wild Flying-type Pokemon
--- arriving / leaving by air. On unless switched off.
--- The Flying Mons option: "full" (everything, the high birds too), "ambient" (no high
--- birds) or "off". A save from when it was an on / off toggle reads true -> full, false -> off.
function Config.flyersMode(mod)
  local v = optGet(mod, "flyers")
  if v == true then return "full" end
  if v == false then return "off" end
  if v == "full" or v == "ambient" or v == "off" then return v end
  return "full"
end

function Config.flyersOn(mod)
  return Config.flyersMode(mod) ~= "off"
end

--- The big blurred passers high overhead (lib/sky_flyers.lua): Flying Mons on Full only.
function Config.highBirdsOn(mod)
  return Config.flyersMode(mod) == "full"
end

local VALID_SILHOUETTE ={ off = true, undiscovered = true, all = true }
function Config.silhouetteMode(mod)
  local v = optGet(mod, "wild_silhouettes")
  if VALID_SILHOUETTE[v] then return v end
  return Config.DEFAULTS.wild_silhouettes
end

--- There is no Follower option any more: a companion is always out (who, and
--- what it does, is chosen from the party menu -- lib/companion.lua). Kept as a
--- function so the callers that ask stay one-liners.
function Config.followerEnabled(_mod)
  return true
end

return Config
