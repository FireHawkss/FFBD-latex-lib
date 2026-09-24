package.path="./?.lua;"..package.path
kpse.set_program_name("texlua")
package.path=assert(kpse.find_file("lualibs.lua")):match("^(.*[/\\])").."?.lua;"..package.path
require("lualibs")
require("lualibs-util-jsn")
local renderer=require("tikzffbd-renderer")
local count=0
local function check(v,message)
  count=count+1
  assert(v,message)
end
local function fixture(path)
  local f=assert(io.open(path,"rb"));local data=f:read("*a");f:close()
  return assert(utilities.json.tolua(data)).objects.Scene
end
for _,name in ipairs({"solved-chain","solved-multipage"}) do
  local scene=fixture("tests/fixtures/scenes/"..name..".json")
  local tex=renderer.render(scene,nil,{})
  local pages=0
  for _ in tex:gmatch("\\ffbdScenePageBegin") do pages=pages+1 end
  check(pages==#scene.pages,name.." page count")
  check(not tex:find("resizebox",1,true),"renderer must not shrink to width")
  for i,page in ipairs(scene.pages) do
    local b=page.bounding_rect
    check(tex:find("{"..b.x_sp.."}{"..b.y_sp.."}{"..b.width_sp.."}{"..b.height_sp.."}",1,true),
      name.." page "..i.." bounding rectangle")
    for _,path in pairs(page.flow_paths) do
      for _,p in ipairs(path.points) do
        check(tex:find("("..p.x_sp.."sp,"..p.y_sp.."sp)",1,true),"flow point preserved")
      end
    end
    for _,m in ipairs(page.continuation_markers) do
      check(tex:find(m.text_ref,1,true),"continuation ref preserved")
    end
  end
end
local scene=fixture("tests/fixtures/scenes/solved-chain.json")
scene.scale=.9
local tex=renderer.render(scene,nil,{})
check(tex:find("\\ffbdScenePageBegin{1}{0.9}",1,true),"explicit .9 scale")
scene.scale=1
local full=renderer.render(scene,nil,{})
check(full:gsub("PageBegin{1}{1}","PageBegin{1}{0.9}")==tex,
  "scale changes only the complete picture box")
local good,err=pcall(renderer.render,scene,{},{nodes={n1={text_ref="@text/missing"}}})
check(not good and err:find("missing text reference",1,true),"missing TeX ref diagnosed")
print("renderer: "..count.." assertions passed")
