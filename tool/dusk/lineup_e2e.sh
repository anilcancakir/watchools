#!/usr/bin/env bash
#
# Dusk end-to-end walk of the line-up screen.
#
# Every browse layout has to carry the same three capabilities, on a phone and
# on a desktop: search the whole line-up, star a channel, and say something
# useful about a channel the provider sent no EPG for. This asserts all three on
# all four at both widths, and fails on any app exception.
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

# Something only this layout renders.
#
# Without it the walk asserts nothing but layout-agnostic facts, so a missed
# switcher tap or a regressed `showLayout` would let every check pass against
# the default layout four times over.
layout_marker() {
  case "$1" in
    # Each of these has to hold at BOTH widths, which the first attempt did
    # not: Sinyal's mode toggle and Sahne's jump rail are both desktop-only, so
    # the mobile pass reported the wrong layout on screen.
    Sinyal) printf 'button "Bilgi"' ;;
    # The merged heading node ends the line after the name and carries its
    # count on the next, so the anchor is the line end rather than a space.
    # The category strip's own child text closes its quote on the same line.
    Vitrin) printf 'text "Ulusal$' ;;
    Sahne)  printf 'text "ULUSAL' ;;
    Mozaik) printf 'SEÇİLİ KANAL' ;;
  esac
}

# Prints the ref of the first "favorilere ekle" button on screen.
#
# Unstarred specifically. Asserting that the post-tap tree contains
# "favorilerden çıkar" proves something only when the tree did not already
# contain one, so the walk has to start from a fixture with nothing starred: the
# line-up fixture has none, and adding one `favourite: true` to it would
# silently disarm this check.
star_ref() {
  ref_matching 'favorilere ekle'
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

  # 0. This layout, and not whichever one was on screen before.
  expect_in_file "$snap" "$(layout_marker "$label")" "$label: is the layout on screen"

  # 1. Search reaches the whole line-up from this layout.
  expect_in_file "$snap" 'textbox' "$label: has a search field"

  # 2. Favourites are actionable here, not only from another layout.
  expect_in_file "$snap" 'favorilere ekle|favorilerden çıkar' "$label: has a favourite control"

  # 3. The provider sending no EPG is a designed state, not a hole.
  expect_in_file "$snap" -i 'akış yok' "$label: names the no-schedule case"

  # 4. Nothing overflowed. Flutter reports this to the console rather than
  #    throwing, so it is invisible to `dusk:exceptions`.
  refute_overflow "$snap" "$label"

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
    # The count, not the word `Spor`: the category strip renders that at all
    # times, so asserting on it passed whether the search worked or not.
    expect_in_file "$OUT/$slug.search.yaml" '2 sonuç' "$label: search narrows to two results"

    $FSA dusk:fill --ref "$sref" --text 'zzzzzz' >/dev/null 2>&1
    sleep 2
    expect_no_exceptions "$label empty search"
    $FSA dusk:snap >"$OUT/$slug.empty.yaml" 2>/dev/null
    $FSA dusk:screenshot --output "$OUT/$slug.empty.png" >/dev/null 2>&1
    expect_in_file "$OUT/$slug.empty.yaml" 'Sonuç yok' "$label: empty search has an empty state"
  fi
}

log "Dusk line-up walk, artefacts in $OUT"
$FSA dusk:reset_overlays >/dev/null 2>&1

for profile in "desktop 1440 900" "mobile 414 896"; do
  # shellcheck disable=SC2086
  set -- $profile
  for label in Sinyal Vitrin Sahne Mozaik; do
    walk_layout "$label" "$1" "$2" "$3"
  done
done

report
