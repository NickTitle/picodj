pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
#include ../audio_bank.lua
#include ../song_ui.lua
fails=0
music_calls={}
sfx_calls={}
stats={}
seen={}
function ck(v,s) if not v then fails+=1 printh("fail: "..s) end end
function say() end
function native_music(p,f,m) add(music_calls,{p,f,m}) end
function native_sfx(n,c,o,l) add(sfx_calls,{n,c,o,l}) end
function native_stat(i) seen[i]=true return stats[i] end
function sfx_keep_visible() end
function same(base,bytes,n)
 for i=0,n-1 do if peek(base+i)!=bytes[i+1] then return false end end
 return true
end
function snap(base,n)
 local out={} for i=0,n-1 do add(out,peek(base+i)) end return out
end
function _init()
 reload(bank_audio_base,bank_audio_base,bank_size,"../pocket-tracker.p8")
 bank_project_init()
 playing=false audition_active=false song_pattern=0 song_play_pattern=0
 song_channel=2 song_scroll=0 app_view="song" sfx_number=1 sfx_row=0
 play_follow=true transport_tick=0 song_error=nil sfx_error=nil
 song_mix,song_mix_channel,song_mix_stage,song_active=0,0,0,"a----"
 poke(bank_sfx_addr(0,64),0)
 poke(bank_sfx_addr(0,66),peek(bank_sfx_addr(0,66))|0x80)
 poke(bank_sfx_addr(0,0),0x7f)
 memcpy(bank_sfx_addr(7,0),bank_sfx_addr(0,0),bank_sfx_size)
 local authored=snap(bank_sfx_addr(1,0),bank_sfx_size*4)
 local scratch=snap(bank_sfx_addr(63,0),bank_sfx_size)
 local raw=snap(bank_audio_base,bank_size)
 bank_profile_kind=0
 ck(start_song(0) and playing and not bank_profile_is_active(),"raw profile start")
 ck(same(bank_audio_base,raw,bank_size) and song_status()=="p00 r00 clean raw all a----",
  "raw playback zero writes status")
 local calls=#music_calls revision=bank_revision
 ck(song_restore_then(function() return bank_write(bank_song_addr(0,0),1,2) end),"raw active edit")
 raw[1]=2
 ck(#music_calls==calls+2 and same(bank_audio_base,raw,bank_size) and
  bank_revision==revision+1 and playing and not bank_profile_is_active(),"raw edit restart once")
 stop_song()
 poke(bank_song_addr(0,0),0x81)
 bank_profile_kind=1 bank_project_init() music_calls={}
 ck(start_song(0) and start_song(0),"idempotent play")
 ck(bank_profile_is_active() and song_status()=="p00 r00 clean +2 all a----",
  "single boosted start")
 ck(start_audition(0),"row preview")
 ck(not playing and not bank_profile_is_active(),"preview stops restores music")
 ck(same(bank_sfx_addr(1,0),authored,bank_sfx_size*4),"sfx 1-4 exact")
 ck(peek2(bank_sfx_addr(63,0))==peek2(bank_note_addr(1,0)),"row copied to scratch")
 ck(not bank_dirty and bank_revision==0,"preview metadata clean")
 ck(stop_audition(true),"preview stop resumes")
 ck(same(bank_sfx_addr(63,0),scratch,bank_sfx_size),"scratch restored")
 ck(playing and bank_profile_is_active() and #music_calls==3,"music resumed")
 sfx_number=63
 ck(start_audition() and stop_audition(true),"whole reserved sfx preview")
 stop_song()
 ck(same(bank_sfx_addr(63,0),scratch,bank_sfx_size) and
  same(bank_sfx_addr(1,0),authored,bank_sfx_size*4),"whole preview restores bytes")
 sfx_number=1 start_song(0)
 local old=bank_note_authored_raw(1,0)
 ck(song_restore_then(function() return bank_write(bank_note_addr(1,0),2,old^^1) end),
  "active edit")
 ck(playing and bank_profile_is_active() and bank_note_authored_raw(1,0)==(old^^1),
  "stop restore edit restart")
 local filter=bank_sfx_filter(1,1)
 ck(song_restore_then(function()
  local addr=bank_sfx_addr(1,64)
  return bank_write(addr,1,peek(addr)+(1-filter*2)*bank_filter_steps[1])
 end),
  "active filter edit")
 ck(playing and bank_profile_is_active() and bank_sfx_filter(1,1)==1-filter,
  "filter stop restore edit restart")
 local sample_addr=bank_sfx_addr(0,0)
 calls=#music_calls revision=bank_revision
 ck(song_restore_then(function() return bank_write(sample_addr,1,0x80) end),
  "active waveform edit")
 ck(#music_calls==calls+2 and peek(sample_addr)==0x80 and
  bank_revision==revision+1 and playing and bank_profile_is_active(),
  "waveform stop restore edit restart once")
 local bass_addr=bank_sfx_addr(0,65) local bass=peek(bass_addr)
 calls=#music_calls revision=bank_revision
 ck(song_restore_then(function() return bank_write(bass_addr,1,bass^^1) end),
  "active waveform bass edit")
 ck(#music_calls==calls+2 and peek(bass_addr)==(bass^^1) and
  (peek(bass_addr)&0xfe)==(bass&0xfe) and bank_revision==revision+1 and
  playing and bank_profile_is_active(),"bass stop restore edit restart once")
 for slot in all({0,7}) do
  local wave_filter=bank_sfx_addr(slot,64) local filter_old=peek(wave_filter)
  calls=#music_calls revision=bank_revision
  ck(song_restore_then(function() return bank_write(wave_filter,1,filter_old+8) end),
   "active waveform filter edit "..slot)
  ck(#music_calls==calls+2 and bank_sfx_filter(slot,3)==1 and
   bank_revision==revision+1 and playing and bank_profile_is_active(),
   "waveform filter restart exact "..slot)
 end
 poke2(bank_clip_base,0x1234) sfx_clip_count=1
 calls=#music_calls revision=bank_revision
 ck(not bank_rows(1,0,1,bank_clip_base,false),"batch preflight differs")
 ck(song_restore_then(function() return bank_rows(1,0,1,bank_clip_base,true) end),
  "active batch edit")
 ck(#music_calls==calls+2 and bank_revision==revision+1 and
  bank_note_authored_raw(1,0)==0x1234 and playing and bank_profile_is_active(),
  "batch stop restore restart once")
 stats[57]=false transport_tick=3 update_playhead()
 ck(not playing and not bank_profile_is_active(),"native stop restores profile")
 start_song(0)
 stats[57]=true stats[54]=12 stats[55]=7 stats[56]=99
 for ch=0,3 do stats[46+ch]=ch+1 stats[50+ch]=ch+4 end
 transport_tick=3 app_view="sfx" sfx_number=3
 update_playhead()
 ck(song_pattern==12 and play_step==7 and sfx_row==6,"native stat follow")
 for i=46,54 do ck(seen[i],"stat "..i) end
 ck(seen[57],"stat 57")
 stop_song()

 -- Profile-range waveforms stay exact through apply, edits, restart, and restore.
 local prior=snap(bank_audio_base,bank_size)
 local prior_dirty,prior_revision=bank_dirty,bank_revision
 reload(bank_stage_base,bank_audio_base,bank_size,"fixtures/pico8-027-waveform.p8")
 for slot in all({1,4}) do
  memcpy(bank_sfx_addr(slot,0),bank_stage_base+0x100,bank_sfx_size)
 end
 poke2(bank_sfx_addr(2,0),0x0a18)
 poke2(bank_sfx_addr(3,0),0x0e18)
 poke2(bank_sfx_addr(8,0),0x8a58)
 local wave=snap(bank_audio_base,bank_size)
 bank_project_init()
 calls=#music_calls
 ck(start_song(0) and start_song(0) and #music_calls==calls+1,
  "waveform profile play idempotent")
 for slot in all({1,4}) do
  for i=0,67 do
   ck(peek(bank_sfx_addr(slot,i))==wave[0x100+slot*68+i+1],
    "playing waveform exact "..slot..":"..i)
  end
 end
 ck((peek2(bank_sfx_addr(2,0))&0xffff)==0x0e18 and
  (peek2(bank_sfx_addr(3,0))&0xffff)==0x0e18,
  "playing conventional siblings boost and cap")
 local wave_addr=bank_sfx_addr(1,0) local wave_old=peek(wave_addr)
 calls=#music_calls revision=bank_revision
 ck(song_restore_then(function() return bank_write(wave_addr,1,wave_old^^1) end),
  "profile waveform sample edit")
 wave[0x100+68+1]=wave_old^^1
 ck(#music_calls==calls+2 and peek(wave_addr)==(wave_old^^1) and
  bank_revision==revision+1 and bank_profile_is_active(),
  "profile waveform sample restart exact")
 local wave_bass=bank_sfx_addr(1,65) local bass_old=peek(wave_bass)
 calls=#music_calls revision=bank_revision
 ck(song_restore_then(function() return bank_write(wave_bass,1,bass_old^^1) end),
  "profile waveform bass edit")
 wave[0x100+68+66]=bass_old^^1
 ck(#music_calls==calls+2 and peek(wave_bass)==(bass_old^^1) and
  bank_revision==revision+1 and bank_profile_is_active(),
  "profile waveform bass restart exact")
 for slot in all({1,4}) do
  local wave_filter=bank_sfx_addr(slot,64) local filter_old=peek(wave_filter)
  calls=#music_calls revision=bank_revision
  ck(song_restore_then(function() return bank_write(wave_filter,1,filter_old+24) end),
   "profile waveform filter edit "..slot)
  wave[0x100+slot*68+65]=filter_old+24
  ck(#music_calls==calls+2 and bank_sfx_filter(slot,4)==1 and
   bank_revision==revision+1 and bank_profile_is_active(),
   "profile waveform filter restart exact "..slot)
 end
 local wave_mode=bank_sfx_addr(4,66) local mode_old=peek(wave_mode)
 calls=#music_calls revision=bank_revision
 ck(song_restore_then(function() return bank_write(wave_mode,1,mode_old&0x7f) end),
  "profile waveform notes mode edit")
 wave[0x100+4*68+67]=mode_old&0x7f
 ck(#music_calls==calls+2 and not bank_sfx_is_waveform(4) and
  bank_revision==revision+1 and bank_profile_is_active(),
  "profile notes mode restart exact")
 calls=#music_calls revision=bank_revision
 ck(song_restore_then(function() return bank_write(wave_mode,1,mode_old|0x80) end),
  "profile waveform wave mode edit")
 wave[0x100+4*68+67]=mode_old|0x80
 ck(#music_calls==calls+2 and bank_sfx_is_waveform(4) and
  bank_revision==revision+1 and bank_profile_is_active(),
  "profile wave mode restart exact")
 stop_song()
 ck(same(bank_audio_base,wave,bank_size),"profile waveform complete restore")
 for i=0,bank_size-1 do poke(bank_audio_base+i,prior[i+1]) end
 bank_dirty,bank_revision=prior_dirty,prior_revision

 -- Session-only audition mix owns no project state and uses exact native masks.
 local bank=snap(bank_audio_base,bank_size)
 local dirty,revision,owner,width=bank_dirty,bank_revision,undo_owner,undo_width
 local mute={0xe,0xd,0xb,7}
 local solo={1,2,4,8}
 for ch=0,3 do
  song_channel=ch
  local calls=#music_calls
  song_mix_stage=1 song_mix_apply()
  ck(#music_calls==calls,"stopped mix defers "..ch)
  ck(start_song(12) and music_calls[#music_calls][3]==mute[ch+1],"mute mask "..ch)
  calls=#music_calls song_mix_stage=2 song_mix_apply()
  ck(#music_calls==calls+2 and music_calls[#music_calls-1][1]==-1 and
   music_calls[#music_calls][1]==12 and music_calls[#music_calls][3]==solo[ch+1],
   "playing solo restart "..ch)
  stop_song()
 end
 song_channel=0 song_mix_stage=0 song_mix_apply()
 start_song(12)
 stats[57]=true stats[54]=9
 for ch=0,3 do stats[46+ch]=ch stats[50+ch]=ch end
 transport_tick=3 update_playhead()
 local calls=#music_calls
 song_mix_stage=1 song_mix_apply()
 ck(#music_calls==calls+2 and music_calls[#music_calls][1]==9,
  "playing mix restarts observed pattern")
 stop_song()
 song_channel=2 song_mix_stage=2 song_mix_apply()
 start_song(9) start_audition(0) stop_audition(true)
 ck(music_calls[#music_calls][1]==9 and music_calls[#music_calls][3]==4,
  "preview resume retains mix")
 stats[57]=true stats[54]=9
 stats[46],stats[47],stats[48],stats[49]=0,-1,3,-1
 stats[50],stats[51],stats[52],stats[53]=2,3,4,5
 transport_tick=3 song_channel=2 app_view="song" update_playhead()
 ck(song_active=="a1-3-" and play_step==5,"active mask includes sfx zero")
 stats[57]=false update_playhead()
 ck(song_active=="a----" and not playing,"native stop resets active mask")
 song_mix_stage=0 song_mix_apply()
 ck(start_song(0) and music_calls[#music_calls][3]==0xf,"all mask")
 stop_song()
 ck(same(bank_audio_base,bank,bank_size) and bank_dirty==dirty and
  bank_revision==revision and undo_owner==owner and undo_width==width and
  not bank_profile_is_active(),"mix preserves project history profile")
 if fails==0 then printh("pocket tracker playback transport: passed")
 else printh("pocket tracker playback transport: failed "..fails) end
 extcmd("shutdown")
end
function _draw() end
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
