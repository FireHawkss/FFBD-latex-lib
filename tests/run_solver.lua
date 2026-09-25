-- Run with: texlua tests/run_solver.lua
local model=require("tikzffbd-model")
local solver=require("tikzffbd-solver")
local quality=require("tikzffbd-quality")
local analysis=require("tikzffbd-analysis")
local constraints=require("tikzffbd-constraints")
local planner=require("tikzffbd-planner")
local n=0
local function check(x,msg) assert(x,msg);n=n+1 end
local function fixture(name,count,opts)
  opts=opts or {max_columns=5}
  local b=model.new{environment_id=name,options=opts}
  local m={environment_id=name,by_text_ref={},by_node_id={},by_annotation_id={},
    by_structure_id={},style_clearances={route_gap_sp=30,row_gap_sp=80}}
  for i=1,count do
    local id="n"..i
    b:add_function{id=id,text_ref="@text/"..id}
    m.by_node_id[id]={width_sp=100,height_sp=70}
    if i>1 then b:add_flow{source="n"..(i-1),target=id} end
  end
  local f={environment_id=name,direction=opts.direction or "right",scale=opts.scale or 1,
    content_width_sp=1200,content_height_sp=10000,page_width_sp=1200,page_height_sp=10000}
  return b,m,f
end
local b,m,f=fixture("base",8)
local spec=assert(b:seal())
local scene,issues=solver.solve(spec,m,f)
check(scene~=nil,issues and issues[1] and issues[1].message)
check(scene.quality.vector[1]==0,"valid quality")
check(scene.quality.candidates_evaluated<=scene.quality.search_budget,"bounded")
check(#scene.pages==1,"single page")
local repeat_scene=assert(solver.solve(spec,m,f))
for i=1,7 do check(scene.quality.vector[i]==repeat_scene.quality.vector[i],"repeat score") end
check(scene.pages[1].bounding_rect.x_sp==repeat_scene.pages[1].bounding_rect.x_sp,"repeat geometry")
b,m,f=fixture("down",8,{direction="down",max_columns=5,scale=2})
spec=assert(b:seal())
scene,issues=solver.solve(spec,m,f)
check(scene~=nil,issues and issues[1] and issues[1].message)
check(scene.scale==2,"explicit scale retained")
check(scene.plan.pages[1].rows[1].direction_sign==1,"downward primary row")

-- Explicit hard positions survive, while soft positions may change.
b,m,f=fixture("notes",2,{max_columns=5})
b:add_annotation{id="note",owner_id="n1",type_ref="@text/type",body_ref="@text/body",
  preferred_position="top-center"}
m.by_annotation_id.note={width_sp=50,height_sp=20}
spec=assert(b:seal())
scene,issues=solver.solve(spec,m,f)
check(scene~=nil,issues and issues[1] and issues[1].message)
check(scene.pages[1].annotations[1].position=="top-center","hard position")
local hard_note=scene.pages[1].annotations[1]
local top=hard_note.rect
check(top.y_sp+top.height_sp<=scene.pages[1].node_rects.n1.y_sp,"note clears owner")
local soft=model.inspect(spec)
soft.annotations[2]={id="note2",index=99,owner_id="n1",type_ref="@text/type",
  body_ref="@text/body",preferred_position="top-center",position_strength="soft"}
m.by_annotation_id.note2={width_sp=50,height_sp=20}
scene=assert(solver.solve(soft,m,f))
check(scene.pages[1].annotations[2].position~="top-center","soft position moves from occupied top")
local hard=model.inspect(soft)
hard.annotations[2].position_strength="hard"
scene,issues=solver.solve(hard,m,f)
check(scene==nil and issues[1].code=="annotation-position-conflict","hard blocked position diagnoses")
for _,position in ipairs({"top-left","top-center","top-right","left","right",
  "bottom-left","bottom-center","bottom-right"}) do
  b,m,f=fixture("position-"..position,2)
  b:add_annotation{id="note",owner_id="n1",type_ref="@text/type",body_ref="@text/body",
    preferred_position=position}
  m.by_annotation_id.note={width_sp=40,height_sp=20}
  spec=assert(b:seal())
  scene,issues=solver.solve(spec,m,f)
  check((scene and scene.pages[1].annotations[1].position==position) or
    (not scene and issues and issues[1].severity=="error"),"hard position holds or diagnoses")
end

-- A measured condition stays attached to its semantic flow and clear of blocks.
b,m,f=fixture("label",2)
-- Replace the builder's unlabeled flow with a labeled sealed copy.
spec=model.inspect(assert(b:seal()))
spec.flows[1].condition_ref="@text/condition"
m.by_text_ref["@text/condition"]={width_sp=30,height_sp=10,depth_sp=0}
scene,issues=solver.solve(spec,m,f)
check(scene~=nil,issues and issues[1] and issues[1].message)
check(scene.pages[1].edge_labels[1].flow_id==spec.flows[1].id,"label flow identity")
check(scene.pages[1].edge_labels[1].text_ref=="@text/condition","label text")
local huge=model.inspect(spec)
-- Keep both endpoints in one row: the label cannot be rescued by allocating
-- a huge inter-row gutter, which is now a valid measured-spacing alternative.
huge.structures={{id="pair",index=99,member_ids={"n1","n2"},
  input_member_ids={},output_member_ids={},style="plain"}}
huge.constraints={{id="@constraint/keep",kind="keep-together",target_ids={"pair"},
  value="row",strength="hard",source={command="test",declaration_index=100}}}
m.by_text_ref["@text/condition"]={width_sp=5000,height_sp=1000,depth_sp=0}
local unreadable,why=solver.solve(huge,m,f)
check(unreadable==nil and why[1].code=="edge-label-conflict","unreadable label diagnoses")
local original_budget=solver.SEARCH_BUDGET
solver.SEARCH_BUDGET=1
local no_scene,exhausted_issue=solver.solve(huge,m,f)
check(no_scene==nil and exhausted_issue[1].code=="solver-budget-exhausted",
  "invalid search reports exhausted budget")
b,m,f=fixture("budget",2)
local budget_scene=assert(solver.solve(assert(b:seal()),m,f))
check(budget_scene.quality.candidates_evaluated==1 and
  budget_scene.quality.budget_exhausted,"one-attempt budget reported")
check(budget_scene.diagnostics[1].code=="solver-budget-exhausted","valid best warns")
solver.SEARCH_BUDGET=original_budget

check(quality.less({0,0,0,0,1,100,0},{0,0,1,0,0,0,0}),"crossing beats spacing")
check(quality.less({0,0,0,0,0,10,0},{0,0,0,0,1,0,0}),"spacing beats length")
local fake={pages={{annotations={},bounding_rect={width_sp=100,height_sp=100}},
  {annotations={},bounding_rect={width_sp=200,height_sp=100}}}}
local regular=quality.vector(fake,{}, {spacing_stats={gap_variance_sp2=0}},
  {costs={},congestion={}}, {strong=0,weak=0})
local compressed=quality.vector(fake,{}, {spacing_stats={gap_variance_sp2=400}},
  {costs={},congestion={}}, {strong=0,weak=0})
check(quality.less(regular,compressed),"irregular local compression penalized")
fake.pages[2].bounding_rect.width_sp=100
local balanced=quality.vector(fake,{}, {spacing_stats={gap_variance_sp2=0}},
  {costs={},congestion={}}, {strong=0,weak=0})
check(quality.less(balanced,regular),"page whitespace imbalance penalized")
local compact={pages={{annotations={},node_rects={n1={width_sp=100,height_sp=100}},
  bounding_rect={width_sp=100,height_sp=100}}}}
local sparse={pages={{annotations={},node_rects={n1={width_sp=100,height_sp=100}},
  bounding_rect={width_sp=300,height_sp=100}}}}
check(quality.less(quality.vector(compact,{}, {spacing_stats={}},
  {costs={},congestion={}}, {}),quality.vector(sparse,{}, {spacing_stats={}},
  {costs={},congestion={}}, {})),"single-page excessive whitespace penalized")

for _,count in ipairs({10,30,50,56}) do
  b,m,f=fixture("size"..count,count,{max_columns=5})
  spec=assert(b:seal())
  local start=os.clock()
  scene,issues=solver.solve(spec,m,f)
  check(scene~=nil,issues and issues[1] and issues[1].message)
  check(scene.quality.candidates_evaluated<=solver.SEARCH_BUDGET,"size budget")
  local again=assert(solver.solve(spec,m,f))
  check(scene.quality.candidates_evaluated==again.quality.candidates_evaluated,
    "size deterministic candidate count")
  for i=1,7 do check(scene.quality.vector[i]==again.quality.vector[i],
    "size deterministic quality") end
  for id,r in pairs(scene.pages[1].node_rects) do
    local q=again.pages[1].node_rects[id]
    check(r.x_sp==q.x_sp and r.y_sp==q.y_sp,"size deterministic placement")
  end
  print(string.format("size=%d seconds=%.3f candidates=%d exhausted=%s",count,
    os.clock()-start,scene.quality.candidates_evaluated,tostring(scene.quality.budget_exhausted)))
end
-- Measured continuation labels accompany routed cross-page flow legs.
b,m,f=fixture("multipage",10,{max_columns=5,multipage=true})
f.content_height_sp=350;f.page_height_sp=350
spec=assert(b:seal())
local cs=assert(constraints.normalize(spec,f))
local plans=assert(planner.plan(analysis.analyze(spec),m,cs,f))
for _,plan in ipairs(plans) do for _,page in ipairs(plan.pages) do
  for _,marker in ipairs(page.continuation_markers or {}) do
    m.by_text_ref[marker.text_ref]={width_sp=40,height_sp=10,depth_sp=0}
  end
end end
scene,issues=solver.solve(spec,m,f)
check(scene~=nil,issues and issues[1] and issues[1].message)
check(#scene.pages>1,"multipage solved")
local marker_count=0
for _,page in ipairs(scene.pages) do marker_count=marker_count+#page.continuation_markers end
check(marker_count>=2,"continuation markers in Scene")
local multipage_scene=scene
-- Search and visual-calibration regressions exposed by integrated examples.
check(scene.quality.router_calls==scene.quality.candidates_evaluated,"every route attempt counted")
check(scene.quality.router_work>=scene.quality.selected_router_work,"total router work includes selected candidate")
local annotations=require("tikzffbd-annotations")
local tiny={environment_id="short-label",options={},structures={},
  flows={{id="@flow/1",source="a",target="b",condition_ref="@text/c"}}}
local geometry={node_rects_by_id={a={x_sp=0,y_sp=0,width_sp=100,height_sp=50},
  b={x_sp=0,y_sp=60,width_sp=100,height_sp=50}},
  row_axes={{page_index=1,layers={{"a"},{"b"}}}},spacing_stats={route_gap_sp=4}}
local metrics={by_text_ref={["@text/c"]={width_sp=20,height_sp=14}}}
local routes={paths_by_flow_id={["@flow/1"]={page_index=1,points={
  {x_sp=110,y_sp=48},{x_sp=110,y_sp=62}}}}}
local labels=assert(annotations.labels(tiny,metrics,geometry,routes,{}))
check(#labels==1,"short segment label can use clear outside flank")
-- A label cannot cover another segment of its own bent route.
routes.paths_by_flow_id["@flow/1"].points={
  {x_sp=110,y_sp=48},{x_sp=110,y_sp=62},{x_sp=150,y_sp=62},
  {x_sp=150,y_sp=80},{x_sp=110,y_sp=80}}
labels=assert(annotations.labels(tiny,metrics,geometry,routes,{}))
check(not annotations.hits_path(labels[1].rect,routes.paths_by_flow_id["@flow/1"].points,0),
  "label clears every segment of its own flow")
local one_row={pages={{rows={{ordered_node_ids={"a","b"}}}}}}
local orphan={pages={{rows={{ordered_node_ids={"a"}},{ordered_node_ids={"b"}}}}}}
check(quality.less(quality.vector(compact,one_row,{spacing_stats={}},{costs={}},{}),
  quality.vector(compact,orphan,{spacing_stats={}},{costs={}},{})),"unnecessary wrap loses to primary row")

-- Export a fully solved scene for the contract validator and renderer mock.
b,m,f=fixture("scene-export",8)
spec=assert(b:seal())
scene=assert(solver.solve(spec,m,f))
local arrays={pages=true,annotations=true,edge_labels=true,continuation_markers=true,
  diagnostics=true,vector=true,points=true,boundary_port_ids=true,
  ordered_node_ids=true,ordered_region_ids=true,rows=true,continuation_ids=true}
local function encode(value,key)
  if type(value)=="string" then return string.format("%q",value) end
  if type(value)~="table" then return tostring(value) end
  local out={}
  if arrays[key] or #value>0 then
    for _,v in ipairs(value) do out[#out+1]=encode(v) end
    return "["..table.concat(out,",").."]"
  end
  local keys={};for k in pairs(value) do keys[#keys+1]=k end;table.sort(keys)
  for _,k in ipairs(keys) do out[#out+1]=encode(k)..":"..encode(value[k],k) end
  return "{"..table.concat(out,",").."}"
end
local out=assert(io.open("/tmp/tikzffbd-solver-scene.json","w"))
out:write(encode({contract_version=1,environment_id="scene-export",
  objects={Scene=scene}}),"\n");out:close()
out=assert(io.open("/tmp/tikzffbd-solver-multipage.json","w"))
out:write(encode({contract_version=1,environment_id="multipage",
  objects={Scene=multipage_scene}}),"\n");out:close()
print("solver assertions: "..n)
