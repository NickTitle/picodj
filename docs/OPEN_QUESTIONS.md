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

Arc 1's SFX screen is deliberately read-only and records the selected pattern,
channel, and SFX number. Arc 2 will replace it with the native 64-by-32 editor.

## Pattern flag byte

Bit 7 means loop-start on channel 1, loop-back on channel 2, and stop on
channel 3. The same bit in channel 4 is reserved and shown as `r`; Arc 1 never
changes it. Muting and SFX edits always preserve all unrelated bits.
