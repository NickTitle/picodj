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
function setup(slot)
 reload(bank_audio_base,bank_audio_base,bank_size,"../pocket-tracker.p8")
 bank_project_init() playing=false audition_active=false
 sfx_number=slot sfx_row=0 sfx_scroll=0 sfx_field=1 sfx_mode="filters"
 sfx_filter_field=1 edit_owner=nil undo_owner=nil sfx_error=nil
 context_menu=nil action_gate=false restore_calls=0
end
function _init()
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
     ck(bank_set_sfx_filter(63,field,value),"set "..raw..":"..field..":"..value)
     ck(bank_sfx_meta_raw(63,0)==raw+(value-values[field])*bank_filter_steps[field],"exact set")
    end
   end
  end end
 end end end end

 -- Unsupported raw states and waveform slots are exact read-only cases.
 for raw=0xd8,0xff do
  poke(bank_sfx_addr(63,64),raw) bank_project_init()
  for field=1,5 do
   ck(bank_sfx_filter(63,field)==nil and not bank_set_sfx_filter(63,field,0),"raw reject "..raw..":"..field)
  end
  ck(peek(bank_sfx_addr(63,64))==raw and not bank_dirty and bank_revision==0,"raw exact "..raw)
 end
 setup(0) poke(bank_sfx_addr(0,66),peek(bank_sfx_addr(0,66))|0x80) bank_project_init()
 local wave=bank_sfx_meta_raw(0,0)
 ck(bank_sfx_filter(0,1)==nil and not bank_set_sfx_filter(0,1,1),"wave reject")
 ck(bank_sfx_meta_raw(0,0)==wave and not bank_dirty and bank_revision==0,"wave exact")

 -- Staged commit, cancel, no-op, whole-byte Undo/Redo, and restore policy.
 setup(63) poke(bank_sfx_addr(63,64),0xd7) bank_project_init()
 sfx_filter_field=5 ck(sfx_begin_edit(),"begin") edit_value=0
 ck(edit_commit() and bank_sfx_meta_raw(63,0)==0x47 and restore_calls==1,"commit")
 local rev=bank_revision
 ck(sfx_undo() and bank_sfx_meta_raw(63,0)==0xd7 and bank_revision==rev+1,"undo")
 rev=bank_revision ck(sfx_undo() and bank_sfx_meta_raw(63,0)==0x47 and bank_revision==rev+1,"redo")
 sfx_filter_field=3 ck(sfx_begin_edit(),"cancel begin") edit_value=2 edit_cancel()
 ck(bank_sfx_meta_raw(63,0)==0x47 and undo_width>0,"cancel preserves")
 local owner=undo_owner rev=bank_revision
 sfx_filter_field=1 ck(sfx_begin_edit(),"noop begin")
 ck(edit_commit() and bank_revision==rev and undo_owner==owner,"noop preserves")

 poke(bank_sfx_addr(63,64),0xd8) bank_project_init() sfx_filter_field=1
 ck(not sfx_begin_edit() and sfx_error=="raw filter state read only","ui raw reject")
 setup(0) poke(bank_sfx_addr(0,66),peek(bank_sfx_addr(0,66))|0x80) bank_project_init()
 ck(not sfx_begin_edit() and sfx_error=="waveform filters read only","ui wave reject")

 if fails==0 then printh("pocket tracker sfx filters: passed")
 else printh("pocket tracker sfx filters: failed "..fails) end
 extcmd("shutdown")
end
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
