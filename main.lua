-- Vivid Worlds: OG (id: vivid_worlds_og): visible, reactive wild Pokemon for Red / Blue /
-- Yellow and Gold / Silver / Crystal, with a partner Pokemon that battles and forages.
--
-- Architecture
--   lib/engine_patch.lua    - the ONLY module touching the engine's world internals: the
--                             Game Boy engine layer (Gen 1 OverworldController, Gen 2 World),
--                             one API in front of lib/gb/gen1.lua and lib/gb/gen2.lua
--   lib/config.lua          - option defaults/getters, options.lua loader
--   lib/sprite_source.lua   - national dex -> HGSS sheet path; lib/sprite_atlas.lua serves them
--   lib/actor_renderer.lua  - the HGSS sheet draw, at each species' own size
--   lib/encounter_source.lua- per-map eligible cells + the map's wild tables
--   lib/behavior.lua        - Idle / Roam movement; lib/wild_reactions.lua the reactions
--   lib/spawn_manager.lua   - entity lifecycle (the mod's core state)
--   lib/battle_trigger.lua  - player-bump -> the engine's wild battle, same mon
--   lib/follower_adapter.lua- the partner's sprite on the engine's follower
--   lib/follower_interaction.lua - face the partner + A: Pet / Play / Talk, with emotes
--   lib/overworld_battle.lua- the Battler role; lib/forager.lua the Forager role
--   lib/voxel_sheets.lua + lib/compat/ - the 3D world mods' cards, at each species' size
--   options.lua             - Mod Manager option schema
--
-- Fail-safe: if EnginePatch.probe() finds any engine touch point has moved (a gen1recomp
-- update), this mod logs exactly what and installs nothing -- vanilla play is always the
-- fallback, never a crash.

return function(mod)
  local V = { mod = mod, path = mod.path }

  local function chunkFor(rel)
    local source = mod:read(rel)
    if not source then
      error(("vivid_worlds_og: %s is missing"):format(rel), 0)
    end
    local loadcode = loadstring or load
    local chunk, err = loadcode(source, "@" .. mod.path .. "/" .. rel)
    if not chunk then
      error(("vivid_worlds_og: %s did not compile: %s"):format(rel, tostring(err)), 0)
    end
    return chunk
  end

  local modules = {}
  function V.require(name)
    local hit = modules[name]
    if hit ~= nil then return hit end
    local value = chunkFor("lib/" .. name .. ".lua")(V)
    modules[name] = value
    return value
  end

  local Config = V.require("config")
  local HdField = V.require("hd_field")
  local EnginePatch = V.require("engine_patch")
  local SpriteAtlas = V.require("sprite_atlas")
  local SpawnFilters = V.require("spawn_filters")
  local SpawnManager = V.require("spawn_manager")
  local BattleTrigger = V.require("battle_trigger")
  local FollowerAdapter = V.require("follower_adapter")
  local PartnerEmote = V.require("partner_emote")
  local FollowerInteraction = V.require("follower_interaction")
  local GbFriendship = V.require("gb_friendship")
  local Companion = V.require("companion")
  local LevelReady = V.require("level_ready")
  local HolderReady = V.require("holder_ready")
  local Forager = V.require("forager")
  local ForageSource = V.require("forage_source")
  local OverworldBattle = V.require("overworld_battle")
  local PartyRoles = V.require("party_roles")
  local ModernSpawns = V.require("modern_spawns_bridge")

  -- the systems this generation's engine layer carries (lib/gb/gen1.lua / gen2.lua FEATURES)
  local function supported(feature)
    return EnginePatch.supports and EnginePatch.supports(feature) == true
  end
  if not supported("wild_reacts") then Config.UNSUPPORTED.wild_reacts = true end
  Config.defineOptions(mod)

  -- The engine's follower npc is built with the SPRITE_PIKACHU record (PikachuFollower /
  -- gen2/Follower.lua), which Red and Blue do not have (Yellow and Gold do): register a
  -- placeholder -- the player's own sheet -- while the registry is open (load phase).
  -- FollowerAdapter puts our renderer on the npc the first tick it is out.
  if mod.content and mod.content.sprites then
    pcall(function()
      local sprites = mod.content.sprites
      local okGet, have = pcall(sprites.get, sprites, "SPRITE_PIKACHU")
      if okGet and have then return end
      local okRed, red = pcall(sprites.get, sprites, "SPRITE_RED")
      sprites:register("SPRITE_PIKACHU", {
        id = "SPRITE_PIKACHU",
        image = okRed and type(red) == "table" and red.image or "assets/generated/sprites/red.png",
        frames = 6, walker = true,
      })
    end)
  end
  HdField.setSpeciesSizes(Config.get(mod, "species_sizes"))

  -- Pure asset I/O, no engine dependency. A repo checkout or --no-atlas build has no
  -- assets/atlas/ index, so this is a normal, silent false everywhere except a release ZIP
  -- built with the atlas (scripts/build-mod.py's default mode).
  local atlasOk, atlasReason = SpriteAtlas.install(mod)
  mod.log:info("[vivid_worlds_og] sprite atlas: %s", atlasOk and "installed" or tostring(atlasReason))

  mod.exports = mod.exports or {}
  mod.exports.version = "0.0.1"
  mod.exports.engineReady = false
  mod.exports.spriteAtlas = SpriteAtlas
  mod.exports.enginePatch = EnginePatch
  mod.exports.hdField = HdField
  -- species swaps from other mods, applied when a visible Pokemon is rolled so the one you
  -- see is the one you fight (lib/spawn_filters.lua)
  mod.exports.addSpawnFilter = SpawnFilters.add
  mod.exports.removeSpawnFilter = SpawnFilters.remove

  local layout = EnginePatch.layoutName()
  if not layout then
    mod.log:info("[vivid_worlds_og] not a game this mod knows -- installing nothing")
    return
  end
  mod.exports.layout = layout

  -- Wilds of Hoenn's Game Boy build (its retired feature/allgens branch) does the same job:
  -- never both at once. (Not a manifest conflict: the Mod Manager's conflict checks ignore
  -- `games`, so it would also flag Wilds of Hoenn on Gen 3, where nothing overlaps.)
  if type(mod.find) == "function" then
    local okFind, other = pcall(mod.find, mod, "wilds_of_hoenn")
    if okFind and other then
      mod.log:warn("[vivid_worlds_og] Wilds of Hoenn is running on this game too -- installing nothing")
      return
    end
  end

  local ok, missing = EnginePatch.probe()
  if not ok then
    mod.log:warn("[vivid_worlds_og] engine probe failed, visible spawns disabled:")
    for _, m in ipairs(missing) do
      mod.log:warn("[vivid_worlds_og]   missing: %s", m)
    end
    return
  end

  local spawnManager = SpawnManager.new(mod)
  local battleTrigger = BattleTrigger.new(mod, spawnManager, mod.log)
  -- a wild Pokemon chasing the player catches up (lib/wild_reactions.lua): the battle
  spawnManager.onContact = function(e) battleTrigger:onChaserContact(e) end
  -- a GB mon has no personality: EnginePatch.monIdentity keys it instead
  local companion = Companion.new(mod, EnginePatch.monIdentity)
  local partyRoles = PartyRoles.new(companion)
  local followerAdapter = FollowerAdapter.new(mod, companion)
  -- what a levelled-up companion is waiting for ("New move ready!" / "Ready to evolve!")
  local levelReady = LevelReady.new(mod, {
    movesLearnedAt = EnginePatch.movesLearnedAt, knowsMove = EnginePatch.knowsMove,
    evolutionTarget = EnginePatch.evolutionTarget,
    identityOf = EnginePatch.monIdentity,
  })
  followerAdapter.levelReady = levelReady
  -- the partner's mood while you talk to it: an emote over its head, no portrait
  local partnerEmote = PartnerEmote.new(mod)
  local followerInteraction = FollowerInteraction.new(mod, partnerEmote, {
    isAway = function() return followerAdapter:isRecalled() end, -- shrunk into the player
    adapter = followerAdapter, -- acts the menu choices out (lib/follower_actions.lua)
    companion = companion,
    levelReady = levelReady,
  })
  -- an Exp. Share holder that levels up from the Battler's wins is not out on the field:
  -- its evolution / move screens open by themselves once the fight is over and the game is free
  local holderReady = HolderReady.new(levelReady, {
    canOpen = function()
      if not EnginePatch.gameFree() or (EnginePatch.uiBusy and EnginePatch.uiBusy())
        or EnginePatch.isMessageOpen() then return false end
      if followerInteraction:isActive() then return false end
      local b = followerAdapter.behaviors and followerAdapter.behaviors.battle
      return not b or b.mode == "idle" or b.mode == "between"
    end,
    partyMons = EnginePatch.partyMons, evolutionTarget = EnginePatch.evolutionTarget,
    startEvolution = EnginePatch.startEvolution, startMoveLearn = EnginePatch.startMoveLearn,
    screenBusy = EnginePatch.screenBusy,
  })

  followerAdapter.interaction = followerInteraction -- its mood effects while you talk (lib/mood_fx.lua)

  mod.exports.spawnManager = spawnManager
  mod.exports.battleTrigger = battleTrigger
  mod.exports.followerAdapter = followerAdapter
  mod.exports.partnerEmote = partnerEmote
  mod.exports.followerInteraction = followerInteraction
  mod.exports.companion = companion
  mod.exports.levelReady = levelReady
  mod.exports.holderReady = holderReady

  -- the Battler hotkey (lib/role_hotkey.lua): one button / key flips the partner between
  -- Battle and Follow in the overworld, swallowing the press only when it acts
  local RoleHotkey = V.require("role_hotkey")
  local roleHotkey = RoleHotkey.new({
    padChoice = function() return Config.rolePad(mod) end,
    keyChoice = function() return Config.roleKey(mod) end,
    free = function()
      if not EnginePatch.gameFree() then return false end
      return not (EnginePatch.uiBusy and EnginePatch.uiBusy())
    end,
    current = function()
      local party = EnginePatch.partyMons and EnginePatch.partyMons()
      if type(party) ~= "table" then return nil end
      local mon, role = companion:resolve(party)
      return mon, role
    end,
    set = function(mon, role) return companion:set(mon, role) end,
    nameOf = function(mon) return EnginePatch.displayName(mon) end,
    -- the player calls it out, in a two-line bubble over their head
    notify = function(text)
      followerAdapter:notify(V.require("popup_text").twoLines(text), { onPlayer = true })
    end,
    sound = function() EnginePatch.playSelect() end,
  })
  mod.exports.roleHotkey = roleHotkey
  if supported("roles") then
    mod.hooks:wrap("input.key", function(next, game, ev)
      local okKey, mine = pcall(roleHotkey.onKey, roleHotkey, ev)
      if okKey and mine then return true end
      return next(game, ev)
    end)
    mod.hooks:wrap("input.gamepad", function(next, game, ev)
      local okPad, mine = pcall(roleHotkey.onPad, roleHotkey, ev)
      if okPad and mine then return true end
      return next(game, ev)
    end)
  end

  -- Forage role: wanders on open cells near the player and bags what it finds
  local forageSource = ForageSource.new(mod)
  local forager = Forager.new({
    cellFree = EnginePatch.cellFree,
    occupied = function(x, y) return spawnManager:blocksCell(x, y) end,
    -- the find is rolled before it sets out (so a trip never comes back empty)
    -- and only bagged once it has dug it up
    rollItem = function(friendship) return forageSource:roll(friendship) end,
    commitItem = function(rolled) return forageSource:commit(rolled) end,
    elevation = EnginePatch.playerElevation,
    playCry = EnginePatch.playCry, -- the cry that tells the player it is foraging
    playFound = EnginePatch.playSuccess,
  })
  followerAdapter.behaviors.forage = forager
  mod.exports.forageSource = forageSource -- what it can find (tests and tools)
  mod.exports.forager = forager

  -- Battle role: charges wild overworld Pokemon near the player, real moves / PP
  local battler = OverworldBattle.new({
    combat = {
      battlerOf = EnginePatch.battlerOf, moveRow = EnginePatch.moveRow,
      moveDamage = EnginePatch.moveDamage, moveNumber = EnginePatch.moveNumber,
      expGain = EnginePatch.expGain, expApply = EnginePatch.expApply,
      buildWild = EnginePatch.buildWildFighter, rng = math.random,
    },
    targets = function() return spawnManager:fightTargets() end,
    alive = function(e) return spawnManager:get(e.id) == e end,
    cellFree = EnginePatch.cellFree,
    swimFree = EnginePatch.waterFree,
    occupied = function(x, y) return spawnManager:blocksCell(x, y) end,
    defeat = function(id) spawnManager:despawn(id) end,
    -- its fight called off mid-way (a job change): the wild Pokemon runs off and disappears
    runAway = function(e) return spawnManager:runAway(e) end,
    chainRecord = ModernSpawns.chainRecord,
    playCry = EnginePatch.playCry,
    -- the knockout's sound (lib/finisher_fx.lua), at the game's SFX volume
    playSe = EnginePatch.playSeNamed,
    -- a knockout can shake loose the wild Pokemon's real held item (the game's own roll)
    heldItem = EnginePatch.wildHeldItem, itemName = EnginePatch.itemName,
    bagAdd = EnginePatch.bagAdd, bagCanAdd = EnginePatch.bagCanAdd,
    playFound = EnginePatch.playSuccess,
    levelUp = function(mon, from, to, holder)
      levelReady:record(mon, from, to)
      if holder then holderReady:push(mon) end -- not out on the field: its screens open by themselves
    end,
    -- an Exp. Share holder takes its share of a win, as in a real battle
    partyMons = EnginePatch.partyMons, holdsExpShare = EnginePatch.holdsExpShare,
    displayName = EnginePatch.displayName,
    expFrozen = function(mon) return levelReady:pending(mon) ~= nil end,
    rng = math.random,
  })
  followerAdapter.behaviors.battle = battler
  mod.exports.battler = battler

  local installed = EnginePatch.install({
    collectActors = function(actors, camX, camY)
      spawnManager:collectActors(actors, camX, camY)
      followerAdapter:collectActors(actors)
    end,
    messageDraw = function() end, -- no portraits: the partner's emote is a field actor
    -- Runs BEFORE the engine's A-button handler: facing your partner and pressing A
    -- opens its Pet / Play / Talk menu instead (true = handled).
    interact = function(game)
      return followerInteraction:tryStart(game)
    end,
    followerTick = function(game)
      spawnManager:tick(game)
      if supported("interaction") then followerInteraction:tick(game) end
      holderReady:tick()
      battleTrigger:tick()
      battleTrigger:checkContact()
      followerAdapter:tick()
    end,
  }, mod.log)

  if not installed then
    mod.log:warn("[vivid_worlds_og] EnginePatch.install reported failure after a passing probe")
    return
  end

  mod.exports.engineReady = true

  -- A 3D world mod (TERRARIUM, Battle Art, Potato Voxel, Dramaless, Stadium2) draws the world from engine
  -- sprites: our Pokemon go in as sheets baked from their own art (lib/voxel_sheets.lua), on
  -- cards of their own size (lib/compat/: one adapter per provider over one shared
  -- SpriteBillboards wrap)
  local VoxelSheets = V.require("voxel_sheets")
  local ActorRenderer = V.require("actor_renderer")
  local SpriteSource = V.require("sprite_source")
  local okAssets, Assets = pcall(require, "src.render.Assets")
  EnginePatch.voxelSheets = VoxelSheets.new({
    assets = okAssets and Assets or nil,
    poses = { STAND = ActorRenderer.POSE_STAND, WALK_A = ActorRenderer.POSE_WALK_A,
      WALK_B = ActorRenderer.POSE_WALK_B },
    makeRenderer = function(key, shiny, style)
      return V.require("renderer_factory").new(mod, key, shiny, style, SpriteSource.PRESENTATION_LAND)
    end,
  })
  local VOXEL_ADAPTERS = {
    "compat/terrarium_variable_geometry", "compat/potato_voxel_variable_geometry",
    "compat/dramaless_variable_geometry", "compat/stadium2_variable_geometry",
    -- Battle Art keeps its own two (Wilds of Kanto Revival's): Gen 2's places cards by its halfWidth
    "compat/battle_art_variable_geometry", "compat/battle_art_gen2_geometry",
  }
  -- each adapter installs only when its provider is loaded (absent -> nothing)
  local function voxelAdapters()
    for _, name in ipairs(VOXEL_ADAPTERS) do
      pcall(function() V.require(name).install(mod) end)
    end
  end
  mod.events:on("mods.loaded", voxelAdapters)
  mod.events:on("game.ready", voxelAdapters)

  -- Collision is a public hook: a wild Pokemon blocks NPCs, never the player stepping onto
  -- it (lib/engine_patch.lua collisionVerdict)
  mod.hooks:wrap("movement.collision", function(next, allowed, ctx)
    local base = next(allowed, ctx)
    local okVerdict, out = pcall(EnginePatch.collisionVerdict, base, ctx, function(x, y)
      return spawnManager:entityAt(x, y)
    end)
    if okVerdict then return out end
    return base
  end)
  -- the field's battle state
  mod.events:on("battle.started", function() EnginePatch.noteBattle(true) end)
  mod.events:on("battle.ended", function() EnginePatch.noteBattle(false) end)

  -- the ROLE row in the party menu: the engine's own `ui.party.submenu` hook hands the
  -- A-list over (lib/party_roles.lua gbRows)
  if supported("roles") then
    mod.hooks:wrap("ui.party.submenu", function(next, _game, _items, mon, ctx)
      local items = next()
      local okRows, rows = pcall(function() return partyRoles:gbRows(items, mon, ctx) end)
      return (okRows and type(rows) == "table") and rows or items
    end)
  end

  mod.events:on("map.entered", function(ev)
    local okMap, err = pcall(function()
      -- the world that loaded this map, before the spawns read it
      if EnginePatch.noteMap then EnginePatch.noteMap(mod.world and mod.world.game, ev and ev.map) end
      spawnManager:onMapEntered(ev and ev.mapId, mod.world and mod.world.game)
      followerAdapter:mapChanged()
    end)
    if not okMap then
      mod.log:warn("[vivid_worlds_og] map.entered error: %s", tostring(err))
    end
  end)

  -- Gen 1 keeps no friendship stat: the mod keeps its own per-mon value
  -- (lib/gb_friendship.lua; Yellow's starter Pikachu uses the game's own happiness byte),
  -- served through EnginePatch.friendshipOf / setFriendship, raised slowly by walking.
  local gbFriendship
  if EnginePatch.setFriendshipStore then
    gbFriendship = GbFriendship.new(mod, function()
      local a = EnginePatch.adapter and EnginePatch.adapter()
      return a and a.save and a.save()
    end)
    EnginePatch.setFriendshipStore(gbFriendship)
  end

  -- The interaction limiter's saved state is per playthrough: re-read it whenever a
  -- different save/checkpoint becomes current.
  for _, eventName in ipairs({ "save.loaded", "save.created", "checkpoint.restored" }) do
    mod.events:on(eventName, function()
      pcall(function() followerInteraction:onSaveChanged() end)
      if gbFriendship then pcall(function() gbFriendship:reset() end) end
      pcall(function() companion:reset() end)
      pcall(function() levelReady:reset() end)
      pcall(function() holderReady:reset() end)
      pcall(function() forageSource:reset() end)
      pcall(function() followerAdapter:resetBehaviors() end)
      pcall(function() followerAdapter:resetDisplay() end)
    end)
  end

  -- A finished step is the contact signal (see lib/battle_trigger.lua): walking through a
  -- wild Pokemon with the direction held must still battle it.
  mod.events:on("world.stepped", function(ev)
    pcall(function()
      battleTrigger:onPlayerStepped(ev and ev.x, ev and ev.y)
    end)
    if gbFriendship then
      pcall(function() gbFriendship:onStep(EnginePatch.leadPartyMon and EnginePatch.leadPartyMon()) end)
    end
  end)

  mod.events:on("map.exited", function(_ev)
    pcall(function() spawnManager:onMapExited() end)
  end)

  -- Classic Encounters: while OFF, the step encounters in grass, caves and on Surf are
  -- suppressed. Gen 1 only rolls steps through encounter.roll (its ctx has no kind); Gen 2
  -- also rolls the Bug-Catching Contest ("contest"), Sweet Scent ("sweet_scent") and
  -- `randomwildmon` scripts ("script") through it, which stay vanilla. Fishing never
  -- comes through here.
  mod.hooks:wrap("encounter.roll", function(next, _tables, ctx)
    local kind = type(ctx) == "table" and ctx.kind or nil
    if (kind == nil or kind == "wild") and not Config.classicEncEnabled(mod) then return nil end
    return next()
  end)

  -- Party follower: the engine's public seam, no patching needed.
  mod.hooks:wrap("world.follower.spawn", function(_next, _game, _world)
    return followerAdapter:shouldSpawn()
  end)

  mod.events:on("mod.options_changed", function(ev)
    if not (ev and ev.mod == mod.id) then return end
    if ev.key == "enabled" then
      local current = mod.world and mod.world:current()
      local mapId = current and current.mapId
      if ev.value == true and mapId then
        spawnManager:onMapEntered(mapId, mod.world and mod.world.game)
      elseif ev.value ~= true then
        spawnManager:onMapExited()
      end
    elseif ev.key == "spawn_amount" then
      -- raised: refill tops up on the next tick; lowered: the extras go now
      pcall(function() spawnManager:trimToAmount() end)
    elseif ev.key == "wild_reacts" then
      if ev.value == false then pcall(function() spawnManager:calmReactions() end) end
    elseif ev.key == "species_sizes" then
      HdField.setSpeciesSizes(ev.value)
    elseif ev.key == "sprite_style" then
      -- re-point every wild Pokemon's renderer now (the partner follows on its next tick)
      pcall(function() spawnManager:refreshSpriteStyle() end)
    end
  end)
end
