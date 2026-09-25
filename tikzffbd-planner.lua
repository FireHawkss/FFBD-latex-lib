-- Bounded semantic row/page planning. Geometry and routing remain downstream.
local constraints_api = require("tikzffbd-constraints")
local M = {}
local BEAM, CANDIDATES, EXPANSIONS = 12, 8, 4096

local function diagnostic(code, ids, cids, message, actions, severity)
  return {code=code, severity=severity or "error", object_ids=ids or {},
    constraint_ids=cids or {}, message=message, suggested_actions=actions or {}}
end
local function copy(t)
  local out = {}
  for i, v in ipairs(t or {}) do out[i] = v end
  return out
end
local function finite_positive(n)
  return type(n) == "number" and n == n and n > 0 and n < math.huge
end
local function marker_key(id)
  return id:gsub("^@", ""):gsub("/", "-")
end
local function sort_trim(bucket, limit)
  table.sort(bucket, function(a,b)
    if a.score ~= b.score then return a.score < b.score end
    return a.signature < b.signature
  end)
  while #bucket > limit do table.remove(bucket) end
end

-- Returns up to eight ranked candidates, or nil plus diagnostics. The input
-- regions are expected to come from analysis.analyze on a sealed Spec.
function M.plan(regions, metrics, constraints, frame)
  if type(regions) ~= "table" or type(metrics) ~= "table" or type(frame) ~= "table"
      or regions.environment_id ~= metrics.environment_id
      or regions.environment_id ~= frame.environment_id then
    return nil, {diagnostic("environment-mismatch", {}, {},
      "Regions, Metrics, and Frame must belong to one environment",
      {"Plan each ffbd environment separately"})}
  end
  if not finite_positive(frame.scale) or not finite_positive(frame.content_width_sp)
      or not finite_positive(frame.content_height_sp) or
      (frame.direction ~= "right" and frame.direction ~= "down") then
    return nil, {diagnostic("invalid-frame", {}, {}, "Invalid planning frame",
      {"Supply positive content dimensions and explicit scale"})}
  end
  local order = regions.forward_order or (regions.regions_by_id[regions.root] or {}).member_ids or {}
  local n = #order
  local node_index, owner, sizes = {}, {}, {}
  local root = regions.regions_by_id[regions.root]
  for i, id in ipairs(order) do node_index[id] = i end
  for _, rid in ipairs(root.ordered_children or {}) do
    for _, id in ipairs(regions.regions_by_id[rid].member_ids) do owner[id] = rid end
  end
  -- A fallback is an overlay: it records the general layered subgraph, but
  -- never creates an inferred parallel relationship.
  local fallback = {}
  for _, g in ipairs(regions.fallback_subgraphs or {}) do
    for _, id in ipairs(g.member_ids) do fallback[id] = g.region_id end
  end
  local primary = frame.direction == "right" and "width_sp" or "height_sp"
  local cross = frame.direction == "right" and "height_sp" or "width_sp"
  local primary_limit = (frame.direction == "right" and frame.content_width_sp
    or frame.content_height_sp) / frame.scale
  local cross_limit = (frame.direction == "right" and frame.content_height_sp
    or frame.content_width_sp) / frame.scale
  local widths = {}
  for i, id in ipairs(order) do
    local m = metrics.by_node_id and metrics.by_node_id[id]
    if not m or not finite_positive(m.width_sp) or not finite_positive(m.height_sp) then
      return nil, {diagnostic("missing-metrics", {id}, {},
        "Node " .. id .. " has no positive measured footprint", {"Measure all node styles before planning"})}
    end
    widths[#widths+1] = m[primary]
    sizes[i] = {primary=m[primary], cross=m[cross]}
  end
  table.sort(widths)
  local median = widths[math.floor((#widths+1)/2)] or 655360
  local style = metrics.style_clearances or {}
  local route_gap = math.max(math.floor(median * 0.30 + 0.5),
    style.route_gap_sp or 0, 1)
  local label_extent,label_cross=0,0
  local ranks={}
  for _,id in ipairs(order) do
    ranks[id]=ranks[id] or 1
    for _,flow in ipairs(regions.flows or {}) do
      if flow.kind=="forward" and flow.source==id then
        ranks[flow.target]=math.max(ranks[flow.target] or 1,ranks[id]+1)
      end
    end
  end
  for _,flow in ipairs(regions.flows or {}) do
    local size=flow.condition_ref and (metrics.by_text_ref or {})[flow.condition_ref]
    if size and flow.kind=="forward" and ranks[flow.target]==ranks[flow.source]+1 then
      label_extent=math.max(label_extent,size[primary]+(primary=="height_sp" and (size.depth_sp or 0) or 0))
      label_cross=math.max(label_cross,size[cross]+(cross=="height_sp" and (size.depth_sp or 0) or 0))
    end
  end
  route_gap=math.max(route_gap,math.ceil(primary=="height_sp" and label_extent*2
    or math.min(label_extent,median/2)*1.5))
  local row_gap = math.max(math.floor(median * 0.40 + 0.5),
    style.row_gap_sp or 0, math.ceil(label_cross*2), 1)
  -- Analysis carries no annotation owners. Metrics may supply them as an
  -- additive map; absent ownership uses a conservative global allowance.
  local global_note, global_note_primary = 0, 0
  for _, m in pairs(metrics.by_annotation_id or {}) do
    if finite_positive(m[cross]) then global_note = math.max(global_note, m[cross]) end
    if finite_positive(m[primary]) then global_note_primary=math.max(global_note_primary,m[primary]) end
  end
  local group_header_cross, group_header_primary=0,0
  for _,m in pairs(metrics.by_structure_id or {}) do
    if finite_positive(m.header_height_sp) then
      group_header_cross=math.max(group_header_cross,m.header_height_sp)
    end
    if finite_positive(m.header_width_sp) then
      group_header_primary=math.max(group_header_primary,m.header_width_sp)
    end
  end
  if next(metrics.by_structure_id or {}) then
    row_gap=math.max(row_gap,route_gap+2*group_header_cross+2*(global_note+route_gap))
  end
  local note_allowance = math.floor(math.max(global_note,group_header_cross)*0.5+0.5)
  local label_primary_allowance=math.floor(math.max(global_note_primary,group_header_primary)*0.25+0.5)
  local hard_columns, soft_columns, breaks, groups = math.huge, nil, {}, {}
  local multipage = false
  for _, c in ipairs(constraints or {}) do
    if c.kind == "max-columns" then
      if c.strength == "hard" then hard_columns = math.min(hard_columns, c.value)
      else soft_columns = math.min(soft_columns or math.huge, c.value) end
    elseif c.kind == "row-break" then breaks[node_index[c.target_ids[1]]] = c
    elseif c.kind == "keep-together" then
      local rid = "@region/group/" .. c.target_ids[1]
      local region = regions.regions_by_id[rid]
      if region then groups[#groups+1] = {constraint=c, members=region.member_ids} end
    elseif c.kind == "page-fit" and c.strength == "hard" then multipage = true end
  end
  local function cut_splits_group(at, kind)
    for _, g in ipairs(groups) do
      if g.constraint.value == kind and g.constraint.strength == "hard" then
        local lo, hi = math.huge, 0
        for _, id in ipairs(g.members) do
          local i = node_index[id]
          if i then lo=math.min(lo,i); hi=math.max(hi,i) end
        end
        if lo <= at and at < hi then return g.constraint end
      end
    end
  end
  local function cut_cost(at)
    if at == n then return 0 end
    for _,rid in ipairs(regions.group_region_ids or {}) do
      local lo,hi=math.huge,0
      for _,id in ipairs(regions.regions_by_id[rid].member_ids) do
        lo=math.min(lo,node_index[id]);hi=math.max(hi,node_index[id])
      end
      if lo<=at and at<hi then return 40 end
    end
    local a, b = owner[order[at]], owner[order[at+1]]
    if a == b and a and regions.regions_by_id[a].kind == "parallel" then return 30 end
    if fallback[order[at]] and fallback[order[at]] == fallback[order[at+1]] then return 7 end
    return 0
  end
  local expansion_budget=math.max(EXPANSIONS,n*BEAM*16)
  local stats = {budget=expansion_budget, expanded=0, pruned={width=0, columns=0,
    hard_break=0, keep_together=0, budget=0, beam=0, page=0}}
  local dp = {[0]={{rows={}, score=0, signature=""}}}
  for start = 1, n do
    local previous = dp[start-1] or {}
    for _, state in ipairs(previous) do
      local used, high = 0, 0
      for stop = start, n do
        if stats.expanded >= expansion_budget then stats.pruned.budget=stats.pruned.budget+1; break end
        stats.expanded = stats.expanded + 1
        local slots = stop-start+1
        if slots > hard_columns then stats.pruned.columns=stats.pruned.columns+1; break end
        used = used + sizes[stop].primary + (slots > 1 and route_gap or 0)
        high = math.max(high, sizes[stop].cross)
        if used+label_primary_allowance > primary_limit then
          stats.pruned.width=stats.pruned.width+1; break
        end
        local impossible = false
        for i=start,stop-1 do
          if breaks[i] and breaks[i].strength == "hard" then impossible=true; break end
        end
        if impossible then stats.pruned.hard_break=stats.pruned.hard_break+1; break end
        local group = cut_splits_group(stop, "row")
        if group then stats.pruned.keep_together=stats.pruned.keep_together+1
        else
          local ids, rids, seen = {}, {}, {}
          for i=start,stop do
            local id=order[i]; ids[#ids+1]=id
            local rid=fallback[id] or owner[id]
            if rid and not seen[rid] then seen[rid]=true; rids[#rids+1]=rid end
          end
          local forced = breaks[stop] and breaks[stop].strength == "hard"
            and {breaks[stop].id} or {}
          local preferred = breaks[stop] and breaks[stop].strength ~= "hard"
            and {breaks[stop].id} or {}
          local local_rank,heights={},{}
          for _,id in ipairs(ids) do
            local rank=1
            for _,flow in ipairs(regions.flows or {}) do
              if flow.kind=="forward" and flow.target==id and local_rank[flow.source] then
                rank=math.max(rank,local_rank[flow.source]+1)
              end
            end
            local_rank[id]=rank
            heights[rank]=(heights[rank] and heights[rank]+math.max(route_gap,style.branch_gap_sp or 0) or 0)
              +metrics.by_node_id[id][cross]
          end
          local actual_cross=0;for _,height in pairs(heights) do actual_cross=math.max(actual_cross,height) end
          local row = {index=#state.rows+1, direction_sign=(#state.rows%2==0) and 1 or -1,
            ordered_region_ids=rids, ordered_node_ids=ids,
            forced_break_ids=forced, preferred_break_ids=preferred,
            estimated_primary_sp=math.floor(used+label_primary_allowance+0.5),
            estimated_cross_sp=math.floor(actual_cross+note_allowance+0.5)}
          local missed_soft = 0
          for i=start,stop-1 do if breaks[i] and breaks[i].strength ~= "hard" then missed_soft=missed_soft+1 end end
          local column_cost = soft_columns and math.max(0,slots-soft_columns) or 0
          local unused = (primary_limit-used)/primary_limit
          local next_state={rows=copy(state.rows),
            score=state.score+cut_cost(stop)+missed_soft*10+column_cost*8+unused*2,
            signature=state.signature .. string.format("%04d,",stop)}
          next_state.rows[#next_state.rows+1]=row
          if not multipage or row.estimated_cross_sp+2*row_gap<=cross_limit then
          local bucket=dp[stop] or {}; dp[stop]=bucket
          bucket[#bucket+1]=next_state
          if #bucket > BEAM then stats.pruned.beam=stats.pruned.beam+1; sort_trim(bucket,BEAM) end
          else stats.pruned.page=stats.pruned.page+1 end
        end
      end
    end
  end
  if n > 0 and not dp[n] then
    local ids = {}
    for _, id in ipairs(order) do ids[#ids+1]=id end
    local hard_ids={}
    for _,c in ipairs(constraints or {}) do
      if c.strength=="hard" and (c.kind=="max-columns" or c.kind=="row-break"
          or c.kind=="keep-together") then hard_ids[#hard_ids+1]=c.id end
    end
    return nil, {diagnostic("no-feasible-rows", ids, hard_ids,
      "No row plan fits the measured blocks, regions, and hard constraints at explicit scale " .. frame.scale,
      {"Use landscape", "Enable multipage", "Increase max-columns where appropriate",
        "Choose a smaller explicit scale", "Relax a conflicting hard break or group"})}
  end
  local function boundary_cost(last_node)
    return cut_cost(last_node) * 3
  end
  local function add_continuations(pages)
    local node_page = {}
    for pi, page in ipairs(pages) do
      for _, row in ipairs(page.rows) do
        for _, id in ipairs(row.ordered_node_ids) do node_page[id]=pi end
      end
      page.continuation_ids={}; page.continuation_markers={}
    end
    for flow_number, flow in ipairs(regions.flows or {}) do
      local source_page, target_page = node_page[flow.source], node_page[flow.target]
      if source_page and target_page and source_page ~= target_page then
        local first, last = math.min(source_page,target_page), math.max(source_page,target_page)
        for pi=first,last-1 do
          local ordinal=pi-first+1
          local stem="@continuation/" .. marker_key(flow.id) .. "/" .. ordinal
          local out_id, in_id=stem .. "/out", stem .. "/in"
          local text_ref="@text/continuation/" .. marker_key(flow.id) .. "/" .. ordinal
          local earlier_is_source=source_page<target_page
          local earlier={id=earlier_is_source and out_id or in_id,
            counterpart_id=earlier_is_source and in_id or out_id,
            semantic_flow_id=flow.id,role=earlier_is_source and "out" or "in",
            text_ref=text_ref,label="Continuation " .. flow_number .. "." .. ordinal}
          local later={id=earlier.counterpart_id,counterpart_id=earlier.id,
            semantic_flow_id=flow.id,role=earlier_is_source and "in" or "out",
            text_ref=text_ref,label="Continuation " .. flow_number .. "." .. ordinal}
          local a,b=pages[pi],pages[pi+1]
          a.continuation_ids[#a.continuation_ids+1]=earlier.id
          b.continuation_ids[#b.continuation_ids+1]=later.id
          a.continuation_markers[#a.continuation_markers+1]=earlier
          b.continuation_markers[#b.continuation_markers+1]=later
        end
      end
    end
  end
  local function paginate(rows)
    if not multipage then return {{rows=rows,continuation_ids={}}},0 end
    local m=#rows; local best={[m+1]={cost=0,pages={}}}
    for i=m,1,-1 do
      local occupied=0
      for j=i,m do
        occupied=occupied+rows[j].estimated_cross_sp+(j>i and row_gap or 0)
        if occupied+2*row_gap > cross_limit then stats.pruned.page=stats.pruned.page+1; break end
        local tail=best[j+1]
        if tail then
          local last=rows[j].ordered_node_ids[#rows[j].ordered_node_ids]
          local split=cut_splits_group(node_index[last],"page")
          if not split or j==m then
            local cost=tail.cost+(j<m and 10+boundary_cost(node_index[last]) or 0)
              +(cross_limit-occupied)/cross_limit
            if not best[i] or cost<best[i].cost then
              local pages={{rows={},continuation_ids={}}}
              for k=i,j do
                local row={}
                for key,value in pairs(rows[k]) do row[key]=value end
                row.index=k-i+1; row.direction_sign=((k-i)%2==0) and 1 or -1
                pages[1].rows[#pages[1].rows+1]=row
              end
              for _, p in ipairs(tail.pages) do pages[#pages+1]=p end
              best[i]={cost=cost,pages=pages}
            end
          else stats.pruned.keep_together=stats.pruned.keep_together+1 end
        end
      end
    end
    if not best[1] then return nil end
    return best[1].pages,best[1].cost
  end
  local candidates={}
  for _, state in ipairs(dp[n] or {{rows={},score=0,signature=""}}) do
    local pages,page_cost=paginate(state.rows)
    if pages then
      add_continuations(pages)
      local plan={environment_id=regions.environment_id,pages=pages,
        estimated_costs={structural=state.score,page=page_cost,total=state.score+page_cost,
          search_budget=expansion_budget,candidates_evaluated=stats.expanded,
          budget_exhausted=stats.expanded>=expansion_budget,pruned=stats.pruned,
          route_gap_sp=route_gap,row_gap_sp=row_gap,
          usable_primary_sp=math.floor(primary_limit),usable_cross_sp=math.floor(cross_limit),
          note_allowance_sp=note_allowance,label_primary_allowance_sp=label_primary_allowance}}
      local proxy={structures={}}
      for _, rid in ipairs(regions.group_region_ids or {}) do
        local g=regions.regions_by_id[rid]
        proxy.structures[#proxy.structures+1]={id=g.structure_id,member_ids=g.member_ids}
      end
      local issues,cost=constraints_api.check({plan=plan,spec=proxy,frame=frame,complete=true},constraints or {})
      local valid=true
      for _, d in ipairs(issues) do if d.severity=="error" then valid=false end end
      if valid then
        plan.estimated_costs.strong=cost.strong
        plan.estimated_costs.weak=cost.weak
        plan.estimated_costs.total=plan.estimated_costs.total+cost.strong*100+cost.weak
        if not multipage then
          local height=0
          for _, row in ipairs(state.rows) do
            height=height+row.estimated_cross_sp+row_gap
          end
          if height-row_gap>cross_limit then
            plan.diagnostics={diagnostic("single-page-overflow",{}, {},
              "Estimated unscaled diagram exceeds one page at explicit scale " .. frame.scale,
              {"Use landscape", "Enable multipage", "Choose a smaller explicit scale"},"warning")}
          end
        end
        candidates[#candidates+1]=plan
      end
    end
  end
  table.sort(candidates,function(a,b)
    if a.estimated_costs.total~=b.estimated_costs.total then
      return a.estimated_costs.total<b.estimated_costs.total end
    local function signature(p)
      local out={}
      for _,page in ipairs(p.pages) do
        for _,row in ipairs(page.rows) do out[#out+1]=row.ordered_node_ids[#row.ordered_node_ids] end
        out[#out+1]="|"
      end
      return table.concat(out,",")
    end
    return signature(a)<signature(b)
  end)
  while #candidates>CANDIDATES do table.remove(candidates) end
  if #candidates==0 then
    local hard_ids,object_ids={},{}
    for _,c in ipairs(constraints or {}) do
      if c.strength=="hard" and (c.kind=="page-fit" or c.kind=="keep-together") then
        hard_ids[#hard_ids+1]=c.id
        if c.kind=="keep-together" then object_ids[#object_ids+1]=c.target_ids[1] end
      end
    end
    return nil,{diagnostic("no-feasible-pages",object_ids, hard_ids,
      "No row and page plan satisfies measured size and hard constraints at explicit scale " .. frame.scale,
      {"Use landscape", "Choose a smaller explicit scale", "Relax a hard keep-together rule"})}
  end
  return candidates
end

return M
