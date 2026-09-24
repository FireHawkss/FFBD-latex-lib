-- Structural analysis of a sealed Spec. No geometry or page decisions.
local M = {}

local function copy(a)
  local b = {}
  for i, v in ipairs(a or {}) do b[i] = v end
  return b
end
local function set(a)
  local b = {}
  for _, v in ipairs(a or {}) do b[v] = true end
  return b
end
local function same_set(a, b)
  for k in pairs(a) do if not b[k] then return false end end
  for k in pairs(b) do if not a[k] then return false end end
  return true
end
local function subset(a, b)
  for k in pairs(a) do if not b[k] then return false end end
  return true
end

function M.analyze(spec)
  assert(type(spec) == "table" and type(spec.environment_id) == "string", "analyze requires a sealed Spec")
  local nodes, flows, succ, pred, branches, joins = {}, {}, {}, {}, {}, {}
  for _, n in ipairs(spec.nodes) do nodes[n.id] = n; succ[n.id] = {}; pred[n.id] = {} end
  for _, f in ipairs(spec.flows) do
    flows[f.id] = f
    if f.kind == "forward" then
      assert(nodes[f.source] and nodes[f.target], "analyze requires a valid Spec")
      succ[f.source][#succ[f.source]+1] = f.target
      pred[f.target][#pred[f.target]+1] = f.source
    end
  end
  for _, b in ipairs(spec.branches) do branches[b.connector_id] = b end
  for _, j in ipairs(spec.joins) do joins[j.connector_id] = j end

  -- A stable topological order gives generic regions a useful layering order.
  local indegree, ready, topo = {}, {}, {}
  for id in pairs(nodes) do
    indegree[id] = #pred[id]
    if indegree[id] == 0 then ready[#ready+1] = id end
  end
  table.sort(ready)
  while #ready > 0 do
    local id = table.remove(ready, 1)
    topo[#topo+1] = id
    for _, target in ipairs(succ[id]) do
      indegree[target] = indegree[target] - 1
      if indegree[target] == 0 then ready[#ready+1] = target; table.sort(ready) end
    end
  end
  assert(#topo == #spec.nodes, "analyze requires an acyclic forward graph")
  local rank = {}
  for i, id in ipairs(topo) do rank[id] = i end
  local function ordered(members)
    local out = {}
    for _, id in ipairs(topo) do if members[id] then out[#out+1] = id end end
    return out
  end
  local function reachable(start, stop)
    local seen, stack = {}, {start}
    while #stack > 0 do
      local id = table.remove(stack)
      if not seen[id] then
        seen[id] = true
        if id ~= stop then for _, next_id in ipairs(succ[id]) do stack[#stack+1] = next_id end end
      end
    end
    return seen
  end
  local reach = {}
  for id in pairs(nodes) do reach[id] = reachable(id) end

  local candidates, ambiguities = {}, {}
  local function ambiguity(split, reason, join_ids)
    ambiguities[#ambiguities+1] = {split_id=split, candidate_join_ids=join_ids or {}, reason=reason}
  end
  for _, b in ipairs(spec.branches) do
    local split = b.connector_id
    local starts = {}
    for _, fid in ipairs(b.arm_flow_ids_in_user_order) do starts[#starts+1] = flows[fid].target end
    local common = {}
    for id in pairs(joins) do
      local yes = rank[id] > rank[split]
      for _, start in ipairs(starts) do if not reach[start][id] then yes = false end end
      if yes then common[#common+1] = id end
    end
    table.sort(common, function(a, c) return rank[a] < rank[c] end)
    local nearest = {}
    for _, id in ipairs(common) do
      local dominated = false
      for _, other in ipairs(common) do
        if id ~= other and reach[other][id] then dominated = true; break end
      end
      if not dominated then nearest[#nearest+1] = id end
    end
    if #nearest ~= 1 then
      ambiguity(split, #nearest == 0 and "no-common-join" or "multiple-incomparable-joins", nearest)
    else
      local join = nearest[1]
      local arm_sets, all, valid, reason = {}, {[split]=true, [join]=true}, true, nil
      for i, start in ipairs(starts) do
        local before = reachable(start, join)
        before[join] = nil
        arm_sets[i] = before
        for id in pairs(before) do
          if all[id] then valid = false; reason = "arms-overlap" end
          all[id] = true
        end
      end
      if nodes[split].logic ~= nodes[join].logic then valid = false; reason = "connector-logic-mismatch" end
      if #joins[join].arm_flow_ids_in_user_order ~= #starts then valid = false; reason = "join-arm-count-mismatch" end
      for i, arm in ipairs(arm_sets) do
        local hits = 0
        for _, fid in ipairs(joins[join].arm_flow_ids_in_user_order) do
          if arm[flows[fid].source] then hits = hits + 1 end
        end
        if hits ~= 1 then valid = false; reason = "ambiguous-join-arm" end
        for id in pairs(arm) do
          if #succ[id] == 0 then valid = false; reason = "arm-does-not-rejoin" end
          for _, source in ipairs(pred[id]) do
            if not arm[source] and not (id == starts[i] and source == split) then
              valid = false; reason = "external-arm-entry"
            end
          end
          for _, target in ipairs(succ[id]) do
            if not arm[target] and target ~= join then valid = false; reason = "external-arm-exit" end
          end
        end
      end
      if valid then
        candidates[#candidates+1] = {split=split, join=join, arms=arm_sets, members=all,
          starts=starts, branch=b}
      else ambiguity(split, reason, {join}) end
    end
  end

  -- Crossing intervals cannot be represented as nested parallel regions.
  local accepted = {}
  for _, c in ipairs(candidates) do
    local conflict = false
    for _, d in ipairs(candidates) do
      if c ~= d then
        local overlap = false
        for id in pairs(c.members) do if d.members[id] then overlap = true; break end end
        if overlap and not subset(c.members, d.members) and not subset(d.members, c.members) then
          conflict = true
        elseif same_set(c.members, d.members) then conflict = true end
      end
    end
    if conflict then ambiguity(c.split, "crossing-or-duplicate-region", {c.join})
    else accepted[#accepted+1] = c end
  end
  table.sort(accepted, function(a,b) return rank[a.split] < rank[b.split] end)
  local matched_joins, ambiguous_joins = {}, {}
  for _, c in ipairs(accepted) do matched_joins[c.join] = true end
  for _, a in ipairs(ambiguities) do
    for _, id in ipairs(a.candidate_join_ids) do ambiguous_joins[id] = true end
  end
  for _, j in ipairs(spec.joins) do
    if not matched_joins[j.connector_id] and not ambiguous_joins[j.connector_id] then
      ambiguities[#ambiguities+1] = {join_id=j.connector_id,
        candidate_join_ids={j.connector_id}, reason="unpaired-join"}
    end
  end

  local result = {environment_id=spec.environment_id, root="@region/root",
    regions_by_id={}, fallback_subgraphs={}, ambiguities=ambiguities,
    feedback_links={}, forward_order=copy(topo), group_region_ids={}, flows={}}
  for _, f in ipairs(spec.flows) do
    result.flows[#result.flows+1] = {id=f.id, source=f.source,
      target=f.target, kind=f.kind}
  end
  local regions = result.regions_by_id
  local function add(id, kind, members, children, extra)
    local r = {id=id, kind=kind, ordered_children=children or {},
      member_ids=ordered(members), can_keep_together=true}
    if #r.member_ids > 0 then r.entry_id=r.member_ids[1]; r.exit_id=r.member_ids[#r.member_ids] end
    for k,v in pairs(extra or {}) do r[k]=v end
    regions[id] = r
    return id
  end
  local by_split = {}
  for _, c in ipairs(accepted) do by_split[c.split] = c end
  local sequence_serial = 0
  local function sequence(members, preferred_order, id)
    sequence_serial = sequence_serial + 1
    id = id or "@region/sequence/" .. sequence_serial
    local children, emitted = {}, {}
    local scan = preferred_order or ordered(members)
    for _, node in ipairs(scan) do
      if members[node] and not emitted[node] then
        local c = by_split[node]
        if c and subset(c.members, members) then
          local pid = "@region/parallel/" .. node:sub(2):gsub("/", "-")
          local arms = {}
          for i, arm in ipairs(c.arms) do
            local arm_id = pid .. "-arm-" .. i
            arms[#arms+1] = sequence(arm, nil, arm_id)
          end
          add(pid, "parallel", c.members, arms, {entry_id=c.split, exit_id=c.join,
            split_id=c.split, join_id=c.join,
            arm_flow_ids_in_user_order=copy(c.branch.arm_flow_ids_in_user_order)})
          children[#children+1] = pid
          for n in pairs(c.members) do emitted[n] = true end
        else
          local leaf = "@region/node/" .. node:gsub("@", ""):gsub("/", "-")
          add(leaf, "sequence", {[node]=true}, {}, {entry_id=node, exit_id=node})
          children[#children+1] = leaf
          emitted[node] = true
        end
      end
    end
    add(id, "sequence", members, children)
    return id
  end
  local all_nodes = {}
  for id in pairs(nodes) do all_nodes[id]=true end
  sequence(all_nodes, topo, result.root)

  -- Structures retain the author's member and declared boundary order. They
  -- are overlays because a group may cross a parallel region's boundary.
  for _, s in ipairs(spec.structures) do
    local id = "@region/group/" .. s.id
    result.group_region_ids[#result.group_region_ids+1] = id
    local members = set(s.member_ids)
    local inbound, outbound = {}, {}
    for _, f in ipairs(spec.flows) do
      if members[f.target] and not members[f.source] then
        inbound[#inbound+1] = {flow_id=f.id, member_id=f.target, kind=f.kind}
      elseif members[f.source] and not members[f.target] then
        outbound[#outbound+1] = {flow_id=f.id, member_id=f.source, kind=f.kind}
      end
    end
    add(id, "group", members, {}, {structure_id=s.id,
      member_ids=copy(s.member_ids), input_member_ids=copy(s.input_member_ids),
      output_member_ids=copy(s.output_member_ids), style=s.style,
      incoming_boundary_flows=inbound, outgoing_boundary_flows=outbound,
      entry_id=s.input_member_ids[1], exit_id=s.output_member_ids[1]})
  end

  -- An unresolved connector and its reachable forward neighbourhood remain
  -- available to the general layered planner with all original flow IDs.
  for _, a in ipairs(ambiguities) do
    local anchor = a.split_id or a.join_id
    local members = {[anchor]=true}
    if a.split_id then
      for _, next_id in ipairs(succ[anchor]) do
        for id in pairs(reach[next_id]) do members[id]=true end
      end
    else
      for _, previous in ipairs(pred[anchor]) do members[previous]=true end
    end
    local flow_ids = {}
    for _, f in ipairs(spec.flows) do
      if f.kind == "forward" and members[f.source] and members[f.target] then
        flow_ids[#flow_ids+1] = f.id
      end
    end
    local id = "@region/generic/" .. anchor:sub(2):gsub("/", "-")
    add(id, "generic", members, {}, {reason=a.reason, flow_ids=flow_ids,
      entry_id=anchor})
    result.fallback_subgraphs[#result.fallback_subgraphs+1] =
      {region_id=id, member_ids=ordered(members), flow_ids=flow_ids, reason=a.reason}
  end

  local containing = {}
  for id, r in pairs(regions) do
    if r.kind == "parallel" or r.kind == "group" then
      for _, member in ipairs(r.member_ids) do
        containing[member] = containing[member] or {}
        containing[member][#containing[member]+1] = id
      end
    end
  end
  for _, ids in pairs(containing) do table.sort(ids) end
  for _, f in ipairs(spec.flows) do
    if f.kind == "feedback" then
      result.feedback_links[#result.feedback_links+1] = {flow_id=f.id,
        source_id=f.source, target_id=f.target,
        source_region_ids=copy(containing[f.source] or {}),
        target_region_ids=copy(containing[f.target] or {})}
    end
  end
  return result
end

return M
