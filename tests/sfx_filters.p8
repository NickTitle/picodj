pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
#include ../audio_bank.lua
#include ../tracker.lua
#include ../song_ui.lua
#include ../sfx_ui.lua
fails=0
restore_calls=0
function say() end
function song_restore_then(action) restore_calls+=1 return action() end
function ck(ok,label) if not ok then fails+=1 printh("fail: "..label) end end
function set_filter(s,f,v)
 local old=bank_sfx_filter(s,f)
 if old==nil or not bank_int(v,0,f<3 and 1 or 2) then return false end
 local addr=bank_sfx_addr(s,64)
 return bank_write(addr,1,peek(addr)+(v-old)*bank_filter_steps[f])
end
function setup(slot)
 reload(bank_audio_base,bank_audio_base,bank_size,"../pocket-tracker.p8")
 bank_project_init() playing=false audition_active=false
 sfx_number=slot sfx_row=0 sfx_scroll=0 sfx_field=1 sfx_mode="filters"
 sfx_filter_field=1 edit_owner=nil undo_owner=nil sfx_error=nil
 context_menu=nil action_gate=false restore_calls=0
end
function _init()
 -- Native waveform matrix proves the three supported mixed-radix digits.
 reload(bank_audio_base,bank_audio_base,bank_size,"fixtures/pico8-027-waveform-filters.p8")
 local wave_fixture={0x00,0x08,0x10,0x18,0x30,0x48,0x90}
 for slot=0,6 do
  ck(bank_sfx_is_waveform(slot) and bank_sfx_meta_raw(slot,0)==wave_fixture[slot+1],
   "wave fixture raw "..slot)
  for i=0,63 do ck(peek(bank_sfx_addr(slot,i))==peek(bank_sfx_addr(0,i)),
   "wave fixture sample "..slot..":"..i) end
  for i=65,67 do ck(peek(bank_sfx_addr(slot,i))==peek(bank_sfx_addr(0,i)),
   "wave fixture metadata "..slot..":"..i) end
 end
 ck(bank_note_authored_raw(8,0)==0x8a18 and peek(bank_song_addr(0,0))==8,
  "wave fixture playback reference")
 ck((bank_checksum(bank_audio_base)&0xffff)==0xb8dd,"wave fixture checksum")

 -- PICO-8 0.2.7 native-editor fixture basis and mixed states.
 reload(bank_audio_base,bank_audio_base,bank_size,"fixtures/pico8-027-filters.p8")
 local fixture={0x00,0x01,0x03,0x05,0x09,0x11,0x19,0x31,0x49,0x91,0xd7,0xd6}
 for slot=0,11 do ck(bank_sfx_meta_raw(slot,0)==fixture[slot+1],"fixture "..slot) end

 -- Every named state decodes and each setter changes only its mixed-radix digit.
 local limits={1,1,2,2,2}
 for mode=0,1 do for noiz=0,1 do for buzz=0,1 do
  for detune=0,2 do for reverb=0,2 do for dampen=0,2 do
   local values={noiz,buzz,detune,reverb,dampen}
   local raw=mode+noiz*2+buzz*4+detune*8+reverb*24+dampen*72
   poke(bank_sfx_addr(63,64),raw)
   for field=1,5 do
    ck(bank_sfx_filter(63,field)==values[field],"decode "..raw..":"..field)
    for value=0,limits[field] do
     poke(bank_sfx_addr(63,64),raw) bank_project_init()
     ck(set_filter(63,field,value),"set "..raw..":"..field..":"..value)
     ck(bank_sfx_meta_raw(63,0)==raw+(value-values[field])*bank_filter_steps[field],"exact set")
    end
   end
 end end
 end end end end

 -- Every supported waveform combination decodes and edits only one digit.
 reload(bank_audio_base,bank_audio_base,bank_size,"fixtures/pico8-027-waveform-filters.p8")
 for hidden in all({0,2,4,6}) do
 for detune=0,2 do for reverb=0,2 do for dampen=0,2 do
  local values={detune,reverb,dampen}
  local raw=hidden+detune*8+reverb*24+dampen*72
  poke(bank_sfx_addr(0,64),raw)
  ck(bank_sfx_filter(0,1)==nil and bank_sfx_filter(0,2)==nil,"wave noiz buzz "..raw)
  for field=3,5 do
   ck(bank_sfx_filter(0,field)==values[field-2],"wave decode "..raw..":"..field)
   for value=0,2 do
    poke(bank_sfx_addr(0,64),raw) bank_project_init()
    ck(set_filter(0,field,value),"wave set "..raw..":"..field..":"..value)
    ck(bank_sfx_meta_raw(0,0)==raw+(value-values[field-2])*bank_filter_steps[field],
     "wave exact set")
   end
  end
 end end end end

 -- Unsupported raw states and waveform slots are exact read-only cases.
 for raw=0xd8,0xff do
  poke(bank_sfx_addr(63,64),raw) bank_project_init()
  for field=1,5 do
   ck(bank_sfx_filter(63,field)==nil and not set_filter(63,field,0),"raw reject "..raw..":"..field)
  end
  ck(peek(bank_sfx_addr(63,64))==raw and not bank_dirty and bank_revision==0,"raw exact "..raw)
 end
 setup(0) poke(bank_sfx_addr(0,64),6) poke(bank_sfx_addr(0,66),peek(bank_sfx_addr(0,66))|0x80) bank_project_init()
 local wave=bank_sfx_meta_raw(0,0)
 ck(bank_sfx_filter(0,1)==nil and not set_filter(0,1,1),"wave noiz reject")
 ck(bank_sfx_filter(0,2)==nil and not set_filter(0,2,1),"wave buzz reject")
 ck(bank_sfx_filter(0,3)!=nil and set_filter(0,3,1),"wave detune edit")
 ck(bank_sfx_meta_raw(0,0)==wave+8 and bank_dirty and bank_revision==1,"wave exact")

 -- Staged commit, cancel, no-op, whole-byte Undo/Redo, and restore policy.
 setup(63) poke(bank_sfx_addr(63,64),0xd7) bank_project_init()
 sfx_filter_field=5 ck(sfx_begin_edit(),"begin") edit_value=0
 ck(edit_commit() and bank_sfx_meta_raw(63,0)==0x47 and restore_calls==1,"commit")
 local rev=bank_revision
 ck(edit_undo("sfx") and bank_sfx_meta_raw(63,0)==0xd7 and bank_revision==rev+1,"undo")
 rev=bank_revision ck(edit_undo("sfx") and bank_sfx_meta_raw(63,0)==0x47 and bank_revision==rev+1,"redo")
 sfx_filter_field=3 ck(sfx_begin_edit(),"cancel begin") edit_value=2 edit_cancel()
 ck(bank_sfx_meta_raw(63,0)==0x47 and undo_width>0,"cancel preserves")
 local owner=undo_owner rev=bank_revision
 sfx_filter_field=1 ck(sfx_begin_edit(),"noop begin")
 ck(edit_commit() and bank_revision==rev and undo_owner==owner,"noop preserves")

 poke(bank_sfx_addr(63,64),0xd8) bank_project_init() sfx_filter_field=1
 ck(not sfx_begin_edit() and sfx_error=="raw filter state read only","ui raw reject")
 setup(0) poke(bank_sfx_addr(0,64),6) poke(bank_sfx_addr(0,66),peek(bank_sfx_addr(0,66))|0x80) bank_project_init()
 sfx_filter_field=4
 ck(not sfx_begin_edit() and sfx_error=="filter unavailable","ui wave invalid reject")
 sfx_filter_field=1
 local begun=sfx_begin_edit()
 ck(begun and edit_label=="detune" and edit_value==0,"ui wave detune begin")
 edit_value=2
 ck(edit_commit() and bank_sfx_meta_raw(0,0)==0x16 and restore_calls==1,"ui wave commit")
 local rev=bank_revision
 ck(edit_undo("sfx") and bank_sfx_meta_raw(0,0)==6 and bank_revision==rev+1,"ui wave undo")
 rev=bank_revision ck(edit_undo("sfx") and bank_sfx_meta_raw(0,0)==0x16 and
  bank_revision==rev+1,"ui wave redo")
 sfx_filter_field=2 ck(sfx_begin_edit(),"ui wave cancel begin") edit_value=2 edit_cancel()
 ck(bank_sfx_meta_raw(0,0)==0x16,"ui wave cancel")
 local owner=undo_owner rev=bank_revision
 sfx_filter_field=1 ck(sfx_begin_edit() and edit_commit(),"ui wave noop")
 ck(bank_revision==rev and undo_owner==owner,"ui wave noop exact")
 sfx_filter_field=3 ck(sfx_begin_edit(),"ui wave loss begin")
 poke(bank_sfx_addr(0,66),peek(bank_sfx_addr(0,66))&0x7f)
 update_sfx_screen()
 ck(edit_owner==nil and sfx_error=="waveform unavailable" and
  bank_revision==rev and undo_owner==owner,"ui wave loss reject")
 poke(bank_sfx_addr(0,66),peek(bank_sfx_addr(0,66))|0x80)
 poke(bank_sfx_addr(0,64),0xd8) bank_project_init() sfx_filter_field=1 sfx_error=nil
 ck(not sfx_begin_edit() and sfx_error=="raw filter state read only" and
  bank_sfx_meta_raw(0,0)==0xd8 and bank_revision==0,"ui wave raw reject")

 if fails==0 then printh("pocket tracker sfx filters: passed")
 else printh("pocket tracker sfx filters: failed "..fails) end
 extcmd("shutdown")
end
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
