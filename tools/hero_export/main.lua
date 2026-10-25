-- Offline template evaluation. Never loads Dove main.lua, saves, updater or plugins.
function love.errorhandler(msg)
  local f=io.open((os.getenv("DOVE_EXPORT_PATH") or "export")..".error","wb");if f then f:write(tostring(msg));f:close() end
  os.exit(1)
end
local source = assert(os.getenv("DOVE_SOURCE_DIR"))
local destination = assert(os.getenv("DOVE_EXPORT_PATH"))
package.path = source .. "/?.lua;" .. source .. "/all/?.lua;" .. source .. "/kr1/?.lua;" .. source .. "/kr1-desktop/?.lua;" .. package.path
local loaded_inputs = {}
local original_require=require
local allowed={
  ["lib.klua.table"]=true,["lib.klua.vector"]=true,["lib.hump.vector-light"]=true,["lib.nav_path"]=true,
  ["lib.json"]=true,["lib.heading"]=true,["all.constants"]=true,["kr1.game_settings"]=true,
  ["lib.constant_spiked_armor"]=true,["lib.nav_rally"]=true,["lib.timed"]=true,
  enemies=true,boss=true,["data.map_animations_paths"]=true,["data.map_animations_paths2"]=true
}
function require(name)
  if package.loaded[name] or name=="bit" or name=="ffi" then return original_require(name) end
  assert(allowed[name],"Module outside hero exporter allowlist: "..name)
  local stem=name:gsub("%.","/")..".lua"
  for _,prefix in ipairs({"","all/","kr1/","kr1-desktop/"}) do
    local file=io.open(source.."/"..prefix..stem,"rb")
    if file then file:close();loaded_inputs[prefix..stem]=true;break end
  end
  return original_require(name)
end
local function chunk(relative, text)
  loaded_inputs[relative] = true
  if not text then local f = assert(io.open(source .. "/" .. relative, "rb")); text=f:read("*a"); f:close() end
  return assert(loadstring(text, "@" .. relative))()
end
-- Callable placeholders retain arbitrary nesting and fail if gameplay is invoked.
local function functions(prefix)
  return setmetatable({}, {__index=function(t,k)
    local value=functions(prefix.."."..tostring(k));rawset(t,k,value);return value
  end,__call=function() error("Behavior execution forbidden: "..prefix) end})
end
local scripts=functions
package.loaded.scripts=scripts("scripts")
package.loaded.game_scripts=scripts("game_scripts")
package.loaded.i18n={cjk=function(_,a) return a end}
package.loaded["all.rally_utils"]=functions("rally_utils")
local U={fts=function(v) return v/30 end}
U.set_terrain_style=function(e,style)
  e.tower.terrain_style=style
  if not (e.tower_holder and e.tower_holder.blocked) and not e.render.sprites[1].animated then
    e.render.sprites[1].name=assert(TERRAIN_STYLE_SPRITE_DICT[style])
  end
end
package.loaded.utils=U
package.loaded.script_utils=functions("script_utils")
local function run()
  require("lib.klua.table")
  require("all.constants")
  local V=require("lib.klua.vector")
  _G.V=V;_G.vec_2=V.v;_G.vec_1=V.vv;_G.r=V.r
  _G.fts=U.fts;_G.IS_PHONE=false;_G.IS_PHONE_OR_TABLET=false;_G.IS_CONSOLE=false
  local E={entities={},components={}}
  function E:register_c(name,base) local v=base and table.deepclone(assert(self.components[base])) or {};self.components[name]=v;return v end
  function E:register_c_ffi(name,v) self.components[name]=v end
  function E:clone_c(name) return table.deepclone(assert(self.components[name],"Unknown component "..name)) end
  function E:register_t(name,base) local v=base and table.deepclone(assert(self.entities[base],"Unknown base "..base)) or {};v.template_name=name;self.entities[name]=v;return v end
  E.register_t_hot=E.register_t
  function E:add_comps(t,...) for _,name in ipairs({...}) do t[name]=self:clone_c(name) end end
  function E:get_template(name) return assert(self.entities[name],"Unknown template "..tostring(name)) end
  _G.E=E;package.loaded.entity_db=E
  chunk("all/components.lua");package.loaded.components=true
  chunk("all/templates.lua");package.loaded.templates=true
  chunk("kr1/game_templates_utils.lua");package.loaded.game_templates_utils=true
  for _,name in ipairs({"foundamental_towers","mage_towers","archer_towers","engineer_towers","barrack_towers"}) do chunk("kr1/"..name..".lua");package.loaded[name]=true end
  chunk("kr1/heroes.lua");package.loaded.heroes=true
  chunk("kr1/game_templates.lua")
  local strings=chunk("_assets/kr1-desktop/strings/zh-Hans.lua")
  _G._=function(key) return strings[key] or key end
  local details=chunk("_assets/kr1-desktop/strings/hero_room_special.lua")
  package.loaded.map_decos_functions=scripts("map_decos_functions")
  _G.GGLabel={static={ref_h=1080}};_G.REF_H=1080
  local map=chunk("kr1-desktop/data/map_data.lua")
  local out={heroes={},inputs=loaded_inputs}
  for _,row in ipairs(map.hero_data) do
    local t=E:get_template(row.name)
    local copy={};for k,v in pairs(row) do copy[k]=v end
    copy.title=_G._((t.info.i18n_key or string.upper(row.name)).."_NAME")
    copy.bio=_G._(string.upper(row.name).."_DESCRIPTION")
    copy.special=_G._(string.upper(row.name).."_SPECIAL")
    copy.sound=t.sound_events.hero_room_select
    copy.details=details[row.name] or details.default
    out.heroes[#out.heroes+1]=copy
  end
  local json=require("lib.json")
  local f=assert(io.open(destination,"wb"));f:write(json.encode(out));f:close()
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then local f=assert(io.open(destination..".error","wb"));f:write(err);f:close() end
  love.event.quit(ok and 0 or 1)
end
