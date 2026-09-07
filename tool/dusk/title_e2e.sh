#!/usr/bin/env bash
#
# Dusk end-to-end walk of the title screen: one movie or one series.
#
# `Perde` is the layout: full-bleed artwork, display type, one filled verb, and
# the season list as a sibling column of the episode list rather than a
# dropdown. The walk asserts the content rather than the composition, because
# the content is what a viewer came for: the one filled verb names the episode
# it would resume, the season the resume point is in is the one that opens, the
# technical stack is on the page, back gets out, and a title the provider sent
# nothing for still renders a page rather than a hole.
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

# Points the catalogue at one title and opens it through the hero's own control.
#
# Through the catalogue rather than by navigating to `/baslik` directly, because
# the title route carries no identifier yet: it renders whatever the catalogue
# last selected, so arriving without selecting first would assert against the
# fixture's first entry every time.
#
# Through the HERO rather than a rail card, and that is the part learned the
# hard way. A search narrows the catalogue to one title, which the hero then
# promotes, and the hero is at the top of the page at every width. The rail card
# for the same title sits below the fold at one width and above it at the other,
# so the walk reported the same title as unreachable at 414 and found it at
# 1440, which measured the fold rather than the app.
open_title() {
  local name="$1" width="$2" height="$3" ref
  $FSA dusk:navigate --route /kutuphane >/dev/null 2>&1
  sleep 3

  # `fill_search` resolves the field's ref immediately before typing. A ref taken
  # once and reused across a sequence that snapshots in between points at
  # nothing, because `dusk:snap` re-mints every `eN`: the fill reports success,
  # the screen does not change, and the assertions after it fail while naming
  # controls that are fine.
  if ! fill_search "$name"; then
    return 1
  fi
  sleep 1

  ref="$(visible_ref_settled "^$name detayı\$" "$width" "$height")"
  if [ -z "$ref" ]; then
    return 1
  fi

  $FSA dusk:tap --ref "$ref" >/dev/null 2>&1
  sleep 3
  return 0
}

walk_title() {
  local profile="$1" width="$2" height="$3"
  local slug snap ref
  slug="perde-$profile"

  log "Perde @ $profile ${width}x${height}"

  reset_app "$width" "$height"

  # A series first: it is the case with seasons, episodes and a resume point.
  if ! open_title 'Bozkır Hattı' "$width" "$height"; then
    fail 'Perde: the fixture series is not reachable from the catalogue'
    return
  fi
  expect_no_exceptions 'Perde open series'

  snap="$OUT/$slug.series.yaml"
  $FSA dusk:snap >"$snap" 2>/dev/null
  $FSA dusk:screenshot --output="$OUT/$slug.series.png" >/dev/null 2>&1

  expect_rendered "$snap" 'Perde' || return

  # 0. This layout, and not the catalogue it was opened from. The meta line
  #    joins genres with a middle dot, which is a rendering difference rather
  #    than a marker planted for the walk: the catalogue's cards carry a comma.
  expect_in_file "$snap" 'Aksiyon · Gerilim|Dram · Tarih' 'Perde: is the title screen on screen'

  # 1. The one filled verb names its target. `Bozkır Hattı` is finished through
  #    S02B01 and 37% into S02B02, so there is exactly one right answer.
  expect_in_file "$snap" 'S02B02' 'Perde: the play verb names the resume episode'

  # 2. The season the resume point is in is the one that opened, not season one.
  #    S02B01 is the first row of season two and is above the fold at both
  #    widths; asserting on the last row would test the fold instead.
  expect_in_file "$snap" 'S02B01' 'Perde: opens the season the resume point is in'

  refute_overflow "$snap" 'Perde series'

  # 3. Back reaches the catalogue. A detail page that traps you is the failure a
  #    route was introduced to prevent, and asserting only that the CONTROL
  #    exists is what this walk used to do: the button was present in every
  #    snapshot and nothing pressed it.
  ref="$(visible_ref_settled '^Geri$' "$width" "$height")"
  if [ -z "$ref" ]; then
    fail 'Perde: no reachable back control'
  else
    $FSA dusk:tap --ref "$ref" >/dev/null 2>&1
    sleep 3
    expect_no_exceptions 'Perde back'
    $FSA dusk:snap >"$OUT/$slug.back.yaml" 2>/dev/null
    # The catalogue's own scope switch, which the title screen does not have.
    # Asserting on the title's name would pass without going anywhere.
    expect_in_file "$OUT/$slug.back.yaml" 'Diziler göster' 'Perde: back lands on the catalogue'
  fi

  # 4. A film. No seasons, no episodes, and a shorter page.
  #
  #    The technical stack is asserted HERE and not on the series page, and that
  #    is not laziness. A snapshot carries what the slivers built, and on a
  #    series page the seasons and the episode list push the stack well past the
  #    cache extent. A film page is short enough for the stack to be real at
  #    both widths.
  if ! open_title 'Sessiz Şehir' "$width" "$height"; then
    fail 'Perde: the fixture film is not reachable from the catalogue'
  else
    expect_no_exceptions 'Perde open film'
    $FSA dusk:snap >"$OUT/$slug.film.yaml" 2>/dev/null
    $FSA dusk:screenshot --output="$OUT/$slug.film.png" >/dev/null 2>&1
    expect_rendered "$OUT/$slug.film.yaml" 'Perde film' &&
      expect_in_file "$OUT/$slug.film.yaml" 'Devam et' 'Perde: a part-watched film offers to resume' &&
      expect_in_file "$OUT/$slug.film.yaml" 'ALTYAZILAR|Altyazılar' 'Perde: a film carries the technical stack' &&
      refute_in_file "$OUT/$slug.film.yaml" 'Sezonlar' 'Perde: a film has no seasons section' &&
      refute_overflow "$OUT/$slug.film.yaml" 'Perde film'
  fi

  # 5. A title the provider sent nothing for. No poster, no rating, no synopsis
  #    and no cast, which is a large share of a real catalogue and the case the
  #    artwork-led half of the screen cannot render.
  if ! open_title 'Gece Yarısı Ekspresi' "$width" "$height"; then
    fail 'Perde: the bare fixture entry is not reachable from the catalogue'
  else
    expect_no_exceptions 'Perde open bare title'
    $FSA dusk:snap >"$OUT/$slug.bare.yaml" 2>/dev/null
    $FSA dusk:screenshot --output="$OUT/$slug.bare.png" >/dev/null 2>&1
    expect_rendered "$OUT/$slug.bare.yaml" 'Perde bare' &&
      expect_in_file "$OUT/$slug.bare.yaml" 'özet göndermedi' 'Perde: a missing synopsis says so' &&
      # The page still exists. A layout that collapses to its chrome when the
      # provider sent nothing is the one this case is here to catch.
      expect_in_file "$OUT/$slug.bare.yaml" 'Gece Yarısı Ekspresi' 'Perde: the bare title still names itself' &&
      refute_overflow "$OUT/$slug.bare.yaml" 'Perde bare'
  fi
}

log "Dusk title walk, artefacts in $OUT"
reap_browsers
$FSA dusk:reset_overlays >/dev/null 2>&1

for profile in "desktop 1440 900" "mobile 414 896"; do
  # shellcheck disable=SC2086
  set -- $profile
  walk_title "$1" "$2" "$3"
done

report
