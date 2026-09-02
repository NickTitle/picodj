pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
#include ../audio_bank.lua

failures=0
test_reference_base=0x9200

function check(ok,label)
 if ok then return end
 failures+=1
 printh("fail: "..label)
end

function check_checksum(base,expected,label)
 local actual=bank_checksum(base)
 check(actual!=nil and (actual&0xffff)==(expected&0xffff),label)
end

function check_owned(before,after,owned,label)
 check(((before^^after)&(0xffff^^owned))==0,label)
end

function raw_song(pattern,channel)
 local addr=bank_song_addr(pattern,channel)
 return addr and peek(addr) or nil
end

function raw_note(sfx,row)
 local addr=bank_note_addr(sfx,row)
 return addr and peek2(addr) or nil
end

function test_equal(a,b,size)
 for i=0,size-1 do
  if peek(a+i)!=peek(b+i) then return false end
 end
 return true
end

function test_field(addr,width,shift,mask,value)
 if not bank_span(addr,width) or width>2 or (width==2 and addr<bank_sfx_base) or
  not bank_int(shift,0,width*8-1) or not bank_int(mask,0,255) then
  if value==nil then return end return false
 end
 local raw=width==1 and peek(addr) or peek2(addr)
 if value==nil then return (raw>>shift)&mask end
 if not bank_int(value,0,mask) then return false end
 return bank_write(addr,width,(raw&(0xffff^^(mask<<shift)))|(value<<shift))
end

function note_field(sfx,row,shift,mask,value)
 return test_field(bank_note_addr(sfx,row),2,shift,mask,value)
end

function check_profile_words(label)
 local saved=bank_profile_base
 local silent,loud=0,0
 for sfx=1,4 do
  for row=0,31 do
   local original=peek2(saved)
   local volume=(original>>9)&7
   local expected=original
   if volume>0 then
    expected=(original&0xf1ff)|(min(7,volume+2)<<9)
    loud+=1
   else
    silent+=1
   end
   local addr=bank_sfx_base+sfx*bank_sfx_size+row*2
   check((peek2(addr)&0xffff)==(expected&0xffff),label.." sfx "..sfx.." row "..row)
   saved+=2
  end
 end
 check(silent>0 and loud>0,label.." covers silent and loud rows")
end

function check_restored_profile(label)
 local saved=bank_profile_base
 for sfx=1,4 do
  for row=0,31 do
   local addr=bank_sfx_base+sfx*bank_sfx_size+row*2
   check((peek2(addr)&0xffff)==(peek2(saved)&0xffff),label.." sfx "..sfx.." row "..row)
   saved+=2
  end
 end
end

function _init()
 bank_project_init()

 -- Exact first/last address boundaries.
 check(bank_song_addr(0,0)==0x3100,"first song address")
 check(bank_song_addr(63,3)==0x31ff,"last song address")
 check(bank_sfx_addr(0,0)==0x3200,"first sfx address")
 check(bank_sfx_addr(63,67)==0x42ff,"last sfx address")
 check(bank_note_addr(0,0)==0x3200,"first note address")
 check(bank_note_addr(63,31)==0x42fa,"last note address")

 -- Load canonical fixture into staging and pin the complete native bank.
 reload(bank_stage_base,0x3100,bank_size,"fixtures/pico-strfld-e7e97ab-track-1.p8")
 local fixture_crc=bank_checksum(bank_stage_base)
 check(fixture_crc==0x2a23,"canonical fixture crc is 0x2a23")
 check_checksum(bank_stage_base,0x2a23,"exact fixture crc-16/ccitt-false")
 check(peek(bank_stage_base)==0x81 and peek(bank_stage_base+1)==0x82 and
       peek(bank_stage_base+2)==3 and peek(bank_stage_base+3)==4,
       "exact fixture pattern 0")

 check(bank_stage_commit(fixture_crc),"fixture staging commit")
 check(bank_equal(bank_audio_base,bank_stage_base),"fixture seed identity")
 check(bank_dirty and bank_revision==1,"commit dirty revision")
 bank_mark_clean()

 -- Track 1 profile is temporary, complete, idempotent, and reversible.
 local profile_crc=bank_checksum(bank_audio_base)
 local profile_revision=bank_revision
 check(bank_profile_apply(),"profile apply")
 check(bank_profile_is_active(),"profile active")
 check_profile_words("profile first apply")
 check(bank_note_authored_raw(1,0)==peek2(bank_profile_base),
       "authored accessor ignores preview profile")
 check(bank_checksum(bank_audio_base)==nil,"authored checksum blocked while profiled")
 check(bank_profile_apply(),"profile second apply")
 check_profile_words("profile idempotent")
 local active_revision=bank_revision
 check(not note_field(1,0,9,7,1) and
       not test_field(bank_song_addr(0,0),1,0,63,2),
       "profile blocks authored writes")
 check(bank_revision==active_revision,"profile rejection preserves revision")
 check_profile_words("profile rejection preserves preview")
 check(bank_revision==profile_revision and not bank_dirty,"profile does not dirty project")
 check(bank_profile_restore(),"profile restore")
 check(not bank_profile_is_active(),"profile inactive")
 check_restored_profile("profile restored")
 check_checksum(bank_audio_base,profile_crc,"profile checksum restored")
 check(bank_note_authored_raw(1,0)==raw_note(1,0),
       "authored accessor reads canonical when stopped")
 check(bank_profile_restore(),"profile second restore")
 check(bank_revision==profile_revision and not bank_dirty,"restore does not dirty project")

 -- Profile-none playback performs no authored-bank or profile-scratch writes.
 memcpy(bank_stage_base,bank_audio_base,bank_size)
 local profile_saved=peek(bank_profile_base)
 bank_profile_kind=0
 check(bank_profile_apply() and not bank_profile_is_active(),"profile-none apply")
 check(test_equal(bank_audio_base,bank_stage_base,bank_size) and
  peek(bank_profile_base)==profile_saved,
  "profile-none performs zero writes")
 check(bank_profile_restore() and test_equal(bank_audio_base,bank_stage_base,bank_size),
  "profile-none restore exact")
 bank_profile_kind=1

 -- Waveform profile boundaries save but never transform sample or metadata bytes.
 memcpy(test_reference_base,bank_audio_base,bank_size)
 reload(bank_stage_base,bank_audio_base,bank_size,"fixtures/pico8-027-waveform.p8")
 for sfx in all({1,4}) do
  memcpy(bank_sfx_addr(sfx,0),bank_stage_base+0x100,bank_sfx_size)
 end
 poke2(bank_sfx_addr(2,0),0x0a18)
 poke2(bank_sfx_addr(3,0),0x0e18)
 poke2(bank_sfx_addr(8,0),0x8a58)
 memcpy(bank_stage_base,bank_audio_base,bank_size)
 bank_project_init()
 local wave_revision=bank_revision
 check(bank_profile_apply() and bank_profile_is_active(),"waveform profile apply")
 for sfx in all({1,4}) do
  local saved=bank_profile_base+(sfx-1)*64
  for i=0,63 do
   check(peek(bank_sfx_addr(sfx,i))==peek(bank_stage_base+0x100+sfx*68+i),
    "waveform sample exact "..sfx..":"..i)
   check(peek(saved+i)==peek(bank_sfx_addr(sfx,i)),
    "waveform snapshot exact "..sfx..":"..i)
  end
  for i=64,67 do
   check(peek(bank_sfx_addr(sfx,i))==peek(bank_stage_base+0x100+sfx*68+i),
    "waveform metadata exact "..sfx..":"..i)
  end
 end
 check((peek2(bank_sfx_addr(2,0))&0xffff)==0x0e18 and
  (peek2(bank_sfx_addr(3,0))&0xffff)==0x0e18,"conventional siblings boost and cap")
 check((peek2(bank_sfx_addr(8,0))&0xffff)==0x8a58,"custom reference exact")
 check(bank_profile_apply(),"waveform profile idempotent")
 check(bank_profile_restore() and bank_equal(bank_audio_base,bank_stage_base),
  "waveform profile restores complete authored bank")
 check(bank_revision==wave_revision and not bank_dirty,"waveform profile metadata clean")
 memcpy(bank_audio_base,test_reference_base,bank_size)
 bank_project_init()

 -- Seed values that exercise unrelated high bits, then reset metadata only.
 poke(bank_song_addr(63,3),0xc5)
 poke(bank_song_addr(62,0),0x55)
 poke(bank_song_addr(62,1),0x66)
 poke(bank_song_addr(62,2),0x77)
 poke2(bank_note_addr(63,31),0x4567)
 bank_project_init()

 -- Song accessors cover both boundaries and preserve mute/reserved bits.
 check((raw_song(0,0)&0x3f)==1,"first pattern sfx")
 check((raw_song(63,3)&0x3f)==5,"last pattern sfx")
 check(test_field(bank_song_addr(63,3),1,0,63,42),"set last pattern sfx")
 check(raw_song(63,3)==0xea,"pattern sfx preserves high bits")
 local revision=bank_revision
 check(test_field(bank_song_addr(63,3),1,0,63,42) and bank_revision==revision,
       "unchanged pattern sfx does not revise")
 check(test_field(bank_song_addr(63,3),1,6,1)==1,"pattern mute getter")
 check(test_field(bank_song_addr(63,3),1,6,1,0),"pattern mute clear")
 check(raw_song(63,3)==0xaa,"mute preserves sfx and reserved bit")

 check(test_field(bank_song_addr(62,0),1,7,1,1),"loop start set")
 check(test_field(bank_song_addr(62,0),1,7,1)==1 and raw_song(62,0)==0xd5,
       "loop start preserves lower bits")
 check(test_field(bank_song_addr(62,0),1,7,1,0) and raw_song(62,0)==0x55,
       "loop start clear")
 check(test_field(bank_song_addr(62,1),1,7,1,1),"loop back set")
 check(test_field(bank_song_addr(62,1),1,7,1)==1 and raw_song(62,1)==0xe6,
       "loop back preserves lower bits")
 check(test_field(bank_song_addr(62,2),1,7,1,1),"stop set")
 check(test_field(bank_song_addr(62,2),1,7,1)==1 and raw_song(62,2)==0xf7,
       "stop preserves lower bits")
 check((raw_song(62,3)&0x80)==0,"reserved song bit preserved")

 -- Note fields own disjoint masks, including the custom-instrument bit.
 check(note_field(0,0,0,63)==0x18,"first note pitch")
 local before=raw_note(63,31)
 check(note_field(63,31,0,63,17),"set pitch")
 local after=raw_note(63,31)
 check_owned(before,after,0x003f,"pitch preserves unrelated bits")
 check(note_field(63,31,0,63)==17,"pitch getter")

 before=after
 check(note_field(63,31,6,7,6),"set instrument")
 after=raw_note(63,31)
 check_owned(before,after,0x01c0,"instrument preserves unrelated bits")
 check(note_field(63,31,6,7)==6,"instrument getter")

 before=after
 check(note_field(63,31,9,7,7),"set volume")
 after=raw_note(63,31)
 check_owned(before,after,0x0e00,"volume preserves unrelated bits")
 check(note_field(63,31,9,7)==7,"volume getter")

 before=after
 check(note_field(63,31,12,7,3),"set effect")
 after=raw_note(63,31)
 check_owned(before,after,0x7000,"effect preserves unrelated bits")
 check(note_field(63,31,12,7)==3,"effect getter")

 before=after
 check(note_field(63,31,15,1,1),"set custom instrument")
 after=raw_note(63,31)
 check_owned(before,after,0x8000,"custom preserves unrelated bits")
 check(note_field(63,31,15,1)==1,"custom getter")
 check(note_field(63,31,15,1,0) and note_field(63,31,15,1)==0,
       "custom clear")

 check(test_field(bank_sfx_addr(63,67),1,0,255,0xa5),"set last raw metadata")
 check(bank_sfx_meta_raw(63,3)==0xa5,"raw metadata getter")

 -- Semantic SFX metadata owns only documented low bits.
 poke(bank_sfx_addr(63,65),0x18)
 poke(bank_sfx_addr(63,66),0xa2)
 poke(bank_sfx_addr(63,67),0xc4)
 bank_project_init()
 check(bank_sfx_meta_raw(63,1)==0x18 and (bank_sfx_meta_raw(63,2)&31)==2 and
       (bank_sfx_meta_raw(63,3)&31)==4,"semantic metadata getters")
 check(test_field(bank_sfx_addr(63,65),1,0,255,31),"semantic speed setter")
 check(bank_sfx_meta_raw(63,1)==31,"speed owns complete byte")
 check(test_field(bank_sfx_addr(63,66),1,0,31,7),"semantic loop start setter")
 check(bank_sfx_meta_raw(63,2)==0xa7,"loop start preserves high bits")
 check(test_field(bank_sfx_addr(63,67),1,0,31,9),"semantic loop end setter")
 check(bank_sfx_meta_raw(63,3)==0xc9,"loop end preserves high bits")

 -- Invalid indices, types, and values never mutate the authored bank.
 local rejected_crc=bank_checksum(bank_audio_base)
 local rejected_revision=bank_revision
 check(bank_song_addr(-1,0)==nil and bank_song_addr(64,0)==nil and
       bank_song_addr(0,4)==nil and bank_song_addr(0.5,0)==nil,
       "song address rejection")
 check(bank_sfx_addr(-1,0)==nil and bank_sfx_addr(64,0)==nil and
       bank_sfx_addr(0,68)==nil,"sfx address rejection")
 check(bank_note_addr(0,-1)==nil and bank_note_addr(0,32)==nil,
       "note address rejection")
 check(not test_field(bank_song_addr(64,0),1,0,63,0) and
       not test_field(bank_song_addr(0,0),1,0,63,64) and
       not test_field(bank_song_addr(0,0),1,6,1,2),"song field rejection")
 check(not note_field(63,31,0,63,64) and
       not note_field(63,31,6,7,8) and
       not note_field(63,31,9,7,8) and
       not note_field(63,31,12,7,8) and
       not note_field(63,31,15,1,2),"note setter rejection")
 check(not test_field(bank_sfx_addr(63,66),1,0,31,32) and
       not test_field(bank_sfx_addr(63,67),1,0,31,32),"semantic metadata rejection")
 check(not test_field(bank_sfx_addr(63,68),1,0,255,0) and
       not test_field(bank_sfx_addr(63,67),1,0,255,256),"metadata rejection")
 check_checksum(bank_audio_base,rejected_crc,"rejections preserve bank")
 check(bank_revision==rejected_revision,"rejections preserve revision")

 -- A corrupt staging image cannot replace any authored byte or metadata.
 memcpy(test_reference_base,bank_audio_base,bank_size)
 memcpy(bank_stage_base,bank_audio_base,bank_size)
 local expected_crc=bank_checksum(bank_stage_base)
 poke(bank_stage_base+123,peek(bank_stage_base+123)^^1)
 local before_corrupt_crc=bank_checksum(bank_audio_base)
 local before_corrupt_revision=bank_revision
 local before_corrupt_dirty=bank_dirty
 local before_corrupt_profile=bank_profile_kind
 check(not bank_stage_commit(expected_crc),"corrupt staging rejected")
 check_checksum(bank_audio_base,before_corrupt_crc,
                "corrupt staging preserves bank")
 check(test_equal(bank_audio_base,test_reference_base,bank_size),
       "corrupt staging preserves every bank byte")
 check(bank_revision==before_corrupt_revision and bank_dirty==before_corrupt_dirty and
       bank_profile_kind==before_corrupt_profile,
       "corrupt staging preserves project metadata")

 -- Waveform slots copy losslessly but reject conventional note semantics.
 memcpy(bank_stage_base,bank_audio_base,bank_size)
 local wave_stage=bank_stage_base+(bank_sfx_base-bank_audio_base)
 poke(wave_stage,0xa5)
 poke(wave_stage+66,peek(wave_stage+66)|0x80)
 local wave_crc=bank_checksum(bank_stage_base)
 local before_wave_revision=bank_revision
 check(bank_stage_commit(wave_crc),"waveform commit")
 check(bank_sfx_is_waveform(0),"waveform detection")
 check(peek(bank_sfx_addr(0,0))==0xa5,"waveform sample preserved")
 check((bank_sfx_meta_raw(0,2)&0x80)!=0,"waveform metadata preserved")
 local wave_revision=bank_revision
 local live_wave_crc=bank_checksum(bank_audio_base)
 check(bank_note_addr(0,0)==nil and note_field(0,0,0,63)==nil and
       not note_field(0,0,0,63,1),"waveform typed access rejected")
 check_checksum(bank_audio_base,live_wave_crc,
                "waveform rejection preserves bank")
 check(bank_revision==wave_revision,"waveform rejection preserves revision")
 check(bank_dirty and wave_revision==before_wave_revision+1,
       "waveform commit establishes dirty revision")

 if failures==0 then
  printh("pocket tracker m1 bank: passed")
 else
  printh("pocket tracker m1 bank: failed "..failures)
 end
 extcmd("shutdown")
end

__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
