pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
#include ../audio_bank.lua
#include ../tracker.lua
#include ../song_ui.lua
#include ../sfx_ui.lua
fails=0
music_calls={}
sfx_calls={}
function say() end
function ck(v,s) if not v then fails+=1 printh("fail: "..s) end end
function native_music(p,f,m) add(music_calls,{p,f,m}) end
function native_sfx(n,c,o,l) add(sfx_calls,{n,c,o,l}) end
function native_stat(i) return i==57 and true or 0 end
function snap(base,n)
 local out={} for i=0,n-1 do add(out,peek(base+i)) end return out
end
function same(base,bytes,n)
 for i=0,n-1 do if peek(base+i)!=bytes[i+1] then return false end end
 return true
end
function setup(slot,row)
 reload(bank_audio_base,bank_audio_base,bank_size,"../pocket-tracker.p8")
 bank_project_init()
 playing,audition_active=false,false
 song_pattern,song_play_pattern,song_channel=0,0,0
 song_mix,song_mix_channel,song_mix_stage,song_active=0,0,0,"a----"
 transport_tick=0
 app_view="sfx"
 sfx_number,sfx_row,sfx_scroll,sfx_field=slot or 5,row or 0,0,1
 sfx_mode,sfx_error="rows",nil
 sfx_clip_count,sfx_row_op=0,nil
 edit_owner,undo_owner=nil,nil
 context_menu,action_gate=nil,false
 reset_action_input()
 music_calls={} sfx_calls={}
end
function put(slot,row,value) poke2(bank_note_addr(slot,row),value) end
function row(slot,row) return bank_note_authored_raw(slot,row)&0xffff end
function copy_rows(first,last)
 sfx_row=first ck(sfx_rows_begin(1),"copy begin") sfx_row=last
 return sfx_rows_apply()
end
function paste_rows(slot,target)
 sfx_number,sfx_row=slot,target
 ck(sfx_rows_begin(2),"paste begin")
 return sfx_rows_apply()
end
function clear_rows(first,last)
 sfx_row=first ck(sfx_rows_begin(3),"clear begin") sfx_row=last
 return sfx_rows_apply()
end
function _init()
 setup(5)
 local words={0xffff,0,0x8001,0x70c2,0x1234}
 for i=1,#words do put(5,i+2,words[i]) end
 bank_project_init()
 local crc=bank_checksum(bank_audio_base)
 ck(copy_rows(7,3) and sfx_clip_count==5,"reversed inclusive copy")
 for i=0,4 do ck((peek2(bank_clip_base+i*2)&0xffff)==words[i+1],"copy word "..i) end
 ck(bank_checksum(bank_audio_base)==crc and not bank_dirty and bank_revision==0 and
  undo_owner==nil,"copy is session only")
 local meta=snap(bank_sfx_addr(6,64),4)
 ck(paste_rows(6,10),"cross slot paste")
 for i=0,4 do ck(row(6,10+i)==words[i+1],"paste word "..i) end
 ck(same(bank_sfx_addr(6,64),meta,4),"metadata unchanged")
 ck(bank_dirty and bank_revision==1 and undo_owner=="sfx" and undo_width==10,
  "paste one transaction")
 local rev=bank_revision
 ck(edit_undo("sfx") and bank_revision==rev+1 and not bank_dirty,"batch undo clean")
 for i=0,4 do ck(row(6,10+i)==0,"undo range "..i) end
 rev=bank_revision
 ck(edit_undo("sfx") and bank_revision==rev+1 and bank_dirty and undo_width>0,
  "batch redo dirty")
 for i=0,4 do ck(row(6,10+i)==words[i+1],"redo range "..i) end

 -- Reversed clear, no-op, cancel, and later scalar history semantics.
 sfx_number=6
 rev=bank_revision
 ck(clear_rows(14,10) and bank_revision==rev+1,"reversed clear once")
 for i=10,14 do ck(row(6,i)==0,"clear row "..i) end
 ck(edit_undo("sfx"),"clear undo")
 local width=undo_width owner=undo_owner calls=#music_calls rev=bank_revision
 sfx_row=20 ck(sfx_rows_begin(3),"noop clear begin")
 ck(sfx_rows_apply() and undo_width==width and undo_owner==owner and
  bank_revision==rev and #music_calls==calls,"noop preserves redo transport")
 sfx_row=2 ck(sfx_rows_begin(3),"cancel begin")
 update_action_buttons(false,true) update_action_buttons(false,false)
 ck(not sfx_row_op and undo_width==width and bank_revision==rev,"cancel preserves redo")
 sfx_row=10 sfx_field=1 ck(sfx_begin_edit(),"scalar begin") edit_value=3
 ck(edit_commit() and undo_width==2,"scalar replaces batch redo")

 -- One-row and complete boundary selections retain exact words.
 setup(7)
 for i=0,31 do put(7,i,(i*0x421+0x8000)&0xffff) end
 bank_project_init()
 ck(copy_rows(31,31) and sfx_clip_count==1 and
  (peek2(bank_clip_base)&0xffff)==row(7,31),"one row boundary")
 ck(copy_rows(0,31) and sfx_clip_count==32,"full 32 rows")
 sfx_number,sfx_row=8,1
 ck(sfx_rows_begin(2) and not sfx_rows_apply() and sfx_error=="paste overflow",
  "overflow atomic")
 ck(not bank_dirty and bank_revision==0 and undo_owner==nil,"overflow clean history")
 sfx_row=0 ck(sfx_rows_begin(2) and sfx_rows_apply(),"full boundary paste")
 for i=0,31 do ck(row(8,i)==row(7,i),"full paste row "..i) end

 -- Empty and waveform operations reject without state changes.
 setup(5) sfx_clip_count=0
 ck(not sfx_rows_begin(2) and sfx_error=="clipboard empty","empty reject")
 poke(bank_sfx_addr(0,66),peek(bank_sfx_addr(0,66))|0x80)
 sfx_number=0 sfx_error=nil
 ck(not sfx_rows_begin(1) and not sfx_rows_begin(3),"wave source clear reject")
 ck(not bank_dirty and bank_revision==0 and undo_owner==nil,"wave exact")

 -- Copy reads authored profile bytes without stopping SONG; real paste stops,
 -- restores, mutates, and restarts the observed pattern exactly once.
 setup(1) put(1,0,0x0a18) bank_project_init()
 ck(start_song(12),"play start") song_play_pattern=9
 calls=#music_calls
 ck(copy_rows(0,0) and #music_calls==calls and playing and bank_profile_is_active(),
  "playing copy transport")
 ck((peek2(bank_clip_base)&0xffff)==0x0a18,"copy authored not boosted")
 sfx_number,sfx_row=5,0 rev=bank_revision calls=#music_calls
 ck(sfx_rows_begin(2) and sfx_rows_apply(),"playing paste")
 ck(bank_revision==rev+1 and #music_calls==calls+2 and
  music_calls[#music_calls-1][1]==-1 and music_calls[#music_calls][1]==9 and
  playing and bank_profile_is_active(),"observed stop restart once")

 -- Active preview is ended through its restore path before capture.
 local scratch=snap(bank_sfx_addr(63,0),bank_sfx_size)
 sfx_number,sfx_row=1,0
 ck(start_audition(0),"active preview") calls=#music_calls
 ck(copy_rows(0,0) and not audition_active and playing,"copy ends preview")
 ck(same(bank_sfx_addr(63,0),scratch,bank_sfx_size),"preview scratch restored")
 ck(#music_calls==calls+1 and music_calls[#music_calls][1]==9,
  "preview resumes observed song")
 stop_song()

 if fails==0 then printh("pocket tracker sfx clipboard: passed")
 else printh("pocket tracker sfx clipboard: failed "..fails) end
 extcmd("shutdown")
end
function _draw() end
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
