pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
#include ../audio_bank.lua

playing=false
audition_active=false
undo_owner=nil
song_error=nil
notice=""

function _init() end
function _update60() end
function context_label(name) return name end
function say(text) notice=text end
function stop_audition() audition_active=false return true end
function stop_song() bank_profile_restore() playing=false return true end

#include ../project_io.lua

failures=0

function check(ok,label)
 if ok then return end
 failures+=1
 printh("fail: "..label)
end

function clipboard_intact()
 if sfx_clip_count!=17 then return false end
 for i=0,63 do
  if peek(bank_clip_base+i)!=(i*37+11)&0xff then return false end
 end
 return true
end

function waveform_intact()
 if not bank_sfx_is_waveform(0) then return false end
 for i=0,63 do
  if peek(bank_sfx_addr(0,i))!=(i*29+7)&0xff then return false end
 end
 return true
end

function saved_byte(offset)
 if offset<io_header_size then return peek(io_header+offset) end
 return peek(bank_snapshot_base+offset-io_header_size)
end

function refresh_saved_envelope_crc()
 io_put16(io_header+10,0)
 local crc=0xffff
 for i=0,io_header_size-1 do crc=io_crc_byte(crc,peek(io_header+i)) end
 for i=0,bank_size-1 do crc=io_crc_byte(crc,peek(bank_snapshot_base+i)) end
 io_put16(io_header+10,crc)
 return crc
end

function emit_saved_page(sequence,offset,corrupt)
 local length=min(io_payload_size,io_envelope_size-offset)
 local flags=(offset==0 and 1 or 0)|(offset+length==io_envelope_size and 2 or 0)
 io_begin_frame(io_page_load,io_id,sequence,offset,io_envelope_size,length,flags)
 for i=0,length-1 do poke(io_gpio+16+i,saved_byte(offset+i)) end
 io_finish_frame()
 if corrupt then poke(io_gpio+16,peek(io_gpio+16)^^1) end
 project_io_update()
 return length
end

project_test_init=_init
function _init()
 project_test_init()
 bank_project_init()
 for i=0,63 do poke(bank_sfx_addr(0,i),(i*29+7)&0xff) end
 poke(bank_sfx_addr(0,66),peek(bank_sfx_addr(0,66))|0x80)
 sfx_clip_count=17
 for i=0,63 do poke(bank_clip_base+i,(i*37+11)&0xff) end
 check(bank_clip_base+63<bank_batch_base and bank_batch_base+63<io_header and
       io_header+io_header_size-1<0x10000,"scratch regions disjoint")
 bank_revision=37
 bank_dirty=true
 local saved_crc=bank_checksum(bank_audio_base)
 check(context_label("save")=="save browser slot" and
       context_label("load")=="load browser slot","lossless slot labels enabled")

 io_begin_frame(io_request_load,1,0,0,io_envelope_size,0,0)
 io_finish_frame()
 check(io_get16(io_gpio+14)==0x4bca,"gpio crc matches browser vector")

 check(bank_profile_apply(),"save test profile applies")
 playing=true
 undo_owner="song"
 check(save_song(),"save starts")
 check(not playing and not bank_profile_is_active(),"save stops and restores authored bytes")
 check(io_mode=="save" and io_frame_valid(io_page_save),"save first frame")
 check(io_get16(io_gpio+10)==io_envelope_size,"save total length")
 io_begin_frame(io_error,io_id,io_sequence,io_offset,io_envelope_size,0,9)
 io_finish_frame()
 project_io_update()
 check(io_mode=="idle" and undo_owner=="song","failed save preserves history")
 check(clipboard_intact(),"failed save preserves clipboard")
 check(waveform_intact(),"failed save preserves waveform")
 check(save_song(),"save retry starts")
 local pages=0
 while io_mode=="save" and pages<50 do
  local sequence=peek(io_gpio+7)
  local offset=io_get16(io_gpio+8)
  local length=peek(io_gpio+12)
  check(io_frame_valid(io_page_save),"save page crc "..pages)
  for i=0,length-1 do
   check(peek(io_gpio+16+i)==io_envelope_byte(offset+i),"save payload "..offset+i)
  end
  io_begin_frame(io_ack,io_id,sequence,offset,io_envelope_size,0,0)
  io_finish_frame()
  project_io_update()
  pages+=1
 end
 check(pages==42 and io_mode=="idle","save sends 42 acknowledged pages")
 check(not bank_dirty and notice=="browser slot saved","save read-back ack gates success")
 check(undo_owner==nil,"successful save clears history")
 check(io_get16(io_header+8)==saved_crc,"save header pins authored bank checksum")
 check(clipboard_intact(),"successful save preserves clipboard")
 check(waveform_intact(),"successful save preserves waveform")

 -- Preserve the saved bank as a fake browser peer, then mutate the live bank.
 memcpy(bank_snapshot_base,bank_audio_base,bank_size)
 local saved_first=peek(bank_snapshot_base)
 poke(bank_audio_base,saved_first^^0x55)
 local mutated_crc=bank_checksum(bank_audio_base)

 undo_owner="sfx"
 check(not load_song(false) and undo_owner=="sfx","cancelled load preserves history")
 check(load_song(),"load request starts")
 emit_saved_page(0,0,true)
 check(io_mode=="idle" and io_frame_valid(io_error),"corrupt gpio frame rejected")
 check(bank_checksum(bank_audio_base)==mutated_crc,"corrupt frame preserves live bank")
 check(undo_owner=="sfx","failed load preserves history")
 check(clipboard_intact(),"failed load preserves clipboard")
 check(waveform_intact(),"failed load preserves waveform")

 check(load_song(),"partial load starts")
 local first_length=emit_saved_page(0,0,false)
 check(io_mode=="load" and io_frame_valid(io_ack),"partial first page staged")
 local partial_offset=io_offset
 emit_saved_page(0,0,false)
 check(io_mode=="load" and io_frame_valid(io_ack) and io_offset==partial_offset,
       "duplicate load page acknowledged without reapply")
 check(bank_checksum(bank_audio_base)==mutated_crc,"partial page preserves live bank")
 io_wait=600
 project_io_update()
 check(io_mode=="idle" and io_frame_valid(io_error),"partial transfer times out")
 check(bank_checksum(bank_audio_base)==mutated_crc,"partial timeout preserves live bank")

 check(load_song(),"out-of-order load starts")
 emit_saved_page(1,first_length,false)
 check(io_mode=="idle" and io_frame_valid(io_error),"out-of-order page rejected")
 check(bank_checksum(bank_audio_base)==mutated_crc,"out-of-order page preserves live bank")

 check(bank_copy(bank_stage_base,bank_snapshot_base),"profile mutation stage copy")
 poke(io_header+56,1)
 refresh_saved_envelope_crc()
 check(load_song(),"profile mutation load starts")
 io_load_complete=true
 io_begin_frame(io_commit_load,io_id,0,0,io_envelope_size,0,0)
 io_finish_frame()
 project_io_update()
 check(io_mode=="idle" and io_frame_valid(io_error),
       "checksum-valid unknown source selection rejected")
 check(bank_checksum(bank_audio_base)==mutated_crc,
       "profile mutation preserves live bank")
 poke(io_header+56,0)
 refresh_saved_envelope_crc()

 check(load_song(),"valid load starts")
 local offset=0
 local sequence=0
 local load_pages=0
 while offset<io_envelope_size do
  local length=emit_saved_page(sequence,offset,false)
  check(io_frame_valid(io_ack),"load page ack "..load_pages)
  offset+=length
  sequence=(sequence+1)%256
  load_pages+=1
 end
 check(load_pages==42 and io_load_complete,"complete load staged")
 io_begin_frame(io_commit_load,io_id,sequence,offset,io_envelope_size,0,0)
 io_finish_frame()
 project_io_update()
 check(io_mode=="idle" and io_frame_valid(io_done),"valid load commits")
 check(bank_checksum(bank_audio_base)==saved_crc and peek(bank_audio_base)==saved_first,
       "valid load restores exact authored bank")
 check(bank_revision==37 and not bank_dirty and not bank_snapshot_valid,
       "valid load restores metadata and clean state")
 check(undo_owner==nil,"successful load clears history")
 check(clipboard_intact(),"successful load preserves clipboard")
 check(waveform_intact(),"successful load restores waveform")

 if failures==0 then printh("pocket tracker project io: passed")
 else printh("pocket tracker project io: failed "..failures) end
 extcmd("shutdown")
end
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
