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

watchExports();
