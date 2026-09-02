'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const {withHelpTestHooks} = require('./browser_test_hooks');

class Target {
  constructor(id, document) {
    this.id = id;
    this.document = document;
    this.listeners = new Map();
    this.attributes = new Map();
    this.inert = false;
    this.isConnected = true;
  }
  addEventListener(type, listener) {
    if (!this.listeners.has(type)) this.listeners.set(type, []);
    this.listeners.get(type).push(listener);
  }
  dispatch(type, event = {}) {
    event.target ||= this;
    for (const listener of this.listeners.get(type) || []) listener(event);
  }
  setAttribute(name, value) { this.attributes.set(name, String(value)); }
  removeAttribute(name) { this.attributes.delete(name); }
  getAttribute(name) { return this.attributes.get(name) ?? null; }
  focus() { this.document.activeElement = this; }
}

const document = {activeElement: null};
const appShell = new Target('app-shell', document);
const helpToggle = new Target('help-toggle', document);
const closeTop = new Target('close-top', document);
const closeBottom = new Target('close-bottom', document);
const helpDialog = new Target('help-dialog', document);
helpDialog.open = false;
helpDialog.showModal = function () { this.open = true; this.setAttribute('open', ''); };
helpDialog.close = function () {
  this.open = false;
  this.removeAttribute('open');
  this.dispatch('close');
};
helpDialog.querySelector = (selector) => selector === '[autofocus]' ? closeTop : null;
helpDialog.querySelectorAll = () => [closeTop, closeBottom];
helpDialog.contains = (node) => node === closeTop || node === closeBottom || node === helpDialog;
document.querySelector = (selector) => ({
  '#app-shell': appShell,
  '#help-toggle': helpToggle,
  '#help-dialog': helpDialog,
}[selector] || null);

const gpio = Object.freeze(new Array(128).fill(0));
const storage = new Map([['project', 'unchanged']]);
const localStorage = Object.freeze({
  getItem() { throw new Error('help must not read storage'); },
  setItem() { throw new Error('help must not write storage'); },
  removeItem() { throw new Error('help must not remove storage'); },
});
const source = withHelpTestHooks(fs.readFileSync('help.js', 'utf8'));
const globalObject = {};
vm.runInNewContext(source, {document, globalThis: globalObject, localStorage, pico8_gpio: gpio,
  requestAnimationFrame(callback) { callback(); }});
const help = globalObject.__PocketTrackerTestHooks.help;

const html = fs.readFileSync('index.html', 'utf8');
assert.match(html, /<button id="help-toggle"[^>]*aria-haspopup="dialog"[^>]*aria-expanded="false"[^>]*aria-controls="help-dialog"/);
assert.ok(html.indexOf('id="help-toggle"') < html.indexOf('id="cart"'),
  'Help precedes the cross-frame tracker in DOM and tab order');
assert.match(html, /<dialog id="help-dialog"[^>]*aria-labelledby="help-title"[^>]*aria-describedby="help-intro"[^>]*aria-modal="true"/);
assert.match(html, /<h1 id="help-title">Pocket Tracker help<\/h1>/);
assert.match(html, /<section aria-labelledby="help-song">/);
assert.match(html, /<section aria-labelledby="help-sfx">/);
assert.match(html, /<section aria-labelledby="help-repeat">/);
assert.match(html, /<section aria-labelledby="help-projects">/);
assert.match(html, /Tracker Save updates only the last-known-good browser slot/);
assert.match(html, /new project and revision actions snapshot that slot/);
assert.match(html, /Stage copies a validated revision into the browser slot/);
assert.match(html, /Tracker Load is the only action that commits it live/);
assert.match(html, /Corrupt newer copies fall back to older valid ones without rewriting storage/);
assert.match(html, /Recovery and library reset never change the browser slot or live tracker/);
assert.match(html, /width: min\(680px, calc\(100vw - 32px\)\)/,
  'desktop viewport keeps a bounded dialog with outer gutters');
assert.match(html, /@media \(max-width: 600px\), \(pointer: coarse\)/,
  'touch viewport has a dedicated responsive rule');
assert.match(html, /#help-dialog \{ width: 100vw; max-width: none; height: 100dvh; max-height: none/,
  'touch viewport uses the full dynamic viewport');
assert.match(html, /#help-dialog button \{ min-width: 44px; min-height: 44px/,
  'dialog actions meet the 44px touch target');
assert.match(html, /env\(safe-area-inset-top\)/);
assert.match(html, /env\(safe-area-inset-bottom\)/);

helpToggle.focus();
helpToggle.dispatch('click');
assert.equal(helpDialog.open, true, 'touch/click activation opens the modal');
assert.equal(appShell.inert, true, 'the complete application background becomes inert');
assert.equal(helpToggle.getAttribute('aria-expanded'), 'true');
assert.equal(document.activeElement, closeTop, 'focus enters the dialog at its labelled close action');

let prevented = false;
document.activeElement = closeBottom;
helpDialog.dispatch('keydown', {key: 'Tab', shiftKey: false, preventDefault() { prevented = true; }});
assert.equal(prevented, true);
assert.equal(document.activeElement, closeTop, 'forward Tab wraps inside the dialog');
prevented = false;
document.activeElement = closeTop;
helpDialog.dispatch('keydown', {key: 'Tab', shiftKey: true, preventDefault() { prevented = true; }});
assert.equal(prevented, true);
assert.equal(document.activeElement, closeBottom, 'reverse Tab wraps inside the dialog');

prevented = false;
helpDialog.dispatch('keydown', {key: 'Escape', preventDefault() { prevented = true; }});
assert.equal(prevented, true);
assert.equal(helpDialog.open, false, 'Escape closes help');
assert.equal(appShell.inert, false, 'closing restores background interactivity');
assert.equal(helpToggle.getAttribute('aria-expanded'), 'false');
assert.equal(document.activeElement, helpToggle, 'closing restores focus to the opener');

appShell.inert = true;
helpToggle.dispatch('click');
let cancelled = false;
helpDialog.dispatch('cancel', {preventDefault() { cancelled = true; }});
assert.equal(cancelled, true, 'native dialog cancellation is handled explicitly');
assert.equal(appShell.inert, true, 'pre-existing inert state is restored exactly');
appShell.inert = false;
helpToggle.dispatch('click');
helpDialog.dispatch('click', {target: {closest(selector) { return selector === '[data-help-close]' ? closeBottom : null; }}});
assert.equal(helpDialog.open, false, 'touch close action closes help');
assert.equal(document.activeElement, helpToggle, 'touch close restores opener focus');

const detachedOpener = new Target('detached', document);
detachedOpener.isConnected = false;
detachedOpener.focus();
help.open();
helpDialog.dispatch('keydown', {key: 'Escape', preventDefault() {}});
assert.equal(document.activeElement, helpToggle, 'a disconnected opener falls back to Help');

const removedDuringHelp = new Target('removed-during-help', document);
removedDuringHelp.focus();
help.open();
removedDuringHelp.isConnected = false;
help.close();
assert.equal(document.activeElement, helpToggle, 'an opener removed while help is open falls back to Help');

assert.deepEqual(Array.from(gpio), new Array(128).fill(0), 'help never mutates live GPIO');
assert.deepEqual(Array.from(storage), [['project', 'unchanged']], 'help never mutates durable project state');
console.log('pocket tracker help dialog: passed');
