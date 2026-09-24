-- TeX input and measurement boundary. Raw TeX tokens remain in TeX.
local model = require("tikzffbd-model")
local constraints = require("tikzffbd-constraints")
local M = {last = nil}
local current

local function list(s)
  local out = {}
  for item in (s or ""):gmatch("[^,]+") do
    item = item:match("^%s*(.-)%s*$")
    if item ~= "" then out[#out + 1] = item end
  end
  return out
end

local function dimension(n)
  n = tonumber(n)
  assert(n and n == math.floor(n) and n >= 0, "invalid TeX sp dimension")
  return n
end

function M.begin(id, direction, theme, scale, multipage, columns, strength, annotation_side)
  assert(current == nil, "nested ffbd environment")
  current = {id=id, builder=model.new{environment_id=id, options={
    direction=direction, theme=theme, scale=tonumber(scale),
    multipage=multipage == "true", max_columns=tonumber(columns),
    max_columns_strength=strength, annotations=annotation_side}},
    metrics={environment_id=id, by_text_ref={}, by_node_id={},
      by_annotation_id={}, by_structure_id={}, style_clearances={}},
    text_refs={}, annotations={}, structures={}}
end

function M.text(ref, width, height, depth)
  assert(current and not current.text_refs[ref], "duplicate or out-of-environment text reference")
  local suffix = ref:sub(#("@text/" .. current.id .. "/") + 1)
  assert(ref:sub(1, #("@text/" .. current.id .. "/")) == "@text/" .. current.id .. "/"
    and suffix:match("^%d+$"), "text reference belongs to another environment")
  current.text_refs[ref] = true
  current.metrics.by_text_ref[ref] = {width_sp=dimension(width),
    height_sp=dimension(height), depth_sp=dimension(depth)}
end

local function check_ref(ref)
  if ref ~= "" then assert(current.text_refs[ref], "unregistered text reference " .. ref) end
  return ref ~= "" and ref or nil
end
function M.node(kind, id, ref, number)
  local arg = {id=id, text_ref=check_ref(ref)}
  if number ~= "" then arg.number = number end
  current.builder["add_" .. kind](current.builder, arg)
end
function M.flow(source, target, condition)
  current.builder:add_flow{source=source,target=target,condition_ref=check_ref(condition)}
end
function M.feedback(source, target, condition, side)
  current.builder:add_feedback{source=source,target=target,
    condition_ref=check_ref(condition),preferred_feedback_side=side ~= "" and side or nil}
end
function M.branch(source, logic, arms)
  current.builder:add_branch{source_id=source,logic=logic,arms=arms}
end
function M.branch_begin(source, logic)
  current.pending_branch = {source_id=source,logic=logic,arms={}}
end
function M.branch_arm(target, condition)
  assert(current.pending_branch, "branch arm without branch")
  current.pending_branch.arms[#current.pending_branch.arms + 1] =
    {target=target,condition_ref=check_ref(condition)}
end
function M.branch_end()
  current.last_connector = current.builder:add_branch(assert(current.pending_branch))
  current.pending_branch = nil
end
function M.join(sources, target, logic)
  current.last_connector = current.builder:add_join{arms=list(sources),target_id=target,logic=logic}
end
function M.connector_metrics(width, height)
  M.node_metrics(assert(current.last_connector), width, height)
end
function M.structure(id, members, inputs, outputs, type_ref, info_ref, style)
  current.builder:add_structure{id=id,member_ids=list(members),input_member_ids=list(inputs),
    output_member_ids=list(outputs),type_ref=check_ref(type_ref),
    info_ref=check_ref(info_ref),style=style}
  current.structures[id] = {type_ref=type_ref,info_ref=info_ref}
end
function M.annotation(id, owner, type_ref, body_ref, position, strength)
  current.builder:add_annotation{id=id,owner_id=owner,type_ref=check_ref(type_ref),
    body_ref=check_ref(body_ref),preferred_position=position ~= "" and position or nil,
    position_strength=strength ~= "" and strength or nil}
  current.annotations[id] = true
end
function M.row_break(owner, strength)
  assert(strength == "hard" or strength == "soft", "endrow strength must be hard or soft")
  local spec = current.builder.spec
  local index = current.builder.index + 1
  current.builder.index = index
  spec.constraints[#spec.constraints + 1] = {id="@constraint/" .. index,
    kind="row-break",target_ids={owner},value=true,
    strength=strength == "soft" and "strong" or "hard",
    source={command="endrow",declaration_index=index}}
end
function M.node_metrics(id, width, height)
  current.metrics.by_node_id[id] = {width_sp=dimension(width),height_sp=dimension(height)}
end
function M.annotation_metrics(id, width, height)
  current.metrics.by_annotation_id[id] = {width_sp=dimension(width),height_sp=dimension(height)}
end
function M.structure_metrics(id, width, height, info_width)
  current.metrics.by_structure_id[id] = {header_width_sp=dimension(width),
    header_height_sp=dimension(height),info_width_sp=dimension(info_width)}
end
function M.finish(page_width, page_height, content_width, content_height)
  local c = assert(current, "no ffbd environment")
  local spec, errors = c.builder:seal()
  local frame = {environment_id=c.id,page_width_sp=dimension(page_width),
    page_height_sp=dimension(page_height),content_width_sp=dimension(content_width),
    content_height_sp=dimension(content_height),direction=c.builder.spec.options.direction,
    scale=c.builder.spec.options.scale}
  local normalized, constraint_errors
  if spec then normalized, constraint_errors = constraints.normalize(spec, frame) end
  M.last = {Spec=spec, Metrics=c.metrics,
    Frame=frame, Constraints=normalized, diagnostics=constraint_errors or errors}
  current = nil
  if not spec then
    for _, e in ipairs(errors) do tex.error("tikzffbd: " .. e.message) end
  elseif not normalized then
    for _, e in ipairs(constraint_errors) do tex.error("tikzffbd: " .. e.message) end
  end
  return M.last
end
return M
