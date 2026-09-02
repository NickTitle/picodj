'use strict';

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const nativeFiles = [
  'audio_bank.lua',
  'tracker.lua',
  'song_ui.lua',
  'sfx_ui.lua',
  'project_io.lua',
];
const browserFiles = ['index.html', 'mobile.js', 'help.js'];
const generatedFiles = ['tracker.html', 'tracker.js'];
const shippedBrowserHookFiles = [
  'index.html',
  'mobile.js',
  'help.js',
  'tracker.html',
  'tracker.js',
  'README.md',
];

function read(relative) {
  return fs.readFileSync(path.join(root, relative));
}

function sourceMetrics(relative, commentPattern) {
  const buffer = read(relative);
  const text = buffer.toString('utf8');
  const lines = text.endsWith('\n') ? text.slice(0, -1).split('\n') : text.split('\n');
  const nonblank = lines.filter((line) => line.trim()).length;
  const commentOnly = lines.filter((line) => commentPattern.test(line)).length;
  return {
    file: relative,
    bytes: buffer.length,
    lines: lines.length,
    nonblank,
    code: nonblank - commentOnly,
    commentOnly,
  };
}

function sumMetrics(files) {
  return files.reduce((total, file) => {
    for (const key of ['bytes', 'lines', 'nonblank', 'code', 'commentOnly']) {
      total[key] += file[key];
    }
    return total;
  }, {bytes: 0, lines: 0, nonblank: 0, code: 0, commentOnly: 0});
}

function sha256(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

const legacyBrowserHookRemovals = [
  {
    symbols: ['PocketTrackerProjectIO', 'PocketTrackerLibrary'],
    file: 'mobile.js',
    source: `globalThis.PocketTrackerProjectIO = Object.freeze({
  key: projectStoreKey,
  commands: projectCommands,
  crc16,
  envelopeValid,
  envelopeRecord,
  parseEnvelopeRecord,
  projectJson,
  parseProjectJson,
  materializedBank,
  p8Audio,
  parseP8Audio,
  storeLastKnownGood,
  loadLastKnownGood,
  frameValid,
  writeFrame,
});

globalThis.PocketTrackerLibrary = Object.freeze({
  key: projectLibraryKey,
  maxProjects: projectLibraryMaxProjects,
  maxRevisions: projectLibraryMaxRevisions,
  maxChars: projectLibraryMaxChars,
  emptyProjectLibrary,
  parseProjectLibrary,
  loadProjectLibrary,
  storeProjectLibrary,
  migrateProjectLibrary,
  addLibraryProject,
  addLibraryRevision,
  stageLibraryRevision,
  deleteLibraryProject,
  deleteLibraryRevision,
  confirmLibraryDelete,
  libraryDeleteFeedback,
  resetProjectLibrary,
  projectTransferActive,
});
`,
  },
  {
    symbols: ['PocketTrackerFileIO'],
    file: 'mobile.js',
    source: 'globalThis.PocketTrackerFileIO = Object.freeze({importProjectJson, importProjectP8, exportStoredFile});\n',
  },
  {
    symbols: ['PocketTrackerHelp'],
    file: 'help.js',
    source: '  globalThis.PocketTrackerHelp = Object.freeze({open: openHelp, close: closeHelp, isOpen: () => active});\n',
  },
];

function browserHookLifecycle() {
  const sources = Object.fromEntries(shippedBrowserHookFiles.map((file) =>
    [file, read(file).toString('utf8')]));
  const present = legacyBrowserHookRemovals.map(({file, source}) => sources[file].includes(source));
  assert.ok(present.every(Boolean) || present.every((value) => !value),
    'browser test-hook globals must retain every exact legacy definition or remove all four');
  const withoutDefinitions = {...sources};
  for (const {file, source} of legacyBrowserHookRemovals) {
    assert.equal(sources[file].split(source).length - 1, present[0] ? 1 : 0,
      `${file} differs from its exact legacy browser test-hook definition allowlist`);
    withoutDefinitions[file] = withoutDefinitions[file].replace(source, '');
  }
  const references = [];
  for (const file of shippedBrowserHookFiles) {
    withoutDefinitions[file].split('\n').forEach((line, index) => {
      for (const symbol of legacyBrowserHookRemovals.flatMap((entry) => entry.symbols)) {
        if (new RegExp(`\\b${symbol}\\b`).test(line)) {
          references.push({symbol, file, line: index + 1, source: line.trim()});
        }
      }
    });
  }
  assert.deepEqual(references, [],
    'an undocumented browser test-hook global gained a shipped HTML/runtime/README consumer');
  const removalBytes = legacyBrowserHookRemovals.reduce((total, entry) =>
    total + Buffer.byteLength(entry.source), 0);
  const removalLines = legacyBrowserHookRemovals.reduce((total, entry) =>
    total + (entry.source.match(/\n/g) || []).length, 0);
  assert.equal(removalBytes, 1071, 'browser test-hook removal byte ledger changed');
  assert.equal(removalLines, 40, 'browser test-hook removal line ledger changed');
  return {
    symbols: legacyBrowserHookRemovals.flatMap((entry) => entry.symbols),
    shippedFiles: shippedBrowserHookFiles,
    legacyDefinitionsPresent: present[0],
    removalBytes,
    removalLines,
    shippedConsumers: references,
  };
}

const legacyStatusSetters = `function setFileStatus(message, failed = false) {
  if (!fileStatus) return;
  fileStatus.textContent = message;
  fileStatus.style.color = failed ? '#ff8a8a' : '#c9c9de';
}

function setLibraryStatus(message, failed = false) {
  if (!libraryStatus) return;
  libraryStatus.textContent = message;
  libraryStatus.style.color = failed ? '#ff8a8a' : '#c9c9de';
}
`;
const sharedStatusSetter = `function setStatus(target, message, failed = false) {
  if (!target) return;
  target.textContent = message;
  target.style.color = failed ? '#ff8a8a' : '#c9c9de';
}
`;

function statusSetterLifecycle() {
  const source = read('mobile.js').toString('utf8');
  const legacyCount = source.split(legacyStatusSetters).length - 1;
  const sharedCount = source.split(sharedStatusSetter).length - 1;
  assert.ok(legacyCount === 1 && sharedCount === 0 || legacyCount === 0 && sharedCount === 1,
    'status mutation must use the exact legacy pair or the exact accepted shared setter');
  const legacyCalls = {
    file: (source.match(/\bsetFileStatus\(/g) || []).length,
    library: (source.match(/\bsetLibraryStatus\(/g) || []).length,
  };
  const sharedCalls = (source.match(/\bsetStatus\(/g) || []).length;
  if (legacyCount) {
    assert.deepEqual(legacyCalls, {file: 4, library: 11},
      'legacy status setter definitions/calls differ from the complete allowlist');
    assert.equal(sharedCalls, 0, 'status setter migration is partial');
  } else {
    assert.deepEqual(legacyCalls, {file: 0, library: 0}, 'legacy status setter survived migration');
    assert.equal(sharedCalls, 14, 'shared status setter definition/calls differ from the allowlist');
    assert.equal((source.match(/setStatus\(fileStatus, /g) || []).length, 3,
      'Files status call-site allowlist changed');
    assert.equal((source.match(/setStatus\(libraryStatus, /g) || []).length, 10,
      'library status call-site allowlist changed');
  }
  const mutationCounts = {
    text: (source.match(/\.textContent = message;/g) || []).length,
    color: (source.match(/\.style\.color = failed \? '#ff8a8a' : '#c9c9de';/g) || []).length,
  };
  assert.deepEqual(mutationCounts, legacyCount ? {text: 2, color: 2} : {text: 1, color: 1},
    'status text/color mutation logic was duplicated outside the accepted shape');
  assert.equal(Buffer.byteLength(legacyStatusSetters), 361,
    'legacy status setter gross-byte ledger changed');
  assert.equal(Buffer.byteLength(sharedStatusSetter), 166,
    'accepted shared status setter byte shape changed');
  return {
    legacy: Boolean(legacyCount),
    grossBytes: 361,
    legacyCalls,
    sharedCalls,
    mutationCounts,
  };
}

const legacyLastKnownGoodTransaction = `function storeLastKnownGood(bytes, storage = localStorage) {
  if (!envelopeValid(bytes)) return false;
  let previous;
  try {
    previous = storage.getItem(projectStoreKey);
    storage.setItem(projectStoreKey, envelopeRecord(bytes));
    const readBack = parseEnvelopeRecord(storage.getItem(projectStoreKey));
    if (sameBytes(readBack, bytes)) return true;
  } catch (_) {}
  try {
    if (previous === null || previous === undefined) storage.removeItem(projectStoreKey);
    else storage.setItem(projectStoreKey, previous);
  } catch (_) {}
  return false;
}

`;
const legacyLibraryTransaction = `function storeProjectLibrary(library, storage = localStorage, expectedRaw) {
  if (projectTransferActive() || uncertainLibraryStorage.has(storage)) return false;
  const candidate = projectLibraryRecord(library);
  const checked = parseProjectLibrary(candidate);
  if (!checked || checked.recovered || projectLibraryRecord(checked.library) !== candidate) return false;
  let previous;
  try {
    previous = storage.getItem(projectLibraryKey);
    if (expectedRaw !== undefined && previous !== expectedRaw) return false;
    storage.setItem(projectLibraryKey, candidate);
    const readBack = storage.getItem(projectLibraryKey);
    const parsed = parseProjectLibrary(readBack);
    if (readBack === candidate && parsed && !parsed.recovered &&
        projectLibraryRecord(parsed.library) === candidate) return true;
  } catch (_) {}
  let restored = false;
  try {
    if (previous === null || previous === undefined) storage.removeItem(projectLibraryKey);
    else storage.setItem(projectLibraryKey, previous);
    restored = storage.getItem(projectLibraryKey) === (previous ?? null);
  } catch (_) {}
  if (!restored) uncertainLibraryStorage.add(storage);
  return false;
}

`;
const sharedExactRecordTransaction = `function storeExactRecord(
  storage, key, candidate, accept, expected, verifyRestore
) {
  let previous;
  try {
    previous = storage.getItem(key);
    if (expected !== undefined && previous !== expected) return 'changed';
    storage.setItem(key, candidate);
    if (accept(storage.getItem(key))) return 'stored';
  } catch (_) {}
  try {
    if (previous === null || previous === undefined) storage.removeItem(key);
    else storage.setItem(key, previous);
    if (!verifyRestore || storage.getItem(key) === (previous ?? null)) return 'failed';
  } catch (_) {}
  return 'uncertain';
}

`;
const sharedCanonicalLibraryRecord = `function canonicalProjectLibraryRecord(raw) {
  const parsed = parseProjectLibrary(raw);
  return parsed && !parsed.recovered && projectLibraryRecord(parsed.library) === raw;
}

`;
const sharedLastKnownGoodTransaction = `function storeLastKnownGood(bytes, storage = localStorage) {
  if (!envelopeValid(bytes)) return false;
  return storeExactRecord(storage, projectStoreKey, envelopeRecord(bytes),
    (raw) => sameBytes(parseEnvelopeRecord(raw), bytes), undefined, false) === 'stored';
}

`;
const sharedLibraryTransaction = `function storeProjectLibrary(library, storage = localStorage, expectedRaw) {
  if (projectTransferActive() || uncertainLibraryStorage.has(storage)) return false;
  const candidate = projectLibraryRecord(library);
  if (!canonicalProjectLibraryRecord(candidate)) return false;
  const state = storeExactRecord(storage, projectLibraryKey, candidate,
    canonicalProjectLibraryRecord, expectedRaw, true);
  if (state === 'uncertain') uncertainLibraryStorage.add(storage);
  return state === 'stored';
}

`;

function storageTransactionLifecycle() {
  const source = read('mobile.js').toString('utf8');
  const legacy = [legacyLastKnownGoodTransaction, legacyLibraryTransaction]
    .map((shape) => source.split(shape).length - 1);
  const shared = [sharedExactRecordTransaction, sharedCanonicalLibraryRecord,
    sharedLastKnownGoodTransaction, sharedLibraryTransaction]
    .map((shape) => source.split(shape).length - 1);
  assert.ok(legacy.every((count) => count === 1) && shared.every((count) => count === 0) ||
    legacy.every((count) => count === 0) && shared.every((count) => count === 1),
  'storage transactions must retain both exact legacy bodies or use the complete shared shape');
  const migrated = shared[0] === 1;
  assert.equal((source.match(/\bstoreExactRecord\s*\(/g) || []).length, migrated ? 3 : 0,
    'shared exact-record mechanics must have exactly two policy-wrapper callers');
  assert.equal((source.match(/\bcanonicalProjectLibraryRecord\s*\(/g) || []).length,
    migrated ? 2 : 0,
  'canonical library validation must have one call plus its exact function-reference use');
  assert.equal((source.match(/\bstoreProjectLibrary\s*\(/g) || []).length, 7,
    'unrelated library mutation plumbing changed during storage transaction migration');
  assert.equal(Buffer.byteLength(legacyLastKnownGoodTransaction) +
    Buffer.byteLength(legacyLibraryTransaction), 1745,
  'exact current legacy transaction-body byte ledger changed');
  return {
    legacy: !migrated,
    exactLegacyBodyBytes: 1745,
    phaseOneGrossRegionBytes: 1898,
    legacyShapeCounts: legacy,
    sharedShapeCounts: shared,
  };
}

function productionReachability(symbol) {
  const definitions = [];
  const calls = [];
  const occurrence = new RegExp(`\\b${symbol}\\s*\\(`, 'g');
  const definition = new RegExp(`^\\s*function\\s+${symbol}\\s*\\(`);
  for (const file of nativeFiles) {
    const lines = read(file).toString('utf8').split('\n');
    lines.forEach((line, index) => {
      const count = [...line.matchAll(occurrence)].length;
      if (!count) return;
      const location = `${file}:${index + 1}`;
      if (definition.test(line)) definitions.push(location);
      for (let i = definition.test(line) ? 1 : 0; i < count; i++) calls.push(location);
    });
  }
  assert.deepEqual(calls, [], `${symbol} gained a shipped production caller`);
  assert.ok(definitions.length === 0 ||
    definitions.length === 1 && definitions[0].startsWith('audio_bank.lua:'),
  `${symbol} definition left its sole allowlisted production location`);
  return {symbol, definitions, calls};
}

function symbolReferences(symbol) {
  const references = [];
  const occurrence = new RegExp(`\\b${symbol}\\b`);
  for (const file of nativeFiles) {
    read(file).toString('utf8').split('\n').forEach((line, index) => {
      if (occurrence.test(line)) {
        references.push({file, line: index + 1, source: line.trim()});
      }
    });
  }
  return references;
}

const microHelperAllowlists = {
  bank_profile_is_active: [
    ['audio_bank.lua', 'function bank_profile_is_active()'],
    ['song_ui.lua', 'if playing or bank_profile_is_active() then stop_song() end'],
    ['song_ui.lua', 'if playing or bank_profile_is_active() then stop_song() end'],
    ['sfx_ui.lua', '(bank_profile_is_active() and "profile" or "auth"))),42,2,6)'],
    ['project_io.lua', 'if bank_profile_is_active() then return false end'],
    ['project_io.lua', 'if playing or bank_profile_is_active() then stop_song() end'],
  ],
  bank_mark_clean: [
    ['audio_bank.lua', 'function bank_mark_clean()'],
    ['project_io.lua', 'bank_mark_clean() undo_owner=nil song_error=nil return true'],
    ['project_io.lua', 'bank_mark_clean() undo_owner=nil io_mode="idle" io_emit_control(io_done,0)'],
  ],
  io_envelope_byte: [
    ['project_io.lua', 'function io_envelope_byte(offset)'],
    ['project_io.lua', 'for i=0,length-1 do poke(io_gpio+16+i,io_envelope_byte(io_offset+i)) end'],
  ],
};

function microHelperLifecycle(symbol) {
  const references = symbolReferences(symbol);
  const actual = references.map(({file, source}) => [file, source]);
  const allowed = microHelperAllowlists[symbol];
  assert.ok(actual.length === 0 || actual.length === allowed.length,
    `${symbol} must retain its complete legacy abstraction or be fully removed`);
  if (actual.length) assert.deepEqual(actual, allowed,
    `${symbol} differs from the exact measured legacy abstraction allowlist`);
  return {symbol, references};
}

const redundantNativeHeaders = [
  ['audio_bank.lua', '-- pocket tracker native pico-8 audio bank core'],
  ['tracker.lua', '-- shared six-button input and menus for the native tracker'],
  ['song_ui.lua', '-- native song/pattern screen'],
  ['sfx_ui.lua', '-- native 64-slot, 32-row sfx editor'],
  ['project_io.lua', '-- browser last-known-good project bridge'],
];
const retainedSafetyComments = [
  ['audio_bank.lua', '-- crc-16/ccitt-false: poly 0x1021, init 0xffff, no reflection/xorout.'],
  ['audio_bank.lua', '-- the result is a signed pico-8 16-bit bit pattern; mask with 0xffff when'],
  ['audio_bank.lua', '-- presenting it outside the vm.'],
  ['audio_bank.lua', '-- SFX 63 is a reversible scratch slot; preview never dirties the project.'],
  ['pocket-tracker-data.p8',
    '-- pocket tracker fixed data cart; project records occupy cart bytes 0x0000..0x248f'],
];

function shippedCommentInventory() {
  const comments = [];
  for (const file of [...nativeFiles, 'pocket-tracker-data.p8']) {
    read(file).toString('utf8').split('\n').forEach((line, index) => {
      if (line.trim().startsWith('--')) {
        comments.push({file, line: index + 1, source: line.trim()});
      }
    });
  }
  const actual = comments.map(({file, source}) => [file, source]);
  const legacy = [redundantNativeHeaders[0], ...retainedSafetyComments.slice(0, 4),
    ...redundantNativeHeaders.slice(1), retainedSafetyComments[4]];
  assert.ok(JSON.stringify(actual) === JSON.stringify(legacy) ||
    JSON.stringify(actual) === JSON.stringify(retainedSafetyComments),
  'shipped comments must be the exact legacy inventory or retain only safety comments');
  const presentHeaders = redundantNativeHeaders.map(([file, source]) =>
    comments.find((comment) => comment.file === file && comment.source === source));
  assert.ok(presentHeaders.every(Boolean) || presentHeaders.every((comment) => !comment),
    'redundant native headers must be completely present or completely absent');
  for (const comment of presentHeaders.filter(Boolean)) {
    assert.equal(comment.line, 1, `${comment.file} redundant header moved from line one`);
  }
  const redundantBytes = redundantNativeHeaders.reduce((total, [, source]) =>
    total + Buffer.byteLength(source + '\n'), 0);
  assert.equal(redundantBytes, 217, 'redundant native header byte inventory changed');
  return {redundantHeaders: redundantNativeHeaders, redundantBytes,
    retainedSafety: retainedSafetyComments, comments};
}

const snapshotAllowlist = {
  bank_snapshot_base: [
    ['audio_bank.lua', 'bank_size,bank_stage_base,bank_snapshot_base=0x1200,0x8000,0x9200'],
    ['audio_bank.lua', 'return base==bank_audio_base or base==bank_stage_base or base==bank_snapshot_base'],
    ['audio_bank.lua', 'memcpy(bank_snapshot_base,bank_audio_base,bank_size)'],
    ['audio_bank.lua', 'memcpy(bank_audio_base,bank_snapshot_base,bank_size)'],
  ],
  bank_snapshot_valid: [
    ['audio_bank.lua', 'bank_snapshot_valid,bank_snapshot_dirty=false,false'],
    ['audio_bank.lua', 'bank_snapshot_valid=true'],
    ['audio_bank.lua', 'if bank_profile_active or not bank_snapshot_valid then return false end'],
    ['audio_bank.lua', 'bank_snapshot_valid=false'],
    ['project_io.lua', 'bank_dirty=false bank_snapshot_valid=false undo_owner=nil'],
  ],
  bank_snapshot_dirty: [
    ['audio_bank.lua', 'bank_snapshot_valid,bank_snapshot_dirty=false,false'],
    ['audio_bank.lua', 'bank_snapshot_dirty=bank_dirty'],
    ['audio_bank.lua', 'bank_dirty=bank_snapshot_dirty'],
  ],
};

function snapshotLifecycle(symbol) {
  const references = symbolReferences(symbol);
  const actual = references.map(({file, source}) => [file, source]);
  const allowed = snapshotAllowlist[symbol];
  assert.ok(actual.length === 0 || actual.length === allowed.length,
    `${symbol} is only allowed as the complete legacy lifecycle or fully removed`);
  if (actual.length) assert.deepEqual(actual, allowed,
    `${symbol} left the exact legacy snapshot lifecycle allowlist`);
  return {symbol, references};
}

function nativeCrcPolynomial() {
  const references = [];
  for (const file of nativeFiles) {
    read(file).toString('utf8').split('\n').forEach((line, index) => {
      if (line.includes('0x1021')) {
        references.push({file, line: index + 1, source: line.trim()});
      }
    });
  }
  const actual = references.map(({file, source}) => [file, source]);
  const legacy = [
    ['audio_bank.lua', '-- crc-16/ccitt-false: poly 0x1021, init 0xffff, no reflection/xorout.'],
    ['audio_bank.lua', 'crc=((crc<<1)^^0x1021)&0xffff'],
    ['project_io.lua', 'crc=(crc&0x8000)!=0 and ((crc<<1)^^0x1021)&0xffff or (crc<<1)&0xffff'],
  ];
  const shared = [
    ['audio_bank.lua', '-- crc-16/ccitt-false: poly 0x1021, init 0xffff, no reflection/xorout.'],
    ['audio_bank.lua', 'crc=(crc&0x8000)!=0 and ((crc<<1)^^0x1021)&0xffff or (crc<<1)&0xffff'],
  ];
  assert.ok(JSON.stringify(actual) === JSON.stringify(legacy) ||
    JSON.stringify(actual) === JSON.stringify(shared),
  'native CRC polynomial must be the exact legacy pair or one shared byte step');
  return references;
}

const cartSource = read('pocket-tracker.p8').toString('utf8');
const cartIncludes = [...cartSource.matchAll(/^#include\s+(.+)$/gm)].map((match) => match[1]);
assert.deepEqual(cartIncludes, nativeFiles,
  'pocket-tracker.p8 production includes no longer match the native allowlist');

const indexSource = read('index.html').toString('utf8');
const browserScripts = [...indexSource.matchAll(/<script\s+src="([^"]+)"/g)].map((match) => match[1]);
const browserFrames = [...indexSource.matchAll(/<iframe[^>]+src="([^"]+)"/g)].map((match) => match[1]);
assert.deepEqual(browserScripts, ['mobile.js', 'help.js'],
  'index.html scripts no longer match the browser allowlist');
assert.deepEqual(browserFrames, ['tracker.html'],
  'index.html cartridge frame no longer points only at tracker.html');

const native = nativeFiles.map((file) => sourceMetrics(file, /^\s*--/));
const browser = browserFiles.map((file) =>
  sourceMetrics(file, /^\s*(?:\/\/|\/\*|<!--)/));
const reachability = ['bank_field', 'bank_copy', 'bank_rollback']
  .map(productionReachability);
const snapshotLifecycleReachability = Object.keys(snapshotAllowlist).map(snapshotLifecycle);
const microHelperReachability = Object.keys(microHelperAllowlists).map(microHelperLifecycle);
const shippedComments = shippedCommentInventory();
const nativeCrcPolynomialReferences = nativeCrcPolynomial();
const browserTestHooks = browserHookLifecycle();
const statusSetters = statusSetterLifecycle();
const storageTransactions = storageTransactionLifecycle();
const nativeTotal = sumMetrics(native);
const browserTotal = sumMetrics(browser);
assert.ok(nativeTotal.bytes <= 41898,
  `native source grew beyond the campaign baseline: ${nativeTotal.bytes} > 41898`);
assert.ok(browserTotal.bytes <= 53175,
  `browser source grew beyond the campaign baseline: ${browserTotal.bytes} > 53175`);

const trackerJs = read('tracker.js').toString('utf8');
const cartDataMatch = /var _cartdat=\[([\s\S]*?)\];/.exec(trackerJs);
assert.ok(cartDataMatch, 'tracker.js is missing its generated _cartdat array');
const cartData = (cartDataMatch[1].match(/\d+/g) || []).map(Number);
assert.equal(cartData.length, 32768, 'generated _cartdat is not exactly 32 KiB');
assert.ok(cartData.every((value) => value >= 0 && value <= 255),
  'generated _cartdat contains a value outside the byte range');

const pxaOffset = 0x4300;
const pxaHeader = cartData.slice(pxaOffset, pxaOffset + 8);
assert.deepEqual(pxaHeader.slice(0, 4), [0, 112, 120, 97],
  'raw/compressed PXA header magic changed');
const pxaRawBytes = pxaHeader[4] * 256 + pxaHeader[5];
const pxaCompressedBytes = pxaHeader[6] * 256 + pxaHeader[7];
assert.ok(pxaRawBytes <= 41913,
  `raw PXA grew beyond the campaign baseline: ${pxaRawBytes} > 41913`);
assert.ok(pxaRawBytes <= 65535, `raw PXA exceeds its format ceiling: ${pxaRawBytes}`);
assert.ok(pxaCompressedBytes <= 11613,
  `compressed PXA grew beyond the campaign baseline: ${pxaCompressedBytes} > 11613`);
assert.ok(pxaCompressedBytes <= 12288,
  `compressed PXA exceeds the release ceiling: ${pxaCompressedBytes}`);

const generated = generatedFiles.map((file) => {
  const buffer = read(file);
  return {file, bytes: buffer.length, sha256: sha256(buffer)};
});

console.log(JSON.stringify({
  allowlists: {
    native: nativeFiles,
    browser: browserFiles,
    generated: generatedFiles,
  },
  native: {files: native, total: nativeTotal},
  browser: {files: browser, total: browserTotal},
  reachability,
  snapshotLifecycle: snapshotLifecycleReachability,
  microHelpers: microHelperReachability,
  shippedComments,
  nativeCrcPolynomial: nativeCrcPolynomialReferences,
  browserTestHooks,
  statusSetters,
  storageTransactions,
  pxa: {
    offset: `0x${pxaOffset.toString(16)}`,
    header: pxaHeader,
    rawBytes: pxaRawBytes,
    compressedBytes: pxaCompressedBytes,
  },
  generated,
}, null, 2));
