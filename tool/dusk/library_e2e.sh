#!/usr/bin/env bash
#
# Dusk end-to-end walk of the catalogue screen.
#
# The same contract as the line-up walk, plus the two things a VOD library has
# that a channel list does not: a scope switch between films and series, and a
# series that has to open on the episode the viewer left off at rather than on
# season one. Both are asserted on a phone and on a desktop.
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

# Something only this layout renders.
layout_marker() {
  case "$1" in
    # Each has to hold at BOTH widths. Defter's column header is desktop-only,
    # so `BAŞLIK` reported the wrong layout on the mobile pass, and the DİZİ
    # badge is invisible to the semantics tree because the row's own label
    # replaces its descendants. The resume note in that label is Defter's: the
    # other two show progress as a bar with no words.
    Duvar)  printf 'button "Sessiz Şehir 2024"' ;;
    Defter) printf 'sırada|dk kaldı' ;;
    Sergi)  printf 'ayrıntıları' ;;
  esac
}

# Prints the ref of an unstarred favourite control on a title that starts
# unstarred.
#
# Named rather than "the first one", because the catalogue fixture ships two
# pre-starred titles and every snapshot therefore already contains
# "favorilerden çıkar". Asserting the flip on a document-wide match passed
# whether the tap did anything or not; naming the subject makes it exact.
STAR_SUBJECT='Kuzey Rüzgârı'

star_ref() {
  ref_matching "\"$STAR_SUBJECT favorilere ekle\""
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

  expect_in_file "$snap" "$(layout_marker "$label")" "$label: is the layout on screen"
  expect_in_file "$snap" 'textbox' "$label: has a search field"
  expect_in_file "$snap" 'favorilere ekle|favorilerden çıkar' "$label: has a favourite control"
  # A title the provider sent no artwork for is stated rather than left blank.
  expect_in_file "$snap" 'afiş yok' "$label: names the missing-artwork case"
  refute_overflow "$snap" "$label"

  # Favourite, before search, because search cannot be undone from here.
  local starref
  starref="$(star_ref)"
  if [ -z "$starref" ]; then
    fail "$label: $STAR_SUBJECT has no unstarred favourite control"
  else
    $FSA dusk:tap --ref "$starref" >/dev/null 2>&1
    sleep 2
    expect_no_exceptions "$label favourite toggle"
    $FSA dusk:snap >"$OUT/$slug.starred.yaml" 2>/dev/null
    expect_in_file "$OUT/$slug.starred.yaml" "$STAR_SUBJECT favorilerden çıkar" \
      "$label: starring flips the control"
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
    refute_in_file "$OUT/$slug.series.yaml" 'Sessiz Şehir' "$label: series scope excludes films"
    expect_in_file "$OUT/$slug.series.yaml" '5 başlık' "$label: series scope narrows the count"

    # The resume point. `Bozkır Hattı` is finished through S02B01 and part way
    # into S02B02, so the play button has exactly one right answer and season
    # two is the one that must be open.
    # Matched on the name and filtered past the favourite button, rather than
    # on the label's shape: the label is a full sentence now (name, kind, year,
    # length, rating, resume note) because a `WAnchor` label replaces the text
    # of everything under it, and a matcher keyed to the old `name year` shape
    # broke the moment that was fixed.
    local seriesitem
    seriesitem="$($FSA dusk:snap 2>/dev/null | rg 'Bozkır Hattı' | rg -v 'favori' \
      | rg -o 'ref=e[0-9]+' | rg -o 'e[0-9]+' | head -1)"
    if [ -z "$seriesitem" ]; then
      fail "$label: the fixture series is not reachable in series scope"
    else
      $FSA dusk:tap --ref "$seriesitem" >/dev/null 2>&1
      sleep 2
      expect_no_exceptions "$label series select"
      $FSA dusk:snap >"$OUT/$slug.detail.yaml" 2>/dev/null
      $FSA dusk:screenshot --output "$OUT/$slug.detail.png" >/dev/null 2>&1
      expect_in_file "$OUT/$slug.detail.yaml" 'S02B02 oynat' "$label: resumes at the right episode"
      # The first episode of season two, which is always at the top of the list
      # whatever the viewport. Asserting on the last one tested the fold.
      expect_in_file "$OUT/$slug.detail.yaml" 'S02B01' "$label: opens the season the resume point is in"
      refute_overflow "$OUT/$slug.detail.yaml" "$label detail"
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
  sref="$(search_ref)"
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
    expect_in_file "$OUT/$slug.search.yaml" '1 sonuç' "$label: search reaches episode titles"

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

report
