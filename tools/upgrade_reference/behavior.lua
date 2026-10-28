-- Source coroutines and helpers run with controlled services and RNG draws.
-- Stubs supply only entity queues/clock/terrain; formulas execute from Dove.
return function(root, project, original, UP)
  local V=require("lib.klua.vector");local bit=require("bit")
  local function read(p)local f=assert(io.open(root.."/"..p,"rb"));local s=f:read("*a");f:close();return s end
  local src=read("all/scripts.lua");local game=read("kr1/game_scripts.lua")
  local function compile(text, marker, ending, env)
    local start=assert(text:find(marker,1,true),marker)
    local finish=assert(text:find(ending,start+#marker,true),ending)
    local chunk=assert(loadstring(text:sub(start,finish-1)));setfenv(chunk,env);chunk()
  end
  local function fn(text,name,env)
    local body=assert(text:match("function "..name:gsub("%.","%%.").."%((.-)\nend"),name)
    local chunk=assert(loadstring("function "..name.."("..body.."\nend"));setfenv(chunk,env);chunk()
  end
  local U={};local scripts={mod_dps={},mod_blood_elves={},mod_slow={},mod_slow_curse={},mod_damage={},aura_apply_damage={},power_fireball_control={}}
  local rows={};local store={entities={},enemies={},tick_ts=0,tick_length=1/30}
  local random_value=0.05;local mathenv=setmetatable({random=function(a,b)if a then return math.floor((a+b)/2)end;return random_value end},{__index=math})
  local simulation={queue_remove_entity=function(_,e)e.removed=true end,queue_insert_entity=function(_,e)rows[#rows+1]={tick=math.floor(store.tick_ts*30+0.5),to={x=e.bullet.to.x,y=e.bullet.to.y}}end}
  local E={assign_damage=function(kind,value,source,target)return {damage_type=kind,value=value,source_id=source,target_id=target,reduce_armor=0,reduce_magic_armor=0,hooks={}}end,
    create_entity=function()return {pos=V.v(0,0),bullet={from=V.v(0,0)}}end}
  local env=setmetatable({U=U,scripts=scripts,UP=UP,E=E,V=V,FPS=30,math=mathenv,random=function()return random_value end,band=bit.band,bor=bit.bor,
    km={clamp=function(a,b,x)return math.max(a,math.min(b,x))end},signal={emit=function()end},log={paranoid=function()end},simulation=simulation,
    queue_damage=function(_,d)rows[#rows+1]={tick=math.floor(store.tick_ts*30+0.5),value=d.value,kind=d.damage_type}end}, {__index=_G})
  for _,name in ipairs({"calc_protection","predict_damage"})do fn(read("all/utils.lua"),"U."..name,env)end
  for _,name in ipairs({"mod_dps.insert","mod_dps.update","mod_damage.insert","mod_slow.insert","mod_slow.remove","aura_apply_damage.update","power_fireball_control.update"})do fn(src,"scripts."..name,env)end
  for _,name in ipairs({"mod_blood_elves.insert","mod_slow_curse.insert"})do fn(game,"scripts."..name,env)end
  local prec=assert(read("kr1/tower_scripts.lua"):match("local function apply_precision%(b%)(.-)\nend"))
  local f=assert(loadstring("return function(b)"..prec.."\nend"));setfenv(f,env);local precision=f()
  UP.levels={archers=6,barracks=6,mages=6,engineers=6,rain=6,reinforcements=6};UP.max_level=6;UP:set_list_id("1")
  local out={precision={}}
  for _,draw in ipairs({0.05,0.5})do random_value=draw;local b={bullet={damage_min=4,damage_max=6}};precision(b);out.precision[#out.precision+1]={draw=draw,min=b.bullet.damage_min,max=b.bullet.damage_max,critical=b.bullet.pop~=nil}end
  local target={id=1,template_name="enemy_dark_knight",health={dead=false,hp=10000,hp_max=10000,armor=0.8,magic_armor=0,poison_armor=0,damage_factor=1.2},vis={flags=F_ENEMY,bans=0},unit={size=1},motion={max_speed=60},pos=V.v(500,300)}
  store.entities[1]=target
  local d=E.assign_damage(DAMAGE_PHYSICAL,100,2,1);d.reduce_armor=0.1
  out.penetration=U.predict_damage(target,d)
  U.has_modifier_types=function()return false,{}end
  random_value=0.05
  local bleed=table.deepclone(original.mod_blood_elves);bleed.modifier.target_id=1;bleed.modifier.source_damage=d
  assert(scripts.mod_blood_elves.insert(bleed,store));out.bleeding_damage=bleed.dps.damage_min
  bleed.dps.fx=nil;rows={};local co=coroutine.create(function()scripts.mod_dps.update(bleed,store)end)
  for tick=1,91 do store.tick_ts=tick/30;if coroutine.status(co)=="dead"then break end;assert(coroutine.resume(co))end
  out.bleeding_pulses=rows
  local slow=table.deepclone(original.mod_slow_curse);slow.modifier.target_id=1
  U.speed_mul=function(t,v)t.motion.max_speed=t.motion.max_speed*v end;U.speed_div=function(t,v)t.motion.max_speed=t.motion.max_speed/v end
  out.slow_insert=scripts.mod_slow_curse.insert(slow,store);out.slow_speed=target.motion.max_speed
  scripts.mod_slow.remove(slow,store);out.slow_removed_speed=target.motion.max_speed
  U.has_modifier_types=function()return true,{}end;out.rage_rejected=not scripts.mod_slow_curse.insert(slow,store)
  -- Real aura coroutine: late insertion, excludes flying and mod-immune targets.
  U.find_enemies_in_range_filter_off=function(_,_,flags,bans)
    return table.filter(store.enemies,function(_,e)return not e.health.dead and bit.band(e.vis.flags,bans)==0 and bit.band(e.vis.bans,flags)==0 end)
  end
  store.enemies={target,{id=2,health={dead=false},vis={flags=bit.bor(F_ENEMY,F_FLYING),bans=0}},{id=3,health={dead=false},vis={flags=F_ENEMY,bans=F_MOD}}}
  rows={};local aura=table.deepclone(original.power_scorched_earth);aura.aura.duration=10;aura.aura.damage_min=20;aura.aura.damage_max=30;aura.pos=V.v(500,300)
  co=coroutine.create(function()scripts.aura_apply_damage.update(aura,store)end)
  for tick=61,362 do store.tick_ts=tick/30;if coroutine.status(co)=="dead"then break end;assert(coroutine.resume(co))end
  out.scorched_pulses=rows
  -- Fire control uses the real target prediction and coroutine timing. Spread
  -- is zero only in this fixture so coordinates do not depend on RNG engines.
  env.GR={cell_size=16,cell_type=function()return TERRAIN_LAND end}
  local path={};for i=1,300 do path[i]=V.v(500,(i-1)*6)end
  env.P={paths={{path,path,path}},average_node_dist=6,node_pos=function(_,_,_,n)return path[n]end,get_random_position=function()return V.v(500,300)end}
  target.health.damage_factor=1;target.enemy={blockers={}};target.unit.is_stunned=false;target.motion.speed=V.v(0,30);target.motion.real_speed=30;target.nav_path={pi=1,spi=1,ni=51}
  store.enemies={target};rows={};store.tick_ts=0
  local control={pos=V.v(500,300),fireball_count=6,cataclysm_count=6,max_spread=0,user_power={level=6}}
  co=coroutine.create(function()scripts.power_fireball_control.update(control,store)end)
  for tick=0,70 do store.tick_ts=tick/30;if coroutine.status(co)=="dead"then break end;assert(coroutine.resume(co))end
  out.fire_bursts=rows
  -- Brilliance invokes the real tower insert/remove hooks; absent templates
  -- have inert numeric fixtures, exactly as the template patch oracle.
  local TE={};function TE:get_template(name)if not TE[name]then TE[name]={bullet={damage_min=10,damage_max=20},dps={damage_min=10,damage_max=20},modifier={damage_min=10,damage_max=20},boss_damage_config={},aura={damage_min=10,damage_max=20}}end;return TE[name]end
  package.loaded.entity_db=TE;local tower=require("all.systems.tower");local ts={};tower:init(ts);out.brilliance={}
  for _,op in ipairs({{"insert",1},{"insert",2},{"remove",1},{"remove",2},{"insert",3}})do
    tower[op[1]=="insert" and "on_insert_unconditional" or "on_remove_unconditional"](tower,{id=op[2],tower={},template_name="tower_mage_1"},ts)
    out.brilliance[#out.brilliance+1]=TE:get_template("bolt_1").bullet.damage_max/20
  end
  return out
end
