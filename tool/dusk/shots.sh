#!/usr/bin/env bash
#
# Captures one screenshot per surface, at whichever width is passed.
#
# For looking at the work, not for gating it. The three walks beside this
# assert; this only produces the images a design decision actually gets made
# from, because every gate in this repository can pass on a screen nobody would
# ship.
#
# Four images: the two live views, the catalogue, and one title.
#
# Usage: tool/dusk/shots.sh [width] [output-dir]

set -u

FSA=./bin/fsa
OUT="${2:-/tmp/watchools-shots}"
W="${1:-1440}"
H=900
[ "$W" -lt 700 ] && H=896

mkdir -p "$OUT"

ref() {
  $FSA dusk:snap 2>/dev/null | rg -- "$1" | rg -o 'ref=e[0-9]+' | rg -o 'e[0-9]+' | head -1
}

shot() {
  sleep 2
  $FSA dusk:screenshot --output="$OUT/$W-$1.png" >/dev/null 2>&1
  printf '  %s\n' "$OUT/$W-$1.png"
}

go() {
  $FSA dusk:navigate --route "$1" >/dev/null 2>&1
  sleep 3
}

tap() {
  local r
  r="$(ref "$1")"
  [ -n "$r" ] && $FSA dusk:tap --ref "$r" >/dev/null 2>&1
  sleep 2
}

$FSA dusk:resize --width "$W" --height "$H" >/dev/null 2>&1
sleep 2

go /
shot 1-canli-simdi
tap '"Zaman görünümü"'
shot 2-canli-zaman
tap '"Şimdi görünümü"'

go /kutuphane
shot 3-kutuphane-vitrin

# Through the catalogue, because `/baslik` renders whatever was last selected
# and arriving cold shows the fixture's first entry rather than a series.
tap '"Diziler göster"'
sleep 2
tap 'detayı"'
shot 4-baslik-perde
