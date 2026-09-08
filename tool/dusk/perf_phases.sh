#!/usr/bin/env bash
#
# One perf session with layout and paint profiling on, for a frame that build
# attribution cannot explain.
#
# `perf.sh` runs with `phases: false`, which is the right default: phase detail
# multiplies the span volume and the build ranking is what answers most
# questions. It does not answer this one. `Zaman`'s average frame is 9 ms and
# its WORST is 420 to 560 ms in every run ever taken, and in every one of those
# envelopes the frame's own `blocks` map is empty while the adjacent one
# attributes 426 of 440 ms to `LAYOUT (root)`. Layout was never profiled, so the
# artefacts cannot say what that frame did.
#
# Deliberately one screen and one gesture. The point is a single expensive
# frame, not a survey, and phase spans at this scale are enough output to
# drown it.
#
# Usage: tool/dusk/perf_phases.sh [view] [scale] [width] [height] [output-dir]
#   view: `zaman` (default) or `simdi`

set -uo pipefail

FSA="./bin/fsa"
VIEW="${1:-zaman}"
SCALE="${2:-5000}"
W="${3:-1440}"
H="${4:-900}"
OUT="${5:-build/perf-phases}"

mkdir -p "$OUT"

ref_matching() {
  $FSA dusk:snap 2>/dev/null | rg -- "$1" | rg -o 'ref=e[0-9]+' | rg -o 'e[0-9]+' | head -1
}

$FSA stop >/dev/null 2>&1
pkill -f 'user-data-dir=/tmp/dusk-chrome-' 2>/dev/null
sleep 2

if ! $FSA start --device chrome --port 3210 --vm-service-port 8299 \
  --cdp-port 9322 --profile-static --timeout 400 \
  --flutter-arg="--dart-define=WATCHOOLS_SCALE=$SCALE" >/dev/null 2>&1; then
  printf 'fsa start failed; this needs an artisan carrying --flutter-arg.\n'
  exit 1
fi
sleep 18

$FSA dusk:resize --width "$W" --height "$H" >/dev/null 2>&1
sleep 2

if [ "$VIEW" = 'zaman' ]; then
  SWITCH="$(ref_matching '"Zaman görünümü"')"
  if [ -z "$SWITCH" ]; then
    printf 'no view switch on screen\n'
    exit 1
  fi
  $FSA dusk:tap --ref "$SWITCH" >/dev/null 2>&1
  sleep 3
fi

TARGET="$(ref_matching 'favorilere ekle')"
if [ -z "$TARGET" ]; then
  printf 'nothing to scroll on screen\n'
  exit 1
fi

$FSA dusk:perf_begin --phases >/dev/null 2>&1
for _ in 1 2 3 4 5 6 7 8; do
  $FSA dusk:scroll --ref "$TARGET" --direction down --pixels 700 >/dev/null 2>&1
done
$FSA dusk:perf_end --json >"$OUT/$VIEW-phases.json" 2>/dev/null

python3 - "$OUT/$VIEW-phases.json" <<'PY'
import json, sys

d = json.load(open(sys.argv[1]))
if d.get('refused'):
    print('REFUSED, liveness advanced', (d.get('liveness') or {}).get('advanced'))
    raise SystemExit(0)

f = d.get('frameSummary') or {}
print('worst build  %.1f ms' % (f.get('worst_frame_build_time_millis') or 0))
print('average      %.1f ms' % (f.get('average_frame_build_time_millis') or 0))
print('phases on:  ', d.get('phases'))
print()

# With phases on, LAYOUT and PAINT spans join the ranking. Their COUNTS are the
# readable part; the micros are nested and rank by tree depth.
print(f'{"span":<32} {"count":>8}')
for b in (d.get('blockAttribution') or [])[:18]:
    print(f'{b.get("name", "?"):<32} {b.get("count", 0):>8}')
PY
