-- shared six-button input and menus for the native tracker

hold_frames=18
start_menu={"play","save","load"}

function say(text)
 notice=text
 notice_tick=120
end

function reset_action_input()
 o_was_down,x_was_down=false,false
 o_hold,x_hold=0,0
 o_consumed,x_consumed,chord_consumed=false,false,false
end

function context_items()
 if context_menu=="start" then return start_menu end
 if context_menu=="song" then return song_menu_items end
 return sfx_menu_items
end

function open_context_menu(kind)
 context_menu,context_item,context_gate=kind,1,true
 say(kind.." menu")
end

function close_context_menu()
 context_menu=nil
 context_gate=false
 action_gate=true
 reset_action_input()
end

function context_apply(name)
 if context_menu=="start" then
  if name=="play" then toggle_song()
  elseif name=="save" then save_song()
  else load_song(true) end
 elseif context_menu=="song" then
  if context_item<=3 then song_begin_edit(name)
  elseif name=="undo" then song_undo()
  elseif name=="play" then toggle_song()
  else play_follow=not play_follow end
 else
  if name=="preview" then toggle_audition(sfx_mode=="rows" and sfx_row or nil)
  elseif name=="metadata" then sfx_mode="meta" sfx_meta_field=1
  elseif name=="rest" then sfx_toggle_rest()
  elseif name=="undo" then sfx_undo()
  else sfx_change_slot(name=="prev sfx" and -1 or 1) end
 end
 close_context_menu()
end

function update_context_menu(o_down,x_down,o_pressed,x_pressed,left_pressed,right_pressed,up_pressed,down_pressed)
 if context_gate then
  if not o_down and not x_down then context_gate=false end
  return
 end
 local items=context_items()
 if up_pressed then context_item=(context_item+#items-2)%#items+1
 elseif down_pressed then context_item=context_item%#items+1
 elseif x_pressed then close_context_menu()
 elseif o_pressed then context_apply(items[context_item]) end
end

function update_action_buttons(o_down,x_down)
 local active=o_down or x_down or o_was_down or x_was_down
 local view=app_view or "song"
 if o_down and x_down then
  if view=="sfx" and not chord_consumed then
   sfx_toggle_rest()
   chord_consumed,o_consumed,x_consumed=true,true,true
  end
 elseif o_down then
  o_hold+=1
  if o_hold>=hold_frames and not o_consumed then
   o_consumed=true
   open_context_menu("start")
  end
 elseif x_down then
  x_hold+=1
  if x_hold>=hold_frames and not x_consumed then
   x_consumed=true
   open_context_menu(view)
  end
 end
 if not o_down and o_was_down then
  if not o_consumed then
   if view=="song" then song_open_sfx()
   elseif sfx_mode=="meta" then sfx_begin_meta_edit()
   else sfx_begin_row_edit() end
  end
  o_hold,o_consumed=0,false
 end
 if not x_down and x_was_down then
  if not x_consumed and view=="sfx" then
   if sfx_mode=="meta" then sfx_mode="rows" else song_return_from_sfx() end
  end
  x_hold,x_consumed=0,false
 end
 if not o_down and not x_down then chord_consumed=false end
 o_was_down,x_was_down=o_down,x_down
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
 if name=="undo" then
  if undo_owner!=(context_menu=="sfx" and "sfx" or "song") then return "undo -" end
  return undo_width<0 and "redo" or "undo"
 end
 if name=="preview" then return audition_active and "stop preview" or "preview" end
 return name
end

function draw_context_menu()
 local items=context_items()
 rectfill(9,13,118,105,0) rect(9,13,118,105,12)
 local title=context_menu=="start" and "project" or context_menu.." context"
 print(title,64-#title*2,18,12)
 for i=1,#items do
  local y=27+(i-1)*9
  local label=context_label(items[i])
  if i==context_item then rectfill(14,y-2,113,y+6,5) print(">",17,y,7) end
  print(label,25,y,i==context_item and 7 or 6)
 end
 print("o choose  x back",35,96,5)
end
