-- browser last-known-good project bridge

io_gpio,io_header,io_header_size=0x5f80,0xa544,64
io_envelope_size,io_payload_size=io_header_size+bank_size,112
io_project_name="strfld track 1"
io_project_source="e7e97ab track 1"

io_page_save,io_ack,io_page_load,io_commit_load=1,2,3,4
io_done,io_error,io_request_load=5,6,7

function io_crc_byte(crc,value)
 crc=(crc^^(value<<8))&0xffff
 for bit=1,8 do
  crc=(crc&0x8000)!=0 and ((crc<<1)^^0x1021)&0xffff or (crc<<1)&0xffff
 end
 return crc
end

function io_frame_crc()
 local crc=0xffff
 for i=0,13 do crc=io_crc_byte(crc,peek(io_gpio+i)) end
 for i=0,peek(io_gpio+12)-1 do crc=io_crc_byte(crc,peek(io_gpio+16+i)) end
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

function io_prepare_envelope()
 if bank_profile_is_active() then return false end
 memset(io_header,0,io_header_size)
 poke(io_header,80) poke(io_header+1,84) poke(io_header+2,80) poke(io_header+3,50)
 poke(io_header+4,2) poke(io_header+5,io_header_size)
 io_put16(io_header+6,io_envelope_size)
 local bank_crc=bank_checksum(bank_audio_base)
 if bank_crc==nil then return false end
 io_put16(io_header+8,bank_crc)
 io_put16(io_header+12,min(0x7fff,max(0,bank_revision)))
 poke(io_header+14,1) poke(io_header+15,1)
 io_put_text(16,io_project_name,15)
 io_put_text(32,io_project_source,23)
 poke(io_header+56,0) poke(io_header+57,1) poke(io_header+58,4)
 local crc=0xffff
 for i=0,io_header_size-1 do crc=io_crc_byte(crc,peek(io_header+i)) end
 for i=0,bank_size-1 do crc=io_crc_byte(crc,peek(bank_audio_base+i)) end
 io_put16(io_header+10,crc)
 return true
end

function io_envelope_byte(offset)
 if offset<io_header_size then return peek(io_header+offset) end
 return peek(bank_audio_base+offset-io_header_size)
end

function io_begin_frame(command,id,sequence,offset,total,length,flags)
 memset(io_gpio,0,128)
 poke(io_gpio,80) poke(io_gpio+1,84) poke(io_gpio+2,75) poke(io_gpio+3,50)
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
 if peek(io_gpio)!=80 or peek(io_gpio+1)!=84 or peek(io_gpio+2)!=75 or
    peek(io_gpio+3)!=50 or peek(io_gpio+4)!=1 or
    peek(io_gpio+5)!=command or peek(io_gpio+12)>io_payload_size then return false end
 return io_get16(io_gpio+14)==io_frame_crc()
end

function io_fail(text,code)
 io_mode="idle"
 io_emit_control(io_error,code or 1)
 song_error=text
 say(text)
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
 say("saving browser slot")
 return true
end

function load_song(show_notice)
 if show_notice==false then return false end
 if io_mode!="idle" then io_fail("project i/o busy",2) return false end
 io_stop_authored()
 io_id,io_sequence,io_offset=(io_id+1)%256,0,0
 io_load_last_sequence,io_load_last_offset,io_load_last_crc=-1,-1,-1
 io_load_complete,io_mode,io_wait=false,"load",0
 io_emit_control(io_request_load,0)
 song_error=nil
 say("loading browser slot")
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
 if peek(io_header)!=80 or peek(io_header+1)!=84 or peek(io_header+2)!=80 or
    peek(io_header+3)!=50 or peek(io_header+4)!=2 or
    peek(io_header+5)!=io_header_size or io_get16(io_header+6)!=io_envelope_size or
    peek(io_header+14)!=1 or peek(io_header+15)!=1 or
    peek(io_header+16)>15 or peek(io_header+32)>23 or
    peek(io_header+56)!=0 or peek(io_header+57)!=1 or peek(io_header+58)!=4 or
    peek(io_header+59)!=0 or peek(io_header+60)!=0 or peek(io_header+61)!=0 or
    peek(io_header+62)!=0 or peek(io_header+63)!=0 then return false end
 local expected_bank=io_get16(io_header+8)
 if (bank_checksum(bank_stage_base)&0xffff)!=(expected_bank&0xffff) then return false end
 local expected=io_get16(io_header+10)
 poke(io_header+10,0) poke(io_header+11,0)
 local crc=0xffff
 for i=0,io_header_size-1 do crc=io_crc_byte(crc,peek(io_header+i)) end
 for i=0,bank_size-1 do crc=io_crc_byte(crc,peek(bank_stage_base+i)) end
 io_put16(io_header+10,expected)
 return (crc&0xffff)==(expected&0xffff)
end

function io_commit_loaded()
 if not io_load_complete or not io_envelope_valid() then
  io_fail("load checksum failed",7) return
 end
 local expected=io_get16(io_header+8)
 if not bank_stage_commit(expected) then io_fail("load commit failed",8) return end
 bank_revision=io_get16(io_header+12)
 bank_dirty=false bank_snapshot_valid=false
 undo_owner=nil
 io_mode="idle"
 io_emit_control(io_done,0)
 song_error=nil
 say("browser slot loaded")
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
    bank_mark_clean() io_mode="idle" io_emit_control(io_done,0)
    song_error=nil say("browser slot saved")
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

project_legacy_context_label=context_label
function context_label(name)
 if name=="save" then return "save browser slot" end
 if name=="load" then return "load browser slot" end
 return project_legacy_context_label(name)
end
