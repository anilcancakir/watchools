import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_wind/fluttersdk_wind.dart';
import 'package:magic/magic.dart' show MagicController, MagicSelector;
import 'package:watchools/app/controllers/guide_controller.dart';
import 'package:watchools/app/controllers/library_controller.dart';
import 'package:watchools/app/models/channel.dart';
import 'package:watchools/app/models/programme.dart';
import 'package:watchools/app/models/title_item.dart';
import 'package:watchools/ui/layouts/now_layout.dart';
import 'package:watchools/ui/layouts/showcase_layout.dart';
import 'package:watchools/ui/layouts/support/library_empty.dart';
import 'package:watchools/ui/layouts/time_layout.dart';

import '../../support/screen.dart';

/// Does a keystroke rebuild the parts of the screen it cannot have changed?
///
/// `refreshUI` notifies every listener and `MagicStatefulViewState` answers with
/// `setState` on the whole view, so before `MagicSelector` a single character
/// rebuilt the category strip, both switches, both heroes and the grid's ruler
/// along with the list that actually changed: measured at 220 `WDiv` builds per
/// character on `Şimdi` at five thousand channels.
///
/// **Widget identity is the assertion, and it is the mechanism rather than a
/// proxy for it.** `Element.updateChild` short circuits when the incoming widget
/// is `==` to the mounted one (`framework.dart:4027`), so handing back the same
/// instance is exactly what ends the descent and leaves the subtree unvisited.
/// A test that only checked the screen still looked right would pass with every
/// one of those rebuilds still happening.
///
/// The two resize cases and the emptying case are the other half: they guard the
/// traps this optimisation introduces rather than the one it removes, and each
/// was A/B'd red against the version without the guard.
void main() {
  setUp(WindParser.clearCache);

  /// Rebuilds [child] whenever [controller] notifies, which is what
  /// `MagicStatefulViewState` does in the running app and what `pumpScreen`
  /// alone does not do. `search_focus_test.dart` records why a bare layout
  /// makes every case here vacuous.
  Widget listening(MagicController controller, Widget Function() child) {
    return ListenableBuilder(listenable: controller, builder: (BuildContext context, Widget? _) => child());
  }

  /// The widget a [MagicSelector] last handed down.
  ///
  /// Found by the selector's own generic type and read off the element rather
  /// than matched on a className, so a case says which SCOPE it is asserting
  /// about and stops depending on how that scope happens to be styled.
  Widget cached(WidgetTester tester, Type selector) {
    Widget? child;
    tester.element(find.byType(selector)).visitChildren((Element e) => child = e.widget);

    return child!;
  }

  /// A term that narrows the fixture without emptying it. An empty result swaps
  /// the body branch, and a swapped branch would destroy the very elements most
  /// of these cases are asserting survived.
  const String narrowing = 'TRT';

  /// A term no fixture channel or title can match.
  const String nonsense = 'zqxv';

  testWidgets('Şimdi: a keystroke leaves the strip, the switch and the hero alone', (tester) async {
    final GuideController controller = GuideController();
    await pumpScreen(tester, listening(controller, () => NowLayout(controller: controller)));

    const Type strip = MagicSelector<GuideController, (List<String>, String)>;
    const Type switcher = MagicSelector<GuideController, GuideMode>;
    const Type hero = MagicSelector<GuideController, (Channel, Programme?, int, bool)>;

    final Widget beforeStrip = cached(tester, strip);
    final Widget beforeSwitch = cached(tester, switcher);
    final Widget beforeHero = cached(tester, hero);

    controller.search(narrowing);
    await tester.pump();

    expect(controller.matches, isNotEmpty, reason: 'the body branch did not swap');
    expect(identical(cached(tester, strip), beforeStrip), isTrue, reason: 'the category strip');
    expect(identical(cached(tester, switcher), beforeSwitch), isTrue, reason: 'the view switch');
    expect(identical(cached(tester, hero), beforeHero), isTrue, reason: 'the hero');
  });

  testWidgets('and the strip still follows a category change', (tester) async {
    // The cache is a scope, not a freeze. Without this the previous case is
    // satisfied by a strip that never rebuilds at all.
    final GuideController controller = GuideController();
    await pumpScreen(tester, listening(controller, () => NowLayout(controller: controller)));

    const Type strip = MagicSelector<GuideController, (List<String>, String)>;
    final Widget before = cached(tester, strip);

    controller.selectGroup('Spor');
    await tester.pump();

    expect(identical(cached(tester, strip), before), isFalse);
  });

  testWidgets('and the count still follows the keystroke', (tester) async {
    // The toolbar reads the query, so it is the one block that has to rebuild.
    // A selector drawn around too much of the screen shows up here first.
    final GuideController controller = GuideController();
    await pumpScreen(tester, listening(controller, () => NowLayout(controller: controller)));

    expect(find.byWidgetPredicate((Widget w) => w is WText && w.data.startsWith('23 kanal')), findsOneWidget);

    controller.search(narrowing);
    await tester.pump();

    expect(find.byWidgetPredicate((Widget w) => w is WText && w.data.startsWith('1 sonuç')), findsOneWidget);
  });

  testWidgets('Şimdi: the hero re-forms when the window crosses the breakpoint', (tester) async {
    // `wide` is computed in the enclosing build from `MediaQuery` and captured
    // by the builder closure, so it only reaches the cache by being part of the
    // selected value. Left out, the hero keeps whichever form it was first
    // built in until the clock or the selection happens to move.
    //
    // `_heroContent` draws the programme description only above `sm`, so the
    // description is what says which form the cached subtree is holding. Read
    // off `WText.data` rather than through `find.text`, which would depend on
    // how wind renders its text.
    final GuideController controller = GuideController();
    await pumpScreen(tester, listening(controller, () => NowLayout(controller: controller)), size: mobile);

    final Finder synopsis = find.byWidgetPredicate((Widget w) => w is WText && w.data.startsWith('Günün gelişmeleri'));

    expect(synopsis, findsNothing, reason: 'the narrow hero drops the description');

    tester.view.physicalSize = desktop;
    await tester.pump();

    expect(synopsis, findsOneWidget, reason: 'a captured `wide` is not in the selected value');
  });

  testWidgets('Zaman: a keystroke leaves the ruler alone', (tester) async {
    final GuideController controller = GuideController();
    await pumpScreen(tester, listening(controller, () => TimeLayout(controller: controller)));

    const Type ruler = MagicSelector<GuideController, (int, int, String)>;
    final Widget before = cached(tester, ruler);

    controller.search(narrowing);
    await tester.pump();

    expect(controller.matches, isNotEmpty, reason: 'the body branch did not swap');
    expect(identical(cached(tester, ruler), before), isTrue);
  });

  testWidgets('and the ruler re-forms when the identity column narrows', (tester) async {
    // The ruler's left inset has to equal the identity column exactly or every
    // time label is offset from the block it names. That width is decided in the
    // enclosing build, so it is the same captured-value trap as `wide`, and
    // getting it wrong here is a misaligned ruler rather than a missing line.
    final GuideController controller = GuideController();
    await pumpScreen(tester, listening(controller, () => TimeLayout(controller: controller)), size: mobile);

    Finder inset(String width) {
      return find.byWidgetPredicate((Widget w) => w is WDiv && w.className == '$width flex flex-row items-center');
    }

    expect(inset('w-[120px] shrink-0'), findsOneWidget, reason: 'the narrow column');

    tester.view.physicalSize = desktop;
    await tester.pump();

    expect(inset('w-[248px] shrink-0'), findsOneWidget, reason: 'the column width is not in the selected value');
  });

  testWidgets('Vitrin: a keystroke leaves the categories, the scopes and the hero alone', (tester) async {
    final LibraryController controller = LibraryController();
    await pumpScreen(tester, listening(controller, () => ShowcaseLayout(controller: controller)));

    const Type categories = MagicSelector<LibraryController, (List<String>, String)>;
    const Type scopes = MagicSelector<LibraryController, LibraryScope>;
    const Type hero = MagicSelector<LibraryController, (TitleItem?, bool)>;

    final Widget beforeCategories = cached(tester, categories);
    final Widget beforeScopes = cached(tester, scopes);
    final Widget beforeHero = cached(tester, hero);

    // Narrow enough to rebuild the catalogue and keep the promoted title in it,
    // which is the case the hero's selector is built for.
    controller.search(controller.continueWatching.first.name.substring(0, 4));
    await tester.pump();

    expect(controller.matches, isNotEmpty, reason: 'the body branch did not swap');
    expect(identical(cached(tester, categories), beforeCategories), isTrue, reason: 'the category strip');
    expect(identical(cached(tester, scopes), beforeScopes), isTrue, reason: 'the scope switch');
    expect(identical(cached(tester, hero), beforeHero), isTrue, reason: 'the hero');
  });

  test('Vitrin: the promoted title survives a narrowing keystroke', () {
    // The property the catalogue hero's selector rests on, and it belongs to the
    // CONTROLLER rather than to `MagicSelector`: narrowing drops the cached list
    // and builds a new one, but it refills it with the same `TitleItem` objects,
    // so the first entry compares equal by identity and the hero holds. Asserted
    // here rather than through the tree because it is a claim about the
    // controller that a widget test would only imply.
    final LibraryController controller = LibraryController();
    final TitleItem before = controller.continueWatching.first;

    controller.search(before.name.substring(0, 4));

    expect(controller.matches, isNotEmpty);
    expect(identical(controller.continueWatching.first, before), isTrue);
  });

  testWidgets('Vitrin: the hero survives the keystroke that empties the catalogue', (tester) async {
    // The hazard a selector brings that a build does not. It reads its value on
    // every NOTIFICATION, and the notification that empties the catalogue
    // arrives while this subtree is still mounted, because `refreshUI` notifies
    // the view and the selector in one loop and `setState` only marks the view
    // dirty. A promoted title that assumed a non-empty result therefore threw
    // `Bad state: No element` on exactly the keystroke that swaps it away, and
    // the only gate that caught it was the one about search focus.
    final LibraryController controller = LibraryController();
    await pumpScreen(tester, listening(controller, () => ShowcaseLayout(controller: controller)));

    controller.search(nonsense);
    await tester.pump();

    expect(controller.matches, isEmpty, reason: 'the query really did empty the catalogue');
    expect(find.byType(LibraryEmpty), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Vitrin: the hero re-forms when the window crosses the breakpoint', (tester) async {
    // The same captured-`wide` trap as `Şimdi`, on the other browse surface.
    // The synopsis is the desktop-only element here.
    final LibraryController controller = LibraryController();
    await pumpScreen(tester, listening(controller, () => ShowcaseLayout(controller: controller)), size: mobile);

    final String synopsis = controller.continueWatching.first.synopsis!;
    final Finder blurb = find.byWidgetPredicate((Widget w) => w is WText && w.data == synopsis);

    expect(blurb, findsNothing, reason: 'the narrow hero drops the synopsis');

    tester.view.physicalSize = desktop;
    await tester.pump();

    expect(blurb, findsOneWidget, reason: 'a captured `wide` is not in the selected value');
  });
}
