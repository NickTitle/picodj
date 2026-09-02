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
  pxa: {
    offset: `0x${pxaOffset.toString(16)}`,
    header: pxaHeader,
    rawBytes: pxaRawBytes,
    compressedBytes: pxaCompressedBytes,
  },
  generated,
}, null, 2));
