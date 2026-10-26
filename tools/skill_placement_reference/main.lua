-- Read-only oracle: execute the frozen grid/path modules and the exact GUI
-- placement expressions, without loading the game, saves or updater.
function love.errorhandler(message)
  io.stderr:write(tostring(message), "\n")
  os.exit(1)
end

function love.load()
  local source = assert(os.getenv("DOVE_SOURCE_DIR"))
  local rally_only = os.getenv("DOVE_RALLY_OUTPUT")
  local destination = rally_only or assert(os.getenv("DOVE_PLACEMENT_OUTPUT"))
  package.path = source .. "/?.lua;" .. source .. "/all/?.lua;" .. package.path
  package.loaded.grid_a_star = {} -- No waypoint search is used by placement.
  package.loaded["dove_modules.perf.perf"] = {}
  require("all.constants")
  local V = require("lib.klua.vector")
  local GR = require("grid_db")
  local P = require("path_db")
  local bit = require("bit")
  local json = require("lib.json")
  love.filesystem.loadWithPreference = function(name)
    return loadfile(source .. "/kr1/" .. name)
  end
  local gui_file = assert(io.open(source .. "/all-desktop/game_gui.lua", "rb"))
  local gui = gui_file:read("*a"); gui_file:close()
  local fire = assert(gui:match("if (not GR:cell_is%(wx, wy, TERRAIN_CLIFF%).-) then"))
  local troops = assert(gui:match("elseif game_gui.mode == GUI_MODE_POWER_2 then%s+if (.-) then"))
  local env = setmetatable({GR=GR, P=P, bor=bit.bor, V=V, level={}}, {__index=_G})
  local function compile(expression)
    local chunk = assert(loadstring("return function(wx, wy) return " .. expression .. " end"))
    setfenv(chunk, env)
    return chunk()
  end
  local can_fire, can_troops = compile(fire), compile(troops)
  local result = {source_commit="e29ece82939fd73fb69bfc4b469d484a72e4dfd2", expressions={fire=fire, reinforcements=troops}, levels={}}
  local resolve_rally
  if rally_only then
    local utils_file = assert(io.open(source .. "/all/utils.lua", "rb"))
    local utils = utils_file:read("*a"); utils_file:close()
    local ellipse = assert(utils:match("function U.is_inside_ellipse%(p, center, radius%)(.-)\nend"))
    local chunk = assert(loadstring("return function(p, center, radius) " .. ellipse .. " end"))
    env.U = {is_inside_ellipse=chunk()}
    local body = assert(gui:match("(local target_pos = V.v%(wx, wy%).-)\n%s*if found_valid_rally_pos then"))
    chunk = assert(loadstring("return function(e, b, wx, wy) " .. body .. " return found_valid_rally_pos, target_pos end"))
    setfenv(chunk,env); resolve_rally = chunk()
    result = {source_commit=result.source_commit, rally_body=body, cases={}}
  end
  for id=1,3 do
    local name = string.format("level%02d", id)
    local grid = assert(loadfile(source .. "/kr1/data/levels/" .. name .. "_grid.lua"))()
    GR.grid, GR.ox, GR.oy = grid.grid, grid.ox, grid.oy
    GR.grid_w, GR.grid_h = #grid.grid, #grid.grid[1]
    P:load(name, {})
    local layout_chunk = assert(loadfile(source .. "/kr1/data/levels/" .. name .. "_data.lua"))
    setfenv(layout_chunk, {v=V.v})
    local layout = layout_chunk()
    for _, range in pairs(layout.invalid_path_ranges or {}) do
      P:add_invalid_range(range.path_id, range.from, range.to, range.flags)
    end
    if rally_only then
      local definition_file = assert(io.open(assert(os.getenv("DOVE_RALLY_DATA_DIR")) .. "/" .. name .. "/definition.json", "rb"))
      local definition = json.decode(definition_file:read("*a")); definition_file:close()
      local towers = {}
      for _, entity in ipairs(layout.entities_list) do
        if entity["tower.holder_id"] then towers[#towers+1] = entity end
      end
      for _, entity in ipairs({towers[1],towers[#towers]}) do
        for tier=1,(id == 1 and 1 or 2) do
          local template_name = "tower_barrack_" .. tier
          local template = definition.templates[template_name]
          local e = {pos=V.v(entity.pos.x,entity.pos.y), tower=template.tower}
          local center = e.pos + V.v(template.tower.range_offset.x,template.tower.range_offset.y)
          local radius = template.barrack.rally_range
          local default = entity["tower.default_rally_pos"]
          local points = {V.v(default.x,default.y),center,center+V.v(3*radius,0),center+V.v(-3*radius,0),center+V.v(0,3*radius),center+V.v(0,-3*radius),center+V.v(3*radius,3*radius),center+V.v(-3*radius,-3*radius)}
          for _, point in ipairs(points) do
            local valid, resolved = resolve_rally(e,template.barrack,point.x,point.y)
            result.cases[#result.cases+1] = {level=id, tower_id=entity["tower.holder_id"], template=template_name, point={x=point.x,y=point.y}, valid=valid, resolved=valid and {x=resolved.x,y=resolved.y} or nil}
          end
        end
      end
    else
      local samples = {}
      local function sample(x,y)
        samples[#samples+1] = {x=x, y=y, terrain=GR:cell_type(x,y), fire=can_fire(x,y), reinforcements=can_troops(x,y)}
      end
      for x=0,1024,64 do for y=40,735,48 do sample(x,y) end end
      -- Source paths and tower rally points supplement the regular grid with
      -- actual deployment positions, both third-level entrances and road edges.
      for _, entity in ipairs(layout.entities_list) do
        local rally = entity["tower.default_rally_pos"]
        if rally then sample(rally.x,rally.y) end
      end
      for _, path in ipairs(P.paths) do
        local node = path[1][math.floor(#path[1]/2)]
        for _, dy in ipairs({0, 41, 42, 43, 59, 60, 61}) do sample(node.x,node.y+dy) end
      end
      result.levels[tostring(id)] = samples
    end
  end
  local file = assert(io.open(destination,"wb")); file:write(json.encode(result)); file:close()
  love.event.quit()
end
