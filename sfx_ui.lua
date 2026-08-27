-- native 64-slot, 32-row sfx editor

sfx_fields=split"pitch,inst,custom,volume,effect"
sfx_field_x="\16\32\40\48\56"
sfx_field_shift="\0\6\15\9\12"
sfx_field_mask="\63\7\1\7\7"
sfx_menu_items=split"preview,metadata,filters,row ops,undo,prev sfx,next sfx"
sfx_row_menu=split"rest,copy rows,paste rows,clear rows"
sfx_meta_fields=split"speed,start/len,end"
sfx_filter_names=split"noiz,buzz,detune,reverb,dampen"
sfx_rest_words={}

function sfx_keep_visible()
 sfx_scroll=mid(0,mid(sfx_row-8,sfx_scroll,sfx_row),23)
end

function sfx_is_waveform()
 return bank_sfx_is_waveform(sfx_number)
end

function sfx_begin_edit()
 if sfx_row_op then return sfx_rows_apply() end
 if sfx_is_waveform() then
  if sfx_mode!="rows" then
   sfx_error="waveform "..sfx_mode.." read only" return false
  end
  local addr=bank_sfx_addr(sfx_number,sfx_row*2+sfx_field-1)
  return edit_begin("sfx",addr,1,@addr,0,0,255,"sample")
 end
 if sfx_mode=="rows" then
  local word=song_restore_then(function()
   return bank_note_authored_raw(sfx_number,sfx_row)
  end)
  if not word then sfx_error="row unavailable" return false end
  local shift=ord(sfx_field_shift,sfx_field)
  local mask=ord(sfx_field_mask,sfx_field)
  return edit_begin("sfx",bank_note_addr(sfx_number,sfx_row),2,word,
   0xffff^^(mask<<shift),shift,mask,sfx_fields[sfx_field])
 end
 local filter=sfx_mode=="filters"
 local index=filter and sfx_filter_field or sfx_meta_field
 local old=bank_sfx_meta_raw(sfx_number,filter and 0 or index)
 if filter and old>0xd7 then sfx_error="raw filter state read only" return false end
 return edit_begin("sfx",bank_sfx_addr(sfx_number,64+(filter and 0 or index)),1,old,
  filter and 0 or (index==1 and 0 or 0xe0),filter and -bank_filter_steps[index] or 0,
  filter and (index<3 and 1 or 2) or (index==1 and 255 or 31),
  (filter and sfx_filter_names or sfx_meta_fields)[index])
end

function sfx_toggle_rest()
 if sfx_is_waveform() then sfx_error="waveform slot read only" return false end
 local addr=bank_note_addr(sfx_number,sfx_row)
 local old=bank_note_authored_raw(sfx_number,sfx_row)
 if old!=0 then sfx_rest_words[addr]=old end
 edit_begin("sfx",addr,2,old,0,0,0xffff,"rest")
 edit_value=old==0 and (sfx_rest_words[addr] or 0x0a18) or 0
 return edit_commit()
end

function sfx_rows_begin(op)
 if sfx_is_waveform() then sfx_error="waveform slot read only" return false end
 if op==2 and sfx_clip_count==0 then sfx_error="clipboard empty" return false end
 sfx_row_op,sfx_anchor=op,sfx_row
 sfx_error=nil
 return true
end

function sfx_rows_apply()
 if audition_active then stop_audition(true) end
 local paste=sfx_row_op==2
 local first=paste and sfx_row or min(sfx_anchor,sfx_row)
 local count=paste and sfx_clip_count or abs(sfx_row-sfx_anchor)+1
 if sfx_row_op==1 then
  if bank_rows(sfx_number,first,count) then sfx_clip_count=count sfx_error=nil
  else sfx_error="copy rejected" return false end
 else
  local source=paste and bank_clip_base or nil
  local same=bank_rows(sfx_number,first,count,source,false)
  if same==nil then sfx_error=paste and "paste overflow" or "range rejected" return false end
  if not same then
   local dirty=bank_dirty
   local ok=song_restore_then(function() return bank_rows(sfx_number,first,count,source,true) end)
   if not ok then sfx_error="batch rejected" return false end
   undo_owner,undo_width,undo_dirty="sfx",count*2,dirty
   undo_addr=bank_note_addr(sfx_number,first)
  end
  sfx_error=nil
 end
 sfx_row_op=nil
 return true
end

function sfx_change_slot(delta)
 if audition_active then stop_audition(true) end
 sfx_number=mid(0,sfx_number+delta,63)
 sfx_error=nil
end

function update_sfx_screen()
 if edit_owner=="sfx" then return edit_update() end
 if context_menu then
  update_context_menu(btn(4),btn(5),btnp(4),btnp(5),
   btnp(0),btnp(1),btnp(2),btnp(3))
  if not context_menu then reset_action_input() end
  return
 end
 if input_gated() then return end
 if update_action_buttons(btn(4),btn(5)) then return end

 if sfx_mode!="rows" then
  local meta=sfx_mode=="meta"
  local field=meta and sfx_meta_field or sfx_filter_field
  if btnp(2) then field-=1 elseif btnp(3) then field+=1 end
  field=mid(1,field,meta and 3 or 5)
  if meta then sfx_meta_field=field else sfx_filter_field=field end
 else
  local fields=sfx_is_waveform() and 2 or 5
  if not sfx_row_op and btnp(0) then sfx_field=mid(1,sfx_field-1,fields)
  elseif not sfx_row_op and btnp(1) then sfx_field=mid(1,sfx_field+1,fields)
  elseif btnp(2) then sfx_row=mid(0,sfx_row-1,31) sfx_keep_visible()
  elseif btnp(3) then sfx_row=mid(0,sfx_row+1,31) sfx_keep_visible() end
 end
end

function draw_sfx_list(names,values,field,y,step)
 for i=1,#names do
  local selected=i==field
  print((selected and "> " or "  ")..names[i].." "..values[i],22,y+(i-1)*step,selected and 7 or 6)
 end
 print("tap o edit/hold start x rows",7,106,5)
end

function draw_sfx_filters()
 local raw=bank_sfx_meta_raw(sfx_number,0)
 local values={}
 for i=1,5 do values[i]=bank_sfx_filter(sfx_number,i) or "-" end
 print("raw filter "..hex2(raw),30,18,5)
 draw_sfx_list(sfx_filter_names,values,sfx_filter_field,32,12)
 if sfx_is_waveform() then print("waveform filters read only",11,96,8)
 elseif raw>0xd7 then print("raw filter state read only",11,96,8) end
end

function draw_sfx_rows()
 local wave=sfx_is_waveform()
 if wave then sfx_field=min(sfx_field,2) end
 local first,last=sfx_row,sfx_row
 if sfx_row_op then
  first,last=min(sfx_anchor,sfx_row),max(sfx_anchor,sfx_row)
  if sfx_row_op==2 then first,last=sfx_row,sfx_row+sfx_clip_count-1 end
 end
 print(wave and "sample even odd" or "row p  i c v e",4,12,5)
 for line=0,8 do
  local row=sfx_scroll+line
  local y=21+line*8
  local selected=row==sfx_row
  if row>=first and row<=last then rectfill(1,y-1,126,y+6,1) end
  local word=bank_note_authored_raw(sfx_number,row)
  if word==nil then
   local addr=bank_sfx_addr(sfx_number,row*2)
   print(hex2(row*2).." "..hex2(@addr)..hex2(@(addr+1)),4,y,selected and 7 or 6)
  else
   print(hex2(row).." "..(word==0 and "---" or hex2(word&0x3f)).." "..
    (word\64%8).." "..((word&0x8000)!=0 and "c" or "b").." "..
    (word\512%8).." "..(word\4096%8),4,y,selected and 7 or 6)
   if selected then
    local x=ord(sfx_field_x,sfx_field)
    rect(x-2,y-2,x+9,y+6,10)
   end
  end
 end
 if wave then
  local sample=sfx_row*2+sfx_field-1
  local raw=@(bank_sfx_addr(sfx_number,sample))
  print("sample "..hex2(sample).." amp "..(raw<<24>>24),3,96,5)
 elseif sfx_row_op then
  print(sfx_row_menu[sfx_row_op+1].." "..hex2(first).."-"..hex2(last),18,96,7)
  print("up/down  o confirm  x cancel",6,105,6)
 else
  print("field "..sfx_fields[sfx_field].."  hold x menu",3,96,5)
 end
 if not sfx_row_op then print("tap o edit/hold start x song",7,105,6) end
end

function draw_sfx_meta()
 local raw={}
 for i=0,3 do raw[i+1]=bank_sfx_meta_raw(sfx_number,i) end
 print("raw m0 m1 m2 m3",15,18,5)
 print(hex2(raw[1]).." "..hex2(raw[2]).." "..hex2(raw[3]).." "..hex2(raw[4]),30,29,7)
 draw_sfx_list({"speed",(raw[4]&0x1f)==0 and "len" or "loop start","loop end"},
  {raw[2],raw[3]&0x1f,raw[4]&0x1f},sfx_meta_field,47,13)
 if sfx_is_waveform() then print("waveform metadata read only",11,91,8) end
end

function draw_sfx_handoff()
 cls(0)
 rectfill(0,0,127,8,1)
 print("sfx "..hex2(sfx_number),2,2,12)
 print((sfx_is_waveform() and "wave" or (audition_active and "preview" or
  (bank_profile_is_active() and "profile" or "auth"))),42,2,6)
 print(bank_dirty and "dirty" or "clean",92,2,bank_dirty and 8 or 5)
 if sfx_mode=="meta" then draw_sfx_meta()
 elseif sfx_mode=="filters" then draw_sfx_filters() else draw_sfx_rows() end
 if sfx_error then print("! "..sfx_error,2,117,8) end
 if context_menu then draw_context_menu() end
 if edit_owner=="sfx" then draw_edit() end
end
