-- Development-only trace hook; never loaded by the package.
local bridge=tikzffbd_bridge
local arrays={nodes=true,flows=true,branches=true,joins=true,structures=true,
  annotations=true,constraints=true,pages=true,rows=true,diagnostics=true,
  edge_labels=true,continuation_markers=true,structure_texts=true,vector=true,
  points=true,boundary_port_ids=true,ordered_node_ids=true,ordered_region_ids=true,
  continuation_ids=true,forced_break_ids=true,preferred_break_ids=true,
  member_ids=true,input_member_ids=true,output_member_ids=true,target_ids=true,
  arm_flow_ids_in_user_order=true,suggested_actions=true,object_ids=true,constraint_ids=true}
local function encode(v,key)
 if type(v)=='string' then
  return '"'..v:gsub('[%z\1-\31\\"]',function(c)
   if c=='"' or c=='\\' then return '\\'..c end
   return string.format('\\u%04x',c:byte())
  end)..'"'
 end
 if type(v)~='table' then return tostring(v) end
 local out={}
 if arrays[key] or #v>0 then
  for _,x in ipairs(v) do out[#out+1]=encode(x) end
  return '['..table.concat(out,',')..']'
 end
 local keys={};for k in pairs(v) do keys[#keys+1]=k end
 table.sort(keys)
 for _,k in ipairs(keys) do out[#out+1]=encode(k)..':'..encode(v[k],k) end
 return '{'..table.concat(out,',')..'}'
end
local original=bridge.render
bridge.render=function()
 original()
 local d=bridge.last
 if d.Scene then
  local path=assert(os.getenv('FFBD_TEST_OUTPUT'))..'/'..tex.jobname..'-'..d.Spec.environment_id..'.json'
  local file=assert(io.open(path,'w'))
  file:write(encode({contract_version=1,environment_id=d.Spec.environment_id,
   objects={Spec=d.Spec,Metrics=d.Metrics,Frame=d.Frame,Scene=d.Scene}}),'\n')
  file:close()
 end
end
