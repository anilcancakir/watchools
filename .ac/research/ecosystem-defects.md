# Ecosystem defects found building the design phase

Seven defects in the sibling packages, each reproduced against a specific line
and each currently worked around in this app with a comment at the site. Per
`.claude/rules/workflow.md` the fix belongs in the sibling, on its own branch,
with its own CI green, following that repository's own rules.

Ordered by how much they cost a consumer who does not know about them.

## 1. `wind`: a clipping row steals the grow share from its own flex child

`lib/src/widgets/w_div.dart:704`

```dart
final bool hasGrowingChild = basisChildren.any(_claimsGrowShare);
final needsFlexible =
    ((needsSpaceDistribution && !hasGrowingChild) || hasOverflowClip) &&
        !isMainAxisScrollable;
```

The `!hasGrowingChild` guard applies only to the `justify-*` branch. With
`overflow-hidden`, every sibling without `shrink-0` is wrapped in a bare
`Flexible(child)`, which defaults to `flex: 1`, so it claims an equal share
against a sibling that actually asked for the space.

**Measured**, in `ChannelRow`: a 4 pixel accent bar and a 44 pixel number column
each took a third of 318 free pixels, the identity column got 106 instead of
270, and 164 pixels went unallocated. The comment immediately above that line
describes this exact failure as already fixed for the other branch.

**Fix**: extend the guard to the clip branch. `overflow-hidden` asks for
shrinking, and a child that grows leaves nothing to shrink.

**Local workaround**: `shrink-0` on every fixed-width sibling of a clipping row.

## 2. `wind`: `shrink-0` is honoured on two widget types only

`lib/src/widgets/w_div.dart:750`

The skip list type-checks `child is WDiv` and `child is WText`. A `WAnchor`
carrying `shrink-0` is still wrapped in a `Flexible`, and `WButton`, `WInput`,
`WImage` and the rest are in the same position. `_extractChildClassName` already
reads the className off ANY Wind widget dynamically two lines away, so the
narrow check looks like an oversight rather than a decision.

**Local workaround**: wrap the anchor in `WDiv(className: 'shrink-0', ...)`.

## 3. `wind`: the display family resolves first-wins, against its own docs

`lib/src/parser/parsers/flexbox_grid_parser.dart:239`

```dart
if (displayType == null && _displayMap.containsKey(className)) {
```

Guarding on `displayType == null` means the FIRST display token wins, while
Wind's documented rule is that the last class in a parser family wins. So
`flex flex-row items-center wrap` takes `flex` and silently discards `wrap`, and
the row can never wrap. Five rows in this app were affected.

**Fix**: assign unconditionally, matching the documented rule and every other
family.

**Local workaround**: write `wrap` with no `flex` beside it.

## 4. `wind`: three hardcoded light greys with no dark peer

- `lib/src/parser/parsers/border_parser.dart:221` —
  `final defaultColor = color ?? const Color(0xFFE5E7EB); // gray-200`
- `lib/src/widgets/w_input.dart:291` —
  `static const Color _defaultBorderColor = Color(0xFFD1D5DB);`, painted by
  `_buildDecoration` whenever the className resolves no border
- `lib/src/theme/wind_theme_data.dart:191` —
  `this.ringColor = const Color(0xFF3B82F6), // Tailwind blue-500`

Each renders identically in light and dark, so a dark-first consumer gets a
bright hairline or a blue focus ring and nothing says why. `border-transparent`
makes the first one worse: it matches `_borderColorRegex` with `shade`
defaulting to 500, but `transparent` in the palette is a plain `Color` rather
than a shade map, so `isValidColor` fails and the near-white is used.

**Fix**: resolve all three from the theme, and make `border-transparent`
resolve to `Colors.transparent`.

## 5. `wind`: `bg-[...]` rejects the 8-digit hex that `border-[...]` accepts

- `background_parser.dart:25` — `#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})`
- `border_parser.dart:38` — 3, 4, 6 **or 8**
- `ring_parser.dart:35` and `shadow_parser.dart:25` — 3 **to** 8
- `text_parser.dart:36` and `:84` — 3 or 6

So `bg-[#00000073]` resolves to no background at all while
`border-[#00000073]` works, and nothing warns. The `/NN` opacity modifier is a
working alternative, which makes this a consistency bug rather than a missing
feature.

**Fix**: one shared arbitrary-colour pattern across the parsers.

## 6. `wind`: the ring colour regex cannot match a hyphenated alias

`lib/src/parser/parsers/ring_parser.dart:29`

```dart
r'^ring-(?<color>[a-zA-Z]+)(?:-(?<shade>[0-9]+))?$'
```

`ring-focus-ring` cannot match, so only the width applies and the colour falls
back to `WindThemeData.ringColor`. `ring-*` and `border-*` also resolve through
separate maps, so a `border-color-x` alias does not give you `ring-x`; both have
to be declared.

**Fix**: admit a hyphenated colour name, as the border parser's alias path does.

## 7. `wind` docs: `n-{n}` is documented and not implemented

`doc/typography/text-overflow.md` lists `n-{n}` mapping to `maxLines: n` plus an
ellipsis. `text_parser.dart` implements `line-clamp-{n}` and nothing else, so
nine texts in this app had no `maxLines` and no ellipsis and the analyser could
not see it.

**Fix**: correct the doc, or implement the alias.

## 8. `magic`: the loading placeholder has no route table

`lib/src/foundation/magic_app_widget.dart:243`

While `!_initialized`, `MagicApplication` renders a plain
`MaterialApp(home: ...)` with no `routes` or `onGenerateRoute`, so the
platform's initial route cannot be matched and Flutter logs "Could not navigate
to initial route" for a path the app does serve. `MaterialApp.router` then takes
over and routes correctly, so it is cosmetic, but it fires on every load whose
URL is not the root and it is noise in any exception gate.

**Fix**: an `onUnknownRoute` on the placeholder that returns the same
placeholder.

---

## Gaps rather than defects

Already recorded in `CLAUDE.md` and unchanged: no D-pad activation in `WAnchor`,
no focus traversal policy, no virtualised list behind `overflow-*`, and no TV
form-factor axis. Add to those a fifth, found here: **Wind has no custom
gradient stops**, so a three-stop scrim ramp cannot be expressed in a className
and the eight scrims in this app are raw `LinearGradient`s with the dark half of
`bg-surface` hand-copied into them.
