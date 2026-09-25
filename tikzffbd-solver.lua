-- Deterministic, bounded coordination of plan, placement, annotation and route.
local constraints=require("tikzffbd-constraints")
local analysis=require("tikzffbd-analysis")
local planner=require("tikzffbd-planner")
local placement=require("tikzffbd-placement")
local router=require("tikzffbd-routing")
local annotations=require("tikzffbd-annotations")
local quality=require("tikzffbd-quality")
local M={}
M.SEARCH_BUDGET=64 -- complete note/route attempts across at most eight plans
local function diag(code,ids,message,actions)
  return {code=code,severity="error",object_ids=ids or {},constraint_ids={},
    message=message,suggested_actions=actions or {}}
end
local function union(a,b)
  if not a then return b end
  if not b then return a end
  local x=math.min(a.x_sp,b.x_sp);local y=math.min(a.y_sp,b.y_sp)
  return {x_sp=x,y_sp=y,width_sp=math.max(a.x_sp+a.width_sp,b.x_sp+b.width_sp)-x,
    height_sp=math.max(a.y_sp+a.height_sp,b.y_sp+b.height_sp)-y}
end
local function point_rect(p)
  return {x_sp=p.x_sp,y_sp=p.y_sp,width_sp=0,height_sp=0}
end
local function copy(value)
  if type(value)~="table" then return value end
  local out={};for k,v in pairs(value) do out[k]=copy(v) end;return out
end
local function normalize_pages(pages)
  -- A whole-picture translation is free: page fitting depends on its measured
  -- extent, not the arbitrary origin selected by placement. Copy first because
  -- note candidates and geometry are shared by later search attempts.
  pages=copy(pages)
  for _,page in ipairs(pages) do
    local dx,dy=1-page.bounding_rect.x_sp,1-page.bounding_rect.y_sp
    local function shift(p) p.x_sp=p.x_sp+dx;p.y_sp=p.y_sp+dy end
    for _,r in pairs(page.node_rects) do shift(r) end
    for _,r in pairs(page.structure_rects) do shift(r) end
    for _,items in ipairs({page.annotations,page.edge_labels,page.continuation_markers,page.structure_texts}) do
      for _,item in ipairs(items) do shift(item.rect) end
    end
    for _,path in pairs(page.flow_paths) do for _,p in ipairs(path.points) do shift(p) end end
    shift(page.bounding_rect)
  end
  return pages
end
local function pages_for(plan,g,routes,notes,labels,metrics)
  local pages={}
  for i=1,#plan.pages do
    pages[i]={node_rects={},structure_rects={},annotations={},flow_paths={},
      edge_labels={},continuation_markers={},structure_texts={},structure_owner_by_id={},bounding_rect=nil}
  end
  local owners=annotations.page_of(g)
  local function add(p,r) pages[p].bounding_rect=union(pages[p].bounding_rect,r) end
  for id,r in pairs(g.node_rects_by_id) do
    local p=owners[id];pages[p].node_rects[id]=r;add(p,r)
  end
  for id,r in pairs(g.group_rects_by_id) do
    local p=(g.group_rect_page_by_id or {})[id] or 1
    pages[p].structure_rects[id]=r;add(p,r)
    pages[p].structure_owner_by_id[id]=(g.structure_owner_by_id or {})[id] or id
  end
  for _,item in ipairs(g.structure_texts or {}) do
    local p=item.page_index
    pages[p].structure_texts[#pages[p].structure_texts+1]=item;add(p,item.rect)
  end
  for _,n in ipairs(notes) do
    local p=n.page_index;pages[p].annotations[#pages[p].annotations+1]=n;add(p,n.rect)
  end
  for _,l in ipairs(labels) do
    local p=l.page_index;pages[p].edge_labels[#pages[p].edge_labels+1]=l;add(p,l.rect)
  end
  local flow_ids={};for id in pairs(routes.paths_by_flow_id) do flow_ids[#flow_ids+1]=id end
  table.sort(flow_ids)
  for _,id in ipairs(flow_ids) do
    local path=routes.paths_by_flow_id[id]
    for _,leg in ipairs(path.page_segments or {path}) do
      local p=leg.page_index or path.page_index or 1
      pages[p].flow_paths[id]={source_port_id=leg.source_port_id,
        target_port_id=leg.target_port_id,points=leg.points,
        boundary_port_ids=path.boundary_port_ids}
      for _,pt in ipairs(leg.points) do add(p,point_rect(pt)) end
    end
  end
  for p,list in pairs(g.continuation_markers_by_page or {}) do
    for _,mark in ipairs(list) do
      local size=(metrics.by_text_ref or {})[mark.text_ref]
      if not size then return nil,diag("unmeasured-continuation",{mark.id},
        "Continuation text is not measured",{"Measure generated continuation labels before solving"}) end
      local anchor
      for _,path in pairs(routes.paths_by_flow_id) do
        for _,leg in ipairs(path.page_segments or {}) do
          if leg.page_index==p and leg.source_marker_id==mark.id then anchor=leg.points[1] end
          if leg.page_index==p and leg.target_marker_id==mark.id then anchor=leg.points[#leg.points] end
        end
      end
      if not anchor then return nil,diag("continuation-unresolved",{mark.id},
        "Continuation has no routed endpoint") end
      local r={x_sp=anchor.x_sp,y_sp=anchor.y_sp,
        width_sp=size.width_sp,height_sp=size.height_sp+(size.depth_sp or 0)}
      if mark.role=="out" then r.y_sp=r.y_sp-r.height_sp end
      local item={id=mark.id,counterpart_id=mark.counterpart_id,
        semantic_flow_id=mark.semantic_flow_id,text_ref=mark.text_ref,rect=r}
      pages[p].continuation_markers[#pages[p].continuation_markers+1]=item;add(p,r)
    end
  end
  for _,page in ipairs(pages) do
    page.bounding_rect=page.bounding_rect or {x_sp=0,y_sp=0,width_sp=1,height_sp=1}
    if page.bounding_rect.width_sp==0 then page.bounding_rect.width_sp=1 end
    if page.bounding_rect.height_sp==0 then page.bounding_rect.height_sp=1 end
  end
  return pages
end
local function geometry_valid(scene,spec,frame)
  local multipage=(spec.options or {}).multipage==true
  for _,page in ipairs(scene.pages) do
    local objects={}
    for id,r in pairs(page.node_rects) do objects[#objects+1]={id=id,rect=r} end
    for _,n in ipairs(page.annotations) do objects[#objects+1]={id=n.id,rect=n.rect} end
    for _,l in ipairs(page.edge_labels) do objects[#objects+1]={id=l.flow_id,rect=l.rect} end
    for _,m in ipairs(page.continuation_markers) do objects[#objects+1]={id=m.id,rect=m.rect} end
    for _,item in ipairs(page.structure_texts or {}) do objects[#objects+1]={id=item.id,rect=item.rect} end
    for i=1,#objects do for j=i+1,#objects do
      if annotations.overlap(objects[i].rect,objects[j].rect) then
        return diag("text-overlap",{objects[i].id,objects[j].id},
          "Text or block rectangles overlap",{"Try another row plan or annotation position"})
      end
    end end
    local text_objects={}
    for _,items in ipairs({page.annotations,page.edge_labels,page.structure_texts or {}}) do
      for _,item in ipairs(items) do text_objects[#text_objects+1]=item end
    end
    for _,n in ipairs(text_objects) do
      for _,path in pairs(page.flow_paths) do
        if annotations.hits_path(n.rect,path.points,0) then
          return diag("annotation-route-overlap",{n.id},"Flow crosses annotation",
            {"Try another annotation position or row plan"}) end
      end
    end
    if multipage then
      local b=page.bounding_rect
      if b.x_sp<0 or b.y_sp<0 or b.x_sp+b.width_sp>frame.content_width_sp/frame.scale
        or b.y_sp+b.height_sp>frame.content_height_sp/frame.scale then
        return diag("page-fit-violated",{},"Solved page exceeds content bounds at explicit scale",
          {"Try landscape, a different page break, or explicit scale"})
      end
    end
  end
end
function M.solve(spec,metrics,frame)
  if type(spec)~="table" or type(metrics)~="table" or type(frame)~="table"
    or spec.environment_id~=metrics.environment_id or spec.environment_id~=frame.environment_id then
    return nil,{diag("environment-mismatch",{},"Spec, Metrics, and Frame must share an environment")}
  end
  local cs,errors=constraints.normalize(spec,frame)
  if not cs then return nil,errors end
  local plans;plans,errors=planner.plan(analysis.analyze(spec),metrics,cs,frame)
  if not plans then return nil,errors end
  local attempts,best,best_vector,last=0,nil,nil,nil
  local exhausted=false
  local router_work,router_calls=0,0
  for plan_index,plan in ipairs(plans) do
    local g,issue=placement.place(plan,spec,metrics,cs)
    if not g then last=issue else
      local states={{}}
      for _,note in ipairs(spec.annotations or {}) do
        local next_states={}
        local selected=note
        for _,c in ipairs(cs) do
          if c.kind=="annotation-position" and c.strength=="hard"
              and c.target_ids[1]==note.id then
            selected={id=note.id,owner_id=note.owner_id,type_ref=note.type_ref,
              body_ref=note.body_ref,preferred_position=c.value,position_strength="hard"}
          end
        end
        for _,state in ipairs(states) do
          for _,candidate in ipairs(annotations.note_candidates(selected,g,spec,metrics,state)) do
            local copy={table.unpack(state)};copy[#copy+1]=candidate
            next_states[#next_states+1]=copy
            if #next_states>=M.SEARCH_BUDGET then exhausted=true;break end
          end
          if #next_states>=M.SEARCH_BUDGET then break end
        end
        states=next_states
        if #states==0 then
          last=diag("annotation-position-conflict",{note.id},
            "No readable position for annotation "..note.id,
            {"Make an explicit position soft", "Increase spacing or change the row plan"})
          for _,c in ipairs(cs) do
            if c.kind=="annotation-position" and c.target_ids[1]==note.id then
              last.constraint_ids[#last.constraint_ids+1]=c.id
            end
          end
          break
        end
      end
      -- Reserve attempts for every structural alternative. Dense annotation
      -- combinations on the first plan must not starve later row plans.
      local quota=math.max(1,math.floor((M.SEARCH_BUDGET-attempts)/(#plans-plan_index+1)))
      local used=0
      if #states>quota then exhausted=true end
      for state_index=1,math.min(#states,quota) do
        local notes=states[1+math.floor((state_index-1)*#states/math.min(#states,quota))]
        if attempts>=M.SEARCH_BUDGET then exhausted=true;break end
        attempts=attempts+1
        used=used+1
        local routes;routes,issue=router.route(g,spec,notes)
        router_calls=router_calls+1
        router_work=router_work+(routes and routes.costs.work_used or issue and issue.work_used or 0)
        if not routes then last=issue else
          local labels,unplaced=annotations.labels(spec,metrics,g,routes,notes)
          if not labels then
            last=diag("edge-label-conflict",{unplaced},"No readable label position for flow "..unplaced,
              {"Change the row plan or allow more spacing"})
          else
            local pages;pages,issue=pages_for(plan,g,routes,notes,labels,metrics)
            if not pages then last=issue else
              local scene={environment_id=spec.environment_id,pages=normalize_pages(pages),diagnostics={},
                scale=frame.scale,plan=plan}
              issue=geometry_valid(scene,spec,frame)
              if not issue then
                local violations,costs=constraints.check({plan=plan,scene=scene,frame=frame,
                  spec=spec,complete=true},cs)
                for _,d in ipairs(violations) do if d.severity=="error" then issue=d;break end end
                if not issue then
                  for _,page in ipairs(scene.pages) do
                  for _,n in ipairs(page.annotations) do
                    for _,a in ipairs(spec.annotations or {}) do
                      if n.id==a.id then n.preferred_position=a.preferred_position end
                    end
                  end
                  end
                  scene.quality={vector=quality.vector(scene,plan,g,routes,costs),
                    selected_router_work=routes.costs.work_used,
                    search_budget=M.SEARCH_BUDGET,candidates_evaluated=attempts,
                    budget_exhausted=false}
                  if quality.less(scene.quality.vector,best_vector) then
                    best,best_vector=scene,scene.quality.vector
                  end
                end
              end
              if issue then last=issue end
            end
          end
        end
      end
    end
    if attempts>=M.SEARCH_BUDGET then exhausted=true;break end
  end
  if best then
    best.quality.router_work=router_work
    best.quality.router_calls=router_calls
    best.quality.candidates_evaluated=attempts
    best.quality.budget_exhausted=exhausted
    if exhausted then best.diagnostics[1]={code="solver-budget-exhausted",severity="warning",
      object_ids={},constraint_ids={},message="Search budget exhausted; returning best valid candidate",
      suggested_actions={"Reduce diagram congestion or split the diagram"}} end
    if not (spec.options or {}).multipage then
      for _,page in ipairs(best.pages) do
        if page.bounding_rect.width_sp*frame.scale>frame.content_width_sp
            or page.bounding_rect.height_sp*frame.scale>frame.content_height_sp then
          best.diagnostics[#best.diagnostics+1]={code="single-page-overflow",severity="warning",
            object_ids={},constraint_ids={},message="Solved diagram exceeds the content area at the explicit scale",
            suggested_actions={"Use landscape, enable multipage, or choose an explicit scale"}}
          break
        end
      end
    end
    return best
  end
  if exhausted then
    local d=diag("solver-budget-exhausted",last and last.object_ids or {},
      "No valid layout within "..M.SEARCH_BUDGET.." candidate attempts; last conflict: "..
      (last and last.message or "unknown"),
      {"Try landscape, multipage, softer constraints, or explicit scale"})
    d.last_conflict_code=last and last.code
    return nil,{d}
  end
  return nil,{last or diag("no-valid-layout",{},"No valid layout within the deterministic search budget",
    {"Try landscape, multipage, softer constraints, or explicit scale"})}
end
return M
