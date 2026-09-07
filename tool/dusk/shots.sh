#!/usr/bin/env bash
#
# Captures one screenshot per direction, at whichever width is passed.
#
# For looking at the work, not for gating it. The walks beside this assert; this
# only produces the images a design decision actually gets made from, because
# every gate in this repository can pass on a screen nobody would ship.

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
tap 'button "Kule'
shot 2-canli-kule
tap 'button "Zaman'
shot 3-canli-zaman
tap 'button "Şimdi'

go /kutuphane
shot 4-kutuphane-vitrin
tap 'button "Raf'
shot 5-kutuphane-raf
tap 'button "Koleksiyon'
shot 6-kutuphane-koleksiyon
tap 'button "Vitrin'

go /baslik
shot 7-detay-kunye
tap 'button "Perde'
shot 8-detay-perde
tap 'button "Sayfa'
shot 9-detay-sayfa
tap 'button "Künye'
