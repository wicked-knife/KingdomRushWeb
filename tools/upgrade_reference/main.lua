-- Actual Dove upgrade functions on exported source templates. Unpublished targets
-- use inert fixtures, explicitly reported and excluded from comparisons.
function love.load()
  local ok,err=xpcall(function()
    local root=assert(os.getenv("DOVE_SOURCE_DIR"));local project=assert(os.getenv("DOVE_PROJECT"))
    package.path=root.."/?.lua;"..root.."/all/?.lua;"..root.."/kr1/?.lua;"..package.path
    require("lib.klua.table");require("all.constants")
    local json=require("lib.json")
    local function read(p)local f=assert(io.open(p,"rb"));local t=f:read("*a");f:close();return t end
    local original={}
    local reference_level=tonumber(os.getenv("DOVE_UPGRADE_LEVEL"))
    for _,id in ipairs(reference_level and {reference_level} or {5,6})do
      for k,v in pairs(json.decode(read(project..string.format("/data/level%02d/definition.json",id))).templates)do original[k]=v end
    end
    local skipped={};local current={}
    local function inert()
      local at={range=0,max_range=0,range_base=0,cooldown=1,cooldown_factor=1,cooldown_base=1,cooldown_inc=0,cooldown_mixed_base=1,cooldown_flying=1,damage_min=0,damage_max=0}
      return {tower={price=0,damage_factor=1},health={hp_max=0,armor=0,armor_lvls={},dead_lifetime=1,magic_armor=0,spiked_armor=0},health_level={},powers=setmetatable({}, {__index=function(t,k)local v={cooldown=k=="tree" and 0 or {},cooldown_dec=0,cooldown_mixed_dec=0,cooldown_inc=0};rawset(t,k,v);return v end}),barrack={rally_range=0},attacks={min_cooldown=1,range=0,list={table.deepclone(at),table.deepclone(at),table.deepclone(at),table.deepclone(at)}},bullet={damage_min=0,damage_max=0,damage_hooks={},reduce_armor=0},dps={damage_min=0,damage_max=0},aura={damage_min=0,damage_max=0,damage_inc=0,cooldown=1},modifier={damage_min=0,damage_max=0},boss_damage_config={},ranged={attacks={table.deepclone(at)}},damage_min=0,damage_max=0,bounce_damage_min=0,bounce_damage_max=0,explosion_damage_min=0,explosion_damage_max=0,damage=0,cooldown=1}
    end
    local E={}
    function E:get_template(n)
      if current[n]then return current[n]end
      skipped[n]=true;current[n]=inert();return current[n]
    end
    function E:set_template(n,v)current[n]=v end
    function E:filter_templates(component)
      local out={};for n,t in pairs(current)do if original[n] and t[component]then out[#out+1]=t end end;return out
    end
    package.loaded.entity_db=E
    local UP=require("kr1.upgrades")
    local bfg_scripts={}
    if reference_level then
      local text=assert(read(root.."/kr1/tower_scripts.lua"):match("scripts.tower_bfg = (.-)\nscripts.lava_dwaarp ="))
      local chunk=assert(loadstring("scripts.tower_bfg = "..text))
      setfenv(chunk,setmetatable({scripts=bfg_scripts},{__index=_G}));chunk()
    end
    local function projection(templates)
      local out={}
      for n in pairs(original)do
        local t=templates[n];local p={}
        if t.tower then p.price=t.tower.price end
        if t.attacks then
          p.range=t.attacks.range
          if reference_level then
            p.attacks=table.deepclone(t.attacks)
            p.attacks.order=nil -- Runtime-computed priority is checked by behavior fixtures.
          end
        end
        if t.barrack then p.rally_range=t.barrack.rally_range end
        if reference_level and t.powers then p.powers=table.deepclone(t.powers)end
        if t.health then p.health={hp_max=t.health.hp_max,armor=t.health.armor,magic_armor=t.health.magic_armor,dead_lifetime=t.health.dead_lifetime,damage_factor=t.health.damage_factor,spiked_armor=t.health.spiked_armor}end
        if t.bullet then p.bullet={damage_min=t.bullet.damage_min,damage_max=t.bullet.damage_max,reduce_armor=t.bullet.reduce_armor,mods=t.bullet.mods,mod=t.bullet.mod,damage_radius=t.bullet.damage_radius}end
        if t.dps then p.dps={damage_min=t.dps.damage_min,damage_max=t.dps.damage_max}end
        if t.aura and (n=="power_scorched_earth" or n=="power_scorched_water")then p.aura={damage_min=t.aura.damage_min,damage_max=t.aura.damage_max,duration=t.aura.duration}end
        if n=="power_fireball"then p.scorch_earth=t.scorch_earth end
        if n=="power_fireball_control"then p.control={cooldown=t.cooldown,fireball_count=t.fireball_count,cataclysm_count=t.cataclysm_count}end
        if n=="power_reinforcements_control"then p.control={cooldown=t.cooldown,duration=t.duration}end
        if next(p)then out[n]=p end
      end
      return out
    end
    local cases={{name="zero",levels={},limit=6}}
    for _,branch in ipairs(reference_level and {"barracks","engineers"} or UP.display_order)do for rank=1,6 do cases[#cases+1]={name=branch.."/"..rank,levels={[branch]=rank},limit=6}end end
    for _,limit in ipairs(reference_level and {6,5,0} or {6,4,0})do
      local levels={};for _,key in ipairs(UP.display_order)do levels[key]=6 end
      cases[#cases+1]={name="all/"..limit,levels=levels,limit=limit}
    end
    local result={source=json.decode(read(project.."/data/campaign_content.json")).source,cases={},reference_level=reference_level}
    for _,case in ipairs(cases)do
      current=table.deepclone(original)
      current.power_fireball_control.user_power={level=0};current.power_thunder_control={user_power={}}
      UP.levels={};for _,key in ipairs(UP.display_order)do UP.levels[key]=case.levels[key]or 0 end
      case.levels=table.deepclone(UP.levels)
      UP.max_level=case.limit;UP:set_list_id("1");UP:patch_templates(case.limit)
      case.templates=projection(current);case.reinforcement=current.re_current and current.re_current.template_name or "re_farmer"
      if reference_level and original.tower_bfg then
        case.bfg_attacks={}
        local tower=table.deepclone(current.tower_bfg)
        for rank=1,3 do
          tower.powers.missile.level=rank;tower.powers.cluster.level=rank
          bfg_scripts.tower_bfg.on_power_upgrade_missile(tower,"missile",tower.powers.missile)
          bfg_scripts.tower_bfg.on_power_upgrade_cluster(tower,"cluster",tower.powers.cluster)
          local missile,cluster=tower.attacks.list[2],tower.attacks.list[3]
          case.bfg_attacks[rank]={range=missile.range,missile_cooldown=missile.cooldown,
            mixed_cooldown=missile.cooldown_mixed,cluster_cooldown=cluster.cooldown}
        end
      end
      result.cases[#result.cases+1]=case
    end
    result.unpublished_inert_targets={};for n in pairs(skipped)do result.unpublished_inert_targets[#result.unpublished_inert_targets+1]=n end;table.sort(result.unpublished_inert_targets)
    if not reference_level then
      result.behaviors=assert(loadfile(project.."/tools/upgrade_reference/behavior.lua"))()(root,project,original,UP)
      result.behaviors.elf_missile=assert(loadfile(project.."/tools/upgrade_reference/elf_precision.lua"))()(root,original,UP)
    end
    local f=assert(io.open(os.getenv("DOVE_UPGRADE_REFERENCE_OUTPUT") or project.."/tests/fixtures/dove_upgrades_source.json","wb"));f:write(json.encode(result));f:close()
  end,debug.traceback)
  if not ok then local f=assert(io.open(assert(os.getenv("DOVE_PROJECT")).."/output/upgrade_reference.error","wb"));f:write(err);f:close();io.stderr:write(err,"\n")end
  love.event.quit(ok and 0 or 1)
end
