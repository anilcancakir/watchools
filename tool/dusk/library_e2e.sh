#!/usr/bin/env bash
#
# Dusk end-to-end walk of the catalogue screen.
#
# The same contract as the live walk, plus the two things a VOD library has that
# a channel list does not: a scope switch between films and series, and a search
# that has to reach episode titles rather than stopping at the top level. Both
# are asserted on a phone and on a desktop.
#
# One layout, `Vitrin`, so there is no view switch here. That asymmetry with the
# live screen is deliberate: a catalogue has no "what is on at nine" cut,
# because everything in it is available at every moment.
#
# The title screen is a route of its own and has its own walk. What this one
# asserts about it is only that opening a title GETS there, which is the seam
# between the two.
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

# The resume rail's source line, and the one string that says this layout
# actually built its hero and its rails rather than falling back to a bare list.
#
# It holds at both widths, which the previous set of markers did not: two of
# them were desktop-only chrome, so the mobile pass reported the wrong layout on
# screen and every check under it certified whatever happened to be there.
LAYOUT_MARKER='Bu cihazda kaldığın yer'

# The title whose star this walk toggles.
#
# Named rather than "the first one", because the catalogue fixture ships two
# pre-starred titles and every snapshot therefore already contains
# "favorilerden çıkar". Asserting the flip on a document-wide match passed
# whether the tap did anything or not; naming the subject makes it exact.
#
# STARRED rather than unstarred, and the inversion is what makes it exact: the
# snapshot cannot already contain `Sessiz Şehir favorilere ekle`, because the
# fixture ships that title starred.
#
# The first resume card is also well clear of the page's other controls. That
# used to matter more than it does: the floating layout switcher's container
# spanned (595..845, 839..883) on a 1440 by 900 window and overlapped an
# obvious alternative subject by half a pixel, so every tap went to the switcher
# and the walk reported a star that would not flip while the app was fine.
# Measured with `dusk:observe`, not guessed. The switcher is gone, the subject
# stays.
STAR_SUBJECT='Sessiz Şehir'
STAR_BEFORE='favorilerden çıkar'
STAR_AFTER='favorilere ekle'

star_ref() {
  visible_ref "^$STAR_SUBJECT $STAR_BEFORE\$" "$1" "$2"
}

walk_catalogue() {
  local profile="$1" width="$2" height="$3"
  local slug snap
  slug="vitrin-$profile"

  log "Vitrin @ $profile ${width}x${height}"

  reset_app "$width" "$height"

  snap="$OUT/$slug.snap.yaml"
  $FSA dusk:snap >"$snap" 2>/dev/null
  $FSA dusk:screenshot --output="$OUT/$slug.png" >/dev/null 2>&1

  # Before anything else. `refute_*` passes on a zero-byte file, so a dead
  # renderer reported eight separate defects on one screen from one empty
  # snapshot and every one of them named a control that was fine.
  expect_rendered "$snap" 'Vitrin' || return

  expect_in_file "$snap" "$LAYOUT_MARKER" 'Vitrin: the hero and its rails are on screen'
  expect_in_file "$snap" 'textbox' 'Vitrin: has a search field'
  expect_in_file "$snap" 'favorilere ekle|favorilerden çıkar' 'Vitrin: has a favourite control'
  # The count of poster-less titles is above the fold, which is what
  # `LibraryToolbar._count` carries. That is all this proves, and its old name
  # ("names the missing-artwork case") claimed more: the string is rendered
  # unconditionally, so deleting the actual handling of a poster-less title
  # would not have failed it.
  #
  # What the screen DOES with such a title is asserted further down, after a
  # search that puts one on screen.
  expect_in_file "$snap" 'afiş yok' 'Vitrin: states how many titles have no artwork'
  refute_overflow "$snap" 'Vitrin'

  # Favourite, before search, because search cannot be undone from here.
  local starref
  starref="$(star_ref "$width" "$height")"
  if [ -z "$starref" ]; then
    fail "Vitrin: $STAR_SUBJECT has no favourite control in its starting state"
  else
    $FSA dusk:tap --ref "$starref" >/dev/null 2>&1
    sleep 2
    expect_no_exceptions 'Vitrin favourite toggle'
    $FSA dusk:snap >"$OUT/$slug.starred.yaml" 2>/dev/null
    expect_in_file "$OUT/$slug.starred.yaml" "$STAR_SUBJECT $STAR_AFTER" \
      'Vitrin: the favourite control flips its own label'
  fi

  # The scope switch is the thing a catalogue has and a channel list does not.
  local seriesref
  seriesref="$(ref_matching '"Diziler göster"')"
  if [ -z "$seriesref" ]; then
    fail 'Vitrin: no series scope switch'
  else
    $FSA dusk:tap --ref "$seriesref" >/dev/null 2>&1
    sleep 2
    expect_no_exceptions 'Vitrin series scope'
    $FSA dusk:snap >"$OUT/$slug.series.yaml" 2>/dev/null
    $FSA dusk:screenshot --output="$OUT/$slug.series.png" >/dev/null 2>&1
    refute_in_file "$OUT/$slug.series.yaml" 'Sessiz Şehir' 'Vitrin: series scope excludes films'
    expect_in_file "$OUT/$slug.series.yaml" '5 başlık' 'Vitrin: series scope narrows the count'

    # Opening a title leaves for the title route. That is the seam this walk
    # owns; what the title screen then renders is the title walk's business.
    #
    # `visible_ref_settled` rather than `ref_matching`, because the semantics
    # tree carries every node a sliver built and the first match here was two
    # screens down: the tap succeeded, landed on whatever was at those
    # coordinates, and the walk reported a card that would not navigate.
    #
    # `card_pattern` rather than a hand-written one. The first version required a
    # comma after the name, which is the resume rail's label shape and not a
    # poster rail's, so the walk reported the same title as unreachable while
    # it was on screen.
    local item
    item="$(visible_ref_settled "$(card_pattern 'Bozkır Hattı')" "$width" "$height")"
    if [ -z "$item" ]; then
      fail 'Vitrin: the fixture series is not reachable in series scope'
    else
      $FSA dusk:tap --ref "$item" >/dev/null 2>&1
      sleep 3
      expect_no_exceptions 'Vitrin open title'
      $FSA dusk:snap >"$OUT/$slug.opened.yaml" 2>/dev/null
      $FSA dusk:screenshot --output="$OUT/$slug.opened.png" >/dev/null 2>&1
      # Something only the title screen renders. Asserting on the title's NAME
      # would pass without navigating, because the card carries it too; the
      # season column exists on no other screen in the app.
      expect_in_file "$OUT/$slug.opened.yaml" 'Sezonlar|. sezon' 'Vitrin: opening a title reaches the title route'

      # Navigated rather than popped. `dusk:navigate_back` pops the active
      # Navigator, and under `MaterialApp.router` that leaves the router's own
      # location behind: the catalogue chrome came back but every control on it
      # was unreachable, so the four checks after this one failed for a reason
      # that had nothing to do with them. Whether BACK works is the title walk's
      # assertion; this one only needs to be on the catalogue again.
      $FSA dusk:navigate --route "$ROUTE" >/dev/null 2>&1
      sleep 3
      expect_no_exceptions 'Vitrin return to the catalogue'
    fi

    local allref
    allref="$(ref_matching '"Tümü göster"')"
    if [ -z "$allref" ]; then
      fail 'Vitrin: no way back to the whole catalogue'
    else
      $FSA dusk:tap --ref "$allref" >/dev/null 2>&1
      sleep 2
      expect_no_exceptions 'Vitrin scope reset'
      $FSA dusk:snap >"$OUT/$slug.allscope.yaml" 2>/dev/null
      expect_in_file "$OUT/$slug.allscope.yaml" '15 başlık' 'Vitrin: Tümü restores the whole catalogue'
    fi
  fi

  # Search, last, because it is one-way.
  local sref
  sref="$(search_ref)"
  if [ -z "$sref" ]; then
    fail 'Vitrin: search field has no usable ref'
  else
    # A title the provider sent no poster for, first. The doctrine's second rule
    # is that artwork earns its place or typography takes it, so such a title
    # has to be a reachable card carrying its own name rather than a hole in the
    # grid. It is below the fold on first paint, so the assertion belongs behind
    # a search rather than against the arrival screen.
    fill_search 'Gece Yarısı'
    expect_no_exceptions 'Vitrin poster-less search'
    $FSA dusk:snap >"$OUT/$slug.noposter.yaml" 2>/dev/null
    $FSA dusk:screenshot --output="$OUT/$slug.noposter.png" >/dev/null 2>&1
    expect_in_file "$OUT/$slug.noposter.yaml" 'Gece Yarısı Ekspresi' \
      'Vitrin: a poster-less title is still a card carrying its name'

    # An episode title, not a film title: a catalogue search that only covers
    # the top level cannot find the thing people actually remember.
    fill_search 'Sınır'
    expect_no_exceptions 'Vitrin episode search'
    $FSA dusk:snap >"$OUT/$slug.search.yaml" 2>/dev/null
    $FSA dusk:screenshot --output="$OUT/$slug.search.png" >/dev/null 2>&1
    expect_in_file "$OUT/$slug.search.yaml" '1 sonuç' 'Vitrin: search reaches episode titles'

    fill_search 'zzzzzz'
    expect_no_exceptions 'Vitrin empty search'
    $FSA dusk:snap >"$OUT/$slug.empty.yaml" 2>/dev/null
    $FSA dusk:screenshot --output="$OUT/$slug.empty.png" >/dev/null 2>&1
    expect_in_file "$OUT/$slug.empty.yaml" 'Sonuç yok' 'Vitrin: empty search has an empty state'
  fi
}

log "Dusk catalogue walk, artefacts in $OUT"
reap_browsers
$FSA dusk:reset_overlays >/dev/null 2>&1

for profile in "desktop 1440 900" "mobile 414 896"; do
  # shellcheck disable=SC2086
  set -- $profile
  walk_catalogue "$1" "$2" "$3"
done

report
