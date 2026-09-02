'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const source = fs.readFileSync('mobile.js', 'utf8');
const html = fs.readFileSync('index.html', 'utf8');
assert.match(html, /<p id="project-library-status" role="status" aria-live="polite">/,
  'the library status remains an independent polite live region');
assert.match(html, /<p id="file-status" role="status" aria-live="polite">/,
  'the Files status remains an independent polite live region');
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
assert.equal(fileStatus.textContent, 'No valid browser slot. Save in the tracker first.',
  'failed export reports its exact Files message through the shipped event path');
assert.equal(fileStatus.style.color, '#ff8a8a', 'failed export uses the exact failure color');
assert.equal(libraryStatus.textContent, '', 'Files failure does not update the library live region');
outerListeners.get('file-panel:click')({target: {
  closest(selector) { return selector === '[data-file-action]' ? {dataset: {fileAction: 'import'}} : null; },
}});
assert.equal(importClicks, 1, 'the Files import action reaches the hidden input through DOM events');
outerListeners.get('project-library:click')({target: {
  closest(selector) { return selector === '[data-library-action]' ? {dataset: {libraryAction: 'new'}} : null; },
}});
assert.equal(libraryStatus.textContent,
  'Could not add a project. Save in the tracker first, free a project slot, or check browser storage.',
  'failed library action reports its exact message through the shipped event path');
assert.equal(libraryStatus.style.color, '#ff8a8a', 'failed library action uses the exact failure color');
assert.equal(fileStatus.textContent, 'No valid browser slot. Save in the tracker first.',
  'library failure does not update the Files live region');

const importChange = outerListeners.get('project-import:change');
assert.equal(typeof importChange, 'function');
projectImport.files = [{name: 'headerless.P8', text: async () => '__sfx__\n__music__\n'}];
Promise.resolve(importChange()).then(() => {
  assert.equal(fileStatus.textContent,
    'Imported audio sections as no profile; external Lua is not included. Choose Load in the tracker.',
  'successful import reports its exact Files message through the shipped change event');
  assert.equal(fileStatus.style.color, '#c9c9de', 'successful import uses the exact normal color');
  assert.match(libraryStatus.textContent, /Could not add a project/,
    'Files success does not update the library live region');
  outerListeners.get('project-library:click')({target: {
    closest(selector) { return selector === '[data-library-action]' ? {dataset: {libraryAction: 'new'}} : null; },
  }});
  assert.equal(libraryStatus.textContent, 'Saved browser slot as project 1.',
    'successful library action reports its exact message through the shipped event path');
  assert.equal(libraryStatus.style.color, '#c9c9de', 'successful library action uses the exact normal color');
  assert.match(fileStatus.textContent, /Imported audio sections as no profile/,
    'library success does not update the Files live region');
  console.log('pocket tracker mobile hold: passed');
}).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

function assertMissingStatusNoop(missingSelector, listenerKey, actionAttribute, datasetKey, action) {
  const listeners = new Map();
  const nodes = new Map();
  function node(selector) {
    if (!nodes.has(selector)) nodes.set(selector, {
      hidden: true,
      files: [],
      value: '',
      style: {},
      addEventListener(type, listener) { listeners.set(`${selector}:${type}`, listener); },
      setAttribute() {},
      click() {},
    });
    return nodes.get(selector);
  }
  const optionalCart = {
    contentDocument: {
      head: {appendChild() {}},
      createElement() { return {}; },
      getElementById() { return null; },
      addEventListener() {},
    },
    contentWindow: {},
    addEventListener() {},
  };
  const optionalDocument = {
    querySelector(selector) {
      if (selector === missingSelector) return null;
      if (selector === '#cart') return optionalCart;
      return node(selector);
    },
    createElement() { return {click() {}, remove() {}}; },
    body: {appendChild() {}},
  };
  const optionalStorage = {
    getItem() { return null; },
    setItem() {},
    removeItem() {},
  };
  vm.runInNewContext(source, {
    Blob,
    URL,
    document: optionalDocument,
    localStorage: optionalStorage,
    requestAnimationFrame() {},
    setTimeout() {},
  });
  const listener = listeners.get(listenerKey);
  assert.equal(typeof listener, 'function');
  assert.doesNotThrow(() => listener({target: {
    closest(selector) {
      return selector === actionAttribute ? {dataset: {[datasetKey]: action}} : null;
    },
  }}), `${missingSelector} is an optional no-op through its shipped event path`);
}

assertMissingStatusNoop('#file-status', '#file-panel:click', '[data-file-action]', 'fileAction', 'json');
assertMissingStatusNoop('#project-library-status', '#project-library:click',
  '[data-library-action]', 'libraryAction', 'new');
