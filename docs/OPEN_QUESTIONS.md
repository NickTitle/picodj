# Open product questions

These choices are deliberately non-blocking. Each arc uses a safe, reversible
default until the product direction is revisited.

## Native project seed

The main cartridge currently embeds the reviewed Starfield Track 1 fixture as
its canonical 4,608-byte native bank. A future project picker may make another
seed the default; changing it must remain an explicit full-bank operation.

## Six-button SONG controls

Tap X returns to the legacy sketch and Hold X opens the SONG context palette.
O enters the selected channel's SFX view. The palette edits SFX/mute/flow as a
staged full-byte transaction: O commits and X cancels. Pattern and channel
navigation clamps at their native bounds; SFX values wrap from `3f` to `00`.

## Native project I/O

Legacy slots, JSON, WAV, and GPIO transfers cover only the old 78-byte sketch
and are disabled with a persistent `native i/o pending` error. They must not be
re-enabled until the M1.4 lossless 4,608-byte bank/envelope path is available.

## Legacy sketch

The four-channel, sixteen-step grid remains visible as a reference, but all of
its bank rebuild and audition writes are quarantined. It is not an alternate
authoritative editor. A later HOME design can remove it after native SONG and
SFX navigation fully replace it.

## SFX handoff

Arc 2 replaces the handoff with the native 64-by-32 editor while preserving the
selected SONG pattern/channel and SFX number on return.

## Waveform SFX editing

- **Default now:** native waveform slots are identifiable and their raw
  metadata remains inspectable, but the 64 sample bytes and metadata are
  read-only. Note and semantic metadata actions fail visibly without changing
  dirty/revision state.
- **Revisit:** add a waveform-specific sample editor only with byte-level
  fixtures and a six-button interaction design; do not reinterpret samples as
  packed note words.

## SFX audition channel

- **Default now:** Arc 2 edits and preserves native bytes but does not audition
  a row. SONG playback remains native and faithful.
- **Revisit:** M1.3 must reserve and prove a preview channel that never
  overwrites authored SFX 1-4 or leaks the temporary playback profile.

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
