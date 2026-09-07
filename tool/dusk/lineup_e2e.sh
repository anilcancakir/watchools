#!/usr/bin/env bash
#
# Dusk end-to-end walk of the line-up screen.
#
# Every browse layout has to carry the same three capabilities, on a phone and
# on a desktop: search the whole line-up, star a channel, and say something
# useful about a channel the provider sent no EPG for. This script asserts all
# three on all of them at both widths, and fails on the first app exception.
#
# It drives the app through dusk rather than a browser automation library, so
# what it exercises is the running Flutter tree and the same semantics labels a
# screen reader would read. That means a missing `semanticLabel` fails here.
#
# Requires an app started with CDP so the viewport can be resized:
#   ./bin/fsa start --device chrome --port 3210 --vm-service-port 8299 \
#     --cdp-port 9322 --timeout 240
#
# Usage: tool/dusk/lineup_e2e.sh [output-dir]

set -uo pipefail

FSA="./bin/fsa"
OUT="${1:-build/e2e}"
FAILURES=0
CHECKS=0

mkdir -p "$OUT"

log()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
pass() { CHECKS=$((CHECKS + 1)); printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { CHECKS=$((CHECKS + 1)); FAILURES=$((FAILURES + 1)); printf '  \033[31m✗\033[0m %s\n' "$*"; }

# Asserts that a pattern appears in a file. Called as
# `expect_in_file <file> [rg-flag...] <pattern> <description>`.
expect_in_file() {
  local file="$1"; shift
  local desc="${@: -1}"
  set -- "${@:1:$(($# - 1))}"
  if rg -q "$@" -- "$file"; then pass "$desc"; else fail "$desc"; fi
}

# Asserts that $2 does NOT appear in the file $1.
refute_in_file() {
  if rg -q -- "$2" "$1"; then fail "$3"; else pass "$3"; fi
}

# Running total of exceptions already accounted for.
#
# `dusk:exceptions` returns the app's whole accumulated list and there is no
# command to clear it, so a bare "count is zero" assertion fails for the rest of
# the run once anything throws once. Comparing against the last seen count
# attributes each new exception to the interaction that caused it.
SEEN_EXCEPTIONS=0

# Fails when the interaction added an exception. Called after every interaction
# because an exception thrown during a rebuild does not stop the app: the frame
# renders with a red box or a missing subtree and every later assertion passes
# against a broken screen.
# Known-benign, and the reason it is filtered rather than fixed: Flutter's
# `WidgetsApp` resolves an initial route before go_router has a chance to, so a
# restart whose browser URL is not `/` logs "Could not navigate to initial
# route" for a path the app does in fact serve. go_router then routes it
# correctly, which every later assertion here confirms.
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

# Prints the e<N> ref of the switcher button whose label starts with $1.
switcher_ref() {
  $FSA dusk:snap 2>/dev/null | rg -o "\"$1: [^\"]*\" \[ref=e[0-9]+\]" | rg -o 'e[0-9]+' | head -1
}

# Prints the e<N> ref of the first text field on screen.
#
# Matches any textbox rather than one placeholder: the four layouts word their
# search field differently on purpose, and an assertion that only knows one
# wording reports a missing field where the field is simply named something
# else. That false negative cost a whole run.
search_ref() {
  $FSA dusk:snap 2>/dev/null | rg '^\s*-?\s*textbox' | rg -o 'ref=e[0-9]+' | rg -o 'e[0-9]+' | head -1
}

# Returns the app to first-run state.
#
# A hot restart, not a cleared search field, and this is the one place where the
# obvious approach does not work at all. On Flutter web:
#
#   * `dusk:clear` empties the widget's own editing value without dispatching a
#     change, so a controlled `WInput` never tells the app, and the field reads
#     empty while `controller.query` still holds the old term.
#   * `dusk:fill --text ''` clears through the same non-notifying path.
#   * `dusk:press_key --key Backspace` has no effect on text at all: a
#     synthesised hardware key does not drive `EditableText` on web, where
#     editing arrives through the browser's composition path.
#   * `artisan tinker`, which could just call `search('')` on the controller,
#     is unavailable here: the `--cdp-port` branch runs `-d web-server`, and
#     DWDS's `WebSocketProxyService` does not implement the VM Service
#     `evaluate` RPC.
#
# So state is reset by dropping it. Each layout starting from a restart also
# means one failing case cannot cascade into the next, which is worth the
# twelve seconds on its own.
reset_app() {
  $FSA hot-restart >/dev/null 2>&1
  sleep 12
  $FSA dusk:resize --width "$1" --height "$2" >/dev/null 2>&1
  sleep 2
  # A hot restart keeps the browser URL, so a previous run of the catalogue
  # walk would leave this one asserting against the wrong screen.
  $FSA dusk:navigate --route / >/dev/null 2>&1
  sleep 2

  # A hot restart replaces Dart state but cannot revive a dead renderer, and
  # CanvasKit does occasionally die outright under this much driving
  # (`RuntimeError: memory access out of bounds` from canvaskit.wasm, usually
  # right after the engine's semantics text-field assertion fires). When that
  # happens the semantics tree comes back empty and every later case fails for
  # a reason that has nothing to do with it, so recover with a full relaunch
  # rather than reporting eight phantom failures.
  if [ -z "$($FSA dusk:snap 2>/dev/null | rg -o 'ref=e[0-9]+' | head -1)" ]; then
    printf '  \033[33m!\033[0m renderer gone, relaunching\n'
    $FSA stop >/dev/null 2>&1
    sleep 2
    $FSA start --device chrome --port 3210 --vm-service-port 8299 \
      --cdp-port 9322 --timeout 240 >/dev/null 2>&1
    sleep 20
    $FSA dusk:resize --width "$1" --height "$2" >/dev/null 2>&1
    sleep 2
  fi

  SEEN_EXCEPTIONS=0
}

# Prints the e<N> ref of the first "favorilere ekle" button on screen.
star_ref() {
  $FSA dusk:snap 2>/dev/null | rg 'favorilere ekle' | rg -o 'ref=e[0-9]+' | rg -o 'e[0-9]+' | head -1
}

walk_layout() {
  local label="$1" profile="$2" width="$3" height="$4"
  local slug snap ref
  slug="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')-$profile"

  log "$label @ $profile ${width}x${height}"

  reset_app "$width" "$height"

  ref="$(switcher_ref "$label")"
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

  # 1. Search reaches the whole line-up from this layout.
  expect_in_file "$snap" 'textbox' "$label: has a search field"

  # 2. Favourites are actionable from this layout, not only from another one.
  expect_in_file "$snap" 'favorilere ekle|favorilerden çıkar' "$label: has a favourite control"

  # 3. The provider sending no EPG is a designed state, not a hole.
  expect_in_file "$snap" -i 'akış yok' "$label: names the no-schedule case"

  # 4. Nothing overflowed. Wind and Flutter both report this to the console
  #    rather than throwing, so it is invisible to `dusk:exceptions`.
  refute_in_file "$snap" 'OVERFLOW' "$label: no overflow marker"

  # 5. Starring works and the control flips its own label. Before search,
  #    because a query cannot be undone from here (see reset_app) and this
  #    needs an unfiltered line-up.
  local starref
  starref="$(star_ref)"
  if [ -z "$starref" ]; then
    fail "$label: no unstarred favourite control to toggle"
  else
    $FSA dusk:tap --ref "$starref" >/dev/null 2>&1
    sleep 2
    expect_no_exceptions "$label favourite toggle"
    $FSA dusk:snap >"$OUT/$slug.starred.yaml" 2>/dev/null
    expect_in_file "$OUT/$slug.starred.yaml" 'favorilerden çıkar' "$label: starring flips the control"
  fi

  # 6. The category strip can narrow AND widen again. `Tümü` has to be on it:
  #    a filter you cannot leave is a trap, and this assertion is what found
  #    that it was missing.
  local groupref allref
  groupref="$($FSA dusk:snap 2>/dev/null | rg 'button "Spor"' | rg -o 'ref=e[0-9]+' | rg -o 'e[0-9]+' | head -1)"
  if [ -z "$groupref" ]; then
    fail "$label: no Spor category button"
  else
    $FSA dusk:tap --ref "$groupref" >/dev/null 2>&1
    sleep 2
    expect_no_exceptions "$label category filter"
    allref="$($FSA dusk:snap 2>/dev/null | rg 'button "Tümü"' | rg -o 'ref=e[0-9]+' | rg -o 'e[0-9]+' | head -1)"
    if [ -z "$allref" ]; then
      fail "$label: no way back to the unfiltered line-up"
    else
      $FSA dusk:tap --ref "$allref" >/dev/null 2>&1
      sleep 2
      expect_no_exceptions "$label category reset"
      $FSA dusk:snap >"$OUT/$slug.allgroups.yaml" 2>/dev/null
      expect_in_file "$OUT/$slug.allgroups.yaml" '23 kanal' "$label: Tümü restores the whole line-up"
    fi
  fi

  # 7. Search narrows, and an empty result set says so rather than rendering a
  #    blank body. Last, because it is one-way.
  local sref
  sref="$(search_ref)"
  if [ -z "$sref" ]; then
    fail "$label: search field has no usable ref"
  else
    $FSA dusk:fill --ref "$sref" --text 'spor' >/dev/null 2>&1
    sleep 2
    expect_no_exceptions "$label search"
    $FSA dusk:snap >"$OUT/$slug.search.yaml" 2>/dev/null
    $FSA dusk:screenshot --output "$OUT/$slug.search.png" >/dev/null 2>&1
    expect_in_file "$OUT/$slug.search.yaml" 'Spor' "$label: search finds Spor"

    $FSA dusk:fill --ref "$sref" --text 'zzzzzz' >/dev/null 2>&1
    sleep 2
    expect_no_exceptions "$label empty search"
    $FSA dusk:snap >"$OUT/$slug.empty.yaml" 2>/dev/null
    $FSA dusk:screenshot --output "$OUT/$slug.empty.png" >/dev/null 2>&1
    expect_in_file "$OUT/$slug.empty.yaml" 'Sonuç yok' "$label: empty search has an empty state"
  fi
}

walk_profile() {
  local profile="$1" width="$2" height="$3"

  for label in Sinyal Vitrin Sahne Mozaik; do
    walk_layout "$label" "$profile" "$width" "$height"
  done
}

log "Dusk line-up walk, artefacts in $OUT"
$FSA dusk:reset_overlays >/dev/null 2>&1

walk_profile desktop 1440 900
walk_profile mobile 414 896

printf '\n'
if [ "$FAILURES" -eq 0 ]; then
  printf '\033[32m%s/%s checks passed\033[0m\n' "$CHECKS" "$CHECKS"
else
  printf '\033[31m%s of %s checks failed\033[0m\n' "$FAILURES" "$CHECKS"
fi
exit $((FAILURES > 0 ? 1 : 0))
