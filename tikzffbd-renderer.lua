-- Scene-to-TikZ emission. Geometry is consumed verbatim in scaled points.
local M = {}

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t or {}) do keys[#keys+1] = k end
  table.sort(keys)
  return keys
end

local function rect_args(r)
  assert(r and r.x_sp and r.y_sp and r.width_sp and r.height_sp, "missing Scene rectangle")
  return table.concat({r.x_sp,r.y_sp,r.width_sp,r.height_sp}, "}{")
end

local function cmd(name, ...)
  local args = {...}
  for i,v in ipairs(args) do args[i] = "{" .. tostring(v or "") .. "}" end
  return "\\ffbdScene" .. name .. table.concat(args)
end

local function node_kind(n)
  if not n then return "function" end
  if n.kind == "start" or n.kind == "finish" then return "terminal" end
  if n.kind == "split" or n.kind == "join" then return n.logic or "and" end
  return n.kind or "function"
end

function M.styles_from_spec(spec)
  local styles={nodes={},structures={}}
  for _,n in ipairs(spec.nodes or {}) do styles.nodes[n.id]=n end
  for _,s in ipairs(spec.structures or {}) do styles.structures[s.id]=s end
  return styles
end

function M.render(scene, text_registry, styles)
  assert(type(scene) == "table" and type(scene.pages) == "table", "Scene required")
  assert(type(scene.scale) == "number" and scene.scale > 0 and scene.scale < math.huge,
    "positive finite Scene scale required")
  styles = styles or {}
  local nodes, structures = styles.nodes or {}, styles.structures or {}
  local refs = text_registry or {}
  local strict = text_registry ~= nil
  local function check(ref)
    if ref and ref ~= "" and strict then assert(refs[ref], "missing text reference " .. ref) end
    return ref or ""
  end
  local out = {}
  local function add(s) out[#out+1] = s end
  for page_index,page in ipairs(scene.pages) do
    add(cmd("PageBegin",page_index,scene.scale))
    local b = assert(page.bounding_rect, "missing page bounding rectangle")
    add(cmd("Bounds",rect_args(b)))
    -- Background group fills precede paths; text is always placed last.
    for _,id in ipairs(sorted_keys(page.structure_rects)) do
      local s = structures[(page.structure_owner_by_id or {})[id] or id] or {}
      add(cmd("Structure",s.style or "plain",rect_args(page.structure_rects[id])))
    end
    for _,id in ipairs(sorted_keys(page.flow_paths)) do
      local path = page.flow_paths[id]
      local points = {}
      for _,p in ipairs(path.points) do
        points[#points+1] = "(" .. p.x_sp .. "sp," .. p.y_sp .. "sp)"
      end
      assert(#points >= 2, "flow requires two points")
      add(cmd("Flow",table.concat(points," -- ")))
    end
    for _,id in ipairs(sorted_keys(page.node_rects)) do
      local n = nodes[id] or {}
      add(cmd("Node",node_kind(n),rect_args(page.node_rects[id]),check(n.text_ref),n.number or "",
        n.logic and n.logic:upper() or ""))
    end
    if page.structure_texts then
      for _,item in ipairs(page.structure_texts) do
        add(cmd("StructureLabel",item.role,rect_args(item.rect),check(item.text_ref)))
      end
    else
    for _,id in ipairs(sorted_keys(page.structure_rects)) do
      local s = structures[(page.structure_owner_by_id or {})[id] or id] or {}
      local r = page.structure_rects[id]
      add(cmd("StructureText",rect_args(r),check(s.type_ref),check(s.info_ref)))
    end
    end
    for _,n in ipairs(page.annotations or {}) do
      add(cmd("Annotation",rect_args(n.rect),check(n.type_ref),check(n.body_ref)))
    end
    for _,l in ipairs(page.edge_labels or {}) do
      add(cmd("Label",rect_args(l.rect),check(l.text_ref)))
    end
    for _,m in ipairs(page.continuation_markers or {}) do
      add(cmd("Continuation",rect_args(m.rect),check(m.text_ref)))
    end
    add(cmd("PageEnd"))
  end
  return table.concat(out," ") .. " "
end

return M
