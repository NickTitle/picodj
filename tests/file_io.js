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
  put16(bytes, 8, io.crc16(bytes, 64));
  put16(bytes, 10, io.crc16(bytes, 0, bytes.length, 10, 12));
  return bytes;
}

const envelope = envelopeFixture();
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

const waveformEnvelope = envelope.slice();
const waveformBase = 64 + 0x100;
for (let sample = 0; sample < 64; sample++) waveformEnvelope[waveformBase + sample] = (sample * 29 + 7) & 255;
waveformEnvelope[waveformBase] = 0x00;
waveformEnvelope[waveformBase + 1] = 0x7f;
waveformEnvelope[waveformBase + 62] = 0x80;
waveformEnvelope[waveformBase + 63] = 0xff;
waveformEnvelope[waveformBase + 66] |= 0x80;
put16(waveformEnvelope, 8, io.crc16(waveformEnvelope, 64));
put16(waveformEnvelope, 10, 0);
put16(waveformEnvelope, 10, io.crc16(waveformEnvelope, 0, waveformEnvelope.length, 10, 12));
assert.deepEqual(Array.from(io.parseProjectJson(io.projectJson(waveformEnvelope))),
  Array.from(waveformEnvelope), 'waveform samples round-trip through lossless JSON');
for (const representation of ['authored', 'materialized']) {
  const parsed = io.parseP8Audio(io.p8Audio(waveformEnvelope, representation));
  assert.deepEqual(Array.from(parsed.bank.slice(0x100, 0x144)),
    Array.from(waveformEnvelope.slice(waveformBase, waveformBase + 68)),
    `${representation} PICO-8 export preserves all waveform bytes and metadata`);
}

const nativeWaveform = io.parseP8Audio(fs.readFileSync('tests/fixtures/pico8-027-waveform.p8', 'utf8'));
assert.equal(nativeWaveform.bank[0x100], 0x00);
assert.equal(nativeWaveform.bank[0x101], 0x7f);
assert.equal(nativeWaveform.bank[0x13e], 0x80);
assert.equal(nativeWaveform.bank[0x13f], 0xff);
assert.equal(nativeWaveform.bank[0x142] & 0x80, 0x80);
assert.equal(nativeWaveform.bank[0x100 + 8 * 68] | (nativeWaveform.bank[0x101 + 8 * 68] << 8),
  0x8a18, 'native fixture includes a conventional note referencing waveform zero');

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
