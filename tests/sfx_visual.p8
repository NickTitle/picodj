pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
#include ../audio_bank.lua
#include ../tracker.lua
#include ../song_ui.lua
#include ../sfx_ui.lua
function _init()
 reload(bank_audio_base,bank_audio_base,bank_size,"../pocket-tracker.p8")
 bank_project_init() fresh_song()
 sfx_number=1 sfx_row=15 sfx_scroll=11 sfx_field=4 sfx_mode="rows"
 sfx_menu=false sfx_edit=false sfx_error=nil playing=false
 draw_sfx_handoff()
 extcmd("set_filename","picodj-sfx-arc2")
 extcmd("screen")
 sfx_mode="meta" sfx_meta_field=2
 draw_sfx_handoff()
 extcmd("set_filename","picodj-sfx-meta-arc2")
 extcmd("screen")
 printh("pocket tracker sfx visual: passed")
 extcmd("shutdown")
end
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
