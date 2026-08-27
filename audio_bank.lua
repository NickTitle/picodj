-- pocket tracker native pico-8 audio bank core

bank_audio_base,bank_song_base,bank_sfx_base=0x3100,0x3100,0x3200
bank_size,bank_stage_base,bank_snapshot_base=0x1200,0x8000,0x9200
bank_profile_base,bank_audition_base=0xa400,0xa500
bank_clip_base,bank_batch_base=0xa544,0xa584
bank_audition_sfx,bank_audition_channel,bank_profile_kind=63,3,1

bank_pattern_count,bank_channel_count,bank_sfx_count=64,4,64
bank_row_count,bank_sfx_size=32,68
bank_filter_steps={2,4,8,24,72}

function bank_int(v,lo,hi)
 return type(v)=="number" and v==flr(v) and v>=lo and v<=hi
end

function bank_region(base)
 return base==bank_audio_base or base==bank_stage_base or base==bank_snapshot_base
end

function bank_touch()
 bank_dirty=true
 bank_revision+=1
end

function bank_project_init()
 if bank_audition_saved then bank_audition_restore() end
 if bank_profile_active then bank_profile_restore() end
 bank_dirty,bank_revision=false,0
 bank_snapshot_valid,bank_snapshot_dirty=false,false
 bank_profile_active,bank_audition_saved=false,false
end

function bank_mark_clean()
 bank_dirty=false
end

function bank_song_addr(pattern,channel)
 if not bank_int(pattern,0,63) or not bank_int(channel,0,3) then return end
 return bank_song_base+pattern*4+channel
end

function bank_sfx_addr(sfx,offset)
 if not bank_int(sfx,0,63) or not bank_int(offset,0,67) then return end
 return bank_sfx_base+sfx*bank_sfx_size+offset
end

function bank_sfx_is_waveform(sfx)
 local addr=bank_sfx_addr(sfx,66)
 return addr and sfx<8 and peek(addr)&0x80!=0
end

function bank_note_addr(sfx,row)
 if not bank_int(sfx,0,63) or not bank_int(row,0,31) or bank_sfx_is_waveform(sfx) then return end
 return bank_sfx_base+sfx*bank_sfx_size+row*2
end

function bank_span(addr,size)
 return bank_int(size,1,64) and bank_int(addr,bank_audio_base,bank_audio_base+bank_size-size)
end

function bank_write(addr,width,value)
 if bank_profile_active or not bank_span(addr,width) or width>2 or
  (width==2 and addr<bank_sfx_base) or type(value)!="number" or value!=flr(value) or
  (width==1 and not bank_int(value,0,255)) then return false end
 value=value&(width==1 and 255 or 0xffff)
 local old=width==1 and peek(addr) or peek2(addr)&0xffff
 if old==value then return true end
 if width==1 then poke(addr,value) else poke2(addr,value) end
 bank_touch()
 return true
end

function bank_swap(addr,size)
 if bank_profile_active or not bank_span(addr,size) then return false end
 for i=0,size-1 do
  local value=peek(addr+i)
  poke(addr+i,peek(bank_batch_base+i))
  poke(bank_batch_base+i,value)
 end
 bank_touch()
 return true
end

function bank_field(addr,width,shift,mask,value)
 if not bank_span(addr,width) or width>2 or (width==2 and addr<bank_sfx_base) or
  not bank_int(shift,0,width*8-1) or not bank_int(mask,0,255) then
  if value==nil then return end return false
 end
 local raw=width==1 and peek(addr) or peek2(addr)
 if value==nil then return (raw>>shift)&mask end
 if not bank_int(value,0,mask) then return false end
 return bank_write(addr,width,(raw&(0xffff^^(mask<<shift)))|(value<<shift))
end

function bank_note_authored_raw(sfx,row)
 local addr=bank_note_addr(sfx,row)
 if not addr then return end
 if bank_profile_active and sfx>=1 and sfx<=4 then
  return peek2(bank_profile_base+(sfx-1)*64+row*2)
 end
 return peek2(addr)
end

function bank_rows(sfx,row,count,source,write)
 if not bank_int(row,0,bank_row_count-1) or not bank_int(count,1,bank_row_count) or
  row+count>bank_row_count or not bank_note_addr(sfx,row) or
  (source!=nil and source!=bank_clip_base) then return end
 local addr=bank_note_addr(sfx,row)
 local authored=bank_profile_active and sfx>=1 and sfx<=4 and
  bank_profile_base+(sfx-1)*64+row*2 or addr
 local bytes=count*2
 if write==nil then memcpy(bank_clip_base,authored,bytes) return true end
 local same=true
 for i=0,bytes-1 do
  if peek(authored+i)!=(source and peek(source+i) or 0) then same=false end
 end
 if not write or same then return same end
 if bank_profile_active then return false end
 memcpy(bank_batch_base,addr,bytes)
 if source then memcpy(addr,source,bytes) else memset(addr,0,bytes) end
 bank_touch()
 return true
end

function bank_sfx_meta_raw(sfx,index)
 local addr=bank_int(index,0,3) and bank_sfx_addr(sfx,64+index)
 return addr and peek(addr)
end

function bank_sfx_filter(sfx,index)
 local raw,step=bank_sfx_meta_raw(sfx,0),bank_filter_steps[index]
 if not step or not raw or raw>0xd7 or
  index<3 and bank_sfx_is_waveform(sfx) then return end
 return flr(raw/step)%(2+index\3)
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
 if not bank_region(base) or base==bank_audio_base and bank_profile_active then return end
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
 if bank_profile_active or bank_profile_kind<1 then return true end
 local saved=bank_profile_base
 for sfx=1,4 do
  local wave=bank_sfx_is_waveform(sfx)
  for row=0,31 do
   local addr=bank_sfx_base+sfx*bank_sfx_size+row*2
   local value=peek2(addr)
   poke2(saved,value)
   local volume=(value>>9)&7
   if not wave and volume>0 then
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

function bank_audition_restore()
 if not bank_audition_saved then return end
 memcpy(bank_sfx_addr(bank_audition_sfx,0),bank_audition_base,bank_sfx_size)
 bank_audition_saved=false
end

-- SFX 63 is a reversible scratch slot; preview never dirties the project.
function bank_audition_build(source,row)
 if bank_sfx_is_waveform(source) then return false end
 bank_audition_restore()
 memcpy(bank_audition_base,bank_sfx_addr(bank_audition_sfx,0),bank_sfx_size)
 bank_audition_saved=true
 local destination=bank_sfx_addr(bank_audition_sfx,0)
 local source_base=source==bank_audition_sfx and bank_audition_base or
  bank_sfx_addr(source,0)
 if row!=nil then
  memset(destination,0,bank_sfx_size)
  poke2(destination,peek2(source_base+row*2))
  poke(destination+65,peek(source_base+65))
 else
  memcpy(destination,source_base,bank_sfx_size)
 end
 return true
end
