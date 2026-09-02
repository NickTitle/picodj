pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
#include ../audio_bank.lua

playing=false
audition_active=false
undo_owner=nil
song_error=nil
stop_song_calls=0
stop_audition_calls=0

function _init() end
function _update60() end
function context_label(name) return name end
function say() end
function stop_audition()
 stop_audition_calls+=1
 audition_active=false
 return true
end
function stop_song()
 stop_song_calls+=1
 bank_profile_restore()
 playing=false
 return true
end

#include ../project_io.lua

native_real_cstore=cstore
native_real_reload=reload
native_cstore_calls=0
native_reload_calls=0
native_cstore_fault_call=0
native_reload_fault_call=0
native_cstore_fault=nil
native_reload_fault=nil

-- Native calls deliberately return nil. The production adapter must determine
-- success from sentinel-prefill plus record and envelope validation.
function cstore(destination,source,length,filename)
 native_cstore_calls+=1
 if native_cstore_calls==native_cstore_fault_call then
  if native_cstore_fault=="noop" then return end
  if native_cstore_fault=="partial" then
   native_real_cstore(destination,source,16,filename)
   return
  end
 end
 native_real_cstore(destination,source,length,filename)
end

function reload(destination,source,length,filename)
 native_reload_calls+=1
 if native_reload_calls==native_reload_fault_call then
  if native_reload_fault=="noop" then return end
  if native_reload_fault=="partial" then
   native_real_reload(destination,source,16,filename)
   return
  end
 end
 native_real_reload(destination,source,length,filename)
end

failures=0

function check(ok,label)
 if ok then return end
 failures+=1
 printh("fail: "..label)
end

function fill_bank(seed)
 for i=0,bank_size-1 do poke(bank_audio_base+i,(i*37+seed)&0xff) end
end

function bank_matches(seed)
 for i=0,bank_size-1 do
  if peek(bank_audio_base+i)!=(i*37+seed)&0xff then return false end
 end
 return true
end

function project(seed,profile,revision,name,source)
 fill_bank(seed)
 bank_profile_kind=profile
 bank_revision=revision
 io_project_name=name
 io_project_source=source
 bank_dirty=true
end

function write_record(slot,generation,seed,profile)
 project(seed,profile,generation,"generation "..generation,"native test")
 check(io_prepare_envelope(),"prepare generation "..generation)
 local base=native_base+slot*native_record
 poke2(base,0x5450) poke2(base+2,0x314a) io_put16(base+4,generation)
 memcpy(base+8,io_header,io_header_size)
 memcpy(base+8+io_header_size,bank_audio_base,bank_size)
 io_put16(base+6,native_crc(base))
 native_real_cstore(slot*native_record,base,native_record,native_cart)
end

function reset_cart(seed)
 memset(native_base,0,native_total)
 native_real_cstore(0,native_base,native_total,native_cart)
 write_record(0,1,seed,0)
end

function record_matches(slot,generation,seed)
 local base=native_base+slot*native_record
 memset(base,0xcc,native_record)
 native_real_reload(base,slot*native_record,native_record,native_cart)
 if native_stage(slot)!=generation then return false end
 for i=0,bank_size-1 do
  if peek(bank_stage_base+i)!=(i*37+seed)&0xff then return false end
 end
 return true
end

function fault_save(label,cstore_fault,reload_fault)
 reset_cart(61)
 project(67,0,67,label,"fault source") undo_owner="sfx"
 native_cstore_calls=0 native_reload_calls=0
 native_cstore_fault_call=cstore_fault and 1 or 0
 native_reload_fault_call=reload_fault and 2 or 0
 native_cstore_fault=cstore_fault native_reload_fault=reload_fault
 check(not native_save(),label.." rejected")
 native_cstore_fault_call=0 native_reload_fault_call=0
 native_cstore_fault=nil native_reload_fault=nil
 check(bank_matches(67) and bank_dirty and bank_revision==67 and
  io_project_name==label and io_project_source=="fault source" and
  undo_owner=="sfx",label.." preserves live project")
 check(record_matches(0,1,61),label.." preserves prior record")
end

native_test_init=_init
function _init()
 native_test_init()
 bank_project_init()
 native_cart="fixtures/pocket-tracker-data-test.p8"
 check(native_base==io_header+io_header_size and
  native_base+native_total<=0x10000,"native scratch is exact and bounded")
 -- First save writes A at generation 1 and restores temporary profile bytes.
 project(11,1,37,"track one","fixture source")
 check(bank_profile_apply(),"profile applies before save")
 playing=true undo_owner="song"
 check(native_save(),"first save")
 check(not playing and not bank_profile_is_active() and stop_song_calls==1,
  "save stops once and restores authored bank")
 check(bank_matches(11),"first save preserves all authored bytes")
 check(not bank_dirty and undo_owner==nil and song_error==nil,
  "first save establishes clean baseline")
 local slot,generation=native_scan()
 check(slot==0 and generation==1,"first save selects record a")

 -- Missing, partial, and unconfirmed writes preserve live and durable state.
 fault_save("cstore no-op","noop")
 fault_save("partial write/read","partial","partial")
 fault_save("read-back no-op",nil,"noop")

 -- Retry writes B, then the newest complete profile-none project loads.
 memset(native_base,0,native_total)
 native_real_cstore(0,native_base,native_total,native_cart)
 project(11,1,37,"track one","fixture source")
 check(native_save(),"restore track-one record a")
 project(23,0,42,"raw project","profile none") undo_owner="sfx"
 audition_active=true
 check(native_save(),"second save retry")
 check(not audition_active and stop_audition_calls==1,
  "save stops active audition once")
 slot,generation=native_scan()
 check(slot==1 and generation==2,"second save alternates to record b")
 project(99,1,9,"temporary","temporary") undo_owner="song"
 check(native_load(),"load newest record")
 check(bank_matches(23) and bank_profile_kind==0 and bank_revision==42 and
  io_project_name=="raw project" and io_project_source=="profile none",
  "profile-none round trip is exact")
 check(not bank_dirty and not bank_snapshot_valid and undo_owner==nil,
  "successful load establishes clean history baseline")
 check(song_error==nil,"successful load clears visible error")

 -- Corrupt newest B on disk; load must fall back to intact A.
 native_real_reload(native_base,0,native_total,native_cart)
 poke(native_base+native_record+123,peek(native_base+native_record+123)^^1)
 native_real_cstore(native_record,native_base+native_record,native_record,native_cart)
 project(77,0,77,"live","unchanged") undo_owner="sfx"
 check(native_load(),"corrupt newest falls back")
 check(bank_matches(11) and bank_profile_kind==1 and bank_revision==37 and
  io_project_name=="track one" and io_project_source=="fixture source",
  "fallback restores older track-one record")

 -- Both invalid records reject atomically.
 native_real_reload(native_base,0,native_total,native_cart)
 poke(native_base+321,peek(native_base+321)^^1)
 native_real_cstore(0,native_base,native_record,native_cart)
 project(71,0,71,"live invalid","keep me") undo_owner="song"
 check(not native_load() and song_error=="data cart invalid","both invalid reject visibly")
 check(bank_matches(71) and bank_dirty and bank_revision==71 and
  bank_profile_kind==0 and io_project_name=="live invalid" and
  io_project_source=="keep me" and undo_owner=="song",
  "invalid load preserves live project")

 -- Modular generation ordering handles alternation, wrap, and exact ties.
 write_record(0,3,29,1)
 write_record(1,2,37,0)
 slot,generation=native_scan()
 check(slot==0 and generation==3,"a3 is newer than b2")
 write_record(0,0xffff,31,1)
 write_record(1,0,47,0)
 slot,generation=native_scan()
 check(slot==1 and generation==0,"generation wrap chooses zero after ffff")
 project(88,1,88,"temporary","temporary")
 check(native_load() and bank_matches(47) and bank_profile_kind==0,
  "wrapped newest record loads")
 write_record(0,0,41,1)
 write_record(1,0xffff,43,0)
 slot,generation=native_scan()
 check(slot==0 and generation==0,"reverse wrap chooses zero after ffff")
 write_record(0,9,53,1)
 write_record(1,9,59,0)
 slot,generation=native_scan()
 check(slot==0 and generation==9,"generation tie deterministically chooses a")
 write_record(0,0,61,1)
 write_record(1,0x8000,63,0)
 slot,generation=native_scan()
 check(slot==0 and generation==0,"generation half-range chooses a")
 memset(native_base,0,native_total)
 native_real_cstore(0,native_base,native_total,native_cart)
 for i=1,4 do
  project(70+i,0,i,"save "..i,"alternation")
  check(native_save(),"sequential save "..i)
  slot,generation=native_scan()
  check(slot==(i-1)%2 and generation==i,"sequential slot "..i)
 end

 -- A cancelled reload leaves both sentinels untouched and changes nothing.
 project(83,0,83,"cancel live","cancel source") undo_owner="sfx"
 native_reload_calls=0 native_reload_fault_call=1 native_reload_fault="noop"
 check(not native_save() and song_error=="data cart missing/cancelled",
  "cancelled save detected without return values")
 check(bank_matches(83) and bank_dirty and bank_revision==83 and
  undo_owner=="sfx","cancelled save preserves live project")
 native_reload_calls=0
 check(not native_load() and song_error=="data cart missing/cancelled",
  "cancelled load detected without return values")
 native_reload_fault_call=0 native_reload_fault=nil
 check(bank_matches(83) and bank_dirty and bank_revision==83 and
  io_project_name=="cancel live" and io_project_source=="cancel source" and
  undo_owner=="sfx","cancelled load preserves live project")

 if failures==0 then printh("pocket tracker native store: passed")
 else printh("pocket tracker native store: failed "..failures) end
 extcmd("shutdown")
end
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
