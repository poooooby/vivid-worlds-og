-- Run: lua tests/engine_api_unit_test.lua
-- Every EnginePatch.<name>(...) call in lib/ and main.lua must either name a function the
-- Game Boy engine layer defines (lib/engine_patch.lua, its STUBS included) or be guarded on the
-- same line (`EnginePatch.<name> and EnginePatch.<name>(...)`): an unguarded call to a name
-- the layer lacks errors every tick in game (it happened with uiBusy).
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then failures = failures + 1; io.stderr:write("FAIL: " .. tostring(msg) .. "\n") else print("ok  " .. tostring(msg)) end
end

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local ep = read("lib/engine_patch.lua")
local defined = {}
for name in ep:gmatch("function EngineGb[.:]([%w_]+)") do defined[name] = true end
for name in ep:gmatch("EngineGb%.([%w_]+)%s*=") do defined[name] = true end
local stubs = ep:match("local STUBS = (%b{})")
for name in (stubs or ""):gmatch('"([%w_]+)"') do defined[name] = true end

local files = { "main.lua" }
local windows = package.config:sub(1, 1) == "\\"
local p = io.popen(windows and 'dir /b /s lib\\*.lua' or 'find lib -name "*.lua"')
for line in p:lines() do
  local rel = line:gsub("\\", "/"):match("(lib/.+%.lua)%s*$")
  if rel and rel ~= "lib/engine_patch.lua" then files[#files + 1] = rel end
end
p:close()
check(#files > 20, "found the modules to scan (" .. #files .. ")")

-- a guard may sit on the line itself or a few lines above (an `if EnginePatch.x and ...`
-- wrapping the call); a name used only behind an indirect guard is listed with its reason
local GUARD_WINDOW = 4
local INDIRECT = { reachFingerprint = "only called once the guarded reach build stored a fingerprint" }
local bad = 0
for _, path in ipairs(files) do
  local n, recent = 0, {}
  for line in (read(path) .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    recent[#recent + 1] = line
    if #recent > GUARD_WINDOW then table.remove(recent, 1) end
    local window = table.concat(recent, "\n")
    for name in line:gmatch("EnginePatch%.([%w_]+)%(") do
      local guarded = window:find("EnginePatch%." .. name .. "%s+and ") or window:find("EnginePatch%." .. name .. "%s+then")
      if not defined[name] and not INDIRECT[name] and not guarded then
        bad = bad + 1
        check(false, string.format("%s:%d calls EnginePatch.%s unguarded, and the Game Boy layer has no %s", path, n, name, name))
      end
    end
  end
end
check(bad == 0, "every EnginePatch call is defined or guarded")

if failures > 0 then io.stderr:write(failures .. " failure(s)\n") os.exit(1) end
print("engine_api_unit_test: all passed")
