pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- m1 track 1 fixture validation

stage_song=0x8000
stage_sfx=0x8100

source_sfx={
 "011800000a05000000010000a050050500100000000050500a0500000000000050500a050000000a0500b0500c05000000000000c050070500000000000070500c0500b000000000c05007050050000505007050",
 "0d1800001a055010051a05519005110051b055120051a0551a0051a055140051a0551a0551e005180551a0551b055200051b055210051d0051d0551a0051b0551b0051b0551c0051b0551b05526005180551b055",
 "491800001961518615186351961519615196351961519615196251a63519615186251963519615196151863518615186151963519615196251963519615186151a6351a61519615196351961519615196351a635",
 "0118000018d70000000000018d7018d70000000000018d7018d70000000000018d7018d700000018d700000018d70000000000018d7018d70000000000018d7018d70000000000018d7018d700000018d7000000"
}

function check(ok,label)
 if ok then return end
 printh("fail: "..label)
 extcmd("shutdown")
end

function hx(s,a,b)
 return tonum("0x"..sub(s,a,b))
end

function source_word(line,row)
 local p=9+row*5
 local pitch=hx(line,p,p+1)
 local instrument=hx(line,p+2,p+2)
 local volume=hx(line,p+3,p+3)
 local effect=hx(line,p+4,p+4)
 local custom=(instrument&8)>0 and 0x8000 or 0
 return pitch+(instrument&7)*64+volume*512+effect*4096+custom
end

function check_source_sfx(s,line)
 local base=stage_sfx+s*68
 check(peek(base+64)==hx(line,1,2),"sfx "..s.." mode/filter")
 check(peek(base+65)==hx(line,3,4),"sfx "..s.." speed")
 check(peek(base+66)==hx(line,5,6),"sfx "..s.." loop start")
 check(peek(base+67)==hx(line,7,8),"sfx "..s.." loop end")
 for row=0,31 do
  check(peek2(base+row*2)==source_word(line,row),"sfx "..s.." row "..row)
 end
end

function _init()
 reload(stage_song,0x3100,0x1200,"fixtures/pico-strfld-e7e97ab-track-1.p8")

 -- pattern 0: source text `03 01020304`
 -- loop-start and loop-back occupy bit 7 of channel bytes 0 and 1.
 check(peek(stage_song)==0x81,"pattern 0 channel 0 / loop start")
 check(peek(stage_song+1)==0x82,"pattern 0 channel 1 / loop back")
 check(peek(stage_song+2)==0x03,"pattern 0 channel 2")
 check(peek(stage_song+3)==0x04,"pattern 0 channel 3")

 -- Preserve the neighboring muted source row copied into the fixture too.
 check(peek(stage_song+4)==0xc1,"pattern 1 channel 0")
 check(peek(stage_song+5)==0x42,"pattern 1 channel 1")
 check(peek(stage_song+6)==0x43,"pattern 1 channel 2")
 check(peek(stage_song+7)==0x44,"pattern 1 channel 3")

 for s=1,4 do check_source_sfx(s,source_sfx[s]) end

 printh("pocket tracker m1 fixture: passed")
 extcmd("shutdown")
end

__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

