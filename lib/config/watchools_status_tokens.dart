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
  'bg-live-soft': 'bg-[#FDE3E2] dark:bg-[#33100F]',
  'text-live-soft-foreground': 'text-[#8E100B] dark:text-[#F79A97]',

  // recording: same red as live, different form.
  'bg-recording': 'bg-[#C62222] dark:bg-[#E83730]',
  'text-recording': 'text-[#C62222] dark:text-[#E83730]',
  'bg-recording-soft': 'bg-[#FDE3E2] dark:bg-[#33100F]',
  'text-recording-soft-foreground': 'text-[#8E100B] dark:text-[#F79A97]',

  // catchup: already aired, still replayable. Blue reads as "available" rather
  // than "happening", which is the distinction that matters in a guide.
  'bg-catchup': 'bg-[#0369A1] dark:bg-[#30ABE8]',
  'text-catchup': 'text-[#0369A1] dark:text-[#30ABE8]',
  'bg-catchup-soft': 'bg-[#E2F4FD] dark:bg-[#0F2733]',
  'text-catchup-soft-foreground': 'text-[#0B628E] dark:text-[#97D7F7]',

  // epg-now: the programme occupying the current time slot. Equals `primary`,
  // because "where you are in the guide" is the one status that is about the
  // product rather than about the stream.
  'bg-epg-now': 'bg-[#A36200] dark:bg-[#F59B14]',
  'text-epg-now': 'text-[#A36200] dark:text-[#F59B14]',
  'bg-epg-now-soft': 'bg-[#FDF2E2] dark:bg-[#33250F]',
  'text-epg-now-soft-foreground': 'text-[#8E5A0B] dark:text-[#F7D097]',

  // The neutral chip that facts live in: resolution, codec, audio channels.
  // Plex's discipline, and the reason it works: a row where every chip is
  // coloured is a row where no chip means anything. Only state gets colour.
  'bg-fact': 'bg-[#EAEDF0] dark:bg-[#1C1F23]',
  'text-fact': 'text-[#4A5058] dark:text-[#C4CAD1]',

  // Focus, deliberately not the brand colour. On a D-pad surface focus moves on
  // every keypress and selection does not, so a user who cannot tell "where am
  // I" from "what is chosen" is lost. Plex separates these for the same reason.
  'border-color-focus-ring': 'border-[#1D6FD0] dark:border-[#7FB2FF]',
  'text-focus-ring': 'text-[#1D6FD0] dark:text-[#7FB2FF]',
  'bg-focus-ring': 'bg-[#1D6FD0] dark:bg-[#7FB2FF]',
};
