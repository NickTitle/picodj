pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
#include ../audio_bank.lua
#include ../tracker.lua
#include ../song_ui.lua
#include ../sfx_ui.lua
fails=0
function say() end
function song_restore_then(action) return action() end
function ck(v,s) if not v then fails+=1 printh("fail: "..s) end end
function own(a,b,m,s) ck(((a^^b)&(0xffff^^m))==0,s) end
function raw(s,r) local a=bank_note_addr(s,r) return a and peek2(a) end
function setup()
 reload(bank_audio_base,bank_audio_base,bank_size,"../pocket-tracker.p8")
 bank_project_init() playing=false audition_active=false
 song_pattern=0 song_channel=0 song_play_pattern=0
 sfx_number=63 sfx_row=31 sfx_scroll=0 sfx_field=1 sfx_mode="rows"
 edit_owner=nil undo_owner=nil context_menu=nil action_gate=false
 sfx_error=nil
end
function edit(field,value,mask)
 sfx_field=field
 local before=raw(63,31)
 ck(sfx_begin_edit(),"begin field "..field)
 edit_value=value
 ck(edit_commit(),"commit field "..field)
 own(before,raw(63,31),mask,"owned field "..field)
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
 if fails==0 then printh("pocket tracker sfx ui: passed")
 else printh("pocket tracker sfx ui: failed "..fails) end
 extcmd("shutdown")
end
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
