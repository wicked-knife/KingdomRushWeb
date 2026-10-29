function love.errorhandler(message)
  local f=assert(io.open(os.getenv('DOVE_PROJECT')..'/output/followup_reference.error','wb'));f:write(message);f:close();os.exit(1)
end
function love.load()
  local root=assert(os.getenv('DOVE_SOURCE_DIR'));local project=assert(os.getenv('DOVE_PROJECT'))
  package.path=root..'/?.lua;'..root..'/all/?.lua;'..package.path
  require('lib.klua.table');require('all.constants')
  local V=require('lib.klua.vector');local json=require('lib.json');local bit=require('bit')
  local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
  local input=json.decode(read(project..'/output/followup_reference_input.json'))
  local scripts_source=read(root..'/all/scripts.lua');local utils=read(root..'/all/utils.lua');local su_source=read(root..'/all/script_utils.lua')
  local function load_function(text,name,next_name,env)
    local a=assert(text:find('function '..name,1,true),name)
    local b=next_name and assert(text:find(next_name,a+1,true),next_name) or assert(text:find('\nfunction ',a+1,true))
    local fn=assert(loadstring(text:sub(a,b-1),'@original/'..name));setfenv(fn,setmetatable(env,{__index=_G}));fn()
  end
  local result={provenance=input.provenance,bombs={},casts={},sale={},hover={}}
  -- Read the actual default, rather than mistaking animation FPS for simulation FPS.
  local main=read(root..'/all/main_utils.lua')
  result.default_fps=tonumber(assert(main:match('d%("fps", (%d+)%)')))
  for _,fps in ipairs({30,60,result.default_fps})do for _,name in ipairs({'bomb','bomb_dynamite','bomb_black'})do
    local tick=0;local samples={};local done=false;local s={bomb={}};local su={};local store={tick_ts=0,tick_length=1/fps}
    local b=table.deepclone(input.templates[name]);b.pos=V.v(200,250);b.bullet.from=V.v(200,250);b.bullet.to=V.v(300,300)
    local common={scripts=s,V=V,SU=su,U={find_enemies_in_range_filter_off=function()return nil end},math=setmetatable({random=function()return 0.5 end},{__index=math}),UP={get_upgrade=function()return nil end},GR={cell_type=function()return 1 end},band=bit.band,S={queue=function()end},E={create_entity=function(_,n)return {template=n,pos=V.v(0,0),render={sprites={{}}}}end},simulation={queue_insert_entity=function()end,queue_remove_entity=function()done=true end}}
    load_function(su_source,'SU.initial_parabola_speed',nil,common)
    su.create_bullet_pop=function()return nil end
    load_function(scripts_source,'scripts.bomb.insert',nil,common);load_function(scripts_source,'scripts.bomb.update','\nscripts.enemy_bomb =',common)
    assert(s.bomb.insert(b,store));local co=coroutine.create(function()s.bomb.update(b,store)end)
    for frame=0,fps*2 do
      tick=frame;store.tick_ts=frame/fps;local ok,error=coroutine.resume(co);assert(ok,error)
      samples[#samples+1]={frame/fps,b.pos.x,b.pos.y,b.render.sprites[1].r or 0,b.render.sprites[1].hidden==true}
      if done then break end
    end
    result.bombs[#result.bombs+1]={fps=fps,template=name,flight=b.bullet.flight_time,samples=samples}
  end end
  -- Run the original complete tower coroutine through two automatic teleports.
  local tower_source=read(root..'/kr1/tower_scripts.lua')
  local a=assert(tower_source:find('scripts.tower_arcane_wizard = {',1,true))
  local z=assert(tower_source:find('\nscripts.',a+1,true))
  for _,factor in ipairs({1,0.75})do
    local tick=0;local events={};local store={tick_ts=0,tick_length=1/30};local s={};local u={};local t=table.deepclone(input.templates.tower_arcane_wizard)
    t.id=1;t.pos=V.v(400,300);t.tower.cooldown_factor=factor;t.powers.teleport.level=1;t.powers.teleport.changed=true
    local enemy={id=10,pos=V.v(450,310),health={hp=100000},unit={},enemy={counts={}},nav_path={ni=50}}
    local function create(_,name)
      local b=table.deepclone(input.templates[name]);b.template_name=name;b.pos=V.v(0,0)
      if b.bullet then b.bullet.from=V.v(0,0);b.bullet.to=V.v(0,0)end
      return b
    end
    function u.detect_foremost_enemy_in_range_filter_on(_,_,_,_,filter)return filter(enemy) and enemy or nil end
    function u.calculate_enemy_ffe_pos(e)return V.vclone(e.pos)end
    function u.animation_start(e,name,flip,ts,loop,sid)
      local sprite=e.render.sprites[sid];sprite.name=name;sprite.ts=ts;sprite.loop=loop;sprite.runs=0
    end
    local common={scripts=s,U=u,V=V,vclone=V.vclone,E={get_template=function(_,n)return input.templates[n]end,create_entity=create},tpos=function(e)return V.v(e.pos.x,e.pos.y+e.tower.range_offset.y)end,animation_start=u.animation_start,animation_name_facing_point=function(_,name)return name..'Up',false end,fts=function(f)return f/30 end,ready_to_attack=function(...)return u.ready_to_attack(...)end,simulation={queue_insert_entity=function(_,b)events[#events+1]={tick,b.template_name}end}}
    for _,name in ipairs({'U.y_wait_unconditional','U.y_animation_wait','U.ready_to_attack','U.tower_ready_to_use_power'})do load_function(utils,name,nil,common)end
    common.y_animation_wait=u.y_animation_wait
    local fn=assert(loadstring(tower_source:sub(a,z-1),'@original/tower_arcane_wizard'));setfenv(fn,setmetatable(common,{__index=_G}));fn()
    local co=coroutine.create(function()s.tower_arcane_wizard.update(t,store)end)
    for frame=0,1000 do
      tick=frame;store.tick_ts=frame/30
      for _,sprite in ipairs(t.render.sprites)do
        local key=sprite.prefix and sprite.prefix..'_'..sprite.name or sprite.name
        local anim=input.animations[key]
        if anim and not sprite.loop and (store.tick_ts-sprite.ts)*30>=#anim.frames then sprite.runs=1 end
      end
      local ok,error=coroutine.resume(co);assert(ok,error)
    end
    result.casts[#result.casts+1]={cooldown_factor=factor,events=events,teleport_animation=input.animations.tower_arcane_wizard_teleport}
  end
  -- Removal marks soldiers dead internally, queues each for removal and clears garrison.
  local s={tower_barrack={}};local su={};local removed={};local env={scripts=s,SU=su,simulation={queue_remove_entity=function(_,e)removed[#removed+1]=e.id end}}
  load_function(su_source,'SU.queue_remove_clean_table',nil,env)
  load_function(scripts_source,'scripts.tower_barrack.remove',nil,env)
  local tower={barrack={soldiers={{id=10,health={}},{id=11,health={}}}}};s.tower_barrack.remove(tower,{})
  result.sale={removed=removed,remaining=#tower.barrack.soldiers}
  -- Hover swaps the first layer without raising z or changing drawing order.
  local gui=read(root..'/all-desktop/game_gui.lua');local pick={};local env={PickView=pick,game_gui={game={store={paused=false}}},S={queue=function()end}}
  load_function(gui,'PickView:show_tower_hover',nil,env);load_function(gui,'PickView:hide_tower_hover',nil,env)
  for _,z in ipairs({1300,1400})do
    local e={render={sprites={{name='build_terrain_0001',z=z,draw_order=1}}}};pick:show_tower_hover(e)
    result.hover[#result.hover+1]={z=e.render.sprites[1].z,name=e.render.sprites[1].name,draw_order=e.render.sprites[1].draw_order}
    pick:hide_tower_hover();assert(e.render.sprites[1].name=='build_terrain_0001')
  end
  local f=assert(io.open(project..'/tests/fixtures/followup_source.json','wb'));f:write(json.encode(result));f:close()
  love.event.quit(0)
end
