-- Test-only fixture for the pre-native 78-byte sketch implementation.
save_size,save_addr,gpio_addr=78,0x5e00,0x5f80

function sfx_speed() return mid(1,flr(1920/bpm+0.5),255) end

function write_note(addr,note,wave,volume,effect)
 local packed=note>=0 and note+wave*64+volume*512+effect*4096 or 0
 poke2(addr,packed)
end

function rebuild_track(ch)
 local base=0x3200+(ch-1)*68
 for step=1,32 do
  local note=step<=steps and notes[ch][step] or -1
  write_note(base+(step-1)*2,note,waves[ch],volumes[ch],effects[ch])
 end
 poke(base+64,0) poke(base+65,sfx_speed()) poke(base+66,0) poke(base+67,steps)
end

function rebuild_all() for ch=1,tracks do rebuild_track(ch) end end

function start_song()
 rebuild_all()
 for ch=0,tracks-1 do sfx(ch,ch) end
 playing,play_tick,play_step=true,0,1
 say("playing")
end

function stop_song()
 for ch=0,tracks-1 do sfx(-1,ch) end
 playing=false say("stopped")
end

function toggle_song() if playing then stop_song() else start_song() end end

function audition(ch,note)
 if playing or note<0 then return end
 local base=0x3200+4*68
 write_note(base,note,waves[ch],volumes[ch],effects[ch])
 for i=1,31 do poke2(base+i*2,0) end
 poke(base+65,8) poke(base+66,0) poke(base+67,0)
 sfx(4,3,0,1)
end

function publish_gpio()
 local p=gpio_addr
 poke(p,80) poke(p+1,84) poke(p+2,1) poke(p+3,bpm) p+=4
 for ch=1,tracks do
  poke(p,waves[ch]) poke(p+1,volumes[ch]) poke(p+2,effects[ch]) p+=3
 end
 for ch=1,tracks do
  for step=1,steps do poke(p,notes[ch][step]<0 and 63 or notes[ch][step]) p+=1 end
 end
 poke(gpio_addr+127,(peek(gpio_addr+127)+1)%256)
end

function save_song()
 local base=save_addr+(slot-1)*save_size
 poke(base,199) poke(base+1,bpm)
 local p=base+2
 for ch=1,tracks do
  poke(p,waves[ch]) poke(p+1,volumes[ch]) poke(p+2,effects[ch]) p+=3
 end
 for ch=1,tracks do
  for step=1,steps do poke(p,notes[ch][step]<0 and 63 or notes[ch][step]) p+=1 end
 end
 dset(63,dget(63)) say("saved slot "..slot)
end

function load_song(show_notice)
 local base=save_addr+(slot-1)*save_size
 if peek(base)!=199 then return false end
 bpm=mid(60,peek(base+1),240)
 local p=base+2
 for ch=1,tracks do
  waves[ch]=peek(p)%8 volumes[ch]=peek(p+1)%8 effects[ch]=peek(p+2)%8 p+=3
 end
 for ch=1,tracks do
  for step=1,steps do
   local note=peek(p)%64
   notes[ch][step]=note==63 and -1 or note
   if note<63 then last_notes[ch]=note end
   p+=1
  end
 end
 rebuild_all() publish_gpio()
 return true
end

function request_export(secondary)
 publish_gpio()
 poke(gpio_addr+125,secondary and 2 or 1)
 export_counter=(export_counter+1)%256
 poke(gpio_addr+126,export_counter)
end

function activate_named(name,secondary)
 if name=="play" then toggle_song()
 elseif name=="save" and not secondary then save_song()
 elseif name=="load" and not secondary then load_song(true)
 elseif name=="slot" then slot=((slot-1+(secondary and -1 or 1))%slot_count)+1
 elseif name=="bpm" then bpm=mid(60,bpm+(secondary and -5 or 5),240) rebuild_all() publish_gpio()
 elseif name=="wave" then waves[cursor_ch]=(waves[cursor_ch]+(secondary and 7 or 1))%8 rebuild_track(cursor_ch) publish_gpio()
 elseif name=="vol" then volumes[cursor_ch]=mid(0,volumes[cursor_ch]+(secondary and -1 or 1),7) rebuild_track(cursor_ch) publish_gpio()
 elseif name=="fx" then effects[cursor_ch]=(effects[cursor_ch]+(secondary and 7 or 1))%8 rebuild_track(cursor_ch) publish_gpio()
 elseif name=="export" then request_export(secondary) end
end

function update_playhead()
 if not playing then return end
 play_tick+=1
 play_step=flr(play_tick/max(1,sfx_speed()*60/128))%steps+1
end

function draw_header()
 rectfill(0,0,127,8,1)
 print("pocket tracker",2,2,7)
 print(bpm.." bpm",75,2,12)
 print("s"..slot,112,2,10)
end
