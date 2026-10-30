-- Execute the actual missile coroutine and damage helper. Archer precision is
-- deliberately enabled with a successful RNG draw: elf missiles never roll it.
return function(root, original, UP)
  local V = require("lib.klua.vector")
  local bit = require("bit")
  local function read(path)
    local f = assert(io.open(root.."/"..path, "rb"))
    local text = f:read("*a"); f:close(); return text
  end
  local function compile(text, name, env)
    local body = assert(text:match("function "..name:gsub("%.", "%%.").."%((.-)\nend"), name)
    local chunk = assert(loadstring("function "..name.."("..body.."\nend"))
    setfenv(chunk, env); chunk()
  end
  local scripts = {arrow_missile = {}}
  local SU = {unit_dodges = function() return false end}
  local rows = {}
  local E = {
    assign_damage = function(kind, value) return {damage_type = kind, value = value} end,
    create_entity = function() return {pos = V.v(0,0), modifier = {}, render = {sprites = {{}}}, particle_system = {}} end
  }
  local mathenv = setmetatable({random = function(a,b) return a and math.floor((a+b)/2) or 0.05 end}, {__index=math})
  local env = setmetatable({scripts=scripts, SU=SU, UP=UP, E=E, V=V, math=mathenv, FPS=30, band=bit.band,
    U={frandom=function(a,b) return (a+b)/2 end},
    simulation={queue_remove_entity=function() end, queue_insert_entity=function() end},
    queue_damage=function(_,damage) rows[#rows+1]=damage end}, {__index=_G})
  compile(read("all/scripts.lua"), "scripts.arrow_missile.update", env)
  compile(read("all/script_utils.lua"), "SU.create_bullet_damage", env)
  local result = {}
  for _,archers in ipairs({4,5,6}) do
    UP:set_levels({archers=archers}); UP.max_level=6
    for level=1,3 do
      local target={id=2,pos=V.v(440,540),health={dead=false},unit={hit_offset=V.v(0,0)},vis={bans=0}}
      local store={entities={[2]=target},tick_ts=0,tick_length=1/30}
      local arrow=table.deepclone(original.arrow_elf_cripple)
      arrow.id=1; arrow.pos=V.v(440,540); arrow.render={sprites={{}}}
      arrow.bullet.from=V.v(440,540); arrow.bullet.to=V.v(440,540); arrow.bullet.speed=V.v(0,0)
      arrow.bullet.target_id=2; arrow.bullet.level=level; arrow.bullet.ts=0; arrow.bullet.flight_time=0
      arrow.bullet.particles_name=nil; arrow.bullet.hit_blood_fx=nil
      rows={}
      local co=coroutine.create(function() scripts.arrow_missile.update(arrow,store) end)
      assert(coroutine.resume(co)); assert(coroutine.status(co)=="dead")
      result[#result+1]={archers=archers,level=level,damage=assert(rows[1]).value,
        critical=arrow.bullet.pop and arrow.bullet.pop[1]=="pop_crit" or false}
    end
  end
  return result
end
