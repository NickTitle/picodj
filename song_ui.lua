-- native song/pattern screen

song_expected_crc=0x2a23
song_rows=10
song_menu_items={"sfx","mute","flow","undo","play","follow"}
song_flow_names={"loop","back","stop","reserved"}

legacy_init=_init
legacy_update60=_update60
legacy_draw=_draw
legacy_context_label=context_label

-- The four-by-sixteen prototype remains a shadow sketch. It must never write
-- the native bank now that SONG is authoritative.
function rebuild_track() end
function rebuild_all() end
function audition() end

function native_io_pending()
 song_error="native i/o pending"
 say(song_error)
end

function save_song() native_io_pending() end
function load_song() native_io_pending() return false end
function request_export() native_io_pending() end

function context_label(name)
 if name=="save" or name=="load" or name=="json" or name=="wav" then
  return name.." - native pending"
 end
 return legacy_context_label(name)
end

function native_music(pattern)
 music(pattern)
end

function native_sfx(number,channel,offset,length)
 sfx(number,channel,offset,length)
end

function native_stat(index)
 return stat(index)
end

function start_song(pattern)
 if playing then return true end
 if audition_active then stop_audition(false) end
 if not bank_profile_apply() then
  song_error="profile apply failed"
  return false
 end
 song_play_pattern=pattern or song_pattern
 native_music(song_play_pattern)
 playing=true
 audition_restart=false
 transport_tick=0
 play_tick=0
 play_step=1
 song_error=nil
 say("playing pattern "..hex2(song_play_pattern))
 return true
end

function stop_song()
 if audition_active then stop_audition(false) end
 native_music(-1)
 bank_profile_restore()
 playing=false
 say("stopped")
 return true
end

function start_audition(row_only)
 if audition_active then stop_audition(false) end
 audition_restart=playing
 audition_restart_pattern=song_play_pattern
 if playing or bank_profile_is_active() then stop_song() end
 if not bank_audition_build(sfx_number,row_only) then
  song_error="preview unavailable"
  sfx_error=song_error
  if audition_restart then start_song(audition_restart_pattern) end
  return false
 end
 audition_active=true
 audition_tick=0
 audition_seen=false
 native_sfx(bank_audition_sfx,bank_audition_channel,0,row_only!=nil and 1 or nil)
 song_error=nil
 sfx_error=nil
 say("sfx preview")
 return true
end

function stop_audition(restart)
 if not audition_active then return true end
 local resume=restart and audition_restart
 local pattern=audition_restart_pattern
 native_sfx(-1,bank_audition_channel)
 bank_audition_restore()
 audition_active=false
 audition_restart=false
 if resume then return start_song(pattern) end
 return true
end

function toggle_audition(row_only)
 if audition_active then return stop_audition(true) end
 return start_audition(row_only)
end

function toggle_song()
 if playing then return stop_song() end
 return start_song()
end

function update_playhead()
 transport_tick+=1
 play_tick+=1
 if audition_active then
  audition_tick+=1
  local current=native_stat(46+bank_audition_channel)
  if current==bank_audition_sfx then audition_seen=true
  elseif audition_seen then
   stop_audition(true)
  end
 end
 if not playing or transport_tick<=2 then return end
 if not native_stat(57) then stop_song() return end
 play_pattern=native_stat(54)
 play_count=native_stat(55)
 play_ticks=native_stat(56)
 for channel=0,3 do
  local current=native_stat(46+channel)
  local row=native_stat(50+channel)
  if channel==song_channel then play_step=mid(0,row,31)+1 end
  if play_follow and app_view=="sfx" and current==sfx_number then
   sfx_row=mid(0,row,bank_row_count-1)
   sfx_keep_visible()
  end
 end
 if play_follow then
  song_pattern=mid(0,play_pattern,bank_pattern_count-1)
  song_keep_visible()
 end
end

function hex2(value)
 local digits="0123456789abcdef"
 return sub(digits,flr(value/16)+1,flr(value/16)+1)..
        sub(digits,value%16+1,value%16+1)
end

function song_keep_visible()
 if song_pattern<song_scroll then song_scroll=song_pattern end
 if song_pattern>=song_scroll+song_rows then
  song_scroll=song_pattern-song_rows+1
 end
 song_scroll=mid(0,song_scroll,bank_pattern_count-song_rows)
end

function song_move_pattern(delta)
 song_pattern=mid(0,song_pattern+delta,bank_pattern_count-1)
 song_keep_visible()
end

function song_move_channel(delta)
 song_channel=mid(0,song_channel+delta,bank_channel_count-1)
end

function open_song_screen()
 app_view="song"
 context_menu=nil
 song_entry_gate=true
 song_x_was_down=false
 song_x_hold=0
 song_x_consumed=false
 song_keep_visible()
 say("native song")
end

function song_open_menu()
 song_menu=true
 song_menu_item=1
 song_menu_gate=true
 song_x_consumed=true
end

function song_close_menu()
 song_menu=false
 song_menu_gate=false
 song_entry_gate=true
 song_x_was_down=false
 song_x_hold=0
 song_x_consumed=false
end

function song_edit_candidate(delta)
 if song_edit_field=="sfx" then
  local value=((song_edit_value&0x3f)+delta)%64
  song_edit_value=(song_edit_value&0xc0)|value
 else
  song_edit_value=song_edit_value^^song_edit_mask
 end
end

function song_begin_edit(field)
 local addr=bank_song_addr(song_pattern,song_channel)
 if not addr then return false end
 if field=="flow" and song_channel==3 then
  song_error="ch4 flag is reserved"
  return false
 end
 song_edit_field=field
 song_edit_addr=addr
 song_edit_old=peek(addr)
 song_edit_value=song_edit_old
 song_edit_mask=field=="mute" and 0x40 or 0x80
 if field!="sfx" then song_edit_candidate(1) end
 song_menu=false
 song_edit=true
 return true
end

function song_cancel_edit()
 song_edit=false
 song_edit_field=nil
 song_entry_gate=true
end

function song_restore_then(action)
 local restart=playing or (audition_active and audition_restart)
 local restart_pattern=playing and song_play_pattern or audition_restart_pattern
 if audition_active then stop_audition(false) end
 if playing or bank_profile_is_active() then stop_song() end
 local ok=action()
 if restart then start_song(restart_pattern) end
 return ok
end

function song_commit_edit()
 if song_edit_value==song_edit_old then
  song_cancel_edit()
  return true
 end
 local old_dirty=bank_dirty
 local old_revision=bank_revision
 local old_value=song_edit_old
 local addr=song_edit_addr
 local ok=song_restore_then(function()
  return bank_write_byte(addr,song_edit_value)
 end)
 if ok then
  song_undo_valid=true
  song_undo_addr=addr
  song_undo_value=old_value
  song_undo_dirty=old_dirty
  song_undo_revision=old_revision
  song_error=nil
 else
  song_error="edit rejected"
 end
 song_cancel_edit()
 return ok
end

function song_undo()
 if not song_undo_valid then
  song_error="nothing to undo"
  return false
 end
 local ok=song_restore_then(function()
  return bank_write_byte(song_undo_addr,song_undo_value)
 end)
 if ok then
  bank_dirty=song_undo_dirty
  song_undo_valid=false
  song_error=nil
  say("undone")
 else
  song_error="undo rejected"
 end
 return ok
end

function song_open_sfx()
 sfx_pattern=song_pattern
 sfx_channel=song_channel
 sfx_number=bank_pattern_sfx(song_pattern,song_channel)
 app_view="sfx"
 song_entry_gate=true
end

function song_return_from_sfx()
 if audition_active then stop_audition(true) end
 app_view="song"
 song_entry_gate=true
end

function song_apply_menu()
 local name=song_menu_items[song_menu_item]
 if name=="sfx" then song_begin_edit("sfx")
 elseif name=="mute" then song_begin_edit("mute")
 elseif name=="flow" then song_begin_edit("flow")
 elseif name=="undo" then song_undo() song_close_menu()
 elseif name=="play" then toggle_song() song_close_menu()
 elseif name=="follow" then play_follow=not play_follow song_close_menu() end
end

function update_song_edit()
 if btnp(0) then song_edit_candidate(-1)
 elseif btnp(1) then song_edit_candidate(1)
 elseif btnp(4) then song_commit_edit()
 elseif btnp(5) then song_cancel_edit() end
end

function update_song_menu()
 if song_menu_gate then
  if not btn(4) and not btn(5) then song_menu_gate=false end
  return
 end
 if btnp(2) then
  song_menu_item=(song_menu_item+#song_menu_items-2)%#song_menu_items+1
 elseif btnp(3) then
  song_menu_item=song_menu_item%#song_menu_items+1
 elseif btnp(4) then song_apply_menu()
 elseif btnp(5) then song_close_menu() end
end

function song_update_x(x_down)
 if x_down then
  song_x_hold+=1
  if song_x_hold>=hold_frames and not song_x_consumed then
   song_open_menu()
  end
 elseif song_x_was_down then
  if not song_x_consumed then app_view="grid" action_gate=true end
  song_x_hold=0
  song_x_consumed=false
 end
 song_x_was_down=x_down
 return x_down
end

function update_song_screen()
 if song_entry_gate then
  if not btn(4) and not btn(5) then song_entry_gate=false end
  return
 end
 if song_edit then return update_song_edit() end
 if song_menu then return update_song_menu() end

 if song_update_x(btn(5)) then return end

 if btnp(0) then song_move_channel(-1)
 elseif btnp(1) then song_move_channel(1)
 elseif btnp(2) then song_move_pattern(-1)
 elseif btnp(3) then song_move_pattern(1)
 elseif btnp(4) then song_open_sfx() end
end

function _init()
 legacy_init()
 bank_project_init()
 app_view="grid"
 song_pattern=0
 song_channel=0
 song_scroll=0
 song_menu=false
 song_menu_item=1
 song_menu_gate=false
 song_edit=false
 song_entry_gate=false
 song_x_was_down=false
 song_x_hold=0
 song_x_consumed=false
 song_undo_valid=false
 song_error=nil
 audition_active=false
 audition_restart=false
 transport_tick=0
 play_pattern=0
 play_count=0
 play_ticks=0
 play_follow=true
 if (bank_checksum(bank_audio_base)&0xffff)!=song_expected_crc then
  song_error="native seed mismatch"
 end
end

function _update60()
 if app_view=="grid" then return legacy_update60() end
 update_playhead()
 if notice_tick>0 then notice_tick-=1 end
 if app_view=="song" then update_song_screen()
 else update_sfx_handoff() end
end

function draw_header()
 rectfill(0,0,127,8,1)
 print("legacy sketch",2,2,7)
 print(song_error and "!" or (playing and "play" or "stop"),82,2,song_error and 8 or (playing and 11 or 6))
 print(bank_dirty and "*" or "-",118,2,bank_dirty and 8 or 5)
end

function song_status()
 local text=playing and "p"..hex2(play_pattern).." r"..hex2(play_step-1) or
  (audition_active and "preview" or "stop "..hex2(song_pattern))
 text..=bank_dirty and " dirty" or " clean"
 if song_error then text="! "..song_error end
 return text
end

function flow_glyph(pattern,channel)
 if channel==3 then return "r" end
 return bank_pattern_flag(pattern,channel) and sub("lbs",channel+1,channel+1) or "-"
end

function draw_song_screen()
 cls(0)
 rectfill(0,0,127,8,1)
 print("song",2,2,12)
 print(song_status(),25,2,song_error and 8 or 7)
 print("pt",2,11,5)
 for ch=0,3 do print("c"..(ch+1),29+ch*24,11,ch+8) end
 for row=0,song_rows-1 do
  local pattern=song_scroll+row
  local y=19+row*8
  if pattern==song_pattern then rectfill(0,y-1,127,y+6,1) end
  print(hex2(pattern),2,y,pattern==song_pattern and 7 or 6)
  for ch=0,3 do
   local x=25+ch*24
   if pattern==song_pattern and ch==song_channel then rect(x-2,y-2,x+19,y+6,10) end
   local muted=bank_pattern_muted(pattern,ch)
   local cell=hex2(bank_pattern_sfx(pattern,ch))..(muted and "m" or "-")..flow_glyph(pattern,ch)
   print(cell,x,y,ch+8)
  end
 end
 print("dpad move o sfx hold x menu",4,101,5)
 print("tap x back",44,109,6)
 if song_menu then draw_song_menu() end
 if song_edit then draw_song_edit() end
end

function draw_song_menu()
 rectfill(17,22,110,101,0)
 rect(17,22,110,101,12)
 print("song context",40,27,12)
 for i=1,#song_menu_items do
  local y=38+(i-1)*9
  local name=song_menu_items[i]
  local label=name
  if name=="flow" then label=song_flow_names[song_channel+1]
  elseif name=="play" then label=playing and "stop" or "play"
  elseif name=="follow" then label=play_follow and "follow on" or "follow off"
  elseif name=="undo" and not song_undo_valid then label="undo -" end
  if i==song_menu_item then rectfill(25,y-2,102,y+6,5) end
  print((i==song_menu_item and "> " or "  ")..label,29,y,i==song_menu_item and 7 or 6)
 end
 print("o choose x back",35,91,5)
end

function draw_song_edit()
 rectfill(14,42,113,83,0)
 rect(14,42,113,83,11)
 print("edit "..song_edit_field,43,48,11)
 print("raw "..hex2(song_edit_old).." > "..hex2(song_edit_value),34,59,7)
 if song_edit_field=="sfx" then print("l/r value",46,68,6) end
 print("o commit x cancel",32,76,5)
end

function _draw()
 if app_view=="song" then draw_song_screen()
 elseif app_view=="sfx" then draw_sfx_handoff()
 else legacy_draw() end
end
