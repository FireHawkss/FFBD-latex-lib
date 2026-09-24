-- Run with: texlua tests/run_placement.lua
local model=dofile("tikzffbd-model.lua")
local analysis=dofile("tikzffbd-analysis.lua")
local normalize=dofile("tikzffbd-constraints.lua")
local planner=dofile("tikzffbd-planner.lua")
local placement=dofile("tikzffbd-placement.lua")
local count=0
local function check(ok,msg) assert(ok,msg);count=count+1 end
local function fixture(name,direction)
  local b=model.new{environment_id=name,options={direction=direction or "right",max_columns=8}}
  local metrics={environment_id=name,by_text_ref={},by_node_id={},
    by_annotation_id={},by_structure_id={},style_clearances={}}
  local frame={environment_id=name,direction=direction or "right",scale=1,
    content_width_sp=2000,content_height_sp=2000,page_width_sp=2000,page_height_sp=2000}
  local function node(id,w,h)
    b:add_function{id=id,text_ref="@text/"..id}
    metrics.by_node_id[id]={width_sp=w or 100,height_sp=h or 80}
  end
  return b,metrics,frame,node
end
local function run(spec,metrics,frame)
  for _,n in ipairs(spec.nodes) do
    if not metrics.by_node_id[n.id] then
      metrics.by_node_id[n.id]={width_sp=40,height_sp=40}
    end
  end
  local cs=assert(normalize.normalize(spec,frame))
  local plans,diagnostics=planner.plan(analysis.analyze(spec),metrics,cs,frame)
  assert(plans,diagnostics and diagnostics[1] and diagnostics[1].message)
  local g,err=placement.place(plans[1],spec,metrics,cs)
  check(g~=nil,err and err.message)
  return g,plans[1],cs
end
local function no_overlap(g)
  local ids={}
  for id in pairs(g.node_rects_by_id) do ids[#ids+1]=id end
  table.sort(ids)
  for i=1,#ids do for j=i+1,#ids do
    local a,b=g.node_rects_by_id[ids[i]],g.node_rects_by_id[ids[j]]
    check(not (a.x_sp<b.x_sp+b.width_sp and b.x_sp<a.x_sp+a.width_sp
      and a.y_sp<b.y_sp+b.height_sp and b.y_sp<a.y_sp+a.height_sp),"no block overlap")
  end end
end
local b,m,f,node=fixture("chain")
for i=1,8 do
  local id="n"..i;node(id,100+(i%2)*20,80)
  if i>1 then b:add_flow{source="n"..(i-1),target=id} end
end
local spec=assert(b:seal())
local g,p,cs=run(spec,m,f)
no_overlap(g)
for _,axis in ipairs(g.row_axes) do
  local ids=p.pages[axis.page_index].rows[axis.row_index].ordered_node_ids
  for i=2,#ids do
    local a,c=g.node_rects_by_id[ids[i-1]],g.node_rects_by_id[ids[i]]
    check(a.y_sp+a.height_sp/2==c.y_sp+c.height_sp/2,"chain centers aligned")
    check(a.x_sp+a.width_sp<=c.x_sp,"chain advances")
  end
end
check(g.spacing_stats.crossings_after==0,"chain has no crossings")
local again=assert(placement.place(p,spec,m,cs))
for id,r in pairs(g.node_rects_by_id) do
  local q=again.node_rects_by_id[id]
  check(r.x_sp==q.x_sp and r.y_sp==q.y_sp and r.width_sp==q.width_sp
    and r.height_sp==q.height_sp,"repeat coordinates")
end
local wrap_spec=model.inspect(spec)
local wrap_frame={environment_id=f.environment_id,direction="right",scale=1,
  content_width_sp=500,content_height_sp=2000,page_width_sp=500,page_height_sp=2000}
local wrapped,wrapped_plan=run(wrap_spec,m,wrap_frame)
check(#wrapped.row_axes>=2 and wrapped.row_axes[2].direction_sign==-1,
  "rightward wrap sign")
local second=wrapped_plan.pages[1].rows[2].ordered_node_ids
check(wrapped.node_rects_by_id[second[1]].x_sp>
  wrapped.node_rects_by_id[second[2]].x_sp,"second row moves left")
for _,port in ipairs(wrapped.provisional_ports) do
  if port.source_id==second[1] and port.target_id==second[2] then
    check(port.source_side=="left" and port.target_side=="right",
      "rightward reverse ports")
  end
end
local tight={}
for i,c in ipairs(cs) do tight[i]=c end
tight[1]={id="@constraint/tight",kind="max-columns",target_ids={},value=1,
  strength="hard",source={command="test",declaration_index=1}}
local rejected,why=placement.place(p,spec,m,tight)
check(rejected==nil and why.code=="max-columns-exceeded","hard plan violation rejected")

b,m,f,node=fixture("branch")
for _,id in ipairs({"s","a","b","c","t"}) do node(id) end
b:add_branch{source_id="s",arms={"c","a","b"}}
b:add_join{arms={"c","a","b"},target_id="t"}
spec=assert(b:seal())
g,p,cs=run(spec,m,f)
no_overlap(g)
local ra,rb,rc=g.node_rects_by_id.a,g.node_rects_by_id.b,g.node_rects_by_id.c
check(rc.y_sp<ra.y_sp and ra.y_sp<rb.y_sp,"user branch arm order")
check(ra.y_sp-rc.y_sp==rb.y_sp-ra.y_sp,"regular branch lanes")
check(g.node_rects_by_id.s.y_sp+40==g.node_rects_by_id.t.y_sp+40,
  "split and join aligned")
for _,r in pairs(g.node_rects_by_id) do
  check(r.x_sp>=0 and r.y_sp>=0,"node stays in positive page coordinates")
end

-- A generic layered graph has a strict crossing improvement by swapping c,d.
b,m,f,node=fixture("crossing")
for _,id in ipairs({"s","a","b","c","d","t"}) do node(id) end
for _,edge in ipairs({{"s","a"},{"s","b"},{"a","d"},{"b","c"},
    {"c","t"},{"d","t"}}) do b:add_flow{source=edge[1],target=edge[2]} end
spec=assert(b:seal())
g=run(spec,m,f)
check(g.spacing_stats.crossings_after<g.spacing_stats.crossings_before,
  "local swap reduces crossings")
check(g.spacing_stats.gap_variance_sp2==0,"shared spacing has zero variance")
local crossing_before,crossing_after=g.spacing_stats.crossings_before,
  g.spacing_stats.crossings_after

-- Downward rows alternate primary direction and their candidates follow it.
b,m,f,node=fixture("down","down")
for i=1,9 do
  local id="v"..i;node(id)
  if i>1 then b:add_flow{source="v"..(i-1),target=id} end
end
spec=assert(b:seal())
f.content_height_sp=360
g,p,cs=run(spec,m,f)
check(#g.row_axes>=2 and g.row_axes[2].direction_sign==-1,"downward wrap sign")
local first_second=p.pages[1].rows[2].ordered_node_ids[1]
local next_second=p.pages[1].rows[2].ordered_node_ids[2]
check(g.node_rects_by_id[first_second].y_sp>g.node_rects_by_id[next_second].y_sp,
  "second band goes upward")
for _,port in ipairs(g.provisional_ports) do
  if port.source_id==first_second and port.target_id==next_second then
    check(port.source_side=="top" and port.target_side=="bottom","downward reverse ports")
  end
end

b,m,f,node=fixture("multi")
for i=1,12 do
  local id="m"..i;node(id)
  if i>1 then b:add_flow{source="m"..(i-1),target=id} end
end
spec=assert(b:seal())
spec=model.inspect(spec);spec.options.multipage=true
f.content_width_sp=550;f.page_width_sp=550
f.content_height_sp=180;f.page_height_sp=180
g,p,cs=run(spec,m,f)
check(#p.pages>1,"multipage fixture")
for i=1,#p.pages do
  check(g.page_extents_by_index[i]~=nil,"page extent exported")
  check(p.pages[i].rows[1].direction_sign==1,"page direction resets")
end
local small={environment_id=p.environment_id,pages=p.pages,estimated_costs={
  route_gap_sp=p.estimated_costs.route_gap_sp,row_gap_sp=p.estimated_costs.row_gap_sp,
  usable_primary_sp=100,usable_cross_sp=100}}
local rejected_page,page_issue=placement.place(small,spec,m,cs)
check(rejected_page==nil and page_issue.code=="page-fit-violated",
  "hard page footprint conflict")

b,m,f,node=fixture("large")
for i=1,64 do
  local id="l"..i;node(id)
  if i>1 then b:add_flow{source="l"..(i-1),target=id} end
end
spec=assert(b:seal())
g,p,cs=run(spec,m,f)
check(#g.row_axes>=8,"64-node chain assigned in bounded rows")
check(g.spacing_stats.crossings_after==0,"64-node chain remains crossing free")

-- Provisional group rectangle contains its measured members.
b,m,f,node=fixture("group")
for i=1,3 do node("g"..i); if i>1 then b:add_flow{source="g"..(i-1),target="g"..i} end end
b:add_structure{id="box",member_ids={"g1","g2"},input_member_ids={"g1"},output_member_ids={"g2"}}
spec=assert(b:seal())
m.by_structure_id.box={header_width_sp=220,header_height_sp=30,info_width_sp=200}
g,p,cs=run(spec,m,f)
local box=g.group_rects_by_id.box
check(box~=nil,"group rectangle exists")
check(box.width_sp>=220 and box.y_sp>=0 and
  g.node_rects_by_id.g1.y_sp-box.y_sp>=30,"group header footprint included")
check(#g.group_boundary_ports==1 and g.group_boundary_ports[1].member_id=="g2"
  and g.group_boundary_ports[1].role=="out","declared boundary candidate")
for _,id in ipairs({"g1","g2"}) do
  local r=g.node_rects_by_id[id]
  check(box.x_sp<r.x_sp and box.y_sp<r.y_sp and
    box.x_sp+box.width_sp>r.x_sp+r.width_sp and
    box.y_sp+box.height_sp>r.y_sp+r.height_sp,"group contains member")
end
local intrusive=model.inspect(spec)
intrusive.structures[1].member_ids={"g1","g3"}
intrusive.structures[1].output_member_ids={"g3"}
local bad_group,group_issue=placement.place(p,intrusive,m,cs)
check(bad_group==nil and group_issue.code=="group-intrusion",
  "provisional group rejects nonmember intrusion")

-- Deliberately impossible plan dimensions report a conflict.
local bad={environment_id=p.environment_id,pages=p.pages,estimated_costs={route_gap_sp=30,row_gap_sp=40}}
bad.pages[1].rows[1].estimated_primary_sp=1
local result,err=placement.place(bad,spec,m,cs)
check(result==nil and err.code=="row-footprint-exceeded","hard footprint conflict")

local arrays={row_axes=true,reserved_channels=true,provisional_ports=true,layers=true}
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
  table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
  for _,k in ipairs(keys) do
    out[#out+1]=encode(tostring(k))..":"..encode(value[k],k)
  end
  return "{"..table.concat(out,",").."}"
end
local trace={contract_version=1,environment_id="group",objects={Geometry=g}}
local file=assert(io.open("/tmp/tikzffbd-placement-geometry.json","w"))
file:write(encode(trace),"\n");file:close()

print("placement: "..count.." assertions passed; crossing "..crossing_before..
  " -> "..crossing_after.."; generic gap variance 0 sp^2")
