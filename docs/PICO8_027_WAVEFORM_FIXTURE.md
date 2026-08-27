# PICO-8 0.2.7 waveform sample fixture

`tests/fixtures/pico8-027-waveform.p8` is the original version-43 waveform
sample cartridge. The paired
`tests/fixtures/pico8-027-waveform-bass-off.p8` and
`tests/fixtures/pico8-027-waveform-bass-on.p8` were each saved by the exact
native PICO-8 0.2.7 editor after clicking its BASS toggle off and on. The two
files normalize only the native saver's trailing blank line and are otherwise
byte-identical except for one ASCII nibble in SFX 0,
which decodes to metadata byte 65 changing `0x10` to `0x11`. Their complete
audio banks therefore differ only by bit 0 of that byte; all 64 samples,
waveform classification, other metadata, the conventional reference, patterns,
and unused slots are identical.

SFX 0 contains all 64 authored waveform sample bytes. The deterministic
sequence is `(index * 37 + 11) & 0xff`, with four explicit boundary vectors:

| Sample | Raw byte | Signed amplitude |
|---:|---:|---:|
| `00` | `0x00` | 0 |
| `01` | `0x7f` | 127 |
| `3e` | `0x80` | -128 |
| `3f` | `0xff` | -1 |

The off fixture's metadata bytes are `00 10 80 00`; the on fixture's are
`00 11 80 00`. Bit 0 of metadata byte 1 is therefore the native bass flag, and
bit 7 of metadata byte 2 is the unchanged waveform classification bit. SFX 8
row 0 is the exact conventional word
`0x8a18`: pitch 24, custom instrument 0, volume 5, effect 0. Pattern 0 points
channel 1 at SFX 8, providing the fixture's audible custom-waveform reference
without introducing a scratch preview path.

Checksums recorded on 2026-08-27:

- PICO-8 executable SHA-256: `b07e76cd6a0336508200be75d67cd893ef90a0a00408163fd33af43ba006eab0`
- Original fixture SHA-256: `da938e273afccc4cbdb0b48138669a99d23c0ed11d06147b3005f23dc5243b64`
- Native bass-off fixture SHA-256: `da938e273afccc4cbdb0b48138669a99d23c0ed11d06147b3005f23dc5243b64`
- Native bass-on fixture SHA-256: `fc5d7b668dccf7315f45012d8cec690dac18f9f3a31d819feaaa92af9e9ec3d5`
- Bass-off audio-bank CRC-16/CCITT-FALSE: `0x20da`
- Bass-on audio-bank CRC-16/CCITT-FALSE: `0x6e12`
- Runtime: PICO-8 0.2.7; text-cartridge version 43
- Semantic reference: [official PICO-8 manual, “SFX Editor”](https://www.lexaloffle.com/dl/docs/pico-8_manual.html#SFX_Editor)

The `.p8` five-digit row representation remains byte-bijective: its pitch,
instrument/custom, volume, and effect digits collectively carry all 16 bits of
each adjacent sample pair. The JSON and both authored/materialized `.p8` codec
tests therefore require the complete 68-byte waveform slot to round-trip
byte-exactly; no browser-side waveform editor is involved.
