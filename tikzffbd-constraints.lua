-- Declarative constraints for plans and solved scenes. No layout decisions here.
local M = {}
local positions = { ["top-left"]=true, ["top-center"]=true,
  ["top-right"]=true, left=true, right=true, ["bottom-left"]=true,
  ["bottom-center"]=true, ["bottom-right"]=true }
local sides = {above=true, below=true, left=true, right=true}
local strengths = {hard=true, strong=true, weak=true}
local kinds = { ["max-columns"]=true, ["row-break"]=true,
  ["keep-together"]=true, ["annotation-position"]=true,
  ["annotation-side"]=true, ["page-fit"]=true }

local function array(t)
  local result = {}
  for i, item in ipairs(t or {}) do result[i] = item end
  return result
end
local function diagnostic(code, ids, constraints, message, actions, severity)
  return {code=code, severity=severity or "error", object_ids=array(ids),
    constraint_ids=array(constraints), message=message, suggested_actions=array(actions)}
end
local function finite(n)
  return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end
local function positive_integer(n)
  return finite(n) and n == math.floor(n) and n >= 1
end
local function constraint_id(id)
  if type(id) ~= "string" or id:sub(1,12) ~= "@constraint/" then return false end
  local path = id:sub(13)
  if path == "" or path:find("//", 1, true) or path:sub(-1) == "/" then return false end
  for segment in path:gmatch("[^/]+") do
    if not segment:match("^[A-Za-z0-9._-]+$") then return false end
  end
  return true
end
local function valid(c)
  if type(c) ~= "table" or not constraint_id(c.id)
      or not kinds[c.kind] or not strengths[c.strength] or type(c.target_ids) ~= "table"
      or type(c.source) ~= "table" or type(c.source.command) ~= "string"
      or c.source.command == "" or not positive_integer(c.source.declaration_index) then return false end
  for _, id in ipairs(c.target_ids) do if type(id) ~= "string" or id == "" then return false end end
  if (c.kind == "max-columns" or c.kind == "annotation-side" or c.kind == "page-fit")
      and #c.target_ids ~= 0 then return false end
  if (c.kind == "row-break" or c.kind == "keep-together" or
      c.kind == "annotation-position") and #c.target_ids ~= 1 then return false end
  if c.kind == "max-columns" then return positive_integer(c.value) end
  if c.kind == "row-break" or c.kind == "page-fit" then return c.value == true end
  if c.kind == "keep-together" then return c.value == "row" or c.value == "page" end
  if c.kind == "annotation-position" then return positions[c.value] == true end
  if c.kind == "annotation-side" then return sides[c.value] == true end
  return false
end
local function copy_constraint(c)
  return {id=c.id, kind=c.kind, target_ids=array(c.target_ids), value=c.value,
    strength=c.strength, source={command=c.source.command,
      option=c.source.option, declaration_index=c.source.declaration_index}}
end
local function source_text(c)
  local s = c.source
  return s.command .. (s.option and " " .. s.option or "") .. " (#" .. s.declaration_index .. ")"
end
local function issue(c, code, ids, message, actions, related)
  local constraint_ids = {c.id}
  local other_sources = {}
  for _, other in ipairs(related or {}) do
    if other.id ~= c.id then
      constraint_ids[#constraint_ids+1] = other.id
      other_sources[#other_sources+1] = source_text(other)
    end
  end
  if #other_sources > 0 then message = message .. "; related: " .. table.concat(other_sources, ", ") end
  return diagnostic(code, ids or c.target_ids, constraint_ids,
    source_text(c) .. ": " .. message, actions)
end
local function same_targets(a, b)
  if #a.target_ids ~= #b.target_ids then return false end
  for i, id in ipairs(a.target_ids) do if id ~= b.target_ids[i] then return false end end
  return true
end

-- Returns normalized records or nil, diagnostics. A missing option receives
-- its documented default; an explicitly invalid option is never replaced.
function M.normalize(spec, frame)
  local diagnostics, out, seen = {}, {}, {}
  if type(spec) ~= "table" or type(frame) ~= "table" or
      spec.environment_id ~= frame.environment_id then
    return nil, {diagnostic("environment-mismatch", {}, {},
      "Spec and Frame must belong to the same environment", {"Compile each ffbd environment separately"})}
  end
  local options = spec.options or {}
  if not positive_integer(frame.content_width_sp) or
      not positive_integer(frame.content_height_sp) or not finite(frame.scale) or frame.scale <= 0 then
    diagnostics[#diagnostics+1] = diagnostic("invalid-frame", {}, {},
      "Frame requires positive content dimensions and positive finite scale",
      {"Correct the page dimensions and explicit scale"})
  end
  local function add(c)
    if not valid(c) or seen[c.id] then
      diagnostics[#diagnostics+1] = diagnostic("invalid-constraint", type(c) == "table" and c.target_ids or {},
        type(c) == "table" and c.id and {c.id} or {}, "Invalid or duplicate constraint record",
        {"Correct the constraint value, source, or ID"})
    else seen[c.id] = true; out[#out+1] = copy_constraint(c) end
  end
  local columns = options.max_columns
  if columns == nil then columns = 5 end
  local column_strength = options.max_columns_strength
  if column_strength == nil then column_strength = "hard" end
  if not positive_integer(columns) or (column_strength ~= "hard" and column_strength ~= "soft") then
    diagnostics[#diagnostics+1] = diagnostic("invalid-option", {}, {},
      "max-columns must be a positive integer and max-columns-strength must be hard or soft",
      {"Set max-columns to a positive integer", "Use max-columns-strength=hard or soft"})
  else
    add{id="@constraint/max-columns", kind="max-columns", target_ids={}, value=columns,
      strength=column_strength == "soft" and "strong" or "hard",
      source={command="ffbd", option="max-columns", declaration_index=1}}
  end
  if options.annotations ~= nil then
    if not sides[options.annotations] then
      diagnostics[#diagnostics+1] = diagnostic("invalid-option", {}, {},
        "annotations must be above, below, left, or right", {"Choose a supported annotations side"})
    else
      add{id="@constraint/annotation-side", kind="annotation-side", target_ids={},
        value=options.annotations, strength="weak",
        source={command="ffbd", option="annotations", declaration_index=1}}
    end
  end
  for _, raw in ipairs(spec.constraints or {}) do add(raw) end
  for _, note in ipairs(spec.annotations or {}) do
    if note.preferred_position ~= nil then
      if not positions[note.preferred_position] or
          (note.position_strength ~= nil and note.position_strength ~= "hard" and note.position_strength ~= "soft") then
        diagnostics[#diagnostics+1] = diagnostic("invalid-option", {note.id}, {},
          "Invalid annotation position or position strength",
          {"Choose one of the eight positions and hard or soft strength"})
      else
        add{id="@constraint/annotation-" .. note.index, kind="annotation-position",
          target_ids={note.id}, value=note.preferred_position,
          strength=note.position_strength == "soft" and "strong" or "hard",
          source={command="annotation", option="position", declaration_index=note.index}}
      end
    elseif note.position_strength ~= nil then
      diagnostics[#diagnostics+1] = diagnostic("invalid-option", {note.id}, {},
        "position-strength requires an explicit position", {"Set position or remove position-strength"})
    end
  end
  if options.multipage == true then
    add{id="@constraint/page-fit", kind="page-fit", target_ids={}, value=true,
      strength="hard", source={command="ffbd", option="multipage", declaration_index=1}}
  end
  -- Detect contradictory equalities before search. Different max-column limits
  -- are compatible: the smaller hard limit wins, while preferences retain cost.
  for i, a in ipairs(out) do
    if a.strength == "hard" and a.kind == "annotation-position" then
      for j = i+1, #out do local b = out[j]
        if b.strength == "hard" and b.kind == a.kind and same_targets(a,b) and a.value ~= b.value then
          diagnostics[#diagnostics+1] = issue(a, "hard-conflict", a.target_ids,
            "conflicts with " .. source_text(b) .. " for the same annotation",
            {"Make one position soft", "Choose the same position"}, {b})
        end
      end
    end
  end
  local by_id = {}
  for _, n in ipairs(spec.nodes or {}) do by_id[n.id] = n end
  local structure_by_id, note_by_id = {}, {}
  for _, g in ipairs(spec.structures or {}) do structure_by_id[g.id] = g end
  for _, a in ipairs(spec.annotations or {}) do note_by_id[a.id] = a end
  for _, c in ipairs(out) do
    if c.kind == "row-break" and not by_id[c.target_ids[1]] or
        c.kind == "keep-together" and not structure_by_id[c.target_ids[1]] or
        c.kind == "annotation-position" and not note_by_id[c.target_ids[1]] then
      diagnostics[#diagnostics+1] = issue(c, "unknown-constraint-target", c.target_ids,
        "target does not exist in the Spec", {"Use an existing node, structure, or annotation ID"})
    end
  end
  for _, group in ipairs(spec.structures or {}) do
    local members = {}
    for _, id in ipairs(group.member_ids or {}) do members[id] = true end
    for _, keep in ipairs(out) do
      if keep.kind == "keep-together" and keep.strength == "hard" and keep.value == "row"
          and keep.target_ids[1] == group.id then
        for _, limit in ipairs(out) do
          if limit.kind == "max-columns" and limit.strength == "hard" and
              #group.member_ids > limit.value then
            diagnostics[#diagnostics+1] = issue(keep, "hard-conflict", {group.id},
              "requires " .. #group.member_ids .. " members in one row but " ..
              source_text(limit) .. " allows " .. limit.value .. " columns",
              {"Increase max-columns", "Make keep-together or max-columns soft"}, {limit})
          end
        end
        for _, br in ipairs(out) do
          if br.kind == "row-break" and br.strength == "hard" and members[br.target_ids[1]] then
            local owner = by_id[br.target_ids[1]]
            if owner then
              local later = false
              for _, id in ipairs(group.member_ids) do
                if by_id[id] and by_id[id].index > owner.index then later = true end
              end
              if later then diagnostics[#diagnostics+1] = issue(keep, "hard-conflict",
                {group.id, owner.id}, "requires one row but " .. source_text(br) .. " breaks inside it",
                {"Remove the row break", "Make keep-together or endrow soft"}, {br}) end
            end
          end
        end
      end
    end
  end
  if #diagnostics > 0 then return nil, diagnostics end
  return out
end

local function row_data(candidate)
  local pages = candidate.plan and candidate.plan.pages or candidate.pages
  if type(pages) ~= "table" then return nil end
  local rows, locations = {}, {}
  for pi, page in ipairs(pages) do
    for ri, row in ipairs(page.rows or {}) do
      local record = {page=pi, row=ri, nodes=row.ordered_node_ids or {},
        forced=row.forced_break_ids or {}}
      rows[#rows+1] = record
      for _, id in ipairs(record.nodes) do locations[id] = {page=pi, row=ri} end
    end
  end
  return rows, locations
end
local function scene_pages(candidate)
  return candidate.scene and candidate.scene.pages or candidate.scene_pages
end
local function bounds(rect, limit)
  return rect and limit and (rect.x_sp < 0 or rect.y_sp < 0 or
    rect.x_sp + rect.width_sp > limit.width_sp or
    rect.y_sp + rect.height_sp > limit.height_sp)
end

-- candidate = {plan?, scene?, frame?, spec?, complete?}. Missing information
-- defers a check for partial plans. Costs count violations per constraint;
-- strong and weak never make a candidate infeasible.
function M.check(candidate, constraints)
  local violations, costs = {}, {strong=0, weak=0}
  local rows, locations = row_data(candidate)
  local pages = scene_pages(candidate)
  local spec, frame = candidate.spec, candidate.frame
  local groups, notes = {}, {}
  for _, g in ipairs(spec and spec.structures or {}) do groups[g.id] = g end
  for _, a in ipairs(spec and spec.annotations or {}) do notes[a.id] = a end
  local function report(c, code, ids, message, actions, related)
    local d = issue(c, code, ids, message, actions, related)
    if c.strength ~= "hard" then
      costs[c.strength] = costs[c.strength] + 1
      d.severity = "warning"
    end
    violations[#violations+1] = d
  end
  for _, c in ipairs(constraints) do
    if c.kind == "max-columns" and rows then
      for _, row in ipairs(rows) do
        if #row.nodes > c.value then report(c, "max-columns-exceeded", row.nodes,
          "row " .. row.row .. " on page " .. row.page .. " has " .. #row.nodes ..
          " columns; limit is " .. c.value,
          {"Increase max-columns", "Choose a different row break"}) end
      end
    elseif c.kind == "row-break" and rows then
      local owner = c.target_ids[1]
      local loc = locations[owner]
      if loc then
        local row
        for _, r in ipairs(rows) do if r.page == loc.page and r.row == loc.row then row = r end end
        if row and row.nodes[#row.nodes] ~= owner then report(c, "row-break-violated", {owner},
          "row continues after " .. owner, {"Break the row after " .. owner, "Make endrow soft"}) end
      elseif candidate.complete then report(c, "row-break-unresolved", {owner},
        "row break target has no planned row", {"Include the target in the plan"}) end
    elseif c.kind == "keep-together" and rows then
      local group = groups[c.target_ids[1]]
      local members = group and group.member_ids or c.target_ids
      local first, split = nil, false
      for _, id in ipairs(members) do
        local loc = locations[id]
        if loc then
          if first and (loc.page ~= first.page or (c.value == "row" and loc.row ~= first.row)) then split = true end
          first = first or loc
        end
      end
      if split then
        local related = {}
        for _, other in ipairs(constraints) do
          if other.strength == "hard" and (other.kind == "row-break" or other.kind == "page-fit") then
            related[#related+1] = other
          end
        end
        report(c, "keep-together-violated", members,
          "members of " .. c.target_ids[1] .. " span " .. (c.value == "row" and "rows" or "pages"),
          {"Make keep-together soft", "Allow a different row or page break"}, related)
      end
    elseif (c.kind == "annotation-position" or c.kind == "annotation-side") and pages then
      local wanted = c.value
      local found = false
      for _, page in ipairs(pages) do
        for _, note in ipairs(page.annotations or {}) do
          local applies = c.kind == "annotation-side" or note.id == c.target_ids[1]
          if applies then found = true end
          local actual_side = note.position and (note.position:match("^top") and "above"
            or note.position:match("^bottom") and "below" or note.position)
          if applies and (c.kind == "annotation-position" and note.position ~= wanted
              or c.kind == "annotation-side" and actual_side ~= wanted) then
            report(c, "annotation-position-violated", {note.id},
              "annotation is at " .. tostring(note.position) .. "; preference is " .. wanted,
              {"Choose another position", "Make the position soft"})
          end
        end
      end
      if c.kind == "annotation-position" and candidate.complete and not found then
        report(c, "annotation-unresolved", c.target_ids,
          "annotation has no placement in the completed scene", {"Place the annotation"})
      end
    elseif c.kind == "page-fit" and pages and frame then
      local limit = {width_sp=frame.content_width_sp / frame.scale,
        height_sp=frame.content_height_sp / frame.scale}
      for pi, page in ipairs(pages) do
        if bounds(page.bounding_rect, limit) then report(c, "page-fit-violated", {},
          "page " .. pi .. " exceeds the content area at explicit scale " .. frame.scale,
          {"Enable a different page break", "Use a smaller explicit scale", "Use landscape"}) end
      end
    end
  end
  return violations, costs
end

return M
