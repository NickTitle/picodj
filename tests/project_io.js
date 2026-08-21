'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

class MemoryStorage {
  constructor() { this.values = new Map(); }
  getItem(key) { return this.values.has(key) ? this.values.get(key) : null; }
  setItem(key, value) { this.values.set(key, String(value)); }
  removeItem(key) { this.values.delete(key); }
}

const gpio = new Array(128).fill(0);
const localStorage = new MemoryStorage();
const raf = [];
let guard = null;
const frameDocument = {
  head: {appendChild(node) { guard = node; }},
  createElement() { return {id: '', textContent: ''}; },
  getElementById(id) { return guard?.id === id ? guard : null; },
  addEventListener() {},
};
const cart = {
  contentDocument: frameDocument,
  contentWindow: {pico8_gpio: gpio},
  addEventListener() {},
};
const sandbox = {
  Blob,
  URL,
  localStorage,
  document: {querySelector() { return cart; }},
  requestAnimationFrame(callback) { raf.push(callback); },
  setTimeout() {},
};
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync('mobile.js', 'utf8'), sandbox);
const io = sandbox.PocketTrackerProjectIO;
const pumpProjectBridge = raf[0];
const projectSource = fs.readFileSync('project_io.lua', 'utf8');
const songSource = fs.readFileSync('song_ui.lua', 'utf8');
assert.doesNotMatch(projectSource, /save_addr|save_size|dset\(|request_export/,
  'lossless project bridge never calls the legacy 78-byte actions');
assert.match(songSource, /function request_export\(\) native_io_pending\(\) end/,
  'legacy JSON/WAV export remains disabled');

function put16(bytes, offset, value) {
  bytes[offset] = value & 255;
  bytes[offset + 1] = value >> 8;
}

function fixtureEnvelope() {
  const bytes = new Uint8Array(4672);
  bytes.set([80, 84, 80, 50, 2, 64]);
  put16(bytes, 6, bytes.length);
  put16(bytes, 12, 37);
  bytes[14] = 1;
  bytes[15] = 1;
  const name = Buffer.from('strfld track 1');
  bytes[16] = name.length;
  bytes.set(name, 17);
  const source = Buffer.from('e7e97ab track 1');
  bytes[32] = source.length;
  bytes.set(source, 33);
  bytes.set([0, 1, 4], 56);
  for (let i = 64; i < bytes.length; i++) bytes[i] = (i * 37 + 11) & 255;
  put16(bytes, 8, io.crc16(bytes, 64));
  put16(bytes, 10, io.crc16(bytes, 0, bytes.length, 10, 12));
  return bytes;
}

const envelope = fixtureEnvelope();
assert.equal(io.envelopeValid(envelope), true);
assert.equal(io.storeLastKnownGood(envelope), true);
assert.deepEqual(Array.from(io.loadLastKnownGood()), Array.from(envelope));

const corruptRecord = JSON.parse(localStorage.getItem(io.key));
corruptRecord.envelope = `${corruptRecord.envelope.slice(0, 200)}g0${corruptRecord.envelope.slice(202)}`;
localStorage.setItem(io.key, JSON.stringify(corruptRecord));
assert.equal(io.loadLastKnownGood(), null, 'corrupt stored envelope is rejected');
assert.equal(io.storeLastKnownGood(envelope), true);
const stableRecord = localStorage.getItem(io.key);

const wrongSelection = envelope.slice();
wrongSelection[56] = 1;
put16(wrongSelection, 10, 0);
put16(wrongSelection, 10, io.crc16(wrongSelection, 0, wrongSelection.length, 10, 12));
assert.equal(io.envelopeValid(wrongSelection), false,
  'checksum-valid unknown source selection is rejected');
assert.equal(io.storeLastKnownGood(wrongSelection), false);
assert.equal(localStorage.getItem(io.key), stableRecord,
  'unknown source selection preserves last known good');

io.writeFrame(gpio, io.commands.loadRequest, 1, 0, 0, envelope.length);
assert.equal(gpio[14] | (gpio[15] << 8), 0x4bca, 'GPIO CRC matches cartridge vector');

const mismatchingStorage = new MemoryStorage();
mismatchingStorage.setItem(io.key, stableRecord);
const normalGet = mismatchingStorage.getItem.bind(mismatchingStorage);
let writes = 0;
mismatchingStorage.setItem = function(key, value) {
  MemoryStorage.prototype.setItem.call(this, key, value);
  writes++;
};
mismatchingStorage.getItem = function(key) {
  const value = normalGet(key);
  if (writes !== 1 || value === null) return value;
  writes++;
  return `${value.slice(0, -1)}x`;
};
assert.equal(io.storeLastKnownGood(envelope, mismatchingStorage), false);
assert.equal(mismatchingStorage.getItem(io.key), stableRecord, 'read-back failure restores last known good');

const throwingStorage = new MemoryStorage();
throwingStorage.setItem(io.key, stableRecord);
throwingStorage.setItem = function() { throw new Error('quota'); };
assert.equal(io.storeLastKnownGood(envelope, throwingStorage), false);
assert.equal(throwingStorage.getItem(io.key), stableRecord, 'write failure preserves last known good');

localStorage.setItem(io.key, stableRecord);
for (let offset = 0, sequence = 0; offset < envelope.length; sequence++) {
  const length = Math.min(112, envelope.length - offset);
  const flags = (offset === 0 ? 1 : 0) | (offset + length === envelope.length ? 2 : 0) | 4;
  const payload = envelope.slice(offset, offset + length);
  io.writeFrame(gpio, io.commands.savePage, 9, sequence & 255, offset, envelope.length, payload, flags);
  pumpProjectBridge();
  assert.equal(io.frameValid(gpio, io.commands.ack), true, `save page ${sequence} acknowledged`);
  if (sequence === 2) {
    io.writeFrame(gpio, io.commands.savePage, 9, sequence, offset, envelope.length, payload, flags);
    pumpProjectBridge();
    assert.equal(io.frameValid(gpio, io.commands.ack), true,
      'duplicate non-first save page is idempotently acknowledged');
  }
  offset += length;
}
assert.deepEqual(Array.from(io.loadLastKnownGood()), Array.from(envelope));

io.writeFrame(gpio, io.commands.loadRequest, 10, 0, 0, envelope.length);
pumpProjectBridge();
const loaded = new Uint8Array(envelope.length);
let loadPages = 0;
while (gpio[5] === io.commands.loadPage) {
  assert.equal(io.frameValid(gpio, io.commands.loadPage), true);
  const sequence = gpio[7];
  const offset = gpio[8] | (gpio[9] << 8);
  const length = gpio[12];
  loaded.set(gpio.slice(16, 16 + length), offset);
  io.writeFrame(gpio, io.commands.ack, 10, sequence, offset, envelope.length);
  pumpProjectBridge();
  loadPages++;
}
assert.equal(loadPages, 42);
assert.equal(io.frameValid(gpio, io.commands.loadCommit), true);
assert.deepEqual(Array.from(loaded), Array.from(envelope));

io.writeFrame(gpio, io.commands.savePage, 11, 0, 0, envelope.length,
  envelope.slice(0, 112), 5);
pumpProjectBridge();
assert.equal(io.frameValid(gpio, io.commands.ack), true);
io.writeFrame(gpio, io.commands.savePage, 11, 2, 224, envelope.length,
  envelope.slice(224, 336), 4);
pumpProjectBridge();
assert.equal(io.frameValid(gpio, io.commands.error), true, 'out-of-order save is rejected');
assert.equal(localStorage.getItem(io.key), stableRecord, 'GPIO fault preserves durable slot');

console.log('pocket tracker project io browser: passed');
