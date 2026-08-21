pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
#include ../tracker.lua

failures=0

function check(ok,label)
 if ok then return end
 failures+=1
 printh("fail: "..label)
end

function rebuild_track() end
function publish_gpio() end
function audition() end

function reset_fixture(note)
 fresh_song()
 notes[1][1]=note
 last_notes[1]=note
 slot=1
 cursor_ch=1
 cursor_step=1
 menu_item=1
 context_menu=nil
 context_item=1
 context_gate=false
 action_gate=false
 playing=false
 notice=""
 notice_tick=0
 reset_action_input()
end

function release_context_gate()
 update_context_menu(false,false,false,false,false,false,false,false)
end

function _init()
 -- A quick O/X press defers its edit until release and fires exactly once.
 reset_fixture(24)
 update_action_buttons(true,false)
 check(notes[1][1]==24,"o tap waits for release")
 update_action_buttons(false,false)
 check(notes[1][1]==25,"o tap raises once")
 update_action_buttons(false,false)
 check(notes[1][1]==25,"o idle does not repeat")

 reset_fixture(24)
 update_action_buttons(false,true)
 check(notes[1][1]==24,"x tap waits for release")
 update_action_buttons(false,false)
 check(notes[1][1]==23,"x tap lowers once")

 -- Holding O opens Start without leaking the normal note edit.
 reset_fixture(24)
 for i=1,hold_frames do update_action_buttons(true,false) end
 check(context_menu=="start","o hold opens start menu")
 check(context_gate,"start menu waits for release")
 check(notes[1][1]==24,"o hold preserves note")
 update_context_menu(true,false,false,false,false,false,false,false)
 check(context_gate,"held opener remains gated")
 release_context_gate()
 check(not context_gate,"released opener clears gate")
 update_context_menu(false,false,false,false,false,false,false,true)
 check(context_item==2,"start menu moves down")
 update_context_menu(false,true,false,true,false,false,false,false)
 check(context_menu==nil and action_gate,"x cancels start menu")

 -- Holding X opens Select; its channel values adjust in place.
 reset_fixture(24)
 for i=1,hold_frames do update_action_buttons(false,true) end
 check(context_menu=="select","x hold opens select menu")
 check(notes[1][1]==24,"x hold preserves note")
 release_context_gate()
 update_context_menu(false,false,false,false,false,false,false,true)
 check(context_item==2,"select menu moves to rest")
 update_context_menu(false,false,false,false,false,false,false,true)
 check(context_item==3,"select menu moves to wave")
 local wave=waves[1]
 update_context_menu(false,false,false,false,false,true,false,false)
 check(waves[1]==(wave+1)%8,"select right raises value")
 check(context_menu=="select","select edit keeps menu open")

 -- The optional O+X chord remains a single rest toggle, never a hold menu.
 reset_fixture(24)
 update_action_buttons(true,true)
 check(notes[1][1]==-1,"chord toggles rest")
 for i=1,hold_frames+2 do update_action_buttons(true,true) end
 check(notes[1][1]==-1,"held chord does not repeat")
 check(context_menu==nil,"held chord opens no menu")
 update_action_buttons(false,false)
 check(notes[1][1]==-1,"chord release fires no tap")

 if failures==0 then
  printh("pocket tracker hold menus: passed")
 else
  printh("pocket tracker hold menus: failed "..failures)
 end
 extcmd("shutdown")
end

__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
