import 'package:magic/magic.dart';

import '../resources/views/guide_view.dart';
import '../resources/views/library_view.dart';
import '../resources/views/playback_view.dart';
import '../resources/views/provider_settings_view.dart';
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
  // `'provider'` (`lib/app/kernel.dart`) sends a credential-less user to
  // `/saglayici` instead of building any of these four: without it,
  // `GuideController.channels` (`guide_controller.dart:227`) and its VOD
  // sibling would still fall back to a fixture nobody can play, silently.
  MagicRoute.page('/', () => const GuideView()).title('Canlı').middleware(['provider']);
  MagicRoute.page('/kutuphane', () => const LibraryView()).title('Kütüphane').middleware(['provider']);
  MagicRoute.page('/baslik', () => const TitleView()).title('Başlık').middleware(['provider']);

  // `/izle` carries no identifier either, and for a sharper reason than
  // `/baslik` does: the controller already holds the channel the user chose,
  // and putting a `streamId` in the path would make a URL that reopens a
  // provider stream on a cold start, before any handshake has said the
  // account is still active. Playback is reached by choosing something, never
  // by arriving at an address.
  MagicRoute.page('/izle', () => const PlaybackView()).title('İzle').middleware(['provider']);

  // `/saglayici` was referenced from five layouts and registered nowhere, so
  // `ProviderNotice`'s action on `expired` fell through to `/` and put the user
  // back on the live screen with the same dead catalogue. A route that is only
  // ever navigated to is silently absent rather than an error, which is what
  // let six call sites accumulate against it. The screen behind it is a
  // placeholder and says so; the form belongs to onboarding, which does not
  // exist yet.
  MagicRoute.page('/saglayici', () => const ProviderSettingsView()).title('Sağlayıcı');
}
