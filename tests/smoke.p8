pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
#include ../tracker.lua
#include legacy_tracker.lua

function check(ok,label)
 if not ok then
  printh("fail: "..label)
  extcmd("shutdown")
 end
end

function _init()
 cartdata("pocket_tracker_test")
 fresh_song()
 slot=3
 cursor_ch=1
 cursor_step=1
 menu_item=1
 playing=false
 play_tick=0
 play_step=1
 export_counter=0
 notice=""
 notice_tick=0
 rebuild_all()

 check(note_word(24)=="c-2","note label")
 check(note_word(-1)=="---","rest label")
 check(sfx_speed()==16,"120 bpm speed")
 check(peek2(0x3200)==24+waves[1]*64+volumes[1]*512,"sfx note packing")

 notes[1][1]=42
 waves[1]=5
 volumes[1]=7
 effects[1]=3
 bpm=150
 save_song()
 notes[1][1]=-1
 waves[1]=0
 volumes[1]=0
 effects[1]=0
 bpm=60
 check(load_song(false),"saved slot loads")
 check(notes[1][1]==42,"note persists")
 check(waves[1]==5 and volumes[1]==7 and effects[1]==3,"instrument persists")
 check(bpm==150,"tempo persists")

 publish_gpio()
 check(peek(gpio_addr)==80 and peek(gpio_addr+1)==84,"gpio signature")
 check(peek(gpio_addr+3)==150,"gpio tempo")
 check(peek(gpio_addr+16)==42,"gpio first note")

 cursor_ch=2
 cursor_step=2
 notes[2][2]=-1
 last_notes[2]=30
 toggle_rest()
 check(notes[2][2]==30,"restore rest")
 toggle_rest()
 check(notes[2][2]==-1,"set rest")

 cursor_ch=1
 menu_item=8
 effects[1]=0
 activate_menu(false)
 check(effects[1]==1,"effect increments")
 activate_menu(true)
 check(effects[1]==0,"effect decrements")

 menu_item=9
 local export_before=peek(gpio_addr+126)
 activate_menu(false)
 check(peek(gpio_addr+125)==1,"json export kind")
 check(peek(gpio_addr+126)!=export_before,"json export request")
 export_before=peek(gpio_addr+126)
 activate_menu(true)
 check(peek(gpio_addr+125)==2,"wav export kind")
 check(peek(gpio_addr+126)!=export_before,"wav export request")

 start_song()
 check(playing,"play starts")
 loop_test_frames=0
 loop_test_phrase_frames=ceil(steps*sfx_speed()*60/128)
 loop_test_target=loop_test_phrase_frames+12
end

function _update60()
 if loop_test_done then return end
 if loop_stop_pending then
  check(not playing,"play stops")
  loop_test_done=true
  printh("pocket tracker smoke: passed")
  extcmd("shutdown")
  return
 end
 loop_test_frames+=1
 update_playhead()
 if loop_test_frames<loop_test_target then return end

 check(play_tick>loop_test_phrase_frames,"playhead crosses loop boundary")
 for ch=0,tracks-1 do
  check(stat(46+ch)==ch,"channel "..ch.." keeps looping")
 end
 stop_song()
 loop_stop_pending=true
end
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
