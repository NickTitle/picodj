pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
#include ../audio_bank.lua
#include ../sfx_ui.lua
fails=0
hold_frames=18
function say() end
function song_restore_then(action) return action() end
function song_return_from_sfx() app_view="song" end
function open_context_menu(kind) context_menu=kind context_gate=true end
function update_context_menu() context_menu=nil end
function ck(v,s) if not v then fails+=1 printh("fail: "..s) end end
function setup(slot)
 reload(bank_audio_base,bank_audio_base,bank_size,"../pocket-tracker.p8")
 bank_project_init() playing=false audition_active=false
 song_pattern=0 song_channel=0 song_play_pattern=0 app_view="sfx"
 sfx_number=slot sfx_row=0 sfx_scroll=0 sfx_field=1 sfx_mode="rows"
 sfx_edit=false sfx_menu=false sfx_entry_gate=false sfx_undo_valid=false
 sfx_o_was_down=false sfx_o_hold=0 sfx_o_consumed=false
 sfx_chord_consumed=false
 sfx_x_was_down=false sfx_x_hold=0 sfx_x_consumed=false sfx_error=nil
 context_menu=nil action_gate=false
end
function _init()
 setup(0)
 poke(bank_sfx_addr(0,66),peek(bank_sfx_addr(0,66))|0x80)
 bank_project_init()
 local bytes={}
 for i=0,67 do add(bytes,peek(bank_sfx_addr(0,i))) end
 ck(not sfx_begin_row_edit() and sfx_error!=nil,"wave row reject")
 sfx_error=nil sfx_meta_field=2
 ck(not sfx_begin_meta_edit() and sfx_error!=nil,"wave meta reject")
 for i=0,67 do
  ck(peek(bank_sfx_addr(0,i))==bytes[i+1],"wave byte "..i)
 end
 ck(not bank_dirty and bank_revision==0,"wave bytes exact clean")
 setup(63)
 for i=1,hold_frames do sfx_update_actions(false,true) end
 ck(sfx_menu and sfx_menu_gate,"hold x menu")
 sfx_close_menu() sfx_entry_gate=false
 sfx_update_actions(false,true) sfx_update_actions(false,false)
 ck(app_view=="song" and song_pattern==0 and song_channel==0,"tap x song")
 setup(63)
 for i=1,hold_frames do sfx_update_actions(true,false) end
 ck(context_menu=="start" and context_gate,"hold o start")
 context_menu=nil sfx_reset_input() sfx_entry_gate=false
 sfx_update_actions(true,false) sfx_update_actions(false,false)
 ck(sfx_edit and sfx_edit_field=="pitch","tap o edits")
 setup(63)
 poke2(bank_note_addr(63,0),0xd6a5) bank_project_init()
 sfx_update_actions(true,true) sfx_update_actions(false,false)
 ck(bank_note_raw(63,0)==0 and not context_menu and not sfx_menu,
  "o+x rest without menu collision")
 if fails==0 then printh("pocket tracker sfx safety: passed")
 else printh("pocket tracker sfx safety: failed "..fails) end
 extcmd("shutdown")
end
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
