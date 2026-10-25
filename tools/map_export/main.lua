-- Only evaluate immutable map tables. Never load Dove's application or saves.
local source = assert(os.getenv("DOVE_SOURCE_DIR"))
local destination = assert(os.getenv("DOVE_EXPORT_PATH"))
local inputs, behaviors = {}, {}
local function behavior_group(name)
  return setmetatable({}, {__index=function(t,k)
    local f=function() error("Behavior execution forbidden: "..name.."."..k) end
    behaviors[f]=name.."."..k; rawset(t,k,f); return f
  end})
end
local modules = {
  ["lib.klua.vector"]={v=function(x,y) return {x=x,y=y} end, r=function(x,y,w,h) return {x=x,y=y,w=w,h=h} end},
  i18n={cjk=function(_,default,zh) return zh or default end},
  map_decos_functions=setmetatable({}, {__index=function(t,k) local g=behavior_group(k);rawset(t,k,g);return g end})
}
local allowed = {
  ["data.map_data"]="kr1-desktop/data/map_data.lua",
  ["data.map_points"]="kr1-desktop/data/map_points.lua",
  ["data.map_animations_paths"]="kr1-desktop/data/map_animations_paths.lua",
  ["data.map_animations_paths2"]="kr1-desktop/data/map_animations_paths2.lua"
}
local function read_module(name)
  if modules[name] then return modules[name] end
  local path=assert(allowed[name],"Module outside map exporter allowlist: "..name)
  local f=assert(io.open(source.."/"..path,"rb")); local text=f:read("*a");f:close();inputs[path]=true
  local fn=assert(loadstring(text,"@"..path))
  setfenv(fn,{require=read_module,GGLabel={static={ref_h=1080}},REF_H=1080})
  modules[name]=fn();return modules[name]
end
local function clean(value)
  if type(value)=="function" then return assert(behaviors[value],"Unknown map behavior") end
  if type(value)~="table" then return value end
  local out={};for k,v in pairs(value) do out[k]=clean(v) end;return out
end
local function merge(a,b)
  local out=clean(a)
  for k,v in pairs(b) do out[k]=type(v)=="table" and type(out[k])=="table" and merge(out[k],v) or clean(v) end
  return out
end
local function run()
  local data=read_module("data.map_data")
  local points=read_module("data.map_points")
  local animations,by_id={},{}
  for _,a in ipairs(data.map_animations1) do
    local expanded=a.template and merge(assert(by_id[a.template]),a) or clean(a)
    expanded.template=nil;by_id[a.id]=expanded;animations[#animations+1]=expanded
  end
  local levels={}
  for _,id in ipairs({1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,1000}) do
    levels[#levels+1]={id=id,flag=clean(assert(points.flags[id])),rules=clean(data.level_data[id] or {})}
  end
  local out={animations=animations,decos=clean(data.map_decos[1]),levels=levels,inputs=inputs}
  package.path=source.."/?.lua;"..package.path
  local json=require("lib.json")
  local file=assert(io.open(destination,"wb"));file:write(json.encode(out));file:close()
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then local file=assert(io.open(destination..".error","wb"));file:write(err);file:close() end
  love.event.quit(ok and 0 or 1)
end
