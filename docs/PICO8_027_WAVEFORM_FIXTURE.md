# PICO-8 0.2.7 waveform sample fixture

`tests/fixtures/pico8-027-waveform.p8` is a version-43 text cartridge built in
PICO-8's native `__sfx__` representation and loaded by the exact PICO-8 0.2.7
runtime used for this project. The executable cartridge test reloads its audio
RAM directly, classifies SFX 0 as a waveform, and checks the complete byte
pattern and bank checksum before exercising the editor.

SFX 0 contains all 64 authored waveform sample bytes. The deterministic
sequence is `(index * 37 + 11) & 0xff`, with four explicit boundary vectors:

| Sample | Raw byte | Signed amplitude |
|---:|---:|---:|
| `00` | `0x00` | 0 |
| `01` | `0x7f` | 127 |
| `3e` | `0x80` | -128 |
| `3f` | `0xff` | -1 |

Its metadata bytes are `00 10 80 00`; bit 7 of metadata byte 2 is the native
waveform classification bit. SFX 8 row 0 is the exact conventional word
`0x8a18`: pitch 24, custom instrument 0, volume 5, effect 0. Pattern 0 points
channel 1 at SFX 8, providing the fixture's audible custom-waveform reference
without introducing a scratch preview path.

Checksums recorded on 2026-08-27:

- PICO-8 executable SHA-256: `b07e76cd6a0336508200be75d67cd893ef90a0a00408163fd33af43ba006eab0`
- Fixture SHA-256: `da938e273afccc4cbdb0b48138669a99d23c0ed11d06147b3005f23dc5243b64`
- Native audio-bank CRC-16/CCITT-FALSE: `0x20da`
- Runtime: PICO-8 0.2.7; text-cartridge version 43
- Semantic reference: [official PICO-8 manual, “SFX Editor”](https://www.lexaloffle.com/dl/docs/pico-8_manual.html#SFX_Editor)

The `.p8` five-digit row representation remains byte-bijective: its pitch,
instrument/custom, volume, and effect digits collectively carry all 16 bits of
each adjacent sample pair. The JSON and both authored/materialized `.p8` codec
tests therefore require the complete 68-byte waveform slot to round-trip
byte-exactly; no browser-side waveform editor is involved.
