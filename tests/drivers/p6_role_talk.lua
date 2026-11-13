-- Role -> Fight from the partner's own menu, then the A press that closes the line (a softlock
-- report: "X will battle..." then "X is beaming with joy!" and the game stuck). Run like
-- tests/drivers/smoke.lua:  POKEPORT_DRIVER=<this> POKEPORT_VERSION=crystal|red lovec .
local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local VERSION = tostring(GameVersion.get())
local GEN = GameVersion.generation and GameVersion.generation() or 1

return function(game)
  local fails = 0
  local function say(line) print("[vwog-roletalk] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
    return cond
  end
  local function finish()
    say(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
    love.event.quit(fails == 0 and 0 or 1)
  end

  U.wait(60)
  local ex = game.mods and game.mods.exports and game.mods.exports.vivid_worlds_og
  if not ok(ex ~= nil and ex.engineReady, VERSION .. ": Vivid Worlds: OG installed") then return finish() end
  local EP, fi = ex.enginePatch, ex.followerInteraction
  -- no battles from the setup walk (step encounters, or walking into a wild Pokemon)
  local opts = game.mods.modOptions
  opts.vivid_worlds_og = opts.vivid_worlds_og or {}
  opts.vivid_worlds_og.classic_enc = false
  local bt = ex.battleTrigger
  bt.onPlayerStepped, bt.onChaserContact, bt.onPlayerBumped = function() end, function() end, function() end

  local mon
  if GEN == 1 then
    local Pokemon = require("src.pokemon.Pokemon")
    mon = Pokemon.new(game.data, "BULBASAUR", 15)
    game.save.party = { mon }
    U.teleport(game, "ROUTE_1", 14, 8, "down")
  else
    local Mon = require("src.battle.gen2.Mon")
    mon = Mon.new(game.data, "CYNDAQUIL", 15)
    mon.happiness = 250 -- "beaming with joy"
    game.save.party = { mon }
    game.world:warpToMapId("ROUTE_29", 17, 5, "down")
  end
  U.wait(120)

  local function faceAndTalk()
    U.hold(game, "left", 40)
    for _ = 1, 180 do
      local c = EP.playerCell()
      if c and not c.moving then break end
      U.wait(1)
    end
    U.wait(60)
    for _ = 1, 12 do
      local c = EP.playerCell()
      if c and c.facing == "right" then break end
      U.hold(game, "right", 1)
    end
    U.wait(20)
    local c0 = EP.playerCell()
    if c0 and c0.facing ~= "right" then
      local pl = EP.world and EP.world() and EP.world().player
      if pl then pl.facing = "right" end
    end
    U.tap(game, "a")
    U.wait(10)
  end

  local function snapshot(tag)
    local w = EP.world and EP.world()
    say(string.format("%s: state=%s msg=%s choice=%s locked=%s battle=%s role=%s", tag, tostring(fi.state),
      tostring(EP.isMessageOpen()), tostring(EP.choiceActive()),
      tostring(EP.isHeld()), tostring(EP.battleActive()),
      tostring(ex.companion and ex.companion:savedRole(mon))))
  end

  local function waitChoice()
    for _ = 1, 600 do
      if EP.choiceActive() then return true end
      if EP.isMessageOpen() and EP.messageOnLastPage() == false then U.tap(game, "a") end
      U.wait(2)
    end
    return false
  end

  faceAndTalk()
  ok(fi:isActive(), "A on the partner starts the interaction")
  ok(waitChoice(), "the partner's menu opens")
  snapshot("main menu")
  U.tap(game, "down") U.wait(6) U.tap(game, "a") U.wait(20) -- Role
  ok(waitChoice(), "the Role sub menu opens")
  U.tap(game, "down") U.wait(6) U.tap(game, "down") U.wait(6)
  U.tap(game, "a") -- Fight
  U.wait(30)
  snapshot("after Fight")
  -- close the line the way a player does, then keep pressing A like an impatient one
  -- (the old bug: the report box came back under it and never closed)
  for i = 1, 20 do
    if not fi:isActive() and not EP.isMessageOpen() then break end
    U.tap(game, "a")
    U.wait(15)
    snapshot("A #" .. i)
  end
  U.wait(60)
  snapshot("settled")
  ok(not fi:isActive(), "the interaction is over")
  ok(not EP.isMessageOpen(), "no message left open")

  -- an A press on the partner the menu passes on (mid-step, busy ...) must not reach the
  -- engine's follower talk: on Red / Blue that is Yellow's Pikachu talk, which errors
  local origTry = fi.tryStart
  fi.tryStart = function() return false end
  local pl = EP.world and EP.world() and EP.world().player
  if pl then pl.facing = "right" end
  local partnerAhead = EP.followerInFacingCell() ~= nil
  U.tap(game, "a")
  U.wait(30)
  fi.tryStart = origTry
  say("partner ahead for the passed-on press: " .. tostring(partnerAhead))
  ok(not EP.isMessageOpen(), "a passed-on press at the partner opens nothing (and did not crash)")

  -- the player can still walk (playerCell reuses one table: copy the numbers)
  local c1 = EP.playerCell()
  local x1, y1 = c1 and c1.x, c1 and c1.y
  U.hold(game, "up", 20)
  U.wait(60)
  local c2 = EP.playerCell()
  ok(c2 and x1 and (c2.x ~= x1 or c2.y ~= y1), "the player can walk afterwards")
  finish()
end
