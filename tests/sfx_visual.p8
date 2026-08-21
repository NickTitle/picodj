pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
#include ../audio_bank.lua
#include ../sfx_ui.lua
function hex2(value)
 local d="0123456789abcdef"
 return sub(d,flr(value/16)+1,flr(value/16)+1)..sub(d,value%16+1,value%16+1)
end
function _init()
 reload(bank_audio_base,bank_audio_base,bank_size,"../pocket-tracker.p8")
 bank_project_init()
 sfx_number=1 sfx_row=15 sfx_scroll=11 sfx_field=4 sfx_mode="rows"
 context_menu=nil edit_owner=nil sfx_error=nil playing=false audition_active=false
 draw_sfx_handoff()
 extcmd("set_filename","picodj-sfx-m13")
 extcmd("screen")
 sfx_mode="meta" sfx_meta_field=2
 draw_sfx_handoff()
 extcmd("set_filename","picodj-sfx-meta-m13")
 extcmd("screen")
 printh("pocket tracker sfx visual: passed")
 extcmd("shutdown")
end
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
