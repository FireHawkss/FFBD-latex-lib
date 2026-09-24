-- Run with: texlua tests/run_constraints.lua
local model = dofile("tikzffbd-model.lua")
local constraints = dofile("tikzffbd-constraints.lua")
local count = 0
local function check(ok, message) assert(ok, message); count = count + 1 end
local function has(ds, code)
  for _, d in ipairs(ds or {}) do if d.code == code then return d end end
end
local function fixture(options)
  local b = model.new{environment_id="constraints", options=options}
  for _, id in ipairs({"a", "b", "c", "d", "e", "f"}) do
    b:add_function{id=id, text_ref="@text/" .. id}
  end
  b:add_structure{id="group", member_ids={"b", "c", "d"}}
  b:add_annotation{id="note", owner_id="b", type_ref="@text/type",
    body_ref="@text/body", preferred_position="top-left"}
  local spec, errors = b:seal()
  check(spec ~= nil, errors and errors[1].message)
  return model.inspect(spec)
end
local frame = {environment_id="constraints", content_width_sp=1000,
  content_height_sp=1000, page_width_sp=1200, page_height_sp=1200,
  direction="right", scale=1}
local function normalize(spec)
  local result, errors = constraints.normalize(spec, frame)
  check(result ~= nil, errors and errors[1].message)
  return result
end
local function row(nodes) return {ordered_node_ids=nodes, ordered_region_ids={}, forced_break_ids={}} end
local function plan(rows) return {pages={{rows=rows, continuation_ids={}}}} end
local spec = fixture()
local cs = normalize(spec)
check(cs[1].kind == "max-columns" and cs[1].value == 5 and cs[1].strength == "hard", "hard five-column default")
check(cs[2].kind == "annotation-position" and cs[2].strength == "hard", "explicit note position defaults hard")
local candidate = {plan=plan{row{"a","b","c","d","e","f"}}, spec=spec, frame=frame, complete=true}
local violations, costs = constraints.check(candidate, cs)
check(has(violations, "max-columns-exceeded") and costs.strong == 0, "hard columns rejected")
check(violations[1].severity == "error", "hard violation severity")

spec.options.max_columns_strength = "soft"
cs = normalize(spec)
violations, costs = constraints.check(candidate, cs)
check(has(violations, "max-columns-exceeded").severity == "warning" and costs.strong == 1,
  "soft column override has recorded strong cost")
spec.options.max_columns = 0
local invalid, errors = constraints.normalize(spec, frame)
check(invalid == nil and has(errors, "invalid-option"), "invalid column value rejected")
spec.options.max_columns = 5
spec.options.max_columns_strength = "unknown"
invalid, errors = constraints.normalize(spec, frame)
check(invalid == nil and has(errors, "invalid-option"), "invalid strength rejected")
spec.options.max_columns_strength = "hard"

spec.constraints = {{id="@constraint/break", kind="row-break", target_ids={"b"},
  value=true, strength="hard", source={command="endrow",declaration_index=9}},
  {id="@constraint/keep", kind="keep-together", target_ids={"group"},
  value="row", strength="hard", source={command="group",declaration_index=10}}}
invalid, errors = constraints.normalize(spec, frame)
local conflict = has(errors, "hard-conflict")
check(invalid == nil and conflict ~= nil, "row/group conflict found before search")
check(#conflict.constraint_ids == 2 and conflict.object_ids[1] == "group" and
  conflict.message:find("endrow",1,true), "both sources and group named")
local one = conflict.message .. table.concat(conflict.constraint_ids, ",")
local _, repeated = constraints.normalize(spec, frame)
local two = repeated[1].message .. table.concat(repeated[1].constraint_ids, ",")
check(one == two, "repeat diagnostics stable")
spec.constraints[1].strength = "strong"
cs = normalize(spec)
candidate.plan = plan{row{"a","b","c"},row{"d","e","f"}}
violations, costs = constraints.check(candidate, cs)
check(has(violations, "keep-together-violated") ~= nil, "group row split rejected")
check(has(violations, "row-break-violated") ~= nil and costs.strong == 1,
  "soft break deviation cost counted")

spec.constraints = {{id="@constraint/keep", kind="keep-together", target_ids={"group"},
  value="row", strength="hard", source={command="group",declaration_index=10}}}
spec.options.max_columns = 2
invalid, errors = constraints.normalize(spec, frame)
check(invalid == nil and has(errors, "hard-conflict") and
  #has(errors, "hard-conflict").constraint_ids == 2, "column/group conflict names both")
spec.options.max_columns = 5

spec.constraints = {{id="@constraint/other-position", kind="annotation-position",
  target_ids={"note"}, value="bottom-right", strength="hard",
  source={command="constraint",declaration_index=11}}}
invalid, errors = constraints.normalize(spec, frame)
check(invalid == nil and #has(errors, "hard-conflict").constraint_ids == 2,
  "annotation position conflict names both")
spec.constraints = {}
spec.options.multipage = true
cs = normalize(spec)
check(has(cs, "page-fit") == nil and cs[#cs].kind == "page-fit", "multipage creates page-fit constraint")
candidate.scene = {pages={{bounding_rect={x_sp=0,y_sp=0,width_sp=1100,height_sp=900},
  annotations={{id="note",position="bottom-right"}}}}}
violations = constraints.check(candidate, cs)
check(has(violations, "page-fit-violated") and has(violations, "annotation-position-violated"),
  "scene checks page and explicit annotation")
candidate.scene.pages[1].bounding_rect.width_sp = 900
candidate.scene.pages[1].annotations[1].position = "top-left"
violations = constraints.check(candidate, cs)
check(#violations == 0, "valid scene satisfies hard constraints")

spec.constraints = {{id="@constraint/page-group", kind="keep-together",
  target_ids={"group"}, value="page", strength="hard",
  source={command="group",declaration_index=13}}}
cs = normalize(spec)
candidate.plan = {pages={{rows={row{"a","b","c"}}},
  {rows={row{"d","e","f"}}}}}
violations = constraints.check(candidate, cs)
local page_group = has(violations, "keep-together-violated")
check(page_group and #page_group.constraint_ids == 2 and
  page_group.constraint_ids[2] == "@constraint/page-fit", "page/group conflict names both causes")
spec.constraints = {}
cs = normalize(spec)

local partial = {plan=plan{row{"a","b"}}, spec=spec, frame=frame}
violations = constraints.check(partial, cs)
check(#violations == 0, "partial plan defers unknown scene and members")
spec.constraints = {{id="@constraint/bad",kind="row-break",target_ids={"missing"},
  value=true,strength="hard",source={command="endrow",declaration_index=12}}}
invalid, errors = constraints.normalize(spec, frame)
check(invalid == nil and has(errors, "unknown-constraint-target"), "unknown target rejected")

print(count .. " constraint assertions passed")
