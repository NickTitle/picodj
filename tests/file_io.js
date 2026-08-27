'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

class MemoryStorage {
  constructor() { this.values = new Map(); }
  getItem(key) { return this.values.has(key) ? this.values.get(key) : null; }
  setItem(key, value) { this.values.set(key, String(value)); }
  removeItem(key) { this.values.delete(key); }
}

const gpio = new Array(128).fill(0);
const localStorage = new MemoryStorage();
let guard = null;
const frameDocument = {
  head: {appendChild(node) { guard = node; }},
  createElement() { return {id: '', textContent: ''}; },
  getElementById(id) { return guard?.id === id ? guard : null; },
  addEventListener() {},
};
const cart = {contentDocument: frameDocument, contentWindow: {pico8_gpio: gpio}, addEventListener() {}};
const control = {addEventListener() {}};
const sandbox = {
  Blob,
  URL,
  localStorage,
  document: {
    querySelector(selector) { return selector === '#cart' ? cart : control; },
    createElement() { return {click() {}, remove() {}}; },
    body: {appendChild() {}},
  },
  requestAnimationFrame() {},
  setTimeout() {},
};
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync('mobile.js', 'utf8'), sandbox);
const io = sandbox.PocketTrackerProjectIO;
const files = sandbox.PocketTrackerFileIO;

function put16(bytes, offset, value) {
  bytes[offset] = value & 255;
  bytes[offset + 1] = value >> 8;
}

function envelopeFixture() {
  const bytes = new Uint8Array(4672);
  bytes.set([80, 84, 80, 50, 2, 64]);
  put16(bytes, 6, bytes.length);
  put16(bytes, 12, 37);
  bytes[14] = 1;
  bytes[15] = 1;
  const name = Buffer.from('strfld track 1');
  bytes[16] = name.length;
  bytes.set(name, 17);
  const provenance = Buffer.from('e7e97ab track 1');
  bytes[32] = provenance.length;
  bytes.set(provenance, 33);
  bytes.set([0, 1, 4], 56);
  for (let i = 64; i < bytes.length; i++) bytes[i] = (i * 37 + 11) & 255;
  for (let sfx = 1; sfx <= 4; sfx++) bytes[64 + 0x100 + sfx * 68 + 66] &= 0x7f;
  put16(bytes, 8, io.crc16(bytes, 64));
  put16(bytes, 10, io.crc16(bytes, 0, bytes.length, 10, 12));
  return bytes;
}

const envelope = envelopeFixture();
for (const kind of [0, 1, 2]) for (const version of [0, 1, 2]) {
  for (const start of [0, 1, 2]) for (const count of [0, 1, 4, 5]) {
    const vector = envelope.slice();
    vector.set([kind, version], 14);
    vector.set([0, start, count], 56);
    put16(vector, 10, 0);
    put16(vector, 10, io.crc16(vector, 0, vector.length, 10, 12));
    assert.equal(io.envelopeValid(vector),
      kind === 0 && version === 0 && start === 0 && count === 0 ||
      kind === 1 && version === 1 && start === 1 && count === 4,
      `profile tuple ${kind}/${version}/${start}/${count}`);
  }
}
const json = io.projectJson(envelope);
assert.equal(typeof json, 'string');
assert.equal(io.projectJson(envelope), json, 'JSON encoding is deterministic');
assert.deepEqual(Array.from(io.parseProjectJson(json)), Array.from(envelope),
  'lossless JSON round-trip reproduces the exact envelope');
let cycled = envelope;
for (let pass = 0; pass < 3; pass++) cycled = io.parseProjectJson(io.projectJson(cycled));
assert.deepEqual(Array.from(cycled), Array.from(envelope), 'three JSON cycles do not accumulate changes');

const decoded = JSON.parse(json);
assert.deepEqual(Object.keys(decoded),
  ['format', 'version', 'project', 'source', 'playbackProfile', 'bank', 'checksum']);
assert.equal(decoded.project.name, 'strfld track 1');
assert.equal(decoded.source.provenance, 'e7e97ab track 1');
assert.deepEqual(decoded.playbackProfile, {
  kind: 'track-1-volume-boost', version: 1, sfxStart: 1, sfxCount: 4, volumeBoost: 2,
});
assert.equal(decoded.bank.data.length, 4608 * 2);
assert.doesNotMatch(json, /gpio|bridge|undo|snapshot|audition|temporary/i,
  'file JSON contains only canonical project state');

function malformed(mutator) {
  const value = JSON.parse(json);
  mutator(value);
  return JSON.stringify(value);
}
assert.equal(io.parseProjectJson(malformed((value) => { value.project.revision = -1; })), null);
assert.equal(io.parseProjectJson(malformed((value) => { value.project.name = '0123456789abcdef'; })), null);
assert.equal(io.parseProjectJson(malformed((value) => { value.source.pattern = 64; })), null);
assert.equal(io.parseProjectJson(malformed((value) => { value.playbackProfile.sfxStart = 2; })), null);
assert.equal(io.parseProjectJson(malformed((value) => { value.bank.length = 4607; })), null);
assert.equal(io.parseProjectJson(malformed((value) => { value.bank.data = `ff${value.bank.data.slice(2)}`; })), null);
assert.equal(io.parseProjectJson(malformed((value) => { value.temporary = {}; })), null);

assert.equal(io.storeLastKnownGood(envelope), true);
let stable = localStorage.getItem(io.key);
assert.equal(files.importProjectJson('{"format":"pocket-tracker-project"}'), false);
assert.equal(localStorage.getItem(io.key), stable, 'malformed import leaves durable data untouched');
const imported = envelope.slice();
put16(imported, 12, 38);
put16(imported, 10, 0);
put16(imported, 10, io.crc16(imported, 0, imported.length, 10, 12));
const gpioBeforeImport = gpio.slice();
assert.equal(files.importProjectJson(io.projectJson(imported)), true);
assert.deepEqual(Array.from(io.loadLastKnownGood()), Array.from(imported),
  'valid import commits the exact validated envelope to the durable slot');
assert.deepEqual(gpio, gpioBeforeImport, 'file import never mutates live GPIO or cartridge state');
stable = localStorage.getItem(io.key);
assert.equal(files.exportStoredFile('json'), true);
assert.equal(files.exportStoredFile('authored'), true);
assert.equal(files.exportStoredFile('materialized'), true);
assert.equal(files.exportStoredFile('unknown'), false);
const faultStorage = new MemoryStorage();
faultStorage.setItem(io.key, stable);
faultStorage.setItem = function() { throw new Error('quota'); };
assert.equal(files.importProjectJson(json, faultStorage), false);
assert.equal(faultStorage.getItem(io.key), stable, 'storage fault preserves prior durable data');

const authored = io.p8Audio(envelope, 'authored');
assert.equal(io.p8Audio(envelope, 'authored'), authored, 'authored PICO-8 encoding is deterministic');
assert.match(authored, /^pico-8 cartridge \/\/ http:\/\/www\.pico-8\.com\nversion 43\n/);
assert.match(authored, /-- representation: authored\+profile/);
const authoredParsed = io.parseP8Audio(authored);
assert.deepEqual(Array.from(authoredParsed.bank), Array.from(envelope.slice(64)),
  'authored PICO-8 audio sections round-trip byte-exactly');
assert.deepEqual(Array.from(authoredParsed.header), Array.from(envelope.slice(0, 64)),
  'authored PICO-8 export carries the metadata and playback-profile header');
const materialized = io.p8Audio(envelope, 'materialized');

const gpioBeforeP8Import = gpio.slice();
assert.equal(files.importProjectP8(authored), true);
assert.deepEqual(Array.from(io.loadLastKnownGood()), Array.from(envelope),
  'authored PICO-8 import stores the exact validated envelope');
assert.deepEqual(gpio, gpioBeforeP8Import, 'authored PICO-8 import never mutates live GPIO');
const authoredBlocks = authored.split('\n');
const sfxStart = authoredBlocks.indexOf('__sfx__');
const musicStart = authoredBlocks.indexOf('__music__');
const reordered = [...authoredBlocks.slice(0, sfxStart),
  ...authoredBlocks.slice(musicStart, musicStart + 65),
  ...authoredBlocks.slice(sfxStart, musicStart), ''].join('\n');
assert.equal(files.importProjectP8(reordered), true, 'authored sections may appear in either order');
assert.deepEqual(Array.from(io.loadLastKnownGood()), Array.from(envelope),
  'reordered authored sections reconstruct the exact envelope');
for (let pass = 0; pass < 3; pass++) {
  const cycle = io.p8Audio(io.loadLastKnownGood(), 'authored');
  assert.equal(files.importProjectP8(cycle), true, `authored PICO-8 cycle ${pass + 1}`);
  assert.deepEqual(Array.from(io.loadLastKnownGood()), Array.from(envelope),
    `authored PICO-8 cycle ${pass + 1} remains byte-exact`);
}

const p8Stable = localStorage.getItem(io.key);
const rejectP8 = (raw, result, label) => {
  const gpioBefore = gpio.slice();
  assert.equal(files.importProjectP8(raw), result, label);
  assert.equal(localStorage.getItem(io.key), p8Stable, `${label} preserves durable slot`);
  assert.deepEqual(gpio, gpioBefore, `${label} preserves live GPIO`);
};
const withHeader = (bytes, raw = authored) => raw.replace(
  /^-- pocket-tracker-header: [0-9a-f]{128}$/m,
  `-- pocket-tracker-header: ${Buffer.from(bytes.slice(0, 64)).toString('hex')}`);
const checksumHeader = (mutator) => {
  const bytes = envelope.slice();
  mutator(bytes);
  put16(bytes, 10, 0);
  put16(bytes, 10, io.crc16(bytes, 0, bytes.length, 10, 12));
  return withHeader(bytes);
};
const authoredLines = authored.split('\n');
const partialSection = (name) => {
  const lines = [...authoredLines];
  lines.splice(lines.indexOf(name) + 1, 1);
  return lines.join('\n');
};
const sidecar = authored.match(/^-- pocket-tracker-header: [0-9a-f]{128}$/m)[0];
rejectP8(authored.replace(sidecar, `${sidecar}\n${sidecar}`), false, 'duplicate sidecar');
rejectP8(authored.replace(sidecar, `${sidecar.slice(0, -1)}g`), false, 'malformed sidecar');
rejectP8(authored.replace(sidecar, '-- pocket-tracker-header : malformed'), false,
  'malformed header marker never downgrades');
rejectP8(authored.replace('__sfx__', ''), false, 'missing SFX section');
rejectP8(`${authored}\n__sfx__\n`, false, 'duplicate SFX section');
rejectP8(authored.replace('__music__', ''), false, 'missing music section');
rejectP8(`${authored}\n__music__\n`, false, 'duplicate music section');
rejectP8(partialSection('__sfx__'), false, 'partial SFX section');
rejectP8(partialSection('__music__'), false, 'partial music section');
rejectP8(authored.replace(/^[0-9a-f]{168}$/m, (line) => `g${line.slice(1)}`), false,
  'malformed SFX section');
rejectP8(authored.replace(/^[0-9a-f]{2} [0-9a-f]{8}$/m, 'ff 00000000'), false,
  'malformed music section');
rejectP8(authored.replace(/^([0-9a-f]{8})([0-9a-f]{2})/m,
  (_, metadata, pitch) => `${metadata}${pitch === '00' ? '01' : '00'}`), false,
  'sidecar bank CRC mismatch');
rejectP8(withHeader(envelope.slice().fill(0, 10, 12)), false, 'sidecar envelope CRC mismatch');
rejectP8(checksumHeader((bytes) => { bytes[0] = 0; }), false, 'unknown envelope magic');
rejectP8(checksumHeader((bytes) => { bytes[4] = 3; }), false, 'unknown envelope version');
rejectP8(checksumHeader((bytes) => { bytes[6] = 0; }), false, 'wrong envelope length');
rejectP8(checksumHeader((bytes) => { bytes[15] = 2; }), false, 'unknown profile version');
rejectP8(checksumHeader((bytes) => { bytes[56] = 1; }), false, 'unknown source selection');
rejectP8(checksumHeader((bytes) => { bytes[16] = 16; }), false, 'overlong project text');
rejectP8(checksumHeader((bytes) => { bytes[8] ^= 1; }), false, 'sidecar bank checksum');

const p8FaultStorage = new MemoryStorage();
p8FaultStorage.setItem(io.key, p8Stable);
p8FaultStorage.setItem = function() { throw new Error('quota'); };
assert.equal(files.importProjectP8(authored, p8FaultStorage), false);
assert.equal(p8FaultStorage.getItem(io.key), p8Stable,
  'authored PICO-8 storage failure preserves prior durable data');
const p8ReadBackStorage = new MemoryStorage();
p8ReadBackStorage.setItem(io.key, p8Stable);
const p8NormalGet = p8ReadBackStorage.getItem.bind(p8ReadBackStorage);
let p8Writes = 0;
p8ReadBackStorage.setItem = function(key, value) {
  MemoryStorage.prototype.setItem.call(this, key, value);
  p8Writes++;
};
p8ReadBackStorage.getItem = function(key) {
  const value = p8NormalGet(key);
  if (p8Writes !== 1 || value === null) return value;
  p8Writes++;
  return `${value.slice(0, -1)}x`;
};
assert.equal(files.importProjectP8(authored, p8ReadBackStorage), false);
assert.equal(p8ReadBackStorage.getItem(io.key), p8Stable,
  'authored PICO-8 read-back failure restores prior durable data');

const gpioBeforeRawImport = gpio.slice();
assert.equal(files.importProjectP8(materialized, localStorage, 'folder/Materialized ★.p8'), 'raw');
const noneEnvelope = io.loadLastKnownGood();
assert.deepEqual(Array.from(noneEnvelope.slice(14, 16)), [0, 0]);
assert.deepEqual(Array.from(noneEnvelope.slice(56, 59)), [0, 0, 0]);
assert.equal(noneEnvelope[12] | (noneEnvelope[13] << 8), 0);
assert.equal(Buffer.from(noneEnvelope.slice(17, 32)).toString().replace(/\0.*$/, ''),
  'Materialized _');
assert.equal(Buffer.from(noneEnvelope.slice(33, 56)).toString().replace(/\0.*$/, ''),
  'Materialized _');
assert.deepEqual(Array.from(noneEnvelope.slice(64)), Array.from(io.parseP8Audio(materialized).bank));
assert.deepEqual(gpio, gpioBeforeRawImport, 'headerless import leaves live GPIO untouched');
const noneJson = io.projectJson(noneEnvelope);
assert.equal(JSON.parse(noneJson).playbackProfile, null);
assert.deepEqual(Array.from(io.parseProjectJson(noneJson)), Array.from(noneEnvelope),
  'profile-none JSON round-trips exactly');
const noneAuthored = io.p8Audio(noneEnvelope, 'authored');
assert.match(noneAuthored, /pocket-tracker-header:/);
assert.equal(files.importProjectP8(noneAuthored), true);
assert.deepEqual(Array.from(io.loadLastKnownGood()), Array.from(noneEnvelope),
  'profile-none authenticated sidecar re-imports exactly');
assert.deepEqual(Array.from(io.materializedBank(noneEnvelope)), Array.from(noneEnvelope.slice(64)));
const noneMaterialized = io.p8Audio(noneEnvelope, 'materialized');
assert.deepEqual(Array.from(io.parseP8Audio(noneMaterialized).bank), Array.from(noneEnvelope.slice(64)));
for (let pass = 0; pass < 3; pass++) {
  assert.equal(files.importProjectP8(noneMaterialized, localStorage, 'Materialized _.p8'), 'raw');
  const cycle = io.loadLastKnownGood();
  assert.deepEqual(Array.from(cycle), Array.from(noneEnvelope), `profile-none cycle ${pass + 1}`);
}
assert.equal(files.importProjectP8('__sfx__\n__music__\n', localStorage, '.p8'), 'raw');
const fallback = io.loadLastKnownGood();
assert.equal(Buffer.from(fallback.slice(17, 32)).toString().replace(/\0.*$/, ''), 'imported p8');
assert.equal(Buffer.from(fallback.slice(33, 56)).toString().replace(/\0.*$/, ''), 'browser p8');

const rawStable = localStorage.getItem(io.key);
const rejectRaw = (raw, label) => {
  const gpioBefore = gpio.slice();
  assert.equal(files.importProjectP8(raw, localStorage, 'raw.p8'), false, label);
  assert.equal(localStorage.getItem(io.key), rawStable, `${label} preserves durable slot`);
  assert.deepEqual(gpio, gpioBefore, `${label} preserves GPIO`);
};
rejectRaw(`${materialized}\n__music__\n`, 'duplicate headerless music section');
rejectRaw(materialized.replace('__sfx__', ''), 'missing headerless SFX section');
rejectRaw(materialized.replace(/^[0-9a-f]{168}$/m, (line) => `g${line.slice(1)}`),
  'malformed headerless SFX line');

assert.equal(io.p8Audio(envelope, 'materialized'), materialized,
  'materialized PICO-8 encoding is deterministic');
assert.match(materialized, /-- representation: materialized/);
assert.doesNotMatch(materialized, /pocket-tracker-header:/,
  'materialized export has no required playback profile');
const materializedParsed = io.parseP8Audio(materialized);
assert.deepEqual(Array.from(materializedParsed.bank), Array.from(io.materializedBank(envelope)));
assert.equal(materializedParsed.header, null);
assert.deepEqual(Array.from(materializedParsed.bank.slice(0, 0x100)),
  Array.from(envelope.slice(64, 64 + 0x100)), 'materialization leaves all patterns unchanged');
for (let sfx = 1; sfx <= 4; sfx++) {
  const base = 0x100 + sfx * 68;
  for (let row = 0; row < 32; row++) {
    const source = envelope[64 + base + row * 2] | (envelope[64 + base + row * 2 + 1] << 8);
    const output = materializedParsed.bank[base + row * 2] | (materializedParsed.bank[base + row * 2 + 1] << 8);
    const volume = (source >> 9) & 7;
    const expected = volume === 0 ? source : (source & 0xf1ff) | (Math.min(7, volume + 2) << 9);
    assert.equal(output, expected, `materialized SFX ${sfx} row ${row}`);
  }
}

const nativeWaveform = io.parseP8Audio(fs.readFileSync('tests/fixtures/pico8-027-waveform.p8', 'utf8'));
const waveformEnvelope = envelope.slice();
const waveformBase = 64 + 0x100;
for (let sample = 0; sample < 64; sample++) waveformEnvelope[waveformBase + sample] = (sample * 29 + 7) & 255;
waveformEnvelope[waveformBase] = 0x00;
waveformEnvelope[waveformBase + 1] = 0x7f;
waveformEnvelope[waveformBase + 62] = 0x80;
waveformEnvelope[waveformBase + 63] = 0xff;
waveformEnvelope[waveformBase + 64] = 0xd0;
waveformEnvelope[waveformBase + 65] = 0xa5;
waveformEnvelope[waveformBase + 66] |= 0x80;
for (const sfx of [1, 4]) {
  waveformEnvelope.set(waveformEnvelope.slice(waveformBase, waveformBase + 68),
    64 + 0x100 + sfx * 68);
}
const customReferenceBase = 64 + 0x100 + 8 * 68;
put16(waveformEnvelope, customReferenceBase, 0x8a58);
put16(waveformEnvelope, customReferenceBase + 2, 0x8b18);
put16(waveformEnvelope, 8, io.crc16(waveformEnvelope, 64));
put16(waveformEnvelope, 10, 0);
put16(waveformEnvelope, 10, io.crc16(waveformEnvelope, 0, waveformEnvelope.length, 10, 12));
assert.deepEqual(Array.from(io.parseProjectJson(io.projectJson(waveformEnvelope))),
  Array.from(waveformEnvelope), 'waveform samples round-trip through lossless JSON');
for (const representation of ['authored', 'materialized']) {
  const parsed = io.parseP8Audio(io.p8Audio(waveformEnvelope, representation));
  for (const sfx of [0, 1, 4]) {
    const bankBase = 0x100 + sfx * 68;
    const envelopeBase = 64 + bankBase;
    assert.deepEqual(Array.from(parsed.bank.slice(bankBase, bankBase + 68)),
      Array.from(waveformEnvelope.slice(envelopeBase, envelopeBase + 68)),
      `${representation} PICO-8 export preserves waveform SFX ${sfx}`);
    assert.equal(parsed.bank[bankBase + 65], 0xa5,
      `${representation} PICO-8 export preserves SFX ${sfx} bass and reserved bits`);
    assert.equal(parsed.bank[bankBase + 64], 0xd0,
      `${representation} PICO-8 export preserves SFX ${sfx} waveform filter digits`);
  }
}
const waveformMaterialized = io.materializedBank(waveformEnvelope);
const expectedWaveformMaterialized = waveformEnvelope.slice(64);
for (const sfx of [2, 3]) {
  const base = 0x100 + sfx * 68;
  for (let row = 0; row < 32; row++) {
    const offset = base + row * 2;
    const source = waveformEnvelope[64 + offset] | (waveformEnvelope[65 + offset] << 8);
    const volume = (source >> 9) & 7;
    const expected = volume === 0 ? source : (source & 0xf1ff) | (Math.min(7, volume + 2) << 9);
    expectedWaveformMaterialized[offset] = expected & 255;
    expectedWaveformMaterialized[offset + 1] = expected >> 8;
    assert.equal(waveformMaterialized[offset] | (waveformMaterialized[offset + 1] << 8), expected,
      `conventional sibling SFX ${sfx} row ${row} retains Track-1 boost`);
  }
}
assert.deepEqual(Array.from(waveformMaterialized), Array.from(expectedWaveformMaterialized),
  'waveform-safe materialization changes only eligible conventional volume bits');
assert.equal(waveformMaterialized[0x100 + 8 * 68] |
  (waveformMaterialized[0x101 + 8 * 68] << 8), 0x8a58,
  'materialization preserves the custom waveform reference');
const notesEnvelope = waveformEnvelope.slice();
const notesBase = 64 + 0x100 + 68;
notesEnvelope[notesBase + 66] &= 0x7f;
put16(notesEnvelope, 8, io.crc16(notesEnvelope, 64));
put16(notesEnvelope, 10, 0);
put16(notesEnvelope, 10, io.crc16(notesEnvelope, 0, notesEnvelope.length, 10, 12));
assert.deepEqual(Array.from(io.parseProjectJson(io.projectJson(notesEnvelope))),
  Array.from(notesEnvelope), 'notes mode round-trips through lossless JSON');
const notesAuthored = io.parseP8Audio(io.p8Audio(notesEnvelope, 'authored')).bank;
assert.deepEqual(Array.from(notesAuthored.slice(0x100 + 68, 0x100 + 2 * 68)),
  Array.from(notesEnvelope.slice(notesBase, notesBase + 68)),
  'authored PICO-8 export preserves all 68 notes-mode bytes');
const notesMaterialized = io.parseP8Audio(io.p8Audio(notesEnvelope, 'materialized')).bank;
assert.equal(notesMaterialized[0x100 + 68 + 66], notesEnvelope[notesBase + 66],
  'materialized export preserves the selected notes mode bit');
for (let row = 0; row < 32; row++) {
  const offset = 0x100 + 68 + row * 2;
  const source = notesEnvelope[64 + offset] | (notesEnvelope[65 + offset] << 8);
  const volume = (source >> 9) & 7;
  const expected = volume === 0 ? source : (source & 0xf1ff) | (Math.min(7, volume + 2) << 9);
  assert.equal(notesMaterialized[offset] | (notesMaterialized[offset + 1] << 8), expected,
    `notes-mode materialization retains conventional gain row ${row}`);
}
const futureWaveform = waveformEnvelope.slice();
futureWaveform[4] = 3;
const rejectedFuture = futureWaveform.slice();
assert.equal(io.materializedBank(futureWaveform), null, 'future envelope rejects atomically');
assert.deepEqual(Array.from(futureWaveform), Array.from(rejectedFuture),
  'rejected materialization never mutates its input');

assert.equal(nativeWaveform.bank[0x100], 0x00);
assert.equal(nativeWaveform.bank[0x101], 0x7f);
assert.equal(nativeWaveform.bank[0x13e], 0x80);
assert.equal(nativeWaveform.bank[0x13f], 0xff);
assert.equal(nativeWaveform.bank[0x142] & 0x80, 0x80);
assert.equal(nativeWaveform.bank[0x100 + 8 * 68] | (nativeWaveform.bank[0x101 + 8 * 68] << 8),
  0x8a18, 'native fixture includes a conventional note referencing waveform zero');
const bassOff = io.parseP8Audio(fs.readFileSync('tests/fixtures/pico8-027-waveform-bass-off.p8', 'utf8'));
const bassOn = io.parseP8Audio(fs.readFileSync('tests/fixtures/pico8-027-waveform-bass-on.p8', 'utf8'));
const bassDeltas = [];
for (let i = 0; i < bassOff.bank.length; i++) {
  if (bassOff.bank[i] !== bassOn.bank[i]) bassDeltas.push([i, bassOff.bank[i], bassOn.bank[i]]);
}
assert.deepEqual(bassDeltas, [[0x141, 0x10, 0x11]],
  'native editor fixture pair proves only waveform bass bit zero');
assert.equal(bassOff.bank[0x142] & 0x80, 0x80);
assert.equal(bassOn.bank[0x142] & 0x80, 0x80);
const modeNotes = io.parseP8Audio(fs.readFileSync('tests/fixtures/pico8-027-waveform-mode-notes.p8', 'utf8'));
const modeWave = io.parseP8Audio(fs.readFileSync('tests/fixtures/pico8-027-waveform-mode-wave.p8', 'utf8'));
const modeDeltas = [];
for (let i = 0; i < modeNotes.bank.length; i++) {
  if (modeNotes.bank[i] !== modeWave.bank[i]) modeDeltas.push([i, modeNotes.bank[i], modeWave.bank[i]]);
}
assert.deepEqual(modeDeltas, [[0x142, 0x00, 0x80]],
  'native editor fixture pair proves only waveform mode bit seven');
assert.deepEqual(Array.from(modeNotes.bank.slice(0x100, 0x140)),
  Array.from(modeWave.bank.slice(0x100, 0x140)), 'mode fixture keeps all 64 payload bytes exact');
assert.equal(modeNotes.bank[0x141], modeWave.bank[0x141]);
const waveformFilters = io.parseP8Audio(fs.readFileSync(
  'tests/fixtures/pico8-027-waveform-filters.p8', 'utf8'));
const waveformFilterRaw = [0x00, 0x08, 0x10, 0x18, 0x30, 0x48, 0x90];
for (let sfx = 0; sfx < waveformFilterRaw.length; sfx++) {
  const base = 0x100 + sfx * 68;
  assert.equal(waveformFilters.bank[base + 64], waveformFilterRaw[sfx],
    `native waveform filter fixture raw slot ${sfx}`);
  assert.deepEqual(Array.from(waveformFilters.bank.slice(base, base + 64)),
    Array.from(waveformFilters.bank.slice(0x100, 0x140)),
    `native waveform filter fixture payload slot ${sfx}`);
  assert.deepEqual(Array.from(waveformFilters.bank.slice(base + 65, base + 68)),
    Array.from(waveformFilters.bank.slice(0x141, 0x144)),
    `native waveform filter fixture metadata slot ${sfx}`);
}
assert.equal(waveformFilters.bank[0x100 + 8 * 68] |
  (waveformFilters.bank[0x101 + 8 * 68] << 8), 0x8a18,
  'native waveform filter fixture keeps its conventional playback reference');

const malformedP8 = authored.replace(/^([0-9a-f]{8})[0-9a-f]{2}/m, '$1ff');
assert.equal(io.parseP8Audio(malformedP8), null, 'out-of-range PICO-8 note pitch is rejected');
assert.equal(io.parseP8Audio('__sfx__\n00\n__music__\n00 00000000\n'), null,
  'truncated PICO-8 SFX rows are rejected');
const canonical = io.parseP8Audio(fs.readFileSync('pocket-tracker.p8', 'utf8'));
assert.equal(io.crc16(canonical.bank), 0x2a23,
  'omitted PICO-8 SFX rows receive the native default speed and canonical CRC');

if (process.env.POCKET_TRACKER_EXPORT_DIR) {
  fs.mkdirSync(process.env.POCKET_TRACKER_EXPORT_DIR, {recursive: true});
  fs.writeFileSync(path.join(process.env.POCKET_TRACKER_EXPORT_DIR, 'authored.p8'), authored);
  fs.writeFileSync(path.join(process.env.POCKET_TRACKER_EXPORT_DIR, 'materialized.p8'), materialized);
}

console.log('pocket tracker lossless file io: passed');
