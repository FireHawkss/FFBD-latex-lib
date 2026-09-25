-- Measured annotation candidates and route-associated edge labels.
local M = {}
M.positions = {"top-left", "top-center", "top-right", "left", "right",
  "bottom-left", "bottom-center", "bottom-right"}
local function round(x) return math.floor(x + 0.5) end
local function rect(x,y,w,h) return {x_sp=round(x),y_sp=round(y),width_sp=w,height_sp=h} end
local function overlap(a,b,pad)
  pad=pad or 0
  return a.x_sp < b.x_sp+b.width_sp+pad and b.x_sp < a.x_sp+a.width_sp+pad
    and a.y_sp < b.y_sp+b.height_sp+pad and b.y_sp < a.y_sp+a.height_sp+pad
end
M.overlap=overlap
local function contains(a,b)
  return b.x_sp>=a.x_sp and b.y_sp>=a.y_sp and
    b.x_sp+b.width_sp<=a.x_sp+a.width_sp and
    b.y_sp+b.height_sp<=a.y_sp+a.height_sp
end
local function page_of(g)
  local out={}
  for _,axis in ipairs(g.row_axes or {}) do
    for _,layer in ipairs(axis.layers or {}) do
      for _,id in ipairs(layer) do out[id]=axis.page_index end
    end
  end
  return out
end
M.page_of=page_of
local function boxes(g,notes,page,omit)
  local result={}
  local owners=page_of(g)
  for id,r in pairs(g.node_rects_by_id or {}) do
    if owners[id]==page then result[#result+1]={id=id,rect=r} end
  end
  for _,note in ipairs(notes or {}) do
    if note.page_index==page and note.id~=omit then
      result[#result+1]={id=note.id,rect=note.rect}
    end
  end
  for _,item in ipairs(g.structure_texts or {}) do
    if item.page_index==page then result[#result+1]={id=item.id,rect=item.rect} end
  end
  return result
end
local function fits_groups(g,spec,owner,box,page)
  for _,group in ipairs(spec.structures or {}) do
    local member=false
    for _,id in ipairs(group.member_ids) do if id==owner then member=true end end
    if member then
      local found=false
      for gid,r in pairs(g.group_rects_by_id or {}) do
        if (gid==group.id or gid:find("group-"..group.id.."-page-",1,true))
            and ((g.group_rect_page_by_id or {})[gid] or 1)==page and contains(r,box) then
          found=true; break
        end
      end
      if not found then return false end
    end
  end
  return true
end
function M.note_candidates(note,g,spec,metrics,existing)
  local owner=(g.node_rects_by_id or {})[note.owner_id]
  local measured=(metrics.by_annotation_id or {})[note.id]
  if not owner or not measured or not measured.width_sp or not measured.height_sp then return {} end
  local page=page_of(g)[note.owner_id]
  local gap=math.max(1,(g.spacing_stats or {}).route_gap_sp or 10)
  local w,h=measured.width_sp,measured.height_sp
  local result={}
  local positions={}
  if note.preferred_position and note.position_strength~="soft" then
    positions[1]=note.preferred_position
  else
    for _,p in ipairs(M.positions) do positions[#positions+1]=p end
  end
  for _,p in ipairs(positions) do
    local x,y
    if p=="left" then x=owner.x_sp-w-gap;y=owner.y_sp+(owner.height_sp-h)/2
    elseif p=="right" then x=owner.x_sp+owner.width_sp+gap;y=owner.y_sp+(owner.height_sp-h)/2
    else
      if p:find("left",1,true) then x=owner.x_sp
      elseif p:find("right",1,true) then x=owner.x_sp+owner.width_sp-w
      else x=owner.x_sp+(owner.width_sp-w)/2 end
      y=p:find("top",1,true) and owner.y_sp-h-gap or owner.y_sp+owner.height_sp+gap
    end
    local b=rect(x,y,w,h)
    local clear=true
    for _,item in ipairs(boxes(g,existing,page,note.id)) do
      if overlap(b,item.rect) then clear=false;break end
    end
    if clear and fits_groups(g,spec,note.owner_id,b,page) then
      result[#result+1]={id=note.id,owner_id=note.owner_id,position=p,rect=b,
        type_ref=note.type_ref,body_ref=note.body_ref,page_index=page}
    end
  end
  local preferred=note.preferred_position
  local side=(spec.options or {}).annotations
  local function priority(p)
    if p==preferred then return 0 end
    if not preferred and ((side=="above" and p:find("top",1,true))
        or (side=="below" and p:find("bottom",1,true)) or p==side) then return 0 end
    return 1
  end
  table.sort(result,function(a,b)
    if a.position==b.position then return false end
    if priority(a.position)~=priority(b.position) then return priority(a.position)<priority(b.position) end
    for _,p in ipairs(M.positions) do
      if a.position==p then return true end
      if b.position==p then return false end
    end
    return false
  end)
  return result
end
local function hits_path(box,points,pad)
  for i=2,#points do
    local a,b=points[i-1],points[i]
    if a.x_sp==b.x_sp then
      if a.x_sp>box.x_sp-pad and a.x_sp<box.x_sp+box.width_sp+pad
        and math.max(a.y_sp,b.y_sp)>box.y_sp-pad
        and math.min(a.y_sp,b.y_sp)<box.y_sp+box.height_sp+pad then return true end
    elseif a.y_sp==b.y_sp then
      if a.y_sp>box.y_sp-pad and a.y_sp<box.y_sp+box.height_sp+pad
        and math.max(a.x_sp,b.x_sp)>box.x_sp-pad
        and math.min(a.x_sp,b.x_sp)<box.x_sp+box.width_sp+pad then return true end
    end
  end
  return false
end
M.hits_path=hits_path
function M.labels(spec,metrics,g,routes,notes)
  local labels={}; local owners=page_of(g)
  local occupied={}
  for _,note in ipairs(notes) do occupied[#occupied+1]={page_index=note.page_index,rect=note.rect} end
  local gap=math.max(1,math.floor(((g.spacing_stats or {}).route_gap_sp or 10)/4))
  for _,flow in ipairs(spec.flows or {}) do
    if flow.condition_ref then
      local size=(metrics.by_text_ref or {})[flow.condition_ref]
      local path=routes.paths_by_flow_id[flow.id]
      if not size or not path then return nil,flow.id end
      local w,h=size.width_sp,size.height_sp+(size.depth_sp or 0)
      local candidates={}
      for _,segment in ipairs(path.page_segments or {path}) do
        local pts=segment.points
        for i=2,#pts do
          local a,b=pts[i-1],pts[i]
          local length=math.abs(a.x_sp-b.x_sp)+math.abs(a.y_sp-b.y_sp)
          if length>0 then
            -- Slide along the segment as well as trying both sides. Keep the
            -- label's centre on the segment so association stays unambiguous.
            for _,fraction in ipairs({0.5,0.25,0.75,0,1}) do
              local cx=a.x_sp+(b.x_sp-a.x_sp)*fraction
              local cy=a.y_sp+(b.y_sp-a.y_sp)*fraction
              for side=1,2 do
                local x,y
                if a.y_sp==b.y_sp then
                  x=cx-w/2;y=side==1 and cy-h-gap or cy+gap
                else
                  x=side==1 and cx+gap or cx-w-gap;y=cy-h/2
                end
                candidates[#candidates+1]={page_index=segment.page_index or path.page_index or owners[flow.source],
                  rect=rect(x,y,w,h),distance=round(math.abs(fraction-0.5)*length),segment=i}
              end
            end
          end
        end
      end
      table.sort(candidates,function(a,b)
        if a.distance~=b.distance then return a.distance<b.distance end
        if a.page_index~=b.page_index then return a.page_index<b.page_index end
        if a.segment~=b.segment then return a.segment<b.segment end
        if a.rect.y_sp~=b.rect.y_sp then return a.rect.y_sp<b.rect.y_sp end
        return a.rect.x_sp<b.rect.x_sp
      end)
      local chosen
      for _,c in ipairs(candidates) do
        local clear=true
        for _,item in ipairs(boxes(g,occupied,c.page_index)) do
          if overlap(c.rect,item.rect,gap) then clear=false;break end
        end
        if clear then
          for _,item in ipairs(occupied) do
            if item.page_index==c.page_index and overlap(c.rect,item.rect,gap) then clear=false;break end
          end
        end
        if clear then
          for _,other in ipairs(spec.flows or {}) do
            do
              local p=routes.paths_by_flow_id[other.id]
              for _,leg in ipairs(p and (p.page_segments or {p}) or {}) do
                if (leg.page_index or p.page_index)==c.page_index and hits_path(c.rect,leg.points,gap) then
                  clear=false;break
                end
              end
            end
            if not clear then break end
          end
        end
        if clear then chosen=c;break end
      end
      if not chosen then return nil,flow.id end
      local item={flow_id=flow.id,text_ref=flow.condition_ref,rect=chosen.rect,
        page_index=chosen.page_index}
      labels[#labels+1]=item;occupied[#occupied+1]=item
    end
  end
  return labels
end
return M
