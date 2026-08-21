-- native 64-slot, 32-row sfx editor

sfx_rows=9
sfx_fields={"pitch","inst","custom","volume","effect"}
sfx_field_x={16,32,40,48,56}
sfx_menu_items={"preview","metadata","rest","undo","prev sfx","next sfx"}
sfx_meta_fields={"speed","start/len","end"}
sfx_rest_words={}

function sfx_keep_visible()
 if sfx_row<sfx_scroll then sfx_scroll=sfx_row end
 if sfx_row>=sfx_scroll+sfx_rows then sfx_scroll=sfx_row-sfx_rows+1 end
 sfx_scroll=mid(0,sfx_scroll,bank_row_count-sfx_rows)
end

function sfx_is_waveform()
 return bank_sfx_is_waveform(sfx_number)==true
end

function sfx_reset_input()
 sfx_entry_gate=true
 sfx_o_was_down=false
 sfx_o_hold=0
 sfx_o_consumed=false
 sfx_chord_consumed=false
 sfx_x_was_down=false
 sfx_x_hold=0
 sfx_x_consumed=false
end

function sfx_open_from_song()
 sfx_row=0
 sfx_scroll=0
 sfx_field=1
 sfx_mode="rows"
 sfx_menu=false
 sfx_edit=false
 sfx_error=nil
 sfx_reset_input()
end

old_song_open_sfx=song_open_sfx
function song_open_sfx()
 old_song_open_sfx()
 sfx_open_from_song()
end

function sfx_raw_word()
 return bank_note_authored_raw(sfx_number,sfx_row)
end

function sfx_field_value(field,word)
 if field=="pitch" then return word&0x3f end
 if field=="inst" then return (word>>6)&7 end
 if field=="custom" then return (word>>15)&1 end
 if field=="volume" then return (word>>9)&7 end
 return (word>>12)&7
end

function sfx_field_word(field,word,value)
 if field=="pitch" then return (word&0xffc0)|value end
 if field=="inst" then return (word&0xfe3f)|(value<<6) end
 if field=="custom" then return (word&0x7fff)|(value<<15) end
 if field=="volume" then return (word&0xf1ff)|(value<<9) end
 return (word&0x8fff)|(value<<12)
end

function sfx_begin_row_edit()
 if sfx_is_waveform() then
  sfx_error="waveform slot read only"
  return false
 end
 local word=song_restore_then(sfx_raw_word)
 if word==nil then sfx_error="row unavailable" return false end
 sfx_edit_kind="word"
 sfx_edit_addr=bank_note_addr(sfx_number,sfx_row)
 sfx_edit_old=word
 sfx_edit_field=sfx_fields[sfx_field]
 sfx_edit_value=sfx_field_value(sfx_edit_field,word)
 sfx_edit=true
 return true
end

function sfx_begin_meta_edit()
 if sfx_is_waveform() then
  sfx_error="waveform metadata read only"
  return false
 end
 local index=sfx_meta_field
 sfx_edit_kind="meta"
 sfx_edit_addr=bank_sfx_addr(sfx_number,64+index)
 sfx_edit_old=bank_sfx_meta_raw(sfx_number,index)
 sfx_edit_field=sfx_meta_fields[index]
 sfx_edit_value=sfx_edit_old&0x1f
 sfx_edit_max=index==1 and 255 or 31
 if index==1 then sfx_edit_value=sfx_edit_old end
 sfx_edit=true
 return true
end

function sfx_cancel_edit()
 sfx_edit=false
 sfx_edit_field=nil
 sfx_reset_input()
end

function sfx_write_edit()
 if sfx_edit_kind=="word" then
  return bank_write_word(sfx_edit_addr,
   sfx_field_word(sfx_edit_field,sfx_edit_old,sfx_edit_value))
 end
 local raw=sfx_edit_old
 local value=sfx_edit_value
 if sfx_meta_field>1 then value=(raw&0xe0)|value end
 return bank_write_byte(sfx_edit_addr,value)
end

function sfx_commit_edit()
 local new=sfx_edit_kind=="word" and
  sfx_field_word(sfx_edit_field,sfx_edit_old,sfx_edit_value) or
  (sfx_meta_field>1 and ((sfx_edit_old&0xe0)|sfx_edit_value) or sfx_edit_value)
 if new==sfx_edit_old then sfx_cancel_edit() return true end
 local old_dirty=bank_dirty
 local old=sfx_edit_old
 local addr=sfx_edit_addr
 local kind=sfx_edit_kind
 local ok=song_restore_then(sfx_write_edit)
 if ok then
  sfx_undo_valid=true
  sfx_undo_kind=kind
  sfx_undo_addr=addr
  sfx_undo_value=old
  sfx_undo_dirty=old_dirty
  sfx_error=nil
 else sfx_error="edit rejected" end
 sfx_cancel_edit()
 return ok
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
  sfx_undo_valid=true
  sfx_undo_kind="word"
  sfx_undo_addr=addr
  sfx_undo_value=old
  sfx_undo_dirty=old_dirty
  sfx_error=nil
 end
 return ok
end

function sfx_undo()
 if not sfx_undo_valid then sfx_error="nothing to undo" return false end
 local ok=song_restore_then(function()
  if sfx_undo_kind=="word" then
   return bank_write_word(sfx_undo_addr,sfx_undo_value)
  end
  return bank_write_byte(sfx_undo_addr,sfx_undo_value)
 end)
 if ok then
  bank_dirty=sfx_undo_dirty
  sfx_undo_valid=false
  sfx_error=nil
  say("sfx undone")
 else sfx_error="undo rejected" end
 return ok
end

function sfx_open_menu()
 sfx_menu=true
 sfx_menu_item=1
 sfx_menu_gate=true
 sfx_x_consumed=true
end

function sfx_close_menu()
 sfx_menu=false
 sfx_menu_gate=false
 sfx_reset_input()
end

function sfx_change_slot(delta)
 if audition_active then stop_audition(true) end
 sfx_number=mid(0,sfx_number+delta,bank_sfx_count-1)
 sfx_error=nil
end

function sfx_apply_menu()
 local name=sfx_menu_items[sfx_menu_item]
 if name=="preview" then
  toggle_audition(sfx_mode=="rows" and sfx_row or nil) sfx_close_menu()
 elseif name=="metadata" then sfx_mode="meta" sfx_meta_field=1 sfx_close_menu()
 elseif name=="rest" then sfx_toggle_rest() sfx_close_menu()
 elseif name=="undo" then sfx_undo() sfx_close_menu()
 elseif name=="prev sfx" then sfx_change_slot(-1) sfx_close_menu()
 elseif name=="next sfx" then sfx_change_slot(1) sfx_close_menu() end
end

function update_sfx_menu()
 if sfx_menu_gate then
  if not btn(4) and not btn(5) then sfx_menu_gate=false end
  return
 end
 if btnp(2) then sfx_menu_item=(sfx_menu_item+#sfx_menu_items-2)%#sfx_menu_items+1
 elseif btnp(3) then sfx_menu_item=sfx_menu_item%#sfx_menu_items+1
 elseif btnp(4) then sfx_apply_menu()
 elseif btnp(5) then sfx_close_menu() end
end

function update_sfx_edit()
 if btnp(0) then
  local max=sfx_edit_kind=="meta" and sfx_edit_max or
   (sfx_edit_field=="pitch" and 63 or (sfx_edit_field=="custom" and 1 or 7))
  sfx_edit_value=(sfx_edit_value+max)%(max+1)
 elseif btnp(1) then
  local max=sfx_edit_kind=="meta" and sfx_edit_max or
   (sfx_edit_field=="pitch" and 63 or (sfx_edit_field=="custom" and 1 or 7))
  sfx_edit_value=(sfx_edit_value+1)%(max+1)
 elseif btnp(4) then sfx_commit_edit()
 elseif btnp(5) then sfx_cancel_edit() end
end

function sfx_update_actions(o_down,x_down)
 if o_down and x_down then
  if not sfx_chord_consumed then
   sfx_toggle_rest()
   sfx_chord_consumed=true
   sfx_o_consumed=true
   sfx_x_consumed=true
  end
  sfx_o_was_down=true
  sfx_x_was_down=true
  return true
 end
 if o_down then
  sfx_o_hold+=1
  if sfx_o_hold>=hold_frames and not sfx_o_consumed then
   sfx_o_consumed=true
   open_context_menu("start")
  end
 elseif sfx_o_was_down then
  if not sfx_o_consumed then
   if sfx_mode=="meta" then sfx_begin_meta_edit() else sfx_begin_row_edit() end
  end
  sfx_o_hold=0
  sfx_o_consumed=false
 end
 if x_down then
  sfx_x_hold+=1
  if sfx_x_hold>=hold_frames and not sfx_x_consumed then sfx_open_menu() end
 elseif sfx_x_was_down then
  if not sfx_x_consumed then
   if sfx_mode=="meta" then sfx_mode="rows" sfx_reset_input()
   else song_return_from_sfx() end
  end
  sfx_x_hold=0
  sfx_x_consumed=false
 end
 sfx_o_was_down=o_down
 sfx_x_was_down=x_down
 if not o_down and not x_down then sfx_chord_consumed=false end
 return o_down or x_down
end

function update_sfx_screen()
 if sfx_entry_gate then
  if not btn(4) and not btn(5) then sfx_entry_gate=false end
  return
 end
 if sfx_edit then return update_sfx_edit() end
 if sfx_menu then return update_sfx_menu() end
 if context_menu then
  update_context_menu(btn(4),btn(5),btnp(4),btnp(5),
   btnp(0),btnp(1),btnp(2),btnp(3))
  if not context_menu then sfx_reset_input() end
  return
 end
 if action_gate then
  if not btn(4) and not btn(5) then action_gate=false sfx_reset_input() end
  return
 end
 if sfx_update_actions(btn(4),btn(5)) then return end

 if sfx_mode=="meta" then
  if btnp(2) then sfx_meta_field=mid(1,sfx_meta_field-1,3)
  elseif btnp(3) then sfx_meta_field=mid(1,sfx_meta_field+1,3)
  end
 else
  if btnp(0) then sfx_field=mid(1,sfx_field-1,#sfx_fields)
  elseif btnp(1) then sfx_field=mid(1,sfx_field+1,#sfx_fields)
  elseif btnp(2) then sfx_row=mid(0,sfx_row-1,31) sfx_keep_visible()
  elseif btnp(3) then sfx_row=mid(0,sfx_row+1,31) sfx_keep_visible() end
 end
end

-- Replace Arc 1's read-only handoff without altering SONG's dispatch.
function update_sfx_handoff() update_sfx_screen() end

function sfx_note_text(word)
 if word==0 then return "---" end
 return hex2(word&0x3f)
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
   local text=hex2(row).." "..sfx_note_text(word).." "..
    ((word>>6)&7).." "..custom.." "..((word>>9)&7).." "..((word>>12)&7)
   print(text,4,y,row==sfx_row and 7 or 6)
   if row==sfx_row then
    local x=sfx_field_x[sfx_field]
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
 local labels={"speed "..raw[2],
  (raw[4]&0x1f)==0 and "len "..(raw[3]&0x1f) or "loop start "..(raw[3]&0x1f),
  "loop end "..(raw[4]&0x1f)}
 for i=1,3 do
  local y=47+(i-1)*13
  if i==sfx_meta_field then rectfill(15,y-2,112,y+7,1) end
  print((i==sfx_meta_field and "> " or "  ")..labels[i],22,y,i==sfx_meta_field and 7 or 6)
 end
 if sfx_is_waveform() then print("waveform metadata read only",11,91,8) end
 print("tap o edit/hold start x rows",7,106,5)
end

function draw_sfx_menu()
 rectfill(17,12,110,108,0)
 rect(17,12,110,108,12)
 print("sfx context",42,16,12)
 for i=1,#sfx_menu_items do
  local y=27+(i-1)*10
  local label=sfx_menu_items[i]
  if label=="preview" and audition_active then label="stop preview" end
  if label=="undo" and not sfx_undo_valid then label="undo -" end
  if i==sfx_menu_item then rectfill(24,y-2,103,y+6,5) end
  print((i==sfx_menu_item and "> " or "  ")..label,28,y,i==sfx_menu_item and 7 or 6)
 end
 print("o choose x back",35,100,5)
end

function draw_sfx_edit()
 rectfill(13,41,114,84,0)
 rect(13,41,114,84,11)
 print("edit "..sfx_edit_field,37,47,11)
 print("raw "..hex2(sfx_edit_old&0xff).." > "..hex2(sfx_edit_value),32,59,7)
 print("l/r value",45,69,6)
 print("o commit x cancel",31,78,5)
end

function draw_sfx_handoff()
 cls(0)
 rectfill(0,0,127,8,1)
 print("sfx "..hex2(sfx_number),2,2,12)
 print((sfx_is_waveform() and "wave" or (audition_active and "preview" or
  (bank_profile_is_active() and "profile" or "auth"))),42,2,6)
 print(bank_dirty and "dirty" or "clean",92,2,bank_dirty and 8 or 5)
 if sfx_mode=="meta" then draw_sfx_meta() else draw_sfx_rows() end
 if sfx_error then print("! "..sfx_error,2,117,8) end
 if sfx_menu then draw_sfx_menu() end
 if context_menu then draw_context_menu() end
 if sfx_edit then draw_sfx_edit() end
end
