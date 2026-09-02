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
const libraryStatus = {textContent: '', style: {}};
let importClicks = 0;
const projectImport = {
  files: [], value: '',
  addEventListener(type, listener) { outerListeners.set(`project-import:${type}`, listener); },
  click() { importClicks++; },
};
function control(name, values = {}) {
  return {
    ...values,
    addEventListener(type, listener) { outerListeners.set(`${name}:${type}`, listener); },
    setAttribute(attribute, value) { this[attribute] = String(value); },
  };
}
const fileToggle = control('file-toggle');
const filePanel = control('file-panel', {hidden: true});
const projectLibraryPanel = control('project-library');
const libraryProject = control('library-project', {value: ''});
const libraryRevision = control('library-revision', {value: ''});
const controlFallback = control('fallback');
const document = {
  querySelector(selector) {
    if (selector === '#cart') return cart;
    if (selector === '#file-toggle') return fileToggle;
    if (selector === '#file-panel') return filePanel;
    if (selector === '#project-import') return projectImport;
    if (selector === '#file-status') return fileStatus;
    if (selector === '#library-project') return libraryProject;
    if (selector === '#library-revision') return libraryRevision;
    if (selector === '#project-library-status') return libraryStatus;
    if (selector === '#project-library') return projectLibraryPanel;
    return controlFallback;
  },
  createElement() { throw new Error('outer document must remain untouched'); },
};
const stored = new Map();
const localStorage = {
  getItem(key) { return stored.has(key) ? stored.get(key) : null; },
  setItem(key, value) { stored.set(key, String(value)); },
  removeItem(key) { stored.delete(key); },
};

const raf = [];
const globalObject = {};
vm.runInNewContext(source, {
  Blob,
  URL,
  document,
  globalThis: globalObject,
  localStorage,
  requestAnimationFrame(callback) { raf.push(callback); },
  setTimeout() {},
});

const legacyMobileHooks = [
  'PocketTrackerProjectIO',
  'PocketTrackerLibrary',
  'PocketTrackerFileIO',
];
const legacyDefinitionsPresent = legacyMobileHooks.every((name) =>
  source.includes(`globalThis.${name} = Object.freeze(`));
assert.deepEqual(legacyMobileHooks.map((name) => Object.hasOwn(globalObject, name)),
  legacyMobileHooks.map(() => legacyDefinitionsPresent),
  'the shipped VM exposes either the exact legacy browser hooks or none of them');
assert.equal(typeof raf[0], 'function', 'the shipped project bridge starts through requestAnimationFrame');

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

outerListeners.get('file-toggle:click')();
assert.equal(filePanel.hidden, false, 'Files opens through its shipped click listener');
assert.equal(fileToggle['aria-expanded'], 'true');
outerListeners.get('file-panel:click')({target: {
  closest(selector) { return selector === '[data-file-action]' ? {dataset: {fileAction: 'json'}} : null; },
}});
assert.match(fileStatus.textContent, /No valid browser slot/,
  'export runs through the Files event path without a test API');
outerListeners.get('file-panel:click')({target: {
  closest(selector) { return selector === '[data-file-action]' ? {dataset: {fileAction: 'import'}} : null; },
}});
assert.equal(importClicks, 1, 'the Files import action reaches the hidden input through DOM events');
outerListeners.get('project-library:click')({target: {
  closest(selector) { return selector === '[data-library-action]' ? {dataset: {libraryAction: 'new'}} : null; },
}});
assert.match(libraryStatus.textContent, /Could not add a project/,
  'library actions run through the shipped panel listener without a test API');

const importChange = outerListeners.get('project-import:change');
assert.equal(typeof importChange, 'function');
projectImport.files = [{name: 'headerless.P8', text: async () => '__sfx__\n__music__\n'}];
Promise.resolve(importChange()).then(() => {
  assert.match(fileStatus.textContent, /Imported audio sections as no profile/);
  assert.equal(fileStatus.style.color, '#c9c9de');
  console.log('pocket tracker mobile hold: passed');
}).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
