#!/usr/bin/env bash
#
# Dusk end-to-end walk of the title screen: one movie or one series.
#
# The three directions disagree about composition and agree about content, so
# the walk asserts the content: the one filled verb names the episode it would
# resume, the season the resume point is in is the one that opens, the technical
# stack is on the page, and a title the provider sent nothing for still renders
# a page rather than a hole.
#
# The last of those is the one worth having. A detail screen is where a missing
# poster, a missing synopsis, a missing rating and an empty cast all land at
# once, and it is the screen most likely to be built against the fixture entry
# that has everything.
#
# What a green run does NOT prove: anything about a real device, a D-pad, or
# text scaling. It runs on web at scale 1.0 with a mouse.
#
# Requires an app started with CDP so the viewport can be resized:
#   ./bin/fsa start --device chrome --port 3210 --vm-service-port 8299 \
#     --cdp-port 9322 --timeout 240
#
# Usage: tool/dusk/title_e2e.sh [output-dir]

set -uo pipefail

FSA="./bin/fsa"
OUT="${1:-build/e2e-title}"
ROUTE="/baslik"

mkdir -p "$OUT"
# shellcheck source=tool/dusk/_lib.sh
source "$(dirname "$0")/_lib.sh"

# Something only this direction renders, at both widths.
#
# The third is a genuine rendering difference rather than a marker planted for
# the walk: the cinematic direction joins genres with a middle dot because they
# sit on one meta line under a display title, and the other two join them with
# a comma because they sit in a labelled fact row.
direction_marker() {
  case "$1" in
    # The header arrows that walk to the next title without going back first.
    Künye) printf 'Sonraki başlık' ;;
    # The meta line's genre separator.
    Perde) printf 'Aksiyon · Gerilim|Dram · Tarih' ;;
    # The specs section's source line.
    Sayfa) printf 'Sağlayıcının bildirdiği değerler' ;;
  esac
}

# Points the catalogue at [1] and opens it, leaving the title route on screen.
#
# Through the catalogue rather than by navigating to `/baslik` directly,
# because the title route carries no identifier yet: it renders whatever the
# catalogue last selected, so arriving without selecting first would assert
# against the fixture's first entry every time.
open_title() {
  local name="$1" width="$2" height="$3" item shelf
  $FSA dusk:navigate --route /kutuphane >/dev/null 2>&1
  sleep 3

  # The grid direction, then a search. Both halves are needed and both were
  # learned the hard way.
  #
  # Searching puts one card on the page instead of fifteen. Switching to the
  # grid decides WHERE that card is: the catalogue's default direction leads
  # with a hero, so a single result sits below the fold at one width and above
  # it at the other, and the walk reported the same title as unreachable in
  # three directions at one width and found it in all three at the other. A grid
  # puts its first cell in the same place at every width.
  #
  # Which catalogue direction the title screen was opened FROM does not change
  # what the title screen renders, so this costs the walk nothing.
  shelf="$(ref_matching '"Raf: ')"
  if [ -n "$shelf" ]; then
    $FSA dusk:tap --ref "$shelf" >/dev/null 2>&1
    sleep 2
  fi

  # `fill_search` resolves the field's ref immediately before typing. A ref taken
  # once and reused across a sequence that snapshots in between points at
  # nothing, because `dusk:snap` re-mints every `eN`: the fill reports success,
  # the screen does not change, and the assertions after it fail while naming
  # controls that are fine.
  if ! fill_search "$name"; then
    return 1
  fi
  sleep 1

  # `visible_ref_settled`, not `ref_matching`. The semantics tree carries every
  # node a sliver built, including rails two screens down, and a tap on one of
  # those succeeds and lands on whatever is at those coordinates instead.
  item="$(visible_ref_settled "$(card_pattern "$name")" "$width" "$height")"
  if [ -z "$item" ]; then
    return 1
  fi

  $FSA dusk:tap --ref "$item" >/dev/null 2>&1
  sleep 3
  return 0
}

walk_direction() {
  local label="$1" profile="$2" width="$3" height="$4"
  local slug snap ref
  slug="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')-$profile"

  log "$label @ $profile ${width}x${height}"

  reset_app "$width" "$height"

  # A series first: it is the case with seasons, episodes and a resume point,
  # and it is the one the three directions compose most differently.
  if ! open_title 'Bozkır Hattı' "$width" "$height"; then
    fail "$label: the fixture series is not reachable from the catalogue"
    return
  fi
  expect_no_exceptions "$label open series"

  ref="$(ref_matching "\"$label: ")"
  if [ -z "$ref" ]; then
    fail "$label: switcher button not found on the title route"
    return
  fi
  $FSA dusk:tap --ref "$ref" >/dev/null 2>&1
  sleep 2
  expect_no_exceptions "$label switch"

  snap="$OUT/$slug.series.yaml"
  $FSA dusk:snap >"$snap" 2>/dev/null
  $FSA dusk:screenshot --output="$OUT/$slug.series.png" >/dev/null 2>&1

  expect_rendered "$snap" "$label" || return

  # 0. This direction, and not whichever one was on screen before.
  expect_in_file "$snap" "$(direction_marker "$label")" "$label: is the direction on screen"

  # 1. The one filled verb names its target. `Bozkır Hattı` is finished through
  #    S02B01 and 37% into S02B02, so there is exactly one right answer.
  expect_in_file "$snap" 'S02B02' "$label: the play verb names the resume episode"

  # 2. The season the resume point is in is the one that opened, not season one.
  #    S02B01 is the first row of season two and is above the fold at both
  #    widths; asserting on the last row would test the fold instead.
  expect_in_file "$snap" 'S02B01' "$label: opens the season the resume point is in"

  # 3. Back reaches the catalogue. A detail page that traps you is the failure
  #    a route was introduced to prevent.
  expect_in_file "$snap" '"Geri"' "$label: has a back control"

  refute_overflow "$snap" "$label series"

  # 4. A film. No seasons, no episodes, and a different shape of page in all
  #    three directions.
  #
  #    The technical stack is asserted HERE and not on the series page, and that
  #    is not laziness. A snapshot carries what the slivers built, and on a
  #    series page the seasons and the episode list push the stack well past the
  #    cache extent: the assertion failed on two directions and passed on the
  #    third only because that one is a phone layout with a shorter page. A film
  #    page is short enough for the stack to be real at both widths.
  if ! open_title 'Sessiz Şehir' "$width" "$height"; then
    fail "$label: the fixture film is not reachable from the catalogue"
  else
    expect_no_exceptions "$label open film"
    $FSA dusk:snap >"$OUT/$slug.film.yaml" 2>/dev/null
    $FSA dusk:screenshot --output="$OUT/$slug.film.png" >/dev/null 2>&1
    expect_rendered "$OUT/$slug.film.yaml" "$label film" &&
      expect_in_file "$OUT/$slug.film.yaml" 'Devam et' "$label: a part-watched film offers to resume" &&
      expect_in_file "$OUT/$slug.film.yaml" 'ALTYAZILAR|Altyazılar' "$label: a film carries the technical stack" &&
      refute_in_file "$OUT/$slug.film.yaml" 'Sezonlar' "$label: a film has no seasons section" &&
      refute_overflow "$OUT/$slug.film.yaml" "$label film"
  fi

  # 5. A title the provider sent nothing for. No poster, no rating, no synopsis
  #    and no cast, which is a large share of a real catalogue and the case the
  #    poster-led half of every direction cannot render.
  if ! open_title 'Gece Yarısı Ekspresi' "$width" "$height"; then
    fail "$label: the bare fixture entry is not reachable from the catalogue"
  else
    expect_no_exceptions "$label open bare title"
    $FSA dusk:snap >"$OUT/$slug.bare.yaml" 2>/dev/null
    $FSA dusk:screenshot --output="$OUT/$slug.bare.png" >/dev/null 2>&1
    expect_rendered "$OUT/$slug.bare.yaml" "$label bare" &&
      expect_in_file "$OUT/$slug.bare.yaml" 'özet göndermedi' "$label: a missing synopsis says so" &&
      # The page still exists. A direction that collapses to its chrome when the
      # provider sent nothing is the one this case is here to catch.
      expect_in_file "$OUT/$slug.bare.yaml" 'Gece Yarısı Ekspresi' "$label: the bare title still names itself" &&
      refute_overflow "$OUT/$slug.bare.yaml" "$label bare"
  fi
}

log "Dusk title walk, artefacts in $OUT"
reap_browsers
$FSA dusk:reset_overlays >/dev/null 2>&1

for profile in "desktop 1440 900" "mobile 414 896"; do
  # shellcheck disable=SC2086
  set -- $profile
  for label in Künye Perde Sayfa; do
    walk_direction "$label" "$1" "$2" "$3"
  done
done

report
