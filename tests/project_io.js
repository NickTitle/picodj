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
const files = sandbox.PocketTrackerFileIO;
const library = sandbox.PocketTrackerLibrary;
const pumpProjectBridge = raf[0];
const projectSource = fs.readFileSync('project_io.lua', 'utf8');
const songSource = fs.readFileSync('song_ui.lua', 'utf8');
const trackerSource = fs.readFileSync('tracker.lua', 'utf8');
const mobileSource = fs.readFileSync('mobile.js', 'utf8');
const indexSource = fs.readFileSync('index.html', 'utf8');
assert.doesNotMatch(projectSource, /save_addr|save_size|dset\(|request_export/,
  'lossless project bridge never calls the legacy 78-byte actions');
assert.doesNotMatch(songSource + trackerSource, /function request_export|dset\(/,
  'legacy JSON/WAV and 78-byte persistence implementations are not shipped');
assert.doesNotMatch(mobileSource, /renderWav|readProject|pocket-tracker-song/,
  'legacy lossy JSON/WAV browser bridge remains removed');
assert.match(indexSource, /Export Pocket Tracker JSON/);
assert.match(indexSource, /Export \.p8 — authored \+ profile/);
assert.match(indexSource, /Export \.p8 — materialized playback/);
assert.match(indexSource, /Import JSON \/ \.p8 audio/);
assert.match(indexSource, /accept="\.json,\.p8,application\/json"/);
assert.match(indexSource, /<label for="library-project">Project<\/label>/);
assert.match(indexSource, /<label for="library-revision">Revision<\/label>/);
assert.match(indexSource, /data-library-action="stage"/);
assert.match(indexSource, /data-library-action="delete-revision"/);
assert.match(indexSource, /data-library-action="reset"/);
assert.match(indexSource, /role="status" aria-live="polite"/);
assert.match(mobileSource, /Imported authored \.p8\. Choose Load in the tracker\./);
assert.match(mobileSource, /Imported audio sections as no profile/);

const crcVectors = [
  [[], 0xffff, 'empty'],
  [[0], 0xe1f0, 'zero byte'],
  [[0x80], 0x7078, 'high bit'],
  [[0xff], 0xff00, 'all bits'],
  [[0, 0, 0, 0], 0x84c0, 'multiple zero bytes'],
  [Array.from(Buffer.from('123456789')), 0x29b1, 'representative bytes'],
];
for (const [bytes, expected, label] of crcVectors) {
  assert.equal(io.crc16(Uint8Array.from(bytes)), expected, `${label} CRC vector`);
}

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
assert.equal(io.crc16(envelope, 64), 0xbc23, 'cross-runtime bank CRC vector');
assert.equal(io.crc16(envelope, 0, envelope.length, 10, 12), 0xa683,
  'cross-runtime envelope CRC vector');
const requestFrame = new Uint8Array(128);
requestFrame.set([80, 84, 75, 50, 1, 7, 1, 0, 0, 0, 64, 18, 0, 0]);
assert.equal(io.crc16(requestFrame, 0, 14), 0x4bca,
  'cross-runtime GPIO frame CRC vector');
const nativeRecord = new Uint8Array(4680);
nativeRecord.set([80, 84, 74, 49, 37, 0]);
nativeRecord.set(envelope, 8);
const nativeRecordPayload = new Uint8Array(nativeRecord.length - 2);
nativeRecordPayload.set(nativeRecord.slice(0, 6));
nativeRecordPayload.set(nativeRecord.slice(8), 6);
assert.equal(io.crc16(nativeRecordPayload), 0x2b65,
  'cross-runtime native journal record CRC vector');
assert.equal(io.envelopeValid(envelope), true);
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
assert.equal(io.storeLastKnownGood(envelope), true);
assert.deepEqual(Array.from(io.loadLastKnownGood()), Array.from(envelope));
const modeEnvelope = envelope.slice();
const modeOffset = 64 + 0x100 + 68 + 66;
const filterOffset = 64 + 0x100 + 68 + 64;
modeEnvelope[modeOffset] ^= 0x80;
modeEnvelope[filterOffset] = 0xd0;
put16(modeEnvelope, 8, io.crc16(modeEnvelope, 64));
put16(modeEnvelope, 10, 0);
put16(modeEnvelope, 10, io.crc16(modeEnvelope, 0, modeEnvelope.length, 10, 12));
assert.equal(io.storeLastKnownGood(modeEnvelope), true);
assert.deepEqual(Array.from(io.loadLastKnownGood()), Array.from(modeEnvelope),
  'browser slot preserves selected waveform mode and filter bytes with all other bytes');
assert.equal(io.storeLastKnownGood(envelope), true);

const corruptRecord = JSON.parse(localStorage.getItem(io.key));
corruptRecord.envelope = `${corruptRecord.envelope.slice(0, 200)}g0${corruptRecord.envelope.slice(202)}`;
localStorage.setItem(io.key, JSON.stringify(corruptRecord));
assert.equal(io.loadLastKnownGood(), null, 'corrupt stored envelope is rejected');
assert.equal(io.storeLastKnownGood(envelope), true);
const stableRecord = localStorage.getItem(io.key);

function revisionEnvelope(revision, salt = revision) {
  const bytes = envelope.slice();
  put16(bytes, 12, revision);
  bytes[64] = salt & 255;
  put16(bytes, 8, io.crc16(bytes, 64));
  put16(bytes, 10, 0);
  put16(bytes, 10, io.crc16(bytes, 0, bytes.length, 10, 12));
  return bytes;
}

assert.equal(library.key, 'pocket-tracker:library:v1');
assert.equal(library.maxProjects, 8);
assert.equal(library.maxRevisions, 4);
assert.equal(library.maxChars, 302213);
assert.equal(library.parseProjectLibrary(' '.repeat(library.maxChars + 1)), null,
  'serialized library storage is explicitly bounded');
const libraryStorage = new MemoryStorage();
libraryStorage.setItem(io.key, stableRecord);
const gpioBeforeLibrary = gpio.slice();
const migrated = library.migrateProjectLibrary(libraryStorage);
assert.equal(migrated.state, 'migrated');
assert.equal(migrated.library.projects.length, 1);
assert.equal(migrated.library.projects[0].revisions.length, 1);
assert.equal(libraryStorage.getItem(io.key), stableRecord, 'migration preserves the compatibility slot');
const migratedRaw = libraryStorage.getItem(library.key);
assert.equal(library.migrateProjectLibrary(libraryStorage).state, 'ready',
  'migration is one-time when a library already exists');
assert.equal(libraryStorage.getItem(library.key), migratedRaw, 'repeat migration is byte-stable');
assert.deepEqual(gpio, gpioBeforeLibrary, 'migration never mutates live GPIO');

const revisions = new Map();
const rolloverMessages = [];
for (let revision = 38; revision <= 42; revision++) {
  const bytes = revisionEnvelope(revision);
  revisions.set(revision, bytes);
  assert.equal(io.storeLastKnownGood(bytes, libraryStorage), true);
  assert.equal(library.addLibraryRevision(1, libraryStorage, (message) => {
    rolloverMessages.push(message);
    return true;
  }), revision - 36);
}
let libraryView = library.loadProjectLibrary(libraryStorage);
assert.equal(libraryView.state, 'ready');
assert.deepEqual(Array.from(libraryView.library.projects[0].revisions, (item) => item.id), [3, 4, 5, 6],
  'bounded history retains exactly the four newest revisions');
assert.deepEqual(rolloverMessages, [
  'Save this revision and permanently evict strfld track 1 saved copy 1?',
  'Save this revision and permanently evict strfld track 1 saved copy 2?',
], 'history rollover confirms the exact project and saved-copy ID');
const boundedRaw = libraryStorage.getItem(library.key);
assert.equal(library.addLibraryRevision(1, libraryStorage), 'duplicate');
assert.equal(libraryStorage.getItem(library.key), boundedRaw, 'duplicate revision is a durable no-op');
assert.equal(library.stageLibraryRevision(1, 3, libraryStorage), true);
assert.deepEqual(Array.from(io.loadLastKnownGood(libraryStorage)), Array.from(revisions.get(39)),
  'selection stages the chosen older revision in the compatibility slot');
assert.equal(libraryStorage.getItem(library.key), boundedRaw, 'staging does not rewrite the library');
assert.deepEqual(gpio, gpioBeforeLibrary, 'staging does not mutate live GPIO');

const corruptLibrary = JSON.parse(boundedRaw);
const corruptRevision = corruptLibrary.projects[0].revisions.at(-1);
corruptRevision.envelope.envelope = `00${corruptRevision.envelope.envelope.slice(2)}`;
const corruptRaw = JSON.stringify(corruptLibrary);
libraryStorage.setItem(library.key, corruptRaw);
libraryView = library.loadProjectLibrary(libraryStorage);
assert.equal(libraryView.state, 'recovered');
assert.deepEqual(Array.from(libraryView.library.projects[0].revisions, (item) => item.id), [3, 4, 5],
  'a corrupt newest copy exposes the older validated history');
assert.equal(library.stageLibraryRevision(1, 5, libraryStorage), true);
assert.equal(libraryStorage.getItem(library.key), corruptRaw,
  'recovery and staging never silently rewrite corrupt durable data');
assert.equal(io.storeLastKnownGood(revisionEnvelope(52), libraryStorage), true);
assert.equal(library.addLibraryRevision(1, libraryStorage, () => true), false,
  'recovered libraries are read-only until explicit reset');
assert.equal(library.deleteLibraryRevision(1, 5, libraryStorage), false);
assert.equal(libraryStorage.getItem(library.key), corruptRaw, 'mutations preserve corrupt recovery evidence');

const deleteStorage = new MemoryStorage();
deleteStorage.setItem(library.key, boundedRaw);
deleteStorage.setItem(io.key, stableRecord);
const cancelledLibrary = deleteStorage.getItem(library.key);
const cancelledSlot = deleteStorage.getItem(io.key);
let confirmationCalls = 0;
let deleteMessage = '';
assert.equal(library.confirmLibraryDelete('delete-revision', 1, 5, deleteStorage, (message) => {
  confirmationCalls++;
  deleteMessage = message;
  return false;
}), 'cancelled');
assert.equal(confirmationCalls, 1);
assert.equal(deleteMessage,
  'Delete strfld track 1 saved copy 5? The tracker and browser slot will not change.');
assert.equal(deleteStorage.getItem(library.key), cancelledLibrary, 'cancelled deletion preserves library');
assert.equal(deleteStorage.getItem(io.key), cancelledSlot, 'cancelled deletion preserves browser slot');
assert.deepEqual(gpio, gpioBeforeLibrary, 'cancelled deletion preserves live GPIO');
assert.deepEqual({...library.libraryDeleteFeedback('cancelled')},
  {message: 'Deletion cancelled. Nothing changed.', failed: false});

const staleRevisionStorage = new MemoryStorage();
staleRevisionStorage.setItem(library.key, boundedRaw);
staleRevisionStorage.setItem(io.key, stableRecord);
assert.equal(library.confirmLibraryDelete('delete-revision', 1, 5, staleRevisionStorage, () => {
  staleRevisionStorage.setItem(io.key, io.envelopeRecord(revisionEnvelope(62)));
  return true;
}), 'changed', 'revision deletion aborts when its LKG snapshot changes after confirmation');
assert.equal(staleRevisionStorage.getItem(library.key), boundedRaw,
  'stale revision deletion preserves every saved revision');
assert.equal(io.loadLastKnownGood(staleRevisionStorage)[12] |
  (io.loadLastKnownGood(staleRevisionStorage)[13] << 8), 62,
  'stale revision deletion does not overwrite the newly changed LKG');
assert.deepEqual({...library.libraryDeleteFeedback('changed')}, {
  message: 'Project data changed before deletion. Nothing was deleted or overwritten.', failed: true,
}, 'stale revision deletion reports an abort rather than success');

const staleProjectStorage = new MemoryStorage();
staleProjectStorage.setItem(library.key, boundedRaw);
staleProjectStorage.setItem(io.key, stableRecord);
let externallyChangedLibrary;
assert.equal(library.confirmLibraryDelete('delete-project', 1, 0, staleProjectStorage, () => {
  const changed = JSON.parse(boundedRaw);
  changed.nextProject++;
  externallyChangedLibrary = JSON.stringify(changed);
  staleProjectStorage.setItem(library.key, externallyChangedLibrary);
  return true;
}), 'changed', 'project deletion aborts when its library snapshot changes after confirmation');
assert.equal(staleProjectStorage.getItem(library.key), externallyChangedLibrary,
  'stale project deletion does not overwrite the externally changed library');
assert.equal(library.loadProjectLibrary(staleProjectStorage).library.projects.length, 1,
  'stale project deletion leaves the selected project present');
assert.deepEqual({...library.libraryDeleteFeedback('changed')}, {
  message: 'Project data changed before deletion. Nothing was deleted or overwritten.', failed: true,
}, 'stale project deletion reports an abort rather than success');
assert.equal(library.resetProjectLibrary(libraryStorage, () => false), 'cancelled');
assert.equal(libraryStorage.getItem(library.key), corruptRaw, 'cancelled reset preserves recovery evidence');
assert.equal(library.resetProjectLibrary(libraryStorage, () => true), true);
assert.equal(library.loadProjectLibrary(libraryStorage).state, 'ready');
assert.equal(library.loadProjectLibrary(libraryStorage).library.projects.length, 0,
  'confirmed reset writes an empty valid root');
assert.notEqual(library.migrateProjectLibrary(libraryStorage).state, 'migrated',
  'an empty valid root is not silently migrated again');
assert.equal(io.loadLastKnownGood(libraryStorage)[12] | (io.loadLastKnownGood(libraryStorage)[13] << 8), 52,
  'library-only reset preserves last-known-good');

const malformedStorage = new MemoryStorage();
malformedStorage.setItem(io.key, stableRecord);
malformedStorage.setItem(library.key, '{"format":"pocket-tracker-library","version":1}');
const malformedRaw = malformedStorage.getItem(library.key);
assert.equal(library.migrateProjectLibrary(malformedStorage).state, 'invalid');
assert.equal(malformedStorage.getItem(library.key), malformedRaw,
  'an invalid existing library is never overwritten by migration');
assert.equal(malformedStorage.getItem(io.key), stableRecord);
assert.equal(library.resetProjectLibrary(malformedStorage, () => true), true,
  'explicit confirmation can reset a malformed library root');
assert.equal(library.loadProjectLibrary(malformedStorage).state, 'ready');
assert.equal(malformedStorage.getItem(io.key), stableRecord);

const migrationQuota = new MemoryStorage();
migrationQuota.setItem(io.key, stableRecord);
migrationQuota.setItem = function(key, value) {
  if (key === library.key) throw new Error('quota');
  MemoryStorage.prototype.setItem.call(this, key, value);
};
assert.equal(library.migrateProjectLibrary(migrationQuota).state, 'fault');
assert.equal(migrationQuota.getItem(library.key), null);
assert.equal(migrationQuota.getItem(io.key), stableRecord, 'failed migration preserves last-known-good');

const quotaStorage = new MemoryStorage();
quotaStorage.setItem(io.key, stableRecord);
assert.equal(library.migrateProjectLibrary(quotaStorage).state, 'migrated');
assert.equal(io.storeLastKnownGood(revisionEnvelope(50), quotaStorage), true);
const quotaLibrary = quotaStorage.getItem(library.key);
const quotaSlot = quotaStorage.getItem(io.key);
quotaStorage.setItem = function(key, value) {
  if (key === library.key) throw new Error('quota');
  MemoryStorage.prototype.setItem.call(this, key, value);
};
assert.equal(library.addLibraryRevision(1, quotaStorage), false);
assert.equal(quotaStorage.getItem(library.key), quotaLibrary, 'quota failure preserves library history');
assert.equal(quotaStorage.getItem(io.key), quotaSlot, 'quota failure preserves staged slot');

const readBackStorage = new MemoryStorage();
readBackStorage.setItem(io.key, stableRecord);
assert.equal(library.migrateProjectLibrary(readBackStorage).state, 'migrated');
assert.equal(io.storeLastKnownGood(revisionEnvelope(51), readBackStorage), true);
const readBackLibrary = readBackStorage.getItem(library.key);
const normalLibraryGet = readBackStorage.getItem.bind(readBackStorage);
let libraryWrites = 0;
readBackStorage.setItem = function(key, value) {
  MemoryStorage.prototype.setItem.call(this, key, value);
  if (key === library.key) libraryWrites++;
};
readBackStorage.getItem = function(key) {
  const value = normalLibraryGet(key);
  if (key !== library.key || libraryWrites !== 1 || value === null) return value;
  libraryWrites++;
  return `${value.slice(0, -1)}x`;
};
assert.equal(library.addLibraryRevision(1, readBackStorage), false);
assert.equal(readBackStorage.getItem(library.key), readBackLibrary,
  'library read-back failure restores the exact previous record');

const uncertainStorage = new MemoryStorage();
uncertainStorage.setItem(io.key, stableRecord);
assert.equal(library.migrateProjectLibrary(uncertainStorage).state, 'migrated');
assert.equal(io.storeLastKnownGood(revisionEnvelope(53), uncertainStorage), true);
let uncertainWrite = 0;
const uncertainGet = uncertainStorage.getItem.bind(uncertainStorage);
uncertainStorage.setItem = function(key, value) {
  if (key === library.key && uncertainWrite++ > 0) throw new Error('rollback failed');
  MemoryStorage.prototype.setItem.call(this, key, value);
};
uncertainStorage.getItem = function(key) {
  const value = uncertainGet(key);
  return key === library.key && uncertainWrite === 1 ? `${value.slice(0, -1)}x` : value;
};
assert.equal(library.addLibraryRevision(1, uncertainStorage), false);
assert.equal(library.loadProjectLibrary(uncertainStorage).state, 'uncertain',
  'unverified rollback disables further library writes');
assert.equal(library.addLibraryProject(uncertainStorage), false);
assert.equal(library.resetProjectLibrary(uncertainStorage, () => true), false);

const limitStorage = new MemoryStorage();
limitStorage.setItem(io.key, stableRecord);
for (let project = 1; project <= library.maxProjects; project++) {
  assert.equal(library.addLibraryProject(limitStorage), project);
}
const fullLibrary = limitStorage.getItem(library.key);
assert.equal(library.addLibraryProject(limitStorage), false);
assert.equal(limitStorage.getItem(library.key), fullLibrary, 'project limit rejects without eviction');
assert.equal(limitStorage.getItem(io.key), stableRecord);

const outOfOrder = JSON.parse(fullLibrary);
[outOfOrder.projects[0], outOfOrder.projects[1]] = [outOfOrder.projects[1], outOfOrder.projects[0]];
assert.equal(library.parseProjectLibrary(JSON.stringify(outOfOrder)), null,
  'project IDs must be strictly increasing');
const revisionOrder = JSON.parse(boundedRaw);
[revisionOrder.projects[0].revisions[0], revisionOrder.projects[0].revisions[1]] =
  [revisionOrder.projects[0].revisions[1], revisionOrder.projects[0].revisions[0]];
assert.equal(library.parseProjectLibrary(JSON.stringify(revisionOrder)), null,
  'revision IDs must be strictly increasing');

const rolloverStorage = new MemoryStorage();
rolloverStorage.setItem(io.key, io.envelopeRecord(revisionEnvelope(60)));
rolloverStorage.setItem(library.key, boundedRaw);
const rolloverRaw = rolloverStorage.getItem(library.key);
const rolloverSlot = rolloverStorage.getItem(io.key);
assert.equal(library.addLibraryRevision(1, rolloverStorage, () => false), 'cancelled');
assert.equal(rolloverStorage.getItem(library.key), rolloverRaw, 'cancelled rollover preserves history');
assert.equal(rolloverStorage.getItem(io.key), rolloverSlot, 'cancelled rollover preserves source slot');
assert.equal(library.addLibraryRevision(1, rolloverStorage, () => {
  rolloverStorage.setItem(io.key, io.envelopeRecord(revisionEnvelope(61)));
  return true;
}), 'changed', 'rollover aborts when its source slot changes during confirmation');
assert.equal(rolloverStorage.getItem(library.key), rolloverRaw);
rolloverStorage.setItem(io.key, rolloverSlot);
assert.equal(library.addLibraryRevision(1, rolloverStorage, () => {
  const changed = JSON.parse(rolloverRaw);
  changed.nextProject++;
  rolloverStorage.setItem(library.key, JSON.stringify(changed));
  return true;
}), 'changed', 'rollover aborts when its library snapshot changes during confirmation');

const activeLibraryRaw = limitStorage.getItem(library.key);
const activeSlotRaw = limitStorage.getItem(io.key);
io.writeFrame(gpio, io.commands.savePage, 70, 0, 0, envelope.length, envelope.slice(0, 112), 5);
pumpProjectBridge();
assert.equal(library.projectTransferActive(), true);
assert.equal(library.stageLibraryRevision(1, 1, limitStorage), false);
assert.equal(library.addLibraryProject(limitStorage), false);
assert.equal(library.storeProjectLibrary(library.emptyProjectLibrary(), limitStorage), false);
assert.equal(limitStorage.getItem(library.key), activeLibraryRaw,
  'library mutations are blocked during an active GPIO save');
assert.equal(limitStorage.getItem(io.key), activeSlotRaw);
io.writeFrame(gpio, io.commands.savePage, 70, 2, 224, envelope.length, envelope.slice(224, 336), 4);
pumpProjectBridge();
assert.equal(library.projectTransferActive(), false);
io.writeFrame(gpio, io.commands.loadRequest, 71, 0, 0, envelope.length);
pumpProjectBridge();
assert.equal(library.projectTransferActive(), true);
assert.equal(library.stageLibraryRevision(1, 1, limitStorage), false,
  'staging is blocked during an active GPIO load');
io.writeFrame(gpio, io.commands.done, 71, 0, 0, envelope.length);
pumpProjectBridge();
assert.equal(library.projectTransferActive(), false);

const wrongSelection = envelope.slice();
wrongSelection[56] = 1;
put16(wrongSelection, 10, 0);
put16(wrongSelection, 10, io.crc16(wrongSelection, 0, wrongSelection.length, 10, 12));
assert.equal(io.envelopeValid(wrongSelection), false,
  'checksum-valid unknown source selection is rejected');
assert.equal(io.storeLastKnownGood(wrongSelection), false);
assert.equal(localStorage.getItem(io.key), stableRecord,
  'unknown source selection preserves last known good');

const gpioBeforeP8Import = gpio.slice();
assert.equal(files.importProjectP8(io.p8Audio(envelope, 'authored')), true);
assert.deepEqual(Array.from(io.loadLastKnownGood()), Array.from(envelope),
  'authored PICO-8 import prepares the exact envelope for staged Load');
assert.deepEqual(gpio, gpioBeforeP8Import,
  'authored PICO-8 import leaves live GPIO untouched until staged Load');

const materialized = io.p8Audio(envelope, 'materialized');
assert.equal(files.importProjectP8(materialized, localStorage, 'Pocket ★.p8'), 'raw');
const rawEnvelope = io.loadLastKnownGood();
assert.deepEqual(Array.from(rawEnvelope.slice(14, 16)), [0, 0]);
assert.deepEqual(Array.from(rawEnvelope.slice(56, 59)), [0, 0, 0]);
assert.equal(JSON.parse(io.projectJson(rawEnvelope)).playbackProfile, null);
assert.deepEqual(Array.from(io.parseProjectJson(io.projectJson(rawEnvelope))), Array.from(rawEnvelope));
assert.deepEqual(Array.from(rawEnvelope.slice(64)), Array.from(io.parseP8Audio(materialized).bank));
assert.equal(io.p8Audio(rawEnvelope, 'materialized'),
  io.p8Audio(rawEnvelope, 'authored').replace(/\n-- pocket-tracker-header: [0-9a-f]{128}/, '')
    .replace('authored+profile', 'materialized'),
  'profile-none materialized audio equals authored audio');
assert.deepEqual(gpio, gpioBeforeP8Import, 'headerless import leaves GPIO untouched');
assert.equal(io.storeLastKnownGood(envelope), true);

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
assert.equal(io.p8Audio(loaded, 'authored'), io.p8Audio(envelope, 'authored'),
  'staged Load followed by authored export reproduces the exact project');

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
