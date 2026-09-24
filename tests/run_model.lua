-- Run with: texlua tests/run_model.lua
local model = dofile("tikzffbd-model.lua")
local count = 0
local function check(condition, message)
  assert(condition, message)
  count = count + 1
end
local function errors_for(builder)
  local spec, errors = builder:seal()
  check(spec == nil and errors ~= nil, "expected diagnostic list")
  return errors
end
local function has(errors, code)
  for _, error in ipairs(errors) do if error.code == code then return true end end
  return false
end
local function base(env)
  local b = model.new{environment_id=env}
  b:add_start{id="start", text_ref="@text/start"}
  b:add_finish{id="finish", text_ref="@text/finish"}
  return b
end
local function function_node(b, id)
  b:add_function{id=id, text_ref="@text/" .. id}
end

local function all_cases()
  for _, logic in ipairs({"and", "or"}) do
    for arms = 2, 4 do
      local b = base("arms-" .. logic .. arms)
      local targets = {}
      for i = 1, arms do
        local id = "arm" .. i
        function_node(b, id)
        targets[i] = {target=id, condition_ref="@text/condition/" .. i}
      end
      local split = b:add_branch{logic=logic, source_id="start", arms=targets}
      local sources = {}
      for i = arms, 1, -1 do sources[#sources+1] = "arm" .. i end
      local join = b:add_join{logic=logic, arms=sources, target_id="finish"}
      local spec, errors = b:seal()
      check(spec ~= nil, errors and errors[1].message)
      check(spec.nodes[arms+3].id == split and spec.nodes[arms+4].id == join, "connector order")
      check(spec.nodes[arms+3].logic == logic, "split logic")
      check(#spec.branches[1].arm_flow_ids_in_user_order == arms, "branch arm count")
      check(#spec.joins[1].arm_flow_ids_in_user_order == arms, "join arm count")
      for i, flow_id in ipairs(spec.branches[1].arm_flow_ids_in_user_order) do
        local flow
        for _, f in ipairs(spec.flows) do if f.id == flow_id then flow = f end end
        check(flow.target == "arm" .. i and flow.condition_ref == "@text/condition/" .. i, "branch order/condition")
      end
      for i, flow_id in ipairs(spec.joins[1].arm_flow_ids_in_user_order) do
        local flow
        for _, f in ipairs(spec.flows) do if f.id == flow_id then flow = f end end
        check(flow.source == sources[i], "join order")
      end
    end
  end

  local b = base("nested")
  for _, id in ipairs({"outer", "innerA", "innerB", "other"}) do function_node(b, id) end
  local first = b:add_branch{source_id="start", arms={"outer", "other"}}
  b:add_branch{logic="or", source_id="outer", arms={"innerA", "innerB"}}
  b:add_join{arms={"innerB", "innerA"}, target_id="finish"}
  b:add_feedback{source="finish", target="start", condition_ref="@text/retry", preferred_feedback_side="below"}
  local nested, nested_errors = b:seal()
  check(nested ~= nil, nested_errors and nested_errors[1].message)
  check(nested.branches[1].connector_id == first, "nested branch retained")
  check(nested.flows[#nested.flows].kind == "feedback", "feedback retained separately")
  check(nested.flows[#nested.flows].preferred_feedback_side == "below", "feedback side")
  check(pcall(function() nested.nodes[1].id = "changed" end) == false, "node immutable")
  check(pcall(function() nested.flows[1] = {} end) == false, "array immutable")
  check(pcall(function() b:add_flow{source="start", target="finish"} end) == false, "builder sealed")

  b = base("structure")
  function_node(b, "a")
  function_node(b, "c")
  b:add_structure{id="group", member_ids={"c", "a"}, input_member_ids={"a"},
    output_member_ids={"c"}, type_ref="@text/type", info_ref="@text/info", style="dashed"}
  b:add_annotation{id="note", owner_id="a", type_ref="@text/note-type", body_ref="@text/note-body",
    preferred_position="bottom-right", position_strength="soft"}
  local structured = b:seal()
  check(structured.structures[1].member_ids[1] == "c", "member order")
  check(structured.structures[1].input_member_ids[1] == "a", "input port")
  check(structured.annotations[1].preferred_position == "bottom-right", "annotation position")
  check(model.inspect(structured).structures[1].id == "group", "inspection copy")
  local copy = model.inspect(structured)
  copy.nodes[1].id = "different"
  check(structured.nodes[1].id == "start", "inspection cannot mutate sealed Spec")

  b = base("errors")
  function_node(b, "start")
  b:add_flow{source="start", target="missing"}
  b:add_flow{source="finish", target="start"}
  b:add_flow{source="start", target="finish"}
  b:add_structure{id="group", member_ids={"start", "start"}, input_member_ids={"finish"}}
  b:add_annotation{id="note", owner_id="missing", type_ref="@text/type", body_ref="@text/body"}
  local errors = errors_for(b)
  for _, code in ipairs({"duplicate-id", "unknown-id", "duplicate-member", "invalid-port-member", "forward-cycle"}) do
    check(has(errors, code), "missing " .. code)
  end

  b = base("bad-logic")
  b:add_branch{logic="xor", source_id="start", arms={"finish", "missing"}}
  errors = errors_for(b)
  check(has(errors, "invalid-logic") and has(errors, "unknown-id"), "bad connector diagnostic")

  b = base("bad-connector")
  local split = b:add_branch{source_id="start", arms={"finish", "finish"}}
  b:add_flow{source="start", target=split}
  errors = errors_for(b)
  check(has(errors, "connector-flow"), "extra connector flow must fail")

  b = model.new{environment_id="bad-options", options={scale=0, direction="left", multipage="yes"}}
  errors = errors_for(b)
  check(has(errors, "invalid-option"), "invalid options must fail")

  local function deterministic()
    local x = base("stable")
    function_node(x, "a")
    function_node(x, "b")
    x:add_branch{source_id="start", arms={{target="a", condition_ref="@text/x"}, "b"}}
    x:add_join{arms={"a", "b"}, target_id="finish"}
    x:add_feedback{source="finish", target="start"}
    return model.inspect(x:seal())
  end
  local arrays = {nodes=true, flows=true, branches=true, joins=true,
    structures=true, annotations=true, constraints=true,
    member_ids=true, input_member_ids=true, output_member_ids=true,
    arm_flow_ids_in_user_order=true}
  local function encode(value, force_array)
    local kind = type(value)
    if kind == "string" then return string.format("%q", value) end
    if kind ~= "table" then return tostring(value) end
    local is_array = force_array or #value > 0
    local entries = {}
    if is_array then
      for _, item in ipairs(value) do entries[#entries+1] = encode(item) end
      return "[" .. table.concat(entries, ",") .. "]"
    end
    local keys = {}
    for key in pairs(value) do keys[#keys+1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do entries[#entries+1] = encode(key) .. ":" .. encode(value[key], arrays[key]) end
    return "{" .. table.concat(entries, ",") .. "}"
  end
  local one, two = deterministic(), deterministic()
  check(encode(one) == encode(two), "repeat-run serialized Spec differs")
  local file = assert(io.open("/tmp/tikzffbd-model-spec.json", "w"))
  file:write(encode({contract_version=1, environment_id="stable", objects={Spec=one}}), "\n")
  file:close()
end

all_cases()
print(count .. " model assertions passed")
