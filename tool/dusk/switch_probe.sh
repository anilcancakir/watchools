#!/usr/bin/env bash
#
# Reproduces one interaction on the live screen and reports the store.
#
# Kept because two separate overflows were blamed on three different things
# before each was reduced to a sequence this short. Pass a search term to
# reproduce a state the walk only reaches after several steps.
#
# Usage: tool/dusk/switch_probe.sh [width] [height] [search-term]

set -uo pipefail

FSA="./bin/fsa"
TERM_="${3:-}"

$FSA dusk:resize --width "${1:-1440}" --height "${2:-900}" >/dev/null 2>&1
sleep 2
$FSA dusk:navigate --route / >/dev/null 2>&1
sleep 3
$FSA dusk:exceptions --clear >/dev/null 2>&1

ref="$($FSA dusk:snap 2>/dev/null | rg '"Şimdi: ' | rg -o 'e[0-9]+' | head -1)"
if [ -z "$ref" ]; then
  printf 'no switcher on screen\n'
  exit 1
fi
$FSA dusk:tap --ref "$ref" >/dev/null 2>&1
sleep 3
printf 'after the switch: %s\n' "$($FSA dusk:exceptions 2>/dev/null | head -c 260)"

if [ -n "$TERM_" ]; then
  # Re-resolved immediately before the fill. `dusk:snap` re-mints every `eN`,
  # so a ref taken before an intervening snapshot points at nothing.
  local_sref="$($FSA dusk:snap 2>/dev/null | rg '^\s*-?\s*textbox' | rg -o 'e[0-9]+' | head -1)"
  $FSA dusk:fill --ref "$local_sref" --text "$TERM_" >/dev/null 2>&1
  sleep 3
  printf 'after "%s":   %s\n' "$TERM_" "$($FSA dusk:exceptions 2>/dev/null | head -c 400)"
  $FSA dusk:screenshot --output=/tmp/probe.png >/dev/null 2>&1
fi
