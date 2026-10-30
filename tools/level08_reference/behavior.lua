-- The functions under test are extracted from the frozen Dove checkout.
-- Only engine services (clock, queues, spatial queries, animation and sound)
-- are replaced. Every comparison keeps its complete event/frame sequence.
return function(root,result,read,V,json,bit)
  local project=assert(os.getenv('DOVE_PROJECT'))
  local f=assert(io.open(project..'/output/level08_reference_input.json','rb'))
  local input=json.decode(f:read('*a'));f:close();result.provenance=input.provenance
  local km=require('lib.klua.macros')
  local function vectors(t)
    if type(t)~='table' then return t end
    if t.x and t.y then return V.v(t.x,t.y) end
    local out={};for k,v in pairs(t)do out[k]=vectors(v)end;return out
  end
  local function template(name)return vectors(table.deepclone(assert(input.templates[name],name)))end
  local tick,store,events,bullets,hits,removed=0,nil,{},{},{},false
  local U,SU,scripts,P,E={},{},{},{},{}
  local draw=.9
  local mathenv=setmetatable({random=function(a,b)return a and math.floor((a+b)/2) or draw end},{__index=math})
  local env=setmetatable({U=U,SU=SU,scripts=scripts,P=P,E=E,V=V,v=V.v,vclone=V.vclone,math=mathenv,
    km=km,fts=function(n)return n/30 end,band=bit.band,bor=bit.bor,S={queue=function()end,stop=function()end},signal={emit=function()end},
    simulation={queue_insert_entity=function(_,e)
      if e.bullet then bullets[#bullets+1]={tick,e.template_name,e.bullet.damage_min,e.bullet.damage_max,e.bullet.damage_type,e.bullet.level or 0,e.bullet.damage_factor,e.pos.x,e.pos.y,e.bullet.to.x,e.bullet.to.y,e.bullet.fragment_count or 0,e.bullet.target_id or 0,e.bullet.flight_time or 0} end
    end,queue_remove_entity=function()removed=true end},
    queue_damage=function(_,d)hits[#hits+1]={tick,d.target_id or d.target,d.value,d.damage_type or 0}end}, {__index=_G})
  local function fn(path,name)
    local body=assert(read(path):match('function '..name:gsub('%.','%%.')..'%((.-)\nend'),name)
    local chunk=assert(loadstring('function '..name..'('..body..'\nend'));setfenv(chunk,env);chunk()
  end
  local function run(co,n)
    tick=n;store.tick_ts=n/30
    if coroutine.status(co)~='dead' then local ok,err=coroutine.resume(co);assert(ok,err)end
  end
  function E:create_entity(name)local t=template(name);t.pos=V.v(0,0);return t end
  function E.assign_damage(kind,value,source,target)return {damage_type=kind,value=value,source_id=source,target_id=target}end
  scripts.soldier_barbarian={};scripts.bomb_cluster={};scripts.missile={};scripts.bomb={}
  for _,name in ipairs({'y_wait_unconditional','y_wait_conditional','ready_to_attack','tower_ready_to_use_power','attack_order','enemy_ready_to_magic_attack'})do fn('all/utils.lua','U.'..name)end
  for _,name in ipairs({'soldier_power_upgrade','soldier_pick_melee_attack','y_soldier_do_single_area_attack','y_soldier_do_single_melee_attack','y_soldier_do_ranged_attack','attack_interrupted','delay_attack','y_enemy_wait','enemy_interrupted'})do fn('all/script_utils.lua','SU.'..name)end
  fn('kr1/game_scripts.lua','scripts.soldier_barbarian.on_power_upgrade')
  fn('kr1/game_scripts.lua','scripts.bomb_cluster.insert');fn('kr1/game_scripts.lua','scripts.bomb_cluster.update')
  fn('all/scripts.lua','scripts.missile.update');fn('all/scripts.lua','scripts.bomb.insert')
  scripts.soldier_barbarian=scripts.soldier_barbarian or {}
  U.animation_start=function(this,name,flip,ts,loop,sid)
    local s=this.render.sprites[sid or 1];s.name=name;s.ts=ts;this.flip=flip
    events[#events+1]={tick,sid or 1,name}
  end
  U.animation_start_default=function(this,name,flip,ts,loop)U.animation_start(this,name,flip,ts,loop,1)end
  env.animation_start=U.animation_start
  U.animation_finished=function(this,sid)
    local s=this.render.sprites[sid or 1];local key=s.prefix and s.prefix..'_'..s.name or s.name
    return km.round((store.tick_ts-s.ts)*30)>=#assert(input.animations[key],key).frames
  end
  U.animation_finished_default=function(this)return U.animation_finished(this,1)end
  env.y_animation_wait=function(this,sid)while not U.animation_finished(this,sid)do coroutine.yield()end end
  U.y_animation_wait_default=function(this)env.y_animation_wait(this,1)end
  U.animation_name_facing_point=function(this,name,pos)return name,pos.x<this.pos.x,1 end
  U.flags_pass=function(vis,a)return bit.band(vis.bans,a.vis_flags or 0)==0 and bit.band(vis.flags,a.vis_bans or 0)==0 end
  U.frandom=function(a,b)return (a+b)/2 end
  U.point_on_ellipse=function(p,r,a)return V.v(p.x+r*math.cos(a),p.y+.7*r*math.sin(a))end
  U.has_modifier_in_list=function()return false end;U.has_modifier_types=function()return false end
  SU.dodge_active=function()return false end;SU.unit_dodges=function()return false end
  local bfgtext=assert(read('kr1/tower_scripts.lua'):match('scripts.tower_bfg = (.-)\nscripts.lava_dwaarp ='))
  local chunk=assert(loadstring('scripts.tower_bfg = '..bfgtext));setfenv(chunk,env);chunk()
  env.tpos=function(t)return V.v(t.pos.x+t.tower.range_offset.x,t.pos.y+t.tower.range_offset.y)end
  env.ready_to_attack=U.ready_to_attack
  U.animation_start_default=function(this,name,flip,ts,loop)
    U.animation_start(this,name,flip,ts,loop,this.template_name=='tower_bfg' and 2 or 1)
  end
  result.towers={}
  for _,scenario in ipairs({'normal','skills','flying','empty','retarget'})do
    local tower=template('tower_bfg');tower.pos=V.v(500,350);tower.id=100
    local enemy={id=1,pos=V.v(580,350),nav_path={pi=1,spi=1,ni=60},health={hp=100000,dead=false},unit={hit_offset=V.v(0,13)},vis={flags=scenario=='flying' and F_FLYING or F_ENEMY,bans=0}}
    local other=table.deepclone(enemy);other.id=2;other.nav_path.ni=59
    events={};bullets={};store={tick_ts=0,tick_length=1/30,entities={[1]=enemy,[2]=other}}
    for key,p in pairs(tower.powers)do p.level=scenario=='normal' and 0 or 3;scripts.tower_bfg['on_power_upgrade_'..key](tower,key,p)end
    local function select(rule,bans)
      if scenario=='empty' or bit.band(enemy.vis.flags,bans or 0)~=0 then return nil end
      return enemy.health.dead and other or enemy
    end
    U.find_first_enemy_in_range_filter_off=function(_,_,flags,bans)return select(flags,bans)end
    U.detect_foremost_enemy_in_range_filter_off=U.find_first_enemy_in_range_filter_off
    U.calculate_enemy_ffe_pos=function(e)return V.vclone(e.pos)end
    local co=coroutine.create(function()scripts.tower_bfg.update(tower,store)end)
    for n=0,1000 do if scenario=='retarget' and n==315 then enemy.health.dead=true end;run(co,n)end
    result.towers[scenario]={animations=events,bullets=bullets}
  end
  result.powers={}
  local sequences={dual_first={'dual','twister','throwing','dual','twister','dual','twister','throwing','throwing'},twister_first={'twister','twister','twister','dual','dual','dual'},throwing={'throwing','throwing','throwing'}}
  for name,sequence in pairs(sequences)do
    local soldier=template('soldier_barbarian');soldier.idle_flip={last_animation='idle'}
    soldier.powers.dual.on_power_upgrade=scripts.soldier_barbarian.on_power_upgrade
    local rows={}
    for _,key in ipairs(sequence)do
      local p=soldier.powers[key];p.level=p.level+1;SU.soldier_power_upgrade(soldier,key)
      local a,b,r=soldier.melee.attacks[1],soldier.melee.attacks[2],soldier.ranged.attacks[1]
      rows[#rows+1]={key,p.level,a.damage_min,a.damage_max,a.damage_type,a.animation,b.damage_min,b.damage_max,b.chance,b.disabled or false,b.animation,r.max_range,r.disabled or false,r.animation,r.bullet,soldier.soldier.melee_slot_offset.x,soldier.render.sprites[1].angles.walk[1],soldier.idle_flip.last_animation}
    end
    result.powers[name]={sequence=sequence,rows=rows}
  end
  -- Cluster's deterministic midpoint service leaves node placement and physics real.
  result.clusters={}
  function P:node_pos(pi,spi,ni)local path=input.paths.paths[pi][spi];return V.vclone(path[math.max(1,math.min(#path,ni))])end
  function P:nearest_nodes(x,y)
    local best,distance=nil,math.huge
    for pi,path in ipairs(input.paths.paths)do for ni,node in ipairs(path[1])do
      local d=(node.x-x)^2+(node.y-y)^2
      if d<distance then best={pi,1,ni};distance=d end
    end end
    return {best}
  end
  SU.initial_parabola_speed=function(from,to,t,g)return V.v((to.x-from.x)/t,(to.y-from.y-.5*g*t*t)/t)end
  SU.position_in_parabola=function(t,from,speed,g)return from.x+speed.x*t,from.y+speed.y*t+.5*g*t*t end
  for _,count in ipairs({4,6,8})do
    local this=template('bomb_bfg_cluster');this.id=3;this.pos=V.v(500,350)
    local b=this.bullet;b.from=V.vclone(this.pos);b.to=V.v(580,350);b.fragment_count=count;b.damage_factor=.6
    store={tick_ts=0,tick_length=1/30,entities={}};events={};bullets={};removed=false
    scripts.bomb_cluster.insert(this,store)
    local to=V.vclone(b.to);local samples={};local co=coroutine.create(function()scripts.bomb_cluster.update(this,store)end)
    for n=0,50 do run(co,n);samples[#samples+1]={n,this.pos.x,this.pos.y,this.render.sprites[1].r,this.render.sprites[1].hidden or false};if removed then break end end
    result.clusters[tostring(count)]={to=to,samples=samples,fragments=bullets,pred_pi=this._pred_pi-1,pred_ni=this._pred_ni-1}
  end
  result.missiles={}
  for _,scenario in ipairs({'hit','retarget','banned','efficiency'})do
    local target={id=1,pos=V.v(300,350),health={hp=10000,dead=false},unit={hit_offset=V.v(0,13)},vis={flags=F_ENEMY,bans=0}}
    local other=table.deepclone(target);other.id=2;other.pos.x=340
    store={tick_ts=0,tick_length=1/30,entities={[1]=target,[2]=other}};events={};bullets={};hits={};removed=false
    local this=template('missile_bfg');this.id=3;this.pos=V.v(100,350)
    local b=this.bullet;b.from=V.vclone(this.pos);b.to=V.v(112,460);b.target_id=1;b.damage_factor=.6;b.damage_min=126;b.damage_max=154;b.speed=V.v(0,0)
    local candidates={target,other}
    U.detect_foremost_enemy_in_range_filter_off=function()return target.health.dead and other or target end
    U.detect_foremost_enemy_in_range_filter_on=function(_,_,_,_,filter)for _,e in ipairs(candidates)do if not e.health.dead and U.flags_pass(e.vis,b) and filter(e)then return e end end end
    U.find_enemies_in_range_filter_off=function()return {target,other}end
    U.dist_factor_inside_ellipse=function(pos,center,radius)
      local dx,dy=pos.x-center.x,pos.y-center.y;local angle=math.atan2(dy,dx)
      return math.min(1,math.sqrt(dx*dx+dy*dy)/(radius*math.sqrt(math.cos(angle)^2+.49*math.sin(angle)^2)))
    end
    SU.create_bullet_damage_without_pops=function(b,id)return {target_id=id,damage_type=b.damage_type}end
    env.UP={get_upgrade=function()return scenario=='efficiency' end}
    local samples={};local co=coroutine.create(function()scripts.missile.update(this,store)end)
    for n=0,250 do
      if n==15 then if scenario=='retarget' then target.health.dead=true elseif scenario=='banned' then target.vis.bans=F_RANGED end end
      run(co,n);samples[#samples+1]={n,this.pos.x,this.pos.y,this.render.sprites[1].r or 0}
      if removed then break end
    end
    if removed then scripts.missile_bfg.remove(this,store)end
    result.missiles[scenario]={samples=samples,hits=hits,children=bullets,removed=removed}
  end
  result.melee={}
  for _,name in ipairs({'soldier_barbarian','soldier_sasquash'})do
    local this=template(name);this.id=5;this.pos=V.v(500,350);this.nav_rally={new=false};this.health.dead=false;this.unit.is_stunned=false
    local index=name=='soldier_barbarian' and 2 or 1
    local a=this.melee.attacks[index];a.damage_min=40;a.damage_max=40;a.disabled=false
    local target={id=1,pos=V.v(520,350),vis={bans=0,flags=F_ENEMY},health={dead=false},unit={}}
    local other=table.deepclone(target);other.id=2
    U.find_enemies_in_range_filter_off=function()return {target,other}end
    store={tick_ts=0,tick_length=1/30,entities={[1]=target,[2]=other}};events={};hits={};draw=.5
    local co=coroutine.create(function()SU.y_soldier_do_single_area_attack(store,this,target,a)end)
    for n=0,60 do run(co,n);if coroutine.status(co)=='dead' then break end end
    result.melee[name]={hits=hits,animations=events,finished=tick}
  end
  result.chieftains={}
  local chief=assert(read('kr1/game_scripts.lua'):match('scripts.enemy_troll_chieftain = (.-)\nscripts.enemy_demon_mage ='))
  chunk=assert(loadstring('scripts.enemy_troll_chieftain = '..chief));setfenv(chunk,env);chunk()
  SU.y_enemy_stun=function()coroutine.yield()end
  SU.y_enemy_mixed_walk_melee_ranged=function(_,_,_,ready)while not ready()do coroutine.yield()end;return false end
  for _,scenario in ipairs({'normal','blocked','stunned','silenced','no_targets'})do
    local this=template('enemy_troll_chieftain');this.id=10;this.pos=V.v(500,350);this.unit.is_stunned=false;this.health.dead=false;this.enemy.can_do_magic=true
    this.timed_attacks.list[1].max_count=this.timed_attacks.list[1].max_count[2]
    store={tick_ts=0,tick_length=1/30,entities={}};events={};local targets={}
    for i=1,8 do targets[i]={id=i,template_name='enemy_troll',pos=V.v(510+i,350)}end
    local marked={};local casts={}
    U.find_enemies_in_range_filter_on=function(_,_,_,_,filter)
      if scenario=='no_targets' then return nil end
      local out={};for _,e in ipairs(targets)do if filter(e)then out[#out+1]=e end end;return #out>0 and out or nil
    end
    U.has_modifier_in_list=function(_,e)return marked[e.id] and marked[e.id]>=tick end
    U.get_blocker=function()return scenario=='blocked' and tick<200 end
    env.enemy_ready_to_magic_attack=U.enemy_ready_to_magic_attack
    env.simulation.queue_insert_entity=function(_,e)casts[#casts+1]={tick,e.template_name,e.modifier.target_id};if e.template_name=='mod_troll_rage' then marked[e.modifier.target_id]=tick+180 end end
    local co=coroutine.create(function()scripts.enemy_troll_chieftain.update(this,store)end)
    for n=0,500 do this.unit.is_stunned=scenario=='stunned' and n>=185 and n<=195;this.enemy.can_do_magic=not(scenario=='silenced' and n>=175 and n<=250);run(co,n)end
    result.chieftains[scenario]={casts=casts,animations=events}
  end
end
