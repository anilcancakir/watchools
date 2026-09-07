---
name: Watchools
description: >
  An IPTV client for a subscription the user already owns. Dark-first across
  phone, web, desktop and the 10-foot screen. Netflix's cinematic near-black
  and its row rhythm, Plex's layering and its state-versus-fact badge
  discipline, on a gold that belongs to neither of them.
colors:
  # ---------------------------------------------------------------------------
  # Surfaces. Dark is the real theme; light exists so the generator has a pair
  # and so a daytime setting is possible later.
  #
  # The dark ramp is near-black with a faint cool cast rather than true black,
  # which is Netflix's move: #141414 on their page, proven by their own hero
  # scrim fading #141414 into transparent. True black makes provider artwork
  # look like it is floating in a void and crushes shadow detail on OLED.
  # ---------------------------------------------------------------------------
  surface:
    light: "#FAFAFB"
    dark: "#0E0F11"
  surface-container:
    light: "#FFFFFF"
    dark: "#16181B"
  surface-container-high:
    light: "#F1F3F5"
    dark: "#1F2226"
  fg:
    light: "#0E0F11"
    dark: "#F2F4F6"
  fg-muted:
    light: "#5A6068"
    dark: "#A8AEB6"
  fg-disabled:
    light: "#B4BAC1"
    dark: "#767D86"
  # ---------------------------------------------------------------------------
  # Brand. Gold rather than red, because gold reads as "your content" and red
  # reads as "our channel". In this product the content is the user's own
  # subscription. Gold also survives on top of warm provider artwork, where a
  # brand red fights every poster it lands on.
  #
  # The light value is much darker than the dark value on purpose: it is the
  # only amber that clears 4.5:1 in both directions on white (4.88 for white
  # text on it, 4.68 for it as text on the page).
  # ---------------------------------------------------------------------------
  primary:
    light: "#A36200"
    dark: "#F59B14"
  on-primary:
    light: "#FFFFFF"
    dark: "#17181A"
  primary-container:
    light: "#FFF0D6"
    dark: "#412E10"
  accent:
    light: "#8F5600"
    dark: "#FAB338"
  border:
    light: "#DFE3E7"
    dark: "#2A2E33"
  border-subtle:
    light: "#EDEFF2"
    dark: "#1A1D20"
  destructive:
    light: "#C42A33"
    dark: "#F2555F"
  on-destructive:
    light: "#FFFFFF"
    dark: "#17181A"
  destructive-container:
    light: "#FDE5E7"
    dark: "#4A1216"
  success:
    light: "#1E8E45"
    dark: "#3FC46B"
  warning:
    light: "#B77400"
    dark: "#F0A93A"
  # ---------------------------------------------------------------------------
  # Playback status families. Human reference only: design:sync emits the 17
  # roles above and ignores everything below. These reach the runtime as
  # className tokens through lib/config/watchools_status_tokens.dart, merged
  # into the WindThemeData alias map in lib/main.dart.
  #
  # Plex's discipline, adopted verbatim: STATE gets colour, FACT does not.
  # live / catchup / recording / epg-now are states and carry these values.
  # 1080p, H.265 and 5.1 are facts and use a neutral chip on
  # rgba(0,0,0,.6), because a row where everything is coloured is a row where
  # nothing is.
  #
  # live and recording deliberately share a red. They are told apart by form,
  # not hue: live is a filled badge carrying the word, recording is a dot. That
  # is the broadcast convention and fighting it costs more than it buys. If the
  # two prove hard to separate on a real panel, changing recording here is a
  # one-line fix.
  # ---------------------------------------------------------------------------
  live:
    light: "#C62222"
    dark: "#E83730"
  recording:
    light: "#C62222"
    dark: "#E83730"
  catchup:
    light: "#0369A1"
    dark: "#30ABE8"
  epg-now:
    light: "#A36200"
    dark: "#F59B14"
  # Focus is not the brand colour. Plex separates them (#8af keyboard focus
  # against a gold accent) and it is the right call: on a D-pad surface, focus
  # moves constantly and selection does not, so they must never be confused.
  focus-ring:
    light: "#1D6FD0"
    dark: "#7FB2FF"
typography:
  # Schibsted Grotesk carries the whole product. One variable family rather
  # than a display-plus-body pair: a hero here shows maybe eight words, and a
  # second family would have to pass the same Turkish audit for that little
  # surface. wght 400 to 900 already spans more tonal range than most pairs.
  #
  # No Light weight exists in this family; the axis starts at 400.
  display:
    fontFamily: Schibsted Grotesk
    fontSize: 36px
    fontWeight: "700"
    lineHeight: 44px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Schibsted Grotesk
    fontSize: 28px
    fontWeight: "700"
    lineHeight: 36px
    letterSpacing: -0.01em
  headline-md:
    fontFamily: Schibsted Grotesk
    fontSize: 22px
    fontWeight: "600"
    lineHeight: 30px
  title-lg:
    fontFamily: Schibsted Grotesk
    fontSize: 18px
    fontWeight: "600"
    lineHeight: 26px
  body-lg:
    fontFamily: Schibsted Grotesk
    fontSize: 16px
    fontWeight: "400"
    lineHeight: 26px
  body-md:
    fontFamily: Schibsted Grotesk
    fontSize: 14px
    fontWeight: "400"
    lineHeight: 22px
  label-md:
    fontFamily: Schibsted Grotesk
    fontSize: 14px
    fontWeight: "600"
    lineHeight: 20px
    letterSpacing: 0.01em
  label-sm:
    fontFamily: Schibsted Grotesk
    fontSize: 12px
    fontWeight: "500"
    lineHeight: 16px
  # The EPG time column and the channel number column. Same family, not a
  # monospace: a monospaced 20:45 sits wider and looser than the channel name
  # beside it and breaks the row rhythm. Tabular figures do the alignment.
  metric:
    fontFamily: Schibsted Grotesk
    fontSize: 14px
    fontWeight: "500"
    lineHeight: 20px
rounded:
  sm: 2px
  DEFAULT: 4px
  md: 6px
  lg: 8px
  xl: 12px
  2xl: 16px
  3xl: 24px
  full: 9999px
spacing:
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
  2xl: 48px
  gutter: 16px
  section: 32px
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.DEFAULT}"
    padding: "{spacing.md}"
  button-destructive:
    backgroundColor: "{colors.destructive}"
    textColor: "{colors.on-destructive}"
    rounded: "{rounded.DEFAULT}"
    padding: "{spacing.md}"
---

## Overview

Watchools plays a subscription the user already pays for. That single fact
decides the visual language: the content is theirs, not ours, so the interface
gets out of the way of provider artwork rather than competing with it.

The reference points are Netflix and Plex, and they contribute different
things. Netflix contributes the cinematic weight: a near-black page, artwork
that runs to the edge, a hero that is mostly image, and a row rhythm that has
been tuned on hundreds of millions of people. Plex contributes the structural
answers, because Plex renders a library the user supplied and so do we: a
layering model built on translucency rather than opaque greys, a badge
vocabulary that separates state from fact, a dense table view for when the list
is too long to browse, and focus treated as a different concept from selection.

One lesson arrived from both of them independently and outranks everything
else here. Netflix moved its TV navigation from a left rail to a top strip in
May 2025 and was still being called "borderline unusable" a year later. Plex
made the same move, absorbed a year of complaints, and reverted it on 18 August
2026. On a 10-foot screen the channel list stays on the left, permanently
visible, one D-pad press away.

## Colors

Seventeen semantic roles drive everything; nothing else is hardcoded. The dark
theme is the real one and the light theme exists so the pair is complete.

Dark backgrounds step `surface` (page) to `surface-container` (cards, rows) to
`surface-container-high` (inputs, menus, nested panels). All three are
near-black with a faint cool cast rather than true black, which keeps provider
artwork from looking like it is floating and preserves shadow detail on OLED.

Every text and surface pair in the dark theme clears WCAG AA for normal text.
Measured against its own tier: `fg` 17.4:1 on the page and 14.5:1 on the
elevated surface, `fg-muted` 8.6:1 and 7.1:1, `primary` 8.8:1 and 7.3:1,
`on-primary` on `primary` 8.1:1. `fg-disabled` clears 3.8:1 at its worst, which
is above the 3:1 floor that applies to inactive controls.

The gold is ours rather than Plex's `#E5A00D`, shifted warmer and richer. The
reasoning for gold over a Netflix red is in the frontmatter, and it has a
second consequence worth stating here: leaving red unclaimed by the brand frees
it to mean exactly one thing, which is that something is on air right now.

`focus-ring` is deliberately not the brand colour. See Layout.

## Typography

Schibsted Grotesk, the Norwegian media group's own face, SIL OFL 1.1, variable
`wght` 400 to 900, self-hosted as one file in `assets/fonts/`.

It was chosen against a Turkish audit that eliminated most of the field.
Turkish needs the dotted and dotless i pair to survive at UI sizes, and several
otherwise-excellent faces fail it: IBM Plex Sans and Outfit both fire an `fi`
ligature even on text tagged Turkish, which swallows the dot on `ofis`, `fiil`
and `finans`. Schibsted has no `fi` ligature at all, so it is safe without
depending on locale handling to rescue it. It also carries `latn/TRK` in its
GSUB langsys along with AZE, CRT and KAZ.

The second filter was the 10-foot screen. A capital `I` that is a bare stem is
indistinguishable from a lowercase `l` and a `1` at three metres, which rules
out Manrope, Geist and DM Sans regardless of their other merits. Schibsted's
`I` carries crossbars. That trait is worth more here than in an English product
because Turkish uses the capital dotless `I` constantly: IŞIK, ISPARTA, IĞDIR.

Two things must be wired or the type work is wasted. `TextStyle.locale` has to
carry `tr` for the Turkish `locl` substitutions to fire at all. And tabular
figures are per style rather than per family, so the EPG time column and the
channel number column each need `FontFeature.tabularFigures()`; without it
`20:45` and `21:00` do not align in a column.

The slashed zero is available as an opt-in `zero` feature and is deliberately
left off. The EPG is the most zero-dense surface in the app and a wall of
slashed zeros reads as a terminal rather than a TV guide.

## Layout

Mobile-first, one column, swapping its navigation shell at the `lg` breakpoint
(1024px) the way the sibling apps do. Below `lg` the shell is a bottom tab bar;
at and above it, a persistent left rail.

The 10-foot surface is the exception to the house rule that layout adapts to
width and never to platform. A 1920px TV and a 1920px monitor are the same
width and need different layouts, because the input is a remote rather than a
pointer. Wind has no form factor axis yet, so until it does, TV layout
decisions are made against the input model rather than the breakpoint.

Three consequences follow from the remote:

Focus and selection are different states with different colours. `focus-ring`
is a blue, `primary` is the gold. On a pointer surface focus barely appears; on
a D-pad surface it moves on every keypress, and a user who cannot tell "where
am I" from "what is chosen" is lost.

`hover:` is inert on TV. Every interaction that matters must be expressed with
`focus:` as well, and the ecosystem's habit of reaching for `hover:` first has
to be reversed here.

Overscan is a percentage, not a token. Netflix's current TV app insets its
content by about 3.55% of screen width per side, which is roughly 68px at
1920. Use the percentage; a fixed dp value is wrong on at least one panel.

## Elevation & Depth

Surface hierarchy is tonal, not shadowed, and it borrows from both references.

From Plex: layers over artwork are translucent rather than opaque, so one set
of tokens works over any provider poster without a second palette. Black at
80/60/30/10 percent for scrims and card fills, white at 10/18 percent for
controls.

From Netflix: the elevated card goes **darker** than the page, not lighter,
separated by a one-pixel line in the page colour. It inverts the usual
elevation instinct and it is what makes a hovered or focused card read as
cinema rather than as a raised button.

## Shapes

Two radii carry most of the product and they are not the same value.

Fact chips (resolution, codec, audio channels) use `rounded-sm`, 2px, which is
tight enough that six of them in a row read as one texture rather than six
objects. State badges (live, recording, catch-up) use `rounded` at 4px and are
filled. Cards use `rounded-lg` at 8px on a pointer surface and `rounded-2xl` at
16px on TV, where everything is larger and softer.

## Components

The generator emits the two buttons above. Everything else is composed in
`lib/ui/components/` as atomic folders through `./bin/fsa make:component`, each
carrying a recipe and a preview.

Three components define the product and are worth naming before they exist.
The channel tile carries a logo, a name, a number in tabular figures, and at
most one state badge. The EPG row is a horizontal time axis where the current
programme is marked with `epg-now` and everything else is neutral. The player
chrome is transparent over video and must never use a scrim heavier than 40
percent, which is the ceiling Plex holds and the reason their artwork stays
legible underneath.
