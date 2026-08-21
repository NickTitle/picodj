const cart = document.querySelector('#cart');
const fileToggle = document.querySelector('#file-toggle');
const filePanel = document.querySelector('#file-panel');
const fileStatus = document.querySelector('#file-status');
const projectImport = document.querySelector('#project-import');

const trackerSurfaceSelector = [
  '#p8_frame_0',
  '#p8_frame',
  '#p8_container',
  '#p8_start_button',
  '#p8_playarea',
  '#canvas',
  '#touch_controls_background',
  '#touch_controls_gfx',
  '#p8_menu_buttons_touch',
  '#p8_menu_buttons',
  '.p8_menu_button',
].join(', ');

function installTouchSelectionGuard() {
  let frameDocument;
  try { frameDocument = cart.contentDocument; } catch (_) { return; }
  if (!frameDocument?.head || frameDocument.getElementById('pocket-tracker-touch-guard')) return;

  const style = frameDocument.createElement('style');
  style.id = 'pocket-tracker-touch-guard';
  style.textContent = `${trackerSurfaceSelector} {
    -webkit-touch-callout: none;
    -webkit-tap-highlight-color: transparent;
    -webkit-user-select: none;
    user-select: none;
  }`;
  frameDocument.head.appendChild(style);

  const preventSurfaceDefault = (event) => {
    if (event.target?.closest?.(trackerSurfaceSelector)) event.preventDefault();
  };
  frameDocument.addEventListener('selectstart', preventSurfaceDefault);
  frameDocument.addEventListener('contextmenu', preventSurfaceDefault);
}

cart.addEventListener('load', installTouchSelectionGuard);
installTouchSelectionGuard();

function download(blob, filename) {
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(link.href), 1000);
  return true;
}

const projectStoreKey = 'pocket-tracker:project:v2:last-known-good';
const projectEnvelopeSize = 4672;
const projectPayloadSize = 112;
const projectCommands = {savePage: 1, ack: 2, loadPage: 3, loadCommit: 4, done: 5, error: 6, loadRequest: 7};
let projectSaveTransfer = null;
let projectSaveLastAck = null;
let projectLoadTransfer = null;

function crc16Byte(crc, value) {
  crc ^= value << 8;
  for (let bit = 0; bit < 8; bit++) crc = crc & 0x8000 ? (crc << 1) ^ 0x1021 : crc << 1;
  return crc & 0xffff;
}

function crc16(bytes, start = 0, end = bytes.length, zeroStart = -1, zeroEnd = -1) {
  let crc = 0xffff;
  for (let i = start; i < end; i++) crc = crc16Byte(crc, i >= zeroStart && i < zeroEnd ? 0 : bytes[i]);
  return crc;
}

function get16(bytes, offset) { return bytes[offset] | (bytes[offset + 1] << 8); }

function envelopeValid(bytes) {
  if (!bytes || bytes.length !== projectEnvelopeSize) return false;
  if (bytes[0] !== 80 || bytes[1] !== 84 || bytes[2] !== 80 || bytes[3] !== 50 ||
      bytes[4] !== 2 || bytes[5] !== 64 || get16(bytes, 6) !== projectEnvelopeSize ||
      bytes[14] !== 1 || bytes[15] !== 1 || bytes[16] > 15 || bytes[32] > 23 ||
      bytes[56] !== 0 || bytes[57] !== 1 || bytes[58] !== 4) return false;
  for (let i = 59; i < 64; i++) if (bytes[i] !== 0) return false;
  if (headerText(bytes, 16, 15) === null || headerText(bytes, 32, 23) === null) return false;
  return crc16(bytes, 64) === get16(bytes, 8) &&
    crc16(bytes, 0, bytes.length, 10, 12) === get16(bytes, 10);
}

function envelopeHex(bytes) {
  let result = '';
  for (const value of bytes) result += value.toString(16).padStart(2, '0');
  return result;
}

function parseEnvelopeRecord(raw) {
  let record;
  try { record = JSON.parse(raw); } catch (_) { return null; }
  if (!record || record.format !== 'pocket-tracker' || record.version !== 2 ||
      typeof record.envelope !== 'string' || !/^[0-9a-f]+$/.test(record.envelope) ||
      record.envelope.length !== projectEnvelopeSize * 2) return null;
  const bytes = new Uint8Array(projectEnvelopeSize);
  for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(record.envelope.slice(i * 2, i * 2 + 2), 16);
  return envelopeValid(bytes) ? bytes : null;
}

function envelopeRecord(bytes) {
  return JSON.stringify({format: 'pocket-tracker', version: 2, envelope: envelopeHex(bytes)});
}

function sameBytes(a, b) {
  if (!a || !b || a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

function headerText(bytes, offset, limit) {
  const length = bytes[offset];
  if (length > limit) return null;
  let result = '';
  for (let i = 0; i < length; i++) {
    const value = bytes[offset + 1 + i];
    if (value < 32 || value > 126) return null;
    result += String.fromCharCode(value);
  }
  for (let i = length; i < limit; i++) if (bytes[offset + 1 + i] !== 0) return null;
  return result;
}

function put16(bytes, offset, value) {
  bytes[offset] = value & 255;
  bytes[offset + 1] = value >> 8;
}

function putHeaderText(bytes, offset, limit, value) {
  bytes[offset] = value.length;
  for (let i = 0; i < value.length; i++) bytes[offset + 1 + i] = value.charCodeAt(i);
}

function hexBytes(hex, length) {
  if (typeof hex !== 'string' || hex.length !== length * 2 || !/^[0-9a-f]+$/.test(hex)) return null;
  const bytes = new Uint8Array(length);
  for (let i = 0; i < length; i++) bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return bytes;
}

function checksumHex(value) { return value.toString(16).padStart(4, '0'); }

function exactKeys(value, keys) {
  return value !== null && typeof value === 'object' && !Array.isArray(value) &&
    Object.keys(value).sort().join('\0') === [...keys].sort().join('\0');
}

function safeText(value, limit) {
  return typeof value === 'string' && value.length <= limit && /^[\x20-\x7e]*$/.test(value);
}

function projectJson(bytes) {
  if (!envelopeValid(bytes)) return null;
  const name = headerText(bytes, 16, 15);
  const provenance = headerText(bytes, 32, 23);
  if (name === null || provenance === null) return null;
  return `${JSON.stringify({
    format: 'pocket-tracker-project',
    version: 2,
    project: {name, revision: get16(bytes, 12)},
    source: {format: 'pico-8', provenance, pattern: bytes[56]},
    playbackProfile: {
      kind: 'track-1-volume-boost', version: bytes[15],
      sfxStart: bytes[57], sfxCount: bytes[58], volumeBoost: 2,
    },
    bank: {
      encoding: 'hex', length: projectEnvelopeSize - 64,
      crc16: checksumHex(get16(bytes, 8)), data: envelopeHex(bytes.slice(64)),
    },
    checksum: {algorithm: 'crc16-ccitt-false', envelope: checksumHex(get16(bytes, 10))},
  }, null, 2)}\n`;
}

function parseProjectJson(raw) {
  let value;
  try { value = JSON.parse(raw); } catch (_) { return null; }
  if (!exactKeys(value, ['format', 'version', 'project', 'source', 'playbackProfile', 'bank', 'checksum']) ||
      value.format !== 'pocket-tracker-project' || value.version !== 2 ||
      !exactKeys(value.project, ['name', 'revision']) || !safeText(value.project.name, 15) ||
      !Number.isInteger(value.project.revision) || value.project.revision < 0 || value.project.revision > 0x7fff ||
      !exactKeys(value.source, ['format', 'provenance', 'pattern']) || value.source.format !== 'pico-8' ||
      !safeText(value.source.provenance, 23) || value.source.pattern !== 0 ||
      !exactKeys(value.playbackProfile, ['kind', 'version', 'sfxStart', 'sfxCount', 'volumeBoost']) ||
      value.playbackProfile.kind !== 'track-1-volume-boost' || value.playbackProfile.version !== 1 ||
      value.playbackProfile.sfxStart !== 1 || value.playbackProfile.sfxCount !== 4 ||
      value.playbackProfile.volumeBoost !== 2 ||
      !exactKeys(value.bank, ['encoding', 'length', 'crc16', 'data']) || value.bank.encoding !== 'hex' ||
      value.bank.length !== projectEnvelopeSize - 64 || !/^[0-9a-f]{4}$/.test(value.bank.crc16) ||
      !exactKeys(value.checksum, ['algorithm', 'envelope']) ||
      value.checksum.algorithm !== 'crc16-ccitt-false' || !/^[0-9a-f]{4}$/.test(value.checksum.envelope)) return null;
  const bank = hexBytes(value.bank.data, projectEnvelopeSize - 64);
  if (!bank || crc16(bank) !== parseInt(value.bank.crc16, 16)) return null;
  const bytes = new Uint8Array(projectEnvelopeSize);
  bytes.set([80, 84, 80, 50, 2, 64]);
  put16(bytes, 6, projectEnvelopeSize);
  put16(bytes, 8, parseInt(value.bank.crc16, 16));
  put16(bytes, 12, value.project.revision);
  bytes[14] = 1;
  bytes[15] = 1;
  putHeaderText(bytes, 16, 15, value.project.name);
  putHeaderText(bytes, 32, 23, value.source.provenance);
  bytes.set([0, 1, 4], 56);
  bytes.set(bank, 64);
  put16(bytes, 10, crc16(bytes, 0, bytes.length, 10, 12));
  return checksumHex(get16(bytes, 10)) === value.checksum.envelope && envelopeValid(bytes) ? bytes : null;
}

function materializedBank(bytes) {
  if (!envelopeValid(bytes)) return null;
  const bank = bytes.slice(64);
  for (let sfx = 1; sfx <= 4; sfx++) {
    const base = 0x100 + sfx * 68;
    for (let row = 0; row < 32; row++) {
      const offset = base + row * 2;
      const word = bank[offset] | (bank[offset + 1] << 8);
      const volume = (word >> 9) & 7;
      const boosted = volume === 0 ? word : (word & 0xf1ff) | (Math.min(7, volume + 2) << 9);
      bank[offset] = boosted & 255;
      bank[offset + 1] = boosted >> 8;
    }
  }
  return bank;
}

function p8Audio(bytes, representation) {
  if (!envelopeValid(bytes) || (representation !== 'authored' && representation !== 'materialized')) return null;
  const bank = representation === 'authored' ? bytes.slice(64) : materializedBank(bytes);
  const hex2 = (value) => value.toString(16).padStart(2, '0');
  const sfxLines = [];
  for (let sfx = 0; sfx < 64; sfx++) {
    const base = 0x100 + sfx * 68;
    let line = '';
    for (let i = 64; i < 68; i++) line += hex2(bank[base + i]);
    for (let row = 0; row < 32; row++) {
      const word = bank[base + row * 2] | (bank[base + row * 2 + 1] << 8);
      line += hex2(word & 0x3f);
      line += (((word >> 6) & 7) | ((word >> 12) & 8)).toString(16);
      line += ((word >> 9) & 7).toString(16);
      line += ((word >> 12) & 7).toString(16);
    }
    sfxLines.push(line);
  }
  const musicLines = [];
  for (let pattern = 0; pattern < 64; pattern++) {
    const base = pattern * 4;
    const flags = ((bank[base] >> 7) & 1) | (((bank[base + 1] >> 7) & 1) << 1) |
      (((bank[base + 2] >> 7) & 1) << 2) | (((bank[base + 3] >> 7) & 1) << 3);
    musicLines.push(`${hex2(flags)} ${hex2(bank[base] & 0x7f)}${hex2(bank[base + 1] & 0x7f)}` +
      `${hex2(bank[base + 2] & 0x7f)}${hex2(bank[base + 3] & 0x7f)}`);
  }
  const label = representation === 'authored' ? 'authored+profile' : 'materialized';
  const profile = representation === 'authored' ? `\n-- pocket-tracker-header: ${envelopeHex(bytes.slice(0, 64))}` : '';
  return `pico-8 cartridge // http://www.pico-8.com\nversion 43\n__lua__\n` +
    `-- pocket tracker audio export\n-- representation: ${label}${profile}\n__sfx__\n${sfxLines.join('\n')}\n` +
    `__music__\n${musicLines.join('\n')}\n`;
}

function parseP8Audio(raw) {
  if (typeof raw !== 'string') return null;
  const lines = raw.replace(/\r\n?/g, '\n').split('\n');
  const section = (name) => {
    const start = lines.indexOf(name);
    if (start < 0) return null;
    const result = [];
    for (let i = start + 1; i < lines.length && !/^__[a-z0-9_]+__$/.test(lines[i]); i++) {
      if (lines[i] !== '') result.push(lines[i]);
    }
    return result;
  };
  const music = section('__music__');
  const sfx = section('__sfx__');
  if (!music || !sfx || music.length > 64 || sfx.length > 64) return null;
  const bank = new Uint8Array(projectEnvelopeSize - 64);
  for (let pattern = 0; pattern < 64; pattern++) {
    for (let channel = 0; channel < 4; channel++) bank[pattern * 4 + channel] = 0x41 + channel;
  }
  for (let number = 0; number < 64; number++) bank[0x100 + number * 68 + 65] = 16;
  for (let pattern = 0; pattern < music.length; pattern++) {
    const match = /^([0-9a-f]{2}) ([0-9a-f]{8})$/.exec(music[pattern]);
    if (!match) return null;
    const flags = parseInt(match[1], 16);
    if (flags > 15) return null;
    for (let channel = 0; channel < 4; channel++) {
      const value = parseInt(match[2].slice(channel * 2, channel * 2 + 2), 16);
      if (value > 0x7f) return null;
      bank[pattern * 4 + channel] = value | (flags & (1 << channel) ? 0x80 : 0);
    }
  }
  for (let number = 0; number < sfx.length; number++) {
    const line = sfx[number];
    if (!/^[0-9a-f]{168}$/.test(line)) return null;
    const base = 0x100 + number * 68;
    for (let i = 0; i < 4; i++) bank[base + 64 + i] = parseInt(line.slice(i * 2, i * 2 + 2), 16);
    for (let row = 0; row < 32; row++) {
      const note = line.slice(8 + row * 5, 13 + row * 5);
      const pitch = parseInt(note.slice(0, 2), 16);
      const instrument = parseInt(note[2], 16);
      const volume = parseInt(note[3], 16);
      const effect = parseInt(note[4], 16);
      if (pitch > 63 || volume > 7 || effect > 7) return null;
      const word = pitch | ((instrument & 7) << 6) | (volume << 9) | (effect << 12) |
        ((instrument & 8) << 12);
      bank[base + row * 2] = word & 255;
      bank[base + row * 2 + 1] = word >> 8;
    }
  }
  const headerMatch = raw.match(/^-- pocket-tracker-header: ([0-9a-f]{128})$/m);
  return {bank, header: headerMatch ? hexBytes(headerMatch[1], 64) : null};
}

function storeLastKnownGood(bytes, storage = localStorage) {
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

function loadLastKnownGood(storage = localStorage) {
  try { return parseEnvelopeRecord(storage.getItem(projectStoreKey)); } catch (_) { return null; }
}

function frameCrc(bytes) {
  let crc = crc16(bytes, 0, 14);
  for (let i = 0; i < bytes[12]; i++) crc = crc16Byte(crc, bytes[16 + i]);
  return crc;
}

function frameValid(bytes, command) {
  return bytes && bytes.length >= 128 && bytes[0] === 80 && bytes[1] === 84 &&
    bytes[2] === 75 && bytes[3] === 50 && bytes[4] === 1 && bytes[5] === command &&
    bytes[12] <= projectPayloadSize && get16(bytes, 14) === frameCrc(bytes);
}

function writeFrame(gpio, command, id, sequence, offset, total, payload = null, flags = 0) {
  gpio.fill(0);
  gpio[0] = 80; gpio[1] = 84; gpio[2] = 75; gpio[3] = 50;
  gpio[4] = 1; gpio[5] = command; gpio[6] = id; gpio[7] = sequence;
  gpio[8] = offset & 255; gpio[9] = offset >> 8;
  gpio[10] = total & 255; gpio[11] = total >> 8;
  gpio[12] = payload?.length || 0; gpio[13] = flags;
  if (payload) for (let i = 0; i < payload.length; i++) gpio[16 + i] = payload[i];
  const checksum = frameCrc(gpio);
  gpio[14] = checksum & 255; gpio[15] = checksum >> 8;
}

function writeProjectError(gpio, id, code) {
  writeFrame(gpio, projectCommands.error, id, 0, 0, projectEnvelopeSize, null, code);
}

function acceptSavePage(gpio) {
  if (!frameValid(gpio, projectCommands.savePage)) return;
  const id = gpio[6], sequence = gpio[7], offset = get16(gpio, 8);
  const total = get16(gpio, 10), length = gpio[12], flags = gpio[13];
  const checksum = get16(gpio, 14);
  if (projectSaveLastAck?.id === id && projectSaveLastAck.sequence === sequence &&
      projectSaveLastAck.offset === offset && projectSaveLastAck.length === length &&
      projectSaveLastAck.checksum === checksum) {
    writeFrame(gpio, projectCommands.ack, id, sequence, offset, total);
    return;
  }
  if ((flags & 1) !== 0 && (!projectSaveTransfer || projectSaveTransfer.id !== id)) {
    projectSaveTransfer = {id, sequence: 0, offset: 0, bytes: new Uint8Array(total)};
    projectSaveLastAck = null;
  }
  const transfer = projectSaveTransfer;
  if (!transfer || transfer.id !== id || total !== projectEnvelopeSize ||
      sequence !== transfer.sequence || offset !== transfer.offset || offset + length > total) {
    writeProjectError(gpio, id, 6); projectSaveTransfer = null; projectSaveLastAck = null; return;
  }
  transfer.bytes.set(gpio.slice(16, 16 + length), offset);
  projectSaveLastAck = {id, sequence, offset, length, checksum};
  transfer.offset += length;
  transfer.sequence = (transfer.sequence + 1) & 255;
  if ((flags & 2) !== 0) {
    if (transfer.offset !== total || !storeLastKnownGood(transfer.bytes)) {
      writeProjectError(gpio, id, 7); projectSaveTransfer = null; projectSaveLastAck = null; return;
    }
    projectSaveTransfer = null;
  }
  writeFrame(gpio, projectCommands.ack, id, sequence, offset, total);
}

function sendLoadPage(gpio) {
  const transfer = projectLoadTransfer;
  const length = Math.min(projectPayloadSize, transfer.bytes.length - transfer.offset);
  const flags = (transfer.offset === 0 ? 1 : 0) |
    (transfer.offset + length === transfer.bytes.length ? 2 : 0);
  writeFrame(gpio, projectCommands.loadPage, transfer.id, transfer.sequence, transfer.offset,
    transfer.bytes.length, transfer.bytes.slice(transfer.offset, transfer.offset + length), flags);
  transfer.length = length;
  transfer.last = (flags & 2) !== 0;
}

function beginLoad(gpio) {
  if (!frameValid(gpio, projectCommands.loadRequest)) return;
  const id = gpio[6];
  const bytes = loadLastKnownGood();
  if (!bytes) { writeProjectError(gpio, id, 9); return; }
  projectLoadTransfer = {id, sequence: 0, offset: 0, bytes, length: 0, last: false};
  sendLoadPage(gpio);
}

function acceptLoadAck(gpio) {
  const transfer = projectLoadTransfer;
  if (!transfer || !frameValid(gpio, projectCommands.ack) || gpio[6] !== transfer.id ||
      gpio[7] !== transfer.sequence || get16(gpio, 8) !== transfer.offset) return;
  if (transfer.last) {
    writeFrame(gpio, projectCommands.loadCommit, transfer.id, transfer.sequence,
      transfer.offset, transfer.bytes.length);
    projectLoadTransfer = null;
    return;
  }
  transfer.offset += transfer.length;
  transfer.sequence = (transfer.sequence + 1) & 255;
  sendLoadPage(gpio);
}

function watchProjectIO() {
  let gpio;
  try { gpio = cart.contentWindow.pico8_gpio; } catch (_) { gpio = null; }
  if (gpio?.length >= 128) {
    if (gpio[5] === projectCommands.savePage) acceptSavePage(gpio);
    else if (gpio[5] === projectCommands.loadRequest) beginLoad(gpio);
    else if (gpio[5] === projectCommands.ack) acceptLoadAck(gpio);
    else if (gpio[5] === projectCommands.done || gpio[5] === projectCommands.error) projectLoadTransfer = null;
  }
  requestAnimationFrame(watchProjectIO);
}

globalThis.PocketTrackerProjectIO = Object.freeze({
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

function importProjectJson(raw, storage = localStorage) {
  const bytes = parseProjectJson(raw);
  return bytes !== null && storeLastKnownGood(bytes, storage);
}

function exportStoredFile(kind, storage = localStorage) {
  const bytes = loadLastKnownGood(storage);
  if (!bytes) return false;
  if (kind === 'json') {
    const json = projectJson(bytes);
    return json !== null && download(new Blob([json], {type: 'application/json'}),
      'pocket-tracker-project.json');
  }
  const p8 = p8Audio(bytes, kind);
  if (p8 === null) return false;
  const filename = kind === 'authored' ? 'pocket-tracker-authored-profile.p8' :
    'pocket-tracker-materialized.p8';
  return download(new Blob([p8], {type: 'text/plain'}), filename);
}

function setFileStatus(message, failed = false) {
  if (!fileStatus) return;
  fileStatus.textContent = message;
  fileStatus.style.color = failed ? '#ff8a8a' : '#c9c9de';
}

fileToggle?.addEventListener('click', () => {
  const open = filePanel.hidden;
  filePanel.hidden = !open;
  fileToggle.setAttribute('aria-expanded', String(open));
});

filePanel?.addEventListener('click', (event) => {
  const action = event.target.closest?.('[data-file-action]')?.dataset.fileAction;
  if (!action) return;
  if (action === 'import') { projectImport.click(); return; }
  const ok = exportStoredFile(action);
  setFileStatus(ok ? 'Download created from the checksum-verified browser slot.' :
    'No valid browser slot. Save in the tracker first.', !ok);
});

projectImport?.addEventListener('change', async () => {
  const file = projectImport.files?.[0];
  projectImport.value = '';
  if (!file) return;
  let raw;
  try { raw = await file.text(); } catch (_) {
    setFileStatus('Could not read that project file. The browser slot is unchanged.', true);
    return;
  }
  const ok = importProjectJson(raw);
  setFileStatus(ok ? 'Imported to the browser slot. Choose Load in the tracker to commit it.' :
    'Invalid project file. The browser slot and live project are unchanged.', !ok);
});

globalThis.PocketTrackerFileIO = Object.freeze({importProjectJson, exportStoredFile});

watchProjectIO();
