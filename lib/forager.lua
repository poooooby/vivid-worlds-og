-- The Forager role: the companion sniffs out items while the player walks.
--
-- It only ever leaves the player's side for a find, and every trip finds
-- something. It counts the player's STEPS (each new cell they reach) on the maps
-- where steps count -- towns, routes and caves, never a building, the water or
-- the sea: the adapter says so in `env.countOk`. Every 20 steps it sniffs the
-- air (the hint: the game's "?" over its head). After 60 steps the find is
-- ROLLED (an item that fits the bag; rarer ones need more friendship,
-- lib/forage_items.lua) and a spot 3-5 cells from the player is picked -- only
-- where it may dig (a route or a cave, `env.forageOk`): a find that comes due
-- in a town waits for the next one. Then:
--   perk    it stops and perks up (an alert bounce, shorter the fonder it is);
--           a glint appears on the spot (lib/forage_sparkle.lua) ->
--   out     it dashes there (faster the fonder it is), cell by cell round
--           obstacles ->
--   dig     it digs; the find goes into the bag ->
--   react   "Found X!", the found sound and its cry. A rare find (tier 3 / 4)
--           gets a second cry, a longer label and a happy bounce ->
--   back    it runs back to within a tile of the player -> near.
-- No spot or nothing that fits the bag yet: it simply tries again a second
-- later (there is no such thing as a failed trip). A trip that has begun is
-- finished even if the player stops; a map change cancels it but keeps the
-- steps (so the next allowed map starts it at once).
--
-- All motion is the same cosmetic draw-time offset the follower scenes and the
-- Battler use (the engine owns the follower's real position). The Forager keeps
-- its WORLD pixel position (`wx`, `wy`) and reports it as an offset from where
-- the follower is drawn, in the shared state shape:
--   { dx, dy, facing, moving, walkMul, bounce, idleSpeed, popup = { text, age } }
-- Pure: every engine fact (open cells, the cry, the roll and the bag) is injected
-- through `deps`.
local V = ...
-- this mod's translations (lib/i18n.lua); English when it cannot be loaded (a bare test)
local I18n
if type(V) == "table" and V.require then
  local okI, mod = pcall(V.require, "i18n")
  if okI and type(mod) == "table" then I18n = mod end
end
local function tr(english, ...)
  if I18n then return I18n.t(english, ...) end
  if select("#", ...) > 0 then return string.format(english, ...) end
  return english
end
local function trc(context, english, ...)
  if I18n then return I18n.tc(context, english, ...) end
  if select("#", ...) > 0 then return string.format(english, ...) end
  return english
end
local Config = V.require("config")
local CellPath = V.require("cell_path")
local ForageSparkle = V.require("forage_sparkle")

local Forager = {}
Forager.__index = Forager

local CELL = 16

--- deps = {
---   cellFree(x, y) -> bool        a creature can stand there (dry, walkable, empty)
---   occupied(x, y) -> bool        optional: something of ours is there (a wild Pokemon)
---   rng() -> [0,1)                optional
---   rollItem(friendship) -> roll  the find, NOT yet bagged ({ name, tier, ... }), or nil
---   commitItem(roll) -> got       bag it; returns what was bagged ({ name, tier }) or nil
---   playCry(species)              optional: its cry when it finds something
---   playFound()                   optional sound
---   elevation() -> n              optional: for the glint actor
---   hintActor(age, wx, wy, renderer) -> actor   optional: the hint over its head (the tile
---                                 it is drawn on at world px (wx, wy); `renderer` its
---                                 renderer, for the height of its head)
---   cfg                           optional (Config.FORAGE)
--- }
function Forager.new(deps)
  local self = setmetatable({ deps = deps or {} }, Forager)
  self.cfg = self.deps.cfg or Config.FORAGE
  self:reset()
  return self
end

function Forager:_rng()
  return self.deps.rng and self.deps.rng() or math.random()
end

local function lerp(a, b, x) return a + (b - a) * x end

local function closeness(friendship)
  return math.max(0, math.min(255, tonumber(friendship) or 0)) / 255
end

-- the trip in progress, and anything shown for it, is dropped
function Forager:_clearTrip()
  self.mode, self.t = "near", 0
  self.wx, self.wy, self.dx, self.dy = nil, nil, 0, 0
  self.facing, self.path, self.idx = nil, nil, 0
  self.rolled, self.spot, self.sparkleAge = nil, nil, 0
  self.popup, self.popupAge = nil, 0
  self.hintAge = nil
  self.lastPx, self.lastPy = nil, nil -- (the next tick only notes where the player is)
end

--- Back to trotting beside the player (role change, save load): the count starts over.
function Forager:reset()
  self:_clearTrip()
  self.steps, self.retry = 0, 0
end

--- A new map: the trip in progress is cancelled (the places it knew are gone) but
--- the steps carry on.
function Forager:mapChanged()
  self:_clearTrip()
  self.retry = 0
end

--- Away from the player's side (the follower menu must not open on it then)?
function Forager:isBusy()
  return self.mode ~= "near" or self.dx ~= 0 or self.dy ~= 0
end

--- Steps until the next find: Config.FORAGE.stepsPerFind, the same for every Pokemon
--- (friendship decides what it finds and how eagerly it goes, not how often).
function Forager:goal()
  return self.cfg.stepsPerFind or 60
end

-- One tick of the step count: a step is the player reaching a new cell (a ledge hop
-- too); a jump further than that (a warp) is no step. Counted only where `countOk`;
-- every `hintEvery` steps short of the find starts the hint.
function Forager:_countStep(env)
  local px, py, lx, ly = env.px, env.py, self.lastPx, self.lastPy
  self.lastPx, self.lastPy = px, py
  if not (lx and px and py) or (px == lx and py == ly) then return end
  if math.max(math.abs(px - lx), math.abs(py - ly)) > 2 then return end
  local countOk = env.countOk
  if countOk == nil then countOk = env.forageOk ~= false end
  if not countOk then return end
  self.steps = self.steps + 1
  local every = self.cfg.hintEvery
  if every and every > 0 and self.mode == "near" and self.steps % every == 0 and self.steps < self:goal() then
    self.hintAge = 0
  end
end

-- ------------------------------------------------------------ helpers

local function cheb(ax, ay, bx, by)
  return math.max(math.abs(ax - bx), math.abs(ay - by))
end

local function cellOf(w) return math.floor(w / CELL + 0.5) end

-- Moves (wx, wy) toward (tx, ty) by at most `speed` px, one axis at a time.
-- Returns true on arrival.
function Forager:_moveTo(tx, ty, speed)
  local ddx, ddy = tx - self.wx, ty - self.wy
  if ddx == 0 and ddy == 0 then return true end
  if ddx ~= 0 then
    self.wx = self.wx + math.max(-speed, math.min(speed, ddx))
    self.facing = ddx > 0 and "right" or "left"
  else
    self.wy = self.wy + math.max(-speed, math.min(speed, ddy))
    self.facing = ddy > 0 and "down" or "up"
  end
  return self.wx == tx and self.wy == ty
end

local function state(self, env, t)
  t.dx, t.dy = self.wx - env.fpx, self.wy - env.fpy
  self.dx, self.dy = t.dx, t.dy
  t.facing = t.facing or self.facing
  if self.popup then t.popup = { text = self.popup, age = self.popupAge } end
  return t
end

function Forager:_free(x, y)
  local deps = self.deps
  return deps.cellFree(x, y) and not (deps.occupied and deps.occupied(x, y))
end

-- ------------------------------------------------------------ planning

-- A spot `minSpread`..`maxSpread` cells from the player (Chebyshev) that can be
-- walked to from where the Pokemon is: the path there, or nil.
function Forager:_findSpot(env)
  local cfg = self.cfg
  local res = CellPath.search(cellOf(self.wx), cellOf(self.wy), {
    maxDepth = cfg.maxWalk,
    free = function(x, y) return self:_free(x, y) end,
    within = function(x, y) return cheb(x, y, env.px, env.py) <= cfg.maxSpread + 3 end,
  })
  local spots = {}
  for _, c in ipairs(res.order) do
    local d = cheb(c[1], c[2], env.px, env.py)
    if d >= cfg.minSpread and d <= cfg.maxSpread then spots[#spots + 1] = c end
  end
  if #spots == 0 then return nil end
  local pick = spots[math.floor(self:_rng() * #spots) + 1] or spots[#spots]
  local path = CellPath.pathTo(res, pick[1], pick[2])
  if not path or #path == 0 then return nil end
  return path
end

-- The way from where it stands to the spot it chose (re-planned after the tell:
-- the follower kept walking under it), or nil when it can no longer get there.
function Forager:_pathToSpot()
  local spot = self.spot
  local res = CellPath.search(cellOf(self.wx), cellOf(self.wy), {
    maxDepth = self.cfg.maxWalk,
    free = function(x, y) return (x == spot.x and y == spot.y) or self:_free(x, y) end,
  })
  local path = CellPath.pathTo(res, spot.x, spot.y)
  if path and #path == 0 then path = { { spot.x, spot.y } } end
  return path
end

-- A way back to the player's side: the open cells from where it stands to the
-- follower's own cell (the last leg is a straight run).
function Forager:_planBack(env)
  local res = CellPath.search(cellOf(self.wx), cellOf(self.wy), {
    maxDepth = self.cfg.maxWalk * 2,
    free = function(x, y) return (x == env.fx and y == env.fy) or self:_free(x, y) end,
  })
  local path = CellPath.pathTo(res, env.fx, env.fy)
  self.path, self.idx = path or {}, 1
end

function Forager:_goBack(env)
  self.mode, self.t = "back", 0
  self.spot = nil
  self:_planBack(env)
end

-- ------------------------------------------------------------ the tick

--- One field tick. `env` = { still = player and follower standing still, fx, fy =
--- the follower's cell, fpx, fpy = where it is drawn (px), px, py = the player's
--- cell, mon = the Pokemon, friendship = 0-255, forageOk = it may dig here,
--- countOk = steps count here (nil: as forageOk), renderer }. Returns the state to
--- draw, or nil while it simply trots beside the player.
function Forager:step(env)
  env = env or {}
  if not (env.fpx and env.px) then return nil end
  self.env = env
  local allowed = env.forageOk ~= false
  local active = not env.still and allowed -- walking, somewhere it may work
  if not self.wx then self.wx, self.wy = env.fpx, env.fpy end
  self.t = self.t + 1
  self:_countStep(env)
  if self.hintAge then
    self.hintAge = self.hintAge + 1
    if self.hintAge >= (self.cfg.hintTicks or 60) then self.hintAge = nil end
  end
  if self.retry > 0 then self.retry = self.retry - 1 end
  if self.spot then self.sparkleAge = self.sparkleAge + 1 end

  if self.popup then
    self.popupAge = self.popupAge + 1
    if self.popupAge >= (self.popupFor or self.cfg.popupTicks) then self.popup = nil end
  end

  local handler = self["_mode_" .. self.mode]
  return handler(self, env, active)
end

function Forager:_mode_near(env, active)
  local cfg = self.cfg
  self.wx, self.wy = env.fpx, env.fpy
  self.dx, self.dy, self.facing = 0, 0, nil
  if active and self.retry <= 0 then
    local goal = self:goal()
    if self.steps >= goal then
      local path = self:_findSpot(env)
      local rolled = path and self.deps.rollItem and self.deps.rollItem(env.friendship) or nil
      if not (path and rolled) then
        self.retry = cfg.retryTicks or 60 -- nowhere to go / nothing fits the bag yet: no trip
      else
        local last = path[#path]
        self.rolled, self.tripGoal, self.hintAge = rolled, goal, nil
        self.spot, self.sparkleAge = { x = last[1], y = last[2] }, 0
        self.closeness = closeness(env.friendship)
        self.perkFor = math.floor(lerp(cfg.perkMax or 45, cfg.perkMin or 30, self.closeness) + 0.5)
        local ddx, ddy = last[1] * CELL - self.wx, last[2] * CELL - self.wy
        if math.abs(ddx) >= math.abs(ddy) then
          self.facing = ddx >= 0 and "right" or "left"
        else
          self.facing = ddy >= 0 and "down" or "up"
        end
        self.mode, self.t = "perk", 0
        return self:_mode_perk(env)
      end
    end
  end
  if self.popup then return state(self, env, { moving = false }) end
  return nil
end

-- the tell: it stops where it is (the follower walks on under it) and perks up
function Forager:_mode_perk(env)
  if self.t >= self.perkFor then
    local path = self:_pathToSpot()
    if path then
      self.path, self.idx = path, 1
      self.mode, self.t = "out", 0
      return self:_mode_out(env)
    end
    -- the spot can no longer be reached: drop it quietly and try again later
    self.rolled = nil
    self.retry = self.cfg.retryTicks or 60
    self:_goBack(env)
    return self:_mode_back(env)
  end
  return state(self, env, { moving = false, bounce = true, idleSpeed = 2 })
end

function Forager:_mode_out(env)
  local cfg = self.cfg
  local speed = lerp(cfg.forageSpeedMin or 2.2, cfg.forageSpeedMax or 3.0, self.closeness or 0)
  local c = self.path[self.idx]
  if self:_moveTo(c[1] * CELL, c[2] * CELL, speed) then
    if self.idx >= #self.path then
      self.mode, self.t = "dig", 0
    else
      self.idx = self.idx + 1
    end
  end
  return state(self, env, { moving = true, walkMul = 2 })
end

function Forager:_mode_dig(env)
  local cfg = self.cfg
  if self.t >= cfg.digTicks then
    local got = self.deps.commitItem and self.deps.commitItem(self.rolled) or nil
    self.rolled, self.spot = nil, nil
    if got then
      local tier = tonumber(got.tier) or 1
      self.popup, self.popupAge = tr("Found %s!", tostring(got.name)), 0
      self.popupFor = tier >= 4 and (cfg.popupTicksTop or 300)
        or tier == 3 and (cfg.popupTicksRare or 240) or cfg.popupTicks
      if self.deps.playFound then self.deps.playFound() end
      if self.deps.playCry and env.mon then self.deps.playCry(env.mon.species) end
      self.reactTier, self.cries = tier, 1
      -- the next find: the steps walked past this one carry over
      self.steps = math.max(0, self.steps - (self.tripGoal or 0))
      self.mode, self.t = "react", 0
      return state(self, env, { moving = false })
    end
    -- the bag filled while it was out: nothing to show, it just comes back
    self.retry = cfg.retryTicks or 60
    self:_goBack(env)
    return self:_mode_back(env)
  end
  return state(self, env, { moving = false, bounce = true, idleSpeed = 1.5 })
end

-- it found something: the cry (twice and a happy bounce for a rare find), a moment, then back
function Forager:_mode_react(env)
  local cfg = self.cfg
  local tier = self.reactTier or 1
  local rare = tier >= 3
  if rare and self.cries < 2 and self.t >= (cfg.cryGap or 40) then
    self.cries = 2
    if self.deps.playCry and env.mon then self.deps.playCry(env.mon.species) end
  end
  local pause = tier >= 4 and (cfg.rarePause4 or 90) or rare and (cfg.rarePause or 70) or cfg.cryPause
  if self.t >= pause then
    self:_goBack(env)
    return self:_mode_back(env)
  end
  return state(self, env, { moving = false, bounce = rare or nil })
end

-- run back to within a tile of the player
function Forager:_mode_back(env)
  local cfg = self.cfg
  local path = self.path
  -- along the open cells first, then straight at the follower
  if path and self.idx <= #path then
    local c = path[self.idx]
    if self:_moveTo(c[1] * CELL, c[2] * CELL, cfg.runSpeed) then self.idx = self.idx + 1 end
  else
    if self:_moveTo(env.fpx, env.fpy, cfg.runSpeed) then
      self.mode, self.t = "near", 0
      self.dx, self.dy, self.facing, self.path = 0, 0, nil, nil
      return state(self, env, { moving = false })
    end
    -- the player keeps walking: keep the run aimed at them
    if (math.abs(env.fpx - self.wx) > CELL * 2 or math.abs(env.fpy - self.wy) > CELL * 2)
        and (self.t % 30) == 0 then
      self:_planBack(env)
    end
  end
  return state(self, env, { moving = true, walkMul = 2 })
end

--- The glint on the spot it is heading for, from the tell until it has dug; while it
--- counts, beside the player, the hint over its head now and then.
function Forager:collectActors(actors)
  if self.hintAge and self.mode == "near" and self.wx and self.deps.hintActor then
    local a = self.deps.hintActor(self.hintAge, self.wx, self.wy, self.env and self.env.renderer)
    if a then actors[#actors + 1] = a end
  end
  if not self.spot then return end
  local elevation = self.deps.elevation and self.deps.elevation() or 3
  actors[#actors + 1] = ForageSparkle.actor(self.spot.x * CELL, self.spot.y * CELL, self.sparkleAge, elevation, 1)
end

return Forager
