function love.errorhandler(message)
  local f=assert(io.open(os.getenv('DOVE_PROJECT')..'/output/feedback_reference.error','wb'));f:write(message);f:close();os.exit(1)
end
function love.load()
  local root=assert(os.getenv('DOVE_SOURCE_DIR'));local project=assert(os.getenv('DOVE_PROJECT'))
  package.path=root..'/?.lua;'..root..'/all/?.lua;'..package.path
  require('lib.klua.table');require('all.constants')
  local V=require('lib.klua.vector');local json=require('lib.json');local bit=require('bit')
  local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
  local input=json.decode(read(project..'/output/feedback_reference_input.json'))
  local scripts_source=read(root..'/all/scripts.lua');local utils=read(root..'/all/utils.lua');local su_source=read(root..'/all/script_utils.lua');local paths=read(root..'/all/path_db.lua')
  local function load_function(text,name,next_name,env)
    local a=assert(text:find('function '..name,1,true),name)
    local b=next_name and assert(text:find(next_name,a+1,true),next_name) or assert(text:find('\nfunction ',a+1,true))
    local fn=assert(loadstring(text:sub(a,b-1),'@original/'..name));setfenv(fn,setmetatable(env,{__index=_G}));fn()
  end
  local result={provenance=input.provenance,powers={},cannons={},bombs={},guards={},slots={},guard_motion={},foremost={}}
  local seek_source=read(root..'/all/seek.lua')
  local ca=assert(seek_source:find('local function foremost_enemy_cmp',1,true))
  local cb=assert(seek_source:find('\nlocal function foremost_enemy_flying_preference_cmp',ca+1,true))
  local cmp_env={band=bit.band,P={nodes_to_goal=function(_,_,_,ni)return 100-ni end}}
  local cmp_chunk=assert(loadstring(seek_source:sub(ca,cb-1):gsub('local function foremost_enemy_cmp','function source_cmp',1),'@original/foremost_enemy_cmp'))
  setfenv(cmp_chunk,setmetatable(cmp_env,{__index=_G}));cmp_chunk()
  for _,scenario in ipairs({'same_node','next_node','mocking'})do
    local a={id=101,vis={flags=scenario=='mocking' and bit.bor(F_ENEMY,F_MOCKING) or F_ENEMY},nav_path={pi=1,spi=1,ni=11}}
    local b={id=102,vis={flags=F_ENEMY},nav_path={pi=1,spi=1,ni=scenario=='same_node' and 11 or 12}}
    result.foremost[#result.foremost+1]={scenario=scenario,target=cmp_env.source_cmp(b,a) and 102 or 101}
  end
  -- Actual format_text_expr, number formatting and rich number diff.
  local U={};local env={U=U}
  load_function(utils,'U.format_text_number',nil,env)
  load_function(utils,'U.format_text_expr',nil,env)
  local diff=require('dove_modules.gui.text_utils')
  for _,id in ipairs({'5','6'})do
    local data=input[id]
    U.eval_text_expr=function(expr,ctx)
      local f=assert(loadstring('return '..expr));setfenv(f,{T=function(n)return assert(data.templates[n],n)end,level=ctx.level,tdmg=ctx.ent.tower.damage_factor,tcd=ctx.ent.tower.cooldown_factor,math=math});return f()
    end
    for _,items in pairs(data.ui.tower_menus)do for _,item in ipairs(items)do if item.tt_list then
      for _,factor in ipairs({1,1.75})do for level,row in ipairs(item.tt_list)do
        local ctx={level=level,ent={tower={damage_factor=factor,cooldown_factor=factor==1 and 1 or 0.75}}}
        local text=U.format_text_expr(data.ui.strings[row.tt_desc],ctx)
        local current=''
        if level>1 then ctx.level=level-1;current=U.format_text_expr(data.ui.strings[item.tt_list[level-1].tt_desc],ctx)end
        local rich=level>1 and diff.create_diff_text(current,text) or diff.mark_number(text)
        result.powers[#result.powers+1]={content=tonumber(id),power=item.action_arg,level=level,factor=factor,cooldown=ctx.ent.tower.cooldown_factor,text=text,comparison=rich:gsub('{c:[^}]+}',''):gsub('{/c}','')}
      end end
    end end end
  end
  -- Actual path prediction and tower_engineer coroutine; controlled target life.
  local P={average_node_dist=8,paths={{{}}}}
  for i=1,80 do P.paths[1][1][i]=V.v(200+(i-1)*8,300)end
  function P:node_pos(pi,spi,ni)return V.vclone(self.paths[pi][spi][ni])end
  load_function(paths,'path_db:predict_enemy_node_advance',nil,{path_db=P,V=V,math=math,km={clamp=function(a,b,v)return math.max(a,math.min(b,v))end}})
  load_function(paths,'path_db:predict_enemy_pos',nil,{path_db=P})
  for _,scenario in ipairs({'stationary','moving','reselect','dead_without_replacement'})do
    local tick=0;local emitted={};local s={tower_engineer={}};local t=table.deepclone(input['6'].templates.tower_engineer_1);t.pos=V.v(200,200)
    local target={id=10,pos=V.v(283,300),nav_path={pi=1,spi=1,ni=11},motion={speed=V.v(scenario=='moving' and 30 or 0,0)}}
    local second={id=11,pos=V.v(296,300),nav_path={pi=1,spi=1,ni=13},motion={speed=V.v(0,0)}}
    local store={tick_ts=0};local u={animation_start=function()end,animation_finished=function()return true end}
    function u.find_foremost_enemy_in_range_filter_off()
      local e=target
      if tick>=102 and scenario=='reselect' then e=second elseif tick>=102 and scenario=='dead_without_replacement'then return nil end
      return e,{e},P:predict_enemy_pos(e,true)
    end
    local e={create_entity=function(_,name)local b=table.deepclone(input['6'].templates[name]);b.pos=V.v(0,0);b.bullet.from=V.v(0,0);b.bullet.to=V.v(0,0);return b end}
    load_function(scripts_source,'scripts.tower_engineer.update','\nscripts.tower_barrack =',{scripts=s,U=u,E=e,V=V,tpos=function(this)return V.v(this.pos.x,this.pos.y+this.tower.range_offset.y)end,simulation={queue_insert_entity=function(_,b)emitted[#emitted+1]={tick,b.pos.x,b.pos.y,b.bullet.to.x,b.bullet.to.y}end}})
    local co=coroutine.create(function()s.tower_engineer.update(t,store)end)
    for frame=0,130 do tick=frame;store.tick_ts=frame/30;local ok,error=coroutine.resume(co);assert(ok,error);if #emitted>0 then break end end
    assert(#emitted==1,scenario);result.cannons[#result.cannons+1]={scenario=scenario,shot=emitted[1]}
  end
  -- Original bomb insert/update with original gravity and ellipse falloff.
  for _,name in ipairs({'bomb','bomb_dynamite','bomb_black'})do
    local tick=0;local samples={};local hits={};local fx={};local s={bomb={}};local u={};local su={}
    local store={tick_ts=0,tick_length=1/30};local b=table.deepclone(input['6'].templates[name]);b.pos=V.v(200,250);b.bullet.from=V.v(200,250);b.bullet.to=V.v(300,300)
    local target={id=5,pos=V.v(300,300),vis={flags=F_ENEMY,bans=0}}
    local done=false
    function su.initial_parabola_speed(a,z,t,g)return V.v((z.x-a.x)/t,(z.y-a.y-0.5*g*t*t)/t)end
    function su.create_bullet_damage_without_pops_and_value()return {}end
    function su.create_bullet_pop()return nil end
    function u.find_enemies_in_range_filter_off()return {target}end
    local common={scripts=s,V=V,SU=su,U=u,math=setmetatable({random=function()return 0.5 end},{__index=math}),km={clamp=function(a,z,v)return math.max(a,math.min(z,v))end},cos=math.cos,sin=math.sin,UP={get_upgrade=function()return nil end},GR={cell_type=function()return 1 end},band=bit.band,S={queue=function()end},E={create_entity=function(_,n)return {template=n,pos=V.v(0,0),render={sprites={{}}}}end},queue_damage=function(_,d)hits[#hits+1]={tick,d.value}end,simulation={queue_insert_entity=function(_,e)fx[#fx+1]={e.template,e.pos.x,e.pos.y}end,queue_remove_entity=function()done=true end}}
    load_function(utils,'U.dist_factor_inside_ellipse',nil,common)
    load_function(scripts_source,'scripts.bomb.insert',nil,common)
    load_function(scripts_source,'scripts.bomb.update','\nscripts.enemy_bomb =',common)
    assert(s.bomb.insert(b,store));local co=coroutine.create(function()s.bomb.update(b,store)end)
    for frame=0,40 do tick=frame;store.tick_ts=frame/30;local ok,error=coroutine.resume(co);assert(ok,error);samples[#samples+1]={frame,b.pos.x,b.pos.y,b.render.sprites[1].r or 0,b.render.sprites[1].hidden==true};if done then break end end
    result.bombs[#result.bombs+1]={template=name,samples=samples,hits=hits,effects=fx}
  end
  -- Original soldier target selection, blocker validity and melee slot geometry.
  local u={};local su={};local candidates;local store={entities={}}
  local common={U=u,SU=su,V=V,band=bit.band,bor=bit.bor,abs=math.abs,PI=math.pi,km={signed_unroll=function(a)return a end,zmod=function(a,b)return (a-1)%b+1 end},GR={cell_type=function(_,x,y)for _,e in ipairs(candidates)do if e.pos.x==x and e.pos.y==y then return e.terrain or 1 end end;return 1 end}}
  for _,name in ipairs({'U.blocker_rank','U.is_blocked_valid','U.dec_blocker','U.unblock_target','U.block_enemy','U.melee_slot_position'})do load_function(utils,name,nil,common)end
  load_function(su_source,'SU.soldier_pick_melee_target',nil,common)
  function u.detect_foremost_enemy_in_range_filter_on(center,range,flags,bans,filter)
    local chosen
    for _,e in ipairs(candidates)do local dx=e.pos.x-center.x;local dy=(e.pos.y-center.y)/0.7
      if not e.health.dead and bit.band(e.vis.bans,flags)==0 and bit.band(e.vis.flags,bans)==0 and dx*dx+dy*dy<=range*range and filter(e) and (not chosen or e.node>chosen.node)then chosen=e end
    end
    return chosen
  end
  local guard=input['6'].templates.soldier_s6_imperial_guard
  for _,scenario in ipairs({'near','primary','secondary','invalid_block','no_walk','cliff','outside','dead'})do
    local s={id=1,pos=V.v(290,390),nav_rally={center=V.v(290,390)},soldier={melee_slot_offset=V.v(8,0)},melee=guard.melee}
    candidates={{id=101,pos=V.v(310,390),health={dead=false},vis={flags=F_ENEMY,bans=0},enemy={blockers={}},node=10},{id=102,pos=V.v(330,390),health={dead=false},vis={flags=F_ENEMY,bans=0},enemy={blockers={}},node=11}}
    store.entities={[101]=candidates[1],[102]=candidates[2],[1]=s}
    if scenario=='primary' or scenario=='secondary' or scenario=='invalid_block'then s.soldier.target_id=101;candidates[1].enemy.blockers=scenario=='secondary' and {999,1} or {1}end
    if scenario=='invalid_block'then candidates[1].vis.bans=F_BLOCK end
    if scenario=='no_walk'then candidates[2].terrain=TERRAIN_NOWALK end
    if scenario=='cliff'then candidates[2].vis.flags=F_CLIFF end
    if scenario=='outside'then candidates[1].pos.x=400;candidates[2].pos.x=420 end
    if scenario=='dead'then candidates[1].health.dead=true;candidates[2].node=9 end
    local target=su.soldier_pick_melee_target(store,s)
    result.guards[#result.guards+1]={scenario=scenario,target=target and target.id or 0}
  end
  for rank=1,4 do for _,angle in ipairs({0,math.pi})do
    local e={pos=V.v(300,390),heading={angle=angle},enemy={melee_slot=V.v(18,0),blockers={1,2,3,4}}}
    local s={id=rank,soldier={melee_slot_offset=V.v(8,0)}}
    local p=u.melee_slot_position(s,e)
    result.slots[#result.slots+1]={rank,angle,p.x,p.y}
  end end
  -- Actual slot movement and its arrival yield, separate from target-search mocks.
  common.atan2=math.atan2;common.cos=math.cos;common.sin=math.sin
  load_function(utils,'U.walk_off__accel__unsnapped',nil,common)
  load_function(su_source,'SU.soldier_move_to_slot_step',nil,common)
  function u.set_destination(s,p)s.motion.dest=p;s.motion.arrived=false end
  function u.animation_name_facing_point(_,name,_)return name,false end
  function u.animation_start_default(s,name)s.animation=name end
  for _,offset in ipairs({1,4,19,50})do
    local e={id=101,pos=V.v(300,390),heading={angle=0},enemy={melee_slot=V.v(18,0),blockers={}},motion={arrived=true}}
    local s={id=1,pos=V.v(326-offset,390),soldier={melee_slot_offset=V.v(8,0)},motion={real_speed=guard.motion.max_speed,arrived=false,speed=V.v(0,0)}}
    store.entities={[101]=e,[1]=s};store.tick_length=1/30
    local samples={}
    for tick=1,30 do store.tick_ts=tick/30;local moving=su.soldier_move_to_slot_step(store,s,e);samples[#samples+1]={tick,s.pos.x,s.pos.y,moving};if not moving then break end end
    result.guard_motion[#result.guard_motion+1]={offset=offset,samples=samples}
  end
  local f=assert(io.open(project..'/tests/fixtures/feedback_source.json','wb'));f:write(json.encode(result));f:close()
  love.event.quit()
end
