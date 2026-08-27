# PICO-8 0.2.7 music timing fixture

`tests/fixtures/pico8-027-timing.p8` was authored and saved by native PICO-8
0.2.7 on 2026-08-27. A temporary cartridge populated the native song/SFX RAM
and used PICO-8's own `cstore()` path to write the version-43 text cartridge.
The temporary authoring cartridge is not part of the repository. One terminal
blank line was removed after save for repository whitespace hygiene; no
cartridge section or authored byte changed.

- Executable: `/home/nick/Development/pico8/pico-8/pico8`
- Executable SHA-256: `b07e76cd6a0336508200be75d67cd893ef90a0a00408163fd33af43ba006eab0`
- Fixture SHA-256: `a1011ae57cfbe6c88d14834e24f305fefff11e798a9b0a8a5fc226d193e3d054`
- Semantic reference: [official PICO-8 manual, Music Editor / Flow Control](https://www.lexaloffle.com/dl/docs/pico-8_manual.html#Music_Editor)

## Raw fixture basis

The three populated music patterns have these exact RAM bytes:

| Pattern | Channel bytes | Purpose |
|---:|---|---|
| 0 | `08 09 0a 09` | case 1 |
| 1 | `0c 0d 0e 0c` | case 2 |
| 2 | `10 10 90 10` | observable successor; channel 2 carries STOP |

Every authored note word is one of `0x0a18..0x0a1b` (built-in instrument 0,
volume 5, effect 0). The SFX metadata bytes are:

| SFX | Raw metadata `mode speed start end` | Meaning |
|---:|---|---|
| 8 | `00 08 00 00` | 32 notes, 8 ticks each; 256-tick authority |
| 9 | `00 01 00 00` | 32 notes, 1 tick each; ends after 32 ticks |
| 10 | `00 01 00 02` | loops rows 0..1 |
| 12 | `00 01 00 02` | loops rows 0..1 |
| 13 | `00 20 08 00` | `LEN 8` at 32 ticks per note; 256-tick authority |
| 14 | `00 10 00 00` | 32 notes, 16 ticks each; still active at tick 256 |
| 16 | `00 08 00 00` | long successor used to expose each transition |

## Native observations

Timing was observed only through `stat(46..57)` in the normal PICO-8 runtime.
Experimental `-x` mode does not run the audio mixer, so this cartridge uses
PICO-8 0.2.7's normal `-run` path against SDL's isolated dummy audio device.
This changes no host audio configuration and executes the native mixer. The
bounded test runner requires the exact pass marker and rejects any `fail:`
marker; it then terminates the editor process because `extcmd("shutdown")` only
closes exported binaries. It passes `-foreground_sleep_ms 16` so the normal
runtime yields a stable cadence to the mixer thread.

```sh
SDL_AUDIODRIVER=dummy timeout 15s xvfb-run -a \
  /home/nick/Development/pico8/pico-8/pico8 \
  -foreground_sleep_ms 16 -run tests/sfx_timing.p8
```

- Case 1 stayed on pattern 0 through `stat(56)==254`, after SFX 9 had passed
  row 31 while SFX 10 continued looping. Pattern 1 was first observed at tick 1.
  The exact native boundary is 32 rows times speed 8 = **256 ticks**.
- Case 2 stayed on pattern 1 through `stat(56)==254`. Channel 0 remained on
  looping SFX 12, channel 1 reached LEN row 7, and slower right channel 2 was
  only at row 15. Pattern 2 was first observed at tick 1. The exact native
  boundary is LEN 8 times speed 32 = **256 ticks**.

At 60 updates per second, native audio snapshots can skip up to three terminal
tick values between Lua observations. The test therefore requires the last
current-pattern sample in `252..255` and the first successor sample in `0..3`;
the exact authority remains 256 ticks in both cases. This tolerance covers only
`stat()` observation cadence, not playback duration.

`tests/sfx_timing.p8` uses frame counts only as a 600-frame failure timeout.
All timing, channel, row, transition, and stop assertions read native
`stat(46..57)`; it introduces no Lua playhead or duration model.
