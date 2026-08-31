'use strict';

const assert = require('node:assert/strict');
const path = require('node:path');
const {pathToFileURL} = require('node:url');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

const pageUrl = pathToFileURL(path.resolve('index.html')).href;
const storageKeys = [
  'pocket-tracker:project:v2:last-known-good',
  'pocket-tracker:library:v1',
];

async function stateSnapshot(page) {
  return page.evaluate((keys) => {
    const storage = keys.map((key) => {
      try { return [key, localStorage.getItem(key)]; } catch (error) { return [key, `error:${error.name}`]; }
    });
    let gpio = null;
    try {
      const value = document.querySelector('#cart').contentWindow.pico8_gpio;
      if (value?.length >= 128) gpio = Array.from(value.slice(0, 128));
    } catch (_) {}
    return {storage, gpio};
  }, storageKeys);
}

async function assertDialogInViewport(page, viewport, label) {
  const box = await page.locator('#help-dialog').boundingBox();
  assert.ok(box, `${label}: dialog has a rendered box`);
  assert.ok(box.x >= -0.5 && box.y >= -0.5, `${label}: dialog begins within the viewport`);
  assert.ok(box.x + box.width <= viewport.width + 0.5,
    `${label}: dialog width stays within the viewport`);
  assert.ok(box.y + box.height <= viewport.height + 0.5,
    `${label}: dialog height stays within the viewport`);
  const metrics = await page.locator('#help-dialog').evaluate((node) => ({
    clientWidth: node.clientWidth,
    scrollWidth: node.scrollWidth,
    clientHeight: node.clientHeight,
    scrollHeight: node.scrollHeight,
  }));
  assert.ok(metrics.scrollWidth <= metrics.clientWidth + 1,
    `${label}: help has no horizontal overflow`);
  assert.ok(metrics.scrollHeight >= metrics.clientHeight,
    `${label}: overflow remains internal to the dialog`);
  const close = await page.locator('[data-help-close]').first().boundingBox();
  assert.ok(close && close.width >= 44 && close.height >= 44,
    `${label}: close remains reachable with a 44px touch target`);
  assert.ok(close.y >= -0.5 && close.y + close.height <= viewport.height + 0.5,
    `${label}: close remains visible`);
}

async function runViewport(browser, viewport, touch) {
  const context = await browser.newContext({viewport, hasTouch: touch, isMobile: touch});
  const page = await context.newPage();
  await page.goto(pageUrl);
  await page.waitForSelector('#help-toggle');
  await page.waitForTimeout(500);
  await page.evaluate(() => {
    const frame = document.querySelector('#cart').contentWindow;
    if (!frame.pico8_gpio?.length) frame.pico8_gpio = Array.from({length: 128}, (_, index) => index);
    window.__helpStorageWrites = [];
    for (const method of ['setItem', 'removeItem']) {
      const original = Storage.prototype[method];
      Storage.prototype[method] = function (...args) {
        window.__helpStorageWrites.push([method, ...args]);
        return original.apply(this, args);
      };
    }
  });
  const before = await stateSnapshot(page);
  assert.equal(before.gpio?.length, 128, 'the post-bootstrap snapshot includes all 128 GPIO bytes');

  const opener = page.locator('#help-toggle');
  const openerBox = await opener.boundingBox();
  if (touch) await page.touchscreen.tap(openerBox.x + openerBox.width / 2, openerBox.y + openerBox.height / 2);
  else await opener.click();
  await page.locator('#help-dialog').waitFor({state: 'visible'});
  assert.equal(await page.locator('#app-shell').evaluate((node) => node.inert), true,
    'native modal keeps the sibling application shell inert');
  await assertDialogInViewport(page, viewport, `${viewport.width}x${viewport.height}`);

  let outsideBlocked = false;
  try { await page.locator('#file-toggle').click({timeout: 500}); }
  catch (_) { outsideBlocked = true; }
  assert.equal(outsideBlocked, true, 'real user-like browser input is blocked on an inert outside control');
  assert.equal(await page.locator('#file-toggle').getAttribute('aria-expanded'), 'false',
    'user-like input cannot activate an inert outside control');

  if (!touch) {
    await page.locator('[data-help-close]').first().focus();
    await page.keyboard.press('Shift+Tab');
    assert.equal(await page.evaluate(() => document.activeElement.textContent.trim()), 'Return to tracker',
      'desktop Shift+Tab wraps to the last dialog action');
    await page.keyboard.press('Tab');
    assert.equal(await page.evaluate(() => document.activeElement.getAttribute('aria-label')), 'Close help',
      'desktop Tab wraps back to the first dialog action');
  } else {
    assert.equal(await page.locator('#help-dialog').evaluate((node) => node.contains(document.activeElement)), true,
      `${viewport.width}x${viewport.height}: opening focus remains inside the dialog`);
  }

  if (viewport.width === 390) {
    const rotated = {width: 844, height: 390};
    await page.setViewportSize(rotated);
    await assertDialogInViewport(page, rotated, '844x390 rotated');
  }
  if (touch) {
    const closeBox = await page.locator('[data-help-close]').first().boundingBox();
    await page.touchscreen.tap(closeBox.x + closeBox.width / 2, closeBox.y + closeBox.height / 2);
  } else await page.keyboard.press('Escape');
  assert.equal(await page.locator('#help-dialog').evaluate((node) => node.open), false,
    'Escape or the touch close action closes the dialog');
  await page.waitForFunction(() => document.activeElement.id === 'help-toggle');
  assert.equal(await page.evaluate(() => document.activeElement.id), 'help-toggle',
    'focus restores to Help after close and resize');
  assert.equal(await page.locator('#app-shell').evaluate((node) => node.inert), false,
    'background inertness is removed on close');

  const after = await stateSnapshot(page);
  assert.deepEqual(await page.evaluate(() => window.__helpStorageWrites), [],
    'help never calls setItem or removeItem after normal page initialization');
  assert.deepEqual(after.storage, before.storage, 'help preserves both durable storage keys');
  assert.deepEqual(after.gpio, before.gpio, 'help preserves all 128 live GPIO bytes');
  await context.close();
}

(async () => {
  const browser = await chromium.launch({headless: true, args: ['--allow-file-access-from-files']});
  try {
    await runViewport(browser, {width: 1280, height: 720}, false);
    await runViewport(browser, {width: 390, height: 844}, true);
    await runViewport(browser, {width: 568, height: 320}, true);
  } finally {
    await browser.close();
  }
  console.log('pocket tracker help viewports: passed');
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
