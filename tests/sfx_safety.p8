pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
#include ../audio_bank.lua
#include ../tracker.lua
#include ../song_ui.lua
#include ../sfx_ui.lua
fails=0
hold_frames=18
function say() end
function song_restore_then(action) return action() end
function song_return_from_sfx() app_view="song" end
function ck(v,s) if not v then fails+=1 printh("fail: "..s) end end
function setup(slot)
 reload(bank_audio_base,bank_audio_base,bank_size,"../pocket-tracker.p8")
 bank_project_init() playing=false audition_active=false
 song_pattern=0 song_channel=0 song_play_pattern=0 app_view="sfx"
 sfx_number=slot sfx_row=0 sfx_scroll=0 sfx_field=1 sfx_mode="rows"
 edit_owner=nil undo_owner=nil sfx_error=nil
 context_menu=nil context_gate=false action_gate=false reset_action_input()
end
function _init()
 setup(0)
 poke(bank_sfx_addr(0,66),peek(bank_sfx_addr(0,66))|0x80)
 bank_project_init()
 local bytes={}
 for i=0,67 do add(bytes,peek(bank_sfx_addr(0,i))) end
 ck(sfx_begin_edit() and edit_width==1 and edit_value==bytes[1],"wave row edit")
 edit_value=(edit_value+1)%256 edit_cancel()
 ck(peek(bank_sfx_addr(0,0))==bytes[1],"wave cancel exact")
 sfx_error=nil sfx_mode="meta" sfx_meta_field=1
 ck(sfx_begin_edit() and edit_label=="bass" and edit_value==
  (bank_sfx_meta_raw(0,1)&1),"wave bass allowed")
 edit_cancel()
 sfx_meta_field=2
 ck(sfx_begin_edit() and edit_label=="mode" and edit_value==1,"wave mode allowed")
 edit_cancel()
 sfx_error=nil sfx_mode="filters" sfx_filter_field=1
 ck(not sfx_begin_edit() and sfx_error!=nil,"wave filter reject")
 sfx_error=nil
 ck(not sfx_rows_begin(1) and not sfx_rows_begin(3),"wave row ops reject")
 for i=0,67 do
  ck(peek(bank_sfx_addr(0,i))==bytes[i+1],"wave byte "..i)
 end
 ck(not bank_dirty and bank_revision==0,"wave bytes exact clean")
 setup(8) sfx_mode="meta" sfx_meta_field=4
 ck(not sfx_begin_edit() and sfx_error=="mode unavailable" and
  not bank_dirty and bank_revision==0,"mode sfx8 exact reject")
 setup(63)
 sfx_clip_count=0
 ck(not sfx_rows_begin(2) and sfx_error=="clipboard empty","empty paste reject")
 ck(not bank_dirty and bank_revision==0 and undo_owner==nil,"empty paste exact")
 setup(63)
 ck(sfx_rows_begin(1),"range begin")
 for i=1,hold_frames do update_action_buttons(false,true) end
 ck(not sfx_row_op and not context_menu,"hold x cancels range")
 update_action_buttons(false,false)
 setup(63)
 for i=1,hold_frames do update_action_buttons(false,true) end
 ck(context_menu=="sfx" and context_gate,"hold x menu")
 close_context_menu() action_gate=false reset_action_input()
 update_action_buttons(false,true) update_action_buttons(false,false)
 ck(app_view=="song" and song_pattern==0 and song_channel==0,"tap x song")
 setup(63)
 for i=1,hold_frames do update_action_buttons(true,false) end
 ck(context_menu=="start" and context_gate,"hold o start")
 context_menu=nil context_gate=false action_gate=false reset_action_input()
 update_action_buttons(true,false) update_action_buttons(false,false)
 ck(edit_owner=="sfx" and edit_label=="pitch","tap o edits")
 setup(63)
 poke2(bank_note_addr(63,0),0xd6a5) bank_project_init()
 update_action_buttons(true,true) update_action_buttons(false,false)
 ck(peek2(bank_note_addr(63,0))==0 and not context_menu,
  "o+x rest without menu collision")
 if fails==0 then printh("pocket tracker sfx safety: passed")
 else printh("pocket tracker sfx safety: failed "..fails) end
 extcmd("shutdown")
end
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
