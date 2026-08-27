# Pocket Tracker technical design

Status: proposed architecture; M1 scaffold started 2026-08-17

Related: [REQUIREMENTS.md](REQUIREMENTS.md),
[M1_TRACK_1_SPEC.md](M1_TRACK_1_SPEC.md)

## 1. Architectural decision

Use PICO-8's audio RAM itself as the canonical project model:

```text
editor actions ──> typed bit/byte accessors ──> 0x3100..0x42ff
                                                │
                                      ┌─────────┼──────────┐
                                      ▼         ▼          ▼
                                  music()/sfx() save/load  GPIO pages
```

This avoids the failure mode already present in the prototype: a simplified
Lua table can describe four uniform 16-step channels, but it cannot round-trip
per-row instruments/volumes/effects, 32-row SFX, 64 patterns, filters, custom
instruments, or waveform instruments. A raw bank can represent all of them and
PICO-8 can audition it directly.

UI state, selection, undo metadata, provenance, and optional playback profiles
live beside the bank. They never replace it.

## 2. Runtime components

| Component | Responsibility | Must not do |
|---|---|---|
| `audio_bank` | Address calculation; raw and typed reads/writes; validation; bank copy/checksum. | Own UI or persistence policy. |
| `project` | Dirty/revision state, project name, provenance, playback profile, transaction staging. | Duplicate every note as Lua tables. |
| `transport` | Start/stop song and SFX audition; temporary mute/solo/profile application; restore raw bytes. | Permanently rewrite bytes for preview. |
| `ui` | Screen state machine, focus, scrolling, help, confirmation, dirty/error display. | Encode PICO-8 audio fields directly. |
| `native_store` | `cstore()` / `reload()` adapter and read-back verification. | Assume browser filesystem access. |
| `gpio_store` | Incremental framed byte transport through GPIO. | Parse project semantics in JavaScript. |
| Browser shell | File picker/download, local last-known-good storage, `.p8` text codec, bridge driver. | Synthesize the authoritative preview or edit fields. |

M1 may keep these as compact groups of functions rather than separate files.
The boundaries are contractual; premature object systems would waste tokens.

## 3. Native audio representation

### 3.1 Bank layout

```text
0x3100 + pattern*4 + channel       song byte (64*4 = 256 bytes)
0x3200 + sfx*68 + row*2            packed note word (64 bytes)
0x3200 + sfx*68 + 64               SFX mode/filter byte
0x3200 + sfx*68 + 65               SFX speed, or waveform bass metadata
0x3200 + sfx*68 + 66               loop start, or waveform-mode metadata
0x3200 + sfx*68 + 67               loop end / mode-specific metadata
```

The complete contiguous bank is `0x1200` (4,608) bytes from `0x3100` through
`0x42ff` inclusive.

### 3.2 Song bytes

Each pattern is four bytes:

- bits 0..5: SFX index 0..63;
- bit 6: channel muted when set;
- channel 0 bit 7: loop-start flag;
- channel 1 bit 7: loop-back flag;
- channel 2 bit 7: stop flag;
- channel 3 bit 7: reserved and preserved.

Typed setters use masks. For example, changing a channel's SFX index keeps both
mute and pattern-control bits. Changing loop-start modifies only byte 0 bit 7.

### 3.3 SFX note words

Each conventional row is a 16-bit word:

```text
bits  0..5   pitch (0..63)
bits  6..8   instrument index (0..7)
bits  9..11  volume (0..7)
bits 12..14  effect (0..7)
bit     15   custom/SFX instrument selector
```

The visual editor treats a row with volume zero as silent but preserves its
other fields. It does not encode a rest as the all-zero word unless the user
explicitly clears the row.

In text `.p8` form, a conventional SFX row uses five hexadecimal digits:
two for pitch, then one each for instrument (including the custom selector),
volume, and effect. The `.p8` order is not a direct hexadecimal rendering of
the little-endian in-memory word; import/export uses field-aware codecs.

### 3.4 SFX metadata and waveform instruments

The four metadata bytes are always preserved raw. Conventional mode exposes
speed, loop/LEN markers, pitch-vs-tracker editor mode, and filter fields through
masked accessors. SFX 0..7 may instead be waveform instruments in PICO-8
0.2.6+: their first 64 bytes are signed 8-bit samples and their metadata bytes
have waveform-specific meanings, including bass and mode bits.

The project validator classifies a slot before a typed editor opens it.
Classified waveform slots expose the first 64 bytes as 32 even/odd raw-hex
pairs. A scalar commit owns exactly one signed 8-bit sample byte and uses the
same byte-span history and stop/restore/restart transaction as conventional
edits. Metadata keeps all four bytes visible; the native fixture-proven bass
field owns only bit 0 of byte 65 and preserves every other metadata bit.
Waveform mode and remaining metadata stay read-only. Import, save/load, JSON,
and authored/materialized `.p8` codecs preserve the complete 68-byte slot
without decoding samples as notes.

## 4. Project envelope

The lossless logical project is:

```text
format             "pocket-tracker"
version            integer, initially 2
audio_bank         exactly 4608 bytes
project_name       bounded P8SCII/ASCII display name
revision           monotonically increasing integer
playback_profile   optional, versioned transforms used only for audition/export
source             optional repo/commit/path/selection provenance
checksum           CRC-16/CCITT of envelope fields and bank
```

The in-cart implementation stores compact binary metadata. Browser JSON uses
lowercase hex for the bank rather than an array of 4,608 decimal values. JSON
key ordering and whitespace are cosmetic; decoded envelope bytes determine
equality.

Unknown playback profiles or envelope versions are rejected. Unknown raw
audio bits are not rejected solely because the current UI cannot name them.

M1.4A's browser slot uses a fixed 4,672-byte binary representation: a 64-byte
header followed by the exact 4,608-byte authored bank. The header records
`PTP2`, format/header/total lengths, bank and envelope CRC-16 values, revision,
the versioned Track 1 `+2` playback profile, bounded project/source strings,
and source pattern/SFX selection. The envelope CRC treats its own two bytes as
zero. Browser local storage wraps those bytes as deterministic lowercase hex
under `pocket-tracker:project:v2:last-known-good`; decoded bytes, rather than
JSON formatting, remain authoritative.

M1.4B keeps the production Lua graph unchanged to preserve the verified
256-token reserve. The browser Files panel encodes and decodes only this valid
last-known-good envelope. A valid JSON import atomically replaces the durable
slot after full validation and storage read-back; the existing 42-page Load
transaction remains the only path that can stage and commit imported bytes to
the live bank. This separation gives malformed files no live or durable write
path and keeps browser code out of arbitrary cartridge RAM.

## 5. Editing transactions

1. An input action resolves to a validated byte-span or bit-field command.
2. The command records its address, width, prior dirty state, and exact
   pre-image in the fixed batch-swap buffer.
3. The accessor validates indices and values before writing.
4. The write touches only owned bits, marks the project dirty, and increments
   the in-memory revision.
5. If the edited bytes are currently playing, the transport stops and restores
   temporary audio, applies the transaction once, then restarts the observed
   pattern under the current audition-mix/profile policy.

The global one-level history swaps the complete recorded span, so scalar edits,
row rest toggles, and 1–32-row paste/clear operations share the same atomic
Undo/Redo path. A no-op, rejected range, copy, or cancelled selection does not
touch history, dirty state, revision, or transport.

Imports use high user RAM as staging:

```text
candidate bytes -> 0x8000..0x91ff -> length/version/checksum validation
                  -> snapshot current bank -> memcpy to 0x3100 -> audible test
                  -> commit dirty/revision state
```

At least one additional 4,608-byte region can hold the pre-import or undo
snapshot. The chosen upper-memory addresses must be constants and checked
against future allocations.

M1.1 fixes those allocations as follows:

| Region | Inclusive range | Purpose |
|---|---:|---|
| Canonical audio | `0x3100..0x42ff` | Authored bank used by native playback. |
| Import staging | `0x8000..0x91ff` | Candidate bank; the only public bulk-copy destination. |
| Rollback snapshot | `0x9200..0xa3ff` | One pre-commit bank, written only by validated commit. |
| Track 1 profile snapshot | `0xa400..0xa4ff` | 128 authored note words for temporary preview gain. |
| SFX audition snapshot | `0xa500..0xa543` | Reversible 68-byte snapshot of reserved preview SFX 63. |
| SFX row clipboard | `0xa544..0xa583` | Session-only 1–32 authored row words; never persisted. |
| Edit batch swap | `0xa584..0xa5c3` | Exact pre-image for one scalar or row-span Undo/Redo transaction. |
| Project I/O header | `0xa5c4..0xa603` | Transient 64-byte browser envelope header. |

The regions are disjoint and remain within PICO-8's upper user-data memory.
M1.1 stage validation uses CRC-16/CCITT-FALSE (`poly=0x1021`, `init=0xffff`,
non-reflected, `xorout=0`). The importer-provided expected CRC must match the
complete staged bank before commit. The project envelope and GPIO frames use
the same CRC variant so there is only one checksum semantic in the system.

## 6. Cartridge UI

### 6.1 Screen map

```text
HOME
 ├─ SONG   pattern list -> four channel cells -> pattern flags
 ├─ SFX    slot list -> 32-row tracker -> SFX metadata/filter panel
 ├─ WAVE   waveform sample pairs through SFX; masked bass edit; mode raw/read-only
 ├─ FILE   seed/new, save, load, import, export, revisions
 ├─ MIX    playback start, mute/solo, profile, follow
 └─ HELP   context controls and field legend
```

SONG and SFX remember independent cursor and scroll positions. The common
header uses eight pixels: screen/index on the left, play/dirty/error glyphs on
the right. The footer uses up to twelve pixels for controls or a modal. The
remaining area is a scrolling viewport.

### 6.2 Input grammar

| State | D-pad | O | X |
|---|---|---|---|
| Navigate | Move focus/cursor | Enter field or primary action | Back / open context action |
| Edit value | Decrease/increase or move digit, depending on field | Accept / next field | Cancel and restore original value |
| Playback | Navigation remains active | Context audition/start | Stop / back |
| Confirm | Left/right selects choice | Confirm selected choice | Always cancel |

Holding O while pressing a direction may provide accelerated field changes.
O+X is reserved for an optional shortcut after touch validation. Required
commands remain reachable without chords.

### 6.3 Initial M1 views

M1 implements only the minimum path through this map:

- HOME with the seeded `strfld track 1` project;
- SONG focused on pattern 00 and its four SFX assignments/flags;
- SFX focused on slots 01..04 with 32 rows and metadata;
- FILE with save, reload, raw lossless export, and source reset;
- playback start/stop plus optional follow.

The old four-by-sixteen grid remains a prototype reference and is not the M1
model to extend.

## 7. Playback and non-destructive profiles

Normal projects call `music(pattern)` directly against the bank. A playback
profile is an ordered, versioned set of temporary transforms required to match
an imported source's runtime behavior.

For Starfield Track 1:

1. Snapshot all 64 data bytes in SFX 1..4.
2. For each conventional slot, add two to every nonzero row volume and cap at
   seven, exactly matching `music.lua` on canonical `shiptoast/pico-strfld` main at
   `e7e97ab01fdd1848e0b78f27191684412e60daf5`. A classified waveform slot is
   never transformed; its 64 samples and four metadata bytes stay exact.
3. Call `music(0)`.
4. On stop, leaving the project, save, checksum, or export of authored bytes,
   stop music and restore the snapshot first.

The profile must be idempotent. Repeated play commands may not compound the
boost. Editing while profiled playback is active uses one of two explicit
policies: stop/restore/edit/restart for M1, or a later dual-view accessor. M1
uses the simpler stop/restore path.

Standalone PICO audio export offers two labelled modes:

- **authored + profile:** exact raw bank plus Pocket Tracker metadata;
- **materialized:** apply the profile to exported bytes so plain `music(0)`
  sounds like Starfield, with no external Lua helper. Classification happens
  per slot before materialization so waveform bytes are never decoded as notes.

## 8. Persistence adapters

### 8.1 Native PICO-8

`cartdata()` stores only preferences and recovery metadata. A complete project
uses `cstore()` and is read with `reload()`.

Recommended safe flow:

1. Stop audio and restore temporary transforms.
2. Construct metadata and compute the bank/envelope checksum.
3. Write a dedicated, pre-existing project/data cart through `cstore()`.
4. Reload its data into staging memory.
5. Recompute the checksum and show success only on equality.

Writing the currently running tracker cart is supported only behind a named,
explicit confirmation because it ties the save to that cartridge version.
Fixed slot filenames avoid an on-screen keyboard in M1. Later project naming
can use a cartridge-native character picker.

### 8.2 Browser

The browser shell drives the same envelope over GPIO. It may store a
last-known-good project in local storage and download/upload JSON or `.p8`
files. File codecs operate on the validated durable envelope, not arbitrary
PICO-8 RAM; live commits still cross only the shared 128-byte GPIO boundary.

The existing wrapper's single 78-byte snapshot is replaced by a paged protocol
because a native bank is 4,608 bytes before metadata.

## 9. GPIO protocol boundary

Each frame is 128 bytes:

| Offset | Size | Meaning |
|---:|---:|---|
| 0 | 4 | ASCII magic `PTK2` |
| 4 | 1 | Protocol version |
| 5 | 1 | command/state |
| 6 | 1 | transfer id |
| 7 | 1 | sequence number modulo 256 |
| 8 | 2 | little-endian payload offset |
| 10 | 2 | little-endian total length |
| 12 | 1 | payload length, 0..112 |
| 13 | 1 | flags (first, last, direction, retry) |
| 14 | 2 | CRC-16/CCITT for header fields and payload |
| 16 | 112 | payload |

M1.4A commands cover save-page, acknowledge, load-page, load-commit, done,
load-request, and error. The producer owns a frame until the consumer echoes
its transfer id and sequence in an acknowledgement. An exact retry of the
immediately preceding frame (same transfer, sequence, offset, length, and frame
CRC) is acknowledged without applying twice. Other old or future pages are
rejected as out of order. A commit succeeds only after total length, total
checksum, format version, complete fixed playback-profile/source-selection
semantics, and staged-bank validation pass.

At 112 payload bytes, the 4,672-byte M1.4A envelope needs 42 pages. The PICO side processes at
most one page per update and keeps rendering/input responsive. Both sides time
out to IDLE without touching the canonical bank.

JavaScript responsibilities are deliberately narrow:

- select/read a file or local revision;
- parse/serialize deterministic JSON and `.p8` text audio sections;
- page an already validated envelope through GPIO;
- download/store bytes received from the cartridge;
- report bridge-level errors.

All note edits, profiles, playback, dirty state, and confirmation live in Lua.

## 10. Import/export codecs

### `.p8` import

The browser codec locates exact `__music__` and `__sfx__` section boundaries,
validates hexadecimal line lengths/counts, decodes field-aware SFX rows and
pattern flags, and produces a raw 4,608-byte bank. Missing trailing rows are
zero-filled exactly as PICO-8 would; malformed non-hex content is rejected.

Native import uses `reload(staging, 0x3100, 0x1200, filename)` from a fixed data
cart and then the same in-cart bank validator.

M1.4B exposes JSON import in the browser Files panel. The `.p8` decoder is
retained as a deterministic export verifier; user-facing `.p8` import remains a
later native/data-cart sub-arc rather than bypassing staged project commit.

### `.p8` export

The browser codec emits only audio sections or inserts them into a documented
template. It must not claim to preserve unrelated source-cartridge formatting.
Song flag bits are converted back into the two-digit prefix and muted channel
bytes; SFX note words are converted into five-digit field order, not dumped as
little-endian words.

The lossless Pocket Tracker JSON is the round-trip authority because it also
retains project metadata and playback profile.

## 11. Verification strategy

### Static and unit checks

- Address functions at all first/last valid indices and rejected boundaries.
- Getter/setter bit preservation for every song and note field.
- `.p8` text codec golden tests, including muted channels and all three flow
  flags.
- Conventional metadata/filter combinations and waveform-mode preservation.
- CRC, envelope, staging/commit, and interrupted transaction tests.
- Code token, character, compressed-size, and generated-export freshness gates.

### Cartridge integration checks

- Fixture reload produces exact expected pattern/SFX bytes.
- `music(0)` drives SFX 1,2,3,4 on channels 0..3.
- `stat(54)` reports pattern 0 and `stat(57)` is true during playback.
- `stat(55)` advances after the pattern and playback loops to pattern 0.
- Editing one field changes only its owned bits and is immediately audible.
- Save, mutation, reload restores the full bank and profile checksum.

### Browser checks

- Real exported cart completes both transfer directions.
- Corrupt, repeated, omitted, reordered, stale, cancelled, and oversized frames
  are handled without partial commit.
- Desktop and touch controls can reach every required M1 action.
- Authored and materialized exports re-import with their documented equality
  rules.

## 12. Budget discipline

Record `INFO` output and the exact PICO-8 executable version at every milestone.
M1 should reserve at least 20% of the 8,192-token and 15,360-compressed-byte
limits for M2/M3 parity. Generated browser files are outputs; source changes go
to Lua and the small wrapper module, followed by a fresh export from the exact
tested commit/worktree. A source cart and checked-in browser export from
different revisions are unshippable: `tracker.html` and `tracker.js` must be
regenerated and verified before commit, publication, or release.

Raw audio lives in the cartridge data sections and does not consume Lua table
tokens. Prefer small masked accessors, data-driven screen definitions, and
shared list widgets. Do not minify until measured limits demand it.

## 13. Rejected alternatives

- **Extend the 4x16 table model.** It loses native semantics and makes imports
  lossy by construction.
- **JavaScript as the real editor.** It violates cartridge-only operation and
  creates a second behavior model.
- **JavaScript WAV as fidelity proof.** It approximates instruments/effects and
  cannot prove PICO-8 mixer equivalence.
- **`cartdata()` for complete projects.** It is 18x too small even before
  metadata.
- **Encode the bank as Lua literals.** It wastes code characters/compression
  and duplicates audio RAM.
- **Write imports directly into `0x3100`.** An interrupted transfer would leave
  a half-old, half-new song.
