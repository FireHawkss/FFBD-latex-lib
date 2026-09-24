-- Semantic FFBD builder. No TeX, layout, or rendering dependencies.
local M = {}
local Builder = {}
Builder.__index = Builder

local function array_copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = array_copy(v) end
  return out
end

local function readonly(value)
  if type(value) ~= "table" then return value end
  local data = {}
  for k, v in pairs(value) do data[k] = readonly(v) end
  return setmetatable({}, {
    __index = data, __len = function() return #data end,
    __pairs = function() return next, data, nil end,
    __newindex = function() error("sealed Spec is immutable", 2) end,
    __metatable = "sealed Spec",
  })
end

local function user_id(s)
  return type(s) == "string" and s:match("^[A-Za-z][A-Za-z0-9._-]*$") ~= nil
end
local function text_ref(s)
  if type(s) ~= "string" or s:sub(1, 6) ~= "@text/" then return false end
  local path = s:sub(7)
  if path == "" or path:find("//", 1, true) or path:sub(-1) == "/" then return false end
  for segment in path:gmatch("[^/]+") do
    if not segment:match("^[A-Za-z0-9._-]+$") then return false end
  end
  return true
end
local positions = { ["top-left"]=true, ["top-center"]=true,
  ["top-right"]=true, left=true, right=true, ["bottom-left"]=true,
  ["bottom-center"]=true, ["bottom-right"]=true }

local function diag(code, ids, message)
  local clean = {}
  for i = 1, 3 do
    if ids and ids[i] ~= nil then clean[#clean + 1] = tostring(ids[i]) end
  end
  return {code=code, severity="error", object_ids=clean,
    constraint_ids={}, message=message, suggested_actions={}}
end
local function err(self, code, ids, message)
  self.errors[#self.errors + 1] = diag(code, ids, message)
end
local function next_index(self)
  if self.sealed then error("builder is sealed", 2) end
  self.index = self.index + 1
  return self.index
end
local function record(self, collection, item)
  self.spec[collection][#self.spec[collection] + 1] = array_copy(item)
end
local function add_node(self, kind, arg)
  local index = next_index(self)
  if type(arg) ~= "table" then err(self, "invalid-declaration", {}, kind .. " requires a record"); return end
  local item = {id=arg.id, index=index, kind=kind, text_ref=arg.text_ref,
    number=arg.number, source={command=kind, declaration_index=index}}
  record(self, "nodes", item)
  return item.id
end
function Builder:add_function(arg) return add_node(self, "function", arg) end
function Builder:add_start(arg) return add_node(self, "start", arg) end
function Builder:add_finish(arg) return add_node(self, "finish", arg) end

local function add_flow(self, index, source, target, kind, condition_ref, side, ordinal, command)
  local id = "@flow/" .. index .. "/" .. ordinal
  record(self, "flows", {id=id, index=index, source=source, target=target,
    kind=kind, condition_ref=condition_ref, preferred_feedback_side=side,
    source_command={command=command, declaration_index=index}})
  return id
end
function Builder:add_flow(arg)
  local index = next_index(self)
  if type(arg) ~= "table" then err(self, "invalid-declaration", {}, "flow requires a record"); return end
  return add_flow(self, index, arg.source, arg.target, "forward", arg.condition_ref, nil, 1, "flow")
end
function Builder:add_feedback(arg)
  local index = next_index(self)
  if type(arg) ~= "table" then err(self, "invalid-declaration", {}, "feedback requires a record"); return end
  return add_flow(self, index, arg.source, arg.target, "feedback", arg.condition_ref,
    arg.preferred_feedback_side, 1, "loopflow")
end
function Builder:add_branch(arg)
  local index = next_index(self)
  if type(arg) ~= "table" then err(self, "invalid-declaration", {}, "branch requires a record"); return end
  local id = "@branch/" .. index
  record(self, "nodes", {id=id, index=index, kind="split", logic=arg.logic or "and",
    source={command="branch", declaration_index=index}})
  add_flow(self, index, arg.source_id, id, "forward", nil, nil, 1, "branch")
  local arms = {}
  if type(arg.arms) ~= "table" then err(self, "invalid-arms", {id}, "branch arms must be an array")
  else
    for i, arm in ipairs(arg.arms) do
      local target = type(arm) == "table" and arm.target or arm
      local condition = type(arm) == "table" and arm.condition_ref or nil
      arms[#arms + 1] = add_flow(self, index, id, target, "forward", condition, nil, i + 1, "branch")
    end
  end
  record(self, "branches", {connector_id=id, source_id=arg.source_id,
    arm_flow_ids_in_user_order=arms, source={command="branch", declaration_index=index}})
  return id
end
function Builder:add_join(arg)
  local index = next_index(self)
  if type(arg) ~= "table" then err(self, "invalid-declaration", {}, "join requires a record"); return end
  local id = "@join/" .. index
  record(self, "nodes", {id=id, index=index, kind="join", logic=arg.logic or "and",
    source={command="join", declaration_index=index}})
  local arms = {}
  if type(arg.arms) ~= "table" then err(self, "invalid-arms", {id}, "join arms must be an array")
  else
    for i, source in ipairs(arg.arms) do
      arms[#arms + 1] = add_flow(self, index, source, id, "forward", nil, nil, i, "join")
    end
  end
  add_flow(self, index, id, arg.target_id, "forward", nil, nil, #arms + 1, "join")
  record(self, "joins", {connector_id=id, target_id=arg.target_id,
    arm_flow_ids_in_user_order=arms, source={command="join", declaration_index=index}})
  return id
end
function Builder:add_structure(arg)
  local index = next_index(self)
  if type(arg) ~= "table" then err(self, "invalid-declaration", {}, "structure requires a record"); return end
  record(self, "structures", {id=arg.id, index=index, member_ids=arg.member_ids,
    type_ref=arg.type_ref, info_ref=arg.info_ref, style=arg.style or "shaded",
    input_member_ids=arg.input_member_ids or {}, output_member_ids=arg.output_member_ids or {},
    source={command="structure", declaration_index=index}})
  return arg.id
end
function Builder:add_annotation(arg)
  local index = next_index(self)
  if type(arg) ~= "table" then err(self, "invalid-declaration", {}, "annotation requires a record"); return end
  record(self, "annotations", {id=arg.id, index=index, owner_id=arg.owner_id,
    type_ref=arg.type_ref, body_ref=arg.body_ref,
    preferred_position=arg.preferred_position,
    position_strength=arg.position_strength,
    source={command="annotation", declaration_index=index}})
  return arg.id
end
function Builder:add_constraint(arg)
  local index = next_index(self)
  if type(arg) ~= "table" then
    err(self, "invalid-declaration", {}, "constraint requires a record")
    return
  end
  local id = arg.id or "@constraint/" .. index
  record(self, "constraints", {id=id, kind=arg.kind, target_ids=arg.target_ids or {},
    value=arg.value, strength=arg.strength or "hard",
    source=arg.source or {command="constraint", declaration_index=index}})
  return id
end

local function unique_list(self, values, owner, name, known)
  if type(values) ~= "table" or #values == 0 then
    err(self, "invalid-members", {owner}, name .. " must be a nonempty array")
    return
  end
  local seen = {}
  for _, id in ipairs(values) do
    if type(id) ~= "string" then err(self, "invalid-id", {owner}, name .. " contains a non-ID")
    else
      if seen[id] then err(self, "duplicate-member", {owner, id}, name .. " repeats " .. id) end
      seen[id] = true
      if known and not known[id] then err(self, "unknown-id", {owner, id}, name .. " names an unknown node") end
    end
  end
end

local function validate(self)
  local spec = self.spec
  local nodes, ids, users = {}, {}, {}
  local function claim(id, owner)
    if not user_id(id) then err(self, "invalid-id", {tostring(id)}, owner .. " requires a user ID")
    elseif users[id] then err(self, "duplicate-id", {id}, "duplicate user ID " .. id)
    else users[id] = true end
  end
  for _, n in ipairs(spec.nodes) do
    if type(n.id) ~= "string" then err(self, "invalid-id", {}, "node ID is missing")
    else
    if n.kind ~= "split" and n.kind ~= "join" then claim(n.id, "node") end
    if nodes[n.id] then err(self, "duplicate-id", {n.id}, "duplicate node ID") end
    nodes[n.id] = n
    end
    if n.kind == "split" or n.kind == "join" then
      if n.logic ~= "and" and n.logic ~= "or" then err(self, "invalid-logic", {n.id}, "connector logic must be and or or") end
    elseif not text_ref(n.text_ref) then err(self, "invalid-text-ref", {n.id}, "node requires @text reference") end
    if n.number ~= nil and type(n.number) ~= "string" and type(n.number) ~= "number" then
      err(self, "invalid-number", {n.id}, "number must be text or number")
    end
  end
  local flows, inbound, outbound = {}, {}, {}
  for _, f in ipairs(spec.flows) do
    flows[f.id] = f
    if f.kind == "forward" and type(f.source) == "string" and type(f.target) == "string" then
      inbound[f.target] = inbound[f.target] or {}
      outbound[f.source] = outbound[f.source] or {}
      inbound[f.target][#inbound[f.target]+1] = f.id
      outbound[f.source][#outbound[f.source]+1] = f.id
    end
    for _, endpoint in ipairs({"source", "target"}) do
      if not nodes[f[endpoint]] then err(self, "unknown-id", {f.id, tostring(f[endpoint])}, "flow " .. endpoint .. " is unknown") end
    end
    if f.condition_ref ~= nil and not text_ref(f.condition_ref) then
      err(self, "invalid-text-ref", {f.id}, "condition must be @text reference")
    end
    if f.kind == "feedback" and f.preferred_feedback_side ~= nil
       and f.preferred_feedback_side ~= "above" and f.preferred_feedback_side ~= "below" then
      err(self, "invalid-side", {f.id}, "feedback side must be above or below")
    end
  end
  for _, b in ipairs(spec.branches) do
    local id = b.connector_id
    if not nodes[b.source_id] then err(self, "unknown-id", {id, tostring(b.source_id)}, "branch source is unknown") end
    unique_list(self, b.arm_flow_ids_in_user_order, id, "branch arms", flows)
    if #b.arm_flow_ids_in_user_order < 2 then err(self, "arm-count", {id}, "branch requires at least two arms") end
    for _, fid in ipairs(b.arm_flow_ids_in_user_order) do
      local f = flows[fid]
      if f and (f.source ~= id or f.kind ~= "forward") then err(self, "connector-flow", {id, fid}, "branch arm must leave split") end
    end
    local incoming = inbound[id] or {}
    local outgoing = outbound[id] or {}
    if #incoming ~= 1 or not flows[incoming[1]] or flows[incoming[1]].source ~= b.source_id
       or #outgoing ~= #b.arm_flow_ids_in_user_order then
      err(self, "connector-flow", {id}, "split must have its declared source and exactly its declared arms")
    end
  end
  for _, j in ipairs(spec.joins) do
    local id = j.connector_id
    if not nodes[j.target_id] then err(self, "unknown-id", {id, tostring(j.target_id)}, "join target is unknown") end
    unique_list(self, j.arm_flow_ids_in_user_order, id, "join arms", flows)
    if #j.arm_flow_ids_in_user_order < 2 then err(self, "arm-count", {id}, "join requires at least two arms") end
    for _, fid in ipairs(j.arm_flow_ids_in_user_order) do
      local f = flows[fid]
      if f and (f.target ~= id or f.kind ~= "forward") then err(self, "connector-flow", {id, fid}, "join arm must enter join") end
    end
    local incoming = inbound[id] or {}
    local outgoing = outbound[id] or {}
    if #incoming ~= #j.arm_flow_ids_in_user_order or #outgoing ~= 1
       or not flows[outgoing[1]] or flows[outgoing[1]].target ~= j.target_id then
      err(self, "connector-flow", {id}, "join must have exactly its declared arms and target")
    end
  end
  local ownership = {}
  for _, s in ipairs(spec.structures) do
    claim(s.id, "structure")
    unique_list(self, s.member_ids, s.id, "structure members", nodes)
    local members = {}
    if type(s.member_ids) == "table" then
      for _, id in ipairs(s.member_ids) do
        if type(id) == "string" then
          members[id] = true
          if ownership[id] then err(self, "duplicate-membership", {s.id, ownership[id], id}, "node belongs to multiple structures") end
          ownership[id] = s.id
        end
      end
    end
    for _, key in ipairs({"input_member_ids", "output_member_ids"}) do
      local seen = {}
      if type(s[key]) ~= "table" then err(self, "invalid-members", {s.id}, key .. " must be an array")
      else for _, id in ipairs(s[key]) do
        if seen[id] then err(self, "duplicate-member", {s.id, id}, key .. " repeats member") end
        if type(id) == "string" then
          seen[id] = true
          if not members[id] then err(self, "invalid-port-member", {s.id, id}, key .. " must name a structure member") end
        end
      end end
    end
    if s.style ~= "shaded" and s.style ~= "dashed" and s.style ~= "plain" then
      err(self, "invalid-style", {s.id}, "unknown structure style")
    end
    for _, key in ipairs({"type_ref", "info_ref"}) do
      if s[key] ~= nil and not text_ref(s[key]) then err(self, "invalid-text-ref", {s.id}, key .. " must be @text reference") end
    end
  end
  for _, a in ipairs(spec.annotations) do
    claim(a.id, "annotation")
    if not nodes[a.owner_id] then err(self, "unknown-id", {a.id, tostring(a.owner_id)}, "annotation owner is unknown") end
    for _, key in ipairs({"type_ref", "body_ref"}) do
      if not text_ref(a[key]) then err(self, "invalid-text-ref", {a.id}, key .. " must be @text reference") end
    end
    if a.preferred_position and not positions[a.preferred_position] then
      err(self, "invalid-position", {a.id}, "unknown annotation position")
    end
    if a.position_strength and a.position_strength ~= "hard" and a.position_strength ~= "soft" then
      err(self, "invalid-strength", {a.id}, "position strength must be hard or soft")
    end
  end
  local adjacency, state = {}, {}
  for _, f in ipairs(spec.flows) do
    if f.kind == "forward" and nodes[f.source] and nodes[f.target] then
      adjacency[f.source] = adjacency[f.source] or {}
      adjacency[f.source][#adjacency[f.source] + 1] = f.target
    end
  end
  local function visit(id)
    state[id] = 1
    for _, target in ipairs(adjacency[id] or {}) do
      if state[target] == 1 then
        err(self, "forward-cycle", {id, target}, "forward flow contains a cycle; use feedback for loops")
      elseif not state[target] then visit(target) end
    end
    state[id] = 2
  end
  for _, n in ipairs(spec.nodes) do
    if type(n.id) == "string" and not state[n.id] then visit(n.id) end
  end
end

function M.new(arg)
  arg = arg or {}
  local env = arg.environment_id
  if type(env) ~= "string" or env == "" then error("environment_id is required", 2) end
  local opts = array_copy(arg.options or {})
  if opts.direction == nil then opts.direction = "right" end
  if opts.scale == nil then opts.scale = 1 end
  if opts.multipage == nil then opts.multipage = false end
  local self = setmetatable({index=0, errors={}, sealed=false,
    spec={environment_id=env, nodes={}, flows={}, branches={}, joins={},
      structures={}, annotations={}, constraints={}, options=opts}}, Builder)
  return self
end
function Builder:seal()
  if self.sealed then error("builder is sealed", 2) end
  self.sealed = true
  local o = self.spec.options
  if o.direction ~= "right" and o.direction ~= "down" then err(self, "invalid-option", {}, "direction must be right or down") end
  if type(o.scale) ~= "number" or o.scale ~= o.scale or o.scale == math.huge or o.scale == -math.huge or o.scale <= 0 then
    err(self, "invalid-option", {}, "scale must be a positive finite number")
  end
  if type(o.multipage) ~= "boolean" then err(self, "invalid-option", {}, "multipage must be boolean") end
  validate(self)
  if #self.errors > 0 then return nil, readonly(self.errors) end
  return readonly(self.spec)
end
function M.inspect(spec) return array_copy(spec) end
return M
