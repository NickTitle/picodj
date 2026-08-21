-- native 64-slot, 32-row sfx editor

sfx_rows=9
sfx_fields={"pitch","inst","custom","volume","effect"}
sfx_field_x={16,32,40,48,56}
sfx_field_shift={0,6,15,9,12}
sfx_field_mask={0x3f,7,1,7,7}
sfx_field_keep={0xffc0,0xfe3f,0x7fff,0xf1ff,0x8fff}
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
 reset_action_input()
end

function sfx_open_from_song()
 sfx_row,sfx_scroll,sfx_field=0,0,1
 sfx_mode,sfx_error="rows",nil
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

function sfx_begin_row_edit()
 if sfx_is_waveform() then
  sfx_error="waveform slot read only"
  return false
 end
 local word=song_restore_then(sfx_raw_word)
 if word==nil then sfx_error="row unavailable" return false end
 return edit_begin("sfx",bank_note_addr(sfx_number,sfx_row),2,word,
  sfx_field_keep[sfx_field],sfx_field_shift[sfx_field],sfx_field_mask[sfx_field],sfx_fields[sfx_field])
end

function sfx_begin_meta_edit()
 if sfx_is_waveform() then
  sfx_error="waveform metadata read only"
  return false
 end
 local index=sfx_meta_field
 local old=bank_sfx_meta_raw(sfx_number,index)
 return edit_begin("sfx",bank_sfx_addr(sfx_number,64+index),1,old,
  index==1 and 0 or 0xe0,0,index==1 and 255 or 31,sfx_meta_fields[index])
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
  if not context_menu then sfx_reset_input() end
  return
 end
 if input_gated() then return end
 if update_action_buttons(btn(4),btn(5)) then return end

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

function draw_sfx_handoff()
 cls(0)
 rectfill(0,0,127,8,1)
 print("sfx "..hex2(sfx_number),2,2,12)
 print((sfx_is_waveform() and "wave" or (audition_active and "preview" or
  (bank_profile_is_active() and "profile" or "auth"))),42,2,6)
 print(bank_dirty and "dirty" or "clean",92,2,bank_dirty and 8 or 5)
 if sfx_mode=="meta" then draw_sfx_meta() else draw_sfx_rows() end
 if sfx_error then print("! "..sfx_error,2,117,8) end
 if context_menu then draw_context_menu() end
 if edit_owner=="sfx" then draw_edit() end
end
