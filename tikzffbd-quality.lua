-- Seven-component lexicographic quality vector, in QUALITY.md order.
local M={}
local function variance(xs)
  if #xs<2 then return 0 end
  local sum=0;for _,x in ipairs(xs) do sum=sum+x end
  local mean=sum/#xs;local v=0
  for _,x in ipairs(xs) do v=v+(x-mean)^2 end
  return math.floor(v/#xs+0.5)
end
function M.vector(scene,plan,geometry,routes,costs)
  local rc=routes.costs or {}
  local spacing=geometry.spacing_stats or {}
  local whitespace={};local blank_area=0
  for _,page in ipairs(scene.pages) do
    local b=page.bounding_rect
    local area=b.width_sp*b.height_sp
    whitespace[#whitespace+1]=area
    local occupied=0
    for _,r in pairs(page.node_rects or {}) do occupied=occupied+r.width_sp*r.height_sp end
    blank_area=blank_area+math.max(0,area-occupied)
  end
  local displacement=0
  for _,page in ipairs(scene.pages) do
    for _,note in ipairs(page.annotations) do
      if note.preferred_position and note.position~=note.preferred_position then
        displacement=displacement+1
      end
    end
  end
  local vector={0,rc.wrong_way_sp or 0,(rc.crossings or 0)+#(routes.congestion or {}),
    (costs.strong or 0)+(spacing.crossings_after or 0),
    (spacing.gap_variance_sp2 or 0)+variance(whitespace)+blank_area+(costs.weak or 0),
    (rc.bends or 0)*((spacing.route_gap_sp or 10))+(rc.length_sp or 0),displacement}
  return vector
end
function M.less(a,b)
  if not b then return true end
  for i=1,7 do if a[i]~=b[i] then return a[i]<b[i] end end
  return false
end
return M
