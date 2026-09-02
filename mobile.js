const cart = document.querySelector('#cart');
const fileToggle = document.querySelector('#file-toggle');
const filePanel = document.querySelector('#file-panel');
const fileStatus = document.querySelector('#file-status');
const projectImport = document.querySelector('#project-import');
const libraryProject = document.querySelector('#library-project');
const libraryRevision = document.querySelector('#library-revision');
const libraryStatus = document.querySelector('#project-library-status');
const projectLibraryPanel = document.querySelector('#project-library');

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
const projectLibraryKey = 'pocket-tracker:library:v1';
const projectLibraryMaxProjects = 8;
const projectLibraryMaxRevisions = 4;
const projectLibraryMaxChars = 302213;
const projectEnvelopeSize = 4672;
const projectPayloadSize = 112;
const projectCommands = {savePage: 1, ack: 2, loadPage: 3, loadCommit: 4, done: 5, error: 6, loadRequest: 7};
let projectSaveTransfer = null;
let projectSaveLastAck = null;
let projectLoadTransfer = null;
const uncertainLibraryStorage = new WeakSet();

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
  const profile = bytes[14];
  if (bytes[0] !== 80 || bytes[1] !== 84 || bytes[2] !== 80 || bytes[3] !== 50 ||
      bytes[4] !== 2 || bytes[5] !== 64 || get16(bytes, 6) !== projectEnvelopeSize ||
      profile > 1 || bytes[15] !== profile || bytes[16] > 15 || bytes[32] > 23 ||
      bytes[56] !== 0 || bytes[57] !== profile || bytes[58] !== profile * 4) return false;
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
    playbackProfile: bytes[14] ? {
      kind: 'track-1-volume-boost', version: bytes[15],
      sfxStart: bytes[57], sfxCount: bytes[58], volumeBoost: 2,
    } : null,
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
  const profile = value?.playbackProfile;
  if (!exactKeys(value, ['format', 'version', 'project', 'source', 'playbackProfile', 'bank', 'checksum']) ||
      value.format !== 'pocket-tracker-project' || value.version !== 2 ||
      !exactKeys(value.project, ['name', 'revision']) || !safeText(value.project.name, 15) ||
      !Number.isInteger(value.project.revision) || value.project.revision < 0 || value.project.revision > 0x7fff ||
      !exactKeys(value.source, ['format', 'provenance', 'pattern']) || value.source.format !== 'pico-8' ||
      !safeText(value.source.provenance, 23) || value.source.pattern !== 0 ||
      profile !== null && (!exactKeys(profile, ['kind', 'version', 'sfxStart', 'sfxCount', 'volumeBoost']) ||
      profile.kind !== 'track-1-volume-boost' || profile.version !== 1 ||
      profile.sfxStart !== 1 || profile.sfxCount !== 4 || profile.volumeBoost !== 2) ||
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
  const kind = profile === null ? 0 : 1;
  bytes[14] = kind;
  bytes[15] = kind;
  putHeaderText(bytes, 16, 15, value.project.name);
  putHeaderText(bytes, 32, 23, value.source.provenance);
  bytes.set([0, kind, kind * 4], 56);
  bytes.set(bank, 64);
  put16(bytes, 10, crc16(bytes, 0, bytes.length, 10, 12));
  return checksumHex(get16(bytes, 10)) === value.checksum.envelope && envelopeValid(bytes) ? bytes : null;
}

function materializedBank(bytes) {
  if (!envelopeValid(bytes)) return null;
  const bank = bytes.slice(64);
  if (bytes[14] === 0) return bank;
  for (let sfx = 1; sfx <= 4; sfx++) {
    const base = 0x100 + sfx * 68;
    if (bank[base + 66] & 0x80) continue;
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

function storeExactRecord(
  storage, key, makeRecord, accept, expected, verifyRestore
) {
  let previous;
  try {
    previous = storage.getItem(key);
    if (expected !== undefined && previous !== expected) return 'changed';
    const candidate = makeRecord();
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

function storeLastKnownGood(bytes, storage = localStorage) {
  if (!envelopeValid(bytes)) return false;
  return storeExactRecord(storage, projectStoreKey, () => envelopeRecord(bytes),
    (raw) => sameBytes(parseEnvelopeRecord(raw), bytes), undefined, false) === 'stored';
}

function loadLastKnownGood(storage = localStorage) {
  try { return parseEnvelopeRecord(storage.getItem(projectStoreKey)); } catch (_) { return null; }
}

function emptyProjectLibrary() {
  return {format: 'pocket-tracker-library', version: 1, nextProject: 1, projects: []};
}

function envelopeValue(bytes) { return JSON.parse(envelopeRecord(bytes)); }

function parseEnvelopeValue(value) {
  if (!exactKeys(value, ['format', 'version', 'envelope'])) return null;
  return parseEnvelopeRecord(JSON.stringify(value));
}

function validLibraryId(value) {
  return Number.isInteger(value) && value > 0 && value <= 0x7fffffff;
}

function parseProjectLibrary(raw) {
  if (typeof raw !== 'string' || raw.length > projectLibraryMaxChars) return null;
  let value;
  try { value = JSON.parse(raw); } catch (_) { return null; }
  if (!exactKeys(value, ['format', 'version', 'nextProject', 'projects']) ||
      value.format !== 'pocket-tracker-library' || value.version !== 1 ||
      !validLibraryId(value.nextProject) || !Array.isArray(value.projects) ||
      value.projects.length > projectLibraryMaxProjects) return null;
  const projects = [];
  const projectIds = new Set();
  let maxProject = 0, previousProject = 0, recovered = false;
  for (const project of value.projects) {
    if (!exactKeys(project, ['id', 'nextRevision', 'revisions']) ||
        !validLibraryId(project.id) || projectIds.has(project.id) ||
        !validLibraryId(project.nextRevision) || !Array.isArray(project.revisions) ||
        project.revisions.length < 1 || project.revisions.length > projectLibraryMaxRevisions ||
        project.id <= previousProject) return null;
    projectIds.add(project.id);
    previousProject = project.id;
    maxProject = Math.max(maxProject, project.id);
    const revisions = [];
    const revisionIds = new Set();
    let maxRevision = 0, previousRevision = 0;
    for (const revision of project.revisions) {
      if (!exactKeys(revision, ['id', 'envelope']) || !validLibraryId(revision.id) ||
          revisionIds.has(revision.id) || revision.id <= previousRevision) return null;
      revisionIds.add(revision.id);
      previousRevision = revision.id;
      maxRevision = Math.max(maxRevision, revision.id);
      const bytes = parseEnvelopeValue(revision.envelope);
      if (bytes) revisions.push({id: revision.id, envelope: revision.envelope});
      else recovered = true;
    }
    if (project.nextRevision <= maxRevision) return null;
    if (revisions.length) projects.push({id: project.id, nextRevision: project.nextRevision, revisions});
    else recovered = true;
  }
  if (value.nextProject <= maxProject) return null;
  return {library: {format: value.format, version: value.version,
    nextProject: value.nextProject, projects}, recovered};
}

function projectLibraryRecord(library) { return JSON.stringify(library); }

function canonicalProjectLibraryRecord(raw) {
  const parsed = parseProjectLibrary(raw);
  return parsed && !parsed.recovered && projectLibraryRecord(parsed.library) === raw;
}

function loadProjectLibrary(storage = localStorage) {
  if (uncertainLibraryStorage.has(storage)) {
    return {state: 'uncertain', library: emptyProjectLibrary(), recovered: false, raw: null};
  }
  let raw;
  try { raw = storage.getItem(projectLibraryKey); } catch (_) {
    return {state: 'fault', library: emptyProjectLibrary(), recovered: false, raw: null};
  }
  if (raw === null || raw === undefined) {
    return {state: 'missing', library: emptyProjectLibrary(), recovered: false, raw: null};
  }
  const parsed = parseProjectLibrary(raw);
  return parsed ? {state: parsed.recovered ? 'recovered' : 'ready', ...parsed, raw} :
    {state: 'invalid', library: emptyProjectLibrary(), recovered: false, raw};
}

function storeProjectLibrary(library, storage = localStorage, expectedRaw) {
  if (projectTransferActive() || uncertainLibraryStorage.has(storage)) return false;
  const candidate = projectLibraryRecord(library);
  if (!canonicalProjectLibraryRecord(candidate)) return false;
  const state = storeExactRecord(storage, projectLibraryKey, () => candidate,
    canonicalProjectLibraryRecord, expectedRaw, true);
  if (state === 'uncertain') uncertainLibraryStorage.add(storage);
  return state === 'stored';
}

function migrateProjectLibrary(storage = localStorage) {
  const existing = loadProjectLibrary(storage);
  if (existing.state !== 'missing') return existing;
  const bytes = loadLastKnownGood(storage);
  if (!bytes) return existing;
  const library = emptyProjectLibrary();
  library.projects.push({id: 1, nextRevision: 2,
    revisions: [{id: 1, envelope: envelopeValue(bytes)}]});
  library.nextProject = 2;
  return storeProjectLibrary(library, storage, null) ?
    {state: 'migrated', library, recovered: false} :
    {state: 'fault', library: emptyProjectLibrary(), recovered: false};
}

function mutableProjectLibrary(storage) {
  const current = loadProjectLibrary(storage);
  if (current.state !== 'ready' && current.state !== 'missing') return null;
  return {library: JSON.parse(projectLibraryRecord(current.library)), raw: current.raw};
}

function lastKnownGoodSnapshot(storage) {
  try {
    const raw = storage.getItem(projectStoreKey);
    return {raw, bytes: parseEnvelopeRecord(raw)};
  } catch (_) { return {raw: null, bytes: null}; }
}

function addLibraryProject(storage = localStorage) {
  const slot = lastKnownGoodSnapshot(storage);
  const bytes = slot.bytes;
  const mutable = mutableProjectLibrary(storage);
  const library = mutable?.library;
  if (projectTransferActive() || !bytes || !library ||
      library.projects.length >= projectLibraryMaxProjects || !validLibraryId(library.nextProject + 1)) return false;
  const id = library.nextProject++;
  library.projects.push({id, nextRevision: 2, revisions: [{id: 1, envelope: envelopeValue(bytes)}]});
  try { if (storage.getItem(projectStoreKey) !== slot.raw) return false; } catch (_) { return false; }
  return storeProjectLibrary(library, storage, mutable.raw) ? id : false;
}

function addLibraryRevision(projectId, storage = localStorage, confirmAction = globalThis.confirm) {
  if (projectTransferActive()) return false;
  const slot = lastKnownGoodSnapshot(storage);
  const bytes = slot.bytes;
  const mutable = mutableProjectLibrary(storage);
  const library = mutable?.library;
  const project = library?.projects.find((item) => item.id === projectId);
  if (!bytes || !project || !validLibraryId(project.nextRevision + 1)) return false;
  const envelope = envelopeValue(bytes);
  const newest = project.revisions[project.revisions.length - 1];
  if (newest && newest.envelope.envelope === envelope.envelope) return 'duplicate';
  if (project.revisions.length === projectLibraryMaxRevisions) {
    const oldest = project.revisions[0];
    const message = `Save this revision and permanently evict ${libraryProjectName(project)} ` +
      `saved copy ${oldest.id}?`;
    if (typeof confirmAction !== 'function' || !confirmAction(message)) return 'cancelled';
    try {
      if (storage.getItem(projectLibraryKey) !== mutable.raw ||
          storage.getItem(projectStoreKey) !== slot.raw) return 'changed';
    } catch (_) { return false; }
  } else {
    try { if (storage.getItem(projectStoreKey) !== slot.raw) return 'changed'; } catch (_) { return false; }
  }
  const id = project.nextRevision++;
  project.revisions.push({id, envelope});
  if (project.revisions.length > projectLibraryMaxRevisions) project.revisions.shift();
  return storeProjectLibrary(library, storage, mutable.raw) ? id : false;
}

function stageLibraryRevision(projectId, revisionId, storage = localStorage) {
  if (projectTransferActive()) return false;
  const current = loadProjectLibrary(storage);
  const revision = current.library.projects.find((item) => item.id === projectId)?.revisions
    .find((item) => item.id === revisionId);
  const bytes = revision && parseEnvelopeValue(revision.envelope);
  return !!bytes && storeLastKnownGood(bytes, storage);
}

function deleteLibraryProject(projectId, storage = localStorage) {
  if (projectTransferActive()) return false;
  const mutable = mutableProjectLibrary(storage);
  const library = mutable?.library;
  const index = library?.projects.findIndex((item) => item.id === projectId) ?? -1;
  if (index < 0) return false;
  library.projects.splice(index, 1);
  return storeProjectLibrary(library, storage, mutable.raw);
}

function deleteLibraryRevision(projectId, revisionId, storage = localStorage) {
  if (projectTransferActive()) return false;
  const mutable = mutableProjectLibrary(storage);
  const library = mutable?.library;
  const projectIndex = library?.projects.findIndex((item) => item.id === projectId) ?? -1;
  if (projectIndex < 0) return false;
  const project = library.projects[projectIndex];
  const revisionIndex = project.revisions.findIndex((item) => item.id === revisionId);
  if (revisionIndex < 0) return false;
  project.revisions.splice(revisionIndex, 1);
  if (!project.revisions.length) library.projects.splice(projectIndex, 1);
  return storeProjectLibrary(library, storage, mutable.raw);
}

function confirmLibraryDelete(action, projectId, revisionId, storage = localStorage,
    confirmAction = globalThis.confirm) {
  if (action !== 'delete-project' && action !== 'delete-revision') return false;
  const current = loadProjectLibrary(storage);
  const project = current.state === 'ready' && current.library.projects
    .find((item) => item.id === projectId);
  const revision = project?.revisions.find((item) => item.id === revisionId);
  if (!project || action === 'delete-revision' && !revision) return false;
  let slotRaw;
  try {
    slotRaw = storage.getItem(projectStoreKey);
  } catch (_) { return false; }
  const message = action === 'delete-project' ?
    `Delete ${libraryProjectName(project)} project ${project.id} and every saved revision? ` +
      'The tracker and browser slot will not change.' :
    `Delete ${libraryProjectName(project)} saved copy ${revision.id}? ` +
      'The tracker and browser slot will not change.';
  if (typeof confirmAction !== 'function' || !confirmAction(message)) return 'cancelled';
  try {
    if (storage.getItem(projectLibraryKey) !== current.raw ||
        storage.getItem(projectStoreKey) !== slotRaw) return 'changed';
  } catch (_) { return false; }
  return action === 'delete-project' ? deleteLibraryProject(projectId, storage) :
    deleteLibraryRevision(projectId, revisionId, storage);
}

function libraryDeleteFeedback(result) {
  if (result === 'cancelled') return {message: 'Deletion cancelled. Nothing changed.', failed: false};
  if (result === 'changed') return {
    message: 'Project data changed before deletion. Nothing was deleted or overwritten.', failed: true,
  };
  return result ? {
    message: 'Deleted from the project library. The tracker and browser slot are unchanged.', failed: false,
  } : {message: 'Could not delete that item. Project data is unchanged.', failed: true};
}

function resetProjectLibrary(storage = localStorage, confirmAction = globalThis.confirm) {
  if (projectTransferActive() || uncertainLibraryStorage.has(storage)) return false;
  let snapshot;
  try { snapshot = storage.getItem(projectLibraryKey); } catch (_) { return false; }
  if (typeof confirmAction !== 'function' || !confirmAction(
    'Reset only the browser project library? The tracker and last-known-good browser slot will not change.')) {
    return 'cancelled';
  }
  try { if (storage.getItem(projectLibraryKey) !== snapshot) return 'changed'; } catch (_) { return false; }
  return storeProjectLibrary(emptyProjectLibrary(), storage, snapshot);
}

function libraryProjectName(project) {
  const bytes = parseEnvelopeValue(project.revisions[project.revisions.length - 1]?.envelope);
  return bytes ? headerText(bytes, 16, 15) || 'untitled' : 'unavailable';
}

function projectTransferActive() { return !!(projectSaveTransfer || projectLoadTransfer); }

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


function importProjectJson(raw, storage = localStorage) {
  const bytes = parseProjectJson(raw);
  return bytes !== null && storeLastKnownGood(bytes, storage);
}

function importProjectP8(raw, storage = localStorage, filename = '') {
  if (typeof raw !== 'string') return false;
  const lines = raw.replace(/\r\n?/g, '\n').split('\n');
  const sidecars = lines.filter((line) => line.includes('pocket-tracker-header'));
  const sectionValid = (name, complete) => {
    const starts = lines.reduce((found, line, index) => line === name ? [...found, index] : found, []);
    if (starts.length !== 1) return false;
    let count = 0;
    for (let i = starts[0] + 1; i < lines.length && !/^__[a-z0-9_]+__$/.test(lines[i]); i++) {
      if (lines[i] !== '') count++;
    }
    return complete ? count === 64 : count <= 64;
  };
  if (sidecars.length > 0 &&
      (sidecars.length !== 1 || !/^-- pocket-tracker-header: [0-9a-f]{128}$/.test(sidecars[0]))) return false;
  const authenticated = sidecars.length === 1;
  if (!sectionValid('__sfx__', authenticated) || !sectionValid('__music__', authenticated)) return false;
  const parsed = parseP8Audio(lines.join('\n'));
  if (!parsed || authenticated !== !!parsed.header) return false;
  const bytes = new Uint8Array(projectEnvelopeSize);
  if (authenticated) bytes.set(parsed.header);
  else {
    const basename = String(filename).replace(/^.*[\\/]/, '').replace(/\.p8$/i, '')
      .replace(/[^\x20-\x7e]/gu, '_');
    bytes.set([80, 84, 80, 50, 2, 64]);
    put16(bytes, 6, projectEnvelopeSize);
    putHeaderText(bytes, 16, 15, (basename || 'imported p8').slice(0, 15));
    putHeaderText(bytes, 32, 23, (basename || 'browser p8').slice(0, 23));
  }
  bytes.set(parsed.bank, 64);
  if (!authenticated) {
    put16(bytes, 8, crc16(parsed.bank));
    put16(bytes, 10, crc16(bytes, 0, bytes.length, 10, 12));
  }
  return envelopeValid(bytes) && storeLastKnownGood(bytes, storage) &&
    (authenticated || 'raw');
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

function setStatus(target, message, failed = false) {
  if (!target) return;
  target.textContent = message;
  target.style.color = failed ? '#ff8a8a' : '#c9c9de';
}

function selectedLibraryId(select) {
  const value = Number(select?.value);
  return validLibraryId(value) ? value : 0;
}

function addLibraryOption(select, value, text) {
  const option = document.createElement('option');
  option.value = String(value);
  option.textContent = text;
  select.appendChild(option);
}

function renderLibraryRevisions(project, preferredRevision = 0) {
  if (!libraryRevision) return;
  libraryRevision.replaceChildren();
  if (!project) {
    addLibraryOption(libraryRevision, 0, 'No revisions');
    libraryRevision.disabled = true;
    return;
  }
  libraryRevision.disabled = false;
  for (const revision of [...project.revisions].reverse()) {
    const bytes = parseEnvelopeValue(revision.envelope);
    addLibraryOption(libraryRevision, revision.id,
      `Revision ${get16(bytes, 12)} · saved copy ${revision.id}`);
  }
  if (project.revisions.some((item) => item.id === preferredRevision)) {
    libraryRevision.value = String(preferredRevision);
  }
}

function renderProjectLibrary(preferredProject = 0, preferredRevision = 0) {
  if (typeof libraryProject?.replaceChildren !== 'function' ||
      typeof libraryRevision?.replaceChildren !== 'function') return loadProjectLibrary();
  const current = loadProjectLibrary();
  libraryProject.replaceChildren();
  if (!current.library.projects.length) {
    addLibraryOption(libraryProject, 0, 'No saved projects');
    libraryProject.disabled = true;
    renderLibraryRevisions(null);
    return current;
  }
  libraryProject.disabled = false;
  for (const project of current.library.projects) {
    addLibraryOption(libraryProject, project.id, `${libraryProjectName(project)} · project ${project.id}`);
  }
  if (current.library.projects.some((item) => item.id === preferredProject)) {
    libraryProject.value = String(preferredProject);
  }
  const project = current.library.projects.find((item) => item.id === selectedLibraryId(libraryProject));
  renderLibraryRevisions(project, preferredRevision);
  return current;
}

function initializeProjectLibrary() {
  if (!projectLibraryPanel || typeof libraryProject?.replaceChildren !== 'function' ||
      typeof libraryRevision?.replaceChildren !== 'function') return;
  const initial = migrateProjectLibrary();
  renderProjectLibrary();
  if (initial.state === 'migrated') {
    setStatus(libraryStatus, 'Migrated the valid browser slot into project 1. The tracker is unchanged.');
  } else if (initial.state === 'recovered') {
    setStatus(libraryStatus, 'Recovered older valid revisions. Corrupt stored copies remain untouched.', true);
  } else if (initial.state === 'invalid') {
    setStatus(libraryStatus, 'The library record is invalid and was not changed. The browser slot is still available.', true);
  } else if (initial.state === 'fault') {
    setStatus(libraryStatus, 'Browser storage is unavailable. No project data was changed.', true);
  } else if (initial.state === 'uncertain') {
    setStatus(libraryStatus, 'Library storage integrity is uncertain. Reload before making changes.', true);
  }
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
  setStatus(fileStatus, ok ? 'Download created from the checksum-verified browser slot.' :
    'No valid browser slot. Save in the tracker first.', !ok);
});

libraryProject?.addEventListener('change', () => {
  const current = loadProjectLibrary();
  renderLibraryRevisions(current.library.projects.find(
    (item) => item.id === selectedLibraryId(libraryProject)));
});

projectLibraryPanel?.addEventListener('click', (event) => {
  const action = event.target.closest?.('[data-library-action]')?.dataset.libraryAction;
  if (!action) return;
  const projectId = selectedLibraryId(libraryProject);
  const revisionId = selectedLibraryId(libraryRevision);
  if (action === 'stage') {
    const ok = stageLibraryRevision(projectId, revisionId);
    setStatus(libraryStatus, ok ? 'Revision staged in the browser slot. Choose Load in the tracker to commit it.' :
      'Could not stage that revision. Library, browser slot, and tracker are unchanged.', !ok);
    return;
  }
  if (action === 'new') {
    const id = addLibraryProject();
    renderProjectLibrary(id || 0);
    setStatus(libraryStatus, id ? `Saved browser slot as project ${id}.` :
      'Could not add a project. Save in the tracker first, free a project slot, or check browser storage.', !id);
    return;
  }
  if (action === 'revision') {
    const id = addLibraryRevision(projectId);
    renderProjectLibrary(projectId, typeof id === 'number' ? id : revisionId);
    setStatus(libraryStatus, id === 'duplicate' ? 'The newest saved revision already matches the browser slot.' : id ?
      id === 'cancelled' ? 'Revision save cancelled. Nothing changed.' :
      id === 'changed' ? 'Project data changed before the save could commit. Nothing was overwritten.' :
      `Saved revision ${id}; only the newest ${projectLibraryMaxRevisions} copies are retained.` :
      'Could not add the revision. Browser storage and existing revisions are unchanged.', !id);
    return;
  }
  if (action === 'reset') {
    const result = resetProjectLibrary();
    renderProjectLibrary();
    setStatus(libraryStatus, result === 'cancelled' ? 'Library reset cancelled. Nothing changed.' :
      result === 'changed' ? 'Library data changed before reset. Nothing was overwritten.' : result ?
      'Browser project library reset. The tracker and last-known-good slot are unchanged.' :
      'Could not reset the browser library. Stored data is unchanged.', !result);
    return;
  }
  const result = confirmLibraryDelete(action, projectId, revisionId);
  if (result !== 'cancelled') renderProjectLibrary();
  const feedback = libraryDeleteFeedback(result);
  setStatus(libraryStatus, feedback.message, feedback.failed);
});

projectImport?.addEventListener('change', async () => {
  const file = projectImport.files?.[0];
  projectImport.value = '';
  if (!file) return;
  let raw;
  try { raw = await file.text(); } catch (_) {
    setStatus(fileStatus, 'Could not read that project file. The browser slot is unchanged.', true);
    return;
  }
  const p8 = /\.p8$/i.test(file.name);
  const ok = p8 ? importProjectP8(raw, localStorage, file.name) : importProjectJson(raw);
  setStatus(fileStatus, ok ? (ok === 'raw' ?
    'Imported audio sections as no profile; external Lua is not included. Choose Load in the tracker.' : p8 ?
    'Imported authored .p8. Choose Load in the tracker.' :
    'Imported to the browser slot. Choose Load in the tracker to commit it.') :
    'Invalid project file. The browser slot and live project are unchanged.', !ok);
});


initializeProjectLibrary();
watchProjectIO();
