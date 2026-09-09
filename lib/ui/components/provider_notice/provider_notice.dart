import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/models/provider_fault.dart';
import 'provider_notice.recipe.dart';

/// What a browse screen shows when the provider is the problem.
///
/// One component for all three surfaces, unlike `GuideEmpty` and
/// `LibraryEmpty`, and that is the point: an empty result means something
/// different on a line-up than in a catalogue, while an unreachable host means
/// exactly the same thing everywhere. Splitting it would be three copies of one
/// sentence drifting apart.
///
/// Three parts, in the order the reader needs them. What happened, in their
/// words. Why they are seeing it and what it implies. Then the one action that
/// can change it, which is the part a generic error screen leaves out and the
/// reason [ProviderFault] is three values.
///
/// The action is a retry for two of the three faults and the route to the
/// provider's credentials for the third, and the widget chooses rather than the
/// caller. Both callbacks are required so the choice cannot be half wired: a
/// panel offering "Yeniden dene" for a lapsed subscription fails identically
/// every time and teaches the user that the app is broken rather than that
/// their subscription is.
///
/// It goes where `GuideEmpty` goes: inside the body branch, under the pinned
/// toolbar. That position is load-bearing rather than tidy, for the reason
/// CLAUDE.md's fifth layout trap records at length, and it also keeps the
/// search field and the category strip reachable so a fault does not strand the
/// user on a screen with no way off it.
///
/// ### Example
/// ```dart
/// ProviderNotice(
///   fault: ProviderFault.unreachable,
///   detail: 'HTTP 502, tr.example-provider.com',
///   onRetry: controller.reload,
///   onOpenSettings: () => MagicRoute.to('/saglayici'),
/// )
/// ```
@immutable
class ProviderNotice extends StatelessWidget {
  /// Which fault to explain.
  final ProviderFault fault;

  /// What the provider actually said: a status code, a host, a rejection body.
  ///
  /// Doctrine rule 7, and null when there is nothing true to put here. The user
  /// cannot act on `HTTP 502`, but whoever they ask for help can, and a panel
  /// that hides it makes that conversation start with "it says something went
  /// wrong". Rendered as no line at all when absent rather than as an empty
  /// one, which would occupy its slot and read as a render fault.
  final String? detail;

  /// Asks for the request to be made again. Used for every fault a retry can
  /// fix, which is all of them except [ProviderFault.expired].
  final VoidCallback onRetry;

  /// Takes the user to their provider credentials. Used for
  /// [ProviderFault.expired] alone.
  final VoidCallback onOpenSettings;

  /// Creates a [ProviderNotice].
  const ProviderNotice({
    super.key,
    required this.fault,
    required this.onRetry,
    required this.onOpenSettings,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Resolve the per-fault slot classNames.
    final Map<String, String> slots = providerNoticeRecipe()(variants: <String, String?>{'fault': fault.name});

    // 2. Pick the copy and the verb. Exhaustive on purpose: a fourth fault has
    //    to answer all four questions here before it can compile.
    final (IconData icon, String title, String body, String verb) said = switch (fault) {
      ProviderFault.unreachable => (
        Icons.cloud_off_outlined,
        'Sağlayıcıya ulaşılamıyor',
        'Sunucu yanıt vermedi. Bağlantınız veya sağlayıcının sunucusu geçici '
            'olarak kapalı olabilir.',
        'Yeniden dene',
      ),
      ProviderFault.expired => (
        Icons.key_off_outlined,
        'Abonelik bilgileri geçersiz',
        'Sağlayıcı bilgilerinizi kabul etmedi. Aboneliğinizin süresi dolmuş '
            'olabilir; yeniden denemek bunu düzeltmez.',
        'Bilgileri güncelle',
      ),
      ProviderFault.throttled => (
        Icons.hourglass_empty_outlined,
        'Sağlayıcı şu an yanıt vermiyor',
        'Sağlayıcı isteklerinizi hız sınırına takıldığı için reddediyor. '
            'Birkaç saniye içinde tekrar deneyin.',
        'Yeniden dene',
      ),
      ProviderFault.evicted => (
        Icons.devices_other_outlined,
        'Aboneliğiniz başka bir cihazda açık',
        'Bağlantı sınırına ulaşıldı. Aboneliğiniz başka bir cihazda açık '
            'olabilir; bilgilerinizde bir sorun yok.',
        'Bağlantıyı devral',
      ),
    };

    return WDiv(
      className: slots['box'],
      children: <Widget>[
        WDiv(
          className: slots['disc'],
          child: WIcon(said.$1, className: slots['icon']),
        ),
        WText(said.$2, className: slots['title']),
        WText(said.$3, className: slots['body']),
        if (detail != null) WText(detail!, className: slots['detail']),
        WDiv(
          className: 'shrink-0',
          child: WAnchor(
            onTap: fault == ProviderFault.expired ? onOpenSettings : onRetry,
            semanticLabel: said.$4,
            child: WDiv(
              className: slots['action'],
              child: WText(said.$4, className: 'text-sm font-bold'),
            ),
          ),
        ),
      ],
    );
  }
}
