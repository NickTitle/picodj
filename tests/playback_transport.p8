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
function native_music(p) add(music_calls,p) end
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
 play_follow=true transport_tick=0 play_tick=0 song_error=nil sfx_error=nil
 local authored=snap(bank_sfx_addr(1,0),bank_sfx_size*4)
 local scratch=snap(bank_sfx_addr(63,0),bank_sfx_size)
 ck(start_song(0) and start_song(0),"idempotent play")
 ck(#music_calls==1 and bank_profile_is_active(),"single boosted start")
 ck(start_audition(0),"row preview")
 ck(not playing and not bank_profile_is_active(),"preview stops restores music")
 ck(same(bank_sfx_addr(1,0),authored,bank_sfx_size*4),"sfx 1-4 exact")
 ck(peek2(bank_sfx_addr(63,0))==bank_note_raw(1,0),"row copied to scratch")
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
 ck(song_restore_then(function() return bank_write_word(bank_note_addr(1,0),old^^1) end),
  "active edit")
 ck(playing and bank_profile_is_active() and bank_note_authored_raw(1,0)==(old^^1),
  "stop restore edit restart")
 local filter=bank_sfx_filter(1,1)
 ck(song_restore_then(function() return bank_set_sfx_filter(1,1,1-filter) end),
  "active filter edit")
 ck(playing and bank_profile_is_active() and bank_sfx_filter(1,1)==1-filter,
  "filter stop restore edit restart")
 stats[57]=false transport_tick=3 update_playhead()
 ck(not playing and not bank_profile_is_active(),"native stop restores profile")
 start_song(0)
 stats[57]=true stats[54]=12 stats[55]=7 stats[56]=99
 for ch=0,3 do stats[46+ch]=ch+1 stats[50+ch]=ch+4 end
 transport_tick=3 app_view="sfx" sfx_number=3
 update_playhead()
 ck(song_pattern==12 and play_count==7 and play_ticks==99 and play_step==7 and
  sfx_row==6,"native stat follow")
 for i=46,57 do ck(seen[i],"stat "..i) end
 stop_song()
 if fails==0 then printh("pocket tracker playback transport: passed")
 else printh("pocket tracker playback transport: failed "..fails) end
 extcmd("shutdown")
end
function _draw() end
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
