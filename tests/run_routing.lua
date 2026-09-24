-- Run with: texlua tests/run_routing.lua
local model=dofile("tikzffbd-model.lua")
local router=dofile("tikzffbd-routing.lua")
local analysis=dofile("tikzffbd-analysis.lua")
local constraints=dofile("tikzffbd-constraints.lua")
local planner=dofile("tikzffbd-planner.lua")
local placement=dofile("tikzffbd-placement.lua")
local n=0
local function check(x,m) assert(x,m);n=n+1 end
local function geometry(env,rects,ports,rows,groups)
  local g={environment_id=env,node_rects_by_id=rects,group_rects_by_id=groups or {},
    group_rect_page_by_id={},row_axes=rows or {},provisional_ports=ports,
    spacing_stats={route_gap_sp=30}}
  for id in pairs(groups or {}) do g.group_rect_page_by_id[id]=1 end
  return g
end
local function build(env,nodes,flows,structures,direction)
  local b=model.new{environment_id=env,options={direction=direction or "right"}}
  for _,id in ipairs(nodes) do b:add_function{id=id,text_ref="@text/"..id} end
  for _,f in ipairs(flows) do
    if f.kind=="feedback" then b:add_feedback{source=f[1],target=f[2]}
    else b:add_flow{source=f[1],target=f[2]} end
  end
  for _,s in ipairs(structures or {}) do b:add_structure(s) end
  return assert(b:seal())
end
local function ports(spec,by_pair)
  by_pair=by_pair or {}
  local out={}
  for _,f in ipairs(spec.flows) do
    local pair=f.source..":"..f.target
    local sides=by_pair[pair] or {"right","left"}
    out[#out+1]={flow_id=f.id,source_id=f.source,target_id=f.target,
      source_side=sides[1],target_side=sides[2],source_page=1,target_page=1}
  end
  return out
end
local function assert_paths(routes,spec,rects)
  for _,f in ipairs(spec.flows) do
    local path=assert(routes.paths_by_flow_id[f.id])
    check(#path.points>=2,"path has points")
    check(routes.ports_by_id[path.source_port_id]~=nil,"source port resolved")
    check(routes.ports_by_id[path.target_port_id]~=nil,"target port resolved")
    for i=2,#path.points do
      local a,b=path.points[i-1],path.points[i]
      check((a.x_sp==b.x_sp)~=(a.y_sp==b.y_sp),"nonzero orthogonal segment")
      for id,r in pairs(rects) do
        if id~=f.source and id~=f.target then
          local inside
          if a.x_sp==b.x_sp then
            inside=a.x_sp>r.x_sp and a.x_sp<r.x_sp+r.width_sp and
              math.max(a.y_sp,b.y_sp)>r.y_sp and math.min(a.y_sp,b.y_sp)<r.y_sp+r.height_sp
          else
            inside=a.y_sp>r.y_sp and a.y_sp<r.y_sp+r.height_sp and
              math.max(a.x_sp,b.x_sp)>r.x_sp and math.min(a.x_sp,b.x_sp)<r.x_sp+r.width_sp
          end
          check(not inside,"no foreign block interior crossed")
        end
      end
    end
  end
end
local spec=build("chain",{"a","b"},{{"a","b"}})
local rects={a={x_sp=20,y_sp=30,width_sp=40,height_sp=30},
  b={x_sp=140,y_sp=30,width_sp=40,height_sp=30}}
local g=geometry("chain",rects,ports(spec),{{page_index=1,row_index=1,direction_sign=1,
  layers={{"a"},{"b"}}}})
local routed,issue=router.route(g,spec)
check(routed~=nil,issue and issue.message)
assert_paths(routed,spec,rects)
check(routed.costs.length_sp==80,"straight length")
check(routed.costs.work_used<=routed.costs.work_budget,"work bounded")
local sealed,obstruction=router.route(g,spec,{{id="note",page_index=1,
  rect={x_sp=61,y_sp=40,width_sp=20,height_sp=10}}})
check(sealed==nil and obstruction.code=="obstructed-corridor",
  "occupied annotation at mandatory port stub diagnoses conflict: "..tostring(obstruction and obstruction.code))
local again=assert(router.route(g,spec))
check(routed.costs.length_sp==again.costs.length_sp,"repeat cost")
for _,f in ipairs(spec.flows) do
  local a,b=routed.paths_by_flow_id[f.id].points,again.paths_by_flow_id[f.id].points
  for i=1,#a do check(a[i].x_sp==b[i].x_sp and a[i].y_sp==b[i].y_sp,"repeat points") end
end
-- A measured block forces a detour using the local visibility graph.
spec=build("detour",{"a","b","c"},{{"a","c"}})
rects={a={x_sp=20,y_sp=30,width_sp=40,height_sp=30},
  b={x_sp=95,y_sp=20,width_sp=40,height_sp=50},
  c={x_sp=170,y_sp=30,width_sp=40,height_sp=30}}
g=geometry("detour",rects,ports(spec),{{page_index=1,row_index=1,direction_sign=1,
  layers={{"a"},{"b"},{"c"}}}})
routed,issue=router.route(g,spec)
check(routed~=nil,issue and issue.message)
assert_paths(routed,spec,rects)
check(routed.costs.bends>=2,"obstacle detour has bends")
-- Reverse row ports do not reverse their first or last stub.
spec=build("wrap",{"a","b"},{{"a","b"}})
rects={a={x_sp=140,y_sp=30,width_sp=40,height_sp=30},
  b={x_sp=20,y_sp=30,width_sp=40,height_sp=30}}
g=geometry("wrap",rects,ports(spec,{["a:b"]={"left","right"}}),
  {{page_index=1,row_index=2,direction_sign=-1,layers={{"a"},{"b"}}}})
routed=assert(router.route(g,spec))
assert_paths(routed,spec,rects)
local path=routed.paths_by_flow_id[spec.flows[1].id].points
check(path[2].x_sp<path[1].x_sp,"reverse row exits left")
spec=build("down-routing",{"top","bottom"},{{"top","bottom"}},nil,"down")
rects={top={x_sp=30,y_sp=20,width_sp=40,height_sp=30},
  bottom={x_sp=30,y_sp=130,width_sp=40,height_sp=30}}
g=geometry("down-routing",rects,ports(spec,{["top:bottom"]={"bottom","top"}}),
  {{page_index=1,row_index=1,direction_sign=1,layers={{"top"},{"bottom"}}}})
routed=assert(router.route(g,spec))
assert_paths(routed,spec,rects)
path=routed.paths_by_flow_id[spec.flows[1].id].points
check(path[2].y_sp>path[1].y_sp,"downward stub exits bottom")
-- Structure crossings require declared boundary members.
spec=build("group",{"a","b"},{{"a","b"}},
  {{id="box",member_ids={"a"},input_member_ids={"a"},output_member_ids={"a"}}})
rects={a={x_sp=40,y_sp=60,width_sp=40,height_sp=30},
  b={x_sp=180,y_sp=60,width_sp=40,height_sp=30}}
g=geometry("group",rects,ports(spec),{{page_index=1,row_index=1,direction_sign=1,
  layers={{"a"},{"b"}}}},
  {box={x_sp=20,y_sp=40,width_sp=90,height_sp=70}})
routed,issue=router.route(g,spec)
check(routed~=nil,issue and issue.message)
check(#routed.paths_by_flow_id[spec.flows[1].id].boundary_port_ids==1,
  "declared structure port")
spec=model.inspect(spec)
spec.structures[1].output_member_ids={}
local rejected,why=router.route(g,spec)
check(rejected==nil and why.code=="undeclared-structure-crossing",
  "undeclared structure crossing diagnosed")
-- Bounded conflict when an annotation closes the only initial stub.
local blocked={id="note",page_index=1,
  rect={x_sp=80,y_sp=60,width_sp=50,height_sp=30}}
local result,err=router.route(g,spec,{blocked})
check(result==nil and err.code=="undeclared-structure-crossing",
  "hard semantic port rule precedes geometric search")
-- Actual planner/placement output carries the continuation contract.
local b=model.new{environment_id="pages",options={direction="right",multipage=true,
  max_columns=3}}
local metrics={environment_id="pages",by_text_ref={},by_node_id={},
  by_annotation_id={},by_structure_id={},style_clearances={}}
for i=1,8 do
  b:add_function{id="p"..i,text_ref="@text/p"..i}
  metrics.by_node_id["p"..i]={width_sp=100,height_sp=45}
  if i>1 then b:add_flow{source="p"..(i-1),target="p"..i} end
end
local pages_spec=assert(b:seal())
local frame={environment_id="pages",direction="right",scale=1,
  content_width_sp=400,content_height_sp=150,
  page_width_sp=400,page_height_sp=150}
local cs=assert(constraints.normalize(pages_spec,frame))
local plans=assert(planner.plan(analysis.analyze(pages_spec),metrics,cs,frame))
local pg=assert(placement.place(plans[1],pages_spec,metrics,cs))
check(#plans[1].pages>1,"planner creates pages")
local page_routes,page_err=router.route(pg,pages_spec)
check(page_routes~=nil,page_err and page_err.message)
for _,f in ipairs(pages_spec.flows) do
  local p=page_routes.paths_by_flow_id[f.id]
  check(p~=nil,"multipage flow routed")
  for _,segment in ipairs(p.page_segments or {p}) do
    for i=2,#segment.points do
      local a,c=segment.points[i-1],segment.points[i]
      check((a.x_sp==c.x_sp)~=(a.y_sp==c.y_sp),"continuation leg orthogonal")
    end
  end
  if p.page_segments then
    for i=1,#p.page_segments-1 do
      local outbound=p.page_segments[i].target_marker_id
      local inbound=p.page_segments[i+1].source_marker_id
      local reciprocal=false
      for _,mark in ipairs(pg.continuation_markers_by_page[p.page_segments[i].page_index]) do
        if mark.id==outbound and mark.counterpart_id==inbound then
          reciprocal=true
        end
      end
      check(reciprocal,"continuation legs retain reciprocal marker IDs")
    end
  end
end
local crossing_flow
for _,f in ipairs(pages_spec.flows) do
  local p=page_routes.paths_by_flow_id[f.id]
  if p.page_segments then crossing_flow=f;break end
end
check(crossing_flow~=nil,"cross-page flow identified")
local structured=model.inspect(pages_spec)
structured.structures[#structured.structures+1]={id="pagebox",index=100,
  member_ids={crossing_flow.source},input_member_ids={crossing_flow.source},
  output_member_ids={crossing_flow.source},style="shaded"}
local owner
for _,candidate in ipairs(pg.provisional_ports) do
  if candidate.flow_id==crossing_flow.id then owner=candidate.source_page end
end
local source_rect=pg.node_rects_by_id[crossing_flow.source]
pg.group_rects_by_id.pagebox={x_sp=source_rect.x_sp-8,
  y_sp=source_rect.y_sp-8,width_sp=source_rect.width_sp+16,
  height_sp=source_rect.height_sp+16}
pg.group_rect_page_by_id.pagebox=owner
local structured_routes,structured_error=router.route(pg,structured)
check(structured_routes~=nil,structured_error and structured_error.message)
check(#structured_routes.paths_by_flow_id[crossing_flow.id].boundary_port_ids==1,
  "cross-page structure flow uses a declared boundary port")
-- A branch fixture exercises connector buses and feedback together.
b=model.new{environment_id="branch-routing",options={direction="right",max_columns=12}}
metrics={environment_id="branch-routing",by_text_ref={},by_node_id={},
  by_annotation_id={},by_structure_id={},style_clearances={}}
for _,id in ipairs({"start","a","b","c","finish"}) do
  b:add_function{id=id,text_ref="@text/"..id}
  metrics.by_node_id[id]={width_sp=70,height_sp=35}
end
local split=b:add_branch{source_id="start",arms={"a","b","c"}}
local join=b:add_join{arms={"a","b","c"},target_id="finish"}
metrics.by_node_id[split]={width_sp=30,height_sp=30}
metrics.by_node_id[join]={width_sp=30,height_sp=30}
b:add_feedback{source="finish",target="start"}
local branch_spec=assert(b:seal())
frame={environment_id="branch-routing",direction="right",scale=1,
  content_width_sp=1200,content_height_sp=1000,
  page_width_sp=1200,page_height_sp=1000}
cs=assert(constraints.normalize(branch_spec,frame))
plans=assert(planner.plan(analysis.analyze(branch_spec),metrics,cs,frame))
local branch_g=assert(placement.place(plans[1],branch_spec,metrics,cs))
local branch_routes,branch_err=router.route(branch_g,branch_spec)
check(branch_routes~=nil,branch_err and branch_err.message)
assert_paths(branch_routes,branch_spec,branch_g.node_rects_by_id)
check(branch_routes.costs.work_used<=branch_routes.costs.work_budget,
  "branch work bounded")
check(#branch_routes.shared_trunks>0,"split/join route shares a trunk")
check(branch_routes.costs.crossings==0,"branch fixture avoids crossings")
check(#branch_routes.feedback_lanes==1,"feedback owns an outer lane")
-- Dense bounded fixture: 30 blocks and one long feedback link.
b=model.new{environment_id="dense-routing",options={direction="right",max_columns=6}}
metrics={environment_id="dense-routing",by_text_ref={},by_node_id={},
  by_annotation_id={},by_structure_id={},style_clearances={}}
for i=1,30 do
  b:add_function{id="d"..i,text_ref="@text/d"..i}
  metrics.by_node_id["d"..i]={width_sp=55,height_sp=30}
  if i>1 then b:add_flow{source="d"..(i-1),target="d"..i} end
end
b:add_feedback{source="d30",target="d1"}
local dense_spec=assert(b:seal())
frame={environment_id="dense-routing",direction="right",scale=1,
  content_width_sp=580,content_height_sp=1500,
  page_width_sp=580,page_height_sp=1500}
cs=assert(constraints.normalize(dense_spec,frame))
plans=assert(planner.plan(analysis.analyze(dense_spec),metrics,cs,frame))
local dense_g=assert(placement.place(plans[1],dense_spec,metrics,cs))
local started=os.clock()
local dense_routes,dense_err=router.route(dense_g,dense_spec)
local elapsed=os.clock()-started
check(dense_routes~=nil,dense_err and dense_err.message)
check(dense_routes.costs.work_used<=dense_routes.costs.work_budget,
  "dense search stays in budget")
check(#dense_spec.flows==30,"dense flow count")
print(string.format("dense routing: %.4f seconds, %d/%d work units",
  elapsed,dense_routes.costs.work_used,dense_routes.costs.work_budget))
local arrays={shared_trunks=true,crossings=true,congestion=true,conflicts=true,
  points=true,boundary_port_ids=true,page_segments=true,flow_ids=true,
  object_ids=true,constraint_ids=true}
local function encode(value,key)
  if type(value)=="string" then return string.format("%q",value) end
  if type(value)~="table" then return tostring(value) end
  local out={}
  if arrays[key] or #value>0 then
    for _,v in ipairs(value) do out[#out+1]=encode(v) end
    return "["..table.concat(out,",").."]"
  end
  local keys={}
  for k in pairs(value) do keys[#keys+1]=k end
  table.sort(keys)
  for _,k in ipairs(keys) do
    out[#out+1]=encode(k)..":"..encode(value[k],k)
  end
  return "{"..table.concat(out,",").."}"
end
local file=assert(io.open("/tmp/tikzffbd-routing-routes.json","w"))
file:write(encode({contract_version=1,environment_id="branch-routing",
  objects={Routes=branch_routes}}),"\n")
file:close()
print("routing: "..n.." assertions passed")
