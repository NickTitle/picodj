pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
#include ../audio_bank.lua
#include ../song_ui.lua
fails=0
phase=1
frames=0
max_tick=-1
max_right_row=-1
max_len_row=-1
saw_fast_end=false
saw_loop=false
function say() end
function ck(ok,label)
 if not ok then fails+=1 printh("fail: "..label) end
end
function reset_player(pattern)
 playing=false audition_active=false song_pattern=pattern song_play_pattern=pattern
 song_channel=0 song_scroll=0 app_view="song" play_follow=false
 transport_tick=0 play_tick=0 song_error=nil
 song_mix,song_mix_channel=0,0
 max_tick=-1 max_right_row=-1 max_len_row=-1
 ck(start_song(pattern),"start pattern "..pattern)
end
function raw_fixture_checks()
 local music={8,9,10,9,12,13,14,12,16,16,0x90,16}
 for i=0,11 do ck(peek(bank_song_base+i)==music[i+1],"music byte "..i) end
 local meta={{8,0,0},{1,0,0},{1,0,2},{1,0,2},{32,8,0},{16,0,0},{8,0,0}}
 local slots={8,9,10,12,13,14,16}
 for i=1,#slots do
  local addr=bank_sfx_addr(slots[i],64)
  ck(peek(addr)==0 and peek(addr+1)==meta[i][1] and
   peek(addr+2)==meta[i][2] and peek(addr+3)==meta[i][3],"sfx meta "..slots[i])
 end
end
function finish()
 ck(not stat(57),"music stopped")
 ck(not bank_profile_is_active(),"profile restored")
 ck((bank_checksum(bank_audio_base)&0xffff)==original_crc,"authored bank restored")
 if fails==0 then printh("pocket tracker sfx timing: passed")
 else printh("pocket tracker sfx timing: failed "..fails) end
 extcmd("shutdown")
end
function _init()
 reload(bank_audio_base,bank_audio_base,bank_size,"fixtures/pico8-027-timing.p8")
 bank_project_init()
 raw_fixture_checks()
 original_crc=bank_checksum(bank_audio_base)
 reset_player(0)
end
function _update60()
 frames+=1
 if frames>600 then ck(false,"bounded timeout") stop_song() finish() return end
 local active=stat(57)
 local pattern=stat(54)
 local ticks=stat(56)
 if phase==1 then
  if active and pattern==0 then
   max_tick=max(max_tick,ticks)
   max_right_row=max(max_right_row,stat(51))
   if ticks>=64 then
    saw_fast_end=saw_fast_end or stat(47)==9 and stat(51)>=32
    saw_loop=saw_loop or stat(48)==10 and stat(52)<=1
   end
  elseif active and pattern==1 then
   printh("case1 stat transition "..max_tick.." -> "..ticks)
   ck(max_tick>=252 and max_tick<256,"case1 boundary 256")
   ck(saw_fast_end,"faster right channel ended first")
   ck(saw_loop,"looping right channel stayed active")
   ck(ticks<=3,"case1 next pattern tick")
   ck(bank_profile_is_active(),"profile active across handoff")
   phase=2 max_tick=-1 max_right_row=-1 max_len_row=-1 saw_loop=false
  elseif not active and max_tick>=0 then ck(false,"case1 stopped early") finish() end
 elseif phase==2 then
  if active and pattern==1 then
   max_tick=max(max_tick,ticks)
   max_len_row=max(max_len_row,stat(51))
   max_right_row=max(max_right_row,stat(52))
   if ticks>=32 then saw_loop=saw_loop or stat(46)==12 and stat(50)<=1 end
  elseif active and pattern==2 then
   printh("case2 stat transition "..max_tick.." -> "..ticks)
   ck(max_tick>=252 and max_tick<256,"case2 len boundary 256")
   ck(saw_loop,"looping left channel skipped")
   ck(max_len_row==7,"len row 7 authority")
   ck(max_right_row<31,"slower right channel cut short")
   ck(ticks<=3,"case2 next pattern tick")
   stop_song() phase=3 wait=4
  elseif not active and max_tick>=0 then ck(false,"case2 stopped early") finish() end
 else
  wait-=1
  if wait==0 then finish() end
 end
end
function _draw() end
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
