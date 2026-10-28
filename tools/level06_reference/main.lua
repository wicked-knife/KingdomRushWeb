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
  local result={source_commit=json.decode(assert(io.open(assert(os.getenv("DOVE_CATALOG")),"rb")):read("*a")).source.commit,layout=eval("kr1/data/levels/level06_data.lua"),modes={},timelines={},rays={}}
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
    local waves=eval("kr1/data/waves/level06_waves_"..name..".lua")
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
  -- Execute the actual frozen mod_ray_arcane body with controlled integer rolls.
  local source=read("kr1/game_scripts.lua")
  local ray=assert(source:match("function scripts.mod_ray_arcane.update%(this, store%)(.-)\nscripts.mod_ray_arcane_disintegrate =")):gsub("\nend%s*$","")
  for _,hp in ipairs({50,1000})do
    local target={id=1,pos=V.v(0,0),health={hp=hp,dead=false},unit={hit_offset=V.v(0,0)}}
    local store={tick_ts=0,entities={[1]=target}};local hits={}
    local rayenv=setmetatable({math=setmetatable({random=function()return 101 end},{__index=math}),
      E={assign_damage=function(dtype,value,source_id,target_id)return {value=value}end},
      queue_damage=function(_,d)hits[#hits+1]={current,d.value};target.health.hp=target.health.hp-d.value;target.health.dead=target.health.hp<=0 end,
      simulation={queue_remove_entity=function()end},log={paranoid=function()end}}, {__index=_G})
    local f=assert(loadstring("return function(this,store)"..ray.."\nend"));setfenv(f,rayenv)
    local this={id=2,modifier={target_id=1,duration=10/30,damage_factor=1},dps={damage_min=101,damage_max=101,damage_type=4,damage_every=2/30}}
    local co=coroutine.create(function()f()(this,store)end)
    for tick=0,20 do current=tick;store.tick_ts=tick/30;if coroutine.status(co)=="dead"then break end;local ok,err=coroutine.resume(co);assert(ok,err)end
    result.rays[tostring(hp)]=hits
  end
  -- Execute the original tracking missile with a controlled target death.
  -- The fixed selector returns the first eligible unit; this isolates movement
  -- and re-target timing from the two engines' different PRNG implementations.
  local allscripts=read("all/scripts.lua")
  local missile=assert(allscripts:match("function scripts.enemy_missile.update%(this, store%)(.-)\nscripts.bolt_enemy =")):gsub("\nend%s*$","")
  local units={}
  for i,pos in ipairs({V.v(300,350),V.v(180,260)})do units[i]={id=i,pos=pos,health={hp=1000,dead=false},vis={flags=F_FRIEND,bans=0},unit={hit_offset=V.v(0,12)}}end
  local projectile={id=3,pos=V.v(100,100),render={sprites={{animated=true}}},sound_events={hit="hit"},bullet={target_id=1,from=V.v(100,100),to=V.v(112,270),speed=V.v(0,0),min_speed=300,max_speed=450,turn_speed=5.235987755983,acceleration_factor=0.1,retarget_range=1e99,rot_dir_from_long_angle=true,vis_flags=F_RANGED,vis_bans=F_ENEMY,damage_flags=F_AREA,damage_bans=bit.bor(F_ENEMY,F_BOSS),damage_radius=41.25,damage_type=DAMAGE_PHYSICAL,damage_factor=1,damage_min=150,damage_max=250,hit_fx="fx"}}
  local store={tick_ts=0,tick_length=1/30,entities=units};local done=false;local hits={}
  local U={animation_start_default=function()end,find_random_target=function(_,origin,min,max,flags,bans)
    for _,unit in ipairs(units)do if not unit.health.dead and bit.band(unit.vis.flags,bans)==0 and bit.band(unit.vis.bans,flags)==0 then return unit end end
  end,is_inside_ellipse=function(p,c,r)return (p.x-c.x)^2+((p.y-c.y)/0.7)^2<=r*r end,
  dist_factor_inside_ellipse=function(p,c,r)return math.min(1,math.sqrt((p.x-c.x)^2+((p.y-c.y)/0.7)^2)/r)end}
  local menv=setmetatable({V=V,U=U,band=bit.band,km={clamp=function(a,b,x)return math.max(a,math.min(b,x))end},S={queue=function()end},
    E={create_entity=function()return {pos=V.v(0,0),render={sprites={{}}}}end,assign_damage=function(_,value,_,id)return {value=value,target=id}end},
    queue_damage=function(_,d)hits[#hits+1]={current,d.target,d.value}end,
    simulation={queue_insert_entity=function()end,queue_remove_entity=function()done=true end}}, {__index=_G})
  local f=assert(loadstring("return function(this,store)"..missile.."\nend"));setfenv(f,menv)
  local co=coroutine.create(function()f()(projectile,store)end);local samples={}
  for tick=0,240 do
    current=tick;store.tick_ts=tick/30
    if tick==25 then units[1].health.dead=true end
    local ok,err=coroutine.resume(co);assert(ok,err)
    samples[#samples+1]={tick,projectile.pos.x,projectile.pos.y,projectile.bullet.to.x,projectile.bullet.to.y,projectile.bullet.speed.x,projectile.bullet.speed.y}
    if done then break end
  end
  result.missile={samples=samples,hits=hits,first_target_dies_at=25}
  -- Original summon coroutine, with a fixed path node and quantized waits.
  local spawnbody=assert(allscripts:match("function scripts.enemies_spawner.update%(this, store%)(.-)\nscripts.delayed_spawn =")):gsub("\nend%s*$","")
  result.spawners={}
  for _,death_tick in ipairs({-1,6})do
    local store={tick_ts=0,entities={[1]={health={dead=false}}}};local entries={}
    local entity={id=2,pos=V.v(300,350),level=7,total_gold=70,tween={},spawner={pi=1,spi=1,ni=61,count=5,count_inc=1,entity="enemy_golem_head",allowed_subpaths={1,2,3},node_offset=2,pos_offset=V.v(0,0),keep_gold=true,cycle_time=6/30,owner_id=1}}
    local senv=setmetatable({km={zmod=function(a,b)return (a-1)%b+1 end},S={queue=function()end},
      E={create_entity=function(_,name)return {template_name=name,enemy={gold=10},nav_path={},pos=V.v(0,0),render={sprites={{}}},unit={}}end},
      U={animation_start_default=function()end,y_wait_conditional=function(_,seconds,condition)
        local until_tick=current+math.floor(seconds*30+0.5)
        while current<until_tick and not condition()do coroutine.yield()end
      end},simulation={queue_remove_entity=function()end,queue_insert_entity=function(_,e)
        entries[#entries+1]={current,e.template_name,e.nav_path.pi-1,e.nav_path.spi-1,e.nav_path.ni-1,e.enemy.gold}
      end}}, {__index=_G})
    local f=assert(loadstring("return function(this,store)"..spawnbody.."\nend"));setfenv(f,senv)
    local co=coroutine.create(function()f()(entity,store)end)
    for tick=0,90 do
      current=tick;store.tick_ts=tick/30;if tick==death_tick then store.entities[1].health.dead=true end
      if coroutine.status(co)=="dead"then break end
      local ok,err=coroutine.resume(co);assert(ok,err)
    end
    result.spawners[tostring(death_tick)]=entries
  end
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
