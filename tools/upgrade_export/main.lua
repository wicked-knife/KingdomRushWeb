-- Metadata only: no source saves, plugins or game bootstrap are loaded.
function love.load()
  local ok,err=xpcall(function()
    local root=assert(os.getenv("DOVE_SOURCE_DIR"))
    package.path=root.."/?.lua;"..root.."/all/?.lua;"..root.."/kr1/?.lua;"..package.path
    require("lib.klua.table");require("all.constants")
    package.loaded.entity_db={}
    local UP=require("kr1.upgrades")
    local GS=require("kr1.game_settings")
    local function clean(v)
      if type(v)=="function" then return nil end
      if type(v)~="table" then return v end
      local out={};for k,x in pairs(v)do out[k]=clean(x)end;return out
    end
    local groups={}
    for _,key in ipairs({"archer_towers","barrack_towers","mage_towers","engineer_towers","arrows","bolts","mage_tower_bolts","engineer_bombs","soldiers","towers_with_barrack","engineer_advanced_tower"})do groups[key]=clean(UP[key])end
    local data={list_id="1",classes=UP.display_order,techs=clean(UP.list["1"].techs),groups=groups,max_level=GS.max_upgrade_level}
    local f=assert(io.open(assert(os.getenv("DOVE_EXPORT_PATH")),"wb"));f:write(require("lib.json").encode(data));f:close()
  end,debug.traceback)
  if not ok then local f=assert(io.open(assert(os.getenv("DOVE_EXPORT_PATH"))..".error","wb"));f:write(err);f:close()end
  love.event.quit(ok and 0 or 1)
end
