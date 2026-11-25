local source=assert(os.getenv("DOVE_SOURCE_DIR"))
package.path=source.."/?.lua;"..package.path
function love.load()
  local ok,err=xpcall(function()
    local strings=assert(loadfile(source.."/_assets/kr1-desktop/strings/zh-Hans.lua"))()
    _G._=function(key)return strings[key] or key end
    local f=assert(io.open(assert(os.getenv("DOVE_EXPORT_PATH")),"wb"))
    f:write(require("lib.json").encode({strings=strings}));f:close()
  end,debug.traceback)
  if not ok then print(err) end
  love.event.quit(ok and 0 or 1)
end
