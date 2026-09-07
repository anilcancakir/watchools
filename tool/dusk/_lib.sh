# Shared helpers for the dusk end-to-end walks.
#
# Sourced by lineup_e2e.sh, library_e2e.sh and title_e2e.sh. They started as two
# copies and every fix had to land twice, which is how three of the assertions
# below came to be silently vacuous in one script and not the other.
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
#
# An empty pattern fails rather than passing. `rg -q ''` matches every line of
# every file, and the per-view patterns in the line-up walk come from a `case`
# that returns nothing for an unmatched label: renaming one view would quietly
# turn several checks into checks that cannot fail, which is the exact shape of
# the four failures recorded elsewhere in this file.
expect_in_file() {
  local file="$1"; shift
  local desc="${@: -1}"
  set -- "${@:1:$(($# - 1))}"

  local pattern="${@: -1}"
  if [ -z "$pattern" ]; then
    fail "$desc: the pattern was empty, so this check could not fail"
    return
  fi

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
# Read from the response ENVELOPE, not by counting a key inside the entries.
#
# The previous version counted `"fatal":`, which only dusk's own ring buffer
# emits (`dusk/lib/src/dusk_error_capture.dart`). `dusk:exceptions` merges that
# buffer with telescope's store, and `telescope`'s `ExceptionRecord.toJson()`
# emits `exceptionType / message / time / stackTrace / isolate` and no `fatal`
# at all. Telescope is the half that hooks `PlatformDispatcher.instance.onError`
# (`exception_watcher.dart`, installed from `lib/main.dart`), so EVERY
# asynchronous, isolate and plugin exception was being counted as zero. So was
# an empty body from an app that had died, which is the case a gate most needs
# to catch.
#
# One message is filtered, and it is filtered from the PARSED entries rather
# than from the response text. `dusk:exceptions` prints the whole response as
# one line of JSON, so an `rg -v` on it deletes the entire list and the count
# then reads zero: that is how roughly forty checks in an earlier version of
# this walk came to pass unconditionally.
#
# Counted against a WATERMARK rather than against zero, because
# `dusk:exceptions --clear` does not empty the `FlutterError` half of the store:
# measured, an entry cleared at 17:04:06.250 was still there, with the same
# timestamp, on the next read. So a single overflow was re-reported by every
# check after it and one defect arrived as twenty one. `SEEN` holds the newest
# timestamp already reported; only entries strictly after it count.
SEEN=""

expect_no_exceptions() {
  local body report
  body="$($FSA dusk:exceptions 2>/dev/null)"

  report="$(printf '%s' "$body" | SEEN="$SEEN" python3 -c '
import json, os, sys

# Magic renders a plain MaterialApp with no route table while it bootstraps, so
# any restart whose URL is not the root logs this for a path the app does serve.
# `MaterialApp.router` then routes correctly. Recorded as defect 8 in
# `.ac/research/ecosystem-defects.md`; it is noise, not a failure.
BENIGN = "Could not navigate to initial route"

raw = sys.stdin.read()
try:
    body = json.loads(raw)
except ValueError:
    print("no readable response from dusk:exceptions, so the app is gone")
    raise SystemExit(0)

if "count" not in body:
    print("response carried no count, so the store could not be read")
    raise SystemExit(0)

seen = os.environ.get("SEEN") or ""
entries = body.get("exceptions", [])
newest = max((e.get("time") or "" for e in entries), default="")

real = [
    e for e in entries
    if BENIGN not in (e.get("message") or "") and (e.get("time") or "") > seen
]

# The watermark advances whether or not anything failed, so a benign entry
# cannot be re-reported either.
print("MARK %s" % newest)
if real:
    print("%d: %s" % (len(real), "; ".join((e.get("message") or "").splitlines()[0] for e in real[:3])))
')"

  local mark
  mark="$(printf '%s' "$report" | rg -o '^MARK .*' | head -1 | cut -c6-)"
  [ -n "$mark" ] && SEEN="$mark"
  report="$(printf '%s' "$report" | rg -v '^MARK ')"

  if [ -z "$report" ]; then
    pass "no exceptions: $1"
  else
    fail "after $1, $report"
  fi
}

# `visible_ref`, with one retry.
#
# The retry is not superstition. Its failure landed on a walk's FIRST iteration
# and on no other: a hot restart plus a route change plus a view switch plus a
# search is four settle windows in a row, and a fixed sleep is always a guess
# that is wrong somewhere.
visible_ref_settled() {
  local ref
  ref="$(visible_ref "$1" "$2" "$3")"
  if [ -z "$ref" ]; then
    sleep 4
    ref="$(visible_ref "$1" "$2" "$3")"
  fi
  printf '%s' "$ref"
}

# The regex that matches a catalogue card's anchor and NOT its favourite button.
#
# A card's label is `<name>, <caption>` in a resume rail and `<name> <year>` in
# a grid or a poster rail, so both shapes have to be admitted. The digit is what
# keeps it off the star, whose label is `<name> favorilere ekle`: a plain
# `[ ,]` matched that too, and matched it FIRST, so the tap starred the title
# instead of opening it and the walk went on asserting against a page it had
# never reached.
card_pattern() {
  printf '^%s(,| [0-9])' "$1"
}

# Fails once, loudly, when a snapshot came back with no nodes at all.
#
# CanvasKit does occasionally die outright under this much driving, and when it
# does the semantics tree comes back empty and every assertion under it fails
# for a reason that has nothing to do with it: one run reported five separate
# defects on one screen from a single zero-byte snapshot. Returns non-zero so
# the caller can stop rather than carry on against nothing.
expect_rendered() {
  if rg -q 'ref=e[0-9]+' -- "$1"; then
    return 0
  fi

  fail "$2: the snapshot came back empty, so the renderer is gone rather than the screen wrong"
  return 1
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

# Prints the ref of the first node matching $1 that is actually inside the
# viewport, or nothing.
#
# `ref_matching` walks the semantics tree, which carries every node a sliver
# BUILT, not every node a viewer can see. A rail two screens down is in that
# tree with a usable ref, and `dusk:tap` on it reports success and lands on
# whatever is at those coordinates: the walk spent two rounds reporting a star
# that would not flip and a card that would not navigate, and in both cases the
# app was fine and the tap was somewhere else.
#
# `dusk:observe` carries `bounds`, so this filters on them. `$2` and `$3` are
# the viewport, and the check is against the whole node rather than its centre
# because `dusk:tap` aims at the centre and a half-visible node has one outside.
#
# Being inside the viewport is not the same as being on top. Nothing in the app
# floats over scrollable content any more, so this is currently sufficient; the
# floating switcher it could not account for was removed with the layouts it
# switched between. Anything added over the page later needs handling here or at
# the call site, and the symptom is a tap that reports success and lands
# elsewhere.
visible_ref() {
  $FSA dusk:observe 2>/dev/null | python3 -c '
import json, re, sys

pattern, width, height = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
try:
    body = json.load(sys.stdin)
except ValueError:
    sys.exit(0)

for node in body.get("candidates", []):
    label = node.get("label") or ""
    if not re.search(pattern, label):
        continue
    box = node.get("bounds") or {}
    x, y = box.get("x", -1), box.get("y", -1)
    w, h = box.get("w", 0), box.get("h", 0)
    if x >= 0 and y >= 0 and x + w <= width and y + h <= height:
        print(node["ref"])
        break
' "$1" "$2" "$3"
}

# Prints the ref of the first text field on screen.
#
# Matches any textbox rather than one placeholder: the line-up and the catalogue
# word their search field differently on purpose, and an assertion that knows
# only one wording reports a missing field where the field is simply named
# something else.
search_ref() {
  $FSA dusk:snap 2>/dev/null | rg '^\s*-?\s*textbox' | rg -o 'ref=e[0-9]+' | rg -o 'e[0-9]+' | head -1
}

# Types $1 into the search field, resolving the field's ref immediately first.
#
# `dusk:snap` re-mints every `eN`, so a ref taken once and reused across a
# sequence that snapshots in between points at nothing: the fill reported
# success, the screen did not change, and the two assertions after it failed
# while naming controls that were fine. Returns non-zero when there is no field.
fill_search() {
  local sref
  sref="$(search_ref)"
  [ -z "$sref" ] && return 1

  $FSA dusk:fill --ref "$sref" --text "$1" >/dev/null 2>&1
  sleep 2
  return 0
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
  # The watermark goes with the isolate. A hot restart empties the store for
  # real, which `--clear` does not, so keeping a mark from the previous
  # iteration would hide this one's first exception.
  SEEN=""
}

# Kills any Chrome left behind by an earlier run and removes its profile.
#
# `fsa stop` does not always reach the browser: it reports
# `Chrome SIGTERM not delivered` when the pid has already been reparented, and
# the process keeps its profile directory and its memory. Seven of them
# accumulated across one afternoon's runs and the last walk was killed by the
# system for memory pressure before it wrote a line of output, which reads
# exactly like a hang.
#
# Matched on the profile path so this cannot touch the user's own browser.
reap_browsers() {
  pkill -f 'user-data-dir=/tmp/dusk-chrome-' 2>/dev/null
  sleep 2
  rm -rf /tmp/dusk-chrome-*
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
