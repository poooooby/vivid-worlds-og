-- In-game check of the partner's mood bubbles (P2), run like tests/drivers/smoke.lua:
--   POKEPORT_DRIVER=<this> POKEPORT_VERSION=red|yellow|crystal VWOG_SHOT_DIR=<dir> lovec .
-- (pre-create <dir>/<version>-emotes: the engine's screenshot helper can't make folders on Windows)
-- Lists the game's own bubbles, then shows the partner in each mood and screenshots it: the
-- game's bubble where it has one, the drawn effect otherwise.
local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local VERSION = tostring(GameVersion.get())
local GEN = GameVersion.generation and GameVersion.generation() or 1
local SHOT = (os.getenv("VWOG_SHOT_DIR") or "shots") .. "/" .. VERSION .. "-emotes"

-- how many bubbles each game ships (emotion_bubbles.asm / Gold's EMOTE_* set)
local EXPECT = { red = 3, blue = 3, yellow = 8, gold = 8, silver = 8, crystal = 8 }

return function(game)
  local fails = 0
  local function say(line) print("[vwog-emotes] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
    return cond
  end

  U.wait(60)
  local ex = game.mods and game.mods.exports and game.mods.exports.vivid_worlds_og
  if not ok(ex ~= nil and ex.engineReady, VERSION .. ": Vivid Worlds: OG installed") then
    love.event.quit(1) return
  end
  local EP, fi, fa = ex.enginePatch, ex.followerInteraction, ex.followerAdapter
  -- no random encounter in the grass while walking into place
  local opts = game.mods.modOptions
  opts.vivid_worlds_og = opts.vivid_worlds_og or {}
  opts.vivid_worlds_og.classic_enc = false
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
  local function where(label)
    local t = game.stack and game.stack:top()
    local c = EP.playerCell()
    say(string.format("%s: overworld on top %s, player %s,%s, partner %s", label, tostring(t and t.isOverworld),
      tostring(c and c.x), tostring(c and c.y), tostring(EP.followerCurrent() ~= nil)))
  end
  where("placed")
  U.hold(game, "left", 40) -- two steps, so the partner stands in the open behind
  U.wait(90)
  where("walked")

  local names = {}
  for _, n in ipairs({ "exclaim", "question", "happy", "sad", "heart", "bolt", "sleep", "skull", "fish" }) do
    if EP.emoteBubble(n) then names[#names + 1] = n end
  end
  say("the game's bubbles: " .. table.concat(names, " "))
  ok(#names == (EXPECT[VERSION] or #names), VERSION .. " has its " .. tostring(EXPECT[VERSION]) .. " bubbles")

  local EmoteArt = { bubbleFor = function(kind)
    local map = { hearts = "heart", notes = "happy", rain = "sad", zzz = "sleep", sparks = "bolt", bubbles = "skull" }
    return map[kind] and EP.emoteBubble(map[kind]) and map[kind] or nil
  end }
  local realMood = fi.moodKind
  for i, kind in ipairs({ "hearts", "notes", "rain", "zzz", "sparks", "bubbles", "anger", "sweat" }) do
    fi.moodKind = function() return kind end
    U.wait(30)
    ok(fa.moodKind == kind, "the partner shows mood '" .. kind .. "' (" .. (EmoteArt.bubbleFor(kind) or "drawn") .. ")")
    U.still(game, string.format("%s/%02d_%s.png", SHOT, i, kind))
  end
  fi.moodKind = realMood
  say(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
