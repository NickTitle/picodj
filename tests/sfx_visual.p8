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
 sfx_number=0 sfx_meta_field=4
 draw_sfx_handoff()
 extcmd("set_filename","picodj-sfx-mode-notes-m3")
 extcmd("screen")
 sfx_number=63 sfx_mode="filters" sfx_filter_field=3
 poke(bank_sfx_addr(63,64),0xd7)
 draw_sfx_handoff()
 extcmd("set_filename","picodj-sfx-filters-m2")
 extcmd("screen")
 poke(bank_sfx_addr(63,64),0xd8)
 draw_sfx_handoff()
 extcmd("set_filename","picodj-sfx-filters-raw-m2")
 extcmd("screen")
 sfx_number=0 sfx_mode="rows" sfx_row=31 sfx_scroll=23 sfx_field=2
 poke(bank_sfx_addr(0,66),peek(bank_sfx_addr(0,66))|0x80)
 poke(bank_sfx_addr(0,62),0x80) poke(bank_sfx_addr(0,63),0xff)
 draw_sfx_handoff()
 extcmd("set_filename","picodj-sfx-waveform-m3")
 extcmd("screen")
 sfx_mode="meta" sfx_meta_field=2
 poke(bank_sfx_addr(0,65),0x11)
 draw_sfx_handoff()
 extcmd("set_filename","picodj-sfx-waveform-mode-m3")
 extcmd("screen")
 sfx_mode="filters" sfx_filter_field=1
 poke(bank_sfx_addr(0,64),0xd0)
 draw_sfx_handoff()
 extcmd("set_filename","picodj-sfx-waveform-filters-m3")
 extcmd("screen")
 printh("pocket tracker sfx visual: passed")
 extcmd("shutdown")
end
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
