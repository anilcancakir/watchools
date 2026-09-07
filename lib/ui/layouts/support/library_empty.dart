import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../app/controllers/library_controller.dart';

/// What the catalogue shows when nothing matches.
///
/// Four states rather than one, because the four dead ends need four different
/// next actions: a search with no hits, an empty favourites list, nothing part
/// watched yet, and a scope that has nothing in it (a provider that sells only
/// live channels sends an empty VOD catalogue, and that is not an error).
@immutable
class LibraryEmpty extends StatelessWidget {
  /// The shared catalogue state.
  final LibraryController controller;

  /// Creates the [LibraryEmpty].
  const LibraryEmpty({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final (IconData, String, String) state = _state();

    return WDiv(
      className: 'flex flex-col items-center justify-center gap-3 h-full px-8',
      children: <Widget>[
        WIcon(state.$1, className: 'text-3xl text-fg-disabled'),
        WText(state.$2, className: 'text-base font-semibold text-fg'),
        WText(state.$3, className: 'text-sm text-fg-muted text-center'),
      ],
    );
  }

  (IconData, String, String) _state() {
    if (controller.query.isNotEmpty) {
      return (
        Icons.search_off_outlined,
        'Sonuç yok',
        'Arama terimini değiştirin veya kapsamı Tümü olarak seçin.',
      );
    }

    return switch (controller.category) {
      'Favoriler' => (
        Icons.star_outline_rounded,
        'Henüz favori yok',
        'Afişteki yıldıza dokunarak başlıkları buraya ekleyin.',
      ),
      'İzlemeye devam et' => (
        Icons.history_rounded,
        'Yarım kalan bir şey yok',
        'Bir film veya bölüm başlatın, bıraktığınız yer burada görünür.',
      ),
      _ => (
        Icons.video_library_outlined,
        'Bu kapsamda başlık yok',
        'Sağlayıcınız bu bölüm için içerik göndermemiş olabilir.',
      ),
    };
  }
}
