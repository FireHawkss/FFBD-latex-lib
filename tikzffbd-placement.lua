-- Measured, deterministic row geometry. Routing remains a separate phase.
local analysis = require("tikzffbd-analysis")
local constraints_api = require("tikzffbd-constraints")
local M = {}

local function round(n) return math.floor(n + 0.5) end
local function diagnostic(code, ids, cids, message)
  return {code=code, severity="error", object_ids=ids or {},
    constraint_ids=cids or {}, message=message,
    suggested_actions={"Choose another row plan", "Increase available page space or set an explicit scale"}}
end
local function rect(x,y,w,h)
  return {x_sp=round(x),y_sp=round(y),width_sp=round(w),height_sp=round(h)}
end
local function intersects(a,b)
  return a.x_sp < b.x_sp+b.width_sp and b.x_sp < a.x_sp+a.width_sp
    and a.y_sp < b.y_sp+b.height_sp and b.y_sp < a.y_sp+a.height_sp
end
local function variance(values)
  if #values == 0 then return 0 end
  local mean=0
  for _,v in ipairs(values) do mean=mean+v end
  mean=mean/#values
  local sum=0
  for _,v in ipairs(values) do sum=sum+(v-mean)^2 end
  return sum/#values
end

-- Layers are longest forward paths in this row. An edge spanning several
-- layers is retained as a virtual segment for crossing evaluation; it never
-- creates a semantic node.
local function layers(ids, flows)
  local in_row, rank, by_layer={}, {}, {}
  for _,id in ipairs(ids) do in_row[id]=true end
  for _,id in ipairs(ids) do
    local r=1
    for _,f in ipairs(flows) do
      if f.kind=="forward" and f.target==id and in_row[f.source] then
        r=math.max(r,(rank[f.source] or 0)+1)
      end
    end
    rank[id]=r
    by_layer[r]=by_layer[r] or {}
    by_layer[r][#by_layer[r]+1]=id
  end
  return by_layer,rank
end
local function crossing_count(order,rank,flows)
  local pos={}
  for _,layer in ipairs(order) do for i,id in ipairs(layer) do pos[id]=i end end
  local segments={}
  for _,f in ipairs(flows) do
    local a,b=rank[f.source],rank[f.target]
    if f.kind=="forward" and a and b and a<b then
      for k=a,b-1 do
        -- The straight virtual segment interpolates across missing layers.
        local left=pos[f.source]+(pos[f.target]-pos[f.source])*(k-a)/(b-a)
        local right=pos[f.source]+(pos[f.target]-pos[f.source])*(k+1-a)/(b-a)
        segments[#segments+1]={layer=k,a=left,b=right}
      end
    end
  end
  local count=0
  for i=1,#segments do for j=i+1,#segments do
    local a,b=segments[i],segments[j]
    if a.layer==b.layer and (a.a-b.a)*(a.b-b.b)<0 then count=count+1 end
  end end
  return count
end
local function arm_keys(regions)
  local keys={}
  local ordered={}
  for id,r in pairs(regions.regions_by_id) do
    if r.kind=="parallel" then ordered[#ordered+1]=id end
  end
  table.sort(ordered)
  for _,id in ipairs(ordered) do
    local r=regions.regions_by_id[id]
    for i,child in ipairs(r.ordered_children) do
      for _,member in ipairs(regions.regions_by_id[child].member_ids) do
        keys[member]=keys[member] or {}
        keys[member][id]=i
      end
    end
  end
  return keys
end
local function arm_conflict(a,b,keys)
  for region,ai in pairs(keys[a] or {}) do
    local bi=(keys[b] or {})[region]
    if bi and ai~=bi then return true end
  end
  return false
end
local function branch_compare(a,b,keys)
  local shared={}
  for region,ai in pairs(keys[a] or {}) do
    if (keys[b] or {})[region] then shared[#shared+1]={region,ai,(keys[b] or {})[region]} end
  end
  table.sort(shared,function(x,y) return x[1]<y[1] end)
  for _,item in ipairs(shared) do
    if item[2]~=item[3] then return item[2]<item[3] end
  end
  return nil
end
local function order_layers(order,rank,flows,keys)
  for _,layer in ipairs(order) do
    local original={}
    for i,id in ipairs(layer) do original[id]=i end
    table.sort(layer,function(a,b)
      local branch=branch_compare(a,b,keys)
      if branch~=nil then return branch end
      return original[a]<original[b]
    end)
  end
  local before=crossing_count(order,rank,flows)
  local initial={}
  for k,layer in ipairs(order) do
    initial[k]={}
    for i,id in ipairs(layer) do initial[k][i]=id end
  end
  -- Alternate barycenter sweeps. Only a strict improvement survives a sweep;
  -- equal scores retain the deterministic incoming order.
  for sweep=1,4 do
    local forward=sweep%2==1
    local first,last,step=forward and 2 or #order-1,forward and #order or 1,
      forward and 1 or -1
    for k=first,last,step do
      local layer=order[k]
      local original,score={},{}
      for i,id in ipairs(layer) do original[id]=i end
      local neighbor={}
      for li,other in ipairs(order) do
        if li==k-step then for i,id in ipairs(other) do neighbor[id]=i end end
      end
      for _,id in ipairs(layer) do
        local total,hits=0,0
        for _,f in ipairs(flows) do
          local peer
          if forward and f.target==id and rank[f.source]==k-1 then peer=f.source end
          if not forward and f.source==id and rank[f.target]==k+1 then peer=f.target end
          if peer then total=total+neighbor[peer];hits=hits+1 end
        end
        score[id]=hits>0 and total/hits or original[id]
      end
      table.sort(layer,function(a,b)
        local branch=branch_compare(a,b,keys)
        if branch~=nil then return branch end
        if score[a]~=score[b] then return score[a]<score[b] end
        return original[a]<original[b]
      end)
    end
  end
  local swept=crossing_count(order,rank,flows)
  if swept>before then
    for k,layer in ipairs(initial) do order[k]=layer end
    swept=before
  end
  -- The following adjacent swaps also evaluate every affected long segment.
  local best=swept
  -- Adjacent local swaps are accepted only for a strict crossing improvement.
  -- This preserves declaration order for ties and arm order for parallels.
  for _=1,4 do
    local improved=false
    for k=1,#order do
      for i=1,#order[k]-1 do
        local a,b=order[k][i],order[k][i+1]
        if not arm_conflict(a,b,keys) then
          order[k][i],order[k][i+1]=b,a
          local after=crossing_count(order,rank,flows)
          if after<best then best=after; improved=true
          else order[k][i],order[k][i+1]=a,b end
        end
      end
    end
    if not improved then break end
  end
  return before,best
end

function M.place(plan,spec,metrics,constraints)
  if type(plan)~="table" or type(spec)~="table" or type(metrics)~="table"
      or plan.environment_id~=spec.environment_id
      or plan.environment_id~=metrics.environment_id then
    return nil,diagnostic("environment-mismatch",{},{},"Plan, Spec, and Metrics must share an environment")
  end
  local violations=constraints_api.check({plan=plan,spec=spec,complete=true},constraints or {})
  for _,d in ipairs(violations) do
    if d.severity=="error" then return nil,d end
  end
  local by_node, flow_list={},spec.flows or {}
  for _,n in ipairs(spec.nodes or {}) do by_node[n.id]=n end
  local seen,hard_columns,breaks={},math.huge,{}
  for _,c in ipairs(constraints or {}) do
    if c.strength=="hard" and c.kind=="max-columns" then
      hard_columns=math.min(hard_columns,c.value)
    elseif c.strength=="hard" and c.kind=="row-break" then
      breaks[c.target_ids[1]]=c.id
    end
  end
  local plan_gap=(plan.estimated_costs or {}).route_gap_sp or 0
  local style=metrics.style_clearances or {}
  local route_gap=math.max(1,round(math.max(plan_gap,style.route_gap_sp or 0)))
  local lane_gap=math.max(1,round(math.max(route_gap,style.branch_gap_sp or 0)))
  local row_gap=math.max(1,round(math.max((plan.estimated_costs or {}).row_gap_sp or 0,
    style.row_gap_sp or 0)))
  local group_pad=math.max(1,round(style.group_padding_sp or route_gap/2))
  local max_header=0
  for _,measured in pairs(metrics.by_structure_id or {}) do
    max_header=math.max(max_header,measured.header_height_sp or 0)
  end
  local page_margin=group_pad+max_header
  local regions=analysis.analyze(spec)
  local keys=arm_keys(regions)
  local geometry={environment_id=plan.environment_id,node_rects_by_id={},
    group_rects_by_id={},row_axes={},reserved_channels={},provisional_ports={},
    group_rect_page_by_id={},page_extents_by_index={},group_boundary_ports={},
    spacing_stats={route_gap_sp=route_gap,lane_gap_sp=lane_gap,row_gap_sp=row_gap,
      group_padding_sp=group_pad}}
  local node_page,node_row={},{}
  local gaps,crossings_before,crossings_after={},0,0
  for page_index,page in ipairs(plan.pages or {}) do
    local cross_cursor=page_margin
    for row_index,row in ipairs(page.rows or {}) do
      local ids=row.ordered_node_ids or {}
      if #ids>hard_columns then
        return nil,diagnostic("max-columns-exceeded",ids,{"@constraint/max-columns"},
          "Row exceeds the hard column limit")
      end
      local local_seen={}
      for i,id in ipairs(ids) do
        if not by_node[id] or seen[id] then
          return nil,diagnostic("invalid-plan-node",{id},{},"Plan repeats or invents a node")
        end
        if i<#ids and breaks[id] then
          return nil,diagnostic("row-break-violated",{id},{breaks[id]},"Hard row break is inside a row")
        end
        seen[id]=true;local_seen[id]=true
        node_page[id]=page_index;node_row[id]=row_index
      end
      local order,rank=layers(ids,flow_list)
      local prior,after=order_layers(order,rank,flow_list,keys)
      crossings_before=crossings_before+prior
      crossings_after=crossings_after+after
      local primary_key=spec.options.direction=="down" and "height_sp" or "width_sp"
      local cross_key=spec.options.direction=="down" and "width_sp" or "height_sp"
      local layer_widths,layer_heights={},{}
      for k,layer in ipairs(order) do
        local width,height=0,0
        for i,id in ipairs(layer) do
          local m=metrics.by_node_id and metrics.by_node_id[id]
          if not m or type(m.width_sp)~="number" or type(m.height_sp)~="number"
              or m.width_sp<=0 or m.height_sp<=0 then
            return nil,diagnostic("missing-metrics",{id},{},"Node has no positive measured rectangle")
          end
          width=math.max(width,m[primary_key]); height=height+m[cross_key]
          if i>1 then height=height+lane_gap end
        end
        layer_widths[k]=width;layer_heights[k]=height
      end
      local primary_total,cross_total=0,0
      for k,width in ipairs(layer_widths) do
        primary_total=primary_total+width
        if k>1 then primary_total=primary_total+route_gap;gaps[#gaps+1]=route_gap end
        cross_total=math.max(cross_total,layer_heights[k])
      end
      if row.estimated_primary_sp and primary_total>row.estimated_primary_sp then
        return nil,diagnostic("row-footprint-exceeded",ids,{},
          "Measured row geometry exceeds its planned primary footprint")
      end
      local origin=0
      for k,layer in ipairs(order) do
        local lane=cross_cursor+round((cross_total-layer_heights[k])/2)
        for _,id in ipairs(layer) do
          local m=metrics.by_node_id[id]
          local primary=page_margin+origin+round((layer_widths[k]-m[primary_key])/2)
          if row.direction_sign==-1 then
            primary=2*page_margin+primary_total-primary-m[primary_key]
          end
          local r
          if spec.options.direction=="down" then r=rect(lane,primary,m.width_sp,m.height_sp)
          else r=rect(primary,lane,m.width_sp,m.height_sp) end
          geometry.node_rects_by_id[id]=r
          lane=lane+m[cross_key]+lane_gap
        end
        origin=origin+layer_widths[k]+route_gap
      end
      local axis=round(cross_cursor+cross_total/2)
      geometry.row_axes[#geometry.row_axes+1]={page_index=page_index,row_index=row_index,
        direction_sign=row.direction_sign,axis_sp=axis,
        primary_extent_sp=primary_total,cross_start_sp=cross_cursor,cross_extent_sp=cross_total,
        layers=order,layer_by_node_id=rank}
      geometry.reserved_channels[#geometry.reserved_channels+1]={kind="row-route",
        page_index=page_index,row_index=row_index,width_sp=route_gap}
      cross_cursor=cross_cursor+cross_total
      if row_index<#page.rows then
        geometry.reserved_channels[#geometry.reserved_channels+1]={kind="wrap",
          page_index=page_index,row_index=row_index,width_sp=row_gap}
        cross_cursor=cross_cursor+row_gap;gaps[#gaps+1]=row_gap
      end
    end
    geometry.reserved_channels[#geometry.reserved_channels+1]={kind="feedback",
      page_index=page_index,width_sp=route_gap}
    geometry.reserved_channels[#geometry.reserved_channels+1]={kind="annotation",
      page_index=page_index,width_sp=math.max(route_gap,
        (plan.estimated_costs or {}).note_allowance_sp or 0)}
  end
  for _,n in ipairs(spec.nodes or {}) do
    if not seen[n.id] then
      return nil,diagnostic("missing-plan-node",{n.id},{},"Plan omits a semantic node")
    end
  end
  local node_ids={}
  for id in pairs(geometry.node_rects_by_id) do node_ids[#node_ids+1]=id end
  table.sort(node_ids)
  for i=1,#node_ids do for j=i+1,#node_ids do
    local a,b=node_ids[i],node_ids[j]
    if node_page[a]==node_page[b] and intersects(geometry.node_rects_by_id[a],geometry.node_rects_by_id[b]) then
      return nil,diagnostic("node-overlap",{a,b},{},"Measured node rectangles overlap")
    end
  end end
  for _,s in ipairs(spec.structures or {}) do
    local page_bounds={}
    for _,id in ipairs(s.member_ids) do
      local p=node_page[id];local r=geometry.node_rects_by_id[id]
      if r then
        local b=page_bounds[p]
        if not b then page_bounds[p]={r.x_sp,r.y_sp,r.x_sp+r.width_sp,r.y_sp+r.height_sp}
        else b[1]=math.min(b[1],r.x_sp);b[2]=math.min(b[2],r.y_sp)
          b[3]=math.max(b[3],r.x_sp+r.width_sp);b[4]=math.max(b[4],r.y_sp+r.height_sp) end
      end
    end
    local pages={}
    for p in pairs(page_bounds) do pages[#pages+1]=p end
    table.sort(pages)
    for _,p in ipairs(pages) do
      local b=page_bounds[p]
      local key=#pages==1 and s.id or ("@region/group-"..s.id.."-page-"..p)
      local measured=(metrics.by_structure_id or {})[s.id] or {}
      local header=measured.header_height_sp or 0
      local width=math.max(b[3]-b[1]+2*group_pad,
        (measured.header_width_sp or 0)+2*group_pad,
        (measured.info_width_sp or 0)+2*group_pad)
      geometry.group_rects_by_id[key]=rect(b[1]-group_pad,b[2]-group_pad-header,
        width,b[4]-b[2]+2*group_pad+header)
      geometry.group_rect_page_by_id[key]=p
      local members={}
      for _,id in ipairs(s.member_ids) do members[id]=true end
      for _,id in ipairs(node_ids) do
        if node_page[id]==p and not members[id]
            and intersects(geometry.group_rects_by_id[key],geometry.node_rects_by_id[id]) then
          return nil,diagnostic("group-intrusion",{s.id,id},{},
            "A nonmember node enters the provisional structure rectangle")
        end
      end
    end
  end
  for id,r in pairs(geometry.node_rects_by_id) do
    local p=node_page[id]
    local b=geometry.page_extents_by_index[p]
    if not b then geometry.page_extents_by_index[p]=rect(r.x_sp,r.y_sp,r.width_sp,r.height_sp)
    else
      local x=math.min(b.x_sp,r.x_sp);local y=math.min(b.y_sp,r.y_sp)
      local right=math.max(b.x_sp+b.width_sp,r.x_sp+r.width_sp)
      local bottom=math.max(b.y_sp+b.height_sp,r.y_sp+r.height_sp)
      geometry.page_extents_by_index[p]=rect(x,y,right-x,bottom-y)
    end
  end
  for id,r in pairs(geometry.group_rects_by_id) do
    local p=geometry.group_rect_page_by_id[id]
    local b=geometry.page_extents_by_index[p]
    if not b then geometry.page_extents_by_index[p]=rect(r.x_sp,r.y_sp,r.width_sp,r.height_sp)
    else
      local x=math.min(b.x_sp,r.x_sp);local y=math.min(b.y_sp,r.y_sp)
      local right=math.max(b.x_sp+b.width_sp,r.x_sp+r.width_sp)
      local bottom=math.max(b.y_sp+b.height_sp,r.y_sp+r.height_sp)
      geometry.page_extents_by_index[p]=rect(x,y,right-x,bottom-y)
    end
  end
  local hard_page_fit=false
  for _,c in ipairs(constraints or {}) do
    if c.kind=="page-fit" and c.strength=="hard" then hard_page_fit=true end
  end
  local costs=plan.estimated_costs or {}
  if hard_page_fit and costs.usable_primary_sp and costs.usable_cross_sp then
    for page_index,b in pairs(geometry.page_extents_by_index) do
      local primary=spec.options.direction=="down" and b.y_sp+b.height_sp or b.x_sp+b.width_sp
      local cross=spec.options.direction=="down" and b.x_sp+b.width_sp or b.y_sp+b.height_sp
      if b.x_sp<0 or b.y_sp<0 or primary>costs.usable_primary_sp
          or cross>costs.usable_cross_sp then
        return nil,diagnostic("page-fit-violated",{}, {"@constraint/page-fit"},
          "Placed rectangles exceed the usable dimensions on page "..page_index)
      end
    end
  end
  for _,f in ipairs(flow_list) do
    local source,target=geometry.node_rects_by_id[f.source],geometry.node_rects_by_id[f.target]
    local same_row=node_page[f.source]==node_page[f.target]
      and node_row[f.source]==node_row[f.target]
    local sign=1
    for _,axis in ipairs(geometry.row_axes) do
      if axis.page_index==node_page[f.source] and axis.row_index==node_row[f.source] then
        sign=axis.direction_sign;break
      end
    end
    local source_side,target_side
    if f.kind=="feedback" then
      source_side,target_side="outer","outer"
    elseif same_row then
      source_side,target_side=(spec.options.direction=="down" and (sign==1 and "bottom" or "top")
        or (sign==1 and "right" or "left")),
        (spec.options.direction=="down" and (sign==1 and "top" or "bottom")
        or (sign==1 and "left" or "right"))
    else
      source_side,target_side=(spec.options.direction=="down" and "right" or "bottom"),
        (spec.options.direction=="down" and "left" or "top")
    end
    geometry.provisional_ports[#geometry.provisional_ports+1]={flow_id=f.id,
      source_id=f.source,target_id=f.target,source_side=source_side,target_side=target_side,
      source_page=node_page[f.source],target_page=node_page[f.target]}
    for _,s in ipairs(spec.structures or {}) do
      local members={}
      for _,id in ipairs(s.member_ids) do members[id]=true end
      local member_id,role,side
      if members[f.source] and not members[f.target] then
        member_id,role,side=f.source,"out",source_side
      elseif members[f.target] and not members[f.source] then
        member_id,role,side=f.target,"in",target_side
      end
      if member_id then
        geometry.group_boundary_ports[#geometry.group_boundary_ports+1]={
          structure_id=s.id,flow_id=f.id,member_id=member_id,role=role,
          candidate_side=side,page_index=node_page[member_id]}
      end
    end
    if f.kind=="forward" and same_row then
      local sr,tr
      for _,axis in ipairs(geometry.row_axes) do
        if axis.page_index==node_page[f.source] and axis.row_index==node_row[f.source] then
          sr,tr=axis.layer_by_node_id[f.source],axis.layer_by_node_id[f.target];break
        end
      end
      if sr and tr and tr-sr>1 then
        geometry.reserved_channels[#geometry.reserved_channels+1]={kind="long-edge",
          flow_id=f.id,page_index=node_page[f.source],from_layer=sr,to_layer=tr,
          width_sp=route_gap}
      end
    end
  end
  for _,n in ipairs(spec.nodes or {}) do
    if n.kind=="join" then
      geometry.reserved_channels[#geometry.reserved_channels+1]={kind="join",
        node_id=n.id,page_index=node_page[n.id],width_sp=route_gap}
    end
  end
  geometry.spacing_stats.crossings_before=crossings_before
  geometry.spacing_stats.crossings_after=crossings_after
  geometry.spacing_stats.gap_variance_sp2=variance(gaps)
  geometry.spacing_stats.gap_count=#gaps
  return geometry
end

return M
