-- Execute frozen source functions; replace only clock, queues, spatial services and renderer.
return function(root,result,read,V,json,bit)
  local f=assert(io.open(os.getenv('DOVE_PROJECT')..'/output/level09_reference_input.json','rb'))
  local input=json.decode(f:read('*a'));f:close();result.provenance=input.provenance
  local km=require('lib.klua.macros')
  local function vectors(t)
    if type(t)~='table' then return t end
    if t.x and t.y then return V.v(t.x,t.y) end
    local out={};for k,v in pairs(t)do out[k]=vectors(v)end;return out
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
  block('kr1/tower_scripts.lua','tower_sorcerer','twister')
  block('kr1/tower_scripts.lua','tower_sunray','tower_pixie')
  result.towers={}
  for _,kind in ipairs({'sorcerer','sunray'})do
    for _,scenario in ipairs(kind=='sunray' and {'normal','skills','empty','lethal','border','boss'} or {'normal','skills','empty'})do
      local tower=template('tower_'..kind);tower.id=100;tower.pos=V.v(500,350)
      for k,p in pairs(tower.powers)do p.level=((scenario=='skills' or scenario=='lethal' or scenario=='border' or scenario=='boss') and p.max_level or (k=='ray' and 1 or 0));p.changed=true end
      local enemies={}
      for i=1,3 do
        local e=template('enemy_slayer');e.id=i;e.pos=V.v(560+i*10,350);e.health.hp=100000;e.health.hp_max=100000;enemies[i]=e
        if scenario=='lethal' or scenario=='boss' then e.health.hp=10 end
        if scenario=='border' then e.health.hp=320;e.health.magic_armor=0 end
        if scenario=='boss' then e.vis.flags=bit.bor(e.vis.flags,F_BOSS) end
      end
      U.find_foremost_enemy_in_range_filter_off=function()if scenario~='empty' then return enemies[1],enemies end end
      U.find_foremost_enemy_with_max_coverage_in_range_filter_off=function()if scenario~='empty' then return enemies[3] end end
      U.find_enemies_in_range_filter_off=function()if scenario~='empty' then return enemies end end
      store={tick_ts=0,tick_length=1/30,entities=enemies,player_gold=0};events={};inserted={}
      local co=coroutine.create(function()scripts['tower_'..kind].update(tower,store)end)
      for n=0,1000 do run(co,n)end
      local shots={}
      for _,row in ipairs(inserted)do local b=row.entity;if b.bullet then shots[#shots+1]={row.tick,b.template_name,b.bullet.target_id,b.bullet.damage_factor,b.bullet.damage_min,b.bullet.damage_max}end end
      result.towers[kind..'_'..scenario]={shots=shots,animations=events,gold=store.player_gold}
    end
  end
  scripts.eb_jt={};scripts.mod_jt_tower={};scripts.jt_spawner_aura={}
  fn('all/utils.lua','U.enemy_ready_to_magic_attack');env.enemy_ready_to_magic_attack=U.enemy_ready_to_magic_attack
  for _,name in ipairs({'on_damage','heal','update'})do fn('kr1/boss_scripts.lua','scripts.eb_jt.'..name)end
  fn('kr1/boss_scripts.lua','scripts.mod_jt_tower.update');fn('kr1/boss_scripts.lua','scripts.jt_spawner_aura.update')
  SU.remove_modifiers=function()end;SU.stun_inc=function(t)t.unit.is_stunned=true end
  U.bans_add=function(vis,flags)vis.bans=bit.bor(vis.bans,flags)end
  SU.insert_sprite=function(_,name,pos)local e=E:create_entity(name);e.pos=V.vclone(pos);env.simulation:queue_insert_entity(e);return e end
  SU.tower_block_inc=function(t)t.blocks=(t.blocks or 0)+1 end
  SU.tower_block_dec=function(t)t.blocks=t.blocks-1 end
  SU.ui_click_proxy_add=function()end;SU.ui_click_proxy_remove=function()end
  result.freezes={}
  SU.hide_modifiers=function()end;SU.show_modifiers=function()end
  SU.y_enemy_walk_until_blocked=function()coroutine.yield();return false end
  SU.y_enemy_wait=function(s,this,duration)local until_ts=s.tick_ts+duration;while s.tick_ts<until_ts do if this.dying then return true end;coroutine.yield()end;return false end
  local candidates={}
  for i=1,5 do local t=template('tower_mage_1');t.id=100+i;t.pos=V.v(500+i*10,350);candidates[i]=t end
  U.find_towers_in_range=function()return candidates end
  local active=template('eb_jt');active.id=5;active.pos=V.v(500,350);active.health.hp=12000
  store={tick_ts=0,tick_length=1/30,entities={[5]=active}};inserted={};events={}
  local active_co=coroutine.create(function()scripts.eb_jt.update(active,store)end)
  for n=0,420 do run(active_co,n)end
  result.jt_cast={}
  for _,row in ipairs(inserted)do if row.entity.template_name=='mod_jt_tower' then result.jt_cast[#result.jt_cast+1]={row.tick,row.entity.modifier.target_id}end end
  local tower=template('tower_mage_1');tower.pos=V.v(500,350);tower.id=100;tower.blocks=0
  local ice=template('mod_jt_tower');ice.pos=V.v(0,0);ice.modifier.target_id=100
  store={tick_ts=0,tick_length=1/30,entities={[100]=tower}};events={};removed={}
  local co=coroutine.create(function()scripts.mod_jt_tower.update(ice,store)end)
  for n=0,180 do
    if n==35 or n==38 or n==41 then ice.ui.clicked=true end
    run(co,n)
    result.freezes[#result.freezes+1]={n,tower.blocks,not ice.render.sprites[2].hidden,ice.render.sprites[1].name,ice.tween.ts and km.round(ice.tween.ts*30) or -1,#removed>0}
  end
  result.jt_death={}
  local jt=template('eb_jt');jt.id=5;jt.pos=V.v(500,350);jt.health.hp=12000
  store={tick_ts=0,tick_length=1/30,entities={[5]=jt}};events={};removed={};inserted={}
  scripts.eb_jt.on_damage(jt,store,E.assign_damage(DAMAGE_TRUE,12000,0,5))
  env.LU={kill_all_enemies=function()events[#events+1]={'cleanup',tick}end}
  co=coroutine.create(function()scripts.eb_jt.update(jt,store)end)
  for n=0,400 do if n==250 then jt.ui.clicked=true end;run(co,n);result.jt_death[#result.jt_death+1]={n,jt.health.hp,jt.render.sprites[1].name,jt.health.ignore_damage,coroutine.status(co)=='dead'}end
  result.jt_death_events=events
  result.jt_spawns={};jt.dying=false
  local aura=template('jt_spawner_aura');aura.aura.source_id=5
  store={tick_ts=0,tick_length=1/30,entities={[5]=jt}};inserted={};P.get_start_node=function()return 1 end
  co=coroutine.create(function()scripts.jt_spawner_aura.update(aura,store)end)
  for n=0,1200 do if n==1000 then jt.dying=true end;run(co,n)end
  for _,row in ipairs(inserted)do local e=row.entity;result.jt_spawns[#result.jt_spawns+1]={row.tick,e.template_name,e.nav_path.pi-1,e.nav_path.spi-1}end
  scripts.mod_polymorph={};fn('all/scripts.lua','scripts.mod_polymorph.insert')
  U.flag_has=function(flags,flag)return bit.band(flags,flag)~=0 end
  U.update_max_speed=function(e,speed)e.motion.max_speed=speed end
  result.polymorph={}
  for _,name in ipairs({'enemy_slayer','enemy_rocketeer'})do
    local old=template(name);old.id=1;old.pos=V.v(550,350);old.nav_path={pi=1,spi=1,ni=60};old.health.hp=1000;old.enemy.gold=31
    local m=template('mod_polymorph_sorcerer');m.modifier.target_id=1;m.modifier.source_id=100
    store={tick_ts=0,entities={[1]=old}};inserted={};events={};tick=0
    scripts.mod_polymorph.insert(m,store)
    local e=inserted[#inserted].entity
    result.polymorph[name]={e.template_name,e.health.hp,e.enemy.gold,e.enemy.lives_cost,e.motion.max_speed}
  end
end
