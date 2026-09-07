import 'package:magic/magic.dart';

import '../controllers/guide_controller.dart';
import '../controllers/library_controller.dart';

/// Application Service Provider.
///
/// Use this provider to bind your own services to the IoC container and
/// to perform any bootstrap logic that requires other services to be ready.
class AppServiceProvider extends ServiceProvider {
  /// Binds this provider to [app], the container it registers services into.
  AppServiceProvider(super.app);

  @override
  void register() {
    // The line-up controller is a singleton so the four competing layouts share
    // one set of filters and favourites: comparing two layouts on different
    // data compares the data. Registered here rather than in `boot()` because
    // the router pre-builds during `Magic.init()`, and a view that resolves its
    // controller in `initState` needs the binding to exist by then.
    //
    // `Magic.put` rather than `app.singleton`: the container's string-keyed
    // bindings and the controller registry are separate maps, and
    // `MagicStatefulViewState` resolves through `Magic.find<T>()`, which reads
    // the registry.
    Magic.put(GuideController());
    Magic.put(LibraryController());
  }

  @override
  Future<void> boot() async {
    // Perform async bootstrap logic here.
    //
    // IMPORTANT: Call setUserFactory() so Auth.user<T>() returns your model:
    //   Auth.manager.setUserFactory((data) => User.fromMap(data));
  }
}
