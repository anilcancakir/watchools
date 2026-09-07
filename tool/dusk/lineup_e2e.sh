#!/usr/bin/env bash
#
# Dusk end-to-end walk of the live television screen.
#
# The screen ships two views of one line-up, `Şimdi` and `Zaman`, and both have
# to carry the same four capabilities on a phone and on a desktop: search the
# whole line-up, star a channel, narrow by category and get back out again, and
# say something useful about a channel the provider sent no EPG for. This
# asserts all four on both, at both widths, and fails on any app exception.
#
# The switch between them is a product control now rather than scaffolding, so
# it gets an assertion of its own: reaching a view has to work through the
# control a viewer would use, and its labels are what a screen reader reads.
#
# It drives the app through dusk rather than a browser automation library, so
# what it exercises is the running Flutter tree and the same semantics labels a
# screen reader would read. A missing `semanticLabel` fails here.
#
# What a green run does NOT prove: anything about a real device, a D-pad, or
# text scaling. It runs on web at scale 1.0 with a mouse.
#
# Requires an app started with CDP so the viewport can be resized:
#   ./bin/fsa start --device chrome --port 3210 --vm-service-port 8299 \
#     --cdp-port 9322 --timeout 240
#
# Usage: tool/dusk/lineup_e2e.sh [output-dir]

set -uo pipefail

FSA="./bin/fsa"
OUT="${1:-build/e2e}"
ROUTE="/"

mkdir -p "$OUT"
# shellcheck source=tool/dusk/_lib.sh
source "$(dirname "$0")/_lib.sh"

# Something only this view renders, at both widths.
#
# Without it the walk asserts nothing but view-agnostic facts, so a missed
# switch tap or a regressed `showMode` would let every check pass against
# whichever view happened to be on screen.
direction_marker() {
  case "$1" in
    # An editorial rail title. Only this view builds rails.
    Şimdi) printf 'Daha yeni başladı' ;;
    # The ruler's day label. Nothing else in the app draws a time axis.
    Zaman) printf 'BUGÜN' ;;
  esac
}

# The string THIS view uses for a channel the provider sent no EPG for.
#
# Neither is the shared count line. `Şimdi` builds a rail for them and names it;
# `Zaman` draws a full-window block inside the grid.
no_guide_marker() {
  case "$1" in
    Şimdi) printf 'Akış bilgisi olmayan kanallar' ;;
    Zaman) printf 'Bu kanal için yayın akışı gelmedi' ;;
  esac
}

# The other view's label, for the round trip below.
other_view() {
  case "$1" in
    Şimdi) printf 'Zaman' ;;
    Zaman) printf 'Şimdi' ;;
  esac
}

# Taps the switch segment named $1 and waits for the swap.
#
# `visible_ref` rather than `ref_matching`: both segments exist in every
# snapshot by design, and the tree carries nodes a viewer cannot reach.
tap_view() {
  local name="$1" width="$2" height="$3" ref
  ref="$(visible_ref_settled "^$name görünümü\$" "$width" "$height")"
  [ -z "$ref" ] && return 1

  $FSA dusk:tap --ref "$ref" >/dev/null 2>&1
  sleep 2
  return 0
}

# Prints the ref of the first "favorilere ekle" button on screen.
#
# Unstarred specifically. Asserting that the post-tap tree contains
# "favorilerden çıkar" proves something only when the tree did not already
# contain one, so the walk has to start from a fixture with nothing starred: the
# line-up fixture has none, and adding one `favourite: true` to it would
# silently disarm this check.
star_ref() {
  visible_ref ' favorilere ekle$' "$1" "$2"
}

walk_view() {
  local label="$1" profile="$2" width="$3" height="$4"
  local slug snap
  slug="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')-$profile"

  log "$label @ $profile ${width}x${height}"

  reset_app "$width" "$height"

  # A round trip rather than one tap, and the extra press is the point. A
  # restart arrives on `Şimdi`, so tapping straight to it is a no-op that proves
  # nothing: the walk would report the arrival screen as a successful switch.
  # Going to the other view first makes both presses real in both iterations,
  # and it is also the only thing that would catch a switch that works one way
  # and strands you the other.
  if ! tap_view "$(other_view "$label")" "$width" "$height"; then
    fail "$label: the view switch is not reachable on the toolbar"
    return
  fi
  expect_no_exceptions "$label switch out"

  if ! tap_view "$label" "$width" "$height"; then
    fail "$label: the switch does not offer a way back from the other view"
    return
  fi
  expect_no_exceptions "$label switch back"

  snap="$OUT/$slug.snap.yaml"
  $FSA dusk:snap >"$snap" 2>/dev/null
  $FSA dusk:screenshot --output="$OUT/$slug.png" >/dev/null 2>&1

  # Before anything else. `refute_*` passes on a zero-byte file, so a dead
  # renderer used to report five separate defects on one screen from one empty
  # snapshot.
  expect_rendered "$snap" "$label" || return

  # 0. This view, and not whichever one was on screen before.
  expect_in_file "$snap" "$(direction_marker "$label")" "$label: is the view on screen"

  # 1. Both segments of the switch survive the switch. A control that renders
  #    only its unselected half, or loses the way back, strands the viewer in
  #    whichever view they last pressed.
  expect_in_file "$snap" 'Şimdi görünümü' "$label: the switch still offers Şimdi"
  expect_in_file "$snap" 'Zaman görünümü' "$label: the switch still offers Zaman"

  # 2. Search reaches the whole line-up from here.
  expect_in_file "$snap" 'textbox' "$label: has a search field"

  # 3. Favourites are actionable here, not only in the other view.
  expect_in_file "$snap" 'favorilere ekle|favorilerden çıkar' "$label: has a favourite control"

  # 4. The count of channels with no EPG is above the fold, in both views.
  #    That much is the doctrine's third rule and both toolbars carry it. What
  #    each view does with those channels is asserted further down, after a
  #    search that puts them on screen.
  expect_in_file "$snap" 'kanalda akış yok' "$label: states the missing-guide count without scrolling"

  # 5. Nothing overflowed. Flutter reports this to the console rather than
  #    throwing, so it is invisible to `dusk:exceptions`.
  refute_overflow "$snap" "$label"

  # 6. Starring works and the control flips its own label. Before search,
  #    because a query cannot be undone from here (see reset_app) and this
  #    needs an unfiltered line-up.
  local starref
  starref="$(star_ref "$width" "$height")"
  if [ -z "$starref" ]; then
    fail "$label: no unstarred favourite control to toggle"
  else
    $FSA dusk:tap --ref "$starref" >/dev/null 2>&1
    sleep 2
    expect_no_exceptions "$label favourite toggle"
    $FSA dusk:snap >"$OUT/$slug.starred.yaml" 2>/dev/null
    expect_in_file "$OUT/$slug.starred.yaml" 'favorilerden çıkar' "$label: starring flips the control"
  fi

  # 7. The category strip can narrow AND widen again. `Tümü` has to be on it:
  #    a filter you cannot leave is a trap, and this assertion is what found
  #    that it was missing.
  local groupref allref
  groupref="$(ref_matching '"Spor kategorisi"')"
  if [ -z "$groupref" ]; then
    fail "$label: no Spor category button"
  else
    $FSA dusk:tap --ref "$groupref" >/dev/null 2>&1
    sleep 2
    expect_no_exceptions "$label category filter"
    $FSA dusk:snap >"$OUT/$slug.filtered.yaml" 2>/dev/null
    expect_in_file "$OUT/$slug.filtered.yaml" '2 kanal' "$label: Spor narrows to two channels"

    allref="$(ref_matching '"Tümü kategorisi"')"
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

  # 8. Search narrows, and an empty result set says so rather than rendering a
  #    blank body. Last, because it is one-way.
  local sref
  sref="$(search_ref)"
  if [ -z "$sref" ]; then
    fail "$label: search field has no usable ref"
  else
    # A channel the provider sent no EPG for, first. Both views have a designed
    # state for it and in `Şimdi` that state is below the fold on first paint:
    # it puts its no-guide rail last, which is editorially right and
    # structurally invisible to a snapshot. Narrowing to one such channel brings
    # each view's own words to the top.
    #
    # This assertion used to sit above, against a loose alternation, and matched
    # exactly one string in the whole app: the shared count line, which both
    # render unconditionally. It proved the fixture has channels without EPG and
    # nothing about either view; delete the designed state from both and it
    # still passed.
    fill_search 'Müzik'
    expect_no_exceptions "$label no-guide search"
    $FSA dusk:snap >"$OUT/$slug.noguide.yaml" 2>/dev/null
    $FSA dusk:screenshot --output="$OUT/$slug.noguide.png" >/dev/null 2>&1
    expect_in_file "$OUT/$slug.noguide.yaml" "$(no_guide_marker "$label")" \
      "$label: names the no-schedule case in its own words"

    fill_search 'spor'
    expect_no_exceptions "$label search"
    $FSA dusk:snap >"$OUT/$slug.search.yaml" 2>/dev/null
    $FSA dusk:screenshot --output="$OUT/$slug.search.png" >/dev/null 2>&1
    # The count, not the word `Spor`: the category strip renders that at all
    # times, so asserting on it passed whether the search worked or not.
    expect_in_file "$OUT/$slug.search.yaml" '2 sonuç' "$label: search narrows to two results"

    fill_search 'zzzzzz'
    expect_no_exceptions "$label empty search"
    $FSA dusk:snap >"$OUT/$slug.empty.yaml" 2>/dev/null
    $FSA dusk:screenshot --output="$OUT/$slug.empty.png" >/dev/null 2>&1
    expect_in_file "$OUT/$slug.empty.yaml" 'Sonuç yok' "$label: empty search has an empty state"
    # The way out of an empty result set. The empty body is its own layout and
    # it dropped the switch once, which left a viewer whose search matched
    # nothing with no route to the other view.
    expect_in_file "$OUT/$slug.empty.yaml" 'görünümü' "$label: the empty state keeps the view switch"
  fi
}

log "Dusk live-television walk, artefacts in $OUT"
reap_browsers
$FSA dusk:reset_overlays >/dev/null 2>&1

for profile in "desktop 1440 900" "mobile 414 896"; do
  # shellcheck disable=SC2086
  set -- $profile
  for label in Şimdi Zaman; do
    walk_view "$label" "$1" "$2" "$3"
  done
done

report
