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
  Hold X also previews the selected row from row mode or the complete SFX from
  metadata mode through reserved SFX 63 on mixer channel 3; the authored slot
  is restored byte-for-byte on stop.

SONG playback uses native `music(pattern)` and the reversible Track 1 playback
profile. Optional follow reads PICO-8's native `stat(46..57)` mixer state.
Save and load use one browser last-known-good slot containing a checksummed
v2 envelope and the complete 4,608-byte authored bank. Save is reported only
after browser-storage read-back succeeds; load stages every page and commits
only after the frame, envelope, and bank checksums agree. JSON/WAV actions
inside the cartridge remain disabled because the older 78-byte format cannot
safely represent native edits.

## Browser exports

The browser shell's **Files** panel operates only on the checksum-verified
last-known-good project slot. Save in the tracker first, then choose one of:

- deterministic Pocket Tracker JSON containing the exact 4,608-byte authored
  bank, project metadata, provenance, revision, and playback profile;
- valid `.p8` audio in **authored + profile** mode, with the exact bank and a
  Pocket Tracker sidecar header;
- valid `.p8` audio in **materialized playback** mode, with the Track 1 gain
  profile applied only to exported SFX 1–4.

JSON import validates every field, range, checksum, and exact key set before it
atomically replaces the durable browser slot. It never writes live cartridge
RAM; choose **Load** in the tracker to use the existing staged, checksum-gated
commit path. Invalid files and storage faults preserve both live and durable
state. Bridge frames, undo, snapshots, and temporary playback bytes are never
serialized.

## Build and test

PICO-8 must be installed separately. From this directory:

```sh
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy /path/to/pico8 \
  pocket-tracker.p8 -export tracker.html

timeout 6s env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  /path/to/pico8 -run tests/smoke.p8

env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  /path/to/pico8 -x tests/size_budget.p8

node tests/mobile_hold.js
node tests/project_io.js
node tests/file_io.js
```

`tracker.html` and `tracker.js` are generated. `audio_bank.lua` is the native
bank boundary, `song_ui.lua` owns SONG, `sfx_ui.lua` owns the native SFX
editor, and `tracker.lua` retains the legacy sketch plus shared six-button
input. `index.html` and `mobile.js` own the lossless browser file codecs and
controls; they do not synthesize or edit authoritative audio.

`tests/size_budget.p8` compiles the exact five-file production include graph
plus a calibrated 261-token probe. Its pass marker therefore gates the shipped
cart below 7,932 tokens, leaving more than 256 tokens below PICO-8's 8,192-token
ceiling.
