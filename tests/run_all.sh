#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

PICO8_BIN=${PICO8_BIN:-/home/nick/Development/pico8/pico-8/pico8}
PLAYWRIGHT_MODULE=${PLAYWRIGHT_MODULE:-/home/nick/Development/crosscrosscross/node_modules/playwright}
export LC_ALL=C PICO8_BIN PLAYWRIGHT_MODULE

if [[ ! -x "$PICO8_BIN" ]]; then
  printf 'PICO-8 executable is unavailable: %s\n' "$PICO8_BIN" >&2
  exit 1
fi
if [[ ! -d "$PLAYWRIGHT_MODULE" ]]; then
  printf 'Playwright module is unavailable: %s\n' "$PLAYWRIGHT_MODULE" >&2
  exit 1
fi

head_before=$(git rev-parse HEAD)
printf 'immutable head: %s\n' "$head_before"

native_carts=(
  tests/hold_menus.p8
  tests/m1_bank.p8
  tests/m1_playback.p8
  tests/m1_track_1_fixture.p8
  tests/playback_transport.p8
  tests/project_io.p8
  tests/sfx_clipboard.p8
  tests/sfx_filters.p8
  tests/sfx_safety.p8
  tests/sfx_ui.p8
  tests/sfx_visual.p8
  tests/sfx_waveforms.p8
  tests/size_budget.p8
  tests/smoke.p8
  tests/song_ui.p8
)
expected_native_carts=(
  tests/hold_menus.p8
  tests/m1_bank.p8
  tests/m1_playback.p8
  tests/m1_track_1_fixture.p8
  tests/native_store.p8
  tests/playback_transport.p8
  tests/project_io.p8
  tests/sfx_clipboard.p8
  tests/sfx_filters.p8
  tests/sfx_safety.p8
  tests/sfx_timing.p8
  tests/sfx_ui.p8
  tests/sfx_visual.p8
  tests/sfx_waveforms.p8
  tests/size_budget.p8
  tests/smoke.p8
  tests/song_ui.p8
)
mapfile -t discovered_native_carts < <(printf '%s\n' tests/*.p8)
if [[ ${#discovered_native_carts[@]} -ne 17 ||
      "${discovered_native_carts[*]}" != "${expected_native_carts[*]}" ]]; then
  printf 'native-cart inventory differs from the exact 17-cart allowlist\n' >&2
  printf 'discovered: %s\n' "${discovered_native_carts[*]}" >&2
  exit 1
fi

for cart in "${native_carts[@]}"; do
  printf 'native cart (-x): %s\n' "$cart"
  timeout 60s env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
    "$PICO8_BIN" -x "$cart"
done

store_fixture=tests/fixtures/pocket-tracker-data-test.p8
if [[ -e "$store_fixture" ]]; then
  printf 'isolated data fixture already exists: %s\n' "$store_fixture" >&2
  exit 1
fi
timing_log=$(mktemp "${TMPDIR:-/tmp}/picodj-sfx-timing.XXXXXX")
cleanup() {
  rm -f "$store_fixture" "$timing_log"
}
trap cleanup EXIT

printf 'native cart (isolated data fixture): tests/native_store.p8\n'
cp pocket-tracker-data.p8 "$store_fixture"
timeout 90s env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  "$PICO8_BIN" -x tests/native_store.p8
rm -f "$store_fixture"

printf 'native cart (real mixer timing): tests/sfx_timing.p8\n'
set +e
env SDL_AUDIODRIVER=dummy timeout 15s xvfb-run -a \
  "$PICO8_BIN" -foreground_sleep_ms 16 -run tests/sfx_timing.p8 \
  >"$timing_log" 2>&1
timing_status=$?
set -e
cat "$timing_log"
if [[ $timing_status -ne 0 && $timing_status -ne 124 ]]; then
  printf 'timing cart exited unexpectedly: %s\n' "$timing_status" >&2
  exit "$timing_status"
fi
if grep -q 'fail:' "$timing_log"; then
  printf 'timing cart reported a failure\n' >&2
  exit 1
fi
if ! grep -q 'pocket tracker sfx timing: passed' "$timing_log"; then
  printf 'timing cart did not report its pass marker\n' >&2
  exit 1
fi
rm -f "$timing_log"

printf 'JavaScript syntax\n'
node --check mobile.js
node --check help.js

printf 'Node/browser suites\n'
node tests/mobile_hold.js
node tests/project_io.js
node tests/file_io.js
node tests/help_dialog.js
node tests/help_viewport.js

printf 'calibrated production token count\n'
node tests/measure_tokens.js

printf 'fresh deterministic browser export\n'
env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  "$PICO8_BIN" pocket-tracker.p8 -export tracker.html
git diff --exit-code -- tracker.html tracker.js

printf 'source, PXA, and generated-artifact budgets\n'
node tests/source_budget.js

head_after=$(git rev-parse HEAD)
if [[ "$head_after" != "$head_before" ]]; then
  printf 'HEAD moved during the suite: %s -> %s\n' "$head_before" "$head_after" >&2
  exit 1
fi
if [[ -n $(git status --porcelain) ]]; then
  printf 'worktree is not clean after the suite\n' >&2
  git status --short >&2
  exit 1
fi
printf 'full suite passed at clean immutable head %s\n' "$head_after"
