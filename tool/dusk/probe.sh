#!/usr/bin/env bash
#
# A fast sweep of every direction, for use while the design is being built.
#
# It is not a gate and asserts nothing: it visits each of the nine directions,
# prints the exception count, the number of nodes dusk flagged as sitting inside
# an overflowing flex, and the node count, and moves on. The three walks beside
# it are the gates.
#
# The node count is the useful column. A direction that renders nothing comes
# back with a handful of nodes rather than an error, and that is the failure
# mode a screenshot-free sweep would otherwise miss.

set -u

FSA=./bin/fsa

ref() {
  $FSA dusk:snap 2>/dev/null | rg -- "$1" | rg -o 'ref=e[0-9]+' | rg -o 'e[0-9]+' | head -1
}

check() {
  local label="$1" body ex ov nodes
  body="$($FSA dusk:snap 2>/dev/null)"
  ex="$($FSA dusk:exceptions 2>/dev/null | rg -o '"fatal":' | wc -l | tr -d ' ')"
  ov="$(printf '%s' "$body" | rg -c 'overflow: true' || true)"
  nodes="$(printf '%s' "$body" | rg -c 'ref=e' || true)"

  printf '%-28s exceptions=%-3s overflow=%-3s nodes=%s\n' "$label" "${ex:-0}" "${ov:-0}" "${nodes:-0}"

  if [ "${ex:-0}" -ne 0 ]; then
    $FSA dusk:exceptions 2>/dev/null | head -c 900
    printf '\n'
    $FSA dusk:exceptions --clear >/dev/null 2>&1
  fi
}

go() {
  $FSA dusk:navigate --route "$1" >/dev/null 2>&1
  sleep 3
}

tap() {
  local r
  r="$(ref "$1")"
  if [ -n "$r" ]; then
    $FSA dusk:tap --ref "$r" >/dev/null 2>&1
    sleep 2
  else
    printf '  ! no ref for %s\n' "$1"
  fi
}

sweep() {
  $FSA dusk:resize --width "$1" --height "$2" >/dev/null 2>&1
  sleep 2
  $FSA dusk:exceptions --clear >/dev/null 2>&1
  printf '\n== %sx%s ==\n' "$1" "$2"

  go /
  check 'canli/Simdi'
  tap 'button "Kule'
  check 'canli/Kule'
  tap 'button "Zaman'
  check 'canli/Zaman'
  tap 'button "Şimdi'
  check 'canli/Simdi geri'

  go /kutuphane
  check 'kutuphane/Vitrin'
  tap 'button "Raf'
  check 'kutuphane/Raf'
  tap 'button "Koleksiyon'
  check 'kutuphane/Koleksiyon'
  tap 'button "Vitrin'
  check 'kutuphane/Vitrin geri'

  go /baslik
  check 'detay/Kunye'
  tap 'button "Perde'
  check 'detay/Perde'
  tap 'button "Sayfa'
  check 'detay/Sayfa'
}

sweep 1440 900
sweep 414 896
