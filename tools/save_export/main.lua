-- Evaluate immutable data only; never load storage, the application or user saves.
local source = assert(os.getenv("DOVE_SOURCE_DIR"))
local destination = assert(os.getenv("DOVE_EXPORT_PATH"))
local function evaluate(relative)
  local file = assert(io.open(source .. "/" .. relative, "rb"))
  local text = file:read("*a"); file:close()
  local fn = assert(loadstring(text, "@" .. relative))
  setfenv(fn, {ipairs=ipairs, table=table, DIFFICULTY_EASY=1, DIFFICULTY_NORMAL=2,
    DIFFICULTY_HARD=3, DIFFICULTY_IMPOSSIBLE=4,
    require=function(name) assert(name == "all.constants") end})
  return fn()
end
function love.load()
  local ok, err = xpcall(function()
    local template = evaluate("kr1/data/slot_template.lua")
    local levels = {}
    for key, value in pairs(template.levels) do levels[tostring(key)] = value end
    template.levels = levels
    local gs = evaluate("kr1/game_settings.lua")
    local generations = {}
    for key, ranges in pairs(gs) do
      local generation = key:match("^level_ranges(%d+)$")
      if generation then generations[generation] = {
        level_ranges=ranges, main_campaign_last=assert(gs["main_campaign_levels"..generation])
      } end
    end
    package.path = source .. "/?.lua;" .. package.path
    local json = require("lib.json")
    local file = assert(io.open(destination, "wb"))
    file:write(json.encode({template=template, generations=generations,
      max_stars=gs.max_stars})); file:close()
  end, debug.traceback)
  if not ok then local f=assert(io.open(destination..".error","wb"));f:write(err);f:close() end
  love.event.quit(ok and 0 or 1)
end
