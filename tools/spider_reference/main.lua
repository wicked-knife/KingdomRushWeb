-- Execute the pinned Dove mother/spawner coroutines in an isolated frame clock.
-- Only engine services (entity queues, movement and rendering) are substituted.
function love.errorhandler(message) io.stderr:write(message,"\n");os.exit(1) end
function love.load()
  local root=assert(os.getenv("DOVE_SOURCE_DIR"));local project=assert(os.getenv("DOVE_PROJECT"))
  package.path=root.."/?.lua;"..root.."/all/?.lua;"..package.path
  require("lib.klua.table")
  local json=require("lib.json")
  local function read(path)local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close();return s end
  local input=json.decode(read(project.."/output/spider_reference_input.json"))
  local source=read(root.."/all/scripts.lua");local utils=read(root.."/all/utils.lua")
  local scripts={enemies_spawner={}};local U={};local store={tick_ts=0,entities={}}
  local rows={};local spawned={};local tick=0;local removed=false
  local E={create_entity=function(_,name)
    local e=table.deepclone(input.templates[name]);e.template_name=name;e.pos={x=0,y=0};e.nav_path={};return e
  end}
  local simulation={queue_insert_entity=function(_,e)
    spawned[#spawned+1]={tick=tick,template=e.template_name,path=e.nav_path.pi,subpath=e.nav_path.spi,node=e.nav_path.ni,x=e.pos.x,y=e.pos.y,gold=e.enemy and e.enemy.gold or 0}
  end,queue_remove_entity=function()removed=true end}
  local env=setmetatable({scripts=scripts,U=U,E=E,simulation=simulation,S={queue=function()end},km={zmod=function(n,d)return (n-1)%d+1 end}}, {__index=_G})
  local function fn(text,name)
    local body=assert(text:match("function "..name:gsub("%.","%%.").."%((.-)\nend"),name)
    local f=assert(loadstring("function "..name.."("..body.."\nend"));setfenv(f,env);f()
  end
  for _,name in ipairs({"animation_start","animation_start_default","y_animation_play","y_wait_conditional","enemy_ready_to_magic_attack","cast_silence","remove_silence"})do fn(utils,"U."..name)end
  -- The Godot simulator has an integer 30 Hz clock. Normalize only the engine
  -- wait service to that clock; fractional Lua timestamp drift is not gameplay.
  U.y_wait_conditional=function(_,seconds,stop)
    local until_tick=tick+math.floor(seconds*30+0.5)
    while tick<until_tick do if stop()then return true end;coroutine.yield()end
    return false
  end
  fn(source,"scripts.enemies_spawner.update")
  local egg=table.deepclone(input.templates.enemy_spider_egg);egg.pos={x=500,y=300};egg.spawner.pi=1;egg.spawner.spi=2;egg.spawner.ni=31
  local co=coroutine.create(function()scripts.enemies_spawner.update(egg,store)end)
  for frame=0,228 do
    tick=frame;store.tick_ts=frame==0 and 0 or store.tick_ts+1/30
    local sprite=egg.render.sprites[1]
    if frame>0 then
      local a=input.animations[sprite.prefix.."_"..sprite.name]
      sprite.runs=math.floor((frame-math.floor(sprite.ts*30+0.5))/#a.frames)
    end
    if coroutine.status(co)~="dead"then assert(coroutine.resume(co))end
    sprite=egg.render.sprites[1]
    local a=input.animations[sprite.prefix.."_"..sprite.name]
    local elapsed=frame-math.floor(sprite.ts*30+0.5)
    local index=sprite.loop and elapsed%#a.frames+1 or math.min(elapsed+1,#a.frames)
    local fade=not egg.tween.disabled
    local fade_tick=fade and math.floor(sprite.ts*30+0.5) or -1
    local alpha=fade and math.max(0,1-(frame-fade_tick)/120)or 1
    rows[#rows+1]={tick=frame,state=sprite.name,frame=string.format("%s_%04d",a.prefix,a.frames[index]),spawned=#spawned,alpha=alpha}
  end
  local result={source=input.source,animations=input.animations,spawns=spawned,frames=rows}
  -- Real mother readiness and silence cooldown suspension; fixed RNG draw only.
  env.enemy_ready_to_magic_attack=U.enemy_ready_to_magic_attack
  U.frandom=function()return 5 end;U.get_blocker=function(_,e)return e.blocked end
  U.y_animation_play=function()error("mother must not play a laying animation")end
  env.SU={y_enemy_mixed_walk_melee_ranged=function()return true end,y_enemy_death=function()end}
  local game=read(root.."/kr1/game_scripts.lua")
  local body=assert(game:match("scripts.enemy_spider_big = (%b{})"))
  local f=assert(loadstring("return "..body));setfenv(f,env);scripts.enemy_spider_big=f()
  local mother=table.deepclone(input.templates.enemy_spider_big)
  mother.pos={x=500,y=300};mother.nav_path={pi=1,spi=2,ni=31}
  mother.timed_attacks.list[1].max_count=mother.timed_attacks.list[1].max_count[2]
  mother.health.dead=false;spawned={}
  co=coroutine.create(function()scripts.enemy_spider_big.update(mother,store)end)
  for frame=0,760 do
    tick=frame;store.tick_ts=frame==0 and 0 or store.tick_ts+1/30
    if frame==140 then U.cast_silence(mother,store.tick_ts)end
    if frame==200 then U.remove_silence(mother,store.tick_ts)end
    mother.blocked=frame>=350 and frame<390
    mother.unit.is_stunned=frame>=530 and frame<550
    assert(coroutine.resume(co))
  end
  result.mother_spawns=spawned
  local out=assert(io.open(project.."/tests/fixtures/dove_spider_source.json","wb"));out:write(json.encode(result));out:close()
  love.event.quit()
end
