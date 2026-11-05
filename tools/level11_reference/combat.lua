-- The functions under test are extracted from the frozen Dove checkout.
-- Only engine services (clock, queues, spatial queries, animation and sound)
-- are replaced. Every comparison keeps its complete event/frame sequence.
return function(root,result,read,V,json,bit)
  local project=assert(os.getenv('DOVE_PROJECT'))
  local f=assert(io.open(project..'/output/level11_reference_input.json','rb'))
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
  for _,name in ipairs({'y_wait_unconditional','y_wait_conditional','ready_to_attack','tower_ready_to_use_power','attack_order','enemy_ready_to_magic_attack','is_inside_ellipse'})do fn('all/utils.lua','U.'..name)end
  for _,name in ipairs({'soldier_power_upgrade','soldier_pick_melee_attack','y_soldier_do_single_area_attack','y_soldier_do_single_melee_attack','y_soldier_do_ranged_attack','y_soldier_ranged_attacks','attack_interrupted','delay_attack','y_enemy_wait','enemy_interrupted','y_enemy_melee_attacks','y_enemy_do_ranged_attack','y_enemy_range_attacks'})do fn('all/script_utils.lua','SU.'..name)end
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
  result.enemy_melee={}
  for _,name in ipairs({'enemy_lava_elemental','enemy_necromancer'})do
    local scenarios=name=='enemy_lava_elemental' and {'normal','flipped','capped','visibility','primary_dead','dodged','stun_before','stun_endpoint','stun_after'} or {'normal','unblocked','stun_before'}
    for _,scenario in ipairs(scenarios)do
      local this=template(name);this.id=100;this.pos=V.v(500,350);this.unit.is_stunned=false;this.health.dead=false;this.enemy.blockers={1}
      local a=this.melee.attacks[1];a.damage_min=40;a.damage_max=40
      local point=V.v(500+(scenario=='flipped' and -30 or 30),350)
      local soldiers={}
      for i=1,(scenario=='capped' and 12 or 4)do
        local pos=scenario=='capped' and V.v(point.x+13-i,350) or V.v(point.x+({0,10,40,0})[i],i==4 and 390 or 350)
        soldiers[i]={id=i,pos=pos,vis={flags=0,bans=0},health={dead=false},unit={}}
      end
      if scenario=='visibility' then soldiers[2].vis.flags=128;soldiers[3].vis.bans=2 end
      if scenario=='dodged' then soldiers[1].dodge={chance=1}end
      SU.unit_dodges=function()return scenario=='dodged'end
      local entities={};for _,s in ipairs(soldiers)do entities[s.id]=s end
      store={tick_ts=100/30,tick_length=1/30,entities=entities,soldiers=soldiers};events={};hits={};local effects={}
      env.simulation.queue_insert_entity=function(_,e)effects[#effects+1]={tick,e.template_name,e.pos.x,e.pos.y}end
      local co=coroutine.create(function()SU.y_enemy_melee_attacks(store,this,soldiers[1])end)
      local hit_tick=100;while hit_tick/30-100/30<a.hit_time do hit_tick=hit_tick+1 end
      for n=100,170 do
        this.unit.is_stunned=(scenario=='stun_before' and n>=103) or (scenario=='stun_endpoint' and n>=hit_tick) or (scenario=='stun_after' and n>=hit_tick+1)
        if n>=103 and scenario=='primary_dead' then soldiers[1].health.dead=true;this.enemy.blockers={}end
        if n>=103 and scenario=='unblocked' then this.enemy.blockers={}end
        run(co,n);if coroutine.status(co)=='dead' then break end
      end
      result.enemy_melee[name..':'..scenario]={hits=hits,effects=effects,animations=events,finished=tick,cooldown=a.ts*30}
    end
  end
  SU.unit_dodges=function()return false end
  result.enemy_ranged={}
  for _,scenario in ipairs({'normal','escaped','dead_target','stun_before','stun_endpoint','stun_after'})do
    local this=template('enemy_necromancer');this.id=100;this.pos=V.v(500,350);this.unit.is_stunned=false;this.health.dead=false
    local a=this.ranged.attacks[1]
    local target={id=1,pos=V.v(560,350),health={dead=false},vis={flags=0,bans=0},unit={hit_offset=V.v(0,13)}}
    store={tick_ts=100/30,tick_length=1/30,entities={[1]=target}};events={};bullets={}
    env.simulation.queue_insert_entity=function(_,e)local b=e.bullet;bullets[#bullets+1]={tick,e.template_name,b.damage_min,b.damage_max,b.damage_type,b.level or 0,b.damage_factor,e.pos.x,e.pos.y,b.to.x,b.to.y,0,b.target_id,b.flight_time or 0}end
    local co=coroutine.create(function()SU.y_enemy_range_attacks(store,this,target)end)
    for n=100,150 do
      this.unit.is_stunned=(scenario=='stun_before' and n>=103) or (scenario=='stun_endpoint' and n>=109) or (scenario=='stun_after' and n>=110)
      if scenario=='escaped' and n>=103 then target.pos.x=800 end
      if scenario=='dead_target' and n>=103 then target.health.dead=true end
      run(co,n);if coroutine.status(co)=='dead' then break end
    end
    result.enemy_ranged[scenario]={bullets=bullets,finished=tick,cooldown=a.ts*30}
  end
end
