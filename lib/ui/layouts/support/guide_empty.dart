import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/controllers/guide_controller.dart';

/// What the line-up shows when nothing matches.
///
/// Two states, not one. "No results" after a search is a dead end and says so;
/// an empty favourites list is an invitation and says how to fill it. Rendering
/// the same sentence for both is the version of this screen that teaches the
/// user nothing.
@immutable
class GuideEmpty extends StatelessWidget {
  /// The shared line-up state.
  final GuideController controller;

  /// Creates the [GuideEmpty].
  const GuideEmpty({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final bool favouritesEmpty = controller.group == 'Favoriler' && controller.query.isEmpty;

    return WDiv(
      className: 'flex flex-col items-center justify-center gap-3 h-full px-8',
      children: <Widget>[
        WIcon(
          favouritesEmpty ? Icons.star_outline_rounded : Icons.search_off_outlined,
          className: 'text-3xl text-fg-disabled',
        ),
        WText(favouritesEmpty ? 'Henüz favori yok' : 'Sonuç yok', className: 'text-base font-semibold text-fg'),
        WText(
          favouritesEmpty
              ? 'Listedeki yıldıza dokunarak kanalları buraya ekleyin.'
              : 'Arama terimini değiştirin veya başka bir kategori seçin.',
          className: 'text-sm text-fg-muted text-center',
        ),
      ],
    );
  }
}
