-- Run with: texlua tests/run_planner.lua
local model=dofile("tikzffbd-model.lua")
local analysis=dofile("tikzffbd-analysis.lua")
local constraints=dofile("tikzffbd-constraints.lua")
local planner=dofile("tikzffbd-planner.lua")
local count=0
local function check(value,message) assert(value,message); count=count+1 end
local function has(ds,code)
  for _,d in ipairs(ds or {}) do if d.code==code then return d end end
end
local function constraint(kind,target,value,strength,index)
  return {id="@constraint/test-"..index,kind=kind,target_ids=target or {},value=value,
    strength=strength,source={command="test",declaration_index=index}}
end
local function fixture(name,number,options,width,height)
  options=options or {}
  local b=model.new{environment_id=name,options=options}
  local ids={}
  for i=1,number do
    local id=string.format("n%02d",i)
    ids[#ids+1]=id
    b:add_function{id=id,text_ref="@text/"..id}
    if i>1 then b:add_flow{source=ids[i-1],target=id} end
  end
  local spec,errors=b:seal()
  check(spec~=nil,errors and errors[1].message)
  local metrics={environment_id=name,by_text_ref={},by_node_id={},
    by_annotation_id={},by_structure_id={},style_clearances={}}
  for _,node in ipairs(spec.nodes) do
    metrics.by_node_id[node.id]={width_sp=100,height_sp=80}
  end
  local frame={environment_id=name,direction=options.direction or "right",scale=options.scale or 1,
    content_width_sp=width or 500,content_height_sp=height or 500,
    page_width_sp=width or 500,page_height_sp=height or 500}
  return b,spec,metrics,frame,ids
end
local function run(spec,metrics,frame)
  local normalized,errors=constraints.normalize(spec,frame)
  check(normalized~=nil,errors and errors[1].message)
  local regions=analysis.analyze(spec)
  local plans,diagnostics=planner.plan(regions,metrics,normalized,frame)
  return plans,diagnostics,regions,normalized
end
local function rows(plan)
  local out={}
  for _,page in ipairs(plan.pages) do for _,row in ipairs(page.rows) do out[#out+1]=row end end
  return out
end
local _,spec,metrics,frame,ids=fixture("right-eight",8,nil,500,1000)
local plans,ds,regions,cs=run(spec,metrics,frame)
check(plans and #plans>0,"eight node chain planned")
local rr=rows(plans[1])
check(#rr>=2 and rr[1].direction_sign==1 and rr[2].direction_sign==-1,"rightward serpentine")
check(#rr[1].ordered_node_ids<=5,"hard max columns")
check(plans[1].estimated_costs.candidates_evaluated<=plans[1].estimated_costs.search_budget,
  "search budget reported")
-- Contract evaluator gets the complete candidate and must find no hard row fault.
local issues=constraints.check({plan=plans[1],spec=spec,frame=frame,complete=true},cs)
for _,d in ipairs(issues) do check(d.severity~="error","hard constraint satisfied") end

_,spec,metrics,frame=fixture("hard-two",8,{max_columns=2},1000,1000)
plans=run(spec,metrics,frame)
for _,r in ipairs(rows(plans[1])) do check(#r.ordered_node_ids<=2,"explicit hard column limit") end

_,spec,metrics,frame=fixture("down-eight",8,{direction="down"},1000,500)
plans=run(spec,metrics,frame)
rr=rows(plans[1])
check(#rr>=2 and rr[1].direction_sign==1 and rr[2].direction_sign==-1,
  "downward bands alternate")

_,spec,metrics,frame=fixture("exact-break",8,nil,500,1000)
spec=model.inspect(spec)
spec.constraints={constraint("row-break",{"n02"},true,"hard",20)}
plans=run(spec,metrics,frame)
check(plans and rows(plans[1])[1].ordered_node_ids[#rows(plans[1])[1].ordered_node_ids]=="n02",
  "hard break exact")
check(rows(plans[1])[1].forced_break_ids[1]=="@constraint/test-20","hard break provenance")
spec.constraints[1].strength="strong"
plans=run(spec,metrics,frame)
local found=false
for _,p in ipairs(plans) do
  for _,r in ipairs(rows(p)) do if r.preferred_break_ids[1]=="@constraint/test-20" then found=true end end
end
check(found,"soft break represented as preference")

_,spec,metrics,frame=fixture("soft-columns",7,{max_columns=2,max_columns_strength="soft"},500,1000)
spec=model.inspect(spec)
spec.structures={{id="grp",index=99,member_ids={"n01","n02","n03"},
  input_member_ids={"n01"},output_member_ids={"n03"},style="shaded"}}
spec.constraints={constraint("keep-together",{"grp"},"row","hard",100)}
plans=run(spec,metrics,frame)
check(plans and #rows(plans[1])[1].ordered_node_ids>2,"soft column limit may be exceeded")
check(plans[1].estimated_costs.strong>0,"soft column cost recorded")

local b=model.new{environment_id="branch",options={max_columns=5}}
for _,id in ipairs({"s","a","b","c","t"}) do b:add_function{id=id,text_ref="@text/"..id} end
b:add_branch{source_id="s",arms={"a","b","c"}}
b:add_join{arms={"a","b","c"},target_id="t"}
spec=assert(b:seal())
metrics={environment_id="branch",by_text_ref={},by_node_id={},by_annotation_id={},
  by_structure_id={},style_clearances={}}
for _,node in ipairs(spec.nodes) do metrics.by_node_id[node.id]={width_sp=100,height_sp=80} end
frame={environment_id="branch",direction="right",scale=1,content_width_sp=1000,
  content_height_sp=1000,page_width_sp=1000,page_height_sp=1000}
plans,ds,regions=run(spec,metrics,frame)
check(plans and #rows(plans[1])>=2,"parallel case planned")
local parallel
for _,r in pairs(regions.regions_by_id) do if r.kind=="parallel" then parallel=r end end
check(parallel and #parallel.member_ids==5,"branch region recognized")
local location={}
for ri,row in ipairs(rows(plans[1])) do for _,id in ipairs(row.ordered_node_ids) do location[id]=ri end end
for _,id in ipairs(parallel.member_ids) do check(location[id]==location[parallel.member_ids[1]],"branch intact") end
spec=model.inspect(spec); spec.options.multipage=true
-- Three measured 80-sp branch lanes plus two 30-sp gaps need 300 sp;
-- reserve the planner's 80-sp page gutters as well.
frame.content_height_sp=400; frame.page_height_sp=400
plans=run(spec,metrics,frame)
local branch_page
for pi,page in ipairs(plans[1].pages) do
  for _,row in ipairs(page.rows) do
    for _,id in ipairs(row.ordered_node_ids) do
      for _,member in ipairs(parallel.member_ids) do
        if id==member then
          if branch_page then check(branch_page==pi,"semantic page cut preserves feasible branch")
          else branch_page=pi end
        end
      end
    end
  end
end
check(branch_page~=nil and #plans[1].pages>=2,"semantic page boundary chosen")

_,spec,metrics,frame=fixture("multipage",12,{multipage=true},500,180)
plans=run(spec,metrics,frame)
check(plans and #plans[1].pages>1,"multipage cut")
for _,page in ipairs(plans[1].pages) do
  check(page.rows[1].direction_sign==1,"page resets direction")
end
local p1,p2=plans[1].pages[1],plans[1].pages[2]
check(#p1.continuation_markers>0 and #p2.continuation_markers>0,"paired continuations")
check(p1.continuation_markers[1].counterpart_id==p2.continuation_markers[1].id and
  p2.continuation_markers[1].counterpart_id==p1.continuation_markers[1].id,
  "continuation reciprocal")
check(p1.continuation_markers[1].semantic_flow_id==p2.continuation_markers[1].semantic_flow_id,
  "continuation carries semantic flow")

local wide=model.new{environment_id="wide-branch",options={multipage=true,max_columns=5}}
wide:add_function{id="s",text_ref="@text/s"}
for i=1,7 do wide:add_function{id="a"..i,text_ref="@text/a"..i} end
wide:add_function{id="t",text_ref="@text/t"}
local arms={}
for i=1,7 do arms[i]="a"..i end
wide:add_branch{source_id="s",arms=arms}
wide:add_join{arms=arms,target_id="t"}
spec=assert(wide:seal())
metrics={environment_id="wide-branch",by_text_ref={},by_node_id={},
  by_annotation_id={},by_structure_id={},style_clearances={}}
for _,node in ipairs(spec.nodes) do metrics.by_node_id[node.id]={width_sp=100,height_sp=80} end
frame={environment_id="wide-branch",direction="right",scale=1,
  content_width_sp=500,content_height_sp=180,page_width_sp=500,page_height_sp=180}
plans,ds,regions=run(spec,metrics,frame)
check(plans and #plans[1].pages>=3,"oversized parallel region split over pages")
local same_region_pages={}
local branch_region
for _,r in pairs(regions.regions_by_id) do if r.kind=="parallel" then branch_region=r end end
for pi,page in ipairs(plans[1].pages) do
  for _,row in ipairs(page.rows) do
    for _,id in ipairs(row.ordered_node_ids) do
      for _,member in ipairs(branch_region.member_ids) do
        if id==member then same_region_pages[pi]=true end
      end
    end
  end
end
local count_pages=0
for _ in pairs(same_region_pages) do count_pages=count_pages+1 end
check(count_pages>1,"oversized semantic region actually continued")
local markers=0
for _,page in ipairs(plans[1].pages) do
  for _,marker in ipairs(page.continuation_markers) do
    check(marker.label:match("^Continuation %d+%.%d+$")~=nil,"reader-facing continuation label")
    markers=markers+1
  end
end
check(markers>=2,"oversized region has linked markers")

_,spec,metrics,frame=fixture("large",64,{multipage=true},500,180)
plans=run(spec,metrics,frame)
check(plans and #plans[1].pages>5,"64 nodes planned")
check(plans[1].estimated_costs.candidates_evaluated<=4096,"large case bounded")
local repeated=run(spec,metrics,frame)
local function signature(p)
  local out={}
  for _,page in ipairs(p.pages) do
    for _,row in ipairs(page.rows) do out[#out+1]=table.concat(row.ordered_node_ids,",") end
    out[#out+1]="|"
  end
  return table.concat(out,";")
end
check(signature(plans[1])==signature(repeated[1]),"repeat deterministic")

_,spec,metrics,frame=fixture("large-single",64,nil,500,180)
plans=run(spec,metrics,frame)
check(plans and #plans[1].pages==1 and has(plans[1].diagnostics,"single-page-overflow"),
  "over 50 nodes without multipage retains explicit scale and recommends alternatives")

_,spec,metrics,frame=fixture("single-overflow",12,nil,500,180)
plans=run(spec,metrics,frame)
check(plans and has(plans[1].diagnostics,"single-page-overflow"),
  "single page warns without changing scale")
check(plans[1].diagnostics[1].suggested_actions[1]=="Use landscape","overflow recommendations")
check(frame.scale==1,"scale unchanged")

_,spec,metrics,frame=fixture("too-wide",1,nil,90,180)
plans,ds=run(spec,metrics,frame)
check(not plans and has(ds,"no-feasible-rows"),"oversized node reports failure")

_,spec,metrics,frame=fixture("note-footprint",1,nil,300,180)
metrics.by_annotation_id.note={width_sp=1000,height_sp=100}
plans,ds=run(spec,metrics,frame)
check(not plans and has(ds,"no-feasible-rows"),"measured annotation allowance affects row feasibility")

-- Produce a version 1 Plan trace for the Python contract validator.
local arrays={pages=true,rows=true,continuation_ids=true,continuation_markers=true,
  ordered_region_ids=true,ordered_node_ids=true,forced_break_ids=true,
  preferred_break_ids=true,suggested_actions=true,object_ids=true,constraint_ids=true}
local function encode(value,array_key)
  if type(value)=="string" then return string.format("%q",value) end
  if type(value)~="table" then return tostring(value) end
  local items={}
  if array_key or #value>0 then
    for _,v in ipairs(value) do items[#items+1]=encode(v) end
    return "["..table.concat(items,",").."]"
  end
  local keys={}
  for key in pairs(value) do keys[#keys+1]=key end
  table.sort(keys)
  for _,key in ipairs(keys) do items[#items+1]=encode(key)..":"..encode(value[key],arrays[key]) end
  return "{"..table.concat(items,",").."}"
end
_,spec,metrics,frame=fixture("trace-plan",12,{multipage=true},500,180)
plans=run(spec,metrics,frame)
local trace={contract_version=1,environment_id="trace-plan",objects={Plan=plans[1]}}
local file=assert(io.open("/tmp/tikzffbd-planner-plan.json","w"))
file:write(encode(trace),"\n"); file:close()

print("planner: "..count.." assertions passed")
