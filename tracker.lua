-- pocket tracker
-- a 4-channel, 16-step handheld song sketchpad

steps=16
tracks=4
slot_count=3
save_size=78
save_addr=0x5e00
gpio_addr=0x5f80
note_names={"c-","c#","d-","d#","e-","f-","f#","g-","g#","a-","a#","b-"}
menu_names={"play","save","load","slot","bpm","wave","vol","fx","export"}
wave_names={"tri","tilt","saw","sqr","pulse","organ","noise","phase"}

function fresh_song()
 notes={}
 last_notes={24,24,24,24}
 waves={0,2,3,6}
 volumes={5,4,4,3}
 effects={0,0,0,0}
 bpm=120
 for ch=1,tracks do
  notes[ch]={}
  for step=1,steps do notes[ch][step]=-1 end
 end
 -- a small editable starter loop
 local seed={24, -1,31,-1, 27,-1,31,-1, 24,-1,31,-1, 29,-1,31,-1}
 for i=1,steps do notes[1][i]=seed[i] end
 for i=1,steps,4 do notes[2][i]=12 end
 for i=3,steps,4 do notes[2][i]=19 end
 for i=1,steps,2 do notes[4][i]=(i%4==1) and 8 or 5 end
end

function _init()
 cartdata("pocket_tracker_v1")
 fresh_song()
 slot=1
 cursor_ch=1
 cursor_step=1
 menu_item=1
 playing=false
 play_tick=0
 play_step=1
 export_counter=0
 poke(gpio_addr+125,0)
 poke(gpio_addr+126,0)
 notice="o/x edit  o+x rest"
 notice_tick=180
 load_song(false)
 rebuild_all()
 publish_gpio()
end

function note_word(note)
 if note<0 then return "---" end
 return note_names[note%12+1]..flr(note/12)
end

function sfx_speed()
 return mid(1,flr(1920/bpm+0.5),255)
end

function write_note(addr,note,wave,volume,effect)
 local packed=0
 if note>=0 then
  packed=note+wave*64+volume*512+effect*4096
 end
 poke2(addr,packed)
end

function rebuild_track(ch)
 local base=0x3200+(ch-1)*68
 for step=1,32 do
  local note=step<=steps and notes[ch][step] or -1
  write_note(base+(step-1)*2,note,waves[ch],volumes[ch],effects[ch])
 end
 poke(base+64,0)
 poke(base+65,sfx_speed())
 poke(base+66,0)
 poke(base+67,steps)
end

function rebuild_all()
 for ch=1,tracks do rebuild_track(ch) end
end

function start_song()
 rebuild_all()
 -- Let the SFX loop markers drive playback. Supplying a length here makes
 -- PICO-8 stop after exactly one phrase even when loop start/end are set.
 for ch=0,tracks-1 do sfx(ch,ch) end
 playing=true
 play_tick=0
 play_step=1
 say("playing")
end

function stop_song()
 for ch=0,tracks-1 do sfx(-1,ch) end
 playing=false
 say("stopped")
end

function toggle_song()
 if playing then stop_song() else start_song() end
end

function audition(ch,note)
 if playing or note<0 then return end
 local base=0x3200+4*68
 write_note(base,note,waves[ch],volumes[ch],effects[ch])
 for i=1,31 do poke2(base+i*2,0) end
 poke(base+65,8)
 poke(base+66,0)
 poke(base+67,0)
 sfx(4,3,0,1)
end

function change_note(delta)
 local note=notes[cursor_ch][cursor_step]
 if note<0 then note=last_notes[cursor_ch]
 else note=mid(0,note+delta,62) end
 notes[cursor_ch][cursor_step]=note
 last_notes[cursor_ch]=note
 rebuild_track(cursor_ch)
 publish_gpio()
 audition(cursor_ch,note)
end

function toggle_rest()
 local note=notes[cursor_ch][cursor_step]
 if note<0 then
  notes[cursor_ch][cursor_step]=last_notes[cursor_ch]
  audition(cursor_ch,last_notes[cursor_ch])
 else
  last_notes[cursor_ch]=note
  notes[cursor_ch][cursor_step]=-1
 end
 rebuild_track(cursor_ch)
 publish_gpio()
end

function say(text)
 notice=text
 notice_tick=120
end

function save_song()
 local base=save_addr+(slot-1)*save_size
 poke(base,199)
 poke(base+1,bpm)
 local p=base+2
 for ch=1,tracks do
  poke(p,waves[ch])
  poke(p+1,volumes[ch])
  poke(p+2,effects[ch])
  p+=3
 end
 for ch=1,tracks do
  for step=1,steps do
   poke(p,notes[ch][step]<0 and 63 or notes[ch][step])
   p+=1
  end
 end
 -- dset flushes the entire persistent cartdata block
 dset(63,dget(63))
 say("saved slot "..slot)
end

function load_song(show_notice)
 local base=save_addr+(slot-1)*save_size
 if peek(base)!=199 then
  if show_notice then say("slot "..slot.." is empty") end
  return false
 end
 bpm=mid(60,peek(base+1),240)
 local p=base+2
 for ch=1,tracks do
  waves[ch]=peek(p)%8 volumes[ch]=peek(p+1)%8 effects[ch]=peek(p+2)%8
  p+=3
 end
 for ch=1,tracks do
  for step=1,steps do
   local note=peek(p)%64
   notes[ch][step]=note==63 and -1 or note
   if note<63 then last_notes[ch]=note end
   p+=1
  end
 end
 rebuild_all()
 publish_gpio()
 if show_notice then say("loaded slot "..slot) end
 return true
end

function publish_gpio()
 local p=gpio_addr
 poke(p,80)
 poke(p+1,84)
 poke(p+2,1)
 poke(p+3,bpm)
 p+=4
 for ch=1,tracks do
  poke(p,waves[ch])
  poke(p+1,volumes[ch])
  poke(p+2,effects[ch])
  p+=3
 end
 for ch=1,tracks do
  for step=1,steps do
   poke(p,notes[ch][step]<0 and 63 or notes[ch][step])
   p+=1
  end
 end
 poke(gpio_addr+127,(peek(gpio_addr+127)+1)%256)
end

function request_export(secondary)
 publish_gpio()
 poke(gpio_addr+125,secondary and 2 or 1)
 export_counter=(export_counter+1)%256
 poke(gpio_addr+126,export_counter)
 say(secondary and "wav downloading" or "json downloading")
end

function activate_menu(secondary)
 local name=menu_names[menu_item]
 if name=="play" then toggle_song()
 elseif name=="save" and not secondary then save_song()
 elseif name=="load" and not secondary then load_song(true)
 elseif name=="slot" then
  slot=((slot-1+(secondary and -1 or 1))%slot_count)+1
  say("slot "..slot)
 elseif name=="bpm" then
 bpm=mid(60,bpm+(secondary and -5 or 5),240)
  rebuild_all()
  publish_gpio()
  say(bpm.." bpm")
  if playing then start_song() end
 elseif name=="wave" then
 waves[cursor_ch]=(waves[cursor_ch]+(secondary and 7 or 1))%8
  rebuild_track(cursor_ch)
  publish_gpio()
  say(wave_names[waves[cursor_ch]+1])
 elseif name=="vol" then
  volumes[cursor_ch]=mid(0,volumes[cursor_ch]+(secondary and -1 or 1),7)
  rebuild_track(cursor_ch)
  publish_gpio()
  say("volume "..volumes[cursor_ch])
 elseif name=="fx" then
  effects[cursor_ch]=(effects[cursor_ch]+(secondary and 7 or 1))%8
  rebuild_track(cursor_ch)
  publish_gpio()
  say("effect "..effects[cursor_ch])
 elseif name=="export" then
  request_export(secondary)
 end
end

function update_playhead()
 if not playing then return end
 play_tick+=1
 local frames=max(1,sfx_speed()*60/128)
 play_step=flr(play_tick/frames)%steps+1
end

function _update60()
 update_playhead()
 if notice_tick>0 then notice_tick-=1 end

 if cursor_step<=steps then
  if btn(4) and btn(5) and (btnp(4) or btnp(5)) then
   toggle_rest()
  elseif btnp(4) then change_note(1)
  elseif btnp(5) then change_note(-1)
  elseif btnp(0) then cursor_ch=max(1,cursor_ch-1)
  elseif btnp(1) then cursor_ch=min(tracks,cursor_ch+1)
  elseif btnp(2) then cursor_step=max(1,cursor_step-1)
  elseif btnp(3) then cursor_step+=1
  end
 else
  if btnp(0) then menu_item=(menu_item+#menu_names-2)%#menu_names+1
  elseif btnp(1) then menu_item=menu_item%#menu_names+1
  elseif btnp(2) then cursor_step=steps
  elseif btnp(4) then activate_menu(false)
  elseif btnp(5) then activate_menu(true)
  end
 end
end

function draw_header()
 rectfill(0,0,127,8,1)
 print("pocket tracker",2,2,7)
 print(bpm.." bpm",75,2,12)
 print("s"..slot,112,2,10)
end

function draw_grid()
 for ch=1,tracks do
  local x=15+(ch-1)*28
  print("ch"..ch,x,10,ch+7)
 end
 for step=1,steps do
  local y=16+(step-1)*5.7
  if playing and play_step==step then rectfill(0,y-1,127,y+4,1) end
  print((step<10 and "0" or "")..step,1,y,5)
  for ch=1,tracks do
   local x=15+(ch-1)*28
   if cursor_step==step and cursor_ch==ch then
    rectfill(x-2,y-1,x+15,y+4,5)
   end
   local col=notes[ch][step]<0 and 6 or ch+7
   print(note_word(notes[ch][step]),x,y,col)
  end
 end
end

function draw_menu()
 rectfill(0,108,127,127,1)
 line(0,108,127,108,5)
 if cursor_step>steps then rect(1,110,126,126,10) end
 local name=menu_names[menu_item]
 print("< "..name.." >",44-#name*2,112,7)
 local detail="o select / x alternate"
 if name=="play" then detail=playing and "o/x stop" or "o/x start"
 elseif name=="slot" then detail="o next / x previous"
 elseif name=="bpm" then detail="o +5 / x -5"
 elseif name=="wave" then detail="ch"..cursor_ch.." "..wave_names[waves[cursor_ch]+1]
 elseif name=="vol" then detail="ch"..cursor_ch.." level "..volumes[cursor_ch]
 elseif name=="fx" then detail="ch"..cursor_ch.." effect "..effects[cursor_ch]
 elseif name=="export" then detail="o json / x wav" end
 if notice_tick>0 then detail=notice end
 print(detail,64-#detail*2,120,6)
end

function _draw()
 cls(0)
 draw_header()
 draw_grid()
 draw_menu()
end
