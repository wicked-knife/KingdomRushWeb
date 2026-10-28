-- Run the actual current Dove helpers and bolt coroutine, with controlled inputs.
function love.errorhandler(message) io.stderr:write(message,"\n");os.exit(1) end
function love.load()
  local root=assert(os.getenv("DOVE_SOURCE_DIR"))
  package.path=root.."/?.lua;"..root.."/all/?.lua;"..package.path
  require("lib.klua.table");require("all.constants")
  local V=require("lib.klua.vector");local json=require("lib.json");local bit=require("bit")
  local function read(p)local f=assert(io.open(root.."/"..p,"rb"));local s=f:read("*a");f:close();return s end
  local catalog=json.decode(assert(io.open(assert(os.getenv("DOVE_CATALOG")),"rb")):read("*a"))
  local out={source=catalog.source,factors={},bolts={}}
  local SU={insert_unit_cooldown_buff=function()end}
  local src=read("all/script_utils.lua")
  local begin=assert(src:find("local function prepare_unit_damage_factor",1,true))
  local ending=assert(src:find("function SU.spiked_armor_inc",begin,true))
  local env=setmetatable({SU=SU},{__index=_G})
  local f=assert(loadstring(src:sub(begin,ending-1)));setfenv(f,env);f()
  for _,name in ipairs({"insert_tower_damage_factor_buff","remove_tower_damage_factor_buff","soldier_inherit_tower_buff_factor"})do
    local body=assert(src:match("function SU%."..name.."%((.-)\nend"))
    local fn=assert(loadstring("function SU."..name.."("..body.."\nend"));setfenv(fn,env);fn()
  end
  local ops={{1.2,false},{1.3,false},{0.8,false},{0.5,false},{1.2,true},{0.8,true},{1.3,true},{0.5,true}}
  out.operations=ops
  for _,received in ipairs({false,true})do
    local unit={unit={damage_factor=1.1},health={damage_factor=1.1}}
    local values={};local prefix=received and "received" or "unit"
    for _,op in ipairs(ops)do
      SU[(op[2] and "remove_" or "insert_")..prefix.."_damage_factor_by_factor"](unit,op[1])
      values[#values+1]=unit[received and "health" or "unit"].damage_factor
    end
    out.factors[prefix]=values
  end
  local soldier={unit={damage_factor=1.1}};local dead={unit={damage_factor=1},health={dead=true}}
  local tower={tower={damage_factor=1,cooldown_factor=1},barrack={soldiers={soldier,dead}}}
  SU.insert_tower_damage_factor_buff(tower,0.2);SU.insert_tower_damage_factor_buff(tower,0.3)
  local replacement={unit={damage_factor=1.1}};SU.soldier_inherit_tower_buff_factor(replacement,tower,0)
  out.tower={tower.tower.damage_factor,soldier.unit.damage_factor,dead.unit.damage_factor,replacement.unit.damage_factor}
  SU.remove_tower_damage_factor_buff(tower,0.2)
  out.tower_removed={tower.tower.damage_factor,soldier.unit.damage_factor,dead.unit.damage_factor}
  src=read("all/scripts.lua")
  local body=assert(src:match("function scripts.bolt.update%(this, store%)(.-)\nscripts.bolt_curve =")):gsub("\nend%s*$","")
  for _,name in ipairs({"stationary","moving","teleport","dead","ranged_ban","near"})do
    local target={id=1,pos=V.v(300,100),health={dead=false},unit={hit_offset=V.v(0,10),size=1},vis={flags=F_ENEMY,bans=0}}
    local bullet={min_speed=30,max_speed=300,acceleration_factor=0.1,max_track_distance=60,target_id=1,source_id=9,damage_factor=1.5,level=2,speed=V.v(0,0),to=V.v(300,110),mod="allowed",mods={"allowed","blocked"}}
    if name=="near" then bullet.to=V.v(100.5,100)end
    local entity={id=2,pos=V.v(100,100),bullet=bullet,render={sprites={{}}},sound_events={}}
    local store={entities={[1]=target},tick_length=1/30,tick_ts=0};local done=false;local hits=0;local mods={}
    local benv=setmetatable({V=V,FPS=30,km={clamp=function(a,b,x)return math.max(a,math.min(b,x))end},
      U={animation_start_default=function()end,flags_pass=function(vis,rule)return bit.band(vis.flags,rule.vis_bans or 0)==0 end},
      S={queue=function()end},SU={create_bullet_damage=function()return {} end},queue_damage=function()hits=hits+1 end,
      E={get_template=function(_,n)return {modifier={vis_bans=n=="blocked" and F_ENEMY or 0}}end,create_entity=function(_,n)return {name=n,modifier={}}end},
      simulation={queue_insert_entity=function(_,m)mods[#mods+1]={m.name,m.modifier.source_id,m.modifier.damage_factor,m.modifier.level}end,queue_remove_entity=function()done=true end}}, {__index=_G})
    local fn=assert(loadstring("return function(this,store)"..body.."\nend"));setfenv(fn,benv)
    local co=coroutine.create(function()fn()(entity,store)end);local samples={}
    for tick=0,80 do
      store.tick_ts=tick/30
      if name=="moving" and tick>2 then target.pos.x=target.pos.x+1 end
      if name=="teleport" and tick==5 then target.pos.x=target.pos.x+200 end
      if name=="dead" and tick==5 then target.health.dead=true end
      if name=="ranged_ban" and tick==4 then target.vis.bans=F_RANGED end
      local ok,err=coroutine.resume(co);assert(ok,err)
      samples[#samples+1]={tick,entity.pos.x,entity.pos.y,bullet.to.x,bullet.to.y}
      if done then break end
    end
    out.bolts[name]={samples=samples,hits=hits,mods=mods}
  end
  local file=assert(io.open(assert(os.getenv("DOVE_REFERENCE_OUTPUT")),"wb"));file:write(json.encode(out));file:close()
  love.event.quit(0)
end
