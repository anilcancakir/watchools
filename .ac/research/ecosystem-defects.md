# Ecosystem defects found building the design phase

Seven defects in the sibling packages, each reproduced against a specific line
and each currently worked around in this app with a comment at the site. Per
`.claude/rules/workflow.md` the fix belongs in the sibling, on its own branch,
with its own CI green, following that repository's own rules.

Ordered by how much they cost a consumer who does not know about them.

**Four entries were retracted after a review read the sibling source rather than
this file.** They are kept at the bottom under `Retracted`, with what was
actually true, because a defect list that only ever grows is a list nobody
trusts and because three of them had already been quoted as fact in code
comments here.

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

**Measured**, in a `ChannelRow` component this repository no longer has (it went
with the `Kule` layout, its only consumer): a 4 pixel accent bar and a 44 pixel
number column each took a third of 318 free pixels, the identity column got 106
instead of 270, and 164 pixels went unallocated. The comment immediately above
that line describes this exact failure as already fixed for the other branch.
The defect is in `wind` and is unaffected by the component going.

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

## 3. `wind`: three hardcoded light greys with no dark peer

- `lib/src/parser/parsers/border_parser.dart:221`:
  `final defaultColor = color ?? const Color(0xFFE5E7EB); // gray-200`
- `lib/src/widgets/w_input.dart:291`:
  `static const Color _defaultBorderColor = Color(0xFFD1D5DB);`, painted by
  `_buildDecoration` whenever the className resolves no border
- `lib/src/theme/wind_theme_data.dart:191`:
  `this.ringColor = const Color(0xFF3B82F6), // Tailwind blue-500`

Each renders identically in light and dark, so a dark-first consumer gets a
bright hairline or a blue focus ring and nothing says why. `border-transparent`
makes the first one worse: it matches `_borderColorRegex` with `shade`
defaulting to 500, but `transparent` in the palette is a plain `Color` rather
than a shade map, so `isValidColor` fails and the near-white is used.

**Fix**: resolve all three from the theme, and make `border-transparent`
resolve to `Colors.transparent`.

## 4. `wind`: `bg-[...]` rejects the 8-digit hex that `border-[...]` accepts

- `background_parser.dart:25`: `#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})`
- `border_parser.dart:38`: 3, 4, 6 **or 8**
- `ring_parser.dart:35` and `shadow_parser.dart:25`: 3 **to** 8
- `text_parser.dart:36` and `:84`: 3 or 6

So `bg-[#00000073]` resolves to no background at all while
`border-[#00000073]` works, and nothing warns. The `/NN` opacity modifier is a
working alternative, which makes this a consistency bug rather than a missing
feature.

**Fix**: one shared arbitrary-colour pattern across the parsers.

## 5. `wind`: the ring colour regex cannot match a hyphenated alias

`lib/src/parser/parsers/ring_parser.dart:29`

```dart
r'^ring-(?<color>[a-zA-Z]+)(?:-(?<shade>[0-9]+))?$'
```

`ring-focus-ring` cannot match, so only the width applies and the colour falls
back to `WindThemeData.ringColor`. `ring-*` and `border-*` also resolve through
separate maps, so a `border-color-x` alias does not give you `ring-x`; both have
to be declared.

**Fix**: admit a hyphenated colour name, as the border parser's alias path does.

## 6. `magic`: the loading placeholder has no route table

`lib/src/foundation/magic_app_widget.dart:243`

While `!_initialized`, `MagicApplication` renders a plain
`MaterialApp(home: ...)` with no `routes` or `onGenerateRoute`, so the
platform's initial route cannot be matched and Flutter logs "Could not navigate
to initial route" for a path the app does serve. `MaterialApp.router` then takes
over and routes correctly, so it is cosmetic, but it fires on every load whose
URL is not the root and it is noise in any exception gate.

**Fix**: an `onUnknownRoute` on the placeholder that returns the same
placeholder.

## 7. `wind`: `WInput` paints a hairline unless the width is zero

`lib/src/widgets/w_input.dart:758`

```dart
if (parsed?.border is Border) {
  final Border b = parsed!.border as Border;
  border = b.top.width == 0 ? null : b;
} else {
  border = Border.all(color: _defaultBorderColor, width: _defaultBorderWidth);
}
```

Only a zero WIDTH drops the border. `border-transparent` takes the first branch
and, through defect 3, resolves to a near-white `#E5E7EB` rather than to
nothing, so a field written to have no border gets the most visible one in the
app. Every search field in this app rendered a bright rounded rectangle on a
dark surface until `border-transparent` was changed to `border-0`.

**Fix**: honour a transparent colour as well as a zero width, and resolve
`_defaultBorderColor` from the theme.

---

## Retracted

Four entries that were here and should not have been. Each was written from a
symptom this app really hit, and each named a mechanism that the sibling source
does not contain. Kept so the same misreading does not get filed twice.

**`wind`: the display family resolves first-wins.** It does not.
`flexbox_grid_parser.dart:226` is `for (var i = classes.length - 1; i >= 0; i--)`,
so the loop runs BACKWARDS and the `displayType == null` guard implements
last-class-wins, which is the documented rule and the same pattern every other
family in that method uses. `flex flex-row items-center wrap` resolves both a
wrap and a horizontal direction, and `_buildWrapStructure` consumes both. The
rows that would not wrap were written `wrap` first and `flex` after, which is
last-class-wins working correctly. Writing `wrap` alone is still the right code;
it is just not a workaround for anything.

**`wind` docs: `n-{n}` is documented and not implemented.** The doc has no such
entry. `doc/typography/text-overflow.md:55` reads
`| line-clamp-{n} | maxLines: n, overflow: ellipsis |`, which is implemented at
`text_parser.dart:117`. This was a table cell misread. The nine texts that had
no `maxLines` had none because they were written with a token this app invented,
not because the doc promised one.

**`wind`: `w-full` inside a `flex-1` brings down a route change.** The crash was
real and removing the `w-full` removed it, but the stated mechanism is not the
code: `w_div.dart:1639` says "w-full: SizedBox(width: infinity), no LayoutBuilder
needed" and `:1686` does exactly that. `FractionallySizedBox` is the `w-1/2`
branch and is never reached on the width-only path. `w-full` sits under a
`flex-1` in six other places in this app and nothing crashes in any of them, so
whatever the collection direction hit is not "`w-full` under a tight parent".
Reproduce it before filing it again.

**`dusk`: `exceptions --clear` empties half the store.** It empties dusk's own
buffer, which is all it claims to own: `ext_exceptions.dart` states that "a
wired telescope owns its own store". The surviving entries are telescope's, and
the fix, if one is wanted, is a clear on telescope rather than a change to dusk.
The walks reset by hot-restarting, so nothing here depends on it.

**`dusk`: `dusk:navigate` reports success for a route that does not exist.**
`dusk:navigate --route /preview` printed `✓ Navigated to /preview` against a
build where `/preview` had never been registered, and `dusk:get_routes` in the
same breath reported `location: "/"`. The screen stayed on the live line-up. It
cost half an hour of chasing a registration that was in fact absent, because the
one tool that could have said so was agreeing with the mistake. `dusk:tap`
already solves this: it returns an `effect: {kind: "treeChanged", changed:
bool}` block precisely so a caller can tell a no-op from an action. `navigate`
needs the same, or simply to compare the location before and after and report
what it found. Local opt-out: read `dusk:get_routes` after every navigate and
believe that instead.

**`artisan`: `tinker --eval` cannot evaluate against a web app.** Every
expression comes back as
`evaluate: (-32603) NoSuchMethodError: Class 'WebSocketProxyService' has no
instance method 'evaluate' with matching arguments`, and the error prints a
`Tried calling:` and a `Found:` signature that read as identical, so it looks
like a version skew between the bundled `vm_service` and the proxy rather than a
call-site bug. Reproduced twice, on `kDebugMode` and on a static field read.
**Not investigated further**, so treat the cause as unknown; `dusk:snap` plus
`dusk:get_routes` answered the question that sent me there. Worth pinning down
before anything relies on state inspection, because it takes the whole tinker
surface out on the one platform this app is developed against.

---

## Gaps rather than defects

Already recorded in `CLAUDE.md` and unchanged: no D-pad activation in `WAnchor`,
no focus traversal policy, no virtualised list behind `overflow-*`, and no TV
form-factor axis. Add to those a fifth, found here: **Wind has no custom
gradient stops**, so a three-stop scrim ramp cannot be expressed in a className
and the eight scrims in this app are raw `LinearGradient`s with the dark half of
`bg-surface` hand-copied into them.
