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

M1.4A uses one namespaced browser last-known-good slot as the safe reversible
default while the native data-cart destination remains undecided. It stores the
complete 4,608-byte authored bank plus project name, revision, Track 1 playback
profile, and source selection in a fixed checksummed v2 envelope. Legacy JSON
and WAV actions remain disabled; the old 78-byte sketch format is never used by
save or load.

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
  waveform samples, persistence, and browser/system clipboards are excluded.
- **Revisit:** pattern/channel copy, whole-SFX metadata, insert/delete/shift,
  persistent clipboards, or waveform operations only as separately designed
  editor features with their own ownership and transport semantics.

## Waveform SFX editing

- **Default now:** native waveform slots are identifiable and their raw
  metadata remains inspectable, but the 64 sample bytes and metadata are
  read-only. Note and semantic metadata actions fail visibly without changing
  dirty/revision state.
- **Revisit:** add a waveform-specific sample editor only with byte-level
  fixtures and a six-button interaction design; do not reinterpret samples as
  packed note words.

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
