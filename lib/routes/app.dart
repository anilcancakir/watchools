import 'package:magic/magic.dart';

import '../resources/views/guide_view.dart';
import '../resources/views/library_view.dart';
import '../resources/views/title_view.dart';

/// Application Route Definitions.
///
/// Register all application routes here. This function is called by
/// [RouteServiceProvider.boot()] during the Magic bootstrap lifecycle.
///
/// `/baslik` carries no identifier yet. There is no data layer, so a title
/// cannot be looked up by id and the screen reads whichever entry the catalogue
/// last selected. It becomes `/baslik/:id` with the Xtream client, at which
/// point the route is deep-linkable and a reload stops losing the selection.
///
/// See also: `lib/app/kernel.dart` for middleware registration.
void registerAppRoutes() {
  MagicRoute.page('/', () => const GuideView()).title('Canlı');
  MagicRoute.page('/kutuphane', () => const LibraryView()).title('Kütüphane');
  MagicRoute.page('/baslik', () => const TitleView()).title('Başlık');
}
