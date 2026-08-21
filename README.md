# Pocket Tracker

A standalone PICO-8 music sketchpad designed for handheld and mobile use. It
provides four channels, sixteen steps, per-channel waveform, volume, and
effect, three persistent song slots, live playback, and browser exports.

## Controls

- D-pad: move around the pattern; Down from step 16 opens the action menu.
- Tap O: raise the selected note. Tap X: lower it.
- Hold O: open the Start palette for playback, save/load, and export.
- Hold X: open the Select palette for the current step/channel parameters.
  Use Up/Down to choose, Left/Right to adjust, O to use, and X to close.
- O+X: toggle the selected step between a note and a rest.
- In the action menu, Left/Right chooses an action, O performs its primary
  action, X performs the alternate action, and Up returns to the pattern.
- On EXPORT, O downloads the exact JSON project and X downloads a WAV preview.

The action menu contains playback, save/load, slot, tempo, waveform, volume,
and export controls. Waveform/volume changes apply to the currently selected
channel.

## Browser exports

The mobile wrapper reads one-shot export requests from the cart over GPIO and
downloads directly, with no additional HTML controls:

- JSON containing the exact notes, tempo, waveform, volume, and effect data.
- A rendered WAV preview suitable for sharing or dropping into a DAW.

The WAV renderer approximates PICO-8's eight waveform families; the JSON is
the lossless project export.

## Build and test

PICO-8 must be installed separately. From this directory:

```sh
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy /path/to/pico8 \
  pocket-tracker.p8 -export tracker.html

timeout 6s env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  /path/to/pico8 -run tests/smoke.p8
```

`tracker.html` and `tracker.js` are generated. `tracker.lua` is the gameplay
source of truth; `index.html` and `mobile.js` bridge the cart's export actions
to browser downloads.
