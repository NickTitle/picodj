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
  pxa: {
    offset: `0x${pxaOffset.toString(16)}`,
    header: pxaHeader,
    rawBytes: pxaRawBytes,
    compressedBytes: pxaCompressedBytes,
  },
  generated,
}, null, 2));
