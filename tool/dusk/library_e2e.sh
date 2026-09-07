#!/usr/bin/env bash
#
# Dusk end-to-end walk of the catalogue screen.
#
# The same contract as the line-up walk, plus the two things a VOD library has
# that a channel list does not: a scope switch between films and series, and a
# series that has to open on the episode the viewer left off at rather than on
# season one. Both are asserted on a phone and on a desktop.
#
# Requires an app started with CDP so the viewport can be resized:
#   ./bin/fsa start --device chrome --port 3210 --vm-service-port 8299 \
#     --cdp-port 9322 --timeout 240
#
# Usage: tool/dusk/library_e2e.sh [output-dir]

set -uo pipefail

FSA="./bin/fsa"
OUT="${1:-build/e2e-library}"
ROUTE="/kutuphane"
FAILURES=0
CHECKS=0
SEEN_EXCEPTIONS=0

mkdir -p "$OUT"

log()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
pass() { CHECKS=$((CHECKS + 1)); printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { CHECKS=$((CHECKS + 1)); FAILURES=$((FAILURES + 1)); printf '  \033[31m✗\033[0m %s\n' "$*"; }

# expect_in_file <file> [rg-flag...] <pattern> <description>
expect_in_file() {
  local file="$1"; shift
  local desc="${@: -1}"
  set -- "${@:1:$(($# - 1))}"
  if rg -q "$@" -- "$file"; then pass "$desc"; else fail "$desc"; fi
}

refute_in_file() {
  if rg -q -- "$2" "$1"; then fail "$3"; else pass "$3"; fi
}

# Known-benign, and the reason it is filtered rather than fixed: Flutter's
# `WidgetsApp` resolves an initial route before go_router has a chance to, so a
# restart whose browser URL is not `/` logs "Could not navigate to initial
# route" for a path the app does in fact serve. go_router then routes it
# correctly, which every later assertion in this walk confirms.
BENIGN='Could not navigate to initial route'

expect_no_exceptions() {
  local body count
  body="$($FSA dusk:exceptions 2>/dev/null | rg -v -- "$BENIGN")"
  # Counted on `"fatal":`, which every exception entry carries and the
  # response envelope does not. Counting `"type":` matched the envelope's own
  # `"type":"Response"` and reported one exception on an empty list.
  count="$(printf '%s' "$body" | rg -o '"fatal":' | wc -l | tr -d ' ')"
  count="${count:-0}"

  if [ "$count" -le "$SEEN_EXCEPTIONS" ]; then
    pass "no new exceptions: $1"
  else
    fail "$((count - SEEN_EXCEPTIONS)) new exception(s) after $1: $body"
    SEEN_EXCEPTIONS="$count"
  fi
}

# See tool/dusk/lineup_e2e.sh for why state is reset by restarting rather than
# by clearing the search field: on Flutter web nothing else reaches the app.
reset_app() {
  $FSA hot-restart >/dev/null 2>&1
  sleep 12
  $FSA dusk:resize --width "$1" --height "$2" >/dev/null 2>&1
  sleep 2
  $FSA dusk:navigate --route "$ROUTE" >/dev/null 2>&1
  sleep 3

  if [ -z "$($FSA dusk:snap 2>/dev/null | rg -o 'ref=e[0-9]+' | head -1)" ]; then
    printf '  \033[33m!\033[0m renderer gone, relaunching\n'
    $FSA stop >/dev/null 2>&1
    sleep 2
    $FSA start --device chrome --port 3210 --vm-service-port 8299 \
      --cdp-port 9322 --timeout 240 >/dev/null 2>&1
    sleep 20
    $FSA dusk:resize --width "$1" --height "$2" >/dev/null 2>&1
    sleep 2
    $FSA dusk:navigate --route "$ROUTE" >/dev/null 2>&1
    sleep 3
  fi

  SEEN_EXCEPTIONS=0
}

# Prints the ref of the first node whose line matches $1.
ref_matching() {
  $FSA dusk:snap 2>/dev/null | rg -- "$1" | rg -o 'ref=e[0-9]+' | rg -o 'e[0-9]+' | head -1
}

walk_layout() {
  local label="$1" profile="$2" width="$3" height="$4"
  local slug snap ref
  slug="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')-$profile"

  log "$label @ $profile ${width}x${height}"

  reset_app "$width" "$height"

  ref="$(ref_matching "\"$label: ")"
  if [ -z "$ref" ]; then
    fail "$label: switcher button not found in the semantics tree"
    return
  fi
  $FSA dusk:tap --ref "$ref" >/dev/null 2>&1
  sleep 2
  expect_no_exceptions "$label switch"

  snap="$OUT/$slug.snap.yaml"
  $FSA dusk:snap >"$snap" 2>/dev/null
  $FSA dusk:screenshot --output "$OUT/$slug.png" >/dev/null 2>&1

  expect_in_file "$snap" 'textbox' "$label: has a search field"
  expect_in_file "$snap" 'favorilere ekle|favorilerden çıkar' "$label: has a favourite control"
  # A title the provider sent no artwork for still names itself somewhere.
  expect_in_file "$snap" 'afiş yok' "$label: names the missing-artwork case"
  refute_in_file "$snap" 'OVERFLOW' "$label: no overflow marker"

  # Favourite, before search, because search cannot be undone from here.
  local starref
  starref="$(ref_matching 'favorilere ekle')"
  if [ -z "$starref" ]; then
    fail "$label: no unstarred favourite control to toggle"
  else
    $FSA dusk:tap --ref "$starref" >/dev/null 2>&1
    sleep 2
    expect_no_exceptions "$label favourite toggle"
    $FSA dusk:snap >"$OUT/$slug.starred.yaml" 2>/dev/null
    expect_in_file "$OUT/$slug.starred.yaml" 'favorilerden çıkar' "$label: starring flips the control"
  fi

  # The scope switch is the thing a catalogue has and a channel list does not.
  local seriesref
  seriesref="$(ref_matching '"Diziler göster"')"
  if [ -z "$seriesref" ]; then
    fail "$label: no series scope switch"
  else
    $FSA dusk:tap --ref "$seriesref" >/dev/null 2>&1
    sleep 2
    expect_no_exceptions "$label series scope"
    $FSA dusk:snap >"$OUT/$slug.series.yaml" 2>/dev/null
    $FSA dusk:screenshot --output "$OUT/$slug.series.png" >/dev/null 2>&1
    # Series only means no films, and the fixture's films are the check.
    refute_in_file "$OUT/$slug.series.yaml" 'Sessiz Şehir' "$label: series scope excludes films"

    # The resume point. `Bozkır Hattı` is finished through S02B01 and part way
    # into S02B02, so the play button has exactly one right answer and season
    # two is the one that must be open.
    local seriesitem
    seriesitem="$(ref_matching '"Bozkır Hattı [0-9]')"
    if [ -z "$seriesitem" ]; then
      fail "$label: the fixture series is not reachable in series scope"
    else
      $FSA dusk:tap --ref "$seriesitem" >/dev/null 2>&1
      sleep 2
      expect_no_exceptions "$label series select"
      $FSA dusk:snap >"$OUT/$slug.detail.yaml" 2>/dev/null
      $FSA dusk:screenshot --output "$OUT/$slug.detail.png" >/dev/null 2>&1
      expect_in_file "$OUT/$slug.detail.yaml" 'S02B02 oynat' "$label: resumes at the right episode"
      expect_in_file "$OUT/$slug.detail.yaml" 'S02B01' "$label: opens the season the resume point is in"
    fi

    # Back out of the detail if the layout opened one. The library chrome only
    # exists on the library, which is correct, so the walk has to leave.
    local backref
    backref="$(ref_matching 'Kütüphaneye dön')"
    if [ -n "$backref" ]; then
      $FSA dusk:tap --ref "$backref" >/dev/null 2>&1
      sleep 2
      expect_no_exceptions "$label detail dismiss"
    fi

    local allref
    allref="$(ref_matching '"Tümü göster"')"
    if [ -z "$allref" ]; then
      fail "$label: no way back to the whole catalogue"
    else
      $FSA dusk:tap --ref "$allref" >/dev/null 2>&1
      sleep 2
      expect_no_exceptions "$label scope reset"
      $FSA dusk:snap >"$OUT/$slug.allscope.yaml" 2>/dev/null
      expect_in_file "$OUT/$slug.allscope.yaml" '15 başlık' "$label: Tümü restores the whole catalogue"
    fi
  fi

  # Search, last, because it is one-way.
  local sref
  sref="$($FSA dusk:snap 2>/dev/null | rg '^\s*-?\s*textbox' | rg -o 'ref=e[0-9]+' | rg -o 'e[0-9]+' | head -1)"
  if [ -z "$sref" ]; then
    fail "$label: search field has no usable ref"
  else
    # An episode title, not a film title: a catalogue search that only covers
    # the top level cannot find the thing people actually remember.
    $FSA dusk:fill --ref "$sref" --text 'Sınır' >/dev/null 2>&1
    sleep 2
    expect_no_exceptions "$label episode search"
    $FSA dusk:snap >"$OUT/$slug.search.yaml" 2>/dev/null
    $FSA dusk:screenshot --output "$OUT/$slug.search.png" >/dev/null 2>&1
    expect_in_file "$OUT/$slug.search.yaml" 'Bozkır Hattı' "$label: search reaches episode titles"

    $FSA dusk:fill --ref "$sref" --text 'zzzzzz' >/dev/null 2>&1
    sleep 2
    expect_no_exceptions "$label empty search"
    $FSA dusk:snap >"$OUT/$slug.empty.yaml" 2>/dev/null
    $FSA dusk:screenshot --output "$OUT/$slug.empty.png" >/dev/null 2>&1
    expect_in_file "$OUT/$slug.empty.yaml" 'Sonuç yok' "$label: empty search has an empty state"
  fi
}

log "Dusk catalogue walk, artefacts in $OUT"
$FSA dusk:reset_overlays >/dev/null 2>&1

for profile in "desktop 1440 900" "mobile 414 896"; do
  # shellcheck disable=SC2086
  set -- $profile
  for label in Duvar Defter Sergi; do
    walk_layout "$label" "$1" "$2" "$3"
  done
done

printf '\n'
if [ "$FAILURES" -eq 0 ]; then
  printf '\033[32m%s/%s checks passed\033[0m\n' "$CHECKS" "$CHECKS"
else
  printf '\033[31m%s of %s checks failed\033[0m\n' "$FAILURES" "$CHECKS"
fi
exit $((FAILURES > 0 ? 1 : 0))
