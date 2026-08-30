# Open product questions

These choices are deliberately non-blocking. Each arc uses a safe, reversible
default until the product direction is revisited.

## Native project seed

The main cartridge currently embeds the reviewed Starfield Track 1 fixture as
its canonical 4,608-byte native bank. A future project picker may make another
seed the default; changing it must remain an explicit full-bank operation.

## Six-button SONG controls

SONG is the primary screen. O enters the selected channel's SFX view, tap X
keeps the user in SONG, Hold O opens the project palette, and Hold X opens the
SONG context palette. The context palette edits SFX/mute/flow as a staged
full-byte transaction: O commits and X cancels. Pattern and channel navigation
clamps at their native bounds; SFX values wrap from `3f` to `00`.

## SONG audition mix

- **Default now:** the SONG mix row applies a runtime-only native channel mask:
  all channels, mute the selected channel, or solo the selected channel. It
  defaults to all, survives transport stops and SFX-preview resume for the
  session, and is never saved or exported. Applying while playing restarts the
  observed native pattern at row 0. Text status reports both the selected mode
  and active channels from `stat(46..49)`; authored pattern mute bits remain a
  separate byte edit.
- **Revisit:** persist mixer preferences, preserve the current row across mask
  changes, or add a broader mixer only as a deliberately designed project/UI
  feature.

## Native project I/O

The browser uses one namespaced last-known-good slot and native PICO-8 uses the
fixed, visible, pre-existing `pocket-tracker-data.p8` slot. Both store the
complete 4,608-byte authored bank plus project name, revision, one exact
profile-none or Track-1 profile tuple, and source selection in a fixed
checksummed v2 envelope. Legacy JSON
and WAV actions remain disabled; the old 78-byte sketch format is never used by
save or load.

The native slot keeps two journal records with modulo-16-bit generations,
wrapper/envelope/bank CRC validation, older-record overwrite, and mandatory
post-write read-back. Corrupt-newest loads fall back to the prior valid record;
missing/cancelled/both-invalid operations do not change the current project.

The browser re-imports its own authored `.p8` when complete unique audio
sections and the exact checksummed PTP2 sidecar are present. Headerless generic
and materialized carts with unique valid audio sections become profile-none,
using deterministic filename metadata and no inferred external Lua transform.
Malformed/duplicate sidecars reject.

- **M4 default:** the browser library keeps up to eight projects and four
  validated revisions per project. It migrates the legacy browser slot once,
  stages selections back through that same slot, and never commits live bytes
  outside tracker Load. Corrupt-newest recovery is non-mutating; quota,
  read-back, stale confirmation, and cancelled deletion/rollover preserve
  durable and live state. Recovered/malformed libraries are read-only until an
  explicit library-only reset, and library work pauses during GPIO transfer.
- **Revisit:** editable library names, pinning revisions, import/export of the
  whole library, and more elaborate recovery management require separately
  designed ownership and quota policies. Concurrent multi-tab writers also
  require cross-document locking and are outside the first bounded M4 arc.

## Legacy sketch

Nick chose the native-first design on 2026-08-23. The four-channel,
sixteen-step grid is removed from the shipped cartridge now that SONG and SFX
fully replace its navigation and editing. Its old behavior remains only in
`tests/legacy_tracker.lua` so regression tests do not enlarge production code.

## SFX handoff

Arc 2 replaces the handoff with the native 64-by-32 editor while preserving the
selected SONG pattern/channel and SFX number on return.

## SFX row clipboard

- **Default now:** conventional SFX support an operation-scoped inclusive row
  selection for copy and clear, plus an exact validated paste destination. The
  session-only clipboard owns 1–32 authored 16-bit words and is reusable across
  conventional slots until the next copy or reboot. Paste and clear are each
  one atomic transaction in the existing one-level Undo/Redo history. Metadata,
  waveform ranges, persistence, and browser/system clipboards are excluded.
- **Revisit:** pattern/channel copy, whole-SFX metadata, insert/delete/shift,
  persistent clipboards, or waveform operations only as separately designed
  editor features with their own ownership and transport semantics.

## Waveform SFX editing

- **Default now:** classified native waveform slots expose all 64 signed sample
  bytes as 32 raw-hex pairs. Up/Down selects a pair, Left/Right selects its
  even/odd byte, and the existing wrapping scalar editor commits one exact byte
  through atomic Undo/Redo. Metadata remains raw and inspectable; the native
  bass toggle is one masked off/on edit that preserves all other bits. Invalid,
  cancel, no-op, and waveform-loss actions preserve history and transport.
  SFX 0–7 also expose the native notes/wave toggle as a masked edit of metadata
  byte 66 bit 7. It reinterprets the same 64 bytes without conversion; Undo/Redo
  and active playback use the shared authored/profile-safe transaction.
  The waveform Filters panel exposes fixture-proven DETUNE, REVERB, and DAMPEN
  levels only. Each edit owns its `8/24/72` mixed-radix digit in metadata byte
  64; waveform NOIZ/BUZZ and unsupported raw states remain read-only.
  Track-1 playback and materialized export snapshot profile-range waveforms but
  skip their volume transform, preserving every sample and metadata byte.
- **Revisit:** other waveform metadata semantics, waveform NOIZ/BUZZ, range
  copy/paste/clear, and direct preview require separate ownership and audition
  designs; never reinterpret sample bytes as packed note words.

## SFX audition channel

- **Default now:** M1.3 snapshots authored SFX 63 outside the bank, uses it as
  a reversible preview slot on mixer channel 3, and restores all 68 bytes on
  stop. Song audio/profile state is stopped and restored before preview; an
  interrupted song optionally resumes afterward. SFX 1-4 are never rewritten.
- **Revisit:** waveform-slot audition remains unavailable until a reserved
  waveform-compatible preview path can preserve custom-instrument references.

## Rest restoration seed

- **Default now:** clearing a row remembers that exact word per native address;
  restoring it is byte-exact. A never-before-authored empty row restores to
  pitch 24, built instrument 0, volume 5, and effect 0 (`0x0a18`).
- **Revisit:** replace the fallback only when a project-level last-note or
  instrument policy exists; remembered row words remain authoritative.

## Pattern flag byte

Bit 7 means loop-start on channel 1, loop-back on channel 2, and stop on
channel 3. The same bit in channel 4 is reserved and shown as `r`; Arc 1 never
changes it. Muting and SFX edits always preserve all unrelated bits.
