-- In-game check of VIVID WORLDS on the game's OPTION screen (lib/options_page.lua), run like
-- tests/drivers/smoke.lua:
--   POKEPORT_DRIVER=<this> POKEPORT_VERSION=red|crystal VWOG_SHOT_DIR=<dir> lovec .
-- (pre-create <dir>/<version>-options.) Opens OPTION, finds the entry on the top page,
-- presses A on it, steps the Follower row with the real input, checks the option is stored
-- and announced, then B goes back to the top page and B again closes OPTION.
local U = require("tests.drivers.util")
local GameVersion = require("src.core.GameVersion")

local VERSION = tostring(GameVersion.get())
local GEN = GameVersion.generation and GameVersion.generation() or 1
local SHOT = (os.getenv("VWOG_SHOT_DIR") or "shots") .. "/" .. VERSION .. "-options"

return function(game)
  local fails = 0
  local function say(line) print("[vwog-options] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
    return cond
  end
  local function press(button)
    table.insert(game.input.pressQueue, button)
    coroutine.yield()
    U.wait(4)
  end

  U.wait(60)
  local ex = game.mods and game.mods.exports and game.mods.exports.vivid_worlds_og
  if not ok(ex ~= nil and ex.engineReady, VERSION .. ": Vivid Worlds: OG installed") then
    love.event.quit(1)
    return
  end
  local opts = game.mods.modOptions
  opts.vivid_worlds_og = opts.vivid_worlds_og or {}
  opts.vivid_worlds_og.show_follower = true
  if GEN == 1 then
    U.teleport(game, "ROUTE_1", 14, 8, "down")
  else
    game.world:warpToMapId("ROUTE_29", 17, 5, "down")
  end
  U.wait(120)

  local announced = {}
  game.mods.events:on("mod.options_changed", function(ev)
    if ev and ev.mod == "vivid_worlds_og" then announced[#announced + 1] = ev end
  end)

  local depth0 = #game.stack.states
  if GEN == 1 then
    game.stack:push(require("src.ui.OptionsMenu").new(game, {}))
  else
    game:showOptions()
  end
  U.wait(10)
  local menu = game.stack:top()
  local view = menu.view or menu.rows
  local at
  for i, row in ipairs(view) do if row.id == "vwog_page" then at = i end end
  if not ok(at ~= nil, "VIVID WORLDS is on the top OPTION page (row " .. tostring(at) .. " of " .. #view .. ")") then
    love.event.quit(1)
    return
  end
  menu.index = at
  if menu.ensureVisible then menu:ensureVisible() end
  U.wait(4)
  U.still(game, SHOT .. "/1-top.png")

  press("a")
  local page = game.stack:top()
  ok(page ~= menu and page.sub == true, "A opens a page")
  local rows = page.view or page.rows
  local follower
  for i, row in ipairs(rows) do if row.id == "vwog_show_follower" then follower = i end end
  ok(follower ~= nil, "...with the Follower row on it (" .. #rows .. " rows)")
  U.still(game, SHOT .. "/2-page.png")

  for _ = 2, follower or 1 do press("down") end
  press("right")
  ok(opts.vivid_worlds_og.show_follower == false, "right on Follower turns it off")
  ok(#announced == 1 and announced[1].key == "show_follower", "...announced like a Mod Manager change")
  local saved = game.save and game.save.options and game.save.options.modOptions
  ok(saved and saved.vivid_worlds_og and saved.vivid_worlds_og.show_follower == false,
    "...and stored with the save's options")
  U.still(game, SHOT .. "/3-follower-off.png")
  U.wait(60)
  local fa = ex.followerAdapter
  ok(fa.renderer == nil or fa.renderer.recall == 0, "the partner went into its ball")
  press("right")
  ok(opts.vivid_worlds_og.show_follower == true, "right again turns it back on")

  press("b")
  ok(game.stack:top() == menu, "B goes back to the top page")
  press("b")
  ok(#game.stack.states == depth0, "B again closes OPTION")
  ok(opts.vivid_worlds_og.show_follower == true, "...keeping the change")

  say(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
  love.event.quit(fails == 0 and 0 or 1)
end
