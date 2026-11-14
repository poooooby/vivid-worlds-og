-- Vsync off for a driver run. The engine already runs POKEPORT_DRIVER unpaced (main.lua: no
-- frame cap for a driver), so vsync is all that ties a run to the display's refresh -- and
-- over Remote Desktop that is about 30 Hz, half speed. Set in the live options too, so an
-- OPTION screen closing (Gold's onDone re-applies them) cannot turn it back on. Every driver
-- calls it first: require("mods.vivid_worlds_og.tests.drivers.novsync")(game).
return function(game)
  for _, o in ipairs({ game and game.save and game.save.options or false, game and game.options or false }) do
    if type(o) == "table" then o.vsync = "off" end
  end
  local ok, VSync = pcall(require, "src.core.VSync")
  if ok and VSync and VSync.apply then
    pcall(VSync.apply, "off")
  elseif love and love.window and love.window.setVSync then
    pcall(love.window.setVSync, 0)
  end
end
