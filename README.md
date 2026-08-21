# Pocket Tracker

A standalone PICO-8 music sketchpad designed for handheld and mobile use. Its
native SONG screen exposes all 64 PICO-8 music patterns, four SFX assignments,
mute bits, and loop/back/stop flags without requiring a keyboard or mouse.

The original four-channel, sixteen-step sketch remains available as a
read-only-bank prototype reference. It is no longer allowed to rebuild or
audition over the canonical PICO-8 audio bank.

## Controls

- D-pad: move around the pattern; Down from step 16 opens the action menu.
- Tap O: raise the selected note. Tap X: lower it.
- Hold O: open the Start palette for playback, save/load, and export.
- Hold X: open the Select palette for the current step/channel parameters;
  choose **Song patterns** to enter the native SONG screen.
  Use Up/Down to choose, Left/Right to adjust, O to use, and X to close.
- O+X: toggle the selected step between a note and a rest.
- In the action menu, Left/Right chooses an action, O performs its primary
  action, X performs the alternate action, and Up returns to the pattern.
- In SONG, Up/Down chooses pattern `00`–`3f`, Left/Right chooses channel,
  O opens the selected channel's native SFX, and tap X returns.
- Hold X in SONG for SFX/mute/flow edits, one-step undo, and native playback.
  Left/Right stages a value, O commits, and X cancels without changing bytes.
- In SFX, Up/Down scrolls all 32 rows and Left/Right selects pitch,
  instrument, built/custom mode, volume, or effect. O edits and tap X returns
  to the same SONG position. Hold X opens rest, undo, metadata, and SFX-slot
  navigation. Metadata exposes all four raw bytes plus speed and loop/LEN.
  Waveform slots remain byte-exact, visibly read-only native data.

SONG playback uses native `music(pattern)` and the reversible Track 1 playback
profile. Save/load/JSON/WAV actions remain visibly disabled until the lossless
4,608-byte native-bank project path lands; the older 78-byte format cannot
safely represent native edits.

## Browser exports

The mobile wrapper still contains the legacy 78-byte JSON/WAV bridge. Those
actions are disabled in the cartridge while the native-bank replacement is in
progress because they are not lossless for SONG edits:

- JSON containing the exact notes, tempo, waveform, volume, and effect data.
- A rendered WAV preview suitable for sharing or dropping into a DAW.

The WAV renderer approximates PICO-8's eight waveform families. Neither legacy
format should be treated as a native-bank project export.

## Build and test

PICO-8 must be installed separately. From this directory:

```sh
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy /path/to/pico8 \
  pocket-tracker.p8 -export tracker.html

timeout 6s env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  /path/to/pico8 -run tests/smoke.p8
```

`tracker.html` and `tracker.js` are generated. `audio_bank.lua` is the native
bank boundary, `song_ui.lua` owns SONG, `sfx_ui.lua` owns the native SFX
editor, and `tracker.lua` retains the legacy sketch plus shared six-button
input. `index.html` and `mobile.js` still contain the disabled legacy browser
bridge.
