-- native 64-slot, 32-row sfx editor

sfx_rows=9
sfx_fields=split"pitch,inst,custom,volume,effect"
sfx_field_x="\16\32\40\48\56"
sfx_field_shift="\0\6\15\9\12"
sfx_field_mask="\63\7\1\7\7"
sfx_menu_items=split"preview,metadata,filters,rest,undo,prev sfx,next sfx"
sfx_meta_fields=split"speed,start/len,end"
sfx_filter_names=split"noiz,buzz,detune,reverb,dampen"
sfx_rest_words={}

function sfx_keep_visible()
 if sfx_row<sfx_scroll then sfx_scroll=sfx_row end
 if sfx_row>=sfx_scroll+sfx_rows then sfx_scroll=sfx_row-sfx_rows+1 end
 sfx_scroll=mid(0,sfx_scroll,bank_row_count-sfx_rows)
end

function sfx_is_waveform()
 return bank_sfx_is_waveform(sfx_number)==true
end

function sfx_raw_word()
 return bank_note_authored_raw(sfx_number,sfx_row)
end

function sfx_begin_edit()
 if sfx_is_waveform() then
  sfx_error="waveform "..(sfx_mode=="rows" and "slot" or sfx_mode).." read only"
  return false
 end
 if sfx_mode=="rows" then
  local word=song_restore_then(sfx_raw_word)
  if word==nil then sfx_error="row unavailable" return false end
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
 local old,new
 local old_dirty=bank_dirty
 local ok=song_restore_then(function()
  old=peek2(addr)
  new=old==0 and (sfx_rest_words[addr] or 0x0a18) or 0
  if old!=0 then sfx_rest_words[addr]=old end
  return bank_write_word(addr,new)
 end)
 if ok and old!=new then
  undo_owner="sfx" undo_width=2 undo_addr=addr undo_value=old undo_dirty=old_dirty
  sfx_error=nil
 end
 return ok
end

function sfx_undo() return edit_undo("sfx") end

function sfx_change_slot(delta)
 if audition_active then stop_audition(true) end
 sfx_number=mid(0,sfx_number+delta,bank_sfx_count-1)
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

 if sfx_mode=="meta" then
  if btnp(2) then sfx_meta_field=mid(1,sfx_meta_field-1,3)
  elseif btnp(3) then sfx_meta_field=mid(1,sfx_meta_field+1,3)
  end
 elseif sfx_mode=="filters" then
  if btnp(2) then sfx_filter_field=mid(1,sfx_filter_field-1,5)
  elseif btnp(3) then sfx_filter_field=mid(1,sfx_filter_field+1,5) end
 else
  if btnp(0) then sfx_field=mid(1,sfx_field-1,#sfx_fields)
  elseif btnp(1) then sfx_field=mid(1,sfx_field+1,#sfx_fields)
  elseif btnp(2) then sfx_row=mid(0,sfx_row-1,31) sfx_keep_visible()
  elseif btnp(3) then sfx_row=mid(0,sfx_row+1,31) sfx_keep_visible() end
 end
end

function draw_sfx_list(names,values,field,y,step)
 for i=1,#names do
  print((i==field and "> " or "  ")..names[i].." "..values[i],22,y+(i-1)*step,i==field and 7 or 6)
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
 print("row p  i c v e",4,12,5)
 for line=0,sfx_rows-1 do
  local row=sfx_scroll+line
  local y=21+line*8
  if row==sfx_row then rectfill(1,y-1,126,y+6,1) end
  local word=bank_note_authored_raw(sfx_number,row)
  if word==nil then
   print(hex2(row).." waveform data",4,y,row==sfx_row and 8 or 6)
  else
   local custom=(word&0x8000)!=0 and "c" or "b"
   local text=hex2(row).." "..(word==0 and "---" or hex2(word&0x3f)).." "..
    ((word>>6)&7).." "..custom.." "..((word>>9)&7).." "..((word>>12)&7)
   print(text,4,y,row==sfx_row and 7 or 6)
   if row==sfx_row then
    local x=ord(sfx_field_x,sfx_field)
    rect(x-2,y-2,x+9,y+6,10)
   end
  end
 end
 print("field "..sfx_fields[sfx_field].."  hold x menu",3,96,5)
 print("tap o edit/hold start x song",7,105,6)
end

function draw_sfx_meta()
 local raw={}
 for i=0,3 do raw[i+1]=bank_sfx_meta_raw(sfx_number,i) end
 print("raw m0 m1 m2 m3",15,18,5)
 print(hex2(raw[1]).." "..hex2(raw[2]).." "..hex2(raw[3]).." "..hex2(raw[4]),30,29,7)
 local names={"speed",(raw[4]&0x1f)==0 and "len" or "loop start","loop end"}
 draw_sfx_list(names,{raw[2],raw[3]&0x1f,raw[4]&0x1f},sfx_meta_field,47,13)
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
