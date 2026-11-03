-- Execute frozen source functions; replace only clock, queues, spatial services and renderer.
return function(root,result,read,V,json,bit)
  local f=assert(io.open(os.getenv('DOVE_PROJECT')..'/output/level10_reference_input.json','rb'))
  local input=json.decode(f:read('*a'));f:close();result.provenance=input.provenance
  local km=require('lib.klua.macros')
  local function vectors(t)
    if type(t)~='table' then return t end
    if t.x and t.y then return V.v(t.x,t.y) end
    local out={};for k,v in pairs(t)do out[tonumber(k) or k]=vectors(v)end;return out
  end
  local function template(name)return vectors(table.deepclone(assert(input.templates[name],name)))end
  local tick,store,events,inserted,removed=0,nil,{},{},{}
  local U,SU,scripts,P,E={},{},{},{},{}
  local env=setmetatable({U=U,SU=SU,scripts=scripts,P=P,E=E,V=V,v=V.v,vclone=V.vclone,km=km,
    band=bit.band,bor=bit.bor,fts=function(n)return n/30 end,
    S={queue=function()end,stop_all=function()end},signal={emit=function()end},
    simulation={queue_insert_entity=function(_,e)inserted[#inserted+1]={tick=tick,entity=e}end,
      queue_remove_entity=function(_,e)removed[#removed+1]={tick,e.template_name or ''}end},
    queue_damage=function(_,d)events[#events+1]={'damage',tick,d.damage_type,d.value}end}, {__index=_G})
  local function fn(path,name)
    local body=assert(read(path):match('function '..name:gsub('%.','%%.')..'%((.-)\nend'),name)
    local chunk=assert(loadstring('function '..name..'('..body..'\nend'));setfenv(chunk,env);chunk()
  end
  local function block(path,name,last)
    local body=assert(read(path):match('scripts.'..name..' = (.-)\nscripts.'..last..' ='))
    local chunk=assert(loadstring('scripts.'..name..' = '..body));setfenv(chunk,env);chunk()
  end
  function E:create_entity(name)local t=template(name);t.pos=V.v(0,0);if t.soldier then t.nav_rally={} end;if t.enemy then t.nav_path={} end;return t end
  function E:get_template(name)return template(name)end
  E.assign_damage=function(kind,value,source,target)return {damage_type=kind,value=value,source_id=source,target_id=target,hooks={},reduce_armor=0,reduce_magic_armor=0}end
  for _,name in ipairs({'y_wait_unconditional','ready_to_attack','tower_ready_to_use_power','calc_protection','predict_damage'})do fn('all/utils.lua','U.'..name)end
  U.animation_start=function(this,name,flip,ts,loop,sid)
    local s=this.render.sprites[sid or 1];s.name=name;s.ts=ts;s.loop=loop
    events[#events+1]={'animation',tick,sid or 1,name}
  end
  env.animation_start=U.animation_start
  U.animation_start_default=function(this,name,flip,ts,loop)U.animation_start(this,name,flip,ts,loop,1)end
  U.animation_finished=function(this,sid)
    local s=this.render.sprites[sid or 1];local key=s.prefix and s.prefix..'_'..s.name or s.name
    return km.round((store.tick_ts-s.ts)*30)>=#assert(input.animations[key],key).frames
  end
  env.y_animation_wait=function(this,sid)while not U.animation_finished(this,sid)do coroutine.yield()end end
  U.y_animation_wait_default=function(this)env.y_animation_wait(this,1)end
  U.y_animation_play=function(this,name,flip,ts,loops,sid)U.animation_start(this,name,flip,ts,false,sid);env.y_animation_wait(this,sid or 1)end
  U.animation_start_group=function(this,name,flip,ts,loop,group)
    for i,s in ipairs(this.render.sprites)do if s.group==group then U.animation_start(this,name,flip,ts,loop,i)end end
  end
  U.y_animation_wait_group=function(this)env.y_animation_wait(this,3)end
  U.y_animation_play_group=function(this,name,flip,ts,loops,group)U.animation_start_group(this,name,flip,ts,false,group);U.y_animation_wait_group(this)end
  env.animation_name_facing_point=function(this,name,pos)return name..(pos.y>this.pos.y and 'Up' or 'Down'),false,pos.y>this.pos.y and 1 or 2 end
  env.ready_to_attack=U.ready_to_attack
  env.get_attack_ready=function(a,s)a.ts=s.tick_ts-a.cooldown end
  env.tpos=function(t)return V.v(t.pos.x+t.tower.range_offset.x,t.pos.y+t.tower.range_offset.y)end
  U.has_modifiers=function()return false end
  SU.soldier_inherit_tower_buff_factor=function()end
  SU.create_bullet_damage=function(b,target,source)return {damage_type=b.damage_type,value=b.damage_min*(b.damage_factor or 1),hooks={},reduce_armor=b.reduce_armor or 0,reduce_magic_armor=b.reduce_magic_armor or 0}end
  local function run(co,n)tick=n;store.tick_ts=n/30;if coroutine.status(co)~='dead' then local ok,err=coroutine.resume(co);assert(ok,err)end end
  block('kr1/tower_scripts.lua','tower_tesla','mod_tesla_overcharge')
  result.towers={}
  for _,scenario in ipairs({'normal','skills','empty','blocked','retarget'}) do
    local tower=template('tower_tesla');tower.id=100;tower.pos=V.v(500,350)
    for _,p in pairs(tower.powers)do p.level=scenario=='skills' and 3 or 0 end
    local enemy=template('enemy_dark_knight');enemy.id=1;enemy.pos=V.v(550,350);enemy.health.hp=10000;enemy.health.dead=false
    local replacement=template('enemy_dark_knight');replacement.id=2;replacement.pos=V.v(570,350);replacement.health.hp=10000;replacement.health.dead=false
    U.detect_foremost_enemy_in_range_filter_off=function()if scenario~='empty' then return enemy.health.dead and replacement or enemy end end
    U.is_inside_ellipse=function()return true end
    store={tick_ts=0,tick_length=1/30,entities={enemy,replacement},soldiers={}};events={};inserted={}
    local co=coroutine.create(function()scripts.tower_tesla.update(tower,store)end)
    for n=0,600 do
      tower.tower.blocked=scenario=='blocked' and n>=50 and n<150
      if scenario=='retarget' and n==80 then enemy.health.dead=true end
      run(co,n)
    end
    local shots={}
    for _,row in ipairs(inserted)do local b=row.entity;shots[#shots+1]={row.tick,b.template_name,b.bullet and b.bullet.target_id or 0,b.bullet and b.bullet.level or b.aura.level}end
    result.towers[scenario]=shots
  end
  env.log={paranoid=function()end}
  scripts.ray_tesla={};fn('kr1/game_scripts.lua','scripts.ray_tesla.update')
  U.animation_finished_default=function(e)return U.animation_finished(e,1)end
  U.find_nearest_soldier=function()return nil end
  env.UP={get_upgrade=function()return nil end}
  scripts.mod_dps={};fn('all/scripts.lua','scripts.mod_dps.insert');fn('all/scripts.lua','scripts.mod_dps.update')
  result.dps={}
  do
    local target=template('enemy_dark_knight');target.id=1;target.health.dead=false;target.health.hp=10000
    store={tick_ts=1/30,tick_length=1/30,entities={target},soldiers={}};events={};inserted={};tick=1
    local mod=E:create_entity('mod_ray_tesla');mod.id=100;mod.modifier.target_id=1;mod.modifier.source_id=100;mod.modifier.damage_factor=1
    mod.dps.damage_min=81*0.5*13/14/7;mod.dps.damage_max=mod.dps.damage_min;mod.dps.damage_every=2/30;mod.modifier.duration=14/30
    assert(scripts.mod_dps.insert(mod,store))
    local co=coroutine.create(function()scripts.mod_dps.update(mod,store)end)
    for n=1,20 do run(co,n)end
    for _,row in ipairs(events)do if row[1]=='damage' then result.dps[#result.dps+1]={row[2],row[4]}end end
  end
  result.rays={}
  for level=0,3 do
    local enemies={}
    for i=1,8 do local e=template('enemy_dark_knight');e.id=i;e.pos=V.v(500+i*30,350);e.health.dead=false;enemies[i]=e end
    U.find_enemies_in_range_filter_on_consider_hit_offset=function(origin,r,flags,bans,filter)
      local found={};for _,e in ipairs(enemies)do if filter(e) and e.pos:dist(origin)<=r then found[#found+1]=e end end;return #found>0 and found or nil
    end
    store={tick_ts=0,tick_length=1/30,entities=enemies,soldiers={}};events={};inserted={}
    env.math=setmetatable({random=function(a,b)return math.floor((a+b)/2)end},{__index=math})
    local ray=E:create_entity('ray_tesla');ray.bounce_damage_min=81;ray.bounce_damage_max=81
    ray.bullet.target_id=1;ray.bullet.source_id=100;ray.bullet.level=level;ray.bullet.damage_factor=1;ray.bullet.to=V.vclone(enemies[1].pos);ray.pos=V.v(500,350)
    local jobs={{co=coroutine.create(function()scripts.ray_tesla.update(ray,store)end),at=0}}
    local index=1;local trace={}
    for n=0,40 do
      for _,job in ipairs(jobs)do if n>=job.at then run(job.co,n)end end
      while index<=#inserted do
        local row=inserted[index];index=index+1;local e=row.entity
        if e.template_name=='mod_ray_tesla' then trace[#trace+1]={row.tick,e.modifier.target_id,e.dps.damage_min}
        elseif e.template_name=='ray_tesla' then e.bounce_damage_min=81;e.bounce_damage_max=81;jobs[#jobs+1]={co=coroutine.create(function()scripts.ray_tesla.update(e,store)end),at=n+1}end
      end
    end
    result.rays[tostring(level)]=trace
  end
  result.ray_visuals={}
  for _,scenario in ipairs({'moving','diagonal','teleport_source','teleport_target'})do
    local enemies={}
    for i=1,3 do local e=template('enemy_dark_knight');e.id=i;e.pos=V.v(530+(i-1)*40,350+(i-1)*20);e.health.dead=false;enemies[i]=e end
    U.find_enemies_in_range_filter_on_consider_hit_offset=function(origin,r,flags,bans,filter)
      local found={};for _,e in ipairs(enemies)do if filter(e) and e.pos:dist(origin)<=r then found[#found+1]=e end end;return #found>0 and found or nil
    end
    store={tick_ts=0,tick_length=1/30,entities=enemies,soldiers={}};events={};inserted={};removed={}
    local ray=E:create_entity('ray_tesla');ray.id=100;ray.bullet.target_id=1;ray.bullet.source_id=99;ray.bullet.level=0;ray.bullet.damage_factor=1;ray.bullet.to=V.vclone(enemies[1].pos);ray.pos=V.v(500,400)
    local jobs={{e=ray,co=coroutine.create(function()scripts.ray_tesla.update(ray,store)end),at=0}}
    local index=1;local trace={}
    for n=0,22 do
      for i,e in ipairs(enemies)do
        if scenario=='moving' then e.pos.x=530+(i-1)*40+n*2;e.pos.y=350+(i-1)*20+n end
        if scenario=='teleport_source' and i==1 and n>=5 then e.pos.x=1000 end
        if scenario=='teleport_target' and i==2 and n>=5 then e.pos.y=700 end
      end
      for _,job in ipairs(jobs)do if n>=job.at then run(job.co,n)end end
      while index<=#inserted do
        local row=inserted[index];index=index+1;local e=row.entity
        if e.template_name=='ray_tesla' then e.id=100+#jobs;jobs[#jobs+1]={e=e,co=coroutine.create(function()scripts.ray_tesla.update(e,store)end),at=n+1}end
      end
      for j,job in ipairs(jobs)do
        if n>=job.at and coroutine.status(job.co)~='dead' then
          local e=job.e;local s=e.render.sprites[1]
          trace[#trace+1]={n,j,e.pos.x,e.pos.y,e.bullet.to.x,e.bullet.to.y,s.r,s.scale.x,s.scale.y,s.hidden or false,km.round((n/30-s.ts)*30)}
        end
      end
    end
    result.ray_visuals[scenario]=trace
  end
end
