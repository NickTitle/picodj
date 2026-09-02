pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
#include ../audio_bank.lua

playing=false
audition_active=false
undo_owner=nil
undo_width,undo_dirty,undo_addr=-7,false,0x3199
song_error=nil

function _init() end
function _update60() end
function context_label(name) return name end
function stop_audition() audition_active=false return true end
function stop_song() bank_profile_restore() playing=false return true end

#include ../project_io.lua

failures=0
test_saved_base,test_live_base=0x9200,0xca94

function test_crc_byte(crc,value)
 crc=(crc^^(value<<8))&0xffff
 for bit=1,8 do
  crc=(crc&0x8000)!=0 and ((crc<<1)^^0x1021)&0xffff or (crc<<1)&0xffff
 end
 return crc
end

function test_crc(values)
 local crc=0xffff
 for i=1,#values do crc=test_crc_byte(crc,values[i]) end
 return crc
end

function test_crc_range(crc,base,size,skip_start,skip_end)
 for i=0,size-1 do
  if not skip_start or i<skip_start or i>=skip_end then
   crc=test_crc_byte(crc,peek(base+i))
  end
 end
 return crc
end

function capture_live()
 memcpy(test_live_base,bank_audio_base,bank_size)
 test_live_profile,test_live_profile_active=bank_profile_kind,bank_profile_active
 test_live_dirty,test_live_revision=bank_dirty,bank_revision
 test_live_owner,test_live_width,test_live_undo_dirty,test_live_addr=
  undo_owner,undo_width,undo_dirty,undo_addr
 test_live_name,test_live_source=io_project_name,io_project_source
 test_live_pattern=song_pattern
 test_live_playing,test_live_audition=playing,audition_active
end

function live_intact()
 for i=0,bank_size-1 do
  if peek(bank_audio_base+i)!=peek(test_live_base+i) then return false end
 end
 return bank_profile_kind==test_live_profile and
  bank_profile_active==test_live_profile_active and
  bank_dirty==test_live_dirty and bank_revision==test_live_revision and
  undo_owner==test_live_owner and undo_width==test_live_width and
  undo_dirty==test_live_undo_dirty and undo_addr==test_live_addr and
  io_project_name==test_live_name and io_project_source==test_live_source and
  song_pattern==test_live_pattern and playing==test_live_playing and
  audition_active==test_live_audition
end

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
 for sfx in all({0,1,4}) do
  if not bank_sfx_is_waveform(sfx) then return false end
  for i=0,63 do
   if peek(bank_sfx_addr(sfx,i))!=(i*29+7)&0xff then return false end
  end
  if bank_sfx_meta_raw(sfx,0)!=0xd0 or bank_sfx_filter(sfx,3)!=2 or
   bank_sfx_filter(sfx,4)!=2 or bank_sfx_filter(sfx,5)!=2 then return false end
  if bank_sfx_meta_raw(sfx,1)!=0xa5 then return false end
  if (bank_sfx_meta_raw(sfx,2)&0x80)==0 then return false end
 end
 return (peek2(bank_sfx_addr(8,0))&0xffff)==0x8a58
end

function saved_byte(offset)
 if offset<io_header_size then return peek(io_header+offset) end
 return peek(test_saved_base+offset-io_header_size)
end

function prepared_byte(offset)
 if offset<io_header_size then return peek(io_header+offset) end
 return peek(bank_audio_base+offset-io_header_size)
end

function refresh_saved_envelope_crc()
 io_put16(io_header+10,0)
 local crc=0xffff
 for i=0,io_header_size-1 do crc=test_crc_byte(crc,peek(io_header+i)) end
 for i=0,bank_size-1 do crc=test_crc_byte(crc,peek(test_saved_base+i)) end
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
 local empty_crc=test_crc({})
 check(empty_crc==-1 and (empty_crc&0xffff)==0xffff,
  "empty crc signed and unsigned presentation")
 check(test_crc({0})==-7696 and (test_crc({0})&0xffff)==0xe1f0,
  "zero-byte crc vector")
 check(test_crc({0x80})==0x7078,"high-bit crc vector")
 check(test_crc({0xff})==-256 and (test_crc({0xff})&0xffff)==0xff00,
  "all-bits crc signed and unsigned presentation")
 check((test_crc({0,0,0,0})&0xffff)==0x84c0,
  "multi-zero crc vector")
 check(test_crc({49,50,51,52,53,54,55,56,57})==0x29b1,
  "representative crc vector")

 -- This exact PTP2 fixture is shared with the JavaScript regression vector.
 for i=0,bank_size-1 do poke(bank_stage_base+i,((i+64)*37+11)&0xff) end
 memset(io_header,0,io_header_size)
 poke2(io_header,0x5450) poke2(io_header+2,0x3250)
 poke2(io_header+4,io_header_size*256+2)
 io_put16(io_header+6,io_envelope_size) io_put16(io_header+12,37)
 poke2(io_header+14,0x0101)
 io_put_text(16,"strfld track 1",15) io_put_text(32,"e7e97ab track 1",23)
 poke(io_header+57,1) poke(io_header+58,4)
 local fixture_bank_crc=bank_checksum(bank_stage_base)
 local reference_bank_crc=test_crc_range(0xffff,bank_stage_base,bank_size)
 check((fixture_bank_crc&0xffff)==0xbc23 and
  (reference_bank_crc&0xffff)==0xbc23,"cross-runtime bank crc vector")
 io_put16(io_header+8,fixture_bank_crc) io_put16(io_header+10,0)
 local fixture_envelope_crc=io_envelope_crc(bank_stage_base)
 local reference_envelope_crc=test_crc_range(0xffff,io_header,io_header_size)
 reference_envelope_crc=test_crc_range(reference_envelope_crc,
  bank_stage_base,bank_size)
 check((fixture_envelope_crc&0xffff)==0xa683 and
  (reference_envelope_crc&0xffff)==0xa683,"cross-runtime envelope crc vector")
 io_put16(io_header+10,fixture_envelope_crc)
 memset(native_base,0,native_record)
 poke2(native_base,0x5450) poke2(native_base+2,0x314a) io_put16(native_base+4,37)
 memcpy(native_base+8,io_header,io_header_size)
 memcpy(native_base+8+io_header_size,bank_stage_base,bank_size)
 local reference_native_crc=test_crc_range(0xffff,native_base,native_record,6,8)
 check((native_crc(native_base)&0xffff)==0x2b65 and
  (reference_native_crc&0xffff)==0x2b65,"cross-runtime native record crc vector")

 for i=0,63 do poke(bank_sfx_addr(0,i),(i*29+7)&0xff) end
 poke(bank_sfx_addr(0,64),0xd0)
 poke(bank_sfx_addr(0,65),0xa5)
 poke(bank_sfx_addr(0,66),peek(bank_sfx_addr(0,66))|0x80)
 for sfx in all({1,4}) do
  memcpy(bank_sfx_addr(sfx,0),bank_sfx_addr(0,0),bank_sfx_size)
 end
 poke2(bank_sfx_addr(8,0),0x8a58)
 -- Distinct sentinels pin header/bank, page, and final partial-page boundaries.
 poke(bank_audio_base,0x91)
 poke(bank_audio_base+47,0x2f) poke(bank_audio_base+48,0x30)
 poke(bank_audio_base+bank_size-80,0xa0)
 poke(bank_audio_base+bank_size-1,0xfe)
 sfx_clip_count=17
 for i=0,63 do poke(bank_clip_base+i,(i*37+11)&0xff) end
 check(bank_clip_base+63<bank_batch_base and bank_batch_base+63<io_header and
       io_header+io_header_size-1<0x10000,"scratch regions disjoint")
 bank_revision=37
 bank_dirty=true
 local saved_crc=bank_checksum(bank_audio_base)
 io_begin_frame(io_request_load,1,0,0,io_envelope_size,0,0)
 io_finish_frame()
 local reference_frame_crc=test_crc_range(0xffff,io_gpio,14)
 check(io_get16(io_gpio+14)==0x4bca and
  (reference_frame_crc&0xffff)==0x4bca,"cross-runtime gpio frame crc vector")

 check(bank_profile_apply(),"save test profile applies")
 playing=true
 undo_owner="song" undo_width=-9 undo_dirty=false undo_addr=0x31a7
 check(save_song(),"save starts")
 check(not playing and not bank_profile_active and
  bank_checksum(bank_audio_base)==saved_crc,
  "save stops profile and restores exact authored bytes")
 check(io_mode=="save" and io_frame_valid(io_page_save),"save first frame")
 check(io_get16(io_gpio+10)==io_envelope_size,"save total length")
 capture_live()
 io_begin_frame(io_error,io_id,io_sequence,io_offset,io_envelope_size,0,9)
 io_finish_frame()
 project_io_update()
 check(io_mode=="idle" and undo_owner=="song" and
  song_error=="browser save failed","failed save is visible and preserves history")
 check(live_intact(),"failed save preserves exact live project and redo state")
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
   check(peek(io_gpio+16+i)==prepared_byte(offset+i),"save payload "..offset+i)
  end
  if offset==0 then
   check(length==112 and peek(io_gpio+16)==0x50 and
    peek(io_gpio+16+63)==0 and peek(io_gpio+16+64)==0x91 and
    peek(io_gpio+16+111)==0x2f,"save first/header/page-boundary byte vector")
  elseif offset==112 then
   check(length==112 and peek(io_gpio+16)==0x30,
    "save page-boundary continuation byte vector")
  elseif offset+length==io_envelope_size then
   check(offset==4592 and length==80 and peek(io_gpio+16)==0xa0 and
    peek(io_gpio+16+length-1)==0xfe,"save final partial-envelope byte vector")
   check(bank_dirty and undo_owner=="song" and undo_width==-9 and
    not undo_dirty and undo_addr==0x31a7,
    "save stays dirty with history until final acknowledgement")
  end
  io_begin_frame(io_ack,io_id,sequence,offset,io_envelope_size,0,0)
  io_finish_frame()
  project_io_update()
  pages+=1
 end
 check(pages==42 and io_mode=="idle","save sends 42 acknowledged pages")
 check(not bank_dirty and io_frame_valid(io_done) and song_error==nil,
  "save read-back ack gates visible success state")
 check(undo_owner==nil and undo_width==-9 and not undo_dirty and
  undo_addr==0x31a7,"successful save establishes exact clean history baseline")
 check(io_get16(io_header+8)==saved_crc,"save header pins authored bank checksum")
 check(peek(io_header+14)==1 and peek(io_header+15)==1 and
  peek(io_header+57)==1 and peek(io_header+58)==4,"save preserves track-1 tuple")
 check(clipboard_intact(),"successful save preserves clipboard")
 check(waveform_intact(),"successful save preserves waveform")

 -- Preserve the saved bank as a fake browser peer, then mutate the live bank.
 memcpy(test_saved_base,bank_audio_base,bank_size)
 local saved_first=peek(test_saved_base)
 poke(bank_audio_base,saved_first^^0x55)
 bank_profile_kind=1 bank_dirty=true bank_revision=44
 io_project_name="live name" io_project_source="live source" song_pattern=23
 undo_owner="sfx" undo_width=-11 undo_dirty=false undo_addr=0x42f8
 local mutated_crc=bank_checksum(bank_audio_base)

 check(load_song(),"load request starts")
 capture_live()
 emit_saved_page(0,0,true)
 check(io_mode=="idle" and io_frame_valid(io_error) and
  song_error=="load frame corrupt","corrupt gpio frame rejected visibly")
 check(bank_checksum(bank_audio_base)==mutated_crc,"corrupt frame preserves live bank")
 check(live_intact(),"corrupt frame preserves exact live project and redo state")
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
 check(live_intact(),"partial page preserves exact live project and redo state")
 io_wait=600
 project_io_update()
 check(io_mode=="idle" and io_frame_valid(io_error) and
  song_error=="project transfer timeout","partial transfer times out visibly")
 check(bank_checksum(bank_audio_base)==mutated_crc,"partial timeout preserves live bank")
 check(live_intact(),"partial timeout preserves exact live project and redo state")

 check(load_song(),"out-of-order load starts")
 emit_saved_page(1,first_length,false)
 check(io_mode=="idle" and io_frame_valid(io_error) and
  song_error=="load page out of order","out-of-order page rejected visibly")
 check(bank_checksum(bank_audio_base)==mutated_crc,"out-of-order page preserves live bank")
 check(live_intact(),"out-of-order page preserves exact live project and redo state")

 check(load_song(),"unavailable browser slot load starts")
 io_begin_frame(io_error,io_id,0,0,io_envelope_size,0,9)
 io_finish_frame()
 project_io_update()
 check(io_mode=="idle" and io_frame_valid(io_error) and
  song_error=="browser slot unavailable","unavailable browser slot rejected visibly")
 check(live_intact(),"unavailable browser slot preserves exact live project and redo state")

 memcpy(bank_stage_base,test_saved_base,bank_size)
 for kind in all({0,1,2}) do
  for version in all({0,1,2}) do
   for start in all({0,1,2}) do
    for count in all({0,1,4,5}) do
     poke(io_header+14,kind) poke(io_header+15,version)
     poke(io_header+57,start) poke(io_header+58,count)
     refresh_saved_envelope_crc()
     local valid=kind==0 and version==0 and start==0 and count==0 or
      kind==1 and version==1 and start==1 and count==4
     check(io_envelope_valid()==valid,"profile tuple "..kind..version..start..count)
    end
   end
  end
 end
 poke(io_header+14,1) poke(io_header+15,0)
 poke(io_header+57,1) poke(io_header+58,4)
 refresh_saved_envelope_crc()
 check(load_song(),"profile mutation load starts")
 io_load_complete=true
 io_begin_frame(io_commit_load,io_id,0,0,io_envelope_size,0,0)
 io_finish_frame()
 project_io_update()
 check(io_mode=="idle" and io_frame_valid(io_error) and
       song_error=="load checksum failed",
       "checksum-valid unknown profile tuple rejected")
 check(bank_checksum(bank_audio_base)==mutated_crc,
       "profile mutation preserves live bank")
 check(live_intact(),"profile mutation preserves exact live project and redo state")

 -- The valid staged load commits the complete profile-none metadata atomically.
 poke(io_header+14,0) poke(io_header+15,0)
 poke(io_header+56,0) poke(io_header+57,0) poke(io_header+58,0)
 io_put16(io_header+12,41)
 memset(io_header+16,0,16) memset(io_header+32,0,24)
 io_put_text(16,"raw import",15) io_put_text(32,"browser p8",23)
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
 check(io_mode=="idle" and io_frame_valid(io_done) and song_error==nil,
  "valid load commits visible success state")
 check(bank_checksum(bank_audio_base)==saved_crc and peek(bank_audio_base)==saved_first,
       "valid load restores exact authored bank")
 check(bank_revision==41 and not bank_dirty and not bank_profile_active,
       "valid load restores metadata and clean state")
 check(bank_profile_kind==0 and io_project_name=="raw import" and
  io_project_source=="browser p8" and song_pattern==0,"profile-none metadata committed")
 check(undo_owner==nil and undo_width==-11 and not undo_dirty and
  undo_addr==0x42f8,"successful load establishes exact clean history baseline")
 check(clipboard_intact(),"successful load preserves clipboard")
 check(waveform_intact(),"successful load restores waveform")
 check(io_prepare_envelope() and peek(io_header+14)==0 and peek(io_header+15)==0 and
  peek(io_header+57)==0 and peek(io_header+58)==0,"profile-none save tuple")

 if failures==0 then printh("pocket tracker project io: passed")
 else printh("pocket tracker project io: failed "..failures) end
 extcmd("shutdown")
end
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
