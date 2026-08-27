pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
#include ../audio_bank.lua
#include ../song_ui.lua
fails=0
frames=0
function ck(v,s) if not v then fails+=1 printh("fail: "..s) end end
function say() end
function finish()
 stop_song()
 ck(not bank_profile_is_active(),"profile restored")
 ck((bank_checksum(bank_audio_base)&0xffff)==original_crc,"authored bank restored")
 if fails==0 then printh("pocket tracker m1 playback: passed")
 else printh("pocket tracker m1 playback: failed "..fails) end
 extcmd("shutdown")
end
function _init()
 reload(bank_audio_base,bank_audio_base,bank_size,"../pocket-tracker.p8")
 bank_project_init()
 playing=false audition_active=false song_pattern=0 song_play_pattern=0
 song_channel=0 song_scroll=0 app_view="song" play_follow=true
 transport_tick=0 play_tick=0 song_error=nil
 song_mix,song_mix_channel=0,0
 original_crc=bank_checksum(bank_audio_base)
 ck(start_song(0),"native start")
end
function _update60()
 frames+=1
 if frames==8 then
  ck(stat(57) and stat(54)==0,"native music active")
  for ch=0,3 do ck(stat(46+ch)==ch+1,"native channel "..ch) end
  finish()
 end
end
function _draw() end
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
