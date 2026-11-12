-- In-game check of Pet / Play / Talk with the partner (P2), run like tests/drivers/smoke.lua:
--   POKEPORT_DRIVER=<this> POKEPORT_VERSION=crystal|red VWOG_SHOT_DIR=<dir> lovec .
-- Walks two steps so the partner trails behind, turns to face it, presses A for real, picks the
-- first row (Pet) and checks the menu, the mood emote and the friendship change.
local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local VERSION = tostring(GameVersion.get())
local GEN = GameVersion.generation and GameVersion.generation() or 1
local SHOT = (os.getenv("VWOG_SHOT_DIR") or "shots") .. "/" .. VERSION .. "-talk"

return function(game)
  local fails = 0
  local function say(line) print("[vwog-talk] " .. line) end
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
  ok(EP.supports("interaction"), "this generation carries Pet / Play / Talk")

  local mon
  if GEN == 1 then
    local Pokemon = require("src.pokemon.Pokemon")
    mon = Pokemon.new(game.data, "BULBASAUR", 15)
    game.save.party = { mon }
    U.teleport(game, "ROUTE_1", 14, 8, "down")
  else
    local Mon = require("src.battle.gen2.Mon")
    mon = Mon.new(game.data, "CYNDAQUIL", 15)
    mon.happiness = 70
    game.save.party = { mon }
    game.world:warpToMapId("ROUTE_29", 17, 5, "down")
  end
  ex.spawnManager.onMapExited = ex.spawnManager.onMapExited -- (keep the field as is)
  U.wait(120)
  local sheet = EP.fieldEffectSheet("exclamation_question_mark", 16, 16, 2)
  ok(sheet ~= nil and sheet.image ~= nil and sheet.quads[0] ~= nil and sheet.quads[1] ~= nil,
    "the game's own \"!\" / \"?\" emote art loads for the wild reactions")
  local before = EP.friendshipOf(mon)
  say("friendship before: " .. tostring(before))

  -- two steps left, then turn round to face the partner trailing behind
  U.hold(game, "left", 40)
  -- let the walk finish and the partner close up behind
  for _ = 1, 180 do
    local c = EP.playerCell()
    if c and not c.moving then break end
    U.wait(1)
  end
  U.wait(60)
  -- turn in place toward it: a short hold (Gen 1 ignores a one-frame tap), stopping as soon
  -- as the player faces right so it never steps onto the partner
  for _ = 1, 12 do
    local c = EP.playerCell()
    if c and c.facing == "right" then break end
    U.hold(game, "right", 1)
  end
  U.wait(20)
  -- (harness only: if the driver's synthetic press did not turn the player, face them directly
  -- -- the A press below is still the real one through the engine's interact)
  local c0 = EP.playerCell()
  if c0 and c0.facing ~= "right" then
    local w = EP.world and EP.world()
    local pl = w and w.player
    if pl then pl.facing = "right" say("(turned the player directly)") end
  end
  local pc, npc = EP.playerCell(), EP.followerCurrent()
  say(string.format("player at %s,%s facing %s; partner at %s,%s", tostring(pc and pc.x), tostring(pc and pc.y),
    tostring(pc and pc.facing), tostring(npc and npc.cellX), tostring(npc and npc.cellY)))
  local facing = EP.followerInFacingCell()
  ok(facing ~= nil, "the partner stands in the cell the player faces")
  U.tap(game, "a")
  U.wait(10)
  ok(fi:isActive(), "A on the partner starts the interaction (not the engine's own A)")
  local menuUp = false
  for _ = 1, 600 do
    if EP.choiceActive() then menuUp = true break end
    if EP.isMessageOpen() and EP.messageOnLastPage() == false then U.tap(game, "a") end
    U.wait(2)
  end
  ok(menuUp, "the Pet / Play / Talk menu opens")
  say("mood emote: " .. tostring(fi:moodKind()))
  U.still(game, SHOT .. "/1_menu.png")
  U.tap(game, "a") -- the first row: Pet
  U.wait(90)
  U.still(game, SHOT .. "/2_pet.png")
  for _ = 1, 900 do
    if not fi:isActive() then break end
    if EP.isMessageOpen() then U.tap(game, "a") end
    U.wait(3)
  end
  ok(not fi:isActive(), "the interaction finishes")
  local after = EP.friendshipOf(mon)
  say("friendship after: " .. tostring(after) .. (GEN == 2 and (" (happiness byte " .. tostring(mon.happiness) .. ")") or ""))
  ok(after and before and after > before, "petting raised its friendship")
  if GEN == 2 then ok(mon.happiness == after, "...on the game's own happiness byte") end
  finish()
end
