-- Run with: texlua tests/run_analysis.lua
local model = dofile("tikzffbd-model.lua")
local analysis = dofile("tikzffbd-analysis.lua")
local count = 0
local function check(ok, message) assert(ok, message); count = count + 1 end
local function builder(name)
  return model.new{environment_id=name}
end
local function node(b, id)
  b:add_function{id=id, text_ref="@text/" .. id}
end
local function flow(b, a, z)
  b:add_flow{source=a, target=z}
end
local function analyze(b)
  local spec, errors = b:seal()
  check(spec ~= nil, errors and errors[1].message)
  return analysis.analyze(spec), spec
end
local function regions_of_kind(result, kind)
  local out = {}
  for _, r in pairs(result.regions_by_id) do if r.kind == kind then out[#out+1] = r end end
  table.sort(out, function(a,b) return a.id < b.id end)
  return out
end
local function contains(a, id)
  for _, v in ipairs(a) do if v == id then return true end end
  return false
end

local b = builder("basic-chain")
for _, id in ipairs({"s","a","b","t"}) do node(b,id) end
flow(b,"s","a"); flow(b,"a","b"); flow(b,"b","t")
local r = analyze(b)
check(#regions_of_kind(r,"parallel") == 0, "chain has no parallel")
check(#r.regions_by_id[r.root].ordered_children == 4, "chain sequence order")
check(r.regions_by_id[r.root].member_ids[1] == "s", "chain entry")

local function parallel_case(name, order)
  local x = builder(name)
  for _, id in ipairs({"s","a","b","b2","c","t"}) do node(x,id) end
  local split = x:add_branch{source_id="s", logic="or", arms=order or {"b","a","c"}}
  flow(x,"b","b2")
  local join = x:add_join{arms={"a","b2","c"}, target_id="t", logic="or"}
  x:add_feedback{source="t",target="s"}
  return analyze(x), split, join
end
r = parallel_case("branches-15-unequal")
local ps = regions_of_kind(r,"parallel")
check(#ps == 1, "multi-arm parallel recognized")
check(#ps[1].ordered_children == 3, "three ordered arms")
check(ps[1].entry_id ~= ps[1].exit_id, "split and join distinct")
local first = r.regions_by_id[ps[1].ordered_children[1]]
check(first.member_ids[1] == "b" and contains(first.member_ids,"b2"), "asymmetric first arm preserved")
check(r.regions_by_id[ps[1].ordered_children[2]].member_ids[1] == "a", "user arm order preserved")
check(#r.feedback_links == 1 and r.feedback_links[1].source_id == "t", "feedback attached")
check(#r.fallback_subgraphs == 0, "unambiguous graph has no fallback")

b = builder("branches-30-unequal")
for _, id in ipairs({"s","a","b","x","y","z","t"}) do node(b,id) end
local outer = b:add_branch{source_id="s",arms={"a","b"}}
local inner = b:add_branch{source_id="a",arms={"x","y"}}
local inner_join = b:add_join{arms={"x","y"},target_id="z"}
local outer_join = b:add_join{arms={"z","b"},target_id="t"}
r = analyze(b)
ps = regions_of_kind(r,"parallel")
check(#ps == 2, "nested parallels recognized")
local outer_region, inner_region
for _, p in ipairs(ps) do
  if p.split_id == outer then outer_region=p else inner_region=p end
end
check(outer_region and inner_region and outer_region.exit_id == outer_join, "outer pairing")
check(inner_region.exit_id == inner_join, "inner pairing")
local arm = r.regions_by_id[outer_region.ordered_children[1]]
check(contains(arm.ordered_children,inner_region.id), "inner region nested inside first arm")

b = builder("structures-feedback")
for _, id in ipairs({"s","a","b","t"}) do node(b,id) end
flow(b,"s","a"); flow(b,"a","b"); flow(b,"b","t")
b:add_structure{id="grp",member_ids={"b","a"},input_member_ids={"a"},output_member_ids={"b"}}
b:add_feedback{source="t",target="a"}
r = analyze(b)
local group = regions_of_kind(r,"group")[1]
check(group.structure_id == "grp" and group.member_ids[1] == "b", "group declaration order retained")
check(group.input_member_ids[1] == "a" and group.output_member_ids[1] == "b", "boundary members retained")
check(group.incoming_boundary_flows[1].member_id == "a" and
  group.outgoing_boundary_flows[1].member_id == "b", "cross-boundary flow endpoints retained")
check(contains(r.feedback_links[1].target_region_ids,group.id), "feedback endpoint attached to group")

b = builder("ambiguous-join")
for _, id in ipairs({"s","a","b","c","t"}) do node(b,id) end
local split = b:add_branch{source_id="s",arms={"a","b"}}
flow(b,"a","c")
b:add_join{arms={"c","b"},target_id="t"}
flow(b,"a","t") -- bypass of the declared join makes pairing ambiguous
r = analyze(b)
check(#regions_of_kind(r,"parallel") == 0, "bypass cannot form a parallel region")
check(#r.ambiguities == 1 and #r.fallback_subgraphs == 1, "ambiguity and generic fallback")
check(r.fallback_subgraphs[1].member_ids[1] == split, "fallback keeps layered order")
check(#r.fallback_subgraphs[1].flow_ids > 0, "fallback keeps forward flow IDs")

b = builder("no-pair")
for _, id in ipairs({"s","a","b","t"}) do node(b,id) end
b:add_branch{source_id="s",arms={"a","b"}}
flow(b,"a","t"); flow(b,"b","t")
r = analyze(b)
check(#r.ambiguities == 1 and r.ambiguities[1].reason == "no-common-join", "plain merge is not invented join")

local r2 = parallel_case("branches-15-unequal")
local p2 = regions_of_kind(r2,"parallel")[1]
check(table.concat(r.regions_by_id[r.root].member_ids,",") ~= "", "root covers graph")
check(p2.entry_id == regions_of_kind(r2,"parallel")[1].entry_id, "repeat deterministic")

local function equivalent(reverse)
  local x = builder("equivalent")
  local ids = reverse and {"t","b","a","s"} or {"s","a","b","t"}
  for _, id in ipairs(ids) do node(x,id) end
  x:add_branch{source_id="s", arms={"b","a"}}
  x:add_join{arms={"a","b"},target_id="t"}
  return analyze(x)
end
local eq1, eq2 = equivalent(false), equivalent(true)
local e1, e2 = regions_of_kind(eq1,"parallel")[1], regions_of_kind(eq2,"parallel")[1]
check(#regions_of_kind(eq1,"parallel") == 1 and #regions_of_kind(eq2,"parallel") == 1,
  "declaration reordering preserves pairing")
for i, expected in ipairs({"b","a"}) do
  check(eq1.regions_by_id[e1.ordered_children[i]].member_ids[1] == expected and
    eq2.regions_by_id[e2.ordered_children[i]].member_ids[1] == expected,
    "equivalent declaration order retains explicit arm order " .. i)
end

b = builder("unpaired-join")
for _, id in ipairs({"a","b","t"}) do node(b,id) end
b:add_join{arms={"a","b"},target_id="t"}
r = analyze(b)
check(#r.fallback_subgraphs == 1 and r.ambiguities[1].reason == "unpaired-join",
  "join without branch has generic fallback")
print("analysis: " .. count .. " assertions passed")
