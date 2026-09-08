#!/usr/bin/env bash
#
# Frame measurement for the browse screens at provider scale.
#
# The hand-written fixtures are 23 channels and 15 titles, which is the right
# size for judging a design and useless for judging a frame: every lazy-list
# question this app has is invisible below about a thousand rows. So this drives
# the app against the generated fixture (see `lib/app/support/fixture_scale.dart`)
# and reports what Flutter's own build profiling saw.
#
# What to believe in the output, in order.
#
# The BUILD COUNTS are the instrument. They were byte-identical across a debug
# run and a profile run of the same code, and they move only when the widget
# tree does, which is the definition of a signal here.
#
# The MILLISECONDS are not. Run to run variance on this machine exceeded the
# effect size of every change measured so far, in both directions: one change
# read as a 60% regression in debug and a 20% improvement in profile with
# identical build counts on both sides. Quote them for a rough order of
# magnitude and never for a delta.
#
# The BLOCK ATTRIBUTION micros are worse than not useful and are not printed.
# They are nested, so a parent's span contains its children's: on one frame the
# blocks summed to twenty one times the frame's own build time. Its counts are
# fine and are what the report shows.
#
# Nothing here is a device number. Run against a profile build
# (`fsa start --profile-static`) for the closest thing, and note even that
# carries dusk, telescope and `debugProfileBuildsEnabled`, which
# `dusk:perf_end`'s own note says costs time significant to what it measures.
#
# Three properties of the harness that are load-bearing.
#
# Every session drives an interaction, because `dusk:perf_end` refuses a session
# whose liveness counter did not advance: Flutter schedules a frame only when
# something is dirty, so a session that opens, sleeps and closes draws nothing
# and a zero report would read as "fast".
#
# This script starts the app itself, and that is not a convenience. The scale
# is a compile-time define, so an app somebody started by hand carries the 23
# channel fixture and every session then measures the wrong thing and reports it
# as fast. Owning the launch is the only way the number in the output and the
# number on the command line cannot disagree.
#
# Every group starts from a hot restart. The controllers are singletons and a
# search term survives `dusk:navigate`, so a typing session left the line-up
# filtered to one channel and every session after it measured an empty screen.
#
# That hot restart also means DO NOT EDIT lib/ WHILE THIS IS RUNNING. Flutter
# web serves this through DDC, so a restart recompiles, and a source change made
# after `boot()` silently reaches every group after the next `reset_to`. Two
# runs were lost that way: the first reported an exception from code that had
# not been compiled when the run started, and the second produced the same
# catalogue counts as a later run of different code. One of them also read as a
# clean result for a version that still had the fault. Let the run finish.
#
# The generated fixture carries no network URLs. It used to point at
# `picsum.photos`, so every session raced hundreds of live fetches and decodes
# against the frames it was timing; `scale_fixture.dart` records the swap. The
# cost is that this harness cannot measure image memory, which needs its own.
#
# Needs `--flutter-arg`, which `fsa start` gained in `fluttersdk/artisan#53`. On
# an older artisan the launch fails with `Could not find an option named
# "--flutter-arg"` rather than quietly measuring the small fixture.
#
# Leaves the app running, in profile mode, so a screenshot or a follow-up
# session can use it. `./bin/fsa stop` when done.
#
# Usage: tool/dusk/perf.sh [scale] [width] [height] [output-dir]

set -uo pipefail

FSA="./bin/fsa"
SCALE="${1:-5000}"
W="${2:-1440}"
H="${3:-900}"
OUT="${4:-build/perf}"

mkdir -p "$OUT"

log() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# A session that could not run is a hole in the comparison, not a footnote.
#
# The first version printed a skip line and carried on, so one run produced a
# `now-strip.json` and the next did not, and the before-and-after table silently
# compared seven sessions against eight. Every skip now counts, and the script
# exits non-zero at the end so a truncated run cannot be read as a complete one.
SKIPPED=0
skip() {
  SKIPPED=$((SKIPPED + 1))
  printf '  \033[31m%-26s SKIPPED, %s\033[0m\n' "$1" "$2"
}

# Prints the ref of the first node whose snapshot line matches $1.
ref_matching() {
  $FSA dusk:snap 2>/dev/null | rg -- "$1" | rg -o 'ref=e[0-9]+' | rg -o 'e[0-9]+' | head -1
}

# Returns the app to a clean, unfiltered state at [route].
#
# A restart rather than clearing the field, for the reason `tool/dusk/_lib.sh`
# records at length: nothing can clear a controlled `WInput` from outside on
# Flutter web.
reset_to() {
  $FSA dusk:navigate --route "$1" >/dev/null 2>&1
  sleep 2
  $FSA hot-restart >/dev/null 2>&1
  sleep 16
  $FSA dusk:resize --width "$W" --height "$H" >/dev/null 2>&1
  sleep 2
}

# Boots the app in profile mode carrying the scale define.
#
# Profile rather than debug because a debug build's milliseconds rank causes and
# do not describe a device, and because `FixtureScale` gates on `kReleaseMode`
# precisely so a profile run still gets the generated fixture.
boot() {
  $FSA stop >/dev/null 2>&1
  pkill -f 'user-data-dir=/tmp/dusk-chrome-' 2>/dev/null
  sleep 2

  if ! $FSA start --device chrome --port 3210 --vm-service-port 8299 \
    --cdp-port 9322 --profile-static --timeout 400 \
    --flutter-arg="--dart-define=WATCHOOLS_SCALE=$SCALE" >/dev/null 2>&1; then
    printf '\033[31mfsa start failed. An artisan without --flutter-arg cannot carry the scale;\n'
    printf 'this needs fluttersdk/artisan#53 or later.\033[0m\n'
    exit 1
  fi
  sleep 18
}

# Closes a session and prints the numbers that matter, or the refusal.
#
# Flutter's own metric names are kept rather than renamed. A report that invents
# vocabulary cannot be checked against the framework, and these are the keys
# `frameSummary` actually ships.
report() {
  local label="$1" file="$OUT/$2.json"
  $FSA dusk:perf_end --json >"$file" 2>/dev/null

  python3 - "$label" "$file" <<'PY'
import json, sys

label, path = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(path))
except Exception as exc:
    print(f'  {label:<26} unreadable response ({exc})')
    raise SystemExit(0)

# The refusal is the first thing to read. A session whose liveness counter did
# not advance rendered nothing, and every metric under it would be a zero that
# reads as speed.
if d.get('refused'):
    live = d.get('liveness') or {}
    print(f'  {label:<26} REFUSED, liveness advanced {live.get("advanced")}')
    raise SystemExit(0)

f = d.get('frameSummary') or {}
cov = d.get('coverage') or {}
wind = d.get('wind') or {}


def ms(key):
    v = f.get(key)
    return '  -   ' if not isinstance(v, (int, float)) else f'{v:6.1f}'


print(
    f'  {label:<26}'
    f' build avg {ms("average_frame_build_time_millis")}'
    f' p90 {ms("90th_percentile_frame_build_time_millis")}'
    f' worst {ms("worst_frame_build_time_millis")}'
    f' raster {ms("average_frame_rasterizer_time_millis")}'
    f' missed {f.get("missed_frame_build_budget_count", 0):>3}'
    f' / {cov.get("framesDrawn", 0):>3} frames'
)
print(
    f'      wind: {wind.get("wDivBuilds", 0)} WDiv, {wind.get("wTextBuilds", 0)} WText,'
    f' cache {wind.get("cacheHits", 0)} hit / {wind.get("cacheMisses", 0)} miss'
)

# Counts, ranked by count, and no milliseconds.
#
# `blockAttribution` micros are NESTED durations: on one frame of
# `build/perf-before/now-vertical.json` the frame's own `buildMicros` is 102800
# while its blocks sum to 2,206,000, twenty one times more. A parent's span
# contains its children's, so ranking by micros ranks by tree depth and reads
# like an attribution. The counts do not have that problem, and a count that
# goes to zero is the only unambiguous evidence this harness has produced.
blocks = sorted(
    (d.get('blockAttribution') or []),
    key=lambda b: b.get('count') or 0,
    reverse=True,
)
for b in blocks[:5]:
    print(f'      {b.get("name", "?"):<24} {b.get("count", 0):>6} builds')
PY
}

printf '\033[1mPerformance walk at scale=%s, %sx%s, artefacts in %s\033[0m\n' "$SCALE" "$W" "$H" "$OUT"
boot

# ---------------------------------------------------------------------------
log 'Şimdi: the live hero over editorial rails'
# ---------------------------------------------------------------------------
reset_to '/'
$FSA dusk:snap 2>/dev/null | rg -o '[0-9]+ kanal · [0-9]+ kanalda akış yok' | head -1

# Vertical, through the rails. The ref is the HERO's play button, and choosing
# it took two tries. `dusk:scroll` walks up to the nearest Scrollable, so a card
# would have scrolled its own rail and been reported as a vertical session; a
# section heading is outside every rail and would have been right, except that a
# heading is a `text` node and text nodes carry no ref, so the lookup silently
# returned nothing and the session was skipped with a message that read like an
# empty screen. The hero's button is outside the rails AND carries a ref.
HEAD="$(ref_matching ' izle"')"
if [ -z "$HEAD" ]; then
  skip 'vertical through rails' 'no hero button on screen'
else
  $FSA dusk:perf_begin >/dev/null 2>&1
  for _ in 1 2 3 4 5 6 7 8; do
    $FSA dusk:scroll --ref "$HEAD" --direction down --pixels 700 >/dev/null 2>&1
  done
  report 'vertical through rails' 'now-vertical'
fi

# Horizontal, inside one rail: does a rail load its cards as it is pushed right,
# or were they all built up front. A rail at this scale holds hundreds.
CARD="$(ref_matching 'favorilere ekle')"
if [ -z "$CARD" ]; then
  skip 'horizontal inside a rail' 'no card on screen'
else
  $FSA dusk:perf_begin >/dev/null 2>&1
  for _ in 1 2 3 4 5 6 7 8; do
    $FSA dusk:scroll --ref "$CARD" --direction right --pixels 900 >/dev/null 2>&1
  done
  report 'horizontal inside a rail' 'now-horizontal'
fi

# The category strip at hundreds of groups, and it needs its own clean screen
# for the same reason the typing session does. The strip sits between the hero
# and the rails, so the vertical session above scrolls it out of the semantics
# tree: this session was skipped on every run, and before the skip counter
# existed it was skipped SILENTLY, which is how one run produced a
# `now-strip.json` and the next did not while both reported success.
reset_to '/'
STRIP="$(ref_matching 'kategorisi')"
if [ -z "$STRIP" ]; then
  skip 'category strip sideways' 'no category chip on screen'
else
  $FSA dusk:perf_begin >/dev/null 2>&1
  for _ in 1 2 3 4 5 6; do
    $FSA dusk:scroll --ref "$STRIP" --direction right --pixels 800 >/dev/null 2>&1
  done
  report 'category strip sideways' 'now-strip'
fi

# Typing gets its own clean screen. On this layout the search field lives in the
# hero, so the vertical session above scrolls it out of the semantics tree
# entirely: the first version measured one frame and refused, which reads as an
# app that did nothing rather than as a harness aiming at a control that was no
# longer there.
#
# Every keystroke drops the frame caches, re-filters the whole line-up and
# rebuilds the category strip with it.
reset_to '/'
$FSA dusk:perf_begin >/dev/null 2>&1
for term in A An And Anad Anado Anadol Anadolu; do
  SREF="$($FSA dusk:snap 2>/dev/null | rg '^\s*-?\s*textbox' | rg -o 'ref=e[0-9]+' | rg -o 'e[0-9]+' | head -1)"
  [ -n "$SREF" ] && $FSA dusk:fill --ref "$SREF" --text "$term" >/dev/null 2>&1
done
report 'typing seven keystrokes' 'now-typing'

# ---------------------------------------------------------------------------
log 'Zaman: the broadcast grid'
# ---------------------------------------------------------------------------
reset_to '/'

SWITCH="$(ref_matching '"Zaman görünümü"')"
if [ -z "$SWITCH" ]; then
  skip 'grid sessions' 'no view switch on screen'
else
  $FSA dusk:tap --ref "$SWITCH" >/dev/null 2>&1
  sleep 3

  ROW="$(ref_matching 'favorilere ekle')"
  if [ -n "$ROW" ]; then
    $FSA dusk:perf_begin >/dev/null 2>&1
    for _ in 1 2 3 4 5 6 7 8; do
      $FSA dusk:scroll --ref "$ROW" --direction down --pixels 700 >/dev/null 2>&1
    done
    report 'grid vertical' 'time-vertical'

    BLOCK="$(ref_matching ' - [0-9][0-9]:[0-9][0-9]"')"
    [ -z "$BLOCK" ] && BLOCK="$ROW"
    $FSA dusk:perf_begin >/dev/null 2>&1
    for _ in 1 2 3 4 5 6; do
      $FSA dusk:scroll --ref "$BLOCK" --direction right --pixels 900 >/dev/null 2>&1
    done
    report 'grid horizontal' 'time-horizontal'
  fi
fi

# ---------------------------------------------------------------------------
log 'Vitrin: the catalogue'
# ---------------------------------------------------------------------------
reset_to '/kutuphane'
$FSA dusk:snap 2>/dev/null | rg -o '[0-9]+ başlık · [0-9]+ başlıkta afiş yok' | head -1

CHEAD="$(ref_matching 'detayı"')"
if [ -z "$CHEAD" ]; then
  skip 'catalogue vertical' 'no hero button on screen'
else
  $FSA dusk:perf_begin >/dev/null 2>&1
  for _ in 1 2 3 4 5 6 7 8; do
    $FSA dusk:scroll --ref "$CHEAD" --direction down --pixels 700 >/dev/null 2>&1
  done
  report 'catalogue vertical' 'library-vertical'
fi

CCARD="$(ref_matching 'favorilere ekle')"
if [ -n "$CCARD" ]; then
  $FSA dusk:perf_begin >/dev/null 2>&1
  for _ in 1 2 3 4 5 6 7 8; do
    $FSA dusk:scroll --ref "$CCARD" --direction right --pixels 900 >/dev/null 2>&1
  done
  report 'catalogue horizontal' 'library-horizontal'
fi

reset_to '/kutuphane'
$FSA dusk:perf_begin >/dev/null 2>&1
for term in A An And Anad Anado Anadol Anadolu; do
  SREF="$($FSA dusk:snap 2>/dev/null | rg '^\s*-?\s*textbox' | rg -o 'ref=e[0-9]+' | rg -o 'e[0-9]+' | head -1)"
  [ -n "$SREF" ] && $FSA dusk:fill --ref "$SREF" --text "$term" >/dev/null 2>&1
done
report 'catalogue typing' 'library-typing'

printf '\n'
$FSA dusk:exceptions 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    print("exceptions: unreadable response"); raise SystemExit(0)
# The initial-route message is magic'"'"'s loading placeholder having no route
# table, recorded as a known defect; it fires on every restart this script does.
entries = [e for e in (d.get("exceptions") or [])
           if "Could not navigate to initial route" not in (e.get("message") or "")]
print(f"exceptions during the walk: {len(entries)}")
for e in entries[:5]:
    print("  " + (e.get("message") or "").splitlines()[0][:160])
'

if [ "$SKIPPED" -ne 0 ]; then
  printf '\n\033[31m%s session(s) skipped, so this run is not comparable to a complete one\033[0m\n' "$SKIPPED"
  exit 1
fi
