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
 reload(bank_audio_base,bank_audio_base,bank_size,"fixtures/pico8-027-waveform-bass-off.p8")
 bank_project_init()
 playing=false audition_active=false song_pattern=0 song_play_pattern=0
 song_channel=0 song_mix=0 song_mix_channel=0 song_active="a----"
 sfx_number=0 sfx_row=0 sfx_scroll=0 sfx_field=1 sfx_mode="rows"
 edit_owner=nil undo_owner=nil sfx_error=nil context_menu=nil action_gate=false
 music_calls={}
end
function _init()
 setup()
 reload(bank_stage_base,bank_audio_base,bank_size,"fixtures/pico8-027-waveform-bass-on.p8")
 local changes=0
 for i=0,bank_size-1 do
  local delta=peek(bank_audio_base+i)^^peek(bank_stage_base+i)
  if delta!=0 then
   changes+=1
   ck(i==0x100+65 and delta==1,"fixture owns bass bit only")
  end
 end
 ck(changes==1 and (bank_checksum(bank_stage_base)&0xffff)==0x6e12,
  "native bass fixture pair")
 reload(bank_stage_base,bank_audio_base,bank_size,"fixtures/pico8-027-waveform-mode-notes.p8")
 changes=0
 for i=0,bank_size-1 do
  local delta=peek(bank_audio_base+i)^^peek(bank_stage_base+i)
  if delta!=0 then
   changes+=1
   ck(i==0x100+66 and delta==0x80,"fixture owns mode bit only")
  end
 end
 ck(changes==1 and (bank_checksum(bank_stage_base)&0xffff)==0x07be,
  "native mode fixture pair")
 ck(bank_sfx_is_waveform(0),"fixture classification")
 ck(sample(0)==0 and sample(1)==0x7f and sample(62)==0x80 and sample(63)==0xff,
  "fixture boundary samples")
 ck(bank_sfx_meta_raw(0,0)==0 and bank_sfx_meta_raw(0,1)==0x10 and
  bank_sfx_meta_raw(0,2)==0x80 and bank_sfx_meta_raw(0,3)==0,"fixture metadata")
 ck(bank_note_authored_raw(8,0)==0x8a18,"fixture custom reference")
 local fixture_crc=bank_checksum(bank_audio_base)
 ck((fixture_crc&0xffff)==0x20da,"fixture checksum")

 -- Bass owns metadata byte 1 bit 0 and shares scalar dirty/history semantics.
 local slot={} for i=0,67 do slot[i+1]=peek(bank_sfx_addr(0,i)) end
 sfx_mode="meta" sfx_meta_field=1
 ck(sfx_begin_edit() and edit_label=="bass" and edit_value==0 and edit_max==1,
  "bass begin off")
 edit_value=1
 ck(edit_commit() and bank_sfx_meta_raw(0,1)==0x11 and bank_dirty and
  bank_revision==1,"bass on commit")
 for i=0,67 do
  ck(peek(bank_sfx_addr(0,i))==(i==65 and (slot[i+1]|1) or slot[i+1]),
   "bass owns byte "..i)
 end
 local rev=bank_revision
 ck(edit_undo("sfx") and bank_sfx_meta_raw(0,1)==0x10 and not bank_dirty and
  bank_revision==rev+1,"bass undo exact clean")
 rev=bank_revision
 ck(edit_undo("sfx") and bank_sfx_meta_raw(0,1)==0x11 and bank_dirty and
  bank_revision==rev+1,"bass redo exact dirty")
 local owner,width,addr=undo_owner,undo_width,undo_addr
 rev=bank_revision local dirty=bank_dirty
 ck(sfx_begin_edit(),"bass cancel begin") edit_value=0 edit_cancel()
 ck(bank_sfx_meta_raw(0,1)==0x11 and bank_revision==rev and bank_dirty==dirty and
  undo_owner==owner and undo_width==width and undo_addr==addr,"bass cancel exact")
 ck(sfx_begin_edit() and edit_commit(),"bass no-op commit")
 ck(bank_revision==rev and bank_dirty==dirty and undo_owner==owner and
  undo_width==width and undo_addr==addr,"bass no-op exact")
 ck(sfx_begin_edit(),"bass loss begin")
 poke(bank_sfx_addr(0,66),bank_sfx_meta_raw(0,2)&0x7f)
 update_sfx_screen()
 ck(edit_owner==nil and sfx_error=="waveform unavailable" and
  bank_sfx_meta_raw(0,1)==0x11 and bank_revision==rev and bank_dirty==dirty and
  undo_owner==owner and undo_width==width and undo_addr==addr,"bass loss rejects")
 poke(bank_sfx_addr(0,66),slot[67])
 setup()

 -- Mode owns metadata byte 2 bit 7 without converting the shared payload.
 local clip={} for i=0,63 do poke(bank_clip_base+i,(i*13+5)&0xff) clip[i+1]=peek(bank_clip_base+i) end
 slot={} for i=0,67 do slot[i+1]=peek(bank_sfx_addr(0,i)) end
 sfx_mode="meta" sfx_meta_field=2
 ck(sfx_begin_edit() and edit_label=="mode" and edit_value==1,"wave mode begin")
 edit_value=0
 ck(edit_commit() and not bank_sfx_is_waveform(0) and bank_dirty and bank_revision==1,
  "mode notes commit")
 for i=0,67 do
  ck(peek(bank_sfx_addr(0,i))==(i==66 and (slot[i+1]&0x7f) or slot[i+1]),
   "mode owns byte "..i)
 end
 for i=0,63 do ck(peek(bank_clip_base+i)==clip[i+1],"mode clipboard "..i) end
 rev=bank_revision
 ck(edit_undo("sfx") and bank_sfx_is_waveform(0) and not bank_dirty and
  bank_revision==rev+1,"mode undo exact clean")
 rev=bank_revision
 ck(edit_undo("sfx") and not bank_sfx_is_waveform(0) and bank_dirty and
  bank_revision==rev+1,"mode redo exact dirty")
 sfx_meta_field=4
 ck(sfx_begin_edit() and edit_value==0,"notes mode begin")
 edit_value=1
 ck(edit_commit() and bank_sfx_is_waveform(0),"mode wave commit")
 local owner,width,addr=undo_owner,undo_width,undo_addr
 rev=bank_revision local dirty=bank_dirty
 sfx_meta_field=2 ck(sfx_begin_edit(),"mode cancel begin") edit_value=0 edit_cancel()
 ck(bank_sfx_is_waveform(0) and bank_revision==rev and bank_dirty==dirty and
  undo_owner==owner and undo_width==width and undo_addr==addr,"mode cancel exact")
 ck(sfx_begin_edit() and edit_commit(),"mode no-op commit")
 ck(bank_revision==rev and bank_dirty==dirty and undo_owner==owner and
  undo_width==width and undo_addr==addr,"mode no-op exact")
 sfx_number=8 sfx_meta_field=4 sfx_error=nil
 ck(not sfx_begin_edit() and sfx_error=="mode unavailable" and
  bank_revision==rev and undo_owner==owner,"mode sfx8 reject")
 setup()
 for target in all({1,4,7}) do
  memcpy(bank_sfx_addr(target,0),bank_sfx_addr(0,0),bank_sfx_size)
  sfx_number=target sfx_mode="meta" sfx_meta_field=2
  ck(bank_sfx_is_waveform(target) and sfx_begin_edit(),"mode boundary wave "..target)
  edit_value=0
  ck(edit_commit() and not bank_sfx_is_waveform(target),"mode boundary notes "..target)
  sfx_meta_field=4
  ck(sfx_begin_edit(),"mode boundary notes begin "..target) edit_value=1
  ck(edit_commit() and bank_sfx_is_waveform(target),"mode boundary wave commit "..target)
 end
 setup()

 -- First/last samples, raw wrap, unrelated bytes, and whole-byte history.
 local before={} for i=0,67 do before[i+1]=peek(bank_sfx_addr(0,i)) end
 ck(sfx_begin_edit() and edit_width==1 and edit_value==0,"first begin")
 edit_value=(edit_value+edit_max)%(edit_max+1)
 ck(edit_commit() and sample(0)==0xff and bank_dirty and bank_revision==1,
  "first wraps left")
 for i=1,67 do ck(peek(bank_sfx_addr(0,i))==before[i+1],"first owns byte "..i) end
 rev=bank_revision
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
 owner,width,addr=undo_owner,undo_width,undo_addr
 rev=bank_revision local dirty=bank_dirty local raw=sample(1)
 ck(sfx_begin_edit(),"cancel begin") edit_value=raw^^1 edit_cancel()
 ck(sample(1)==raw and bank_revision==rev and bank_dirty==dirty and
  undo_owner==owner and undo_width==width and undo_addr==addr,"cancel exact")
 ck(sfx_begin_edit() and edit_commit(),"no-op commit")
 ck(sample(1)==raw and bank_revision==rev and bank_dirty==dirty and
  undo_owner==owner and undo_width==width and undo_addr==addr,"no-op exact")

 -- Only fixture-backed waveform filters are editable; range/preview stay unavailable.
 sfx_mode="filters" sfx_filter_field=4
 ck(not sfx_begin_edit() and sfx_error=="filter unavailable","filter reject")
 sfx_filter_field=1 sfx_error=nil
 ck(sfx_begin_edit() and edit_label=="detune","filter begin") edit_value=1
 ck(edit_commit() and bank_sfx_filter(0,3)==1,"filter commit")
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
  music_calls[#music_calls][1]==0 and playing and bank_profile_active,
  "playing edit restarts once")
 ck(bank_revision==1 and bank_checksum(bank_audio_base)!=fixture_crc,
  "playing edit touches once")
 stop_song()

 setup() song_play_pattern=0 sfx_mode="meta" sfx_meta_field=1
 ck(start_song(0),"bass song starts")
 calls=#music_calls
 ck(sfx_begin_edit(),"playing bass begin") edit_value=1
 ck(edit_commit() and #music_calls==calls+2 and music_calls[#music_calls-1][1]==-1 and
  music_calls[#music_calls][1]==0 and playing and bank_profile_active,
  "playing bass restarts once")
 ck(bank_sfx_meta_raw(0,1)==0x11 and bank_revision==1,
  "playing bass touches once")
 stop_song()

 if fails==0 then printh("pocket tracker sfx waveforms: passed")
 else printh("pocket tracker sfx waveforms: failed "..fails) end
 extcmd("shutdown")
end
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
