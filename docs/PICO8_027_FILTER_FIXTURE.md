# PICO-8 0.2.7 SFX filter fixture

`tests/fixtures/pico8-027-filters.p8` was created and saved by the native
PICO-8 0.2.7 SFX editor on 2026-08-27. The editor was launched against a blank
version-43 text cartridge, switched to tracker mode, and given one C note in
each populated slot so native save retained the metadata-only states.

The native editor produced these mode/filter bytes:

| Slot | Editor state | Byte |
|---:|---|---:|
| 0 | pitch; all filters off | `0x00` |
| 1 | tracker; all filters off | `0x01` |
| 2 | tracker; NOIZ on | `0x03` |
| 3 | tracker; BUZZ on | `0x05` |
| 4 | tracker; DETUNE 1 | `0x09` |
| 5 | tracker; DETUNE 2 | `0x11` |
| 6 | tracker; REVERB 1 | `0x19` |
| 7 | tracker; REVERB 2 | `0x31` |
| 8 | tracker; DAMPEN 1 | `0x49` |
| 9 | tracker; DAMPEN 2 | `0x91` |
| 10 | tracker; NOIZ/BUZZ on and all ternary filters at 2 | `0xd7` |
| 11 | pitch; same filters as slot 10 | `0xd6` |

This derives the codec as `mode + noiz*2 + buzz*4 + detune*8 + reverb*24 +
dampen*72`. Consequently the 216 named states are exactly raw bytes
`0x00..0xd7`; `0xd8..0xff` are not classified by this fixture and remain
read-only.

The checksummed native-format waveform matrix
`tests/fixtures/pico8-027-waveform-filters.p8` records the same waveform
payload at all-off and levels 1/2 for each supported waveform filter:

| Slot | Waveform filter state | Byte 64 |
|---:|---|---:|
| 0 | all supported filters off | `0x00` |
| 1 | DETUNE 1 | `0x08` |
| 2 | DETUNE 2 | `0x10` |
| 3 | REVERB 1 | `0x18` |
| 4 | REVERB 2 | `0x30` |
| 5 | DAMPEN 1 | `0x48` |
| 6 | DAMPEN 2 | `0x90` |

All seven slots have exact matching 64-byte samples, bass, notes/wave bit, and
remaining metadata. SFX 8 and pattern 0 retain the conventional custom-
instrument playback reference. This proves the waveform-owned digits remain
`8/24/72`; executable tests cover every 3×3×3 combination and preserve raw
NOIZ/BUZZ bits without exposing them as waveform controls.

Executable: `/home/nick/Development/pico8/pico-8/pico8`

- Executable SHA-256: `b07e76cd6a0336508200be75d67cd893ef90a0a00408163fd33af43ba006eab0`
- Fixture SHA-256: `7730d07d2c264b66761aedfc8104c27e43cc939cbcd4cbc2e82e48d4d69ff038`
- Waveform filter matrix SHA-256: `7bceaada74bc5183b3cf58ee860d8a68ee96778e2ff0db755cdc7228ee5128a1`
- Waveform filter matrix audio-bank CRC-16/CCITT-FALSE: `0xb8dd`
- Runtime/editor version: PICO-8 0.2.7; text-cartridge version 43
- Semantic reference: [official PICO-8 manual, “SFX Editor / Filters”](https://www.lexaloffle.com/dl/docs/pico-8_manual.html#Filters)
