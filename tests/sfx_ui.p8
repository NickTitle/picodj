pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
#include ../audio_bank.lua
#include ../tracker.lua
#include ../song_ui.lua
#include ../sfx_ui.lua
fails=0
test_buttons,test_pressed={},{}
function btn(i) return test_buttons[i+1] or false end
function btnp(i) return test_pressed[i+1] or false end
function say() end
function song_restore_then(action) return action() end
function ck(v,s) if not v then fails+=1 printh("fail: "..s) end end
function own(a,b,m,s) ck(((a^^b)&(0xffff^^m))==0,s) end
function raw(s,r) local a=bank_note_addr(s,r) return a and peek2(a) end
function setup()
 reload(bank_audio_base,bank_audio_base,bank_size,"../pocket-tracker.p8")
 test_buttons,test_pressed={},{}
 bank_project_init() playing=false audition_active=false
 song_pattern=0 song_channel=0 song_play_pattern=0
 sfx_number=63 sfx_row=31 sfx_scroll=0 sfx_field=1 sfx_mode="rows"
 edit_owner=nil undo_owner=nil context_menu=nil action_gate=false
 sfx_error,sfx_row_op=nil,nil transport_tick=0
end
function edit(field,value,mask)
 sfx_field=field
 local before=raw(63,31)
 ck(sfx_begin_edit(),"begin field "..field)
 edit_value=value
 ck(edit_commit(),"commit field "..field)
 own(before,raw(63,31),mask,"owned field "..field)
end
function repeat_frame(i,down,screen)
 for j=1,4 do dpad_pressed[j]=false end
 dpad_pressed[i]=dpad_step(i,down)
 screen()
end
function _init()
 setup()
 sfx_change_slot(-80) ck(sfx_number==0,"slot zero")
 sfx_change_slot(80) ck(sfx_number==63,"slot 3f")
 sfx_row=31 sfx_keep_visible() ck(sfx_scroll==23,"row 31 visible")
 poke2(bank_note_addr(63,31),0xd6a5) bank_project_init()
 local word_before=raw(63,31)
 edit(1,17,0x003f)
 local word_after=raw(63,31) local rev=bank_revision
 ck(edit_undo("sfx") and raw(63,31)==word_before and bank_revision==rev+1,
  "word undo exact")
 rev=bank_revision
 ck(edit_undo("sfx") and raw(63,31)==word_after and bank_revision==rev+1,
  "word redo exact")
 edit(2,6,0x01c0) edit(3,0,0x8000)
 edit(4,7,0x0e00) edit(5,3,0x7000)
 local before=raw(63,31) rev=bank_revision
 sfx_field=1 ck(sfx_begin_edit(),"begin cancel")
 edit_value=22 edit_cancel()
 ck(raw(63,31)==before and bank_revision==rev,"cancel exact")
 setup() poke2(bank_note_addr(63,31),0xd6a5) bank_project_init()
 before=raw(63,31)
 ck(sfx_toggle_rest() and raw(63,31)==0,"rest")
 rev=bank_revision ck(edit_undo("sfx"),"undo")
 ck(raw(63,31)==before and not bank_dirty and bank_revision==rev+1,
  "undo exact clean")
 rev=bank_revision ck(undo_width<0 and edit_undo("sfx"),"redo")
 ck(raw(63,31)==0 and bank_dirty and bank_revision==rev+1 and undo_width>0,
  "redo exact dirty")
 rev=bank_revision ck(edit_undo("sfx"),"undo again")
 ck(raw(63,31)==before and not bank_dirty and bank_revision==rev+1,
  "second undo exact clean")
 setup() sfx_row=0 sfx_mode="meta"
 poke(bank_sfx_addr(63,66),0xa2) poke(bank_sfx_addr(63,67),0xc0)
 bank_project_init()
 sfx_meta_field=1 ck(sfx_begin_edit(),"speed begin")
 local speed_before=bank_sfx_meta_raw(63,1)
 edit_value=31 ck(edit_commit() and bank_sfx_meta_raw(63,1)==31,"speed")
 rev=bank_revision
 ck(edit_undo("sfx") and bank_sfx_meta_raw(63,1)==speed_before and
    bank_revision==rev+1,"metadata undo exact")
 rev=bank_revision
 ck(edit_undo("sfx") and bank_sfx_meta_raw(63,1)==31 and bank_revision==rev+1,
    "metadata redo exact")
 sfx_meta_field=2 ck(sfx_begin_edit(),"len begin")
 edit_value=12 ck(edit_commit(),"len commit")
 ck(bank_sfx_meta_raw(63,2)==0xac,"len reserved")
 sfx_meta_field=3 ck(sfx_begin_edit(),"end begin")
 edit_value=7 ck(edit_commit(),"end commit")
 ck(bank_sfx_meta_raw(63,3)==0xc7,"end reserved")
 setup() put=nil
 poke2(bank_note_addr(63,3),0x8001) poke2(bank_note_addr(63,4),0x70c2)
 bank_project_init() sfx_row=4
 ck(sfx_rows_begin(1),"row copy begin") sfx_row=3
 ck(sfx_rows_apply() and sfx_clip_count==2,"reversed row copy")
 sfx_number=62 sfx_row=30
 ck(sfx_rows_begin(2) and sfx_rows_apply() and
  (raw(62,30)&0xffff)==0x8001 and
  (raw(62,31)&0xffff)==0x70c2,"row paste ui")
 setup() sfx_number=0 sfx_row=0
 poke(bank_sfx_addr(0,66),peek(bank_sfx_addr(0,66))|0x80)
 poke(bank_sfx_addr(0,0),0x7f) bank_project_init()
 ck(sfx_begin_edit() and edit_width==1 and edit_value==0x7f,"wave sample begin")
 edit_value=0x80 ck(edit_commit() and peek(bank_sfx_addr(0,0))==0x80,
  "wave sample commit")
 sfx_mode="meta" sfx_meta_field=1
 poke(bank_sfx_addr(0,65),0xb0) bank_project_init()
 ck(sfx_begin_edit() and edit_label=="bass" and edit_value==0,"wave bass begin")
 edit_value=1 ck(edit_commit() and bank_sfx_meta_raw(0,1)==0xb1,
  "wave bass preserves reserved")
 local payload={} for i=0,67 do payload[i+1]=peek(bank_sfx_addr(0,i)) end
 sfx_meta_field=2
 ck(sfx_begin_edit() and edit_label=="mode" and edit_value==1,"wave mode begin")
 edit_value=0 ck(edit_commit() and not bank_sfx_is_waveform(0),"notes mode commit")
 for i=0,67 do ck(peek(bank_sfx_addr(0,i))==
  (i==66 and (payload[i+1]&0x7f) or payload[i+1]),"mode byte "..i) end
 sfx_meta_field=4
 ck(sfx_begin_edit() and edit_label=="mode" and edit_value==0,"notes mode begin")
 edit_value=1 ck(edit_commit() and bank_sfx_is_waveform(0),"wave mode commit")
 sfx_mode="filters" sfx_filter_field=2
 ck(sfx_begin_edit() and edit_label=="reverb" and edit_value==0,"wave filter begin")
 edit_value=2
 ck(edit_commit() and bank_sfx_filter(0,4)==2,"wave filter commit")
 sfx_number=8 sfx_mode="meta" sfx_meta_field=4 sfx_error=nil
 ck(not sfx_begin_edit() and sfx_error=="mode unavailable","mode limited to sfx 0-7")

 -- D-pad taps change once, then repeat at 16/4 and accelerate at 48/2.
 setup() app_view="song" song_pattern=0 song_channel=0 song_scroll=0
 reset_action_input()
 repeat_frame(2,true,update_song_screen)
 repeat_frame(2,false,update_song_screen)
 ck(song_channel==1,"song tap exactly once")
 song_channel=0 reset_action_input()
 for frame=1,50 do repeat_frame(4,true,update_song_screen) end
 ck(song_pattern==11 and song_scroll==2,"song hold cadence viewport")
 repeat_frame(4,false,update_song_screen)
 ck(song_pattern==11,"song release stops repeat")
 song_pattern=63 song_scroll=54 reset_action_input()
 for frame=1,50 do repeat_frame(4,true,update_song_screen) end
 ck(song_pattern==63 and song_scroll==54,"song hold clamps")

 setup() app_view="sfx" sfx_row=0 sfx_scroll=0 sfx_field=1
 reset_action_input()
 repeat_frame(2,true,update_sfx_screen)
 repeat_frame(2,false,update_sfx_screen)
 ck(sfx_field==2,"sfx tap exactly once")
 sfx_field=1 reset_action_input()
 for frame=1,50 do repeat_frame(4,true,update_sfx_screen) end
 ck(sfx_row==11 and sfx_scroll==3,"sfx hold cadence viewport")

 setup() app_view="song" song_pattern=0 song_channel=0
 ck(song_begin_edit("sfx"),"repeat scalar begin")
 edit_value=60 reset_action_input()
 repeat_frame(1,true,update_song_screen)
 repeat_frame(1,false,update_song_screen)
 ck(edit_value==59,"scalar tap exactly once")
 edit_value=60 reset_action_input()
 for frame=1,50 do repeat_frame(2,true,update_song_screen) end
 ck(edit_value==7,"scalar hold cadence wraps")
 edit_cancel()

 -- Action gates, menus, row operations, and cancellation clear repeat state.
 reset_action_input()
 for frame=1,20 do dpad_step(4,true) end
 dpad_update(false)
 ck(dpad_step(4,true) and not dpad_step(4,true),"action reset restarts tap cadence")
 reset_action_input()
 local repeats=0
 for block=1,200 do
  for frame=1,200 do if dpad_step(1,true) then repeats+=1 end end
 end
 ck(repeats==19986,"sustained cadence does not overflow")
 setup() app_view="song" context_menu="song" context_item=1
 dpad_update(false) update_song_screen()
 ck(context_item==1,"context menu excludes acceleration")
 setup() app_view="sfx" sfx_row=5 sfx_row_op=1
 dpad_update(false) update_sfx_screen()
 ck(sfx_row==5,"row operation excludes acceleration")

 -- The production frame gate isolates actions and chords from D-pad repeat.
 setup() app_view="song" song_pattern=0 song_scroll=0 reset_action_input()
 test_buttons={false,false,false,true,true,false}
 for frame=1,20 do _update60() end
 ck(song_pattern==0 and context_menu=="start","o hold isolates dpad repeat")
 test_buttons={} close_context_menu()
 test_buttons={false,false,false,true,false,false}
 _update60() _update60()
 ck(song_pattern==1,"action release restarts cadence")
 setup() app_view="sfx" sfx_row=8 sfx_scroll=0 sfx_row_op=1
 reset_action_input() test_pressed={false,false,false,true}
 _update60() test_pressed={} _update60()
 ck(sfx_row==9 and sfx_scroll==1,"row operation tap moves once and scrolls")
 setup() app_view="sfx" sfx_row=31 sfx_scroll=23 sfx_row_op=1
 reset_action_input() test_pressed={false,false,false,true}
 _update60()
 ck(sfx_row==31 and sfx_scroll==23,"row operation tap clamps")
 setup() app_view="sfx" sfx_row=0 sfx_scroll=0 sfx_row_op=1
 reset_action_input() test_buttons={false,false,false,true}
 for frame=1,50 do
  test_pressed={false,false,false,frame==1 or (frame>=16 and frame%4==0)}
  _update60()
 end
 ck(sfx_row==10 and sfx_scroll==2,"row operation uses native repeat")
 ck(dpad_hold[4]==0,"row operation never consumes accelerated signal")
 setup() app_view="sfx" sfx_row=0 sfx_scroll=0
 poke2(bank_note_addr(sfx_number,0),0x1234) bank_project_init()
 reset_action_input() test_buttons={false,false,false,true,true,true}
 for frame=1,50 do _update60() end
 ck(sfx_row==0 and raw(sfx_number,0)==0,"chord isolates repeat and acts once")
 test_buttons={}
 if fails==0 then printh("pocket tracker sfx ui: passed")
 else printh("pocket tracker sfx ui: failed "..fails) end
 extcmd("shutdown")
end
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
