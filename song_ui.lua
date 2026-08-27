-- native song/pattern screen

song_expected_crc,song_rows=0x2a23,10
song_menu_items=split"sfx,mute,flow,mix,undo,play,follow"
song_flow_names=split"loop,back,stop,reserved"

native_music=music
native_sfx=sfx
native_stat=stat

function start_song(pattern)
 if playing then return true end
 if audition_active then stop_audition(false) end
 if not bank_profile_apply() then
  song_error="profile apply failed"
  return false
 end
 song_play_pattern=pattern or song_pattern
 native_music(song_play_pattern,nil,song_mix==2 and 1<<song_mix_channel or
  0xf^^(song_mix<<song_mix_channel))
 playing=true
 audition_restart=false
 transport_tick=0
 play_step=1
 song_error=nil
 return true
end

function stop_song()
 if audition_active then stop_audition(false) end
 native_music(-1)
 bank_profile_restore()
 playing=false
 song_active="a----"
 return true
end

function song_mix_label(mode,channel)
 return mode==0 and "all" or sub("ms",mode,mode)..(channel+1)
end

function song_mix_apply()
 song_mix,song_mix_channel=song_mix_stage,song_channel
 if playing then
  stop_song()
  start_song(song_play_pattern)
 end
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

function toggle_song()
 return playing and stop_song() or start_song()
end

function update_playhead()
 transport_tick+=1
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
 song_play_pattern=native_stat(54)
 song_active="a"
 for channel=0,3 do
  local current=native_stat(46+channel)
  local row=native_stat(50+channel)
  song_active..=current>=0 and channel+1 or "-"
  if channel==song_channel then play_step=mid(0,row,31)+1 end
  if play_follow and app_view=="sfx" and current==sfx_number then
   sfx_row=mid(0,row,bank_row_count-1)
   sfx_keep_visible()
  end
 end
 if play_follow then
  song_pattern=mid(0,song_play_pattern,bank_pattern_count-1)
  song_keep_visible()
 end
end

function hex2(value)
 return sub(tostr(value,true),5,6)
end

function song_keep_visible()
 song_scroll=mid(song_pattern-song_rows+1,song_scroll,song_pattern)
 song_scroll=mid(0,song_scroll,bank_pattern_count-song_rows)
end

function song_move_pattern(delta)
 song_pattern=mid(0,song_pattern+delta,bank_pattern_count-1)
 song_keep_visible()
end

function song_move_channel(delta)
 song_channel=mid(0,song_channel+delta,bank_channel_count-1)
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

function edit_error(owner,text)
 if owner=="song" then song_error=text else sfx_error=text end
end

function edit_begin(owner,addr,width,old,keep,shift,max_value,label)
 edit_owner=owner edit_addr=addr edit_width=width edit_old=old
 edit_keep=keep edit_shift=shift edit_max=max_value edit_label=label
 edit_value=shift<0 and flr(old/-shift)%(max_value+1) or (old>>shift)&max_value
 edit_dirty=bank_dirty
 return true
end

function edit_cancel()
 edit_owner=nil
 action_gate=true reset_action_input()
end

function edit_write(addr,width,value)
 if width==1 then return bank_write_byte(addr,value) end
 return bank_write_word(addr,value)
end

function edit_commit()
 local owner=edit_owner
 local value=edit_shift<0 and edit_old+(edit_value-flr(edit_old/-edit_shift)%(edit_max+1))*-edit_shift or (edit_old&edit_keep)|(edit_value<<edit_shift)
 if value==edit_old then edit_cancel() return true end
 local ok=song_restore_then(function() return edit_write(edit_addr,edit_width,value) end)
 if ok then
  undo_owner=owner undo_addr=edit_addr undo_width=edit_width
  undo_value=edit_old undo_dirty=edit_dirty edit_error(owner,nil)
 else edit_error(owner,"edit rejected") end
 edit_cancel()
 return ok
end

function edit_undo(owner)
 if undo_owner!=owner then edit_error(owner,"nothing to undo") return false end
 local width=abs(undo_width)
 local value,dirty=nil,bank_dirty
 local ok=song_restore_then(function()
  value=width==1 and peek(undo_addr) or peek2(undo_addr)
  return edit_write(undo_addr,width,undo_value)
 end)
 if ok then
  undo_value=value bank_dirty=undo_dirty undo_dirty=dirty undo_width=-undo_width
  edit_error(owner,nil)
 else edit_error(owner,"undo rejected") end
 return ok
end

function edit_update()
 if btnp(0) then edit_value=(edit_value+edit_max)%(edit_max+1)
 elseif btnp(1) then edit_value=(edit_value+1)%(edit_max+1)
 elseif btnp(4) then edit_commit()
 elseif btnp(5) then edit_cancel() end
end

function draw_edit()
 rectfill(13,44,114,78,0)
 print("edit "..edit_label,32,49,11)
 print("raw "..hex2(edit_old&0xff).." value "..hex2(edit_value),25,60,7)
 print("l/r  o commit  x cancel",21,70,5)
end

function song_begin_edit(field)
 local addr=bank_song_addr(song_pattern,song_channel)
 if not addr then return false end
 if field=="flow" and song_channel==3 then song_error="ch4 flag is reserved" return false end
 local shift=field=="sfx" and 0 or (field=="mute" and 6 or 7)
 local ok=edit_begin("song",addr,1,peek(addr),field=="sfx" and 0xc0 or
  (field=="mute" and 0xbf or 0x7f),shift,field=="sfx" and 63 or 1,field)
 if field!="sfx" then edit_value=1-edit_value end
 return ok
end

function song_open_sfx()
 sfx_pattern=song_pattern
 sfx_channel=song_channel
 sfx_number=bank_pattern_sfx(song_pattern,song_channel)
 app_view="sfx"
 sfx_row,sfx_scroll,sfx_field=0,0,1
 sfx_mode,sfx_error="rows",nil
 action_gate=true reset_action_input()
end

function song_return_from_sfx()
 if audition_active then stop_audition(true) end
 app_view="song"
 action_gate=true reset_action_input()
end

function update_song_screen()
 if input_gated() then return end
 if edit_owner=="song" then return edit_update() end
 if context_menu then
  update_context_menu(btn(4),btn(5),btnp(4),btnp(5),btnp(0),btnp(1),btnp(2),btnp(3))
  return
 end

 if update_action_buttons(btn(4),btn(5)) then return end

 if btnp(0) then song_move_channel(-1)
 elseif btnp(1) then song_move_channel(1)
 elseif btnp(2) then song_move_pattern(-1)
 elseif btnp(3) then song_move_pattern(1)
 elseif btnp(4) then song_open_sfx() end
end

function _init()
 bank_project_init()
 app_view="song"
 context_menu,context_item,context_gate,action_gate=nil,1,false,false
 reset_action_input()
 playing,play_step=false,1
 song_pattern,song_channel,song_scroll=0,0,0
 edit_owner,undo_owner,song_error=nil,nil,nil
 audition_active,audition_restart=false,false
 transport_tick=0
 play_follow=true
 song_mix,song_mix_channel,song_mix_stage,song_active=0,0,0,"a----"
 if (bank_checksum(bank_audio_base)&0xffff)!=song_expected_crc then
  song_error="native seed mismatch"
 end
end

function _update60()
 update_playhead()
 if app_view=="song" then update_song_screen()
 else update_sfx_screen() end
end

function song_status()
 local text=playing and "p"..hex2(song_play_pattern).." r"..hex2(play_step-1) or
  (audition_active and "preview" or "stop "..hex2(song_pattern))
 text..=bank_dirty and " dirty" or " clean"
 text..=" "..song_mix_label(song_mix,song_mix_channel).." "..song_active
 if song_error then text="! "..song_error end
 return text
end

function flow_glyph(pattern,channel)
 return (channel==3 or bank_pattern_flag(pattern,channel)) and
  sub("lbsr",channel+1,channel+1) or "-"
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
   print(hex2(bank_pattern_sfx(pattern,ch))..
    (bank_pattern_muted(pattern,ch) and "m" or "-")..flow_glyph(pattern,ch),x,y,ch+8)
  end
 end
 print("dpad move o sfx hold x menu",4,101,5)
 print("hold o project",35,109,6)
 if edit_owner=="song" then draw_edit() end
end

function _draw()
 if app_view=="song" then
  draw_song_screen()
  if context_menu then draw_context_menu() end
 else draw_sfx_handoff() end
end
