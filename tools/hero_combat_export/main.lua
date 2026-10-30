-- Source-only actor bundle. Never opens game saves, plugins or the game itself.
function love.load()
  local ok,err=xpcall(function()
    local root=assert(os.getenv("DOVE_SOURCE_DIR"))
    local output=assert(os.getenv("DOVE_EXPORT_PATH"))
    package.path=root.."/?.lua;"..root.."/all/?.lua;"..root.."/kr1/?.lua;"..package.path
    require("lib.klua.table"); require("all.constants")
    local V=require("lib.klua.vector")
    _G.V=V; _G.vec_2=V.v; _G.vec_1=V.vv; _G.r=V.r; _G.fts=function(v) return v/30 end
    _G.IS_PHONE=false; _G.IS_PHONE_OR_TABLET=false; _G.IS_CONSOLE=false
    local inputs={}; local names={}
    local function functions(prefix)
      return setmetatable({}, {__index=function(t,k)
        local fn=function() error("Behavior execution forbidden in actor exporter") end
        names[fn]=prefix.."."..k; rawset(t,k,fn); return fn
      end})
    end
    local function scripts(prefix)
      return setmetatable({}, {__index=function(t,k) local v=functions(prefix.."."..k);rawset(t,k,v);return v end})
    end
    package.loaded.scripts=scripts("scripts"); package.loaded.game_scripts=scripts("game_scripts")
    package.loaded.script_utils=functions("script_utils")
    package.loaded.utils={fts=fts}; package.loaded.i18n={cjk=function(_,v) return v end}
    package.loaded["all.rally_utils"]=functions("rally_utils"); package.loaded.achievements=functions("achievements")
    local E={entities={},components={}}
    function E:register_c(n,base) local v=base and table.deepclone(assert(self.components[base])) or {};self.components[n]=v;return v end
    function E:register_c_ffi(n,v) self.components[n]=v end
    function E:clone_c(n) return table.deepclone(assert(self.components[n],n)) end
    function E:register_t(n,base) local v=base and table.deepclone(assert(self.entities[base],base)) or {};v.template_name=n;self.entities[n]=v;return v end
    E.register_t_hot=E.register_t
    function E:add_comps(t,...) for _,n in ipairs({...}) do t[n]=self:clone_c(n) end end
    function E:get_template(n) return assert(self.entities[n],n) end
    _G.E=E; package.loaded.entity_db=E
    local function read(path) inputs[path]=true;local f=assert(io.open(root.."/"..path,"rb"));local s=f:read("*a");f:close();return s end
    local function chunk(path,text) return assert(loadstring(text or read(path),"@"..path))() end
    chunk("all/components.lua"); package.loaded.components=true
    chunk("all/templates.lua"); package.loaded.templates=true
    chunk("kr1/game_templates_utils.lua"); package.loaded.game_templates_utils=true
    local heroes=read("kr1/heroes.lua")
    local header=heroes:sub(1,assert(heroes:find('tt = RT(',1,true))-1)
    local a=assert(heroes:find('tt = RT("hero_malik",',1,true))
    local b=assert(heroes:find('tt = RT("hero_denas",',a,true))
    chunk("kr1/heroes.lua",header..heroes:sub(a,b-1))
    local function clean(v)
      if type(v)=="function" then return assert(names[v],"Unmapped source callback") end
      if type(v)=="number" and math.abs(v)==math.huge then return v>0 and 1e99 or -1e99 end
      if type(v)=="cdata" then
        local ok,x,y=pcall(function() return tonumber(v.x),tonumber(v.y) end)
        if ok then return {x=x,y=y} end
        local ok,c,p=pcall(function() return clean(v.center),clean(v.pos) end)
        if ok then return {center=c,pos=p} end
        error("Unsupported actor cdata: "..tostring(v))
      end
      if type(v)~="table" then return v end
      local out={}; for k,value in pairs(v) do out[k]=clean(value) end;return out
    end
    local fields={"template_name","render","health","health_bar","motion","unit","soldier","melee","sound_events","ui","regen","tween","info","vis","hero","nav_grid","modifier","stun","aura"}
    local refs={hit_aura=true,hit_fx=true,hit_decal=true,fx=true,mod=true,tombstone_decal=true}
    local out={templates={},behaviors={},dependencies={},callbacks={},inputs=inputs}
    local function export(id)
      if out.templates[id] then return end
      local t=E:get_template(id);local row={}; for _,key in ipairs(fields) do if t[key]~=nil then row[key]=clean(t[key]) end end
      out.templates[id]=row
      if t.hero then row.hero_rally={immune_to=tonumber(t.nav_rally.immune_to),requires_node_nearby=t.nav_rally.requires_node_nearby} end
      if t.main_script and t.main_script.update then out.behaviors[id]=clean(t.main_script.update) end
      out.callbacks[id]={}
      for key,fn in pairs(t.main_script or {}) do if type(fn)=="function" then out.callbacks[id][key]=clean(fn) end end
      local found={}
      local function visit(v)
        if type(v)~="table" then return end
        for k,child in pairs(v) do if refs[k] and type(child)=="string" and child~="" then found[child]=true end; visit(child) end
      end
      visit(row); out.dependencies[id]={}
      for child in pairs(found) do out.dependencies[id][#out.dependencies[id]+1]=child; export(child) end
      table.sort(out.dependencies[id])
    end
    export("hero_malik")
    -- These dependencies are created by the shared hero death coroutine.
    for _,id in ipairs({"fx_soldier_desintegrate","fx_unit_explode","decal_blood_pool"}) do
      export(id);table.insert(out.dependencies.hero_malik,id)
    end
    local GS=chunk("kr1/game_settings.lua")
    out.rules={hero_xp_thresholds=GS.hero_xp_thresholds,hero_xp_gain_per_difficulty_mode=GS.hero_xp_gain_per_difficulty_mode,soldier_regen_factor=GS.soldier_regen_factor}
    out.rules.death_hide_types=bit.bor(DAMAGE_DISINTEGRATE,DAMAGE_EAT,DAMAGE_HOST)
    local strings=chunk("_assets/kr1-desktop/strings/zh-Hans.lua")
    out.strings={}
    for id,t in pairs(out.templates) do if t.info then local key=(t.info.i18n_key or string.upper(id)).."_NAME";out.strings[key]=strings[key] or key end end
    inputs["kr1/hero_scripts.lua"]=true;inputs["kr1/hero_utils.lua"]=true;inputs["all/script_utils.lua"]=true
    inputs["all/level_utils.lua"]=true;inputs["all/grid_db.lua"]=true;inputs["all/systems/health.lua"]=true
    for _,path in ipairs({"all/grid_a_star.lua","all/path_db.lua","all/utils.lua","all/systems/render.lua","all/systems/level.lua","all-desktop/game_gui.lua"})do inputs[path]=true end
    local json=require("lib.json")
    local function encode(v)
      if type(v)=="number" then return string.format("%.17g",v) end
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
    if os.getenv("DOVE_HERO_REFERENCE") then
      out=assert(loadfile(os.getenv("DOVE_HERO_REFERENCE")))()(root,E,GS,read)
    end
    local f=assert(io.open(output,"wb")); f:write(encode(clean(out))); f:close()
  end,debug.traceback)
  if not ok then
    local f=assert(io.open(assert(os.getenv("DOVE_EXPORT_PATH"))..".error","wb"));f:write(err);f:close();io.stderr:write(err,"\n")
  end
  love.event.quit(ok and 0 or 1)
end
