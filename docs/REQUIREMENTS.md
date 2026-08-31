# Pocket Tracker product requirements

Status: architecture baseline for Milestone 1 (M1)

Target runtime: PICO-8 0.2.7 / text cartridge version 43

Normative words: **must**, **should**, and **may** carry their usual RFC-style
meanings.

## 1. Product definition

Pocket Tracker is a music workstation that runs as a PICO-8 cartridge. A user
must be able to author, audition, arrange, save, and recover PICO-8 music from
the running cartridge with only the standard D-pad, O, and X controls. The
browser shell may make files easier to move, but it must not become the editor
or the source of audio behavior.

The compatibility target is the practical music-authoring surface of the
current PICO-8 SFX and music editors, presented with an LSDJ-like, screen-based
workflow. Compatibility means that a supported project can be represented by
PICO-8's native song and SFX bytes and plays through PICO-8's native `music()`
and `sfx()` functions without a replacement synthesizer.

M1 is narrower: load Starfield's title-menu **Track 1**, reproduce its actual
sound and timing, edit it in the cartridge, save and reload it, and export it
without silent data loss. See [M1_TRACK_1_SPEC.md](M1_TRACK_1_SPEC.md).

## 2. Goals and non-goals

### Goals

- Entire editing workflow is usable on a 128x128 display with six buttons.
- Native PICO-8 audio memory is the authoritative song representation.
- All 64 song patterns, four music channels, and all 64 SFX slots are
  addressable.
- All sound-affecting note, SFX, and music-pattern fields are preserved on
  import, edit, save, reload, and export.
- Playback uses the PICO-8 mixer so the editor is a trustworthy preview of a
  target cartridge.
- Native PICO-8 and browser builds share the same editor and project model.
- File and bridge operations are transactional: invalid or interrupted input
  cannot partially replace the current song.
- The implementation remains exportable as a normal PICO-8 HTML or PNG/ROM
  cartridge within platform limits.

### Non-goals for the parity release

- Editing Lua, sprites, maps, flags, or labels.
- Reimplementing PICO-8 synthesis in Lua or JavaScript.
- Acting as a full DAW, MIDI host, or sample recorder.
- Guaranteeing that browser-rendered WAV previews are sample-identical to
  PICO-8. A WAV helper is a convenience artifact, not the project authority.
- Supporting arbitrary host filesystem navigation from a sandboxed cartridge.
- Adding LSDJ song-chain, table, groove, or performance systems before native
  PICO-8 audio parity is stable.

## 3. Compatibility scope

### 3.1 Must-have PICO-8 parity

| Area | Required capability |
|---|---|
| Song patterns | Select and edit 64 patterns; four channel assignments per pattern; channel mute; loop-start, loop-back, and stop flags. |
| SFX rows | Select and edit 64 SFX, each with 32 rows; pitch/rest, built-in or custom instrument, volume, and effect on every row. |
| SFX timing | Edit speed, loop start/end, and the `LEN` case where the first marker is set and the second is zero. Preserve unequal channel speeds and PICO-8's left-most non-looping-channel pattern timing. |
| SFX filters | Preserve and edit NOIZ, BUZZ, both DETUNE levels, both REVERB levels, and both DAMPEN levels. Unknown/reserved metadata bits must survive round-trips. |
| Instruments | Support the eight built-in instruments and SFX instruments 0-7, including their pitch/volume/effect composition behavior. |
| Waveform instruments | Preserve and eventually edit PICO-8 0.2.6+ waveform-instrument samples, waveform mode, and bass state in SFX 0-7. Import/export must be lossless before the dedicated waveform UI ships. |
| Playback | Start/stop a song at any pattern; audition an SFX or row; expose current pattern, row, and active channels; mute/solo for audition without rewriting project bytes. |
| Editing | Single-field edits, rest insertion, selection, copy/paste, clear, and bounded undo/redo. Operations must preserve fields they do not own. |
| Project I/O | Import and export native audio sections and the lossless Pocket Tracker envelope; save and reload at least one complete project in every supported runtime. |
| Controls | Every required command works through D-pad, O, and X. Keyboard, mouse, and browser controls may accelerate but never gate a capability. |

Waveform instruments are included because they are part of the current PICO-8
music editor. Their UI can land after conventional SFX editing, but the raw
68-byte slot must be preserved from the first importer onward.

### 3.2 Later LSDJ-style enhancements

These are product extensions, not PICO-8 compatibility requirements:

- Phrase/chains that compile into the 64 native music patterns.
- Instrument macros and per-tick tables.
- Groove templates, swing, probability, conditional steps, and pattern
  transposition.
- Bookmarks, performance scenes, live pattern queueing, and song sections.
- Named instruments, cloning, deduplication, dependency views, and safe SFX
  allocation when pasting patterns.
- More than one undo snapshot, autosave history, crash recovery, and project
  library/search.
- MIDI, OSC, stems, polished WAV rendering, and share links.

Extensions must compile to an explicit native-bank snapshot before playback or
export. They must never make the native bytes ambiguous.

## 4. Functional requirements

### 4.1 Cartridge UX

- **UX-001** On boot, the cart must show project identity, dirty/save state,
  and a clear path into SONG and SFX screens.
- **UX-002** The D-pad moves a cursor or changes the focused value; O performs
  the primary edit/confirm action; X performs secondary/back/cancel.
- **UX-003** Holding a button may repeat movement, but one press must always
  make one deterministic change.
- **UX-004** Destructive actions require a confirmation state that names the
  target and can be cancelled with X.
- **UX-005** A persistent header must identify screen, pattern/SFX index,
  playback state, and dirty state.
- **UX-006** Long grids must scroll around the cursor. The cursor may not leave
  the visible viewport after navigation or playback follow.
- **UX-007** Playback-follow must be optional; editing may not be blocked while
  a song is playing unless PICO-8 itself cannot apply the edit safely.
- **UX-008** Numeric fields must support single-step and accelerated changes.
  All values wrap or clamp consistently and visibly.
- **UX-009** O+X chords may be shortcuts, but no required command may depend on
  a chord that common mobile overlays cannot generate reliably.
- **UX-010** Errors and completed I/O operations must remain visible until
  acknowledged; transient toast text alone is insufficient for data loss.

### 4.2 Audio editing and playback

- **AUD-001** Song bytes at `0x3100..0x31ff` and SFX bytes at
  `0x3200..0x42ff` are the canonical editable bank.
- **AUD-002** A note edit must change only the documented bits for that field.
  Custom-instrument and reserved bits must not be cleared accidentally.
- **AUD-003** A metadata edit must preserve unknown bits and waveform mode.
- **AUD-004** Playback must call native `music()` / `sfx()` against the
  canonical bank; a shadow representation may not drift from audible memory.
- **AUD-005** Song audition must respect PICO-8 pattern flags, channel mutes,
  differing SFX speeds, loop markers, `LEN`, filters, effects, custom SFX
  instruments, and waveform instruments.
- **AUD-006** Mute and solo used only for audition must live outside the bank.
- **AUD-007** The editor must stop or reserve playback channels deliberately
  before an audition; accidental overlap is a bug.
- **AUD-008** Import must reject malformed ranges and must stage data before
  replacing the current bank.
- **AUD-009** The editor must expose raw hexadecimal inspection for fields it
  can preserve but does not yet provide a semantic editor for.

### 4.3 Persistence

- **PER-001** A complete native audio bank is 4,608 bytes: 256 song bytes plus
  4,352 SFX bytes. No complete-save design may assume it fits in the 256-byte
  `cartdata()` area.
- **PER-002** Save and load must include the full native bank and Pocket Tracker
  metadata that affects audition or export.
- **PER-003** Save must be explicit, transactional where the runtime permits,
  and followed by a read-back checksum before success is shown.
- **PER-004** `cartdata()` may retain UI preferences, last screen/cursor, and a
  small recovery marker. It is not the primary project store.
- **PER-005** Native PICO-8 may use `cstore()` / `reload()` with a dedicated
  project cart or explicitly confirmed current-cart storage.
- **PER-006** Browser storage must be namespaced by project format/version and
  retain at least one last-known-good revision.
- **PER-007** A failed load, checksum mismatch, cancelled cart swap, or browser
  refresh during transfer must leave the previous in-RAM project intact.
- **PER-008** Format migrations must be explicit and one-way per saved copy;
  unknown future versions must be rejected without mutation.
- **PER-009** The browser project library must retain multiple checksum-verified
  projects and a bounded revision history without changing the existing
  last-known-good key or GPIO/file formats.
- **PER-010** Choosing a browser-library revision may replace only the durable
  staging slot. The live project changes only after the existing tracker Load
  transaction validates and commits that slot.

### 4.4 Import and export

- **IO-001** Importers must accept a Pocket Tracker lossless project and the
  `__music__` / `__sfx__` sections of a text `.p8` cartridge.
- **IO-002** A native data-cart import must use a fixed, visible slot or a
  project name selected wholly in-cart; browser file pickers are optional
  adapters.
- **IO-003** Export must offer a lossless project envelope containing the raw
  4,608-byte bank, format version, source/provenance when known, and playback
  profile.
- **IO-004** Text-cartridge export must emit valid, deterministic `__music__`
  and `__sfx__` sections with lowercase hexadecimal and stable ordering.
- **IO-005** Import followed by lossless export without edits must reproduce
  the same audio bank byte-for-byte, including muted channels, filters,
  waveform data, and reserved bits.
- **IO-006** If an external source uses a runtime playback transform, the
  project must preserve that transform as metadata or explicitly materialize
  it. The UI and export must say which representation is active.
- **IO-007** Browser JavaScript may transport, validate, serialize, download,
  and store bytes. It may not own editing rules or produce the authoritative
  preview.
- **IO-008** GPIO transfer must be framed, versioned, checksummed, acknowledged,
  cancellable, and safe across duplicate or dropped animation frames.
- **IO-009** WAV export, when present, must be labelled an approximation unless
  it is produced by the same PICO-8 runtime and bank as the cartridge preview.

### 4.5 Quality and accessibility

- **QLT-001** Every binary accessor and transform must have boundary tests.
- **QLT-002** Golden fixtures must record source repository, exact commit, raw
  source lines, and a content checksum.
- **QLT-003** Acceptance tests must exercise real PICO-8 playback state with
  `stat(46..57)`, not only a Lua-side playhead approximation.
- **QLT-004** Browser bridge tests must cover duplicate, missing, reordered,
  corrupt, cancelled, and version-mismatched frames.
- **QLT-005** Colors may aid focus but may not be the only focus, mute, dirty,
  or error indicator.
- **QLT-006** A user must be able to abandon any modal operation with X without
  changing project bytes.
- **QLT-007** Browser project and revision controls must be labelled native
  controls usable by keyboard and touch. Project or revision deletion requires
  an explicit confirmation, and cancellation is a no-op.

## 5. Platform budgets and constraints

| Resource | Hard fact | Product consequence |
|---|---:|---|
| Display | 128x128, 16 colors | One focused job per screen; scrolling grids; no desktop-style four-pane editor. |
| Input | D-pad + O + X | Mode/state clarity is more important than dense shortcuts. |
| Audio | 4 channels; 64 SFX x 32 rows | Store/edit the native bank rather than inventing a smaller 4x16 model. |
| Song RAM | 256 bytes at `0x3100` | 64 patterns x 4 bytes. |
| SFX RAM | 4,352 bytes at `0x3200` | 64 slots x 68 bytes. |
| Persistent cart data | 256 bytes at `0x5e00` | Preferences/recovery only; full bank requires another persistence path. |
| Browser GPIO | 128 bytes at `0x5f80` | Full projects require a multi-frame protocol. |
| Code | 8,192 tokens; 65,535 characters | Track token, character, and compressed-size budgets in CI. |
| Exported code | 12,288 compressed bytes | Preserve the post-M3 release reserve and measure real HTML/PNG export. |
| CPU | 4M VM instructions/sec | Bound work per frame; transport and checksums advance incrementally. |

Source for platform limits and audio behavior: the
[official PICO-8 manual](https://www.lexaloffle.com/dl/docs/pico-8_manual.html).

The checked-in prototype's four channels x sixteen steps, one instrument per
channel, 78-byte slot, and JavaScript WAV synthesizer are useful interaction
experiments. They are not sufficient as the compatibility data model.

## 6. Milestones

1. **M1 — Starfield Track 1:** provenance fixture, native-bank model, focused
   song/SFX editing, faithful playback profile, one durable save/load path,
   deterministic lossless export, and the acceptance suite in the M1 spec.
2. **M2 — Conventional PICO-8 parity:** all 64 patterns/SFX, all standard note
   fields, pattern flow, SFX timing, filters, copy/paste, and bounded undo.
3. **M3 — Complete modern audio parity:** custom SFX instruments, waveform
   instrument preservation/editing, native data-cart workflow, and robust
   browser `.p8` import/export.
4. **M4 — Handheld polish (complete):** project browser, multiple revisions,
   recovery, input acceleration, help overlays, mobile/browser validation, and
   release budget gates. Exact closure evidence is recorded in section 20 of
   the M1 implementation specification.
5. **M5 — LSDJ extensions:** chains/phrases, grooves, tables/macros,
   performance mode, and optional external integrations.

## 7. Decisions requiring Nick

1. **M1 volume representation.** Current Starfield Track 1 is audibly boosted
   by `+2` volume steps at runtime, capped at 7, while the cartridge restores
   the authored bytes afterward. Recommendation: retain the authored bank plus
   a non-destructive playback profile; lossless export keeps both, while a
   standalone `.p8` export can deliberately materialize the boost.
2. **Native save target.** Recommendation: default to a dedicated project/data
   cart and require confirmation before writing the tracker cart itself.
   Overwriting the current cart is simpler but couples saves to that exact cart
   version.
3. **Waveform-instrument milestone.** Recommendation: lossless preservation in
   M1/M2 and a dedicated editor in M3. Requiring the waveform editor in M1
   would delay the Track 1 goal without improving its fidelity.
4. **Project publication.** The public repository is `NickTitle/picodj`, with
   reviewed arcs merged through focused pull requests. Publication ownership
   and visibility are resolved; each new arc remains gated on exact-head
   review before merge.
