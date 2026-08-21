pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
#include ../audio_bank.lua
#include ../sfx_ui.lua
fails=0
function say() end
function song_restore_then(action) return action() end
function ck(v,s) if not v then fails+=1 printh("fail: "..s) end end
function own(a,b,m,s) ck(((a^^b)&(0xffff^^m))==0,s) end
function setup()
 reload(bank_audio_base,bank_audio_base,bank_size,"../pocket-tracker.p8")
 bank_project_init() playing=false audition_active=false
 song_pattern=0 song_channel=0 song_play_pattern=0
 sfx_number=63 sfx_row=31 sfx_scroll=0 sfx_field=1 sfx_mode="rows"
 sfx_edit=false sfx_menu=false sfx_entry_gate=false sfx_undo_valid=false
 sfx_error=nil
end
function edit(field,value,mask)
 sfx_field=field
 local before=bank_note_raw(63,31)
 ck(sfx_begin_row_edit(),"begin field "..field)
 sfx_edit_value=value
 ck(sfx_commit_edit(),"commit field "..field)
 own(before,bank_note_raw(63,31),mask,"owned field "..field)
end
function _init()
 setup()
 sfx_change_slot(-80) ck(sfx_number==0,"slot zero")
 sfx_change_slot(80) ck(sfx_number==63,"slot 3f")
 sfx_row=31 sfx_keep_visible() ck(sfx_scroll==23,"row 31 visible")
 poke2(bank_note_addr(63,31),0xd6a5) bank_project_init()
 edit(1,17,0x003f) edit(2,6,0x01c0) edit(3,0,0x8000)
 edit(4,7,0x0e00) edit(5,3,0x7000)
 local before=bank_note_raw(63,31) local rev=bank_revision
 sfx_field=1 ck(sfx_begin_row_edit(),"begin cancel")
 sfx_edit_value=22 sfx_cancel_edit()
 ck(bank_note_raw(63,31)==before and bank_revision==rev,"cancel exact")
 setup() poke2(bank_note_addr(63,31),0xd6a5) bank_project_init()
 before=bank_note_raw(63,31)
 ck(sfx_toggle_rest() and bank_note_raw(63,31)==0,"rest")
 rev=bank_revision ck(sfx_undo(),"undo")
 ck(bank_note_raw(63,31)==before and not bank_dirty and bank_revision==rev+1,
  "undo exact clean")
 setup() sfx_row=0 sfx_mode="meta"
 poke(bank_sfx_addr(63,66),0xa2) poke(bank_sfx_addr(63,67),0xc0)
 bank_project_init()
 sfx_meta_field=1 ck(sfx_begin_meta_edit(),"speed begin")
 sfx_edit_value=31 ck(sfx_commit_edit() and bank_sfx_speed(63)==31,"speed")
 sfx_meta_field=2 ck(sfx_begin_meta_edit(),"len begin")
 sfx_edit_value=12 ck(sfx_commit_edit(),"len commit")
 ck(bank_sfx_meta_raw(63,2)==0xac,"len reserved")
 sfx_meta_field=3 ck(sfx_begin_meta_edit(),"end begin")
 sfx_edit_value=7 ck(sfx_commit_edit(),"end commit")
 ck(bank_sfx_meta_raw(63,3)==0xc7,"end reserved")
 if fails==0 then printh("pocket tracker sfx ui: passed")
 else printh("pocket tracker sfx ui: failed "..fails) end
 extcmd("shutdown")
end
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
