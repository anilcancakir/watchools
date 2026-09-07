# Shared helpers for the dusk end-to-end walks.
#
# Sourced by lineup_e2e.sh and library_e2e.sh. They started as two copies and
# every fix had to land twice, which is how three of the assertions below came
# to be silently vacuous in one script and not the other.
#
# Not executable and not standalone: it defines functions and expects the caller
# to have set FSA, OUT and ROUTE.

# shellcheck shell=bash

FAILURES=0
CHECKS=0

log()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
pass() { CHECKS=$((CHECKS + 1)); printf '  \033[32m✓\033[0m %s\n' "$*"; }
fail() { CHECKS=$((CHECKS + 1)); FAILURES=$((FAILURES + 1)); printf '  \033[31m✗\033[0m %s\n' "$*"; }
note() { printf '  \033[33m!\033[0m %s\n' "$*"; }

# expect_in_file <file> [rg-flag...] <pattern> <description>
expect_in_file() {
  local file="$1"; shift
  local desc="${@: -1}"
  set -- "${@:1:$(($# - 1))}"
  if rg -q "$@" -- "$file"; then pass "$desc"; else fail "$desc"; fi
}

# refute_in_file <file> <pattern> <description>
refute_in_file() {
  if rg -q -- "$2" "$1"; then fail "$3"; else pass "$3"; fi
}

# Fails when the app has recorded any exception since the last reset.
#
# The exception store is emptied by `reset_app` through `dusk:exceptions
# --clear`, so this is an absolute "is it zero" rather than a delta against a
# running total. The delta version this replaces was worse than useless: it
# filtered a known-benign message out of a response that `dusk:exceptions`
# prints as ONE line of JSON, so the filter deleted the whole exception list
# and the count read zero for the rest of that iteration. In the catalogue walk
# that condition held on every single iteration, so roughly forty checks were
# passing unconditionally.
#
# Counted on `"fatal":`, which every exception entry carries and the response
# envelope does not.
expect_no_exceptions() {
  local body count
  body="$($FSA dusk:exceptions 2>/dev/null)"
  count="$(printf '%s' "$body" | rg -o '"fatal":' | wc -l | tr -d ' ')"

  if [ "${count:-0}" -eq 0 ]; then
    pass "no exceptions: $1"
  else
    fail "$count exception(s) after $1: $body"
    # Cleared so the next assertion reports its own interaction rather than
    # inheriting this one.
    $FSA dusk:exceptions --clear >/dev/null 2>&1
  fi
}

# Fails when any node in the snapshot sits inside an overflowing flex.
#
# The marker is the lowercase `overflow: true` sub-line dusk adds from its live
# render-object walk. The scripts refuted uppercase `OVERFLOW` for a while,
# which appears nowhere in dusk's output, so fourteen checks could not fail.
refute_overflow() {
  refute_in_file "$1" 'overflow: true' "$2: no overflow marker"
}

# Prints the ref of the first node whose snapshot line matches $1.
ref_matching() {
  $FSA dusk:snap 2>/dev/null | rg -- "$1" | rg -o 'ref=e[0-9]+' | rg -o 'e[0-9]+' | head -1
}

# Prints the ref of the first text field on screen.
#
# Matches any textbox rather than one placeholder: the layouts word their search
# field differently on purpose, and an assertion that knows only one wording
# reports a missing field where the field is simply named something else.
search_ref() {
  $FSA dusk:snap 2>/dev/null | rg '^\s*-?\s*textbox' | rg -o 'ref=e[0-9]+' | rg -o 'e[0-9]+' | head -1
}

# Returns the app to first-run state and empties the exception store.
#
# A hot restart rather than a cleared search field, and this is the one place
# where the obvious approach does not work at all. On Flutter web:
#
#   * `dusk:clear` empties the widget's own editing value without dispatching a
#     change, so a controlled `WInput` never tells the app, and the field reads
#     empty while the controller still holds the old term.
#   * `dusk:fill --text ''` clears through the same non-notifying path.
#   * `dusk:press_key --key Backspace` has no effect on text at all: a
#     synthesised hardware key does not drive `EditableText` on web, where
#     editing arrives through the browser's composition path.
#   * `artisan tinker`, which could just call `search('')` on the controller,
#     is unavailable here: the `--cdp-port` branch runs `-d web-server`, and
#     DWDS's `WebSocketProxyService` does not implement the VM Service
#     `evaluate` RPC.
#
# So state is reset by dropping it. Each case starting from a restart also
# means one failing case cannot cascade into the next.
#
# Flutter logs "Could not navigate to initial route" on any restart whose
# browser URL is not the root: `MagicApplication` shows a plain `MaterialApp`
# while it bootstraps, and a bare `MaterialApp` with no route table cannot match
# the platform's initial route. `MaterialApp.router` then takes over and routes
# correctly. That is a defect in the sibling's loading placeholder rather than
# here, so the store is cleared AFTER navigating rather than the message being
# filtered out of a response the filter cannot safely touch.
reset_app() {
  $FSA hot-restart >/dev/null 2>&1
  sleep 12
  $FSA dusk:resize --width "$1" --height "$2" >/dev/null 2>&1
  sleep 2
  $FSA dusk:navigate --route "$ROUTE" >/dev/null 2>&1
  sleep 3

  # A hot restart replaces Dart state but cannot revive a dead renderer, and
  # CanvasKit does occasionally die outright under this much driving
  # (`RuntimeError: memory access out of bounds` from canvaskit.wasm). When that
  # happens the semantics tree comes back empty and every later case fails for a
  # reason that has nothing to do with it.
  if [ -z "$($FSA dusk:snap 2>/dev/null | rg -o 'ref=e[0-9]+' | head -1)" ]; then
    note 'renderer gone, relaunching'
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

  $FSA dusk:exceptions --clear >/dev/null 2>&1
}

# Prints the totals and exits non-zero on any failure.
report() {
  printf '\n'
  if [ "$FAILURES" -eq 0 ]; then
    printf '\033[32m%s/%s checks passed\033[0m\n' "$CHECKS" "$CHECKS"
  else
    printf '\033[31m%s of %s checks failed\033[0m\n' "$FAILURES" "$CHECKS"
  fi
  exit $((FAILURES > 0 ? 1 : 0))
}
