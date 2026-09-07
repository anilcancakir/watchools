// Hand-authored playback status supplement.
//
// `design:sync` emits only the 17 standard semantic roles; its alias mapping is
// hardcoded and never includes a status family. This file carries the four
// playback states as Wind className tokens so a view can write `bg-live`,
// `text-catchup-soft-foreground` and so on directly.
//
// Hex values mirror the `colors:` reference block in DESIGN.md. Change one and
// change the other, or the document stops describing the product.
//
// Merged into the alias map in `lib/main.dart`:
//   WindThemeData(aliases: {...designAliases, ...watchoolsStatusAliases})
//
// Wind's alias expander matches a whole token, prefixed or not, against a key,
// so every value is a `'<util>-[#light] dark:<util>-[#dark]'` pair.

/// Playback status className aliases, four tokens per state.
///
/// For each state `s` in live / recording / catchup / epg-now:
/// - `bg-<s>` and `text-<s>`: the solid tone, for a filled badge or a dot.
/// - `bg-<s>-soft`: the quiet badge background.
/// - `text-<s>-soft-foreground`: the label on that soft background.
///
/// Every foreground clears WCAG AA against its own soft background: live 7.7:1
/// light and 8.2:1 dark, catch-up 5.9:1 and 9.9:1, EPG-now 5.3:1 and 10.2:1.
///
/// `live` and `recording` share a red on purpose and are told apart by form,
/// not hue: live is a filled badge carrying the word, recording is a dot. Both
/// keys exist so that separating them later is a one-line change here rather
/// than a search through every view.
const Map<String, String> watchoolsStatusAliases = <String, String>{
  // live: on air right now. Red is unclaimed by the brand precisely so it can
  // mean this and nothing else.
  'bg-live': 'bg-[#C62222] dark:bg-[#E83730]',
  'text-live': 'text-[#C62222] dark:text-[#E83730]',
  'border-color-live': 'border-[#C62222] dark:border-[#E83730]',
  'bg-live-soft': 'bg-[#FDE3E2] dark:bg-[#33100F]',
  'text-live-soft-foreground': 'text-[#8E100B] dark:text-[#F79A97]',

  // recording: same red as live, different form.
  'bg-recording': 'bg-[#C62222] dark:bg-[#E83730]',
  'text-recording': 'text-[#C62222] dark:text-[#E83730]',
  'border-color-recording': 'border-[#C62222] dark:border-[#E83730]',
  'bg-recording-soft': 'bg-[#FDE3E2] dark:bg-[#33100F]',
  'text-recording-soft-foreground': 'text-[#8E100B] dark:text-[#F79A97]',

  // catchup: already aired, still replayable. Blue reads as "available" rather
  // than "happening", which is the distinction that matters in a guide.
  'bg-catchup': 'bg-[#0369A1] dark:bg-[#30ABE8]',
  'text-catchup': 'text-[#0369A1] dark:text-[#30ABE8]',
  'border-color-catchup': 'border-[#0369A1] dark:border-[#30ABE8]',
  'bg-catchup-soft': 'bg-[#E2F4FD] dark:bg-[#0F2733]',
  'text-catchup-soft-foreground': 'text-[#0B628E] dark:text-[#97D7F7]',

  // epg-now: the programme occupying the current time slot. Equals `primary`,
  // because "where you are in the guide" is the one status that is about the
  // product rather than about the stream.
  'bg-epg-now': 'bg-[#A36200] dark:bg-[#F59B14]',
  'text-epg-now': 'text-[#A36200] dark:text-[#F59B14]',
  'border-color-epg-now': 'border-[#A36200] dark:border-[#F59B14]',
  'bg-epg-now-soft': 'bg-[#FDF2E2] dark:bg-[#33250F]',
  'text-epg-now-soft-foreground': 'text-[#8E5A0B] dark:text-[#F7D097]',

  // The neutral chip that facts live in: resolution, codec, audio channels.
  // Plex's discipline, and the reason it works: a row where every chip is
  // coloured is a row where no chip means anything. Only state gets colour.
  'bg-fact': 'bg-[#EAEDF0] dark:bg-[#1C1F23]',
  'text-fact': 'text-[#4A5058] dark:text-[#C4CAD1]',

  // Three roles `design:sync` does not emit, each of which was silently
  // resolving to the wrong thing until an audit caught it.
  //
  // `text-primary` had no alias, so it fell through the alias table to
  // `designColors['primary']`, which is a single `MaterialColor` seeded on the
  // LIGHT gold `#A36200` with no `dark:` half. Every gold label in the app was
  // rendering the light value on a dark surface, roughly 4:1 and under the 4.5
  // floor the rest of this palette is tested against, while `bg-primary` beside
  // it correctly rendered `#F59B14`.
  //
  // `ring-*` resolves through a separate map from `border-*`, and Wind's ring
  // colour regex (`^ring-(?<color>[a-zA-Z]+)(?:-(?<shade>[0-9]+))?$`) cannot
  // match a hyphenated name at all. `focus:ring-focus-ring` therefore set only
  // the width, and the colour came from `WindThemeData.ringColor`, whose
  // default is Tailwind blue-500: every focus ring in the app was `#3B82F6`,
  // identical in both modes, and plausible enough on screen to survive review.
  'text-primary': 'text-[#A36200] dark:text-[#F59B14]',
  'bg-primary-hover': 'bg-[#8F5600] dark:bg-[#FAB338]',
  'ring-focus-ring': 'ring-[#1D6FD0] dark:ring-[#7FB2FF]',

  // The scrim, for a control that sits on top of artwork.
  //
  // Neither `surface` nor `surface-container` works there: a chip over a still
  // has to darken whatever is behind it rather than replace it, and the still
  // is a photograph whose brightness we do not control. Translucent black in
  // both modes, because a light scrim over a light image reads as a smudge
  // while black reads as shade in either.
  //
  // Two weights. `scrim` is enough behind an icon, `scrim-strong` is what a
  // line of text needs to clear AA over an arbitrary frame.
  //
  // The opacity is an `/NN` modifier rather than an eight-digit hex, and the
  // difference is not cosmetic: Wind's `bg-[...]` regex admits only three or
  // six hex digits, so `bg-[#00000073]` matched nothing and resolved to no
  // background at all. `border-[...]` accepts eight, and `ring-[...]` accepts
  // three to eight, which is why the shape of this looked obviously fine.
  // Caught by `test/config/token_resolution_test.dart`, which exists because
  // `flutter analyze` cannot see any of this.
  'bg-scrim': 'bg-[#000000]/45 dark:bg-[#000000]/45',
  'bg-scrim-strong': 'bg-[#000000]/72 dark:bg-[#000000]/72',

  // The inverted surface, for the one thing the user is pointed at.
  //
  // Plex fills its focused guide block white and flips the text to near-black
  // (`--color-highlight-focus: #fff`, `--color-text-on-focus: #1c1c1c`). It is
  // the strongest signal in their whole system and it costs no new hue, which
  // matters here because gold, red and blue are all already spoken for.
  //
  // There is no `bg-fg`: the generated table names the text role `text-fg` and
  // nothing else, so the surface form has to be declared.
  'bg-inverse': 'bg-[#0E0F11] dark:bg-[#F2F4F6]',
  'text-on-inverse': 'text-[#FAFAFB] dark:text-[#0E0F11]',

  // Focus, deliberately not the brand colour. On a D-pad surface focus moves on
  // every keypress and selection does not, so a user who cannot tell "where am
  // I" from "what is chosen" is lost. Plex separates these for the same reason.
  'border-color-focus-ring': 'border-[#1D6FD0] dark:border-[#7FB2FF]',
  'text-focus-ring': 'text-[#1D6FD0] dark:text-[#7FB2FF]',
  'bg-focus-ring': 'bg-[#1D6FD0] dark:bg-[#7FB2FF]',
};
