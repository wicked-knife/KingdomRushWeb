-- Execute pinned Lua functions with controlled entities and a 30 Hz clock.
return function(root,result,read,V,json,bit)
  local input=json.decode(assert(io.open(os.getenv('DOVE_PROJECT')..'/output/level12_reference_input.json','rb')):read('*a'))
  result.provenance=input.provenance
  local function vectors(t)
    if type(t)~='table' then return t end
    if t.x and t.y then return V.v(t.x,t.y) end
    local out={};for k,v in pairs(t)do out[tonumber(k) or k]=vectors(v)end;return out
  end
  local function template(name)return vectors(table.deepclone(assert(input.templates[name],name)))end
  local tick,store,events,inserted=0,nil,{},{}
  local U,SU,E,scripts={},{},{},{eb_veznan={},mod_veznan_tower={},veznan_souls_aura={}}
  local env=setmetatable({U=U,SU=SU,E=E,scripts=scripts,V=V,fts=function(n)return n/30 end,
    bor=bit.bor,band=bit.band,v=V.v,vec_2=V.v,
    S={queue=function(_,id)events[#events+1]={'sound',tick,id}end,stop_all=function()end},
    LU={list_entities=function()return {}end,kill_all_enemies=function()events[#events+1]={'clear',tick}end},
    P={node_pos=function()local p=input.paths.paths[1][1][1];return V.v(p.x,p.y)end},signal={emit=function(name)events[#events+1]={'signal',tick,name}end},
    simulation={queue_insert_entity=function(_,e)inserted[#inserted+1]={tick,e}end,queue_remove_entity=function(_,e)events[#events+1]={'remove',tick,e.template_name}end},
    queue_damage=function(_,d)events[#events+1]={'damage',tick,d.target_id};store.soldiers[d.target_id].health.dead=true end}, {__index=_G})
  -- Re-evaluate all Veznan-owned scalar/table assignments from raw Lua. Engine
  -- component defaults are supplied only for fields the source does not assign.
  scripts.enemy_basic={};env.FPS=30;env.AC=function(t)return t end
  env.RT=function()local t=template('eb_veznan');t.main_script={};return t end;env.CC=function()return {}end
  env.r=function(x,y,w,h)return {pos={x=x,y=y},size={x=w,y=h}}end
  local block=assert(read('kr1/boss.lua'):match('(tt = RT%("eb_veznan", "boss"%).-)\ntt = RT%("eb_sarelgaz"'))
  local scalar_chunk=assert(loadstring(block));setfenv(scalar_chunk,env);scalar_chunk()
  local raw=env.tt;result.boss_fields={}
  for _,field in ipairs({'health.hp_max','health.magic_armor','motion.max_speed','enemy.lives_cost','enemy.melee_slot','pos_castle','battle','demon','taunts.sets','timed_attacks.list','melee.attacks'})do
    local value=raw;for part in field:gmatch('[^.]+')do value=value[part]end;result.boss_fields[field]=value
  end
  env.math=setmetatable({random=function(a,b)return a or 0 end},{__index=math})
  local function fn(path,name)
    local body=assert(read(path):match('function '..name:gsub('%.','%%.')..'%((.-)\nend'),name)
    local chunk=assert(loadstring('function '..name..'('..body..'\nend'));setfenv(chunk,env);chunk()
  end
  function E:create_entity(name)local e=template(name);e.pos=V.v(0,0);e.nav_path={};return e end
  E.assign_damage=function(kind,value,source,target)return {target_id=target}end
  U.animation_start=function(e,name,flip,ts,loop,idx)
    local s=e.render.sprites[idx or 1];s.name=name;s.ts=ts;s.loop=loop
    if flip~=nil then s.flip_x=flip end
    events[#events+1]={'animation',tick,name}
  end
  U.animation_start_default=U.animation_start
  local function finished(e)
    local s=e.render.sprites[1];local a=assert(input.animations[s.prefix..'_'..s.name],s.prefix..'_'..s.name)
    return math.floor((store.tick_ts-(s.ts or 0))*30+0.00001)>=#a.frames
  end
  U.animation_finished_default=finished
  U.y_animation_wait_default=function(e)while not finished(e)do coroutine.yield()end end
  U.y_animation_play=function(e,name,flip,ts,loop,idx)U.animation_start(e,name,flip,ts,loop,idx);U.y_animation_wait_default(e)end
  for _,name in ipairs({'y_wait_unconditional','y_wait_conditional','enemy_ready_to_magic_attack'})do fn('all/utils.lua','U.'..name)end
  env.enemy_ready_to_magic_attack=U.enemy_ready_to_magic_attack
  U.bans_add=function(v,f)v.bans=bit.bor(v.bans,f)end
  U.bans_remove=function(v,f)v.bans=bit.band(v.bans,bit.bnot(f))end
  U.change_health_bar_offset_run_time=function()end
  U.update_max_speed=function(e,s)e.motion.max_speed=s end
  U.has_modifiers=function()return false end
  U.heal=function(e,amount)e.health.hp=math.min(e.health.hp_max,e.health.hp+amount)end
  U.find_soldiers_in_range=function(soldiers,pos,min,max,flags,bans,filter)
    local out={};for _,s in ipairs(soldiers)do if not s.health.dead and filter(s) then out[#out+1]=s end end;return out
  end
  SU.delay_attack=function(st,a,delay)a.ts=st.tick_ts+delay-a.cooldown end
  SU.y_show_taunt_set=function(st,t,set,idx)events[#events+1]={'taunt',tick,idx or t.sets[set].start_idx};U.y_wait_unconditional(st,t.duration)end
  SU.y_enemy_mixed_walk_melee_ranged=function()coroutine.yield();return false end
  SU.remove_modifiers=function()end
  SU.tower_block_inc=function(e)e.block_count=(e.block_count or 0)+1;events[#events+1]={'block',tick,e.block_count}end
  SU.tower_block_dec=function(e)e.block_count=e.block_count-1;events[#events+1]={'block',tick,e.block_count}end
  SU.ui_click_proxy_add=function()end;SU.ui_click_proxy_remove=function()end
  fn('kr1/boss_scripts.lua','scripts.eb_veznan.update')
  fn('kr1/boss_scripts.lua','scripts.mod_veznan_tower.update')
  fn('kr1/boss_scripts.lua','scripts.veznan_souls_aura.update')
  local function run(co,n)tick=n;store.tick_ts=n/30;if coroutine.status(co)~='dead' then local ok,err=coroutine.resume(co);assert(ok,err)end end
  result.boss={}
  for _,scenario in ipairs({'lifecycle','soul','soul_stun','soul_phase','elemental'})do
    events={};inserted={}
    local e=template('eb_veznan');e.id=1;e.pos=V.v(500,350);e.phase='idle';e.health.hp_max=7999;e.health.hp=4000;e.nav_path={};e.health_bar.frames={};e.enemy.can_do_magic=true
    store={tick_ts=0,lives=20,wave_group_number=0,entities={},towers={},soldiers={}}
    if scenario~='lifecycle' then
      local target=template('soldier_militia');target.id=1;target.template_name=scenario=='elemental' and 'soldier_elemental' or 'soldier_militia';target.pos=V.v(510,350);target.health.dead=false;store.soldiers={target}
    end
    local co=coroutine.create(function()scripts.eb_veznan.update(e,store)end)
    local phases={};local last=''
    for n=0,1600 do
      store.wave_group_number=n>=32 and 1 or 0
      if n==31 or n==200 or n==(scenario=='lifecycle' and 400 or 700) or n==(scenario=='lifecycle' and 700 or 1100) then e.phase_signal=true end
      e.unit.is_stunned=scenario=='soul_stun' and n>=630 and n<640
      if scenario=='soul_phase' and n==630 then e.phase_signal=true end
      run(co,n)
      if n==380 and store.soldiers[1] then store.soldiers[1].pos=V.v(e.pos.x+10,e.pos.y) end
      if e.phase~=last then phases[#phases+1]={n,e.phase};last=e.phase end
    end
    result.boss[scenario]={events=events,phases=phases}
  end
  result.blocks={}
  for _,scenario in ipairs({'click','timeout'})do
    events={};inserted={};local t=template('mod_veznan_tower');t.pos=V.v(0,0);t.modifier.target_id=1;local tower={pos=V.v(0,0)}
    store={tick_ts=0,entities={[1]=tower}};local co=coroutine.create(function()scripts.mod_veznan_tower.update(t,store)end)
    for n=0,400 do t.ui.clicked=scenario=='click' and (n==40 or n==41 or n==42);run(co,n)end
    result.blocks[scenario]=events
  end
  fn('all/script_utils.lua','SU.y_enemy_melee_attacks')
  U.animation_name_facing_point=function(e,name,point)return name,point.x<e.pos.x end
  U.is_inside_ellipse=function(p,c,r)return (p.x-c.x)^2+((p.y-c.y)/0.7)^2<=r*r end
  SU.unit_dodges=function()return false end
  result.melee={}
  for _,scenario in ipairs({'human','demon','demon_stun'})do
    events={};inserted={}
    local e=template('eb_veznan');e.pos=V.v(500,350);e.health.dead=false;e.melee.order={1,2};e.id=10;e.enemy.blockers={1}
    local demon=scenario~='human';e.melee.attacks[1].disabled=demon;e.melee.attacks[2].disabled=not demon
    if demon then e.render.sprites[1].prefix=e.demon.sprites_prefix end
    local target=template('soldier_militia');target.pos=V.v(510,350);target.id=1;target.health.dead=false
    store={tick_ts=3,soldiers={target}};tick=90
    E.assign_damage=function(kind,value,source,target)return {target_id=target,damage_type=kind,value=value}end
    env.queue_damage=function(_,d)events[#events+1]={'hit',tick,d.damage_type}end
    local co=coroutine.create(function()SU.y_enemy_melee_attacks(store,e,target)end)
    for n=90,200 do e.unit.is_stunned=scenario=='demon_stun' and n>=116 and n<125;run(co,n)end
    local hits={};for _,row in ipairs(events)do if row[1]=='hit' then hits[#hits+1]=row end end
    result.melee[scenario]=hits
  end
  fn('kr1/template_groups/level12_templates.lua','veznan_portal_update')
  local portal
  for _,entity in ipairs(input.layout.entities_list)do if entity.portal_idx==3 then portal=template(entity.template);portal.pos=vectors(entity.pos);portal.out_nodes=entity.out_nodes;portal.portal_idx=3;break end end
  events={};inserted={};store={tick_ts=0}
  local co=coroutine.create(function()env.veznan_portal_update(portal,store)end)
  for n=0,750 do if n==0 or n==400 then portal.spawn_signal=true end;run(co,n)end
  result.portal_births={}
  for _,row in ipairs(inserted)do local e=row[2];result.portal_births[#result.portal_births+1]={row[1],e.template_name,e.nav_path.pi-1,e.nav_path.ni-1}end
  result.portal_events=events
  U.frandom=function(a,b)return a end
  local aura=template('veznan_souls_aura');aura.pos=V.v(500,350)
  events={};inserted={};store={tick_ts=0}
  co=coroutine.create(function()scripts.veznan_souls_aura.update(aura,store)end)
  for n=0,180 do run(co,n)end
  result.aura_births={}
  for _,row in ipairs(inserted)do result.aura_births[#result.aura_births+1]={row[1],row[2].soul_phase}end
end
