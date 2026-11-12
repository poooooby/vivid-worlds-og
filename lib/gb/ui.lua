-- The dialogue plumbing both Game Boy adapters share (lib/gb/gen1.lua, lib/gb/gen2.lua): the
-- engine's own text box (src/render/TextBox.lua -- the same module on Red and on Gold) pushed on
-- the game's state stack, with the mod's own boxes tracked so a "stay" box under a menu still
-- reads as open. Each adapter keeps its own choice menu (Gen 1: ListMenu; Gen 2: ScriptMenu)
-- and hands it to `trackChoice`.
--
--   local UI = V.require("gb/ui").new(function(world) return <the game> end, function() return load end)
local UI = {}

--- `gameOf(world)` -> the live game (with `.stack`); `loader()` -> the adapter's module loader.
function UI.new(gameOf, loader)
  local self = {}
  local openBoxes = setmetatable({}, { __mode = "k" }) -- our TextBoxes still open
  local stayBox -- the one "stay" box up (the interaction's report)
  local choiceMenu -- the one menu up (the interaction's rows)

  local function stackOf(world)
    local game = gameOf(world)
    return game and game.stack or nil, game
  end

  function self.stackTop(world)
    local stack = stackOf(world)
    if not (stack and stack.top) then return nil end
    local ok, top = pcall(stack.top, stack)
    return ok and top or nil
  end

  --- Any dialogue box up: the stack's top, or the mod's own "stay" box under a menu.
  function self.isMessageOpen(world)
    local top = self.stackTop(world)
    if type(top) == "table" and top.isTextBox then return true end
    return stayBox ~= nil and openBoxes[stayBox] == true
  end

  --- The engine's own dialogue box. `opts`: `stay` keeps it up (the caller closes it with
  --- closeStayMessage), `done` runs when it closes itself. Returns true when it opened.
  function self.showMessage(world, text, opts)
    local stack, game = stackOf(world)
    local load = loader()
    local TextBox = load and load("src.render.TextBox")
    if not (stack and TextBox and TextBox.new) then return false end
    local box
    local function onDone()
      if box then openBoxes[box] = nil end
      if box == stayBox then stayBox = nil end
      if opts and opts.done then pcall(opts.done) end
    end
    local tbOpts = nil
    if opts and opts.stay then tbOpts = { stay = {} } end
    local ok, b = pcall(TextBox.new, game, tostring(text or ""), onDone, tbOpts)
    if not (ok and b) then return false end
    box = b
    openBoxes[box] = true
    if opts and opts.stay then stayBox = box end
    local okP = pcall(stack.push, stack, box)
    if not okP then
      openBoxes[box] = nil
      if box == stayBox then stayBox = nil end
      return false
    end
    return true
  end

  --- Has the open box typed out its last page (a menu can open over it now)?
  function self.messageOnLastPage(world)
    local top = self.stackTop(world)
    local box = (type(top) == "table" and top.isTextBox) and top or stayBox
    if not (type(box) == "table" and box.pages) then return false end
    return box.done == true and box.pageIndex ~= nil and box.pageIndex >= #box.pages
  end

  --- Closes the "stay" box, wherever it sits on the stack.
  function self.closeStayMessage(world)
    local box = stayBox
    if not box then return false end
    stayBox = nil
    openBoxes[box] = nil
    local stack = stackOf(world)
    if not stack then return false end
    if self.stackTop(world) == box then
      pcall(stack.pop, stack)
      return true
    end
    -- under something else (should not happen: the menu closes first): drop it from the list
    local list = stack.stack or stack.states
    if type(list) == "table" then
      for i = #list, 1, -1 do
        if list[i] == box then table.remove(list, i) return true end
      end
    end
    return false
  end

  --- The adapter's menu, now on the stack (nil once it closed).
  function self.trackChoice(menu) choiceMenu = menu end

  function self.choiceActive(world)
    return choiceMenu ~= nil and self.stackTop(world) == choiceMenu
  end

  return self
end

return UI
