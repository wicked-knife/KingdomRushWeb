-- Offline template evaluation. Never loads Dove main.lua, saves, updater or plugins.
function love.errorhandler(msg)
  local f=io.open((os.getenv("DOVE_EXPORT_PATH") or "export")..".error","wb");if f then f:write(tostring(msg));f:close() end
  os.exit(1)
end
local source = assert(os.getenv("DOVE_SOURCE_DIR"))
local destination = assert(os.getenv("DOVE_EXPORT_PATH"))
local level_id = tonumber(os.getenv("DOVE_LEVEL_ID") or "1")
local ranger_arena = os.getenv("DOVE_RANGER_ARENA") == "1"
assert(level_id >= 1 and level_id <= 5)
local advanced = ranger_arena or level_id == 5
local level_name = string.format("level%02d", level_id)
package.path = source .. "/?.lua;" .. source .. "/all/?.lua;" .. source .. "/kr1/?.lua;" .. package.path
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
  local foundation=read("kr1/foundamental_towers.lua")
  chunk("kr1/foundamental_towers.lua",foundation:sub(1,assert(foundation:find('tt = RT("tower_neptune_holder")',1,true))-1))
  local enemies=read("kr1/enemies.lua")
  local header=enemies:sub(1,assert(enemies:find("tt = RT(",1,true))-1)
  local enemy_ids={"enemy_goblin","enemy_fat_orc"}
  if level_id >= 2 then table.insert(enemy_ids,"enemy_wolf_small") end
  if level_id >= 3 then table.insert(enemy_ids,"enemy_shaman");table.insert(enemy_ids,"enemy_ogre") end
  if level_id >= 4 then table.insert(enemy_ids,"enemy_bandit");table.insert(enemy_ids,"enemy_brigand") end
  if ranger_arena then table.insert(enemy_ids,"enemy_spider_small") end
  if level_id == 5 then
    for _,id in ipairs({"enemy_wolf","enemy_spider_tiny","enemy_spider_small","enemy_spider_big","enemy_spider_egg","enemy_marauder"}) do table.insert(enemy_ids,id) end
  end
  for _,id in ipairs(enemy_ids) do
    local start=assert(enemies:find('tt = RT("'..id..'"',1,true))
    local finish=enemies:find("\ntt = ",start+1,true) or #enemies+1
    chunk("kr1/enemies.lua",header..enemies:sub(start,finish-1))
  end
  local game=read("kr1/game_templates.lua")
  local start=assert(game:find('tt = RT("re_farmer",',1,true))
  local finish=assert(game:find('tt = RT("re_farmer_well_fed",',start,true))
  chunk("kr1/game_templates.lua","local tt;local image_y;local anchor_y;local scripts=require('game_scripts');local function ady(v) return v-anchor_y*image_y end;"..game:sub(start,finish-1))
  if level_id >= 3 then
    local a=assert(game:find('tt = RT("mod_shaman_heal",',1,true))
    local b=assert(game:find('\ntt = ',a+1,true))
    chunk("kr1/game_templates.lua","local tt;local scripts=require('game_scripts');"..game:sub(a,b-1))
  end
  if advanced then
    local archers=read("kr1/archer_towers.lua")
    chunk("kr1/archer_towers.lua",archers:sub(1,assert(archers:find('local tower_crossbow = RT(',1,true))-1))
  end
  if level_id == 5 then
    local barracks=read("kr1/barrack_towers.lua")
    local header=barracks:sub(1,assert(barracks:find('tt = RT(',1,true))-1)
    local a=assert(barracks:find('tt = RT("tower_elf_holder")',1,true))
    local b=assert(barracks:find('tt = RT("tower_barrack_amazonas"',a,true))
    chunk("kr1/barrack_towers.lua",header..barracks:sub(a,b-1))
    local heroes=read("kr1/heroes.lua")
    local a=assert(heroes:find('tt = RT("ps_arrow_multishot_hero_alleria")',1,true))
    local b=assert(heroes:find('\ntt = ',a+1,true))
    chunk("kr1/heroes.lua","local tt;"..heroes:sub(a,b-1))
  end
  local function clean(v)
    local kind=type(v)
    if kind=="function" then return behavior_names[v] or "local_source_function" end
    if kind=="cdata" then
      local ok,x,y=pcall(function() return tonumber(v.x),tonumber(v.y) end)
      if ok then return {x=x,y=y} end
      error("Unsupported exported cdata: "..tostring(v))
    end
    if kind~="table" then return v end
    local out={};for k,value in pairs(v) do out[k]=clean(value) end;return out
  end
  local fields={"template_name","render","health","health_bar","motion","unit","enemy","soldier","tower","barrack","attacks","melee","bullet","sound_events","reinforcement","cooldown","duration","fireball_count","max_spread","delayed_play","ui","regen","tween","build_duration","info","dodge","timed_attacks","modifier","hps","vis"}
  if advanced then
    for _,name in ipairs({"powers","dps","slow","aura","damage_min","damage_max","damage_type","damage_every"}) do table.insert(fields,name) end
  end
  if level_id == 5 then for _,name in ipairs({"ranged","mercenary","spawner","particle_system"}) do table.insert(fields,name) end end
  local out={templates={},inputs=loaded_inputs,constants={FPS=FPS,ASPECT=ASPECT,TERRAIN_LAND=TERRAIN_LAND,TERRAIN_NOWALK=TERRAIN_NOWALK,DAMAGE_PHYSICAL=DAMAGE_PHYSICAL,DAMAGE_MAGICAL=DAMAGE_MAGICAL,DAMAGE_EXPLOSION=DAMAGE_EXPLOSION,DAMAGE_TRUE=DAMAGE_TRUE}}
  out.constants.spatial_cell_size=SPATIAL_HASH_CELL_SIZE
  out.constants.spatial_origin={x=IN_GAME_X_MIN,y=IN_GAME_Y_MIN}
  if advanced then
    for _,name in ipairs({"DAMAGE_POISON","F_POISON","F_FLYING","F_BOSS","F_CLIFF"}) do out.constants[name]=_G[name] end
  end
  if level_id == 5 then out.constants.DAMAGE_NO_DODGE=DAMAGE_NO_DODGE;out.constants.F_BLOOD=F_BLOOD end
  for _,pair in ipairs({{"layout","kr1/data/levels/"..level_name.."_data.lua"},{"paths","kr1/data/levels/"..level_name.."_paths.lua"},{"terrain","kr1/data/levels/"..level_name.."_grid.lua"},{"waves","kr1/data/waves/"..level_name.."_waves_campaign.lua"}}) do
    local env={v=V.v};local f=assert(loadstring(read(pair[2]),"@"..pair[2]));setfenv(f,env);out[pair[1]]=clean(f());loaded_inputs[pair[2]]=true
  end
  if not ranger_arena then
    out.modes={}
    for mode,name in ipairs({"heroic","iron"}) do
      local path="kr1/data/waves/"..level_name.."_waves_"..name..".lua"
      local f=assert(loadstring(read(path),"@"..path));setfenv(f,{v=V.v})
      out.modes[tostring(mode+1)]={waves=clean(f())};loaded_inputs[path]=true
    end
  end
  for _,id in ipairs(out.layout.required_templates or {}) do chunk("kr1/template_groups/"..id..".lua") end
  local template_ids={"tower_archer_1","tower_archer_2","tower_barrack_1","tower_barrack_2","tower_mage_1","tower_mage_2","tower_engineer_1","tower_engineer_2","tower_holder_grass","tower_build_archer","tower_build_barrack","tower_build_mage","tower_build_engineer","soldier_militia","soldier_footmen","re_farmer","arrow_1","arrow_2","bolt_1","bolt_2","bomb","bomb_dynamite","power_fireball_control","power_fireball","power_reinforcements_control","fx_fireball_explosion","fx_bolt_hit","fx_explosion_small","fx_unit_explode","decal_bomb_crater","fx_blood_splat","fx_tower_buy_dust","fx_tower_sell_dust"}
  for _,id in ipairs(enemy_ids) do table.insert(template_ids,id) end
  if level_id >= 3 then table.insert(template_ids,"mod_shaman_heal") end
  if level_id >= 4 then
    for _,id in ipairs({"tower_archer_3","tower_barrack_3","tower_mage_3","tower_engineer_3","soldier_knight","arrow_3","bolt_3","bomb_black","fx_explosion_water"}) do table.insert(template_ids,id) end
  end
  if advanced then
    for _,id in ipairs({"tower_ranger","arrow_ranger","aura_ranger_thorn","mod_ranger_poison","mod_thorn","fx_spider_explode"}) do table.insert(template_ids,id) end
  end
  if level_id == 5 then
    for _,id in ipairs({"tower_elf_holder","tower_elf","soldier_elf","arrow_elf","arrow_elf_cripple","mod_elf_bleed","mod_elf_cripple","fx_bleeding","decal_background","ps_arrow_multishot_hero_alleria"}) do table.insert(template_ids,id) end
  end
  for _,entity in ipairs(out.layout.entities_list) do
    if E.entities[entity.template] and entity.template ~= "decal_background" and entity.template ~= "decal_defend_point" and entity.template ~= "editor_wave_flag" then table.insert(template_ids,entity.template) end
  end
  for _,id in ipairs(template_ids) do
    local t=E:get_template(id);local filtered={};for _,key in ipairs(fields) do if t[key]~=nil then filtered[key]=clean(t[key]) end end
    if t.bullet then filtered.behavior=clean(t.main_script.update) end
    out.templates[id]=filtered
  end
  -- UI data only: evaluate the Chinese CJK branch, without loading any UI runtime.
  package.loaded.i18n.cjk=function(_,default,zh) return zh or default end
  _G._=function(key) return key end
  for _,key in ipairs({"N_ENEMY","N_TUTORIAL","N_TIP","N_POWER","N_TOWER","N_TOWER_2","N_TOWER_4"}) do _G[key]=key end
  local gui=chunk("kr1-desktop/data/game_gui_data.lua")
  out.ui={notifications={},slides={},balloons={},tower_menu_button_places=clean(gui.tower_menu_button_places),tower_menu_center_x=gui.tower_menu_center_x,tower_menu_center_y=gui.tower_menu_center_y}
  local notification_ids={"TUTORIAL_1","TUTORIAL_2","TUTORIAL_3","TIP_ARMOR","TIP_RALLY","POWER_REINFORCEMENT","POWER_FIREBALL"}
  if level_id >= 2 then table.insert(notification_ids,"TOWER_LEVEL2");table.insert(notification_ids,"TIP_STRATEGY");table.insert(notification_ids,"enemy_wolf_small") end
  if level_id >= 3 then table.insert(notification_ids,"TIP_ARMOR_MAGIC");table.insert(notification_ids,"enemy_shaman");table.insert(notification_ids,"enemy_ogre") end
  if level_id >= 4 then table.insert(notification_ids,"enemy_bandit");table.insert(notification_ids,"enemy_brigand") end
  if level_id == 5 then for _,id in ipairs({"TOWER_RANGER","enemy_wolf","enemy_spider_small","enemy_spider_big","enemy_marauder"}) do table.insert(notification_ids,id) end end
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
    for level=1,(level_id >= 4 and 2 or 1) do
      local item=menus[kind][level][1]
      out.ui.upgrade_menus[item.action_arg]=clean(item)
    end
  end
  if advanced then
    out.ui.tower_menus.ranger=clean(menus.ranger[1])
    out.ui.upgrade_menus.tower_ranger=clean(menus.archer[3][1])
  end
  if level_id == 5 then
    out.ui.tower_menus.holder_elf=clean(menus.holder_elf[1]);out.ui.tower_menus.elf=clean(menus.elf[1])
    out.ui.upgrade_menus.tower_elf=clean(menus.holder_elf[1][1])
  end
  local strings=chunk("_assets/kr1-desktop/strings/zh-Hans.lua")
  out.ui.strings={}
  local function collect(v)
    if type(v)=="string" and strings[v] then out.ui.strings[v]=strings[v]
    elseif type(v)=="table" then for _,value in pairs(v) do collect(value) end end
  end
  collect(out.ui)
  if level_id == 5 then
    for _,prefix in ipairs({"TOWER_RANGER","TOWER_ELF"}) do
      for _,suffix in ipairs({"_NAME","_EXTRA"}) do out.ui.strings[prefix..suffix]=assert(strings[prefix..suffix]) end
    end
  end
  if advanced then
    -- Evaluate only the selected frozen arithmetic expressions, without gameplay.
    out.ui.power_descriptions={}
    for _,power in ipairs(level_id == 5 and {"poison","thorn","bleed","cripple"} or {"poison","thorn"}) do
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
