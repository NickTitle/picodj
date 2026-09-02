-- shared six-button input and menus for the native tracker

hold_frames=18
dpad_hold,dpad_pressed={0,0,0,0},{}
start_menu=split"play,save browser slot,load browser slot,save data cart,load data cart"

function reset_action_input()
 o_hold,x_hold=0,0
 dpad_update()
end

function dpad_step(i,down)
 local n=down and dpad_hold[i]+1 or 0
 if n>49 then n=48 end
 dpad_hold[i]=n
 return n==1 or n>=16 and n%(n<48 and 4 or 2)==0
end

function dpad_update(on)
 for i=1,4 do dpad_pressed[i]=dpad_step(i,on and btn(i-1)) end
end

function context_items()
 return context_menu=="start" and start_menu or
  (context_menu=="song" and song_menu_items or
  (context_menu=="row ops" and sfx_row_menu or sfx_menu_items))
end

function open_context_menu(kind)
 context_menu,context_item,context_gate=kind,1,true
 song_mix_stage=song_mix_channel==song_channel and song_mix or 0
end

function close_context_menu()
 context_menu=nil
 action_gate=true
 reset_action_input()
end

function context_apply(name)
 if context_menu=="start" then
  if name=="play" then toggle_song()
  elseif name=="save browser slot" then save_song()
  elseif name=="load browser slot" then load_song()
  elseif name=="save data cart" then native_save()
  else native_load() end
 elseif context_menu=="song" then
  if context_item<=3 then song_begin_edit(name)
  elseif name=="mix" then song_mix_apply()
  elseif name=="undo" then edit_undo("song")
  elseif name=="play" then toggle_song()
  else play_follow=not play_follow end
 else
  if context_menu=="row ops" then
   if name=="rest" then sfx_toggle_rest() else sfx_rows_begin(context_item-1) end
  elseif name=="row ops" then open_context_menu(name) return
  elseif name=="preview" then
   if audition_active then stop_audition(true)
   else start_audition(sfx_mode=="rows" and sfx_row or nil) end
  elseif name=="metadata" then sfx_mode="meta" sfx_meta_field=1
  elseif name=="filters" then sfx_mode="filters" sfx_filter_field=1
  elseif name=="undo" then edit_undo("sfx")
  else sfx_change_slot(name=="prev sfx" and -1 or 1) end
 end
 close_context_menu()
end

function update_context_menu(o_down,x_down,o_pressed,x_pressed,left_pressed,right_pressed,up_pressed,down_pressed)
 if context_gate then
  context_gate=o_down or x_down
  return
 end
 local items=context_items()
 if (left_pressed or right_pressed) and items[context_item]=="mix" then
  song_mix_stage=(song_mix_stage+(right_pressed and 1 or 2))%3
 elseif up_pressed then context_item=(context_item+#items-2)%#items+1
 elseif down_pressed then context_item=context_item%#items+1
 elseif x_pressed then close_context_menu()
 elseif o_pressed then context_apply(items[context_item]) end
end

function update_action_buttons(o_down,x_down)
 local active=o_down or x_down or o_hold!=0 or x_hold!=0
 local view=app_view or "song"
 if o_down and x_down then
  if view=="sfx" and o_hold>=0 and x_hold>=0 then
   sfx_toggle_rest()
   o_hold,x_hold=-1,-1
  elseif view=="song" then o_hold,x_hold=1,1
  end
 elseif o_down then
  if o_hold>=0 then o_hold+=1 end
  if o_hold>=hold_frames then
   o_hold=-1
   open_context_menu("start")
  end
 elseif x_down then
  if x_hold>=0 then x_hold+=1 end
  if x_hold>=hold_frames then
   x_hold=-1
   if view=="sfx" and sfx_row_op then sfx_row_op=nil
   else open_context_menu(view) end
  end
 end
 if not o_down and o_hold!=0 then
  if o_hold>0 then
   if view=="song" then song_open_sfx()
   else sfx_begin_edit() end
  end
  o_hold=0
 end
 if not x_down and x_hold!=0 then
  if x_hold>0 and view=="sfx" then
   if sfx_row_op then sfx_row_op=nil
   elseif sfx_mode!="rows" then sfx_mode="rows" else song_return_from_sfx() end
  end
  x_hold=0
 end
 return active
end

function input_gated()
 if not action_gate then return false end
 if not btn(4) and not btn(5) then action_gate=false reset_action_input() end
 return true
end

function context_label(name)
 if name=="play" then return playing and "stop playback" or "start playback" end
 if name=="flow" then return song_flow_names[song_channel+1] end
 if name=="follow" then return play_follow and "follow on" or "follow off" end
 if name=="mix" then return "mix "..song_mix_label(song_mix_stage,song_channel) end
 if name=="undo" then
  if undo_owner!=(context_menu=="sfx" and "sfx" or "song") then return "undo -" end
  return undo_width<0 and "redo" or "undo"
 end
 if name=="preview" then return audition_active and "stop preview" or "preview" end
 return name
end

function draw_context_menu()
 local items=context_items()
 rectfill(9,13,118,105,0)
 print(context_menu=="start" and "project" or context_menu,16,18,12)
 for i=1,#items do
  local picked=i==context_item
  print((picked and "> " or "  ")..context_label(items[i]),16,19+i*10,picked and 7 or 6)
 end
end
