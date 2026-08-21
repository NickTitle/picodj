-- pocket tracker native pico-8 audio bank core

bank_audio_base=0x3100
bank_song_base=0x3100
bank_sfx_base=0x3200
bank_size=0x1200
bank_stage_base=0x8000
bank_snapshot_base=0x9200
bank_profile_base=0xa400

bank_pattern_count=64
bank_channel_count=4
bank_sfx_count=64
bank_row_count=32
bank_sfx_size=68

function bank_int(v,lo,hi)
 return type(v)=="number" and v==flr(v) and v>=lo and v<=hi
end

function bank_byte(v)
 return bank_int(v,0,255)
end

function bank_bool(v)
 return type(v)=="boolean"
end

function bank_region(base)
 return base==bank_audio_base or base==bank_stage_base or base==bank_snapshot_base
end

function bank_touch()
 bank_dirty=true
 bank_revision+=1
end

function bank_project_init()
 if bank_profile_active then bank_profile_restore() end
 bank_dirty=false
 bank_revision=0
 bank_snapshot_valid=false
 bank_snapshot_dirty=false
 bank_profile_active=false
end

function bank_mark_clean()
 bank_dirty=false
end

function bank_song_addr(pattern,channel)
 if not bank_int(pattern,0,bank_pattern_count-1) or
    not bank_int(channel,0,bank_channel_count-1) then return nil end
 return bank_song_base+pattern*4+channel
end

function bank_sfx_addr(sfx,offset)
 if not bank_int(sfx,0,bank_sfx_count-1) or
    not bank_int(offset,0,bank_sfx_size-1) then return nil end
 return bank_sfx_base+sfx*bank_sfx_size+offset
end

function bank_sfx_is_waveform(sfx)
 local addr=bank_sfx_addr(sfx,66)
 if not addr then return nil end
 return sfx<8 and (peek(addr)&0x80)!=0
end

function bank_note_addr(sfx,row)
 if not bank_int(sfx,0,bank_sfx_count-1) or
    not bank_int(row,0,bank_row_count-1) then return nil end
 if sfx<8 and bank_sfx_is_waveform(sfx) then return nil end
 return bank_sfx_base+sfx*bank_sfx_size+row*2
end

function bank_write_byte(addr,value)
 if bank_profile_active or
    not bank_int(addr,bank_audio_base,bank_audio_base+bank_size-1) or
    not bank_byte(value) then return false end
 if peek(addr)==value then return true end
 poke(addr,value)
 bank_touch()
 return true
end

function bank_write_word(addr,value)
 if bank_profile_active or
    not bank_int(addr,bank_sfx_base,bank_audio_base+bank_size-2) or
    type(value)!="number" or value!=flr(value) then return false end
 if (peek2(addr)&0xffff)==(value&0xffff) then return true end
 poke2(addr,value)
 bank_touch()
 return true
end

function bank_song_raw(pattern,channel)
 local addr=bank_song_addr(pattern,channel)
 return addr and peek(addr) or nil
end

function bank_pattern_sfx(pattern,channel)
 local value=bank_song_raw(pattern,channel)
 return value and value&0x3f or nil
end

function bank_set_pattern_sfx(pattern,channel,sfx)
 local addr=bank_song_addr(pattern,channel)
 if not addr or not bank_int(sfx,0,bank_sfx_count-1) then return false end
 return bank_write_byte(addr,(peek(addr)&0xc0)|sfx)
end

function bank_pattern_muted(pattern,channel)
 local value=bank_song_raw(pattern,channel)
 if value==nil then return nil end
 return (value&0x40)!=0
end

function bank_set_pattern_muted(pattern,channel,muted)
 local addr=bank_song_addr(pattern,channel)
 if not addr or not bank_bool(muted) then return false end
 local value=peek(addr)
 value=muted and (value|0x40) or (value&0xbf)
 return bank_write_byte(addr,value)
end

function bank_pattern_flag(pattern,channel)
 if not bank_int(channel,0,2) then return nil end
 local value=bank_song_raw(pattern,channel)
 if value==nil then return nil end
 return (value&0x80)!=0
end

function bank_set_pattern_flag(pattern,channel,enabled)
 if not bank_int(channel,0,2) then return false end
 local addr=bank_song_addr(pattern,channel)
 if not addr or not bank_bool(enabled) then return false end
 local value=peek(addr)
 value=enabled and (value|0x80) or (value&0x7f)
 return bank_write_byte(addr,value)
end

function bank_pattern_loop_start(pattern)
 return bank_pattern_flag(pattern,0)
end

function bank_set_pattern_loop_start(pattern,enabled)
 return bank_set_pattern_flag(pattern,0,enabled)
end

function bank_pattern_loop_back(pattern)
 return bank_pattern_flag(pattern,1)
end

function bank_set_pattern_loop_back(pattern,enabled)
 return bank_set_pattern_flag(pattern,1,enabled)
end

function bank_pattern_stop(pattern)
 return bank_pattern_flag(pattern,2)
end

function bank_set_pattern_stop(pattern,enabled)
 return bank_set_pattern_flag(pattern,2,enabled)
end

function bank_note_raw(sfx,row)
 local addr=bank_note_addr(sfx,row)
 return addr and peek2(addr) or nil
end

function bank_note_authored_raw(sfx,row)
 if not bank_note_addr(sfx,row) then return nil end
 if bank_profile_active and sfx>=1 and sfx<=4 then
  return peek2(bank_profile_base+(sfx-1)*64+row*2)
 end
 return bank_note_raw(sfx,row)
end

function bank_note_pitch(sfx,row)
 local value=bank_note_raw(sfx,row)
 return value and value&0x3f or nil
end

function bank_note_instrument(sfx,row)
 local value=bank_note_raw(sfx,row)
 return value and (value>>6)&7 or nil
end

function bank_note_custom(sfx,row)
 local value=bank_note_raw(sfx,row)
 if value==nil then return nil end
 return (value&0x8000)!=0
end

function bank_note_volume(sfx,row)
 local value=bank_note_raw(sfx,row)
 return value and (value>>9)&7 or nil
end

function bank_note_effect(sfx,row)
 local value=bank_note_raw(sfx,row)
 return value and (value>>12)&7 or nil
end

function bank_set_note_field(sfx,row,value,max_value,shift,keep)
 local addr=bank_note_addr(sfx,row)
 if not addr or not bank_int(value,0,max_value) then return false end
 return bank_write_word(addr,(peek2(addr)&keep)|(value<<shift))
end

function bank_set_note_pitch(sfx,row,value)
 return bank_set_note_field(sfx,row,value,63,0,0xffc0)
end

function bank_set_note_instrument(sfx,row,value)
 return bank_set_note_field(sfx,row,value,7,6,0xfe3f)
end

function bank_set_note_volume(sfx,row,value)
 return bank_set_note_field(sfx,row,value,7,9,0xf1ff)
end

function bank_set_note_effect(sfx,row,value)
 return bank_set_note_field(sfx,row,value,7,12,0x8fff)
end

function bank_set_note_custom(sfx,row,custom)
 local addr=bank_note_addr(sfx,row)
 if not addr or not bank_bool(custom) then return false end
 local value=peek2(addr)
 value=custom and (value|0x8000) or (value&0x7fff)
 return bank_write_word(addr,value)
end

function bank_sfx_meta_raw(sfx,index)
 if not bank_int(index,0,3) then return nil end
 local addr=bank_sfx_addr(sfx,64+index)
 return addr and peek(addr) or nil
end

function bank_set_sfx_meta_raw(sfx,index,value)
 if not bank_int(index,0,3) or not bank_byte(value) then return false end
 local addr=bank_sfx_addr(sfx,64+index)
 if not addr then return false end
 return bank_write_byte(addr,value)
end

function bank_sfx_speed(sfx)
 return bank_sfx_meta_raw(sfx,1)
end

function bank_set_sfx_speed(sfx,value)
 if not bank_int(value,1,255) or bank_sfx_is_waveform(sfx) then return false end
 return bank_set_sfx_meta_raw(sfx,1,value)
end

function bank_sfx_loop_start(sfx)
 local value=bank_sfx_meta_raw(sfx,2)
 return value and value&0x1f or nil
end

function bank_set_sfx_loop_start(sfx,value)
 if not bank_int(value,0,31) or bank_sfx_is_waveform(sfx) then return false end
 local raw=bank_sfx_meta_raw(sfx,2)
 if raw==nil then return false end
 return bank_set_sfx_meta_raw(sfx,2,(raw&0xe0)|value)
end

function bank_sfx_loop_end(sfx)
 local value=bank_sfx_meta_raw(sfx,3)
 return value and value&0x1f or nil
end

function bank_set_sfx_loop_end(sfx,value)
 if not bank_int(value,0,31) or bank_sfx_is_waveform(sfx) then return false end
 local raw=bank_sfx_meta_raw(sfx,3)
 if raw==nil then return false end
 return bank_set_sfx_meta_raw(sfx,3,(raw&0xe0)|value)
end

function bank_equal(a,b)
 if not bank_region(a) or not bank_region(b) then return false end
 if a==b then return true end
 for i=0,bank_size-1 do
  if peek(a+i)!=peek(b+i) then return false end
 end
 return true
end

-- crc-16/ccitt-false: poly 0x1021, init 0xffff, no reflection/xorout.
-- the result is a signed pico-8 16-bit bit pattern; mask with 0xffff when
-- presenting it outside the vm.
function bank_checksum(base)
 if not bank_region(base) then return nil end
 if base==bank_audio_base and bank_profile_active then return nil end
 local crc=0xffff
 for i=0,bank_size-1 do
  crc=(crc^^(peek(base+i)<<8))&0xffff
  for bit=1,8 do
   if (crc&0x8000)!=0 then
    crc=((crc<<1)^^0x1021)&0xffff
   else
    crc=(crc<<1)&0xffff
   end
  end
 end
 return crc
end

function bank_checksum_matches(base,expected)
 if not bank_int(expected,-0x8000,0x7fff) then return false end
 local actual=bank_checksum(base)
 return actual!=nil and (actual&0xffff)==(expected&0xffff)
end

-- memcpy ordering: destination, source.
function bank_copy(destination,source)
 if not bank_region(destination) or not bank_region(source) then return false end
 -- Only staging is writable through the public bulk-copy path. Commit and
 -- rollback exclusively own canonical and snapshot writes.
 if destination!=bank_stage_base then return false end
 if bank_profile_active and source==bank_audio_base then return false end
 if bank_equal(destination,source) then return true end
 memcpy(destination,source,bank_size)
 return true
end

function bank_stage_commit(expected)
 if bank_profile_active or
    not bank_checksum_matches(bank_stage_base,expected) then return false end
 if bank_equal(bank_audio_base,bank_stage_base) then return true end
 memcpy(bank_snapshot_base,bank_audio_base,bank_size)
 bank_snapshot_valid=true
 bank_snapshot_dirty=bank_dirty
 memcpy(bank_audio_base,bank_stage_base,bank_size)
 bank_touch()
 return true
end

function bank_rollback()
 if bank_profile_active or not bank_snapshot_valid then return false end
 memcpy(bank_audio_base,bank_snapshot_base,bank_size)
 bank_snapshot_valid=false
 bank_revision+=1
 bank_dirty=bank_snapshot_dirty
 return true
end

function bank_profile_is_active()
 return bank_profile_active==true
end

function bank_profile_apply()
 if bank_profile_active then return true end
 for sfx=1,4 do
  if bank_sfx_is_waveform(sfx) then return false end
 end
 local saved=bank_profile_base
 for sfx=1,4 do
  for row=0,31 do
   local addr=bank_sfx_base+sfx*bank_sfx_size+row*2
   local value=peek2(addr)
   poke2(saved,value)
   local volume=(value>>9)&7
   if volume>0 then
    poke2(addr,(value&0xf1ff)|(min(7,volume+2)<<9))
   end
   saved+=2
  end
 end
 bank_profile_active=true
 return true
end

function bank_profile_restore()
 if not bank_profile_active then return true end
 local saved=bank_profile_base
 for sfx=1,4 do
  for row=0,31 do
   poke2(bank_sfx_base+sfx*bank_sfx_size+row*2,peek2(saved))
   saved+=2
  end
 end
 bank_profile_active=false
 return true
end
