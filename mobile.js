const cart = document.querySelector('#cart');
const waveNames = ['triangle', 'tilted-saw', 'saw', 'square', 'pulse', 'organ', 'noise', 'phaser'];
let lastExportRequest = null;

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

function readProject() {
  let gpio;
  try { gpio = cart.contentWindow.pico8_gpio; } catch (_) { return null; }
  if (!gpio || gpio[0] !== 80 || gpio[1] !== 84 || gpio[2] !== 1) return null;
  let p = 4;
  const channels = [];
  for (let ch = 0; ch < 4; ch++) {
    channels.push({waveform: gpio[p++], volume: gpio[p++], effect: gpio[p++], notes: []});
  }
  for (let ch = 0; ch < 4; ch++) {
    for (let step = 0; step < 16; step++) {
      const note = gpio[p++];
      channels[ch].notes.push(note === 63 ? null : note);
    }
  }
  return {
    format: 'pocket-tracker',
    version: 1,
    bpm: gpio[3],
    steps: 16,
    channels: channels.map((ch) => ({...ch, waveformName: waveNames[ch.waveform] || 'unknown'})),
  };
}

function download(blob, filename) {
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(link.href), 1000);
}

function sampleWave(wave, phase, sample, frequency, seed) {
  const cycle = phase - Math.floor(phase);
  if (wave === 0) return 1 - 4 * Math.abs(cycle - 0.5);
  if (wave === 1) return 1.5 * (1 - 2 * cycle) * (0.55 + 0.45 * Math.sin(phase * Math.PI * 2));
  if (wave === 2) return 1 - 2 * cycle;
  if (wave === 3) return cycle < 0.5 ? 1 : -1;
  if (wave === 4) return cycle < 0.25 ? 1 : -1;
  if (wave === 5) return 0.65 * Math.sin(phase * Math.PI * 2) + 0.25 * Math.sin(phase * Math.PI * 4) + 0.1 * Math.sin(phase * Math.PI * 8);
  if (wave === 6) {
    const n = Math.sin((sample + seed * 8191) * 12.9898) * 43758.5453;
    return (n - Math.floor(n)) * 2 - 1;
  }
  return 0.65 * Math.sin(phase * Math.PI * 2) + 0.35 * Math.sin((phase * 1.013 + seed) * Math.PI * 2);
}

function renderWav(project) {
  const sampleRate = 44100;
  const stepSeconds = 60 / project.bpm / 4;
  const length = Math.ceil(project.steps * stepSeconds * sampleRate);
  const pcm = new Float32Array(length);
  for (let ch = 0; ch < project.channels.length; ch++) {
    const channel = project.channels[ch];
    const gain = channel.volume / 7 * 0.22;
    for (let step = 0; step < project.steps; step++) {
      const note = channel.notes[step];
      if (note == null || gain === 0) continue;
      const start = Math.floor(step * stepSeconds * sampleRate);
      const end = Math.min(length, Math.floor((step + 1) * stepSeconds * sampleRate));
      const frequency = 16.3516 * Math.pow(2, note / 12);
      for (let i = start; i < end; i++) {
        const local = (i - start) / sampleRate;
        const duration = (end - start) / sampleRate;
        const attack = Math.min(1, local / 0.006);
        const release = Math.min(1, (duration - local) / 0.025);
        const phase = local * frequency;
        pcm[i] += sampleWave(channel.waveform, phase, i, frequency, ch + 1) * gain * attack * release;
      }
    }
  }
  const buffer = new ArrayBuffer(44 + pcm.length * 2);
  const view = new DataView(buffer);
  const text = (offset, value) => [...value].forEach((char, i) => view.setUint8(offset + i, char.charCodeAt(0)));
  text(0, 'RIFF'); view.setUint32(4, 36 + pcm.length * 2, true); text(8, 'WAVE');
  text(12, 'fmt '); view.setUint32(16, 16, true); view.setUint16(20, 1, true);
  view.setUint16(22, 1, true); view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true); view.setUint16(32, 2, true); view.setUint16(34, 16, true);
  text(36, 'data'); view.setUint32(40, pcm.length * 2, true);
  for (let i = 0; i < pcm.length; i++) {
    const value = Math.max(-1, Math.min(1, pcm[i]));
    view.setInt16(44 + i * 2, value < 0 ? value * 32768 : value * 32767, true);
  }
  return new Blob([buffer], {type: 'audio/wav'});
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
  storeLastKnownGood,
  loadLastKnownGood,
  frameValid,
  writeFrame,
});

function watchExports() {
  let gpio;
  try { gpio = cart.contentWindow.pico8_gpio; } catch (_) { gpio = null; }

  const project = readProject();
  if (gpio && project) {
    const request = gpio[126];
    if (lastExportRequest === null) {
      lastExportRequest = request;
    } else if (request !== lastExportRequest) {
      lastExportRequest = request;
      if (gpio[125] === 2) {
        download(renderWav(project), 'pocket-tracker-song.wav');
      } else {
        download(new Blob([JSON.stringify(project, null, 2)], {type: 'application/json'}), 'pocket-tracker-song.json');
      }
    }
  }

  requestAnimationFrame(watchExports);
}

watchProjectIO();
watchExports();
