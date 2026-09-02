pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
#include ../audio_bank.lua
#include ../tracker.lua
#include ../song_ui.lua

failures=0
music_calls={}
function load_song() return false end
function save_song() return false end
app_init=_init

function check(ok,label)
 if ok then return end
 failures+=1
 printh("fail: "..label)
end
function raw_song(pattern,channel) return peek(bank_song_addr(pattern,channel)) end
function move_pattern(delta)
 song_pattern=mid(0,song_pattern+delta,bank_pattern_count-1)
 song_keep_visible()
end
function move_channel(delta)
 song_channel=mid(0,song_channel+delta,bank_channel_count-1)
end

function native_music(pattern,fade,mask)
 add(music_calls,{pattern,fade,mask})
end

function song_edit_candidate(delta) edit_value=(edit_value+delta)%64 end
function song_cancel_edit() edit_cancel() end
function song_commit_edit() return edit_commit() end
function song_undo() return edit_undo("song") end

function reset_ui()
 reload(bank_audio_base,bank_audio_base,bank_size,"../pocket-tracker.p8")
 bank_project_init()
 app_view="song"
 context_menu=nil
 context_item=1
 context_gate=false
 action_gate=false
 song_pattern=0
 song_channel=0
 song_scroll=0
 edit_owner=nil undo_owner=nil
 song_error=nil
 playing=false
 play_step=1
 song_mix,song_mix_channel,song_mix_stage,song_active=0,0,0,"a----"
 music_calls={}
 reset_action_input()
end

function check_unrelated(before,after,owned,label)
 check(((before^^after)&(0xff^^owned))==0,label)
end

function _init()
 reload(bank_audio_base,bank_audio_base,bank_size,"../pocket-tracker.p8")
 app_init()

 -- The main cartridge, not only the fixture cart, boots the canonical bank.
 check((bank_checksum(bank_audio_base)&0xffff)==song_expected_crc,
       "main cartridge canonical crc")
check(raw_song(0,0)==0x81 and raw_song(0,1)==0x82 and
       raw_song(0,2)==3 and raw_song(0,3)==4,
       "main cartridge pattern 00")
check(app_view=="song" and song_error==nil and not bank_dirty and
       bank_revision==0 and song_mix==0 and song_active=="a----",
       "main initialization accepts canonical seed")
 reset_ui()

 -- Native SONG is the primary boot screen; Hold X opens its own context.
 for i=1,hold_frames do update_action_buttons(false,true) end
 check(context_menu=="song" and context_item==1,
       "hold x opens native song context")
 update_context_menu(false,false,false,false,false,false,false,false)
 close_context_menu()
 check(app_view=="song" and action_gate,
       "song context returns to native screen")

 -- All 64 patterns and four channels are reachable without wraparound.
 action_gate=false reset_action_input()
 move_pattern(63)
 move_channel(3)
 check(song_pattern==63 and song_channel==3 and song_scroll==54,
       "last pattern channel and scroll")
 move_pattern(1)
 move_channel(1)
 check(song_pattern==63 and song_channel==3,"upper bounds clamp")
 move_pattern(-63)
 move_channel(-3)
 check(song_pattern==0 and song_channel==0 and song_scroll==0,
       "first pattern channel and scroll")

 -- SFX edits own only bits 0..5 and commit as one full-byte transaction.
 poke(bank_song_addr(63,3),0xff)
 bank_project_init()
 song_pattern=63
 song_channel=3
 check(song_begin_edit("sfx"),"begin wrap sfx edit")
 song_edit_candidate(1)
 check(edit_value==0,"sfx 3f wraps to 00 preserving high bits")
 song_cancel_edit()
 poke(bank_song_addr(63,3),0xc5)
 bank_project_init()
 song_pattern=63
 song_channel=3
 check(song_begin_edit("sfx"),"begin last sfx edit")
 song_edit_candidate(1)
 check(edit_value==6,"staged sfx preserves high bits")
 local before=peek(edit_addr)
 local revision=bank_revision
 check(song_commit_edit(),"commit sfx edit")
 local after=raw_song(63,3)
 check(after==0xc6,"commit stores complete byte")
 check_unrelated(before,after,0x3f,"sfx preserves mute/reserved")
 check(bank_dirty and bank_revision==revision+1,"commit dirty revision")

 -- Cancel and no-op commit do not mutate bytes or metadata.
 before=after
 revision=bank_revision
 local dirty=bank_dirty
 check(song_begin_edit("sfx"),"begin cancel edit")
 song_edit_candidate(1)
 song_cancel_edit()
 check(raw_song(63,3)==before and bank_revision==revision and
       bank_dirty==dirty,"cancel preserves byte dirty revision")
 check(song_begin_edit("sfx"),"begin no-op edit")
 check(song_commit_edit(),"no-op commit")
 check(raw_song(63,3)==before and bank_revision==revision and
       bank_dirty==dirty,"no-op preserves byte dirty revision")

 -- Every channel mute owns only bit 6.
 for ch=0,3 do
  reset_ui()
  song_pattern=1
  song_channel=ch
  before=raw_song(1,ch)
  check(song_begin_edit("mute"),"begin mute "..ch)
  check(song_commit_edit(),"commit mute "..ch)
  after=raw_song(1,ch)
  check(after==(before^^0x40),"mute toggles bit "..ch)
  check_unrelated(before,after,0x40,"mute preserves bits "..ch)
 end

 -- One-level history swaps exact bytes and dirty states in both directions.
 reset_ui()
 song_pattern=1
 song_channel=0
 before=raw_song(1,0)
 check(song_begin_edit("mute"),"begin undo edit")
 check(song_commit_edit(),"commit undo edit")
 after=raw_song(1,0)
 check(after==(before^^0x40),"mute toggles owned bit")
 check_unrelated(before,after,0x40,"mute preserves unrelated bits")
 revision=bank_revision
 check(song_undo(),"undo succeeds")
 check(raw_song(1,0)==before,"undo restores full byte")
 check(not bank_dirty and bank_revision==revision+1,
       "undo restores clean and advances revision")
 revision=bank_revision
 check(undo_width<0,"undo exposes redo phase")
 check(song_begin_edit("sfx"),"begin cancel with redo")
 edit_value=(edit_value+1)%64
 song_cancel_edit()
 check(undo_width<0 and bank_revision==revision,"cancel preserves redo")
 check(song_begin_edit("sfx"),"begin no-op with redo")
 check(song_commit_edit() and undo_width<0 and bank_revision==revision,
       "no-op preserves redo")
 check(song_undo(),"redo succeeds")
 check(raw_song(1,0)==after and bank_dirty and
       bank_revision==revision+1 and undo_width>0,
       "redo restores post byte dirty and advances revision")
 revision=bank_revision
 check(song_undo() and raw_song(1,0)==before and not bank_dirty and
       bank_revision==revision+1,"second undo restores pre state")

 -- A new real edit replaces the available redo transaction.
 local replacement_before=raw_song(1,0)
 check(song_begin_edit("sfx"),"begin replacement edit")
 edit_value=(edit_value+1)%64
 check(song_commit_edit() and undo_width>0,"new edit replaces redo phase")
 local replacement_after=raw_song(1,0)
 check(song_undo() and raw_song(1,0)==replacement_before,
       "replacement undo restores its own pre byte")
 check(song_undo() and raw_song(1,0)==replacement_after,
       "replacement redo restores its own post byte")

 -- Flow flags preserve every other bit; channel four remains reserved.
 for ch=0,2 do
  reset_ui()
  song_pattern=1
  song_channel=ch
  before=raw_song(1,ch)
  check(song_begin_edit("flow"),"begin flow "..ch)
  check(song_commit_edit(),"commit flow "..ch)
  after=raw_song(1,ch)
  check(after==(before^^0x80),"flow toggles bit "..ch)
  check_unrelated(before,after,0x80,"flow preserves bits "..ch)
 end
 reset_ui()
 song_pattern=1
 song_channel=3
 before=raw_song(1,3)
 revision=bank_revision
 check(not song_begin_edit("flow") and song_error!=nil,
       "reserved flow rejected visibly")
 check(raw_song(1,3)==before and bank_revision==revision,
       "reserved flow preserves byte revision")

 -- Active playback stops/restores, edits, reapplies, and restarts natively.
 reset_ui()
 song_pattern=63
 song_channel=0
 check(start_song(),"native playback starts")
 check(playing and bank_profile_active and music_calls[1][1]==63 and
       music_calls[1][3]==0xf,
       "music pattern and profile active")
 before=raw_song(63,0)
 check(song_begin_edit("mute"),"begin edit during play")
 check(song_commit_edit(),"commit edit during play")
 check(playing and bank_profile_active,"playback restarts")
 check(#music_calls==3 and music_calls[2][1]==-1 and music_calls[3][1]==63,
       "edit uses stop restore restart")
 check(raw_song(63,0)==(before^^0x40),"active edit is not dropped")
 check(song_undo() and playing and bank_profile_active and
       raw_song(63,0)==before and #music_calls==5,
       "active undo stops restores swaps restarts")
 check(song_undo() and playing and bank_profile_active and
       raw_song(63,0)==(before^^0x40) and #music_calls==7,
       "active redo stops restores swaps restarts")
 check(stop_song() and not bank_profile_active,"native playback restores")

 -- O hands the exact selected SFX to Arc 2; X return keeps cursor/scroll.
 reset_ui()
 app_view="song"
 song_pattern=63
 song_channel=3
 song_scroll=54
 local prior_status=song_status()
 song_open_sfx()
 check(app_view=="sfx" and sfx_number==(raw_song(63,3)&0x3f) and
       sfx_row==0 and sfx_scroll==0 and sfx_field==1 and sfx_mode=="rows",
       "sfx handoff shipped state")
 check(song_status()==prior_status,"sfx handoff preserves song status")
 action_gate=false reset_action_input()
 song_return_from_sfx()
 check(song_pattern==63 and song_channel==3 and song_scroll==54,
       "sfx return preserves song cursor")
 check(song_status()==prior_status,"sfx return preserves song status")

 -- SONG's own X hold opens context; a quick release stays on native SONG.
 reset_ui()
 app_view="song"
 for i=1,hold_frames do update_action_buttons(false,true) end
 check(context_menu=="song" and context_gate and app_view=="song",
       "song hold x opens contextual menu")
 close_context_menu()
 check(app_view=="song" and action_gate,"menu close release-gated")
 action_gate=false reset_action_input()
 update_action_buttons(false,true)
 update_action_buttons(false,false)
 check(app_view=="song","song tap x stays native")

 if failures==0 then
  printh("pocket tracker song ui: passed")
 else
  printh("pocket tracker song ui: failed "..failures)
 end
 extcmd("shutdown")
end

__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
