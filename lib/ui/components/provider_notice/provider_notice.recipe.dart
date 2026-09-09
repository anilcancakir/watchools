import 'package:magic/magic.dart';

/// Builds the [WindSlotRecipe] for the ProviderNotice component.
///
/// One axis, `fault`, and it moves exactly one slot: the disc behind the icon.
/// The panel's box, its type scale and its button are identical for all three,
/// because what separates them is what the copy says and what the button does,
/// not how loud the panel is.
///
/// The severity lives in the DISC rather than in the glyph, and that is forced
/// rather than chosen. This palette has `bg-destructive`,
/// `bg-destructive-container` and `text-on-destructive` and no
/// `text-destructive`: `destructive` is defined in DESIGN.md as a button colour
/// (`button-destructive`, a background plus its foreground), so a
/// destructive-tinted glyph cannot be written at all and `text-destructive`
/// would resolve to nothing while looking deliberate. Enclosing the icon is the
/// shape that says the same thing with the tokens that exist, and it says it
/// louder.
///
/// `warning` would have been the obvious tint and is unusable here. In dark
/// mode it is #F0A93A against `primary` #F59B14 and `accent` #FAB338: three
/// ambers nobody can tell apart, so a warning-tinted panel sitting directly
/// above an amber primary button reads as part of the button. Doctrine rule 4
/// reserves that amber for the primary action, progress and live status, and
/// this is the case that shows the palette leaves no room to bend it.
///
/// Only `expired` is tinted. The other three keep the neutral disc, because
/// they are conditions rather than faults in the user's setup and a red panel
/// for a provider that dropped a connection is the app blaming the user for
/// the weather. `evicted` falls on that same side: the credential is fine and
/// the account is fully alive, just booked on another device right now, so it
/// reads as busy rather than as broken.
WindSlotRecipe providerNoticeRecipe() {
  return const WindSlotRecipe(
    slots: <String, String>{
      // Centred in whatever the body branch gives it, which is the same box
      // `GuideEmpty` fills. `px-8` keeps the explanation off the edge on a
      // phone, where this panel is nearly the whole screen.
      'box': 'flex flex-col items-center justify-center gap-3 h-full w-full px-8',
      'disc': 'flex items-center justify-center size-14 rounded-full shrink-0',
      'icon': 'text-2xl text-fg',
      'title': 'text-base font-semibold text-fg text-center',
      'body': 'text-sm text-fg-muted text-center',
      // `disabled` rather than `muted`, so the line reads as a reference for
      // whoever the user asks for help rather than as part of the explanation
      // they are meant to act on.
      'detail': 'text-xs text-fg-disabled text-center',
      'action': '''
        flex flex-row items-center gap-2
        h-11 px-6 rounded-full
        bg-primary text-on-primary
        hover:bg-primary-hover
        focus:ring-2 focus:ring-focus-ring
      ''',
    },
    variants: <String, Map<String, Map<String, String>>>{
      'fault': <String, Map<String, String>>{
        'unreachable': <String, String>{'disc': 'bg-surface-container-high'},
        'expired': <String, String>{'disc': 'bg-destructive-container'},
        'throttled': <String, String>{'disc': 'bg-surface-container-high'},
        'evicted': <String, String>{'disc': 'bg-surface-container-high'},
      },
    },
    defaultVariants: <String, String>{'fault': 'unreachable'},
  );
}
