-- Resolve colocated modules when TeX finds this package through TEXINPUTS.
-- LuaHBTeX's require uses a kpse searcher rather than package.path.
table.insert(package.searchers, 2, function(name)
  if name:match("^tikzffbd%-") then
    local path = kpse.find_file(name .. ".lua")
    if path then return function() return dofile(path) end, path end
  end
  return "\nno colocated tikzffbd module " .. name
end)
tikzffbd_bridge = dofile(assert(kpse.find_file("tikzffbd-bridge.lua")))
