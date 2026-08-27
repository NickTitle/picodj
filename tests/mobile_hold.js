'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('mobile.js', 'utf8');
const frameListeners = new Map();
const cartListeners = new Map();
const outerListeners = new Map();
const appended = [];
let installedStyle = null;

const frameDocument = {
  head: {appendChild(node) { appended.push(node); installedStyle = node; }},
  createElement(tag) { return {tagName: tag.toUpperCase(), id: '', textContent: ''}; },
  getElementById(id) { return installedStyle?.id === id ? installedStyle : null; },
  addEventListener(type, listener) { frameListeners.set(type, listener); },
};
const cart = {
  contentDocument: frameDocument,
  contentWindow: {},
  addEventListener(type, listener) { cartListeners.set(type, listener); },
};
const fileStatus = {textContent: '', style: {}};
const projectImport = {
  files: [], value: '',
  addEventListener(type, listener) { outerListeners.set(`project-import:${type}`, listener); },
};
const control = {
  hidden: true,
  addEventListener() {},
  setAttribute() {},
};
const document = {
  querySelector(selector) {
    if (selector === '#cart') return cart;
    if (selector === '#project-import') return projectImport;
    if (selector === '#file-status') return fileStatus;
    return control;
  },
  createElement() { throw new Error('outer document must remain untouched'); },
};

vm.runInNewContext(source, {
  Blob,
  URL,
  document,
  localStorage: {getItem() { return null; }, setItem() {}, removeItem() {}},
  requestAnimationFrame() {},
  setTimeout() {},
});

assert.equal(typeof cartListeners.get('load'), 'function');
assert.equal(appended.length, 1);
assert.equal(installedStyle.id, 'pocket-tracker-touch-guard');
assert.match(installedStyle.textContent, /#p8_frame_0/);
assert.match(installedStyle.textContent, /#canvas/);
assert.match(installedStyle.textContent, /\.p8_menu_button/);
assert.match(installedStyle.textContent, /-webkit-touch-callout:\s*none/);
assert.match(installedStyle.textContent, /-webkit-tap-highlight-color:\s*transparent/);
assert.match(installedStyle.textContent, /-webkit-user-select:\s*none/);
assert.match(installedStyle.textContent, /user-select:\s*none/);
assert.doesNotMatch(installedStyle.textContent, /(^|,)\s*(html|body|\*)\s*[{,]/m);

for (const type of ['selectstart', 'contextmenu']) {
  const listener = frameListeners.get(type);
  assert.equal(typeof listener, 'function');
  let prevented = false;
  listener({target: {closest: () => ({id: 'canvas'})}, preventDefault() { prevented = true; }});
  assert.equal(prevented, true, `${type} is suppressed on the tracker surface`);
  prevented = false;
  listener({target: {closest: () => null}, preventDefault() { prevented = true; }});
  assert.equal(prevented, false, `${type} remains normal outside the tracker surface`);
}

assert.equal(frameListeners.has('keydown'), false);
assert.equal(frameListeners.has('touchstart'), false);
cartListeners.get('load')();
assert.equal(appended.length, 1, 'installation is idempotent');
const importChange = outerListeners.get('project-import:change');
assert.equal(typeof importChange, 'function');
projectImport.files = [{name: 'headerless.P8', text: async () => '__sfx__\n__music__\n'}];
Promise.resolve(importChange()).then(() => {
  assert.match(fileStatus.textContent, /no lossless profile header/);
  assert.equal(fileStatus.style.color, '#ff8a8a');
  console.log('pocket tracker mobile hold: passed');
}).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
