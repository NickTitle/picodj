-- browser last-known-good project bridge

io_gpio,io_header,io_header_size=0x5f80,0xa5c4,64
io_envelope_size,io_payload_size=io_header_size+bank_size,112
io_project_name="strfld track 1"
io_project_source="e7e97ab track 1"

io_page_save,io_ack,io_page_load,io_commit_load=1,2,3,4
io_done,io_error,io_request_load=5,6,7
native_cart="pocket-tracker-data.p8"
native_base,native_record,native_total=0xa604,0x1248,0x2490
native_sentinel=0xa55a

function io_frame_crc()
 local crc=0xffff
 for i=0,13 do crc=crc_byte(crc,peek(io_gpio+i)) end
 for i=0,peek(io_gpio+12)-1 do crc=crc_byte(crc,peek(io_gpio+16+i)) end
 return crc
end

function io_put16(addr,value)
 poke(addr,value&0xff) poke(addr+1,(value>>8)&0xff)
end

function io_get16(addr)
 return peek(addr)|(peek(addr+1)<<8)
end

function io_put_text(offset,text,limit)
 local length=min(#text,limit)
 poke(io_header+offset,length)
 for i=1,length do poke(io_header+offset+i,ord(text,i)) end
end

function io_get_text(o)
 local s=""
 for i=1,peek(io_header+o) do s..=chr(peek(io_header+o+i)) end
 return s
end

function io_envelope_crc(base)
 local crc=0xffff
 for i=0,io_header_size-1 do crc=crc_byte(crc,peek(io_header+i)) end
 for i=0,bank_size-1 do crc=crc_byte(crc,peek(base+i)) end
 return crc
end

function io_prepare_envelope()
 if bank_profile_is_active() then return false end
 memset(io_header,0,io_header_size)
 poke2(io_header,0x5450) poke2(io_header+2,0x3250)
 poke2(io_header+4,io_header_size*256+2)
 io_put16(io_header+6,io_envelope_size)
 local bank_crc=bank_checksum(bank_audio_base)
 if bank_crc==nil then return false end
 io_put16(io_header+8,bank_crc)
 io_put16(io_header+12,min(0x7fff,max(0,bank_revision)))
 local profile=bank_profile_kind
 poke2(io_header+14,profile*257)
 io_put_text(16,io_project_name,15)
 io_put_text(32,io_project_source,23)
 poke(io_header+57,profile) poke(io_header+58,profile*4)
 io_put16(io_header+10,io_envelope_crc(bank_audio_base))
 return true
end

function io_envelope_byte(offset)
 if offset<io_header_size then return peek(io_header+offset) end
 return peek(bank_audio_base+offset-io_header_size)
end

function native_crc(base)
 local crc=0xffff
 for i=0,native_record-1 do
  if i<6 or i>7 then crc=crc_byte(crc,peek(base+i)) end
 end
 return crc
end

function native_stage(slot)
 local base=native_base+slot*native_record
 if peek2(base)!=0x5450 or peek2(base+2)!=0x314a then return false end
 if native_crc(base)!=io_get16(base+6) then return false end
 memcpy(io_header,base+8,io_header_size)
 memcpy(bank_stage_base,base+8+io_header_size,bank_size)
 return io_envelope_valid() and io_get16(base+4)
end

function native_scan()
 memset(native_base,0xcc,native_total)
 poke2(native_base,native_sentinel)
 poke2(native_base+native_record,native_sentinel)
 reload(native_base,0,native_total,native_cart)
 if peek2(native_base)==native_sentinel and
    peek2(native_base+native_record)==native_sentinel then return end
 local a,b=native_stage(0),native_stage(1)
 local delta=a and b and ((b-a)&0xffff)
 if b and (not a or delta>0) then return 1,b end
 if a then return 0,a end
 return -1,0
end

function native_save()
 if io_mode!="idle" then return io_fail("project i/o busy") end
 io_stop_authored()
 local slot,generation=native_scan()
 if not slot then return io_fail("data cart missing/cancelled") end
 local target=slot<0 and 0 or 1-slot
 generation=(generation+1)&0xffff
 if not io_prepare_envelope() then return io_fail("data cart prepare failed") end
 local base=native_base+target*native_record
 poke2(base,0x5450) poke2(base+2,0x314a) io_put16(base+4,generation)
 memcpy(base+8,io_header,io_header_size)
 memcpy(base+8+io_header_size,bank_audio_base,bank_size)
 io_put16(base+6,native_crc(base))
 local expected=native_base+(1-target)*native_record+8
 memcpy(expected,base+8,io_envelope_size)
 cstore(target*native_record,base,native_record,native_cart)
 memset(base,0xcc,native_record)
 poke2(base,native_sentinel)
 reload(base,target*native_record,native_record,native_cart)
 if peek2(base)==native_sentinel then return io_fail("data cart write cancelled") end
 if native_stage(target)!=generation then return io_fail("data cart read-back failed") end
 for i=0,io_envelope_size-1 do
  if peek(base+8+i)!=peek(expected+i) then return io_fail("data cart read-back failed") end
 end
 bank_mark_clean() undo_owner=nil song_error=nil return true
end

function native_load()
 if io_mode!="idle" then return io_fail("project i/o busy") end
 io_stop_authored()
 local slot=native_scan()
 if not slot then return io_fail("data cart missing/cancelled") end
 if slot<0 then return io_fail("data cart invalid") end
 native_stage(slot)
 if not io_commit_stage() then return io_fail("data cart commit failed") end
 song_error=nil return true
end

function io_begin_frame(command,id,sequence,offset,total,length,flags)
 memset(io_gpio,0,128)
 poke2(io_gpio,0x5450) poke2(io_gpio+2,0x324b)
 poke(io_gpio+4,1) poke(io_gpio+5,command) poke(io_gpio+6,id) poke(io_gpio+7,sequence)
 io_put16(io_gpio+8,offset) io_put16(io_gpio+10,total)
 poke(io_gpio+12,length) poke(io_gpio+13,flags)
end

function io_finish_frame()
 io_put16(io_gpio+14,io_frame_crc())
end

function io_emit_save_page()
 local length=min(io_payload_size,io_envelope_size-io_offset)
 local flags=(io_offset==0 and 1 or 0)|
  (io_offset+length==io_envelope_size and 2 or 0)|4
 io_begin_frame(io_page_save,io_id,io_sequence,io_offset,io_envelope_size,length,flags)
 for i=0,length-1 do poke(io_gpio+16+i,io_envelope_byte(io_offset+i)) end
 io_finish_frame()
 io_page_length=length
 io_page_last=(flags&2)!=0
end

function io_emit_control(command,flags)
 io_begin_frame(command,io_id,io_sequence,io_offset,io_envelope_size,0,flags or 0)
 io_finish_frame()
end

function io_frame_valid(command)
 if peek2(io_gpio)!=0x5450 or peek2(io_gpio+2)!=0x324b or peek(io_gpio+4)!=1 or
    peek(io_gpio+5)!=command or peek(io_gpio+12)>io_payload_size then return false end
 return io_get16(io_gpio+14)==io_frame_crc()
end

function io_fail(text,code)
 if code then io_mode="idle" io_emit_control(io_error,code) end
 song_error=text
 return false
end

function io_stop_authored()
 if audition_active then stop_audition(false) end
 if playing or bank_profile_is_active() then stop_song() end
end

function save_song()
 if io_mode!="idle" then io_fail("project i/o busy",2) return false end
 io_stop_authored()
 if not io_prepare_envelope() then io_fail("save prepare failed",3) return false end
 io_id,io_sequence,io_offset,io_mode=(io_id+1)%256,0,0,"save"
 io_wait=0
 io_emit_save_page()
 song_error=nil
 return true
end

function load_song()
 if io_mode!="idle" then io_fail("project i/o busy",2) return false end
 io_stop_authored()
 io_id,io_sequence,io_offset=(io_id+1)%256,0,0
 io_load_last_sequence,io_load_last_offset,io_load_last_crc=-1,-1,-1
 io_load_complete,io_mode,io_wait=false,"load",0
 io_emit_control(io_request_load,0)
 song_error=nil
 return true
end

function io_ack_load(sequence,offset)
 io_begin_frame(io_ack,io_id,sequence,offset,io_envelope_size,0,0)
 io_finish_frame()
end

function io_accept_load_page()
 if not io_frame_valid(io_page_load) or peek(io_gpio+6)!=io_id then
  io_fail("load frame corrupt",4) return
 end
 local sequence=peek(io_gpio+7)
 local offset=io_get16(io_gpio+8)
 local total=io_get16(io_gpio+10)
 local length=peek(io_gpio+12)
 local flags=peek(io_gpio+13)
 if total!=io_envelope_size or offset+length>total then
  io_fail("load length invalid",5) return
 end
 if sequence==io_load_last_sequence and offset==io_load_last_offset and
    io_get16(io_gpio+14)==io_load_last_crc then
  io_ack_load(sequence,offset) return
 end
 if sequence!=io_sequence or offset!=io_offset then
  io_fail("load page out of order",6) return
 end
 for i=0,length-1 do
  local destination=offset+i
  if destination<io_header_size then poke(io_header+destination,peek(io_gpio+16+i))
  else poke(bank_stage_base+destination-io_header_size,peek(io_gpio+16+i)) end
 end
 io_load_last_sequence=sequence io_load_last_offset=offset
 io_load_last_crc=io_get16(io_gpio+14)
 io_offset+=length
 io_sequence=(io_sequence+1)%256
 io_wait=0
 if (flags&2)!=0 then io_load_complete=io_offset==io_envelope_size end
 io_ack_load(sequence,offset)
end

function io_envelope_valid()
 local profile=peek(io_header+14)
 if peek2(io_header)!=0x5450 or peek2(io_header+2)!=0x3250 or peek(io_header+4)!=2 or
    peek(io_header+5)!=io_header_size or io_get16(io_header+6)!=io_envelope_size or
    profile>1 or peek(io_header+15)!=profile or
    peek(io_header+16)>15 or peek(io_header+32)>23 or
    peek(io_header+56)!=0 then return false end
 for i=57,63 do
  if peek(io_header+i)!=(i==57 and profile or i==58 and profile*4 or 0) then return false end
 end
 local expected_bank=io_get16(io_header+8)
 if (bank_checksum(bank_stage_base)&0xffff)!=(expected_bank&0xffff) then return false end
 local expected=io_get16(io_header+10)
 poke(io_header+10,0) poke(io_header+11,0)
 local crc=io_envelope_crc(bank_stage_base)
 io_put16(io_header+10,expected)
 return (crc&0xffff)==(expected&0xffff)
end

function io_commit_stage()
 if not bank_stage_commit(io_get16(io_header+8)) then return false end
 bank_profile_kind=peek(io_header+14)
 io_project_name=io_get_text(16) io_project_source=io_get_text(32)
 song_pattern=peek(io_header+56) bank_revision=io_get16(io_header+12)
 bank_dirty=false undo_owner=nil
 return true
end

function io_commit_loaded()
 if not io_load_complete or not io_envelope_valid() then
  io_fail("load checksum failed",7) return
 end
 if not io_commit_stage() then io_fail("load commit failed",8) return end
 io_mode="idle"
 io_emit_control(io_done,0)
 song_error=nil
end

function project_io_update()
 if io_mode!="idle" then
  io_wait+=1
  if io_wait>600 then io_fail("project transfer timeout",10) return end
 end
 if io_mode=="save" then
  if io_frame_valid(io_error) and peek(io_gpio+6)==io_id then
   io_fail("browser save failed",peek(io_gpio+13))
  elseif io_frame_valid(io_ack) and peek(io_gpio+6)==io_id and
         peek(io_gpio+7)==io_sequence and io_get16(io_gpio+8)==io_offset then
   if io_page_last then
    bank_mark_clean() undo_owner=nil io_mode="idle" io_emit_control(io_done,0)
    song_error=nil
   else
    io_offset+=io_page_length io_sequence=(io_sequence+1)%256
    io_wait=0
    io_emit_save_page()
   end
  end
 elseif io_mode=="load" then
  if peek(io_gpio+5)==io_error and peek(io_gpio+6)==io_id and io_frame_valid(io_error) then
   io_fail("browser slot unavailable",peek(io_gpio+13))
  elseif peek(io_gpio+5)==io_page_load then io_accept_load_page()
  elseif peek(io_gpio+5)==io_commit_load and io_frame_valid(io_commit_load) and
         peek(io_gpio+6)==io_id then io_commit_loaded() end
 end
end

project_legacy_init=_init
function _init()
 project_legacy_init()
 io_id,io_sequence,io_offset,io_wait,io_mode=0,0,0,0,"idle"
end

project_legacy_update60=_update60
function _update60()
 project_io_update()
 if io_mode!="idle" then return end
 project_legacy_update60()
end
