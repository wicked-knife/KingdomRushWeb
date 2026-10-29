-- Independent oracle: raw frozen tables and original wave spawner / ray scripts.
-- Never reads the generated Godot definition and never starts the Dove game.
function love.errorhandler(message) io.stderr:write(message,"\n");os.exit(1) end
function love.load()
  local root=assert(os.getenv("DOVE_SOURCE_DIR"))
  package.path=root.."/?.lua;"..root.."/all/?.lua;"..package.path
  require("lib.klua.table");require("all.constants")
  local V=require("lib.klua.vector");local json=require("lib.json");local bit=require("bit")
  local function read(path) local f=assert(io.open(root.."/"..path,"rb"));local t=f:read("*a");f:close();return t end
  local function eval(path) local f=assert(loadstring(read(path)));setfenv(f,{v=V.v});return f() end
  local result={source_commit=json.decode(assert(io.open(assert(os.getenv("DOVE_CATALOG")),"rb")):read("*a")).source.commit,layout=eval("kr1/data/levels/level07_data.lua"),modes={},timelines={},rays={}}
  local wave_source=read("all/systems/wave_spawn.lua")
  local body=assert(wave_source:match("local function spawner%(store, wave, group_id%)(.-)\nfunction wave_spawn:init"))
  body=body:gsub("\nend%s*$","")
  local current,entries,group,route,subpath
  local env={math=math,random=function() return 0 end,fts=function(v)return v/30 end,
    configer={config=function()return {enabled=false}end},DI={level=2},DIFFICULTY_HARD=3,
    P={paths={{1,2,3},{1,2,3},{1,2,3},{1,2,3},{1,2,3}},get_start_node=function()return 1 end},
    E={create_entity=function(_,name)return {template=name,nav_path={}}end},
    U={y_wait_unconditional=function(store,seconds)
      local until_tick=current+math.floor(seconds*30+0.5)
      while current<until_tick do coroutine.yield()end
    end},simulation={queue_insert_entity=function(_,entity)
      entries[#entries+1]={current,entity.template,entity.nav_path.pi-1,subpath,route}
    end}}
  setmetatable(env,{__index=_G})
  local fn=assert(loadstring("return function(store,wave,group_id)"..body.."\nend"));setfenv(fn,env);local spawner=fn()
  for mode,name in ipairs({"campaign","heroic","iron"}) do
    local waves=eval("kr1/data/waves/level07_waves_"..name..".lua")
    result.modes[tostring(mode)]=waves;local groups={}
    for gi,g in ipairs(waves.groups)do
      entries={}
      for wi,w in ipairs(g.waves)do
        current=w.delay;route=wi
        -- This fixture compares random routes by legal domain; fixed routes exact.
        local co=coroutine.create(function()return spawner({},w,gi)end)
        while coroutine.status(co)~="dead" do
          subpath=-1
          env.E.create_entity=function(_,template)
            -- Recover the current source spawn segment from emitted ordinal.
            return {template=template,nav_path={}}
          end
          local ok,err=coroutine.resume(co);assert(ok,err);current=current+1
        end
      end
      table.sort(entries,function(a,b)return a[1]<b[1] or a[1]==b[1] and a[5]<b[5] end)
      -- fixed_sub_path is reconstructed from each lane's sequential source program.
      local lane_index={}
      for _,entry in ipairs(entries)do
        local lane=entry[5];lane_index[lane]=(lane_index[lane]or 0)+1;local n=lane_index[lane]
        for _,s in ipairs(g.waves[lane].spawns)do
          if n<=s.max then entry[4]=s.fixed_sub_path==1 and s.path-1 or -1;break end
          n=n-s.max
        end
        entry[1]=math.max(1,entry[1]);entry[5]=nil
      end
      groups[#groups+1]=entries
    end
    result.timelines[tostring(mode)]=groups
  end
  assert(loadfile(assert(os.getenv('DOVE_PROJECT'))..'/tools/level07_reference/behavior.lua'))()(root,result,read,V,json,bit)
  local function clean(value)
    if type(value)=="cdata" then return {x=tonumber(value.x),y=tonumber(value.y)} end
    if type(value)~="table" then return value end
    local out={};for k,v in pairs(value)do out[k]=clean(v)end;return out
  end
  local function encode(value)
    if type(value)~="table" then return json.encode(value) end
    local max,count,array=0,0,true
    for k in pairs(value)do count=count+1;if type(k)~="number" or k<1 or k%1~=0 then array=false else max=math.max(max,k)end end
    local parts={}
    if array and count>0 then for i=1,max do parts[#parts+1]=value[i]==nil and "null" or encode(value[i])end;return "["..table.concat(parts,",").."]"end
    local keys={};for k in pairs(value)do keys[#keys+1]=k end;table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
    for _,k in ipairs(keys)do parts[#parts+1]=json.encode(tostring(k))..":"..encode(value[k])end
    return "{"..table.concat(parts,",").."}"
  end
  local encoded=encode(clean(result))
  local f=assert(io.open(assert(os.getenv("DOVE_REFERENCE_OUTPUT")),"wb"));f:write(encoded);f:close()
  love.event.quit(0)
end
