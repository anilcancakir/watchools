#!/usr/bin/env bash
#
# Dusk end-to-end walk of the catalogue screen.
#
# The same contract as the live walk, plus the two things a VOD library has that
# a channel list does not: a scope switch between films and series, and a search
# that has to reach episode titles rather than stopping at the top level. Both
# are asserted on a phone and on a desktop.
#
# The detail screen is a route of its own now and has its own walk. What this
# one asserts about it is only that opening a title GETS there, which is the
# seam between the two.
#
# What a green run does NOT prove: anything about a real device, a D-pad, or
# text scaling. It runs on web at scale 1.0 with a mouse.
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

mkdir -p "$OUT"
# shellcheck source=tool/dusk/_lib.sh
source "$(dirname "$0")/_lib.sh"

# Something only this direction renders, and at both widths.
#
# All three hold on a phone as well as a desktop, which the previous set did
# not: two of its three markers were desktop-only chrome, so the mobile pass
# reported the wrong direction on screen and every check under it certified
# whatever happened to be there.
direction_marker() {
  case "$1" in
    # The resume rail's source line. Only this direction builds a hero and
    # rails, and only it names where the resume point came from.
    Vitrin)     printf 'Bu cihazda kaldığın yer' ;;
    # The grid/table toggle. Only this direction hands the user controls, and
    # they now keep their own line on a phone rather than being dropped.
    Raf)        printf 'Liste görünümü' ;;
    # The provider rail, which is this direction's own borrowing from Apple.
    Koleksiyon) printf 'Kaynakların' ;;
  esac
}

# The title whose star this walk toggles, and the direction it toggles it in.
#
# Named rather than "the first one", because the catalogue fixture ships two
# pre-starred titles and every snapshot therefore already contains
# "favorilerden çıkar". Asserting the flip on a document-wide match passed
# whether the tap did anything or not; naming the subject makes it exact.
#
# STARRED rather than unstarred, and that is the interesting part. The obvious
# subject is the fixture's first unstarred part-watched title, and its star
# lands at (638, 839) on a 1440 by 900 window while the floating direction
# switcher's container spans (595..845, 839..883). They overlap by half a pixel,
# the switcher is on top, and every tap went to it: the walk reported a star
# that would not flip and the app was fine. Measured with `dusk:observe`, not
# guessed.
#
# A floating overlay above scrollable content always covers something, and the
# switcher is scaffolding that goes when a direction is chosen, so the answer is
# to aim somewhere else rather than to move it. The first resume card sits well
# clear of it, and toggling a STARRED title is the same assertion inverted: the
# snapshot cannot already contain `Sessiz Şehir favorilere ekle`, because the
# fixture ships that title starred.
STAR_SUBJECT='Sessiz Şehir'
STAR_BEFORE='favorilerden çıkar'
STAR_AFTER='favorilere ekle'

star_ref() {
  visible_ref "^$STAR_SUBJECT $STAR_BEFORE\$" "$1" "$2"
}

walk_direction() {
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
  $FSA dusk:screenshot --output="$OUT/$slug.png" >/dev/null 2>&1

  # Before anything else. `refute_*` passes on a zero-byte file, so a dead
  # renderer reported eight separate defects in one direction from one empty
  # snapshot and every one of them named a control that was fine.
  expect_rendered "$snap" "$label" || return

  expect_in_file "$snap" "$(direction_marker "$label")" "$label: is the direction on screen"
  expect_in_file "$snap" 'textbox' "$label: has a search field"
  expect_in_file "$snap" 'favorilere ekle|favorilerden çıkar' "$label: has a favourite control"
  # The count of poster-less titles is above the fold in every direction, which
  # is what `LibraryToolbar._count` carries. That is all this proves, and its
  # old name ("names the missing-artwork case") claimed more: the string is
  # rendered unconditionally by all three, so deleting every direction's actual
  # handling of a poster-less title would not have failed it.
  #
  # What each direction DOES with such a title is asserted further down, after a
  # search that puts one on screen.
  expect_in_file "$snap" 'afiş yok' "$label: states how many titles have no artwork"
  refute_overflow "$snap" "$label"

  # Favourite, before search, because search cannot be undone from here.
  local starref
  starref="$(star_ref "$width" "$height")"
  if [ -z "$starref" ]; then
    fail "$label: $STAR_SUBJECT has no favourite control in its starting state"
  else
    $FSA dusk:tap --ref "$starref" >/dev/null 2>&1
    sleep 2
    expect_no_exceptions "$label favourite toggle"
    $FSA dusk:snap >"$OUT/$slug.starred.yaml" 2>/dev/null
    expect_in_file "$OUT/$slug.starred.yaml" "$STAR_SUBJECT $STAR_AFTER" \
      "$label: the favourite control flips its own label"
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
    $FSA dusk:screenshot --output="$OUT/$slug.series.png" >/dev/null 2>&1
    refute_in_file "$OUT/$slug.series.yaml" 'Sessiz Şehir' "$label: series scope excludes films"
    expect_in_file "$OUT/$slug.series.yaml" '5 başlık' "$label: series scope narrows the count"

    # Opening a title leaves for the title route. That is the seam this walk
    # owns; what the title screen then renders is the title walk's business.
    #
    # `visible_ref_settled` rather than `ref_matching`, because the semantics
    # tree carries every node a sliver built and the first match here was two
    # screens down: the tap succeeded, landed on whatever was at those
    # coordinates, and the walk reported a card that would not navigate.
    #
    # `card_pattern` rather than a hand-written one. The first version required a
    # comma after the name, which is the resume rail's label shape and not the
    # grid's: the grid direction reported the same title as unreachable at both
    # widths while the other two found it.
    local item
    item="$(visible_ref_settled "$(card_pattern 'Bozkır Hattı')" "$width" "$height")"
    if [ -z "$item" ]; then
      fail "$label: the fixture series is not reachable in series scope"
    else
      $FSA dusk:tap --ref "$item" >/dev/null 2>&1
      sleep 3
      expect_no_exceptions "$label open title"
      $FSA dusk:snap >"$OUT/$slug.opened.yaml" 2>/dev/null
      $FSA dusk:screenshot --output="$OUT/$slug.opened.png" >/dev/null 2>&1
      # The title screen's own switcher, which the catalogue screen does not
      # have. Asserting on the title's NAME would pass without navigating.
      expect_in_file "$OUT/$slug.opened.yaml" 'button "Künye: ' "$label: opening a title reaches the title route"

      # Navigated rather than popped. `dusk:navigate_back` pops the active
      # Navigator, and under `MaterialApp.router` that leaves the router's own
      # location behind: the catalogue chrome came back but every control on it
      # was unreachable, so the four checks after this one failed for a reason
      # that had nothing to do with them. Whether BACK works is the title walk's
      # assertion; this one only needs to be on the catalogue again.
      $FSA dusk:navigate --route "$ROUTE" >/dev/null 2>&1
      sleep 3
      expect_no_exceptions "$label return to the catalogue"
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
  sref="$(search_ref)"
  if [ -z "$sref" ]; then
    fail "$label: search field has no usable ref"
  else
    # A title the provider sent no poster for, first. The doctrine's second rule
    # is that artwork earns its place or typography takes it, so such a title
    # has to be a reachable card carrying its own name rather than a hole in the
    # grid. In two of the three directions that card is below the fold on first
    # paint, so the assertion belongs behind a search rather than against the
    # arrival screen: asserting it there measured which direction happened to
    # put it near the top.
    fill_search 'Gece Yarısı'
    expect_no_exceptions "$label poster-less search"
    $FSA dusk:snap >"$OUT/$slug.noposter.yaml" 2>/dev/null
    $FSA dusk:screenshot --output="$OUT/$slug.noposter.png" >/dev/null 2>&1
    expect_in_file "$OUT/$slug.noposter.yaml" 'Gece Yarısı Ekspresi' \
      "$label: a poster-less title is still a card carrying its name"

    # An episode title, not a film title: a catalogue search that only covers
    # the top level cannot find the thing people actually remember.
    fill_search 'Sınır'
    expect_no_exceptions "$label episode search"
    $FSA dusk:snap >"$OUT/$slug.search.yaml" 2>/dev/null
    $FSA dusk:screenshot --output="$OUT/$slug.search.png" >/dev/null 2>&1
    expect_in_file "$OUT/$slug.search.yaml" '1 sonuç' "$label: search reaches episode titles"

    fill_search 'zzzzzz'
    expect_no_exceptions "$label empty search"
    $FSA dusk:snap >"$OUT/$slug.empty.yaml" 2>/dev/null
    $FSA dusk:screenshot --output="$OUT/$slug.empty.png" >/dev/null 2>&1
    expect_in_file "$OUT/$slug.empty.yaml" 'Sonuç yok' "$label: empty search has an empty state"
  fi
}

log "Dusk catalogue walk, artefacts in $OUT"
reap_browsers
$FSA dusk:reset_overlays >/dev/null 2>&1

for profile in "desktop 1440 900" "mobile 414 896"; do
  # shellcheck disable=SC2086
  set -- $profile
  for label in Vitrin Raf Koleksiyon; do
    walk_direction "$label" "$1" "$2" "$3"
  done
done

report
