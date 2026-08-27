pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
#include ../tracker.lua

failures=0
song_menu_items={"sfx","mute","flow","mix","undo","play","follow"}
sfx_menu_items=split"preview,metadata,filters,row ops,undo,prev sfx,next sfx"
sfx_row_menu=split"rest,copy rows,paste rows,clear rows"

function check(ok,label)
 if ok then return end
 failures+=1
 printh("fail: "..label)
end

function save_song() save_calls+=1 end
function load_song() load_calls+=1 end
function toggle_song() play_calls+=1 end
function song_open_sfx() sfx_open_calls+=1 app_view="sfx" end
function song_return_from_sfx() return_calls+=1 app_view="song" end
function sfx_begin_edit() edit_calls+=1 end
function sfx_toggle_rest() rest_calls+=1 end
function sfx_rows_begin(op) row_op=op return true end
function song_mix_apply() mix_apply_calls+=1 end
function song_mix_label(mode,channel)
 return mode==0 and "all" or sub("ms",mode,mode)..(channel+1)
end

function reset_fixture(view)
 app_view=view or "song"
 context_menu,context_item,context_gate,action_gate=nil,1,false,false
 playing,play_follow=false,true
 song_channel=1
 song_mix,song_mix_channel,song_mix_stage=0,0,0
 save_calls,load_calls,play_calls=0,0,0
 sfx_open_calls,return_calls,edit_calls,rest_calls=0,0,0,0
 mix_apply_calls=0
 row_op=nil
 sfx_mode="rows"
 notice=""
 undo_owner=nil undo_width=1
 reset_action_input()
end

function release_context_gate()
 update_context_menu(false,false,false,false,false,false,false,false)
end

function _init()
 -- Native SONG is primary: quick O enters SFX and quick X cannot reveal GRID.
 reset_fixture("song")
 update_action_buttons(true,false)
 check(sfx_open_calls==0,"o tap waits for release")
 update_action_buttons(false,false)
 check(sfx_open_calls==1 and app_view=="sfx","o tap opens selected sfx")
 reset_fixture("song")
 update_action_buttons(false,true)
 update_action_buttons(false,false)
 check(app_view=="song","song x tap stays native")

 -- Hold O opens project actions from SONG without leaking the SFX tap.
 reset_fixture("song")
 for i=1,hold_frames do update_action_buttons(true,false) end
 check(context_menu=="start" and context_gate,"o hold opens project menu")
 check(sfx_open_calls==0,"o hold does not open sfx")
 release_context_gate()
 update_context_menu(false,false,false,false,false,false,false,true)
 check(context_item==2,"project menu reaches save")
 update_context_menu(false,false,true,false,false,false,false,false)
 check(save_calls==1 and context_menu==nil,"project save action")

 -- Hold X opens the current native context without leaking a back action.
 reset_fixture("song")
 for i=1,hold_frames do update_action_buttons(false,true) end
 check(context_menu=="song" and context_gate,"x hold opens song menu")
 close_context_menu()
 check(app_view=="song" and action_gate,"song menu closes release gated")

 -- Mix staging is transient until O applies; X discards it.
 reset_fixture("song") open_context_menu("song") release_context_gate()
 context_item=4
 update_context_menu(false,false,false,false,false,true,false,false)
 check(song_mix_stage==1 and context_label("mix")=="mix m2","mix right stages mute")
 update_context_menu(false,false,false,true,false,false,false,false)
 check(mix_apply_calls==0 and context_menu==nil,"mix x cancels")
 action_gate=false open_context_menu("song") release_context_gate() context_item=4
 update_context_menu(false,false,false,false,true,false,false,false)
 check(song_mix_stage==2 and context_label("mix")=="mix s2","mix left stages solo")
 update_context_menu(false,false,true,false,false,false,false,false)
 check(mix_apply_calls==1 and context_menu==nil,"mix o applies")

 -- The history row names the next available direction for each owner.
 context_menu="song" undo_owner="song" undo_width=1
 check(context_label("undo")=="undo","song undo label")
 undo_width=-1
 check(context_label("undo")=="redo","song redo label")
 context_menu="sfx"
 check(context_label("undo")=="undo -","other owner unavailable")
 undo_owner="sfx"
 check(context_label("undo")=="redo","sfx redo label")
 context_apply("filters")
 check(sfx_mode=="filters" and sfx_filter_field==1,"filter menu route")
 context_menu="sfx" context_apply("metadata")
 check(sfx_mode=="meta" and sfx_meta_field==1,"metadata menu route")
 context_menu="sfx" context_apply("row ops")
 check(context_menu=="row ops" and context_gate,"row ops submenu")
 context_gate=false context_item=2 context_apply("copy rows")
 check(row_op==1 and context_menu==nil,"copy rows route")
 context_menu=nil

 -- The SFX chord remains one rest toggle and quick X returns to SONG.
 reset_fixture("sfx")
 update_action_buttons(true,true)
 for i=1,hold_frames+2 do update_action_buttons(true,true) end
 check(rest_calls==1 and context_menu==nil,"sfx chord toggles rest once")
 update_action_buttons(false,false)
 reset_action_input()
 update_action_buttons(false,true)
 update_action_buttons(false,false)
 check(return_calls==1 and app_view=="song","sfx x tap returns to song")

 reset_fixture("sfx") sfx_mode="filters"
 update_action_buttons(true,false) update_action_buttons(false,false)
 check(edit_calls==1,"filter o tap edits")
 reset_fixture("sfx") sfx_mode="filters"
 update_action_buttons(false,true) update_action_buttons(false,false)
 check(sfx_mode=="rows" and return_calls==0,"filter x tap returns to rows")

 if failures==0 then printh("pocket tracker hold menus: passed")
 else printh("pocket tracker hold menus: failed "..failures) end
 extcmd("shutdown")
end

__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
