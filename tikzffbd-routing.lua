-- Orthogonal routing over measured Geometry. Pure Lua; no drawing decisions.
local M={}
local BUDGET=120000
local crossing
local function pt(x,y) return {x_sp=math.floor(x+0.5),y_sp=math.floor(y+0.5)} end
local function eq(a,b) return a.x_sp==b.x_sp and a.y_sp==b.y_sp end
local function hit(a,b,r,pad)
  pad=pad or 0
  local l,t,h,k=r.x_sp-pad,r.y_sp-pad,r.x_sp+r.width_sp+pad,r.y_sp+r.height_sp+pad
  if a.x_sp==b.x_sp then
    return a.x_sp>l and a.x_sp<h and math.max(a.y_sp,b.y_sp)>t and math.min(a.y_sp,b.y_sp)<k
  elseif a.y_sp==b.y_sp then
    return a.y_sp>t and a.y_sp<k and math.max(a.x_sp,b.x_sp)>l and math.min(a.x_sp,b.x_sp)<h
  end
  return true
end
local function conflict(code,id,message,region)
  return {code=code,severity="error",object_ids={id},constraint_ids={},
    message=message,suggested_actions={"Try another row or page candidate","Increase route clearance"},
    obstructed_region=region}
end
local function sidept(r,side)
  local x=math.floor(r.x_sp+r.width_sp/2+0.5)
  local y=math.floor(r.y_sp+r.height_sp/2+0.5)
  if side=="left" then x=r.x_sp elseif side=="right" then x=r.x_sp+r.width_sp
  elseif side=="top" then y=r.y_sp else y=r.y_sp+r.height_sp end
  return pt(x,y)
end
local function step(p,side,n)
  if side=="left" then return pt(p.x_sp-n,p.y_sp) end
  if side=="right" then return pt(p.x_sp+n,p.y_sp) end
  if side=="top" then return pt(p.x_sp,p.y_sp-n) end
  return pt(p.x_sp,p.y_sp+n)
end
local function compact(input)
  local out={}
  for _,p in ipairs(input) do
    if #out==0 or not eq(out[#out],p) then
      out[#out+1]=p
      while #out>=3 do
        local a,b,c=out[#out-2],out[#out-1],out[#out]
        if (a.x_sp==b.x_sp and b.x_sp==c.x_sp) or
            (a.y_sp==b.y_sp and b.y_sp==c.y_sp) then table.remove(out,#out-1)
        else break end
      end
    end
  end
  return out
end
local function clear(a,b,obs,skip,work)
  work.n=work.n+1
  if work.n>BUDGET then work.exhausted=true;return false end
  for _,o in ipairs(obs) do
    if not skip[o.id] and hit(a,b,o.rect,o.pad) then return false end
  end
  return true
end
local function direct(a,b,obs,skip,work)
  local best,best_score
  for _,c in ipairs({pt(b.x_sp,a.y_sp),pt(a.x_sp,b.y_sp)}) do
    if (eq(a,c) or clear(a,c,obs,skip,work)) and
        (eq(c,b) or clear(c,b,obs,skip,work)) then
      local candidate=compact({a,c,b})
      local score=0
      for _,old in ipairs(work.prior or {}) do
        for i=2,#candidate do for j=2,#old do
          if crossing(candidate[i-1],candidate[i],old[j-1],old[j]) then
            score=score+1
          end
        end end
      end
      if not best_score or score<best_score then best,best_score=candidate,score end
    end
  end
  return best
end
-- Sparse local visibility graph: obstacle corners, endpoint projections, and
-- adjacent-corner projections. Adjacent visible vertices share a row/column.
local function search(a,b,obs,skip,work,pref)
  local v,lookup,corners={},{},{}
  local function add(x,y)
    local key=x..":"..y
    if not lookup[key] then lookup[key]=#v+1;v[#v+1]=pt(x,y) end
  end
  add(a.x_sp,a.y_sp);add(b.x_sp,b.y_sp)
  add(a.x_sp,b.y_sp);add(b.x_sp,a.y_sp)
  local m=pref.margin
  for _,o in ipairs(obs) do
    local r=o.rect
    if not skip[o.id] and r.x_sp<=math.max(a.x_sp,b.x_sp)+m and
        r.x_sp+r.width_sp>=math.min(a.x_sp,b.x_sp)-m and
        r.y_sp<=math.max(a.y_sp,b.y_sp)+m and
        r.y_sp+r.height_sp>=math.min(a.y_sp,b.y_sp)-m then
      local d=o.pad+1
      for _,x in ipairs({r.x_sp-d,r.x_sp+r.width_sp+d}) do
        for _,y in ipairs({r.y_sp-d,r.y_sp+r.height_sp+d}) do
          corners[#corners+1]=pt(x,y)
          add(x,y);add(x,a.y_sp);add(x,b.y_sp)
          add(a.x_sp,y);add(b.x_sp,y)
        end
      end
    end
  end
  table.sort(corners,function(p,q)
    return p.x_sp<q.x_sp or (p.x_sp==q.x_sp and p.y_sp<q.y_sp)
  end)
  for i=2,#corners do add(corners[i-1].x_sp,corners[i].y_sp) end
  if #v>3000 then return nil,"visibility-vertex-budget" end
  local rows,cols,adj={},{},{}
  for i,p in ipairs(v) do
    rows[p.y_sp]=rows[p.y_sp] or {};rows[p.y_sp][#rows[p.y_sp]+1]=i
    cols[p.x_sp]=cols[p.x_sp] or {};cols[p.x_sp][#cols[p.x_sp]+1]=i
    adj[i]={}
  end
  local function join(i,j)
    if clear(v[i],v[j],obs,skip,work) then
      adj[i][#adj[i]+1]=j;adj[j][#adj[j]+1]=i
    end
  end
  for _,bucket in pairs(rows) do
    table.sort(bucket,function(i,j)return v[i].x_sp<v[j].x_sp end)
    for i=2,#bucket do join(bucket[i-1],bucket[i]) end
  end
  for _,bucket in pairs(cols) do
    table.sort(bucket,function(i,j)return v[i].y_sp<v[j].y_sp end)
    for i=2,#bucket do join(bucket[i-1],bucket[i]) end
  end
  if work.exhausted then return nil,"route-work-budget" end
  local goal=lookup[b.x_sp..":"..b.y_sp]
  local dist,prev,open={["1:"]=0},{},{{id=1,dir="",cost=0}}
  while #open>0 do
    table.sort(open,function(p,q)
      if p.cost~=q.cost then return p.cost<q.cost end
      if p.id~=q.id then return p.id<q.id end
      return p.dir<q.dir
    end)
    local s=table.remove(open,1)
    local key=s.id..":"..s.dir
    if s.cost==dist[key] then
      work.n=work.n+1
      if work.n>BUDGET then work.exhausted=true;return nil,"route-work-budget" end
      if s.id==goal then
        local rev={v[s.id]}
        while prev[key] do
          key=prev[key]
          rev[#rev+1]=v[tonumber(key:match("^(%d+):"))]
        end
        local path={}
        for i=#rev,1,-1 do path[#path+1]=rev[i] end
        return compact(path)
      end
      for _,j in ipairs(adj[s.id]) do
        local p,q=v[s.id],v[j]
        local dir=p.x_sp==q.x_sp and "v" or "h"
        local length=math.abs(p.x_sp-q.x_sp)+math.abs(p.y_sp-q.y_sp)
        local bend=s.dir~="" and s.dir~=dir and pref.bend or 0
        local delta=dir=="h" and q.x_sp-p.x_sp or q.y_sp-p.y_sp
        local wrong=dir==pref.axis and delta*pref.sign<0 and length*pref.wrong or 0
        local crossing_penalty=0
        for _,old in ipairs(pref.prior or {}) do
          for k=2,#old do
            if crossing(p,q,old[k-1],old[k]) then
              crossing_penalty=crossing_penalty+pref.crossing_penalty
            end
          end
        end
        local cost=s.cost+length+bend+wrong+crossing_penalty
        local nk=j..":"..dir
        if not dist[nk] or cost<dist[nk] then
          dist[nk]=cost;prev[nk]=key;open[#open+1]={id=j,dir=dir,cost=cost}
        end
      end
    end
  end
  return nil,"obstructed-corridor"
end
crossing=function(a,b,c,d)
  if a.x_sp==b.x_sp and c.y_sp==d.y_sp then
    return a.x_sp>math.min(c.x_sp,d.x_sp) and a.x_sp<math.max(c.x_sp,d.x_sp)
      and c.y_sp>math.min(a.y_sp,b.y_sp) and c.y_sp<math.max(a.y_sp,b.y_sp)
  elseif a.y_sp==b.y_sp and c.x_sp==d.x_sp then
    return c.x_sp>math.min(a.x_sp,b.x_sp) and c.x_sp<math.max(a.x_sp,b.x_sp)
      and a.y_sp>math.min(c.y_sp,d.y_sp) and a.y_sp<math.max(c.y_sp,d.y_sp)
  end
  return false
end
local function overlap(a,b,c,d)
  if a.x_sp==b.x_sp and c.x_sp==d.x_sp and a.x_sp==c.x_sp then
    local lo=math.max(math.min(a.y_sp,b.y_sp),math.min(c.y_sp,d.y_sp))
    local hi=math.min(math.max(a.y_sp,b.y_sp),math.max(c.y_sp,d.y_sp))
    if lo<hi then return pt(a.x_sp,lo),pt(a.x_sp,hi) end
  elseif a.y_sp==b.y_sp and c.y_sp==d.y_sp and a.y_sp==c.y_sp then
    local lo=math.max(math.min(a.x_sp,b.x_sp),math.min(c.x_sp,d.x_sp))
    local hi=math.min(math.max(a.x_sp,b.x_sp),math.max(c.x_sp,d.x_sp))
    if lo<hi then return pt(lo,a.y_sp),pt(hi,a.y_sp) end
  end
end
local function route_impl(g,spec,occupied_annotations,work)
  if type(g)~="table" or type(spec)~="table" or g.environment_id~=spec.environment_id then
    return nil,conflict("environment-mismatch","@flow/unknown","Geometry and Spec environments differ")
  end
  local gap=(g.spacing_stats or {}).route_gap_sp or 10
  local stub=math.max(2,math.floor(gap/5))
  local pad=math.max(0,math.floor(gap/10))
  local routes={environment_id=spec.environment_id,paths_by_flow_id={},ports_by_id={},
    shared_trunks={},crossings={},congestion={},conflicts={},
    feedback_lanes={},
    costs={length_sp=0,bends=0,crossings=0,wrong_way_sp=0,work_budget=BUDGET,
      work_used=0,budget_exhausted=false,ripup_passes=0}}
  local page,row,sign={},{},{}
  for _,axis in ipairs(g.row_axes or {}) do
    for _,layer in ipairs(axis.layers or {}) do
      for _,id in ipairs(layer) do
        page[id]=axis.page_index;row[id]=axis.row_index;sign[id]=axis.direction_sign
      end
    end
  end
  local candidates={}
  for _,p in ipairs(g.provisional_ports or {}) do candidates[p.flow_id]=p end
  local obs={}
  local function obstacle(p,id,r,padding,group)
    obs[p]=obs[p] or {};obs[p][#obs[p]+1]={id=id,rect=r,pad=padding,group=group}
  end
  for id,r in pairs(g.node_rects_by_id or {}) do obstacle(page[id],id,r,pad,false) end
  for id,r in pairs(g.group_rects_by_id or {}) do
    obstacle((g.group_rect_page_by_id or {})[id] or 1,id,r,0,true)
  end
  for i,item in ipairs(occupied_annotations or {}) do
    obstacle(item.page_index or 1,item.id or "annotation-"..i,item.rect or item,pad,false)
  end
  for _,item in ipairs(g.structure_texts or {}) do
    obstacle(item.page_index,item.id,item.rect,0,false)
  end
  for _,list in pairs(obs) do table.sort(list,function(a,b)return a.id<b.id end) end
  local prior,prior_flows={},{}
  work.prior=prior
  for _,f in ipairs(spec.flows or {}) do
    local c=candidates[f.id]
    local sr,tr=g.node_rects_by_id[f.source],g.node_rects_by_id[f.target]
    if not c or not sr or not tr then
      return nil,conflict("missing-port-candidate",f.id,"Flow lacks measured endpoints or provisional ports")
    end
    for _,structure in ipairs(spec.structures or {}) do
      local members={}
      for _,id in ipairs(structure.member_ids) do members[id]=true end
      local source_inside,target_inside=members[f.source],members[f.target]
      if source_inside~=target_inside then
        local member=source_inside and f.source or f.target
        local declared=source_inside and structure.output_member_ids or
          structure.input_member_ids
        local allowed=false
        for _,id in ipairs(declared or {}) do if id==member then allowed=true end end
        if not allowed then
          return nil,conflict("undeclared-structure-crossing",f.id,
            "Flow crosses "..structure.id.." through undeclared member "..member,
            structure.id)
        end
      end
    end
    if page[f.source]~=page[f.target] then
      local markers=g.continuation_markers_by_page or {}
      local first,last=math.min(page[f.source],page[f.target]),
        math.max(page[f.source],page[f.target])
      local flow_markers={}
      for p=first,last do
        flow_markers[p]={}
        for _,mark in ipairs(markers[p] or {}) do
          if mark.semantic_flow_id==f.id then
            flow_markers[p][mark.role]=mark
          end
        end
      end
      if not flow_markers[page[f.source]].out or
          not flow_markers[page[f.target]]["in"] then
        return nil,conflict("page-continuation-unresolved",f.id,
          "Cross-page flow lacks reciprocal plan markers",
          tostring(page[f.source])..":"..tostring(page[f.target]))
      end
      local suffix=f.id:gsub("^@flow/",""):gsub("/","-")
      local source_side=c.source_side=="outer" and
        (spec.options.direction=="down" and "left" or "top") or c.source_side
      local target_side=c.target_side=="outer" and
        (spec.options.direction=="down" and "left" or "top") or c.target_side
      local source_port=sidept(sr,source_side)
      local target_port=sidept(tr,target_side)
      local source_id,target_id="@port/"..suffix.."/source",
        "@port/"..suffix.."/target"
      routes.ports_by_id[source_id]=source_port
      routes.ports_by_id[target_id]=target_port
      local cross_boundaries={}
      local function boundary_for(node,other,side,node_port,role)
        local chosen
        for _,structure in ipairs(spec.structures or {}) do
          local inside,other_inside=false,false
          for _,id in ipairs(structure.member_ids) do
            if id==node then inside=true end
            if id==other then other_inside=true end
          end
          if inside and (not other_inside or page[node]~=page[other]) then
            if chosen then return nil,"Nested structure corridor needs another candidate" end
            local declared=role=="out" and structure.output_member_ids or
              structure.input_member_ids
            local allowed=false
            for _,id in ipairs(declared or {}) do if id==node then allowed=true end end
            if not allowed and not other_inside then return nil,"No declared "..role..
              " boundary member for "..structure.id end
            local key
            for gid,owner_page in pairs(g.group_rect_page_by_id or {}) do
              if owner_page==page[node] and (gid==structure.id or
                  gid:find("group-"..structure.id.."-page-",1,true)) then
                key=gid;break
              end
            end
            if not key then return nil,"No measured boundary for "..structure.id end
            local bp=sidept(g.group_rects_by_id[key],side)
            if side=="left" or side=="right" then bp.y_sp=node_port.y_sp
            else bp.x_sp=node_port.x_sp end
            local id="@port/"..suffix.."/group-"..structure.id.."-"..role
            routes.ports_by_id[id]=bp
            cross_boundaries[#cross_boundaries+1]=id
            chosen={id=id,point=bp,side=side,key=key}
          end
        end
        return chosen
      end
      local source_boundary,source_error=boundary_for(
        f.source,f.target,source_side,source_port,"out")
      if source_error then return nil,conflict("missing-structure-boundary",f.id,
        source_error,tostring(page[f.source])) end
      local target_boundary,target_error=boundary_for(
        f.target,f.source,target_side,target_port,"in")
      if target_error then return nil,conflict("missing-structure-boundary",f.id,
        target_error,tostring(page[f.target])) end
      local segments={}
      local advance=page[f.source]<page[f.target] and 1 or -1
      local function marker_port(p,mark)
        local ext=(g.page_extents_by_index or {})[p]
        if not ext then return nil end
        local offset=gap+stub
        local x,y
        if spec.options.direction=="down" then
          x=mark.role=="out" and ext.x_sp+ext.width_sp+offset or
            ext.x_sp-offset
          y=math.floor(ext.y_sp+ext.height_sp/2+0.5)
        else
          x=math.floor(ext.x_sp+ext.width_sp/2+0.5)
          y=mark.role=="out" and ext.y_sp+ext.height_sp+offset or
            ext.y_sp-offset
        end
        local id="@port/"..suffix.."/continuation-"..
          mark.id:gsub("^@continuation/",""):gsub("/","-")
        local result=pt(x,y)
        routes.ports_by_id[id]=result
        return id,result
      end
      for p=page[f.source],page[f.target],advance do
        local from_mark=flow_markers[p]["in"]
        local to_mark=flow_markers[p].out
        local from_id,from_pt
        if p==page[f.source] then
          from_id,from_pt=source_id,source_port
        else
          from_id,from_pt=marker_port(p,from_mark)
        end
        local to_id,to_pt
        if p==page[f.target] then
          to_id,to_pt=target_id,target_port
        else
          to_id,to_pt=marker_port(p,to_mark)
        end
        if not from_pt or not to_pt then
          return nil,conflict("page-continuation-unresolved",f.id,
            "Continuation page has no measured extent",tostring(p))
        end
        local local_skip={}
        local start=from_pt
        local finish=to_pt
        if p==page[f.source] then
          start=step(source_boundary and source_boundary.point or from_pt,
            source_side,stub)
        end
        if p==page[f.target] then
          finish=step(target_boundary and target_boundary.point or to_pt,
            target_side,stub)
        end
        local list=obs[p] or {}
        local pref={axis=spec.options.direction=="down" and "v" or "h",
          sign=sign[f.source] or 1,bend=gap,wrong=0,margin=5*gap,
          prior=prior,crossing_penalty=10*gap}
        local core=direct(start,finish,list,local_skip,work)
        local why
        if not core then core,why=search(start,finish,list,local_skip,work,pref) end
        if not core then return nil,conflict(why or "obstructed-continuation",f.id,
          "No corridor to continuation marker on page "..p,tostring(p)) end
        local all={from_pt}
        if p==page[f.source] and source_boundary then
          all[#all+1]=source_boundary.point
        end
        for _,q in ipairs(core) do all[#all+1]=q end
        if p==page[f.target] and target_boundary then
          all[#all+1]=target_boundary.point
        end
        all[#all+1]=to_pt
        all=compact(all)
        for i=2,#all do
          if all[i].x_sp~=all[i-1].x_sp and all[i].y_sp~=all[i-1].y_sp then
            return nil,conflict("nonorthogonal-continuation",f.id,
              "Continuation leg has a diagonal segment",tostring(p))
          end
          for _,o in ipairs(list) do
            if not o.group and
                hit(all[i-1],all[i],o.rect,0) then
              return nil,conflict("route-through-obstacle",f.id,
                "Continuation leg enters "..o.id,tostring(p))
            end
          end
        end
        segments[#segments+1]={page_index=p,source_port_id=from_id,
          target_port_id=to_id,points=all,
          source_marker_id=from_mark and from_mark.id or nil,
          target_marker_id=to_mark and to_mark.id or nil}
        for i=2,#all do
          routes.costs.length_sp=routes.costs.length_sp+
            math.abs(all[i].x_sp-all[i-1].x_sp)+
            math.abs(all[i].y_sp-all[i-1].y_sp)
          if i>2 then routes.costs.bends=routes.costs.bends+1 end
        end
      end
      local head=segments[1]
      routes.paths_by_flow_id[f.id]={source_port_id=head.source_port_id,
        target_port_id=head.target_port_id,points=head.points,
        page_index=head.page_index,kind=f.kind,page_segments=segments,
        semantic_source_port_id=source_id,semantic_target_port_id=target_id,
        boundary_port_ids=cross_boundaries}
      prior[#prior+1]=head.points;prior_flows[#prior_flows+1]=f
    else
    local ss,ts=c.source_side,c.target_side
    if ss=="outer" then
      ss=spec.options.direction=="down" and "left" or "top";ts=ss
    end
    local feedback_lane
    if f.kind=="feedback" then
      local extent=(g.page_extents_by_index or {})[page[f.source]]
      if extent then
        if spec.options.direction=="down" then
          if extent.x_sp-gap-stub>=0 then
            ss,ts="left","left";feedback_lane=extent.x_sp-gap
          else
            ss,ts="right","right"
            feedback_lane=extent.x_sp+extent.width_sp+gap
          end
        else
          if extent.y_sp-gap-stub>=0 then
            ss,ts="top","top";feedback_lane=extent.y_sp-gap
          else
            ss,ts="bottom","bottom"
            feedback_lane=extent.y_sp+extent.height_sp+gap
          end
        end
      end
    end
    local sp,tp=sidept(sr,ss),sidept(tr,ts)
    local a,b=step(sp,ss,stub),step(tp,ts,stub)
    local skip={}
    local boundaries={}
    for _,structure in ipairs(spec.structures or {}) do
      local members={}
      for _,id in ipairs(structure.member_ids) do members[id]=true end
      local source_inside,target_inside=members[f.source],members[f.target]
      if source_inside~=target_inside then
        local member=source_inside and f.source or f.target
        local declared=source_inside and structure.output_member_ids or structure.input_member_ids
        local allowed=false
        for _,id in ipairs(declared or {}) do if id==member then allowed=true end end
        if not allowed then
          return nil,conflict("undeclared-structure-crossing",f.id,
            "Flow crosses "..structure.id.." through undeclared member "..member,structure.id)
        end
        local key
        for gid,p in pairs(g.group_rect_page_by_id or {}) do
          if p==page[member] and (gid==structure.id or
              gid:find("group-"..structure.id.."-page-",1,true)) then key=gid;break end
        end
        if not key then return nil,conflict("missing-structure-boundary",f.id,
          "No measured boundary for "..structure.id,structure.id) end
        local side=source_inside and ss or ts
        local bp=sidept(g.group_rects_by_id[key],side)
        local nodept=source_inside and sp or tp
        if side=="left" or side=="right" then bp.y_sp=nodept.y_sp
        else bp.x_sp=nodept.x_sp end
        boundaries[#boundaries+1]={key=key,point=bp,side=side,
          role=source_inside and "out" or "in",structure_id=structure.id}
      elseif source_inside and target_inside then
        for gid,p in pairs(g.group_rect_page_by_id or {}) do
          if p==page[f.source] and (gid==structure.id or
              gid:find("group-"..structure.id.."-page-",1,true)) then skip[gid]=true end
        end
      end
    end
    local sb,tb
    for _,boundary in ipairs(boundaries) do
      if boundary.role=="out" then
        if sb then return nil,conflict("nested-structure-corridor",f.id,
          "Flow exits more than one structure",tostring(page[f.source])) end
        sb=boundary
      else
        if tb then return nil,conflict("nested-structure-corridor",f.id,
          "Flow enters more than one structure",tostring(page[f.target])) end
        tb=boundary
      end
    end
    if sb then a=step(sb.point,sb.side,stub);skip[sb.key]=true end
    if tb then b=step(tb.point,tb.side,stub);skip[tb.key]=true end
    local pref={axis=spec.options.direction=="down" and "v" or "h",
      sign=sign[f.source] or 1,bend=gap,wrong=f.kind=="feedback" and 0 or 2,
      margin=math.max(3*gap,math.abs(a.x_sp-b.x_sp)+math.abs(a.y_sp-b.y_sp)),
      prior=prior,crossing_penalty=10*gap}
    local middle
    if feedback_lane then
      local lane_a,lane_b
      if spec.options.direction=="down" then
        lane_a,lane_b=pt(feedback_lane,a.y_sp),pt(feedback_lane,b.y_sp)
      else
        lane_a,lane_b=pt(a.x_sp,feedback_lane),pt(b.x_sp,feedback_lane)
      end
      local route=compact({a,lane_a,lane_b,b})
      local valid=true
      for i=2,#route do
        if not clear(route[i-1],route[i],obs[page[f.source]] or {},skip,work) then
          valid=false;break
        end
      end
      if valid then
        middle=route
        routes.feedback_lanes[#routes.feedback_lanes+1]={
          flow_id=f.id,page_index=page[f.source],side=ss,coordinate_sp=feedback_lane}
      end
    end
    if not middle then middle=direct(a,b,obs[page[f.source]] or {},skip,work) end
    local reason
    if not middle then middle,reason=search(a,b,obs[page[f.source]] or {},skip,work,pref) end
    if middle and #prior>0 and f.kind~="feedback" then
      local before=0
      for _,old in ipairs(prior) do for i=2,#middle do for j=2,#old do
        if crossing(middle[i-1],middle[i],old[j-1],old[j]) then before=before+1 end
      end end end
      if before>0 then
        local alternate=search(a,b,obs[page[f.source]] or {},skip,work,pref)
        if alternate then
          local after=0
          for _,old in ipairs(prior) do for i=2,#alternate do for j=2,#old do
            if crossing(alternate[i-1],alternate[i],old[j-1],old[j]) then after=after+1 end
          end end end
          if after<before then
            middle=alternate
            routes.costs.ripup_passes=routes.costs.ripup_passes+1
          end
        end
      end
    end
    if not middle then return nil,conflict(reason or "obstructed-corridor",f.id,
      "No orthogonal corridor for "..f.id,reason or tostring(row[f.source])) end
    local points={sp}
    if sb then points[#points+1]=sb.point end
    for _,p in ipairs(middle) do points[#points+1]=p end
    if tb then points[#points+1]=tb.point end
    points[#points+1]=tp;points=compact(points)
    for i=2,#points do
      if points[i].x_sp~=points[i-1].x_sp and points[i].y_sp~=points[i-1].y_sp then
        return nil,conflict("nonorthogonal-boundary",f.id,"Structure boundary port cannot join its corridor")
      end
      for _,o in ipairs(obs[page[f.source]] or {}) do
        if not o.group and
            hit(points[i-1],points[i],o.rect,0) then
          return nil,conflict("route-through-obstacle",f.id,"Route enters "..o.id,o.id)
        end
      end
    end
    for _,o in ipairs(obs[page[f.source]] or {}) do
      if o.group then
        local source_group=sb and sb.key==o.id
        local target_group=tb and tb.key==o.id
        if not skip[o.id] or source_group or target_group then
          for i=2,#points do
            if hit(points[i-1],points[i],o.rect,0) and
                not (source_group and i==2) and
                not (target_group and i==#points) then
              return nil,conflict("invalid-structure-port",f.id,
                "Route crosses structure away from its declared boundary port",o.id)
            end
          end
        else
          for _,p in ipairs(points) do
            if p.x_sp<o.rect.x_sp or p.x_sp>o.rect.x_sp+o.rect.width_sp or
                p.y_sp<o.rect.y_sp or p.y_sp>o.rect.y_sp+o.rect.height_sp then
              return nil,conflict("invalid-structure-port",f.id,
                "Internal flow leaves its structure",o.id)
            end
          end
        end
      end
    end
    local suffix=f.id:gsub("^@flow/",""):gsub("/","-")
    local sid,tid="@port/"..suffix.."/source","@port/"..suffix.."/target"
    routes.ports_by_id[sid]=sp;routes.ports_by_id[tid]=tp
    local path={source_port_id=sid,target_port_id=tid,points=points,
      page_index=page[f.source],kind=f.kind,boundary_port_ids={}}
    for _,v in ipairs(boundaries) do
      local id="@port/"..suffix.."/group-"..v.structure_id.."-"..v.role
      routes.ports_by_id[id]=v.point;path.boundary_port_ids[#path.boundary_port_ids+1]=id
    end
    local crossings=0
    for i=2,#points do
      local a1,b1=points[i-1],points[i]
      local primary=spec.options.direction=="down" and
        b1.y_sp-a1.y_sp or b1.x_sp-a1.x_sp
      if f.kind=="forward" and row[f.source]==row[f.target]
          and primary*(sign[f.source] or 1)<0 then
        routes.costs.wrong_way_sp=routes.costs.wrong_way_sp+math.abs(primary)
      end
      routes.costs.length_sp=routes.costs.length_sp+
        math.abs(a1.x_sp-b1.x_sp)+math.abs(a1.y_sp-b1.y_sp)
      if i>2 then routes.costs.bends=routes.costs.bends+1 end
      for old_index,old in ipairs(prior) do for j=2,#old do
        if crossing(a1,b1,old[j-1],old[j]) then crossings=crossings+1 end
        local lo,hi=overlap(a1,b1,old[j-1],old[j])
        if lo then
          local earlier=prior_flows[old_index]
          if earlier and (earlier.source==f.source or earlier.target==f.target) then
            routes.shared_trunks[#routes.shared_trunks+1]={
              flow_ids={earlier.id,f.id},source_id=f.source,target_id=f.target,
              points={lo,hi},page_index=page[f.source]}
          else
            routes.congestion[#routes.congestion+1]={
              flow_ids={earlier and earlier.id or "unknown",f.id},
              points={lo,hi},page_index=page[f.source]}
          end
        end
      end end
    end
    routes.costs.crossings=routes.costs.crossings+crossings
    if crossings>0 then routes.crossings[#routes.crossings+1]={flow_id=f.id,count=crossings} end
    routes.paths_by_flow_id[f.id]=path
    prior[#prior+1]=points;prior_flows[#prior_flows+1]=f
    end
  end
  routes.costs.work_used=work.n;routes.costs.budget_exhausted=work.exhausted
  return routes
end
function M.route(g,spec,occupied_annotations)
  local work={n=0,exhausted=false}
  local routes,issue=route_impl(g,spec,occupied_annotations,work)
  if issue then
    issue.work_used=work.n;issue.work_budget=BUDGET
    issue.budget_exhausted=work.exhausted
  end
  return routes,issue
end
return M
