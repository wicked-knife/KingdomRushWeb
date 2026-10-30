-- Execute Dove functions/coroutines. Only clock, rendering/audio and entity
-- queues are services; stat, XP, cooldown, attack and propagation code is real.
return function(root,E,GS,read)
  local V=require("lib.klua.vector");local bit=require("bit");local km=require("lib.klua.macros")
  local SU,U,scripts,P,GR={},{},{},{},{}
  local rows,fx,removed={},{},{}
  local store={entities={},tick_ts=0,tick_length=1/30,hero_xp_multiplier=.225}
  local draw=.9
  local mathenv=setmetatable({random=function(a,b)return a and math.floor((a+b)/2) or draw end},{__index=math})
  local sound={queue=function()end,stop=function()end}
  local env=setmetatable({SU=SU,U=U,scripts=scripts,E=E,GS=GS,P=P,path_db=P,GR=GR,grid_db=GR,V=V,FPS=30,km=km,math=mathenv,
    band=bit.band,bor=bit.bor,atan2=math.atan2,cos=math.cos,sin=math.sin,S=sound,signal={emit=function()end},
    log={paranoid=function()end,error=function()end},
    simulation={queue_insert_entity=function(_,e)fx[#fx+1]={tick=km.round(store.tick_ts*30),name=e.template_name,x=e.pos.x,y=e.pos.y}end,
      queue_remove_entity=function(_,e)removed[#removed+1]={tick=km.round(store.tick_ts*30),name=e.template_name}end},
    queue_damage=function(_,d)rows[#rows+1]={tick=km.round(store.tick_ts*30),value=d.value,kind=d.damage_type,xp=d.xp_gain_factor or 0}end}, {__index=_G})
  function E:create_entity(name)
    local t=table.deepclone(self:get_template(name));t.pos=V.v(0,0);return t
  end
  function E.assign_damage(kind,value,source,target)return {damage_type=kind,value=value,source_id=source,target_id=target}end
  local function fn(path,name)
    local body=assert(read(path):match("function "..name:gsub("%.","%%.").."%((.-)\nend"),name)
    local chunk=assert(loadstring("function "..name.."("..body.."\nend"));setfenv(chunk,env);chunk()
  end
  for _,name in ipairs({"update_armor","hero_gain_xp_from_skill","hero_level_up","soldier_pick_melee_attack","attack_interrupted","y_soldier_do_single_area_attack","y_soldier_do_single_melee_attack","y_hero_death_and_respawn","soldier_regen","y_hero_walk_waypoints"})do fn("all/script_utils.lua","SU."..name)end
  for _,name in ipairs({"attack_order","heal","y_wait_unconditional","walk","set_destination"})do fn("all/utils.lua","U."..name)end
  U.hnum_on_applied_impl=function()end
  U.unblock_target=function()end
  U.animation_name_facing_point=function(_,name)return name,false end
  U.animation_start_default=function(h,name,_,ts)h.animation=name;h.animation_ts=ts end
  local file=assert(io.open(assert(os.getenv("DOVE_HERO_ANIMATIONS")),"rb"))
  local animations=require("lib.json").decode(file:read("*a"));file:close()
  local lengths={}
  for key,animation in pairs(animations)do lengths[key:sub(#"hero_malik_"+1)]=#animation.frames end
  U.animation_finished_default=function(h)return km.round((store.tick_ts-h.animation_ts)*30) >= (lengths[h.animation] or 1) end
  U.y_animation_play=function(h,name,_,ts)
    U.animation_start_default(h,name,nil,ts)
    while not U.animation_finished_default(h)do coroutine.yield()end
  end
  SU.dodge_active=function()return false end;SU.unit_dodges=function()return false end
  U.flags_pass=function(vis,rule)return bit.band(vis.bans,rule.vis_flags or 0)==0 and bit.band(vis.flags,rule.vis_bans or 0)==0 end
  U.find_enemies_in_range_filter_off=function()return store.targets or {}end
  package.loaded.utils=U;package.loaded.script_utils=SU;package.loaded.grid_db=GR
  package.loaded.path_db=P;package.loaded.sound_db=sound;package.loaded["kr1.game_settings"]=GS
  local HU=assert(loadstring(read("kr1/hero_utils.lua")))()
  env.level_up_basic=HU.level_up_basic;env.upgrade_skill=HU.upgrade_skill;env.update_hp=HU.update_hp
  local hero_source=read("kr1/hero_scripts.lua")
  local start=assert(hero_source:find("scripts.aura_malik_fissure = {",1,true))
  local finish=assert(hero_source:find("scripts.mod_priest_armor = {",start,true))
  local chunk=assert(loadstring(hero_source:sub(start,finish-1)));setfenv(chunk,env);chunk()
  local function hero(level)
    local h=E:create_entity("hero_malik");h.id=1;h.health.hp=nil
    h.nav_rally={pos=V.v(0,0),center=V.v(0,0),new=false};h.nav_grid.waypoints={}
    for l=1,level do h.hero.level=l;scripts.hero_malik.level_up(h,store)end
    h.melee.order=U.attack_order(h.melee.attacks);h.hero.fn_level_up=scripts.hero_malik.level_up
    return h
  end
  local out={levels={},xp={},choices={},attacks={},deaths={},fissures={},paths={},regen={},animation_lengths=lengths}
  for l=1,10 do
    local h=hero(l);local a=h.melee.attacks;local au=E:get_template("aura_malik_fissure").aura
    out.levels[#out.levels+1]={level=l,hp=h.health.hp,armor=h.health.armor,regen=h.regen.health,
      min=a[1].damage_min,max=a[1].damage_max,smash=h.hero.skills.smash.level,fissure=h.hero.skills.fissure.level,
      smash_min=a[3].damage_min or 0,smash_max=a[3].damage_max or 0,stun_chance=a[3].mod_chance,
      fissure_min=au.damage_min,fissure_max=au.damage_max}
  end
  out.order=hero(10).melee.order
  for _,level_id in ipairs({3,7})do
    local h=hero(1);store.hero_xp_multiplier=GS.hero_xp_gain_per_difficulty_mode[2]*.1*level_id
    local sample={level_id=level_id,steps={}}
    for _,value in ipairs({1,1,1,1000,50000,0,1})do
      h.hero.xp_queued=value;local changed=SU.hero_level_up(store,h)
      sample.steps[#sample.steps+1]={queued=value,xp=h.hero.xp,level=h.hero.level,changed=changed}
    end
    out.xp[#out.xp+1]=sample
  end
  local target={id=2,pos=V.v(10,0),vis={flags=F_ENEMY,bans=0},health={dead=false},enemy={blockers={1}},unit={}}
  store.targets={target};store.entities[2]=target
  for _,time in ipairs({1,31/30,97/30,338/30})do
    for _,random in ipairs({.05,.9})do
      local h=hero(10);store.tick_ts=time;draw=random
      local attack=SU.soldier_pick_melee_attack(store,h,target);local index=-1
      for i,a in ipairs(h.melee.attacks)do if a==attack then index=i-1 end end
      out.choices[#out.choices+1]={tick=km.round(time*30),draw=random,index=index}
    end
  end
  for index=1,4 do for _,start_tick in ipairs({0,37})do
    local h=hero(10);h.unit.is_stunned=false;rows={};fx={};store.tick_ts=start_tick/30
    local attack=h.melee.attacks[index]
    local co=coroutine.create(function()
      if attack.type=="area"then SU.y_soldier_do_single_area_attack(store,h,target,attack)
      else SU.y_soldier_do_single_melee_attack(store,h,target,attack)end
    end)
    local stop
    for tick=start_tick,start_tick+60 do store.tick_ts=tick/30;assert(coroutine.resume(co));if coroutine.status(co)=="dead"then stop=tick;break end end
    out.attacks[#out.attacks+1]={index=index-1,start=start_tick,hit=rows[1] and rows[1].tick or -1,
      value=rows[1] and rows[1].value or 0,xp=rows[1] and rows[1].xp or 0,stop=stop}
  end end
  for _,kind in ipairs({DAMAGE_PHYSICAL,DAMAGE_DISINTEGRATE,DAMAGE_EAT,DAMAGE_HOST})do
    local h=hero(1);h.health.dead=true;h.health.hp=0;h.health.last_damage_types=kind;h.health_bar.hidden=true
    rows={};fx={};removed={};store.tick_ts=0
    local co=coroutine.create(function()SU.y_hero_death_and_respawn(store,h)end)
    local sample={kind=kind,states={}}
    for tick=0,480 do
      store.tick_ts=tick/30;assert(coroutine.resume(co))
      if tick==0 or tick==9 or tick==60 or tick==449 or tick==450 or coroutine.status(co)=="dead"then
        sample.states[#sample.states+1]={tick=tick,hidden=h.render.sprites[1].hidden or false,click=h.ui.can_click,
          hp=h.health.hp,ignore=h.health.ignore_damage,animation=h.animation or ""}
      end
      if coroutine.status(co)=="dead"then break end
    end
    sample.fx=fx;sample.removed=removed;out.deaths[#out.deaths+1]=sample
  end
  local h=hero(1);h.health.hp=100;h.regen.ts_counter=0;h.regen.last_hit_ts=0
  for tick=0,100 do store.tick_ts=tick/30;local old=h.health.hp;SU.soldier_regen(store,h)
    if old~=h.health.hp then out.regen[#out.regen+1]={tick=tick,hp=h.health.hp}end
  end
  local function eval(path,values)local f=assert(loadstring(read(path)));setfenv(f,setmetatable(values or {},{__index=_G}));return f()end
  for _,name in ipairs({"node_pos","nearest_nodes","is_node_valid","is_path_active","get_visible_start_node","get_visible_end_node"})do fn("all/path_db.lua","path_db:"..name)end
  env.GA=assert(loadstring(read("all/grid_a_star.lua")))()
  for _,name in ipairs({"get_coords","find_waypoints"})do fn("all/grid_db.lua","grid_db:"..name)end
  for _,level_id in ipairs({3,7})do
    local paths=eval(string.format("kr1/data/levels/level%02d_paths.lua",level_id),{v=V.v})
    P.paths=paths.paths;P.active_paths=paths.active;P.invalid_ranges={};P.visible_path_start_node={};P.visible_path_end_node={}
    for i,p in ipairs(P.paths)do P.invalid_ranges[i]={};P.visible_path_end_node[i]=#p[1];if P.active_paths[i]==nil then P.active_paths[i]=true end end
    for _,rank in ipairs({1,2,3,4})do for _,has_target in ipairs({true,false})do
      local aura=E:create_entity("aura_malik_fissure");aura.id=10;aura.aura.level=rank
      aura.pos=V.vclone(P.paths[1][1][80]);aura.aura.target_id=has_target and 2 or nil
      store.entities=has_target and {[2]={nav_path={pi=1,spi=1,ni=80}}} or {};store.targets={};fx={};removed={}
      local co=coroutine.create(function()scripts.aura_malik_fissure.update(aura,store)end)
      local stop
      for tick=31,80 do store.tick_ts=tick/30;assert(coroutine.resume(co));if coroutine.status(co)=="dead"then stop=tick;break end end
      out.fissures[#out.fissures+1]={level_id=level_id,rank=rank,has_target=has_target,pos=aura.pos,pulses=fx,stop=stop}
    end end
    local grid=eval(string.format("kr1/data/levels/level%02d_grid.lua",level_id))
    GR.grid=grid.grid;GR.ox=grid.ox;GR.oy=grid.oy;GR.cell_size=16;GR.grid_w=#GR.grid;GR.grid_h=#GR.grid[1];GR.waypoints_cache={}
    local from=P.paths[1][1][80];local to=P.paths[1][1][120]
    for _,pair in ipairs({{from,to},{from,from},{from,V.v(10,10)},{V.v(10,10),to}})do
      local points=GR:find_waypoints(pair[1],from,pair[2],2049,true)
      local sample={level_id=level_id,from=pair[1],fallback=from,to=pair[2],found=points~=nil,points=points or {}}
      if points and #points>0 and pair[1]==from then
        local walker=hero(1);walker.pos=V.vclone(from);walker.nav_rally.pos=V.vclone(pair[2]);walker.nav_grid.waypoints=table.deepclone(points)
        walker.motion.real_speed=78;store.tick_ts=0
        sample.walk={}
        local co=coroutine.create(function()SU.y_hero_walk_waypoints(store,walker)end)
        for tick=0,500 do
          store.tick_ts=tick/30;assert(coroutine.resume(co))
          if tick%10==0 or coroutine.status(co)=="dead"then sample.walk[#sample.walk+1]={tick=tick,x=walker.pos.x,y=walker.pos.y,done=coroutine.status(co)=="dead"}end
          if coroutine.status(co)=="dead"then break end
        end
      end
      out.paths[#out.paths+1]=sample
    end
  end
  return out
end
