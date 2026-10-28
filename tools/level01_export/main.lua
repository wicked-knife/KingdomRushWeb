-- Offline template evaluation. Never loads Dove main.lua, saves, updater or plugins.
function love.errorhandler(msg)
  local f=io.open((os.getenv("DOVE_EXPORT_PATH") or "export")..".error","wb");if f then f:write(tostring(msg));f:close() end
  os.exit(1)
end
local source = assert(os.getenv("DOVE_SOURCE_DIR"))
local destination = assert(os.getenv("DOVE_EXPORT_PATH"))
local level_id = tonumber(os.getenv("DOVE_LEVEL_ID") or "1")
local ranger_arena = os.getenv("DOVE_RANGER_ARENA") == "1"
local level_name = string.format("level%02d", level_id)
package.path = source .. "/?.lua;" .. source .. "/all/?.lua;" .. source .. "/kr1/?.lua;" .. package.path
local spec_file = assert(io.open(assert(os.getenv("DOVE_CONTENT_SPEC")), "rb"))
local spec = require("lib.json").decode(spec_file:read("*a")); spec_file:close()
assert(spec.id == level_id, "Content registration differs from requested level")
local selected_features = {}
for _, name in ipairs(spec.features) do selected_features[name] = true end
local function has(name) return selected_features[name] == true end
local advanced = has("ranger")
local loaded_inputs = {}
local function chunk(relative, text)
  loaded_inputs[relative] = true
  if not text then local f = assert(io.open(source .. "/" .. relative, "rb")); text=f:read("*a"); f:close() end
  return assert(loadstring(text, "@" .. relative))()
end
local behavior_names = {}
local function functions(prefix)
  return setmetatable({}, {__index=function(t,k)
    local f=function() error("Behavior execution forbidden in exporter: " .. prefix .. "." .. k) end
    behavior_names[f]=prefix .. "." .. k; rawset(t,k,f); return f
  end})
end
local function scripts(prefix)
  return setmetatable({}, {__index=function(t,k) local v=functions(prefix .. "." .. k);rawset(t,k,v);return v end})
end
package.loaded.scripts=scripts("scripts")
package.loaded.game_scripts=scripts("game_scripts")
package.loaded.i18n={cjk=function(_,a) return a end}
package.loaded["all.rally_utils"]=functions("rally_utils")
package.loaded.achievements=functions("achievements")
local U={fts=function(v) return v/30 end}
U.set_terrain_style=function(e,style)
  e.tower.terrain_style=style
  if not (e.tower_holder and e.tower_holder.blocked) and not e.render.sprites[1].animated then
    e.render.sprites[1].name=assert(TERRAIN_STYLE_SPRITE_DICT[style])
  end
end
package.loaded.utils=U
local function run()
  math.randomseed(1)
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
  local function read(relative) local f=assert(io.open(source.."/"..relative,"rb"));local s=f:read("*a");f:close();return s end
  -- Game-template dependencies are loaded individually; never execute the full
  -- file (which would register every generation, hero and optional tower).
  local function load_game_template(id)
    if E.entities[id] then return end
    local path="kr1/game_templates.lua"
    local text=read(path)
    local a=assert(text:find('tt = RT("'..id..'"',1,true),spec.folder..": missing game template "..id)
    local b=text:find("\ntt = ",a+1,true) or #text+1
    local body=text:sub(a,b-1)
    local base=body:match('^tt = RT%([^,]+,%s*"([^"]+)"')
    if base and not E.entities[base] then load_game_template(base) end
    local header='local tt;local anchor_x,anchor_y,image_x,image_y=0,0,0,0;local scripts=require("game_scripts");local v=vec_2;local vv=vec_1;local function adx(x) return x-anchor_x*image_x end;local function ady(y) return y-anchor_y*image_y end;'
    chunk(path,header..body)
  end
  -- Source wave/layout tables are dependency roots, not hand-maintained enemy lists.
  local source_tables={}
  for _,pair in ipairs({{"layout","kr1/data/levels/"..level_name.."_data.lua"},{"paths","kr1/data/levels/"..level_name.."_paths.lua"},{"terrain","kr1/data/levels/"..level_name.."_grid.lua"},{"waves","kr1/data/waves/"..level_name.."_waves_campaign.lua"}}) do
    local f=assert(loadstring(read(pair[2]),"@"..pair[2]));setfenv(f,{v=V.v})
    source_tables[pair[1]]=f();loaded_inputs[pair[2]]=true
  end
  if not ranger_arena then
    source_tables.modes={}
    for _,mode in ipairs(spec.modes) do
      if mode ~= 1 then
        local name=assert(({[2]="heroic",[3]="iron"})[mode],spec.folder..": unsupported mode "..tostring(mode))
        local path="kr1/data/waves/"..level_name.."_waves_"..name..".lua"
        local f=assert(loadstring(read(path),"@"..path));setfenv(f,{v=V.v})
        source_tables.modes[tostring(mode)]={waves=f()};loaded_inputs[path]=true
      end
    end
  end
  local foundation=read("kr1/foundamental_towers.lua")
  chunk("kr1/foundamental_towers.lua",foundation:sub(1,assert(foundation:find('tt = RT("tower_neptune_holder")',1,true))-1))
  local enemies=read("kr1/enemies.lua")
  local header=enemies:sub(1,assert(enemies:find("tt = RT(",1,true))-1)
  local enemy_ids=table.deepclone(spec.export.enemy_ids)
  local enemy_set={};for _,id in ipairs(enemy_ids) do enemy_set[id]=true end
  local function wave_roots(program)
    for _,group in ipairs(program.groups) do for _,wave in ipairs(group.waves) do for _,spawn in ipairs(wave.spawns) do
      for _,key in ipairs({"creep","creep_aux"}) do
        local id=spawn[key]
        if id and id~="" and not enemy_set[id] then enemy_set[id]=true;table.insert(enemy_ids,id) end
      end
    end end end
  end
  wave_roots(source_tables.waves)
  for _,variant in pairs(source_tables.modes or {}) do wave_roots(variant.waves) end
  local function load_enemy(id)
    if E.entities[id] then return end
    local start=assert(enemies:find('tt = RT("'..id..'"',1,true),spec.folder..": wave/template -> missing enemy "..id)
    local finish=enemies:find("\ntt = ",start+1,true) or #enemies+1
    local body=enemies:sub(start,finish-1)
    local base=body:match('^tt = RT%([^,]+,%s*"([^"]+)"')
    if base and not E.entities[base] then load_enemy(base) end
    chunk("kr1/enemies.lua",header..body)
  end
  local load_capabilities = assert(love.filesystem.load("capabilities.lua"))()
  load_capabilities({read=read,chunk=chunk,features=spec.features,template=load_game_template,callback=function(fn,id) behavior_names[fn]=id end})
  for _,id in ipairs(enemy_ids) do load_enemy(id) end
  local game=read("kr1/game_templates.lua")
  local start=assert(game:find('tt = RT("re_farmer",',1,true))
  local finish=assert(game:find('tt = RT("re_farmer_well_fed",',start,true))
  chunk("kr1/game_templates.lua","local tt;local image_y;local anchor_y;local scripts=require('game_scripts');local function ady(v) return v-anchor_y*image_y end;"..game:sub(start,finish-1))
  behavior_names[E.entities.re_farmer.main_script.insert]="kr1.game_templates.re_farmer.insert"
  local function clean(v)
    local kind=type(v)
    if kind=="function" then return assert(behavior_names[v],spec.folder..": unmapped source callback") end
    if kind=="number" and (v==math.huge or v==-math.huge) then return v>0 and 1e99 or -1e99 end
    if kind=="cdata" then
      local ok,x,y=pcall(function() return tonumber(v.x),tonumber(v.y) end)
      if ok then return {x=x,y=y} end
      local rally,center,pos=pcall(function() return clean(v.center),clean(v.pos) end)
      if rally then return {center=center,pos=pos} end
      error("Unsupported exported cdata: "..tostring(v))
    end
    if kind~="table" then return v end
    local out={};for k,value in pairs(v) do out[k]=clean(value) end;return out
  end
  local fields=spec.export.fields
  local out={templates={},behaviors={},dependencies={},callbacks={},inputs=loaded_inputs,constants={FPS=FPS,ASPECT=ASPECT,TERRAIN_LAND=TERRAIN_LAND,TERRAIN_NOWALK=TERRAIN_NOWALK,DAMAGE_PHYSICAL=DAMAGE_PHYSICAL,DAMAGE_MAGICAL=DAMAGE_MAGICAL,DAMAGE_EXPLOSION=DAMAGE_EXPLOSION,DAMAGE_TRUE=DAMAGE_TRUE}}
  out.constants.spatial_cell_size=SPATIAL_HASH_CELL_SIZE
  out.constants.spatial_origin={x=IN_GAME_X_MIN,y=IN_GAME_Y_MIN}
  for _,name in ipairs(spec.export.constants or {}) do out.constants[name]=assert(_G[name]) end
  for key,value in pairs(source_tables) do out[key]=clean(value) end
  for _,id in ipairs(out.layout.required_templates or {}) do chunk("kr1/template_groups/"..id..".lua") end
  local template_ids=table.deepclone(spec.export.template_ids)
  for _,id in ipairs(enemy_ids) do table.insert(template_ids,id) end
  for _,entity in ipairs(out.layout.entities_list) do
    if entity.template ~= "decal_background" and entity.template ~= "decal_defend_point" and entity.template ~= "editor_wave_flag" then
      assert(E.entities[entity.template],spec.folder..": layout -> missing template "..entity.template)
      table.insert(template_ids,entity.template)
    end
  end
  local references={bullet=true,mod=true,hit_fx=true,hit_decal=true,hit_blood_fx=true,soldier_type=true,entity=true}
  for _,name in ipairs(spec.export.reference_fields or {}) do references[name]=true end
  local unsupported={}
  local function export_template(id,origin)
    if out.templates[id] then return end
    if not E.entities[id] and id:match('^enemy_') then load_enemy(id) end
    if not E.entities[id] and (has("arcane") or has("paladin") or has("juggernaut")) then load_game_template(id) end
    assert(E.entities[id],spec.folder..": "..origin.." -> missing template "..id)
    local t=E:get_template(id);local filtered={};for _,key in ipairs(fields) do if t[key]~=nil then filtered[key]=clean(t[key]) end end
    if spec.export.validate_callbacks then
      local supported={main_script=true,editor=true,editor_script=true,nav_grid=true,nav_path=true,pos=true,tower_upgrade_persistent_data=true,idle_flip=true,tower_holder=true,user_power=true,user_selection=true}
      for _,key in ipairs(fields) do supported[key]=true end
      for key,value in pairs(t) do
        if type(value)=="table" and not supported[key] then unsupported[key]=id end
      end
    end
    if t.bullet then filtered.behavior=clean(t.main_script.update) end
    out.templates[id]=filtered
    if spec.export.validate_callbacks then
      out.callbacks[id]={}
      for key,fn in pairs(t.main_script or {}) do
        if type(fn)=="function" then out.callbacks[id][key]=assert(behavior_names[fn],spec.folder..": "..id..".main_script."..key.." -> unmapped source callback") end
      end
    end
    if t.modifier or t.aura or t.spawner or t.fireball_count or t.enemy or t.soldier or t.bullet or (t.tower and not t.tower_holder) then
      local fn=t.main_script and (t.main_script.update or t.main_script.insert)
      assert(fn and behavior_names[fn],spec.folder..": "..id.." has an unmapped behavior")
      out.behaviors[id]=behavior_names[fn]
    end
    local found={}
    local function visit(value)
      if type(value)~="table" then return end
      for key,child in pairs(value) do
        if references[key] and type(child)=="string" and child~="" then found[child]=true end
        visit(child)
      end
    end
    visit(filtered)
    local dependencies={};for child in pairs(found) do dependencies[#dependencies+1]=child end;table.sort(dependencies)
    out.dependencies[id]=dependencies
    for _,child in ipairs(dependencies) do export_template(child,id) end
  end
  for _,id in ipairs(template_ids) do export_template(id,"wave/layout/adapter") end
  local errors={};for key,id in pairs(unsupported) do errors[#errors+1]=id.."."..key end;table.sort(errors)
  assert(#errors==0,spec.folder..": wave/layout/dependencies -> unsupported components: "..table.concat(errors,", "))
  -- UI data only: evaluate the Chinese CJK branch, without loading any UI runtime.
  package.loaded.i18n.cjk=function(_,default,zh) return zh or default end
  _G._=function(key) return key end
  for _,key in ipairs({"N_ENEMY","N_TUTORIAL","N_TIP","N_POWER","N_TOWER","N_TOWER_2","N_TOWER_4"}) do _G[key]=key end
  local gui=chunk("kr1-desktop/data/game_gui_data.lua")
  out.ui={notifications={},slides={},balloons={},tower_menu_button_places=clean(gui.tower_menu_button_places),tower_menu_center_x=gui.tower_menu_center_x,tower_menu_center_y=gui.tower_menu_center_y}
  local notification_ids=spec.export.notification_ids
  for _,id in ipairs(notification_ids) do
    out.ui.notifications[id]=clean(gui.notifications[id]);out.ui.slides[id]=clean(gui.notification_slides[id])
  end
  out.ui.tutorial_balloons={}
  for _,id in ipairs({"TB_BUILD","TB_START","TB_POWER1","TB_POWER2","TB_ROAD"}) do out.ui.tutorial_balloons[id]=clean(gui.tutorial_balloons[id]) end
  package.loaded["data.tower_menus_data_templates"]=chunk("kr1/data/tower_menus_data_templates.lua")
  local menus=chunk("kr1/data/tower_menus_data.lua")
  out.ui.tower_menus={holder=clean(menus.holder[1])}
  out.ui.upgrade_menus={}
  for _,kind in ipairs({"archer","barrack","mage","engineer"}) do
    out.ui.tower_menus[kind]=clean(menus[kind][1])
    for level=1,(has("tier3") and 2 or 1) do
      local item=menus[kind][level][1]
      out.ui.upgrade_menus[item.action_arg]=clean(item)
    end
  end
  if advanced then
    out.ui.tower_menus.ranger=clean(menus.ranger[1])
    out.ui.upgrade_menus.tower_ranger=clean(menus.archer[3][1])
  end
  if has("elf") then
    out.ui.tower_menus.holder_elf=clean(menus.holder_elf[1]);out.ui.tower_menus.elf=clean(menus.elf[1])
    out.ui.upgrade_menus.tower_elf=clean(menus.holder_elf[1][1])
  end
  for _,kind in ipairs(spec.export.tower_menus or {}) do out.ui.tower_menus[kind]=clean(menus[kind][1]) end
  for _,key in ipairs(spec.export.upgrade_menus or {}) do
    local kind,level,index=key:match("([^:]+):(%d+):(%d+)")
    local item=menus[kind][tonumber(level)][tonumber(index)]
    out.ui.upgrade_menus[item.action_arg]=clean(item)
  end
  local strings=chunk("_assets/kr1-desktop/strings/zh-Hans.lua")
  out.ui.strings={}
  local function collect(v)
    if type(v)=="string" and strings[v] then out.ui.strings[v]=strings[v]
    elseif type(v)=="table" then for _,value in pairs(v) do collect(value) end end
  end
  collect(out.ui)
  for _,prefix in ipairs(spec.export.power_prefixes or {}) do
    out.ui.power_descriptions=out.ui.power_descriptions or {}
    for _,item in ipairs(out.ui.tower_menus[string.lower(prefix)] or {}) do
      if item.action_arg and item.tt_list then
        local descriptions={}
        for level,entry in ipairs(item.tt_list) do
          local description=assert(strings[entry.tt_desc],entry.tt_desc)
          description=description:gsub("%%%$(.-)%%%$",function(expr)
            local fn=assert(loadstring("return "..expr,"@power_description"))
            setfenv(fn,{T=function(id) return E:get_template(id) end,level=level,tdmg=1,tcd=1,math=math})
            return string.format("%g",fn())
          end)
          descriptions[level]=description
        end
        out.ui.power_descriptions[item.action_arg]=descriptions
      end
    end
  end
  if has("elf") then
    for _,prefix in ipairs({"TOWER_RANGER","TOWER_ELF"}) do
      for _,suffix in ipairs({"_NAME","_EXTRA"}) do out.ui.strings[prefix..suffix]=assert(strings[prefix..suffix]) end
    end
  end
  if advanced then
    -- Evaluate only the selected frozen arithmetic expressions, without gameplay.
    out.ui.power_descriptions=out.ui.power_descriptions or {}
    for _,power in ipairs(has("elf") and {"poison","thorn","bleed","cripple"} or {"poison","thorn"}) do
      local descriptions={}
      for level=1,3 do
        local key="TOWER_"..((power == "bleed" or power == "cripple") and "ELF_" or "RANGER_")..string.upper(power).."_DESCRIPTION_"..level
        local text=assert(strings[key])
        text=text:gsub("%%%$(.-)%%%$",function(expr)
          local f=assert(loadstring("return "..expr,"@ranger_description"))
          setfenv(f,{T=function(id) return E:get_template(id) end,level=level,tdmg=1,tcd=1})
          return string.format("%g",f())
        end)
        descriptions[level]=text
      end
      out.ui.power_descriptions[power]=descriptions
    end
  end
  for _,id in ipairs(enemy_ids) do
    local prefix=string.upper(id)
    for _,suffix in ipairs({"_NAME","_DESCRIPTION","_EXTRA"}) do out.ui.strings[prefix..suffix]=strings[prefix..suffix] or "" end
  end
  out.ui.unit_names={}
  for id,t in pairs(out.templates) do
    if t.info and t.info.random_name_format then
      local names={};for i=1,t.info.random_name_count do local k=string.format(t.info.random_name_format,i);names[i]=strings[k] or k end;out.ui.unit_names[id]=names
    end
    if t.info then local key=(t.info.i18n_key or string.upper(id)).."_NAME";out.ui.strings[key]=strings[key] or key end
  end
  for _,id in ipairs({"TB_BUILD","TB_START","TB_POWER1","TB_POWER2","TB_ROAD"}) do out.ui.slides[id]=clean(gui.notification_slides[id]);collect(out.ui.slides[id]) end
  for _,key in ipairs({"INSTRUCTIONS","HINT","NEW SPECIAL POWER!","POWER_REINFORCEMENTS_NAME","POWER_REINFORCEMENTS_LARGE_DESCRIPTION","POWER_FIREBALL_NAME","POWER_FIREBALL_LARGE_DESCRIPTION","MENU_HUD_WAVES","I'm ready. Now bring it on!"}) do out.ui.strings[key]=strings[key] or key end
  local json=require("lib.json")
  local function encode(v)
    if type(v)~="table" then return json.encode(v) end
    local max,count,array=0,0,true
    for k in pairs(v) do count=count+1;if type(k)~="number" or k<1 or k%1~=0 then array=false else max=math.max(max,k) end end
    local parts={}
    if array and count>0 then
      for i=1,max do parts[#parts+1]=v[i]==nil and "null" or encode(v[i]) end
      return "["..table.concat(parts,",").."]"
    end
    local keys={};for k in pairs(v) do keys[#keys+1]=k end;table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,k in ipairs(keys) do parts[#parts+1]=json.encode(tostring(k))..":"..encode(v[k]) end
    return "{"..table.concat(parts,",").."}"
  end
  local f=assert(io.open(destination,"wb"));f:write(encode(out));f:close()
end
function love.load()
  local ok,err=xpcall(run,debug.traceback)
  if not ok then local f=assert(io.open(destination..".error","wb"));f:write(err);f:close() end
  love.event.quit(ok and 0 or 1)
end
