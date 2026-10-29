return function(root, result, read, V, json, bit)
  local project=assert(os.getenv('DOVE_PROJECT'))
  local f=assert(io.open(project..'/output/level07_reference_input.json','rb'))
  local input=json.decode(f:read('*a')); f:close()
  result.provenance=input.provenance
  local source=read('all/scripts.lua')
  local function extract(text,start,stop)
    return assert(text:match(start..'(.-)'..stop)):gsub('\nend%s*$','')
  end
  local function compile(body,args,env)
    local fn=assert(loadstring('return function('..args..')'..body..'\nend'))
    setfenv(fn,setmetatable(env,{__index=_G}));return fn()
  end
  local function run(co,store,tick)
    store.tick_ts=tick/30
    if coroutine.status(co)~='dead' then local ok,err=coroutine.resume(co);assert(ok,err)end
  end
  local function wait(store,seconds)
    local until_tick=math.floor(store.tick_ts*30+0.5)+math.floor(seconds*30+0.5)
    while math.floor(store.tick_ts*30+0.5)<until_tick do coroutine.yield()end
  end
  local tick=0
  local towertext=read('kr1/tower_scripts.lua')
  local body=assert(towertext:match('scripts.tower_musketeer = {%s*update = function%(this, store%)(.-)\n}\n%-%-')):gsub('\n\tend%s*$','')
  result.towers={}
  for _,scenario in ipairs({'normal','skills','instakill','immune','boss','retarget','far'})do
    local tower=table.deepclone(input.templates.tower_musketeer)
    tower.id=100;tower.pos=V.v(500,350)
    local enemy={id=1,pos=V.v(scenario=='far' and 620 or 580,350),health={hp=100000,hp_max=100000,dead=false},unit={hit_offset=V.v(0,13)},vis={flags=scenario=='boss' and F_BOSS or F_ENEMY,bans=scenario=='immune' and F_INSTAKILL or 0}}
    local replacement=table.deepclone(enemy);replacement.id=2
    for _,p in pairs(tower.powers)do p.level=scenario=='normal' and 0 or 3;p.changed=true end
    local store={tick_ts=0,tick_length=1/30,entities={[1]=enemy,[2]=replacement}}
    local events={};local bullets={};local removed={}
    local function animation_start(this,name,flip,ts,loop,sid)
      this.render.sprites[sid].name=name;this.render.sprites[sid].ts=ts
      events[#events+1]={tick,sid,name,flip or false}
    end
    local U={y_wait_unconditional=wait,animation_name_facing_point_use_offset=function(this,action,pos,sid,offset)
      local direction=pos.y>this.pos.y+offset.y and 1 or 2
      return this.render.sprites[sid].angles[action][direction],pos.x<this.pos.x+offset.x,direction
    end, animation_name_facing_point_simple=function(this,action,pos,sid)return this.render.sprites[sid].angles[action][1],false end,
    change_sprite_draw_order=function()end,find_biggest_enemy_in_range_filter_off=function()return enemy end,
    refind_foremost_enemy=function()return replacement end,
    find_foremost_enemy_with_max_coverage_in_range_filter_off=function()return enemy end,
    detect_foremost_enemy_with_flying_preference_in_range_filter_off=function()return enemy end,
    frandom=function(a,b)return (a+b)/2 end,point_on_ellipse=function(p,r,a)return V.v(p.x+r*math.cos(a),p.y+0.7*r*math.sin(a))end}
    local function ready(a,s,factor)return s.tick_ts-a.ts>a.cooldown*(factor or 1)+1e-9 end
    U.tower_ready_to_use_power=function(p,a,s,tw)return p.level>0 and ready(a,s,tw.cooldown_factor)end
    local env={V=V,v=V.v,vclone=V.vclone,band=bit.band,fts=function(n)return n/30 end,U=U,
      km={zmod=function(n,m)return (n-1)%m+1 end,clamp=function(a,b,x)return math.max(a,math.min(b,x))end},
      random=function()return scenario=='instakill' or scenario=='immune' or scenario=='boss' and 0 or 0.99 end,
      ready_to_attack=ready,tpos=function(t)return V.v(t.pos.x+t.tower.range_offset.x,t.pos.y+t.tower.range_offset.y)end,
      animation_start=animation_start,apply_precision=function()end,
      y_animation_wait=function(this,sid)
        local s=this.render.sprites[sid];local a=input.animations[s.prefix..'_'..s.name]
        wait(store,math.max(0,#a.frames/30-(store.tick_ts-s.ts)))
      end,
      P={predict_enemy_pos=function(_,e)return V.vclone(e.pos)end},
      SU={insert_sprite=function()return {render={sprites={{}}}}end},
      E={create_entity=function(_,name)local t=table.deepclone(assert(input.templates[name],name));t.template=name; t.pos=V.v(0,0);return t end},
      simulation={queue_insert_entity=function(_,e)
        if e.bullet then bullets[#bullets+1]={tick,e.template,e.bullet.damage_min,e.bullet.damage_max,e.bullet.damage_type,e.bullet.level,e.bullet.damage_factor,e.pos.x,e.pos.y,e.bullet.to.x,e.bullet.to.y}end
      end,queue_remove_entity=function(_,e)removed[#removed+1]=tick end}}
    env.random=function() if scenario=='instakill' or scenario=='immune' or scenario=='boss' then return 0 end;return 0.99 end
    local fn=compile(body,'this,store',env)
    local co=coroutine.create(function()fn(tower,store)end)
    for n=0,1000 do tick=n;if scenario=='retarget' and n==430 then enemy.health.dead=true end;run(co,store,n)end
    result.towers[scenario]={animations=events,bullets=bullets,removed=removed}
  end
  result.shotguns={}
  local shotbody=extract(source,'function scripts.shotgun.update%(this, store%)','\nscripts.ray_simple =')
  for _,scenario in ipairs({'hit','move','dead','banned'})do
    local target={id=1,pos=V.v(300,350),unit={hit_offset=V.v(0,13),blood_color='red'},vis={flags=F_ENEMY,bans=0},health={hp=1000,dead=false}}
    local store={entities={[1]=target},tick_length=1/30,tick_ts=0}
    local this=table.deepclone(input.templates.shotgun_musketeer);this.id=3;this.pos=V.v(100,363)
    -- shotgun.insert initializes visibility before its update coroutine starts.
    this.render.sprites[1].hidden=this.bullet.hide_radius~=nil
    this.bullet.from=V.vclone(this.pos);this.bullet.to=V.v(300,363);this.bullet.target_id=1;this.bullet.speed=V.v(0,0)
    local samples={};local hits={};local done=false
    local env={V=V,band=bit.band,UP={get_upgrade=function()end},
      SU={create_bullet_damage=function(b,id)return {value=b.damage_min,target=id}end},
      queue_damage=function(_,d)hits[#hits+1]={tick,d.target,d.value}end,
      E={create_entity=function()return {pos=V.v(0,0),render={sprites={{}}}}end},
      simulation={queue_insert_entity=function()end,queue_remove_entity=function()done=true end}}
    local fn=compile(shotbody,'this,store',env);local co=coroutine.create(function()fn(this,store)end)
    for n=0,20 do tick=n;if n==3 then if scenario=='move' then target.pos.x=600 elseif scenario=='dead' then target.health.dead=true elseif scenario=='banned' then target.vis.bans=F_RANGED end end
      run(co,store,n);samples[#samples+1]={n,this.pos.x,this.pos.y,this.render.sprites[1].hidden or false};if done then break end
    end
    result.shotguns[scenario]={samples=samples,hits=hits}
  end
  result.regen={}
  result.bombs={}
  -- Extract up to the next actual script table, independent of its name.
  local bombbody=assert(source:match('function scripts.bomb.update%(this, store%)(.-)\nend\n'))
  for _,frames in ipairs({4,5.4,6,8})do
    local this=table.deepclone(input.templates.bomb_musketeer);this.id=3;this.pos=V.v(500,350)
    local b=this.bullet;b.level=3;b.damage_factor=0.6;b.from=V.v(500,350);b.to=V.v(540,350);b.flight_time=frames/30;b.ts=0
    b.speed=V.v((b.to.x-b.from.x)/b.flight_time,(b.to.y-b.from.y-0.5*b.g*b.flight_time^2)/b.flight_time)
    this.render.sprites[1].r=0
    local enemy={id=1,pos=V.v(540,350),vis={flags=F_ENEMY,bans=0}}
    local store={tick_ts=0,tick_length=1/30};local samples={};local hits={};local done=false
    local env={V=V,band=bit.band,UP={get_upgrade=function()end},U={find_enemies_in_range_filter_off=function()return {enemy}end,dist_factor_inside_ellipse=function(p,c,r)return V.dist(p.x,p.y,c.x,c.y)/r end},
      SU={create_bullet_damage_without_pops_and_value=function()return {}end,create_bullet_pop=function()end},queue_damage=function(_,d)hits[#hits+1]={tick,d.value}end,
      GR={cell_type=function()return 1 end},S={queue=function()end},E={create_entity=function()return {pos=V.v(0,0),render={sprites={{}}}}end},
      simulation={queue_insert_entity=function()end,queue_remove_entity=function()done=true end}}
    local fn=compile(bombbody,'this,store',env);local co=coroutine.create(function()fn(this,store)end)
    for n=0,12 do tick=n;run(co,store,n);samples[#samples+1]={n,this.pos.x,this.pos.y};if done then break end end
    result.bombs[tostring(frames)]={samples=samples,hits=hits}
  end
  local regenbody=extract(source,'function scripts.aura_unit_regen.update%(this, store%)','\nscripts.aura_hero_regen =')
  local target={health={hp=200,hp_max=280,dead=false},enemy={can_do_magic=true},unit={is_stunned=false},vis={bans=0}}
  local store={entities={[1]=target},tick_ts=0}
  local aura={aura={source_id=1,ts=0},regen=table.deepclone(input.templates.aura_troll_regen.regen)}
  local fn=compile(regenbody,'this,store',{U={flag_has=function(a,b)return bit.band(a,b)~=0 end,heal=function(t,h)t.health.hp=math.min(t.health.hp_max,t.health.hp+h)end},simulation={queue_remove_entity=function()end}})
  local co=coroutine.create(function()fn(aura,store)end)
  for n=0,35 do tick=n;target.enemy.can_do_magic=not(n>=7 and n<=12);target.unit.is_stunned=n>=18 and n<=21;target.vis.bans=n>=22 and n<=27 and F_MOD or 0;target.health.dead=n==35
    run(co,store,n);result.regen[#result.regen+1]={n,target.health.hp,aura.aura.ts*30}
  end
  result.tunnels={}
  local tunnelbody=extract(source,'function scripts.tunnel.update%(this, store%)','\nscripts.tunnel_KR6 =')
  for _,speed in ipairs({27,13.5})do
    local enemy={id=1,health={dead=false},pos=V.v(0,0),nav_path={pi=2,spi=3,ni=80},main_script={co=true},motion={real_speed=speed},ui={can_click=true}}
    local store={enemies={[1]=enemy},entities={[1]=enemy},tick_ts=0};local events={}
    local tu={pick_pi=2,place_pi=4,speed_factor=2,picked_enemies={}}
    local function node(pi,spi,ni)return input.paths.paths[pi][spi][ni]end
    local env={V=V,P={get_end_node=function(_,pi)return #input.paths.paths[pi][1]end,node_pos_ref=function(_,pi,spi,ni)return node(pi,spi,ni)end,node_pos=function(_,pi,spi,ni)return node(pi,spi,ni)end},
      SU={remove_modifiers=function()events[#events+1]={tick,'mods'}end,remove_auras=function()events[#events+1]={tick,'auras'}end},
      U={unblock_all=function()events[#events+1]={tick,'unblock'}end},log={debug=function()end},
      simulation={queue_remove_entity=function()store.enemies={};store.entities={}end,queue_insert_entity=function(_,e)store.enemies={[1]=e};store.entities={[1]=e};events[#events+1]={tick,'exit',e.nav_path.pi-1,e.nav_path.spi-1,e.nav_path.ni-1}end}}
    local fn=compile(tunnelbody,'this,store',env);local co=coroutine.create(function()fn({id=2,tunnel=tu},store)end)
    for n=0,1000 do tick=n;run(co,store,n);if #events>3 then break end end
    result.tunnels[tostring(speed)]={events=events,length=tu.length}
  end
end
