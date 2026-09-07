# Design doctrine

Read from eight reference screens: Netflix on a TV and on the web, Plex on the
web and on Android, Apple TV. What follows is what each one is actually doing,
then the rules they agree on, then the places where Watchools cannot follow
them and has to decide for itself.

This is upstream of `DESIGN.md`. `DESIGN.md` names the tokens; this names what
the tokens are for.

## Part one: reading the references

### Netflix, television

Full-bleed key art with no frame, no letterbox and no card. The artwork is not
illustrating the screen, it **is** the screen. A left icon rail about 40 pixels
wide sits at the lowest contrast the design allows, unlabelled, one item
underlined in red; it is a hint that a menu exists, not a menu.

The content block occupies the left third: a small wide-tracked type label
(`N SERIES`), then the title **as artwork** rather than as text, then four lines
of synopsis, then exactly two buttons. White filled `Play`, translucent
`More Info`. Underneath, one rail titled `Trending Now` in quiet 16 pixel type,
posters edge to edge, the eighth one clipped by the screen edge.

No poster carries a label. The art carries its own title.

### Netflix, web

The whole page is rails and nothing else. No grid, no filter, no sort control.
Cards are **16:9 landscape**, not posters, and they carry no metadata at all:
no year, no rating, no runtime, no duration. Gutters are 4 to 8 pixels; the last
card in every row is cut by the viewport.

The row titles do the work the metadata is not doing, and they are editorial
sentences rather than taxonomy: `Because you watched Narcos`,
`Top Picks for Joshua`. Badges are a provider logo top left and a red
`NEW EPISODES` flag bottom left.

### Netflix, series detail on television

A two column split. Left is narrow: the title logotype, one metadata line
(`97% Match · 2003 · 10 Seasons`), then seasons as a **plain vertical list**,
not a dropdown. The focused season carries a thin rectangular ring, never a
fill, and reveals `24 episodes` on its right edge. Seasons below the focused one
fade toward the bottom.

Right is the episode list: 16:9 still, title, two or three lines of synopsis,
`(22m)`. Above it a content advisory spelled out in words rather than symbols:
`Season 4 · U/A 13+ · Crude humor, language, mature themes`.

There is no poster of the show anywhere on the page.

### Plex, web home

A 250 pixel left sidebar with **words**, outline icons, three groups (primary,
sources, more) and an explicit collapse control. A persistent 470 pixel search
field in the top bar, always there, never behind an icon.

The content header carries the page name, a small grey subtitle underneath, a
tab row underlined in amber, and on the right a **zoom slider and a grid/list
toggle**. The user is given control over their own shelf.

Sections are titled, and each title carries a small grey **source line** beneath
it saying where the row came from (`Discover`). Cards are 2:3 posters with the
title and a meta line **below** the artwork: `8 episodes`, `1 season`,
`5 seasons`. Continue-watching carries an amber progress bar across the bottom
of the poster and `S12 · B24` in the meta.

### Plex, series detail on the web

The background is washed with a warm brown pulled out of the poster, darkening
downward. Not a blurred backdrop image, a colour wash.

Left: the poster at about 250 pixels with a black square badge in the corner
holding the unwatched count `29`, and beneath it the resume target spelled out:
`Hazır, S12 · B24`.

Right, stacked with real air between each: title at 36 pixels, year, genre, then
a fact line holding a `TV-14` pill and a `71%` critic chip, then the action row.
The action row is **one amber filled button** (`▶ Devam`) and then five icon
only ghost buttons. Then the synopsis, clamped to three lines with an amber
`Daha fazla ⌄`. Then seasons as posters with count badges. Then cast as
**circular** avatars with name and role, where a missing photo becomes initials
in a grey circle rather than a gap.

The header also carries previous/next title arrows, so you can walk the library
without going back to it.

### Plex, episode detail on the web

The same shell with a 16:9 still where the poster was. Show name large, episode
name beneath it. A fact line: `Season 13 · Bölüm 2`, then
`October 7, 2022 · 88 dakika · TV-14`.

Then the part that matters most for this product: a **technical spec table**.
`Video 720p (H.264)`, `Ses Unknown (AAC Mono)`, `Altyazılar Hiçbiri ⌄`. Two are
read-only facts and the third is a control, and they share one row shape.

And an empty state that occupies real space inside a bordered box, with a
sentence explaining itself: `Şu anda bu başlık için uygun konum yok.`

### Plex, Android

The primary action becomes a large amber circular button straddling the seam
between the backdrop and the content. Everything else collapses into a centred
icon row. The poster shrinks to 90 pixels and overlaps the backdrop's lower
edge.

The label-value pattern survives the move from web to phone unchanged: small
grey caps label on the left (`GENRE`, `CAST`), value beside it.

An overflow `⋮` sits on every object at every level: the card, the row, the
page. The server name in the app bar is itself a dropdown.

Amber appears only as progress, badge, primary action and active state. Nothing
else on the screen is coloured.

### Apple TV

The menu is a **left overlay drawer** that dims the content behind it rather
than pushing it. Profile and clock at the top, then two items, then a labelled
group `Channels & Apps` listing providers by their own square logos.

Focus is a light-filled rounded rectangle with a lift and a shadow. The focused
row is raised into light; everything unfocused recedes to near-monochrome.

Ranking is typographic: a giant numeral outside the card, half cropped by its
neighbour, rather than a badge inside it. Below each card, title in semibold
white and a single genre word in grey.

One entire rail is nothing but provider brand tiles: solid colour 16:9
rectangles with a logo centred. Brand identity is a first class citizen, not a
watermark.

## Part two: what all three agree on

Eleven rules. Each one is followed by all three products, on every platform they
ship, which is what makes them worth adopting rather than debating.

1. **One primary verb per screen, in the brand colour.** Netflix has one white
   `Play`. Plex has one amber `Devam`. Apple has the lifted focus. Everything
   else is a ghost button or an icon. There is never a second filled button.

2. **Focus is physical, not chromatic.** Apple lifts into light, Netflix draws a
   ring. Neither fills the focused element with the accent colour, because the
   accent colour is already spoken for by the primary action and by progress.

3. **Progress is a thin bar along the bottom edge of the artwork.** Never a
   percentage, never a ring, never a number. Netflix red, Plex amber, two to
   four pixels tall, flush with the bottom of the image.

4. **Counts live in a corner badge on the artwork, not in the metadata line.**
   Plex puts unwatched episodes in a black square top right. Apple puts rank in
   a giant numeral beside the card. Neither writes it as prose.

5. **Rails bleed, grids do not.** A horizontal row is honest about continuing:
   the last card is clipped by the viewport (Netflix, Apple) or the row carries
   explicit arrows (Plex). A grid ends where it ends.

6. **Missing data occupies its slot.** A cast member with no photo gets a grey
   circle with initials. An empty section gets a bordered box with a sentence in
   it. Nothing collapses, because a collapsing layout teaches the user that the
   page is broken.

7. **The label-value stack carries the truth.** Small grey caps label, value
   beside it, one per line. This is where genre, cast, codec, audio track and
   subtitle selection live, and it survives unchanged from a 27 inch monitor to
   a phone.

8. **Section titles are sentences with a point of view.** `Because you watched
   Narcos`, `Spine-Chilling Horror Debuts`, `İzlemeye Devam Et`. Optionally a
   small grey source line beneath saying where the row came from.

9. **Navigation is left, dark, and has three registers.** Icon-only rail that
   expands on focus (Netflix TV), labelled and collapsible (Plex web), overlay
   drawer (Apple TV). None of the three uses a bottom tab bar anywhere except a
   phone.

10. **Artwork aspect ratio encodes what the thing is.** 2:3 poster means a
    title. 16:9 still means an episode or a moment inside a title. 1:1 means a
    brand. The user reads the shape before they read the text.

11. **Chrome recedes when content arrives.** Netflix's rail sits at the lowest
    contrast the design allows. Apple dims everything behind the drawer. Plex is
    the exception and pays for it with a busier screen, which is the trade it
    made deliberately to be a librarian.

## Part three: where Watchools cannot follow

This is the part that matters, because copying the eleven rules onto an IPTV
client produces a broken product. Three of the references' load-bearing
assumptions are false here.

**They own their artwork. We do not.** Netflix commissions key art at four
aspect ratios per title. Plex fetches from TMDB and lets you correct it. Our
artwork arrives from a provider's playlist: a channel logo that is 1:1, often
120 pixels wide, often a JPEG with a white background, and for a meaningful
fraction of channels absent entirely. **A design that collapses without artwork
is not shippable here.** Rule 1 of the references (artwork is the interface)
inverts into our first rule: artwork earns its place or typography takes it.

**They have one row per title. We have one row per moment.** Netflix's unit is a
title, which is stable: `Stranger Things` is the same object all day. Our unit
on the live screen is a channel, and a channel is a *different object every
forty minutes*. The interesting content is not the channel, it is what is on it
now and what is on it next. **The now is our key art.** This is the single
largest divergence and the thing that separates a real IPTV client from a
Netflix skin with an M3U parser.

**They assume metadata exists. We assume it might not.** EPG coverage across a
typical provider is partial: some channels have a full seven day schedule, some
have today, many have nothing. A layout that only works with a programme title
is a layout that shows blank rows for a third of the list. Rule 6 (missing data
occupies its slot) is not a nicety here, it is the primary case.

Two smaller ones. Netflix and Plex both have a *finite curated* catalogue where
scrolling is browsing. An IPTV provider ships six to twenty thousand channels,
where scrolling is futile and **search and grouping are the only real
navigation**. And all three references have a login that is theirs; ours is a
third party credential that expires, gets throttled, and goes unreachable, so
**the failure states are a design surface, not an afterthought**.

## Part four: the doctrine

Seven rules for this product. The references' eleven still hold underneath;
these are what we add and where we depart.

1. **The now is the artwork.** On the live screen the emphasised object is the
   programme currently airing, not the channel carrying it. The channel is the
   attribution line. Progress through the current programme is the one piece of
   real time information no competitor's static grid gives you, and it goes
   where the references put progress: a thin bar along the bottom edge.

2. **Artwork earns its place.** A channel logo is shown when it is present and
   legible, and replaced by a typographic mark when it is not, at the same size
   and in the same slot. The mark is derived (initials from the channel name,
   noise words stripped) so it is stable across sessions. A screen must look
   deliberate with every logo missing.

3. **No EPG is a state, not a gap.** A channel with no schedule gets a designed
   row that says so, in the same height as a row that has one. The count of such
   channels is surfaced, because the user's next action is to change provider
   settings, and they cannot decide that without the number.

4. **One primary verb, and it is amber.** Adopted unchanged. Our accent is
   spoken for by exactly three things: the primary action, progress, and live
   status. It is never a focus colour, never a hover colour, never a border.

5. **Focus is a lift and a ring, and it never collapses with selection.** A TV
   remote moves focus without changing selection, so the two must be visually
   distinct or the user cannot tell where they are. Selection is a fill or a
   left accent bar. Focus is a ring plus a lift. This is already written into
   the status tokens and the references confirm it.

6. **Search is a peer of navigation, not a mode.** Plex keeps a 470 pixel field
   in the top bar at all times. With twenty thousand channels we need it more
   than Plex does. It is never behind an icon on a surface wider than a phone.

7. **Technical truth is a feature.** Plex's `Video / Ses / Altyazılar` table is
   the single most transplantable thing in the references, because our audience
   is the one that cares: source URL health, resolution, codec, audio track,
   subtitle track, and which provider a title came from when several are
   configured. It goes in the label-value stack, where they put it.

## What this rules out

Stated plainly so the alternatives can be judged against it.

- A screen whose hierarchy depends on posters being present.
- A channel row whose main text is the channel name.
- A focus treatment that fills with the accent colour.
- Two filled buttons in one view.
- A percentage number anywhere a progress bar would do.
- An empty section that renders as nothing.
- A search field behind an icon above the `sm` breakpoint.
- A layout that shows a blank cell where the EPG is missing.
