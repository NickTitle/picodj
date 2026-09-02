# Pocket Tracker

A standalone PICO-8 music sketchpad designed for handheld and mobile use. Its
native SONG screen exposes all 64 PICO-8 music patterns, four SFX assignments,
mute bits, and loop/back/stop flags without requiring a keyboard or mouse.

The native SONG/SFX tracker is the primary and only shipped editor. The former
four-channel, sixteen-step sketch remains only as a test fixture for regression
coverage; it is not included in the production cartridge.

## Controls

- The cartridge opens directly in SONG. Up/Down chooses pattern `00`–`3f`,
  Left/Right chooses channel, and O opens the selected channel's native SFX.
- Hold O from either native screen opens the project palette for playback,
  browser-slot save/load, and fixed data-cart save/load. Up/Down chooses, O
  activates, and X closes.
- Hold X in SONG for SFX/mute/flow edits, session-only audition mix,
  one-level undo/redo, and native playback. On the mix row, Left/Right stages
  all, mute selected channel, or solo selected channel; O applies and X
  cancels. Other edits retain their staged O-commit/X-cancel behavior.
- In SFX, Up/Down scrolls all 32 rows and Left/Right selects pitch,
  instrument, built/custom mode, volume, or effect. O edits and tap X returns
  to the same SONG position. Hold X opens row operations, undo/redo, metadata,
  named conventional filters, and SFX-slot navigation. Row operations include
  the existing one-row rest toggle plus inclusive copy, paste, and clear:
  Up/Down selects a range, O confirms, and X cancels. Paste shows and validates
  its exact destination interval before changing anything. Metadata exposes all
  four raw bytes plus speed and loop/LEN.
  Waveform slots remain byte-exact, visibly read-only native data.
  Hold X also previews the selected row from row mode or the complete SFX from
  metadata mode through reserved SFX 63 on mixer channel 3; the authored slot
  is restored byte-for-byte on stop.
- O+X toggles the selected SFX row between a note and a rest.

Native D-pad navigation and staged scalar edits use a deterministic 60 Hz
repeat cadence: one change on press frame 1, no repeats through frame 15,
one repeat every four frames from frame 16 through frame 44, then one every
two frames from frame 48 onward. Release restarts the cadence. O/X actions,
chords, action-release gates, context and row-operation menus, confirmations,
and destructive commands keep their existing non-accelerated input paths and
clear any held D-pad state. Browser and touch controls are unchanged.

SONG playback uses native `music(pattern, nil, channel_mask)`. Track-1 projects
apply the reversible `+2` profile; profile-none imports play authored bytes raw
with no snapshot or gain writes. The status always shows `+2` or `raw`.
Audition mix defaults to all channels, survives
stop/start and SFX-preview resume for the session, and never changes authored
mute bits or saved/exported project data. Applying a new mix while playing
restarts the observed pattern at row 0. SONG shows `all`, `mN`, or `sN` plus a
textual four-channel active mask derived from PICO-8's native `stat(46..49)`;
optional follow retains the selected-channel row and native pattern behavior.
Save and load use one browser last-known-good slot containing a checksummed
v2 envelope and the complete 4,608-byte authored bank. Save is reported only
after browser-storage read-back succeeds; load stages every page and commits
only after the frame, envelope, and bank checksums agree. JSON/WAV actions
inside the cartridge remain disabled because the older 78-byte format cannot
safely represent native edits.

Native **Save data cart** / **Load data cart** use the shipped, pre-existing
`pocket-tracker-data.p8` slot. Two 4,680-byte journal records alternate inside
the cart's writable data: an 8-byte magic/generation/CRC wrapper followed by
the exact 4,672-byte PTP2 envelope. Save overwrites only the older or invalid
record and reports success only after reloading and fully validating the new
generation. Load chooses the newest valid modulo-16-bit generation, falls back
when the newest record is corrupt, stages the complete project, and commits it
atomically. Missing, cancelled, invalid, and read-back-failed operations leave
the authored project and the prior rollback record intact; attempted I/O may
stop playback or preview.

The row clipboard holds 1–32 exact authored words, is reusable across
conventional SFX slots, and lasts until the next copy or reboot. It is internal
to the session: save, load, browser storage, and export never include it.
Undo and redo preserve the exact edited byte span and its prior dirty state;
an entire paste or clear is one transaction. A new real edit replaces redo
history. Selection, copy, cancel, rejection, and no-op preserve it. Successful
save and load establish a new clean baseline and clear history; failed
transfers leave history available.

## Browser exports

The browser shell's **Files** panel operates only on the checksum-verified
last-known-good project slot. Save in the tracker first, then choose one of:

- deterministic Pocket Tracker JSON containing the exact 4,608-byte authored
  bank, project metadata, provenance, revision, and optional playback profile;
- valid `.p8` audio in **authored + profile** mode, with the exact bank and a
  Pocket Tracker sidecar header;
- valid `.p8` audio in **materialized playback** mode, with the Track 1 gain
  profile applied only to conventional rows in exported SFX 1–4. Classified
  waveform slots keep all 64 samples and all four metadata bytes exact.

JSON import validates every field, range, checksum, and exact key set. The same
Files action re-imports Pocket Tracker **authored + profile** `.p8` exports by
requiring complete unique audio sections and the exact lossless sidecar, then
validating the reconstructed envelope without repair. Headerless generic carts
with unique 0–64-line audio sections, including materialized exports, import as
an explicit profile-none project: no external Lua transform is inferred, and
bounded project/provenance text is derived deterministically from the filename.
Malformed or duplicate Pocket Tracker headers always reject rather than
downgrading to headerless import.
Successful imports atomically replace the durable browser slot after read-back
and never write live cartridge RAM; choose **Load** in the tracker to use the
existing staged, checksum-gated commit path. Invalid files and storage faults
preserve both live and durable state. Bridge frames, undo, snapshots, and
temporary playback bytes are never serialized.

## Browser project library

The Files panel also provides a browser-only project library. It keeps at most
eight projects and the newest four validated revisions of each project under
`pocket-tracker:library:v1`. Adding a fifth revision requires a confirmation
that names the project and exact saved copy to evict; adding a ninth project is
rejected without evicting anything. Existing users'
valid `pocket-tracker:project:v2:last-known-good` slot is copied into the library
once when no library record exists.
The deterministic library record is capped at 302,213 ASCII characters, the
maximum possible for 32 complete envelopes and ten-digit IDs.

The compatibility slot remains unchanged: file import/export and the GPIO
bridge still use only that last-known-good key. **Stage revision for tracker
Load** copies a selected validated revision into the compatibility slot but
does not write live cartridge RAM. Choose **Load** in the tracker to validate
and commit it. Corrupt newer library copies fall back to older valid revisions
without silently rewriting storage; recovered or malformed libraries remain
read-only until an explicit library-only reset. Quota, read-back, stale source,
and cancelled deletion/rollover failures preserve the library, compatibility
slot, and live tracker state. Library staging and mutation are disabled during
an active GPIO save or load.
Project and revision selection uses labelled native controls for touch and
keyboard access; every deletion requires confirmation. This first arc supports
one active writer tab; concurrent multi-tab writes are not serialized.

## Browser help

The browser shell's **Help** button opens a responsive modal guide to SONG,
SFX, accelerated input, and browser project recovery. Native button activation
works with touch and keyboard. While help is open, the tracker, Files panel,
and other background controls are inert; focus is trapped inside the dialog.
Close, Escape, and native dialog cancellation restore both the prior inert
state and focus to the opener. Opening and closing help is DOM-only and never
reads or writes GPIO, browser storage, or live project state.

## Build and test

PICO-8 must be installed separately. From this directory:

```sh
PICO8_BIN=/path/to/pico8 \
PLAYWRIGHT_MODULE=/path/to/playwright \
tests/run_all.sh
```

The full runner exercises all 17 native carts in their required headless,
isolated-data, or real-mixer shapes; checks both browser JavaScript files; runs
all five Node/browser suites including real Chromium viewports; measures the exact
calibrated production token count; performs a fresh export; and gates source,
raw/compressed PXA, generated hashes, and final worktree cleanliness. Its
defaults match this repository's maintainer workstation. Individual commands
remain available for focused diagnosis:

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
node tests/help_dialog.js
PLAYWRIGHT_MODULE=/path/to/playwright node tests/help_viewport.js

cp pocket-tracker-data.p8 tests/fixtures/pocket-tracker-data-test.p8
timeout 30s env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  /path/to/pico8 -run tests/native_store.p8
rm tests/fixtures/pocket-tracker-data-test.p8
```

`tracker.html` and `tracker.js` are generated. `audio_bank.lua` is the native
bank boundary, `song_ui.lua` owns SONG, `sfx_ui.lua` owns the native SFX
editor, and `tracker.lua` owns shared native six-button input and menus.
`index.html` and `mobile.js` own the lossless browser file codecs and controls;
they do not synthesize or edit authoritative audio.

The SFX filter panel exposes NOIZ, BUZZ, and the two levels of DETUNE,
REVERB, and DAMPEN. Its byte codec is derived from the checksummed native
PICO-8 0.2.7 fixture documented in `docs/PICO8_027_FILTER_FIXTURE.md`;
fixture-unsupported filter states remain visibly read-only. Classified
waveform SFX expose only the fixture-backed DETUNE, REVERB, and DAMPEN fields;
waveform NOIZ and BUZZ remain unavailable.

Classified waveform SFX 0–7 expose their 64 signed sample bytes as 32 raw-hex
pairs. Up/Down selects a pair, Left/Right selects its even or odd byte, and O
opens the same wrapping scalar editor used elsewhere. The footer names the
exact sample index and signed amplitude. Hold X → Metadata shows all four raw
bytes and exposes the native `bass off/on` bit as one masked scalar edit;
unknown bits remain preserved. For SFX 0–7 the same panel also exposes the
fixture-proven `mode notes/wave` bit without converting any of the other 67
slot bytes. Their Filters panel edits the three supported ternary digits in
metadata byte 64 while preserving NOIZ/BUZZ bits and all other slot bytes.
Notes mode restores conventional preview and row operations;
direct waveform preview remains unavailable, so a conventional note
referencing the waveform is the audible path. The paired native 0.2.7 fixtures
and checksums are documented in
`docs/PICO8_027_WAVEFORM_FIXTURE.md`.

`tests/size_budget.p8` compiles the exact five-file production include graph
plus a calibrated 1,024-token probe. Its pass marker gates the completed M3
and M4 cart at or below 7,168 tokens. The completed M4 production graph is
7,082 tokens, 86 below that release gate and 1,110 below PICO-8's 8,192-token
ceiling. Fresh export additionally gates raw PXA at 65,535 bytes and compressed
PXA at 12,288 bytes; the M4 closure measures 41,913 raw / 11,613 compressed.
