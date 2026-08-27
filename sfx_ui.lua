-- native 64-slot, 32-row sfx editor

sfx_fields,sfx_field_x,sfx_field_shift,sfx_field_mask=
 split"pitch,inst,custom,volume,effect","\16\32\40\48\56","\0\6\15\9\12","\63\7\1\7\7"
sfx_menu_items,sfx_row_menu,sfx_meta_fields,sfx_filter_names,sfx_rest_words=
 split"preview,metadata,filters,row ops,undo,prev sfx,next sfx",
 split"rest,copy rows,paste rows,clear rows",split"speed,start/len,end,mode",
 split"noiz,buzz,detune,reverb,dampen",{}

function sfx_keep_visible()
 sfx_scroll=mid(0,mid(sfx_row-8,sfx_scroll,sfx_row),23)
end

function sfx_is_waveform()
 return bank_sfx_is_waveform(sfx_number)
end

function sfx_begin_edit()
 if sfx_row_op then return sfx_rows_apply() end
 local wave=sfx_is_waveform()
 sfx_wave_edit=wave
 if sfx_mode!="rows" then
  local filter=sfx_mode=="filters"
  local index=filter and sfx_filter_field+(wave and 2 or 0) or sfx_meta_field
  local mode=not filter and sfx_number<8 and index>(wave and 1 or 3)
  if index>3 and not (filter or mode) then sfx_error="mode unavailable" return false end
  local meta=filter and 0 or mode and 2 or index
  local old=bank_sfx_meta_raw(sfx_number,meta)
  if filter and (not bank_filter_steps[index] or old>0xd7) then
   sfx_error=old>0xd7 and "raw filter state read only" or "filter unavailable" return false
  end
  local keep,shift,max=0,0,31
  if filter then shift=-bank_filter_steps[index] max=1+index\3
  elseif mode or wave then
   keep,shift,max=mode and 0x7f or 0xfe,mode and 7 or 0,1
  elseif index==1 then max=255 else keep=0xe0 end
  return edit_begin("sfx",bank_sfx_addr(sfx_number,64+meta),1,old,
   keep,shift,max,mode and "mode" or filter and sfx_filter_names[index] or
   wave and "bass" or sfx_meta_fields[index])
 end
 if wave then
  local addr=bank_sfx_addr(sfx_number,sfx_row*2+sfx_field-1)
  return edit_begin("sfx",addr,1,@addr,0,0,255,"sample")
 end
 local word=bank_note_authored_raw(sfx_number,sfx_row)
 local shift,mask=ord(sfx_field_shift,sfx_field),ord(sfx_field_mask,sfx_field)
 return edit_begin("sfx",bank_note_addr(sfx_number,sfx_row),2,word,
  0xffff^^(mask<<shift),shift,mask,sfx_fields[sfx_field])
end

function sfx_rows_begin(op)
 local addr,old=bank_note_addr(sfx_number,sfx_row),
  bank_note_authored_raw(sfx_number,sfx_row)
 if not addr then sfx_error="waveform slot read only" return false end
 if op then
  if op==2 and sfx_clip_count==0 then sfx_error="clipboard empty" return false end
  sfx_row_op,sfx_anchor=op,sfx_row
  sfx_error=nil
  return true
 end
 if old!=0 then sfx_rest_words[addr]=old end
 edit_begin("sfx",addr,2,old,0,0,0xffff,"rest")
 edit_value=old==0 and (sfx_rest_words[addr] or 0x0a18) or 0
 return edit_commit()
end

sfx_toggle_rest=sfx_rows_begin

function sfx_rows_apply()
 stop_audition(true)
 local paste=sfx_row_op==2
 local first,count=paste and sfx_row or min(sfx_anchor,sfx_row),
  paste and sfx_clip_count or abs(sfx_row-sfx_anchor)+1
 if sfx_row_op==1 then
  if bank_rows(sfx_number,first,count) then sfx_clip_count=count
  else sfx_error="copy rejected" return false end
 else
  local source=paste and bank_clip_base or nil
  local same=bank_rows(sfx_number,first,count,source,false)
  if same==nil then sfx_error=paste and "paste overflow" or "range rejected" return false end
  if not same then
   local dirty=bank_dirty
   if not song_restore_then(function() return bank_rows(sfx_number,first,count,source,true) end) then
    sfx_error="batch rejected" return false
   end
   undo_owner,undo_width,undo_dirty,undo_addr=
    "sfx",count*2,dirty,bank_note_addr(sfx_number,first)
  end
 end
 sfx_error,sfx_row_op=nil,nil
 return true
end

function sfx_change_slot(delta)
 stop_audition(true)
 sfx_number,sfx_error=mid(0,sfx_number+delta,63),nil
end

function update_sfx_screen()
 if edit_owner=="sfx" then
  if sfx_wave_edit and not sfx_is_waveform() then
   edit_cancel() sfx_error="waveform unavailable"
  else edit_update() end
  return
 end
 if context_menu then
  update_context_menu(btn(4),btn(5),btnp(4),btnp(5),
   btnp(0),btnp(1),btnp(2),btnp(3))
  if not context_menu then reset_action_input() end
  return
 end
 if input_gated() then return end
 if update_action_buttons(btn(4),btn(5)) then return end

 if sfx_mode!="rows" then
  local meta,wave=sfx_mode=="meta",sfx_is_waveform()
  local field=meta and sfx_meta_field or sfx_filter_field
  field=mid(1,field+(btnp(3) and 1 or btnp(2) and -1 or 0),
   meta and (sfx_number<8 and (wave and 2 or 4) or 3) or wave and 3 or 5)
  if meta then sfx_meta_field=field else sfx_filter_field=field end
 else
  local fields=sfx_is_waveform() and 2 or 5
  if not sfx_row_op then
   sfx_field=mid(1,sfx_field+(btnp(1) and 1 or btnp(0) and -1 or 0),fields)
  end
  sfx_row=mid(0,sfx_row+(btnp(3) and 1 or btnp(2) and -1 or 0),31)
  sfx_keep_visible()
 end
end

function draw_sfx_list(names,values,field,y,step)
 for i=1,#values do
  local picked=i==field
  print((picked and "> " or "  ")..names[i].." "..values[i],22,
   y+(i-1)*step,picked and 7 or 6)
 end
 print("tap o edit/hold start x rows",7,106)
end

function draw_sfx_filters()
 local raw,values=bank_sfx_meta_raw(sfx_number,0),{}
 local wave=sfx_is_waveform()
 local names=wave and split"detune,reverb,dampen" or sfx_filter_names
 sfx_filter_field=min(#names,sfx_filter_field)
 for i=1,#names do add(values,bank_sfx_filter(sfx_number,i+(wave and 2 or 0)) or "-") end
 print("raw filter "..hex2(raw),30,18,5)
 draw_sfx_list(names,values,sfx_filter_field,32,12)
 print(raw>0xd7 and "raw filter state read only" or "",11,96,8)
end

function draw_sfx_rows()
 local wave=sfx_is_waveform()
 sfx_field=min(sfx_field,wave and 2 or 5)
 local first,last=sfx_row,sfx_row
 if sfx_row_op then
  first,last=min(sfx_anchor,sfx_row),max(sfx_anchor,sfx_row)
  if sfx_row_op==2 then first,last=sfx_row,sfx_row+sfx_clip_count-1 end
 end
 print(wave and "sample even odd" or "row p  i c v e",4,12,5)
 for line=0,8 do
  local row,y=sfx_scroll+line,21+line*8
  local selected=row==sfx_row
  if mid(first,row,last)==row then rectfill(1,y-1,126,y+6,1) end
  if wave then
   local addr=bank_sfx_addr(sfx_number,row*2)
   print(hex2(row*2).." "..hex2(@addr)..hex2(@(addr+1)),4,y,selected and 7 or 6)
  else
   local word=bank_note_authored_raw(sfx_number,row)
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
  print("sample "..hex2(sample).." amp "..
   (@(bank_sfx_addr(sfx_number,sample))<<24>>24),3,96,5)
 elseif sfx_row_op then
  print(sfx_row_menu[sfx_row_op+1].." "..hex2(first).."-"..hex2(last),18,96,7)
  print("up/down  o confirm  x cancel",6,105)
 else
  print("field "..sfx_fields[sfx_field].."  hold x menu",3,96,5)
 end
 if not sfx_row_op then print("tap o edit/hold start x song",7,105) end
end

function draw_sfx_meta()
 local raw,text={},""
 for i=0,3 do
  add(raw,bank_sfx_meta_raw(sfx_number,i)) text..=hex2(raw[#raw]).." "
 end
 print("raw "..text,15,24,7)
 local wave=sfx_is_waveform()
 local values=wave and {(raw[2]&1)!=0 and "on" or "off","wave"} or
  {raw[2],raw[3]&0x1f,raw[4]&0x1f,sfx_number<8 and "notes"}
 sfx_meta_field=min(sfx_meta_field,#values)
 draw_sfx_list(wave and split"bass,mode" or sfx_meta_fields,
  values,sfx_meta_field,47,13)
end

function draw_sfx_handoff()
 cls(0)
 rectfill(0,0,127,8,1)
 print("sfx "..hex2(sfx_number),2,2,12)
 print((sfx_is_waveform() and "wave" or (audition_active and "preview" or
  (bank_profile_is_active() and "profile" or "auth"))),42,2,6)
 print(bank_dirty and "dirty" or "clean",92,2,bank_dirty and 8 or 5)
 local draw=sfx_mode=="meta" and draw_sfx_meta or
  sfx_mode=="filters" and draw_sfx_filters or draw_sfx_rows
 draw()
 if sfx_error then print("! "..sfx_error,2,117,8) end
 if context_menu then draw_context_menu() end
 if edit_owner=="sfx" then draw_edit() end
end
