import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:watchools/app/network/resolving_http_overrides.dart';
import 'package:watchools/app/providers/app_service_provider.dart';

/// A host that cannot resolve, anywhere, ever.
///
/// `.invalid` is reserved by RFC 2606 precisely so a test can name a host and
/// be certain no DNS answers for it. That certainty is what makes the
/// assertion below a discriminator: a real attempt throws, and only a mocked
/// stack can return a status code instead.
const String _unresolvable = 'http://nothing.invalid/probe.png';

void main() {
  // Initialised explicitly, and the test below is a plain `test` rather than a
  // `testWidgets`, which is the whole reason this file reads oddly. The binding
  // is what installs the mock `HttpOverrides` this asserts against, so it has to
  // exist; but `testWidgets` runs its body under a FAKE clock, and a real socket
  // never completes there, so the same assertion inside one hangs until the
  // suite's own deadline rather than failing. Measured, on the first version of
  // this file.
  TestWidgetsFlutterBinding.ensureInitialized();

  /// What `flutter_test` installed before this file touched anything.
  HttpOverrides? previousOverrides;

  setUp(() {
    previousOverrides = HttpOverrides.current;

    MagicApp.reset();
    Magic.flush();
  });

  tearDown(() {
    HttpOverrides.global = previousOverrides;
  });

  group('register(), and what it does to the process', () {
    test('leaves the binding able to answer a network image without reaching the network', () async {
      // The regression gate for a hazard that fails QUIETLY. `register()`
      // assigns `HttpOverrides.global`, and the override it installs takes
      // `super.createHttpClient` as its base, which is a REAL client rather
      // than the one `flutter_test` put there to keep tests off the network.
      // So a widget test that boots the provider and renders an
      // `Image.network` would make a genuine outbound request and go green,
      // which is worse than failing: nothing in the run says the isolate
      // started talking to the internet.
      //
      // Asserted through behaviour rather than by comparing override
      // identities, because the identity says nothing about whether a request
      // escapes. A mocked stack answers with a status code; a real one cannot
      // resolve `.invalid` and throws.
      AppServiceProvider(Magic.app).register();

      // The positive half. Without it this test passes unchanged on the day
      // somebody deletes the install entirely, because "the binding still
      // answers 400" is exactly what a process with no override of ours looks
      // like. Asserting both halves is what makes it a gate rather than a
      // description.
      expect(HttpOverrides.current, isA<ResolvingHttpOverrides>());

      final HttpClient client = HttpClient();
      addTearDown(client.close);

      final HttpClientRequest request = await client.getUrl(Uri.parse(_unresolvable));
      final HttpClientResponse response = await request.close();

      expect(
        response.statusCode,
        HttpStatus.badRequest,
        reason: 'the binding answers a network image with a canned 400; a real client would have thrown',
      );
    });
  });
}
