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
 poke(bank_sfx_addr(0,66),peek(bank_sfx_addr(0,66))|0x80)
 poke(bank_sfx_addr(0,0),0x7f)
 local authored=snap(bank_sfx_addr(1,0),bank_sfx_size*4)
 local scratch=snap(bank_sfx_addr(63,0),bank_sfx_size)
 ck(start_song(0) and start_song(0),"idempotent play")
 ck(#music_calls==1 and bank_profile_is_active(),"single boosted start")
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
 local calls=#music_calls revision=bank_revision
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
