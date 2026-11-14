-- In-game check that the partner turns to face the player when talked to, run like
-- tests/drivers/smoke.lua:
--   POKEPORT_DRIVER=<this> POKEPORT_VERSION=red|yellow|crystal VWOG_SHOT_DIR=<dir> lovec .
-- (pre-create <dir>/<version>-face.) Walks left so the partner trails on the right, turns to
-- it, points the partner away (as an idle look-around does), presses A for real and checks it
-- turns to the player and stays so while the menu is up. Screenshots before and after.
local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local VERSION = tostring(GameVersion.get())
local GEN = GameVersion.generation and GameVersion.generation() or 1
local SHOT = (os.getenv("VWOG_SHOT_DIR") or "shots") .. "/" .. VERSION .. "-face"

return function(game)
  local fails = 0
  local function say(line) print("[vwog-face] " .. line) end
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
  local opts = game.mods.modOptions
  opts.vivid_worlds_og = opts.vivid_worlds_og or {}
  opts.vivid_worlds_og.classic_enc = false
  opts.vivid_worlds_og.enabled = false

  if GEN == 1 then
    local Pokemon = require("src.pokemon.Pokemon")
    game.save.party = { Pokemon.new(game.data, "BULBASAUR", 15) }
    U.teleport(game, "ROUTE_1", 14, 8, "down")
  else
    local Mon = require("src.battle.gen2.Mon")
    game.save.party = { Mon.new(game.data, "CYNDAQUIL", 15) }
    game.world:warpToMapId("ROUTE_29", 17, 5, "down")
  end
  U.wait(120)

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
    local w = EP.world and EP.world()
    local pl = w and w.player
    if pl then pl.facing = "right" say("(turned the player directly)") end
  end
  local npc = EP.followerCurrent()
  if not ok(EP.followerInFacingCell() ~= nil, "the partner stands in the cell the player faces") then return finish() end

  -- looking away, as Yellow's idle look-around or a turn leaves it
  npc.facing = "down"
  U.wait(2)
  U.still(game, SHOT .. "/1-looking-away.png")
  U.tap(game, "a")
  U.wait(10)
  ok(fi:isActive(), "A on the partner starts the interaction")
  ok(npc.facing == "left", "...and it turns to face the player (facing " .. tostring(npc.facing) .. ")")
  U.still(game, SHOT .. "/2-faces-player.png")

  local menuUp = false
  for _ = 1, 600 do
    if EP.choiceActive() then menuUp = true break end
    if EP.isMessageOpen() and EP.messageOnLastPage() == false then U.tap(game, "a") end
    U.wait(2)
  end
  ok(menuUp, "the menu opens")
  local turned = false
  for _ = 1, 300 do
    U.wait(1)
    if npc.facing ~= "left" then turned = true end
  end
  ok(not turned, "...and it keeps facing the player while the menu is up (5 s)")
  U.still(game, SHOT .. "/3-menu.png")

  for _ = 1, 600 do
    if not fi:isActive() then break end
    U.tap(game, "b")
    U.wait(4)
  end
  ok(not fi:isActive(), "B closes the interaction")
  finish()
end
