-- Feature adapters evaluate frozen source templates without running gameplay.
local adapters = {}
  adapters.healer = function(ctx)
    local read,chunk = ctx.read,ctx.chunk
    local game = read("kr1/game_templates.lua")
    local a=assert(game:find('tt = RT("mod_shaman_heal",',1,true))
    local b=assert(game:find('\ntt = ',a+1,true))
    chunk("kr1/game_templates.lua","local tt;local scripts=require('game_scripts');"..game:sub(a,b-1))
  end
  adapters.ranger = function(ctx)
    local read,chunk = ctx.read,ctx.chunk
    local archers=read("kr1/archer_towers.lua")
    chunk("kr1/archer_towers.lua",archers:sub(1,assert(archers:find('local tower_crossbow = RT(',1,true))-1))
  end
  adapters.elf = function(ctx)
    local read,chunk = ctx.read,ctx.chunk
    local barracks=read("kr1/barrack_towers.lua")
    local header=barracks:sub(1,assert(barracks:find('tt = RT(',1,true))-1)
    local a=assert(barracks:find('tt = RT("tower_elf_holder")',1,true))
    local b=assert(barracks:find('tt = RT("tower_barrack_amazonas"',a,true))
    chunk("kr1/barrack_towers.lua",header..barracks:sub(a,b-1))
    local heroes=read("kr1/heroes.lua")
    local a=assert(heroes:find('tt = RT("ps_arrow_multishot_hero_alleria")',1,true))
    local b=assert(heroes:find('\ntt = ',a+1,true))
    chunk("kr1/heroes.lua","local tt;"..heroes:sub(a,b-1))
  end

return function(ctx)
  for _,feature in ipairs(ctx.features) do
    if adapters[feature] then adapters[feature](ctx) end
  end
end
