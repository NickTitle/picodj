# M1 implementation specification: Starfield Track 1

Status: executable target; fixture scaffold included

- Fixture authority: `refs/remotes/pico-strfld/main` in the local Starfield
  checkout
- Source commit: `e7e97ab01fdd1848e0b78f27191684412e60daf5`
- Authority state: remote-tracking ref inspected directly with `git show`; the
  checkout itself was clean on local `master` at
  `e25e7b86337ce0428c5008eab28e0a07cef6f674`
- Context worktree: clean `agent/louder-title-music` at
  `60518b1ba1c2eb8f417555c63ff08afadf1e2385`
- Source cartridge: `starfield.p8`, text cartridge version 43

## 1. What “Track 1” means

Track 1 is a UI name, not music pattern 1:

- `constants.lua` defines `music_tracks={0}`.
- `select_music_track(1)` calls `music(music_tracks[1])`, therefore
  `music(0)`.
- `starfield.p8` music pattern 0 is `03 01020304`.
- The `03` flow prefix sets loop-start and loop-back on the same pattern.
- Its four enabled channels reference SFX 1, 2, 3, and 4.
- In audio RAM the four pattern bytes are `81 82 03 04`: loop-start is channel
  0 bit 7 and loop-back is channel 1 bit 7.

Track 1 is therefore one self-looping 32-row pattern. The referenced SFX all
have speed `0x18` (24), so the timing authority is 32 rows x 24 PICO-8 audio
ticks on the left-most non-looping channel. Acceptance observes native playback
state rather than relying on a frame-rate-derived Lua playhead.

## 2. Authored bytes versus audible title playback

The source commit added a runtime loudness transform in `music.lua`:

1. `init_music_menu()` snapshots all 32 note words in SFX 1..4.
2. `boost_music_sfx()` raises each nonzero volume by two, capped at seven.
3. Starfield calls `music(0)` against those temporary words.
4. Turning music off or starting gameplay restores the authored words.

M1 must preserve both facts. Its canonical bank is the authored Starfield bank,
and its project metadata contains this playback profile:

```text
profile type: volume-offset-v1
sfx range:    1..4
predicate:    volume > 0
delta:        +2
clamp:        7
restore:      required before edit/save/checksum/authored export
```

This is the default pending Nick's decision in `REQUIREMENTS.md`. The profile
must never compound when play is pressed repeatedly.

## 3. Exact source representation

The checked-in fixture is
`tests/fixtures/pico-strfld-e7e97ab-track-1.p8`. It copies the canonical source
cartridge's complete `__sfx__` and `__music__` sections verbatim so the original
indices and unrelated neighboring audio bytes remain available for provenance.
M1 selects only pattern 0 and its dependency closure, SFX 1..4.

The canonical audio-block checksum is SHA-256
`55c095c40b262f59c501fe0cefba8f2a716434feecc85b63b9aca22a82a27a77`.
It is calculated over LF-terminated lines beginning with `__sfx__` and ending
with `01 41424344`. The same extraction from the canonical Git object and from
the fixture has no diff. The complete fixture-file SHA-256 is
`ae6e2150da878b84abecc98da725d43bf27d531568e6c1c0a62817a142384666`.
When loaded as the complete native `0x3100..0x42ff` audio bank, its
CRC-16/CCITT-FALSE is `0x2a23` (`poly=0x1021`, `init=0xffff`, non-reflected,
`xorout=0`). M1.1 pins this value before any staged commit.

Referenced SFX headers are:

| SFX | Mode/filter byte | Speed | Loop start | Loop end | Rows |
|---:|---:|---:|---:|---:|---:|
| 1 | `01` | `18` (24) | `00` | `00` | 32 |
| 2 | `0d` | `18` (24) | `00` | `00` | 32 |
| 3 | `49` | `18` (24) | `00` | `00` | 32 |
| 4 | `01` | `18` (24) | `00` | `00` | 32 |

The fixture is intentionally data-only. It does not include or modify any
Starfield Lua, and the Starfield checkout remains read-only for this work.

## 4. Deterministic import/load path

### M1 embedded seed

1. Build `pocket-tracker.p8` with the fixture's authored pattern 0 and SFX 1..4
   at their original indices. Other song/SFX slots are zero unless reserved by
   the tracker; tracker UI sounds must not occupy 1..4.
2. At `_init`, copy `0x3100..0x42ff` to a clean authored snapshot in upper
   memory before any preview transform.
3. Create the project record `strfld track 1`, source commit/path, pattern 0,
   dependency set `{1,2,3,4}`, and `volume-offset-v1` profile.
4. Compute and retain the raw-bank and envelope checksums.
5. Open SONG on pattern 00. No host file, cross-repository relative path, or
   network request is needed at runtime.

### Fixture/native acceptance load

The fixture test loads `0x1200` bytes beginning at source address `0x3100`
into staging RAM, verifies the expected pattern and referenced SFX, then may
commit. Production import never reloads directly over the canonical bank.

### Browser import

The wrapper parses the fixture or source `.p8`, emits a version-2 envelope, and
uses the paged GPIO protocol. The cart validates the same authored bytes and
adds the playback profile only when the user selects the named Starfield
import preset or the envelope already contains it. A generic `.p8` import must
not infer the source's Lua-side boost.

## 5. M1 implementation slices

### M1.0 — Architecture and provenance scaffold (this pass)

- Requirements, design, and this implementation spec exist under `docs/`.
- Exact source commit/state is recorded.
- A standalone read-only audio fixture exists under `tests/fixtures/`.
- A cartridge fixture test validates pattern 0, its flags/dependencies, and all
  raw SFX 1..4 headers/note rows without changing the prototype.

### M1.1 — Native bank core

Status: implemented and cartridge-tested in the working tree.

- Add address constants and bounded raw/typed accessors.
- Add bank copy, equality/checksum, staging, commit, and one-snapshot rollback.
- Add project metadata and playback-profile application/restoration.
- Replace the prototype's `notes`, `waves`, `volumes`, and `effects` tables as
  authority; do not delete them until the new fixture path passes.

### M1.2 — Minimum cartridge editor

- SONG pattern 00 as the primary screen, SFX slots 01..04, and the project
  palette for playback and file operations.
- SONG edits four channel SFX/mute fields and three flow flags.
- SFX edits 32 rows of pitch/instrument/custom flag/volume/effect plus raw
  metadata, speed, and loop/LEN values.
- Current field, dirty state, profile-active state, play state, and errors are
  visible.
- Every action is reachable without keyboard, mouse, or O+X.

### M1.3 — Faithful playback

- Start/stop `music(0)` with idempotent temporary volume boost and restoration.
- SFX/row audition uses an explicitly reserved channel and never corrupts SFX
  1..4.
- Editing during playback performs stop -> restore -> edit -> optional restart.
- Playback follow reads `stat(46..57)`; it does not estimate rows from BPM.

### M1.4 — Save/reload and export

- Implement one complete native project slot or, if native project-cart policy
  remains undecided, the browser last-known-good store first.
- Read-back checksum gates the success message.
- Lossless JSON export/import retains authored bank and playback profile.
- Deterministic `.p8` audio export offers authored and materialized modes.

### M1.5 — Release acceptance

- Run all tests against an exact recorded PICO-8 executable version and exact
  repository HEAD.
- Export a fresh HTML build and verify desktop/touch editing, audio start, full
  loop, stop/restore, save/reload, and both export modes.
- Record `INFO` token, character, and compressed-size results.

## 6. Acceptance criteria

### AC-1 Source and import identity

- Fixture provenance commit equals
  `e7e97ab01fdd1848e0b78f27191684412e60daf5`.
- Pattern 0 text is `03 01020304`; RAM bytes are `81 82 03 04`.
- Every one of the 32 packed note words and all four metadata bytes in each of
  SFX 1..4 equal the authored source.
- Pattern 0 dependency traversal returns exactly `{1,2,3,4}`.
- Loading an invalid/truncated/corrupt fixture leaves the current bank and
  dirty/revision state unchanged.

### AC-2 Playback fidelity

- Before play, authored SFX 1..4 match AC-1.
- The temporary playback words match Starfield's transform for all 128 rows:
  zero volume is unchanged; nonzero volume is `min(7, source+2)`; every other
  bit is unchanged.
- Immediately after the mixer starts, channels 0..3 report SFX 1..4,
  `stat(54)==0`, and `stat(57)` is true.
- `stat(55)` advances after the full pattern and playback returns to pattern 0;
  it remains active for at least two complete loops.
- Stop sets `stat(57)` false and restores every authored word.
- Native and browser builds pass a human A/B at matched master volume. Because
  both use identical transformed bytes and the native mixer, a mismatch is
  treated as a data/build bug rather than accepted as synthesizer variance.

### AC-3 Editability

- From boot using only six buttons, a user can reach each of SFX 1..4 and all
  32 rows, change pitch, built/custom instrument, volume, and effect, and clear
  or restore a row.
- A field edit changes only its owned bits. At least one test starts with
  unrelated high bits set to prove preservation.
- The user can edit SFX speed and loop/LEN markers and pattern channel/flow
  fields.
- The changed value is visible, audible on audition, and marks the project
  dirty.
- Cancel restores the pre-edit value; undo restores the complete prior word.

### AC-4 Save and reload

- Save while stopped writes the authored bank, profile, provenance, revision,
  and checksum.
- Save while playing first stops and restores authored bytes.
- After deliberately mutating pattern and SFX data, reload restores the exact
  saved envelope and the UI reports clean state.
- Power/relaunch in the supported target runtime can recover the saved project.
- Interrupted or checksum-failed reload retains the pre-load project.

### AC-5 Round-trip and export

- Lossless project export -> import produces byte-identical authored bank,
  profile, and source selection.
- Authored `.p8` export -> import produces byte-identical pattern 0 and SFX
  1..4 and keeps the profile in its Pocket Tracker sidecar/envelope.
- Materialized `.p8` export has no required playback profile; its SFX 1..4
  equal the deterministic boosted words and plain `music(0)` matches M1
  audition.
- Repeating either round-trip three times yields identical decoded envelopes;
  formatting changes may not accumulate.
- Export never includes partial temporary state, bridge headers, undo snapshots,
  or unrelated high-memory bytes.

### AC-6 Constraints

- Cartridge runs below the measured CPU budget on editor, playback, and GPIO
  transfer frames.
- It remains within 8,192 tokens, 65,535 characters, and 15,360 compressed code
  bytes with at least the design's 20% M2/M3 token/compression reserve at M1.
- Full-project GPIO transfer uses multiple acknowledged pages and cannot commit
  a partial bank.

## 7. Test inventory

| Test | Purpose | Current state |
|---|---|---|
| `tests/m1_track_1_fixture.p8` | Reload fixture; validate exact pattern bytes and SFX 1..4 raw rows/metadata. | Added; pass marker observed on PICO-8 0.2.7. |
| Existing `tests/smoke.p8` | Protects the former prototype behavior through a test-only legacy fixture. | Preserved. |
| `tests/m1_bank.p8` | Accessor masks/boundaries, exact seed, profile, staging/commit/rollback/checksum, corruption, and waveform preservation. | Added; pass marker and status 0 on PICO-8 0.2.7. |
| `tests/hold_menus.p8` | Native SONG/SFX tap-versus-hold input, release gating, project/context palettes, and O+X chord isolation. | Updated for the native-first UI; pass marker and status 0 on PICO-8 0.2.7. |
| `tests/playback_transport.p8` | Profile idempotence, reversible SFX 63 preview, stop/restore/edit/restart, and complete `stat(46..57)` follow. | Added in M1.3; pass marker and status 0 on PICO-8 0.2.7. |
| `tests/m1_playback.p8` | Real native mixer start/channels plus stop and authored-bank restoration. | Added in M1.3; pass marker and status 0 on PICO-8 0.2.7. |
| `tests/project_io.p8` | 42-page GPIO save/load, exact bank/metadata restore, corrupt/out-of-order/partial rollback. | Added in M1.4A. |
| `tests/project_io.js` | Envelope/storage round-trip, corrupt record, read-back/write faults, and GPIO paging. | Added in M1.4A. |
| `tests/file_io.js` | Deterministic lossless JSON, strict import validation/rollback, and byte-exact authored/materialized `.p8` codecs. | Added in M1.4B. |

## 8. Known blockers and owner choices

- At the M1.4A checkpoint, the generated outputs were deterministically
  regenerated: `tracker.html` was SHA-256
  `858c7c8e299f1900c484a00435dea08590169a70d3c2d2366f671a7bb7161d18`
  and `tracker.js` was SHA-256
  `1a2b59dd99a9a40d22a6fc8a83ef8d76e7f03a967042cbb15def7acfec6179db`.
  Any source change must still be followed by regeneration and exact-source
  verification before commit, publication, or release.
- The project is published publicly as `NickTitle/picodj`; the production-cart
  size correction is merged in `main` at
  `0bcf9b85aa7bf46f0e983772614db0f42c29cf38`.
- The native data-cart destination remains open. M1.4B exposes lossless JSON
  import/export plus both labelled `.p8` export representations through the
  browser last-known-good slot; user-facing `.p8` import remains a later
  staged native/data-cart sub-arc.

## 9. M1.0 verification record

Both cartridge tests were run from the unborn `build/mobile-tracker` worktree
with PICO-8 0.2.7, dummy SDL video/audio drivers, and a 10-second outer
timeout:

- `tests/m1_track_1_fixture.p8` emitted
  `pocket tracker m1 fixture: passed` and no failure marker.
- Existing `tests/smoke.p8` emitted `pocket tracker smoke: passed` and no
  failure marker.

In this headless environment `extcmd("shutdown")` did not terminate the host,
so the outer timeout ended both processes with status 124 after their pass
markers. Acceptance is based on the explicit marker and absence of any
`fail:` output, not on the timeout status.

## 10. M1.1 verification record

The additive native-bank core is `audio_bank.lua`; `pocket-tracker.p8` includes
it before the unchanged prototype model. The core fixes staging at
`0x8000..0x91ff`, one rollback snapshot at `0x9200..0xa3ff`, and the temporary
Track 1 profile snapshot at `0xa400..0xa4ff`. Generic bulk copy may write only
staging; CRC-16/CCITT-FALSE-gated commit and rollback exclusively own
canonical/snapshot writes. The fixture CRC is pinned at `0x2a23`, and a
one-bit staging corruption is rejected without bank or metadata mutation.

The complete cartridge suite was run with PICO-8 0.2.7 in headless `-x` mode.
Each process exited with status 0:

- `tests/m1_track_1_fixture.p8` emitted
  `pocket tracker m1 fixture: passed`;
- `tests/m1_bank.p8` emitted `pocket tracker m1 bank: passed`;
- `tests/smoke.p8` emitted `pocket tracker smoke: passed`.

A main-cartridge HTML export to `/tmp` also completed with status 0, proving
that the included core remains within PICO-8's enforced compile and compressed
export limits. An `INFO()` inspection cart reported 3,901/8,192 tokens,
17,808/65,535 characters, and 4,982/15,360 compressed bytes. The identical
measurement hook alone is 37 tokens and 173 characters, making the included
core plus prototype 3,864 tokens and 17,635 PICO-8 characters; the inspection
cart's 4,982 compressed bytes are a conservative measured bound that includes
the hook. The two source files contain 17,626 host bytes before the cartridge
wrapper, and a minimal inspection cart reported `stat(0)` memory use as
`96.0879`. The repository's `tracker.html` and `tracker.js` were then
regenerated from the accepted source. A second export matched both outputs
byte-for-byte, producing the SHA-256 values recorded above. Generated-output
freshness is therefore resolved; repository destination and Git author
identity were still publication blockers at that historical M1.1 checkpoint;
both were subsequently resolved by the public `NickTitle/picodj` repository
and its established noreply author identity.

## 11. M1.3 verification record

The faithful-playback implementation was reviewed and merged from exact clean
head `8af4b465426b49ccec2a1d8089cb4adb1b20a359`, based on merged `main`
`6bc095c478b753ec4d45cbe046cdd077f5226cc9`. All ten PICO-8 0.2.7
cartridges exited with status 0 and emitted their pass markers:

- `tests/hold_menus.p8`;
- `tests/m1_bank.p8`;
- `tests/m1_playback.p8`;
- `tests/m1_track_1_fixture.p8`;
- `tests/playback_transport.p8`;
- `tests/sfx_safety.p8`;
- `tests/sfx_ui.p8`;
- `tests/sfx_visual.p8`;
- `tests/smoke.p8`;
- `tests/song_ui.p8`.

Two independent browser exports were byte-identical, and the committed files
matched them: `tracker.html` SHA-256
`858c7c8e299f1900c484a00435dea08590169a70d3c2d2366f671a7bb7161d18`
and `tracker.js` SHA-256
`5d9925a079d9801b3b48efebd2df0be42317aef55ab0a3f2e6bad68076e997af`.
Node syntax, whitespace, committed-content safety, and clean-worktree checks
also passed at that head. The existing port 4179 apphost served those exact
hashes from the M1.3 worktree.

## 12. M1.4A verification record

M1.4A adds `project_io.lua` and the browser-side v2 envelope adapter. The
focused cartridge test exercises all 42 save/load pages, cross-runtime GPIO
CRC agreement, exact authored-bank and metadata restoration, corrupt frames,
idempotent duplicate pages, out-of-order pages, a checksum-valid unknown fixed
selection, and a partial-transfer timeout. The focused Node test
exercises deterministic envelope/storage round-trip, corrupt stored data,
write and read-back faults with last-known-good restoration, checksum-valid
profile/selection mutation, all save/load pages, duplicate retry, and invalid
GPIO ordering. The complete cartridge suite now contains
eleven PICO-8 tests; browser validation also includes both Node regressions.

Two fresh exports must remain byte-identical to the committed artifacts. For
this M1.4A source, `tracker.html` is SHA-256
`858c7c8e299f1900c484a00435dea08590169a70d3c2d2366f671a7bb7161d18`
and `tracker.js` is SHA-256
`1a2b59dd99a9a40d22a6fc8a83ef8d76e7f03a967042cbb15def7acfec6179db`.

## 13. Full-cartridge token gate

Merged M1.4A failed the real `pico8 -x pocket-tracker.p8` load path at exactly
9,731/8,192 production tokens (9,748 with the 17-token inspection wrapper),
even though HTML export returned success. The earlier cartridges compiled
feature slices and never included all five production Lua files together.

At that correction checkpoint, the bounded change removed only
runtime-shadowed prototype bodies from
the shipped graph, preserves them in `tests/legacy_tracker.lua`, and shares
the context-menu, hold/release, edit, undo, and modal-draw engines across GRID,
SONG, and SFX. The fixed production graph measures exactly 7,928 tokens: 1,803
fewer than merged M1.4A and 264 below the platform ceiling. The committed
`tests/size_budget.p8` adds a calibrated 261-token probe to the exact production
graph and emitted `pocket tracker size budget: passed`.

## 14. M1.4B browser file boundary

The M1.4B Files panel serializes only a checksum-valid v2 last-known-good
envelope. JSON contains the complete authored bank, bounded project metadata,
provenance, revision, fixed Track 1 source selection, and versioned playback
profile. Import requires the exact schema, bounded ASCII strings and integers,
lowercase fixed-length bank/checksum fields, bank CRC, reconstructed envelope
CRC, and storage read-back before replacing the durable slot. Malformed input
never reaches GPIO or the live bank; the existing staged Load transaction is
still the only live commit path.

Authored `.p8` output preserves all 4,608 bank bytes and embeds the 64-byte
Pocket Tracker header as a labelled sidecar comment. Materialized output keeps
patterns and all unrelated SFX bytes exact while applying the profile gain only
to non-resting rows in SFX 1..4; it carries no required profile. Both codecs
have deterministic repeated-output and field-aware decode regressions. No Lua
source changed in this arc, so the production graph remained exactly 7,928
tokens with 264 tokens of headroom at that historical M1.4B checkpoint.

## 15. M1.5 native-first reserve correction

Nick selected the native-first option on 2026-08-23. The shipped legacy 4x16
grid was removed and SONG now opens directly as the primary experience. The
shared six-button layer retains only native SONG/SFX navigation, project and
context palettes, release gating, and the SFX rest chord. Legacy behavior is
kept solely in `tests/legacy_tracker.lua` for regression coverage.

The exact five-file production graph now measures 6,492 tokens, 61 below the
documented 6,553-token reserve gate and 1,700 below PICO-8's 8,192-token hard
ceiling. The calibrated reserve test adds exactly 1,639 tokens, so it compiles
at 8,131 tokens on this source and would reject a production graph above the
gate. The exported production PXA header records 39,235 raw code bytes and
10,061 compressed bytes, 2,227 below the 12,288-byte reserve gate.

Two fresh browser exports were byte-identical, and the tracked artifacts match
them exactly: `tracker.html` is SHA-256
`858c7c8e299f1900c484a00435dea08590169a70d3c2d2366f671a7bb7161d18`
and `tracker.js` is SHA-256
`fad2d72a1120ade026b25ff6e5c9125e5c9f4379bcfb4261be87bd9b68ccbe4b`.

## 16. M2 conventional SFX filters

The named filter codec is derived from the PICO-8 0.2.7 native-editor fixture
and provenance record in `docs/PICO8_027_FILTER_FIXTURE.md`. The focused
cartridge exhaustively verifies all 108 named filter combinations under both
editor-mode-bit states, every unsupported raw state, waveform rejection,
whole-byte commit/Undo/Redo, dirty/revision behavior, and the playback restore
policy. The complete suite now contains thirteen PICO-8 cartridges plus all
three Node regressions.

The accepted five-file production graph measures exactly **6,533 tokens**,
five below the arc ceiling of 6,538 and twenty below the unchanged 6,553
reserve gate. The exported PXA header records 39,220 raw code bytes and 10,219
compressed bytes, 2,069 below the unchanged 12,288-byte gate.

Two independent exports are byte-identical and match the tracked artifacts:
`tracker.html` SHA-256
`858c7c8e299f1900c484a00435dea08590169a70d3c2d2366f671a7bb7161d18`
and `tracker.js` SHA-256
`08bcc9adb9e084402eac1d7348956a1a4d37e16f5751407d5073920ede7be2ae`.

## 17. Final M3 native data-cart persistence

The final M3 persistence arc adds the shipped fixed `pocket-tracker-data.p8`
slot without changing PTP2. Two 4,680-byte records preserve one rollback
generation in 9,360 of the data cart's 17,152 writable bytes. Each record has
an 8-byte magic/generation/CRC wrapper and the exact 4,672-byte envelope. Save
writes only the older or invalid record and succeeds only after complete
read-back validation; load chooses the newest valid modular generation and
falls back to the older valid record. Native `cstore()` and `reload()` return
values are not assumed: sentinel-prefill distinguishes an untouched
missing/cancelled operation from loaded data before CRC validation. The full
scan scratch and full read-back target are poisoned before reload, so partial
I/O cannot validate stale intended RAM. Modular ordering uses PICO-8's signed
low-16-bit delta: only `1..0x7fff` selects B; ties and `0x8000` select A.

The release gate is deliberately re-baselined for completed M3: the calibrated
probe is 1,024 tokens, requiring production at or below **7,168 / 8,192** and
preserving at least 1,024 hard-limit tokens for separately budgeted M4 work.
Raw PXA remains capped at 65,535 bytes and compressed PXA at 12,288 bytes.

The accepted five-file graph measures **6,960 tokens**, leaving 208 tokens
below the M3 gate and 1,232 below the hard ceiling, and 41,327 source bytes.
The exported PXA header records 41,342 raw bytes and 11,427 compressed bytes.
Two same-basename fresh exports
are byte-identical; `tracker.html` remains SHA-256
`858c7c8e299f1900c484a00435dea08590169a70d3c2d2366f671a7bb7161d18`
and regenerated `tracker.js` is SHA-256
`f65b3f8297f4adea2feb4794da41a657bdda1fcb45a7c6de944c734f968c4690`.
The production-shaped runtime retained 600 frames at 60 FPS with no bad frame
and peak `stat(1)` of 0.0031.
