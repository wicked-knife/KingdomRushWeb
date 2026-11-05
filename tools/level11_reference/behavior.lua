-- Execute the actual pinned scripts with controlled clocks, queues and random input.
return function(root,result,read,V,json,bit)
  local input=json.decode(assert(io.open(os.getenv('DOVE_PROJECT')..'/output/level11_reference_input.json','rb')):read('*a'))
  result.provenance=input.provenance
  local function vectors(t)
    if type(t)~='table' then return t end
    if t.x and t.y then return V.v(t.x,t.y) end
    local out={};for k,v in pairs(t)do out[tonumber(k) or k]=vectors(v)end;return out
  end
  local function template(name)return vectors(table.deepclone(assert(input.templates[name],name)))end
  -- Evaluate source scalar statements independently of exported values. Component
  -- defaults are tested by the shared oracle; these are the new enemy overrides.
  result.enemy_fields={}
  for _,name in ipairs({'enemy_necromancer','enemy_lava_elemental'})do
    local block=assert(read('kr1/enemies.lua'):match('tt = RT%("'..name..'", "enemy"%)(.-)\ntt ='))
    local fields={}
    local values=setmetatable({FPS=30,fts=function(n)return n/30 end,bor=bit.bor,vec_2=function(x,y)return {x=x,y=y}end},{__index=_G})
    for field,expression in block:gmatch('\ntt%.([%w_%.%[%]]+) = ([^\n]+)')do
      if (field:match('^health%.') or field:match('^enemy%.') or field:match('^motion%.') or field:match('^melee%.') or field:match('^ranged%.') or field:match('^timed_actions%.') or field=='vis.bans' or field=='unit.can_explode' or field=='unit.size' or field=='unit.hit_offset') and not expression:match('^CC') then
        local fn=assert(loadstring('return '..expression));setfenv(fn,values)
        local value=fn();assert(value~=nil,name..'.'..field);fields[field]=value
      end
    end
    result.enemy_fields[name]=fields
  end
  local tick,store,events,inserted,removed,random_index,next_id=0,nil,{},{},{},0,100
  local U,SU,scripts,P,E={},{},{enemy_necromancer={},bolt_enemy={}}, {},{}
  local rng_input=json.decode(assert(io.open(os.getenv('DOVE_PROJECT')..'/output/level11_random_input.json','rb')):read('*a'))
  local random_values={}
  local env=setmetatable({U=U,SU=SU,scripts=scripts,P=P,E=E,V=V,km=require('lib.klua.macros'),
    band=bit.band,bor=bit.bor,fts=function(n)return n/30 end,
    S={queue=function(_,id)if id then events[#events+1]={'sound',tick,id}end end},
    simulation={queue_insert_entity=function(_,e)
      inserted[#inserted+1]={tick=tick,entity=e};store.entities[e.id]=e
    end,queue_remove_entity=function(_,e)removed[#removed+1]={tick,e.template_name or ''}end},
    queue_damage=function(_,d)events[#events+1]={'damage',tick,d.damage_type,d.value}end}, {__index=_G})
  env.math=setmetatable({random=function(lo,hi)
    random_index=random_index+1;local value=assert(random_values[random_index],'random input exhausted')
    if lo then assert(value>=lo and value<=hi,'random domain')end
    return value
  end},{__index=math})
  local function fn(path,name)
    local body=assert(read(path):match('function '..name:gsub('%.','%%.')..'%((.-)\nend'),name)
    local chunk=assert(loadstring('function '..name..'('..body..'\nend'));setfenv(chunk,env);chunk()
  end
  function E:create_entity(name)
    local t=template(name);next_id=next_id+1;t.id=next_id;t.pos=V.v(0,0)
    if t.enemy then t.nav_path={} end;return t
  end
  U.animation_start_default=function(this,name,flip,ts,loop)
    local s=this.render.sprites[1];s.name=name;s.ts=ts;s.loop=loop
    events[#events+1]={'animation',tick,name}
  end
  U.animation_finished_default=function(this)
    local s=this.render.sprites[1];local a=assert(input.animations[s.prefix..'_'..s.name])
    return math.floor((store.tick_ts-s.ts)*30+0.5)>=#a.frames
  end
  U.y_animation_wait_default=function(this)while not U.animation_finished_default(this)do coroutine.yield()end end
  for _,name in ipairs({'y_wait_unconditional','y_wait_conditional','enemy_ready_to_magic_attack'})do fn('all/utils.lua','U.'..name)end
  env.enemy_ready_to_magic_attack=U.enemy_ready_to_magic_attack
  for _,name in ipairs({'enemy_interrupted','y_enemy_wait'})do fn('all/script_utils.lua','SU.'..name)end
  U.get_blocker=function()return store.blocked and {} or nil end
  U.random_table_idx=function(chances)
    local roll=env.math.random();for i,n in ipairs(chances)do if roll<=n then return i end end;return #chances
  end
  SU.insert_received_damage_factor_mul_buff=function(e,f)e.received=f end
  SU.remove_received_damage_factor_mul_buff=function(e,f)e.received=(e.received or 1)/f;events[#events+1]={'release',tick,e.id}end
  SU.y_enemy_mixed_walk_melee_ranged=function()coroutine.yield();return false end
  SU.y_enemy_stun=function()coroutine.yield()end
  SU.y_enemy_death=function()events[#events+1]={'death',tick}end
  P.is_node_valid=function(_,pi,ni)return ni>=1 and ni<=#input.paths.paths[pi][1]end
  fn('kr1/game_scripts.lua','scripts.enemy_necromancer.update')
  local function run(co,n)
    tick=n;store.tick_ts=n/30
    if coroutine.status(co)~='dead' then local ok,err=coroutine.resume(co);assert(ok,err)end
  end
  result.necromancers={}
  for _,scenario in ipairs({'normal','blocked','silenced','silenced_cast','stun_windup','stun_boundary','stun_delay','dead_cast','dead_after','invalid_node','cap'})do
    events={};inserted={};removed={};random_index=0;random_values=rng_input[scenario];next_id=100
    local enemy=template('enemy_necromancer');enemy.id=1;enemy.pos=V.v(500,350)
    enemy.nav_path={pi=1,spi=1,ni=scenario=='invalid_node' and #input.paths.paths[1][1]+1 or 41}
    enemy.health.dead=false;enemy.unit.is_stunned=false;enemy.enemy.can_do_magic=true
    enemy.render.sprites[1].name='idle'
    store={tick_ts=0,tick_length=1/30,entities={[1]=enemy}}
    local co=coroutine.create(function()scripts.enemy_necromancer.update(enemy,store)end)
    for n=0,(scenario=='cap' and 2100 or 650)do
      store.blocked=scenario=='blocked' and n<90
      enemy.enemy.can_do_magic=not (scenario=='silenced' and n<300 or scenario=='silenced_cast' and n>=245)
      enemy.unit.is_stunned=(scenario=='stun_windup' and n>=245 and n<255)or(scenario=='stun_boundary' and n==257)or(scenario=='stun_delay' and n>=259 and n<270)
      if scenario=='dead_cast' and n==259 or scenario=='dead_after' and n==300 then enemy.health.dead=true end
      run(co,n)
    end
    local births={}
    for _,r in ipairs(inserted)do local e=r.entity;births[#births+1]={r.tick,e.template_name,e.nav_path.pi-1,e.nav_path.spi-1,e.nav_path.ni-1,e.enemy.gold,e.motion.max_speed,e.received or 1}end
    result.necromancers[scenario]={births=births,events=events,random_calls=random_index}
  end
  -- Load the real local generator function and template, not a rewritten schedule.
  local raw_template
  local generator_E={register_t=function(_,name)raw_template={template_name=name};return raw_template end,
    add_comps=function(_,t)t.main_script={}end,create_entity=function(_,name)return E:create_entity(name)end}
  package.loaded.entity_db=generator_E;package.loaded.sound_db=env.S;package.loaded.utils=U
  local group_env=setmetatable({simulation=env.simulation},{__index=_G})
  local chunk=assert(loadstring(read('kr1/template_groups/level11_templates.lua')));setfenv(chunk,group_env);chunk()
  result.lava_template={entity=raw_template.entity,cooldown=raw_template.cooldown,cooldown_after=raw_template.cooldown_after,pi=raw_template.pi,sound=raw_template.sound}
  store={tick_ts=0,tick_length=1/30,wave_group_number=0,entities={}};inserted={};events={}
  raw_template.pos=V.v(498,383)
  local co=coroutine.create(function()raw_template.main_script.update(raw_template,store)end)
  for n=0,15700 do store.wave_group_number=n>=17 and 1 or 0;run(co,n)end
  result.lava_births={}
  for _,r in ipairs(inserted)do local e=r.entity;result.lava_births[#result.lava_births+1]={r.tick,e.template_name,e.nav_path.pi-1,e.nav_path.spi-1,e.nav_path.ni-1,e.pos.x,e.pos.y,e.render.sprites[1].name}end
  -- Enemy bolt's actual coroutine retains its own tracking and acceleration rules.
  U.flag_has=function(flags,mask)return bit.band(flags,mask)~=0 end
  SU.create_bullet_damage=function(b,target,source)return {damage_type=b.damage_type,value=b.damage_min,target_id=target,source_id=source}end
  fn('all/scripts.lua','scripts.bolt_enemy.insert');fn('all/scripts.lua','scripts.bolt_enemy.update')
  result.bolts={}
  for _,scenario in ipairs({'stationary','moving','dead','teleport','near'})do
    store={tick_ts=0,tick_length=1/30,entities={}};inserted={};events={};removed={}
    local target=template('soldier_militia');target.id=1;target.pos=V.v(650,350);target.health.dead=false;store.entities[1]=target
    local bolt=E:create_entity('bolt_necromancer');bolt.pos=V.v(scenario=='near' and 649 or 500,350);bolt.bullet.from=V.vclone(bolt.pos);bolt.bullet.to=V.vclone(target.pos);bolt.bullet.to.y=bolt.bullet.to.y+target.unit.hit_offset.y;bolt.bullet.target_id=1
    tick=0;scripts.bolt_enemy.insert(bolt,store)
    local co=coroutine.create(function()scripts.bolt_enemy.update(bolt,store)end);local frames={}
    for n=0,60 do
      if scenario=='moving' then target.pos.x=650+n end
      if scenario=='dead' and n>=3 then target.health.dead=true end
      if scenario=='teleport' and n>=3 then target.pos.x=1000 end
      run(co,n)
      frames[#frames+1]={n,bolt.pos.x,bolt.pos.y,bolt.bullet.to.x,bolt.bullet.to.y,coroutine.status(co)=='dead'}
      if coroutine.status(co)=='dead' then break end
    end
    result.bolts[scenario]={frames=frames,events=events}
  end
  assert(loadfile(os.getenv('DOVE_PROJECT')..'/tools/level11_reference/combat.lua'))()(root,result,read,V,json,bit)
end
