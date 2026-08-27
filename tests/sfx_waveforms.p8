pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
#include ../audio_bank.lua
#include ../tracker.lua
#include ../song_ui.lua
#include ../sfx_ui.lua
fails=0
music_calls={}
function native_music(p,f,m) add(music_calls,{p,f,m}) end
function native_sfx() end
function ck(ok,label) if not ok then fails+=1 printh("fail: "..label) end end
function sample(index) return peek(bank_sfx_addr(0,index)) end
function setup()
 reload(bank_audio_base,bank_audio_base,bank_size,"fixtures/pico8-027-waveform.p8")
 bank_project_init()
 playing=false audition_active=false song_pattern=0 song_play_pattern=0
 song_channel=0 song_mix=0 song_mix_channel=0 song_active="a----"
 sfx_number=0 sfx_row=0 sfx_scroll=0 sfx_field=1 sfx_mode="rows"
 edit_owner=nil undo_owner=nil sfx_error=nil context_menu=nil action_gate=false
 music_calls={}
end
function _init()
 setup()
 ck(bank_sfx_is_waveform(0),"fixture classification")
 ck(sample(0)==0 and sample(1)==0x7f and sample(62)==0x80 and sample(63)==0xff,
  "fixture boundary samples")
 ck(bank_sfx_meta_raw(0,0)==0 and bank_sfx_meta_raw(0,1)==0x10 and
  bank_sfx_meta_raw(0,2)==0x80 and bank_sfx_meta_raw(0,3)==0,"fixture metadata")
 ck(bank_note_authored_raw(8,0)==0x8a18,"fixture custom reference")
 local fixture_crc=bank_checksum(bank_audio_base)
 ck((fixture_crc&0xffff)==0x20da,"fixture checksum")

 -- First/last samples, raw wrap, unrelated bytes, and whole-byte history.
 local before={} for i=0,67 do before[i+1]=peek(bank_sfx_addr(0,i)) end
 ck(sfx_begin_edit() and edit_width==1 and edit_value==0,"first begin")
 edit_value=(edit_value+edit_max)%(edit_max+1)
 ck(edit_commit() and sample(0)==0xff and bank_dirty and bank_revision==1,
  "first wraps left")
 for i=1,67 do ck(peek(bank_sfx_addr(0,i))==before[i+1],"first owns byte "..i) end
 local rev=bank_revision
 ck(edit_undo("sfx") and sample(0)==0 and not bank_dirty and bank_revision==rev+1,
  "first undo exact clean")
 rev=bank_revision
 ck(edit_undo("sfx") and sample(0)==0xff and bank_dirty and bank_revision==rev+1,
  "first redo exact dirty")

 sfx_row=31 sfx_field=2 sfx_keep_visible()
 ck(sfx_scroll==23 and sfx_begin_edit() and edit_value==0xff,"last begin")
 edit_value=(edit_value+1)%(edit_max+1)
 ck(edit_commit() and sample(63)==0,"last wraps right")

 -- Cancel and no-op preserve prior history, bytes, dirty state, and revision.
 sfx_row=0 sfx_field=2
 local owner,width,addr=undo_owner,undo_width,undo_addr
 rev=bank_revision local dirty=bank_dirty local raw=sample(1)
 ck(sfx_begin_edit(),"cancel begin") edit_value=raw^^1 edit_cancel()
 ck(sample(1)==raw and bank_revision==rev and bank_dirty==dirty and
  undo_owner==owner and undo_width==width and undo_addr==addr,"cancel exact")
 ck(sfx_begin_edit() and edit_commit(),"no-op commit")
 ck(sample(1)==raw and bank_revision==rev and bank_dirty==dirty and
  undo_owner==owner and undo_width==width and undo_addr==addr,"no-op exact")

 -- Metadata/range/preview remain read-only while scalar editing is available.
 sfx_mode="meta" sfx_meta_field=1
 ck(not sfx_begin_edit() and sfx_error=="waveform meta read only","metadata reject")
 sfx_mode="rows" sfx_error=nil
 ck(not sfx_rows_begin(1) and not sfx_toggle_rest(),"range reject")
 ck(not start_audition() and sfx_error=="preview unavailable","preview reject")

 -- A playing song is stopped/restored, mutated once, and restarted at observation.
 setup() song_play_pattern=0
 ck(start_song(0),"song starts")
 local calls=#music_calls
 sfx_row=1 sfx_field=1
 ck(sfx_begin_edit(),"playing begin") edit_value=(edit_value+1)%256
 ck(edit_commit() and #music_calls==calls+2 and music_calls[#music_calls-1][1]==-1 and
  music_calls[#music_calls][1]==0 and playing and bank_profile_is_active(),
  "playing edit restarts once")
 ck(bank_revision==1 and bank_checksum(bank_audio_base)!=fixture_crc,
  "playing edit touches once")
 stop_song()

 if fails==0 then printh("pocket tracker sfx waveforms: passed")
 else printh("pocket tracker sfx waveforms: failed "..fails) end
 extcmd("shutdown")
end
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
