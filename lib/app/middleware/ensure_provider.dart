import 'package:magic/magic.dart';

import '../provider/provider_session.dart';

/// Sends a credential-less user to `/saglayici` instead of the fixture the
/// app would otherwise render.
///
/// The first inhabitant of `lib/app/middleware/`, and that is a deliberate
/// split from `lib/app/{controllers,models,protocol,provider,providers,
/// support}` rather than an accident: a redirect guard is neither a
/// controller nor a provider, and Magic's own convention names this layer
/// `middleware`.
///
/// ## Why this exists
///
/// Today the app boots to `/` unconditionally, and `GuideController.channels`
/// falls back to the 23-channel fixture whenever `ProviderSession.hasCredentials`
/// is false (`guide_controller.dart:227`): a new user sees a catalogue they
/// cannot play and no path to the form that fixes it. This is the guard that
/// closes that gap, ahead of the four routes a real catalogue needs.
///
/// ## `redirectTarget`, not `handle`
///
/// `MagicMiddleware.redirectTarget` is evaluated synchronously inside the
/// router's `redirect` callback, before any page builds
/// (`magic_middleware.dart:47-57`), so the destination mounts exactly once.
/// `handle` runs post-mount and would remount the destination on top of
/// whatever already built, which is the double-mount `handle` exists to warn
/// against.
///
/// ## The loop guard
///
/// `redirectTarget` must return null when `location` already equals the
/// target, "otherwise the redirect loops"
/// (`magic_middleware.dart:56-57`). Handled here, explicitly, ahead of the
/// credential check, even though `MagicRouter._handleRedirect` also drops a
/// target equal to the current location (`magic_router.dart:469`): relying on
/// that would make this guard wrong the day the router's own skip changes,
/// since a location can differ from a route's `fullPath` in ways this class
/// has no visibility into.
class EnsureProvider extends MagicMiddleware {
  @override
  String? redirectTarget(String location) {
    // The loop guard, checked first and unconditionally: the router already
    // resolves `location` from `/saglayici`, so returning the same address a
    // second time is what actually causes the loop, not a rule this class
    // could get away with skipping.
    if (location == '/saglayici') return null;

    // `findOrPut` rather than `find`: a boot ordering bug that runs this
    // guard before `AppServiceProvider.register()` has bound the real
    // session must not throw the app to a blank screen over a route guard.
    // An auto-vivified session has no stored credential and no development
    // seam override, so it reads exactly as "no credential", which is the
    // safe direction for a guard that exists to protect onboarding.
    final ProviderSession session = Magic.findOrPut<ProviderSession>(ProviderSession.new);

    return session.hasCredentials ? null : '/saglayici';
  }
}
