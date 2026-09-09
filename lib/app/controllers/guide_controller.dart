import 'package:flutter/foundation.dart';
import 'package:magic/magic.dart';

import '../models/channel.dart';
import '../models/programme.dart';
import '../models/provider_fault.dart';
import '../provider/provider_session.dart';
import '../support/fixture_scale.dart';
import '../support/guide_clock.dart';

/// The two ways to look at the same line-up.
///
/// Both ship. They are not two styles of one screen, they answer two different
/// questions: [now] answers "what is on", [grid] answers "what is on at nine".
/// A viewer opening the app in the evening wants the first and a viewer
/// planning the evening wants the second, and neither layout can do the other's
/// job without becoming it.
enum GuideMode {
  /// A live hero that ticks, over editorial rails. Netflix's television screen,
  /// rebuilt around a subject that changes every forty minutes.
  now,

  /// A real broadcast grid: channels down, time across, a now line, and past
  /// blocks that are reachable because catch-up makes them playable. The only
  /// view where 20:55 and 21:30 are visible at the same moment.
  grid,
}

/// One editorial rail on the [GuideMode.now] screen.
///
/// The title is a sentence with a point of view, not a taxonomy label, and the
/// source line says where the row came from. Both halves are Netflix's and
/// Plex's respectively, and together they answer the two questions a row raises:
/// what is this, and why am I being shown it.
@immutable
class GuideRail {
  /// The editorial title.
  final String title;

  /// Where the row came from, or null when the answer is uninteresting.
  final String? source;

  /// The channels in it, already filtered.
  final List<Channel> channels;

  /// Creates a [GuideRail].
  const GuideRail({required this.title, required this.channels, this.source});
}

/// Everything the line-up screen knows: the channels, the filters, the
/// selection, and which of the two views is on show.
///
/// A [SimpleMagicController] rather than a [MagicController] with a state
/// mixin: reading a [ProviderFault] off [ProviderSession] is a plain getter,
/// not a request this controller itself makes, so there is still nothing here
/// to be loading.
class GuideController extends SimpleMagicController {
  /// Resolved once and shared by both views, so switching between them keeps
  /// the query, the category and the favourites the user just set.
  static GuideController get instance => Magic.findOrPut(GuideController.new);

  /// What time it is, and the only source of it on the fixture path. See
  /// [now].
  ///
  /// Injected rather than read from the wall, for two reasons that pull the
  /// same way. The fixtures are one evening, so a real clock shows an empty
  /// guide for the nineteen hours a day that evening is not on. And a
  /// measurement session runs twenty to sixty seconds, so a free-running clock
  /// would tick inside it and put a rebuild in the middle of the frames being
  /// counted.
  final GuideClock clock;

  /// Whether this controller built its own clock and therefore owns it.
  ///
  /// A caller that passes one keeps it: a test drives a stub across several
  /// controllers, and disposing it on the first `onClose` would break the
  /// second. Latent while the default is a `FixedGuideClock`, which holds no
  /// resource; the day the default becomes a `TickingGuideClock` this is the
  /// difference between a cancelled timer and a leaked one.
  final bool _ownsClock;

  /// The provider handle passed in, or null to resolve one from the
  /// container. See [_session].
  final ProviderSession? _sessionOverride;

  /// Creates the controller, stopped at the fixture's hour unless told
  /// otherwise.
  ///
  /// [session] is what [channels], [groups], [fault] and [now] read on the
  /// provider path; pass one in a test, leave it null in the app.
  GuideController({GuideClock? clock, ProviderSession? session})
    : clock = clock ?? FixedGuideClock(),
      _ownsClock = clock == null,
      _sessionOverride = session {
    _tickingSource = this.clock;
    this.clock.addListener(_onTick);
  }

  /// The provider handle, resolved on every read rather than captured once.
  ///
  /// `AppServiceProvider.register()` binds `GuideController` before it binds
  /// `ProviderSession` (`app_service_provider.dart:30-38`), so capturing the
  /// container's instance in the constructor would freeze this controller on
  /// whatever [Magic.findOrPut] auto-vivified at that earlier moment, a
  /// throwaway session `AppServiceProvider`'s own `Magic.put` then discards.
  /// `Magic.findOrPut` rather than `Magic.find` for the same reason
  /// [GuideController.instance] uses it: a test or a preview that never
  /// bound a [ProviderSession] gets an unstarted one back (no credentials, no
  /// fault, empty catalogue) instead of an exception.
  ProviderSession get _session => _sessionOverride ?? Magic.findOrPut(ProviderSession.new);

  /// Minutes since the schedule's midnight, never wrapped. See [GuideClock].
  ///
  /// Reads [ProviderSession.clock] on the provider path, so a channel's
  /// status and every programme this controller filters by line up with the
  /// real wall clock a refresh anchored, per `CLAUDE.md`'s "The clock".
  /// Falls back to [clock] (`FixedGuideClock` by default) while no provider
  /// is configured or no refresh has landed one yet.
  int get now => (_session.clock ?? clock).minute;

  /// The axis starts on the half hour before now, which is what a guide does:
  /// you want to see what you just missed, not what already ended an hour ago.
  ///
  /// Derived rather than declared, so it follows the clock. As a constant it
  /// agreed with [now] only because both were written by hand on the same day;
  /// the first tick past 20:30 would have left the now line sitting an hour
  /// into a window that no longer started where it claimed.
  int get windowStart => (now ~/ 30) * 30 - 30;

  /// Five hours, 19:30 to 00:30.
  ///
  /// It was three and a half while the axis had to fit a laptop without
  /// scrolling, which capped the window at whatever left a block wide enough to
  /// carry a title. The grid scrolls now, so the cap is gone and the window
  /// becomes a question about the evening rather than about the viewport: five
  /// hours covers prime time end to end, which is the span someone opens a
  /// guide to plan.
  static const int windowMinutes = 300;

  /// The fixture line-up, mutated in place by [toggleFavourite] while no
  /// provider is configured.
  ///
  /// [FixtureScale] hands back the hand-written fixture unless a measurement
  /// run asked for a generated one through `WATCHOOLS_SCALE`. Kept alive
  /// unconditionally, not only while a session lacks credentials, so
  /// `tool/dusk/perf.sh` keeps measuring the requested size regardless of
  /// what `Vault` holds on the machine it runs on.
  final List<Channel> _fixtureChannels = FixtureScale.channelList;

  /// The reference [_session]'s channel list held the last time any cached
  /// getter below ran, so a [ProviderSession.refresh] that landed with
  /// nobody calling a mutation method still drops the caches.
  ///
  /// [ProviderSession] is a plain class and does not notify
  /// (`provider_session.dart`'s own class doc): nothing calls [refreshUI]
  /// when a refresh replaces its list out from under this controller. Polling
  /// the reference is enough because `ProviderSession._refreshChannels`
  /// always builds and assigns a brand new list rather than mutating the held
  /// one in place, so identity is exactly the signal a catalogue swap leaves.
  List<Channel>? _lastSeenChannels;

  /// The clock [_onTick] is currently attached to.
  ///
  /// The constructor attaches to [clock]. A refresh then anchors a real
  /// [ProviderSession.clock] and the subscription has to move with it, because
  /// reading the right minute is not the same as being told when it changes:
  /// [now] would report a live value that nothing ever repainted, so the
  /// progress bars, the countdown and the grid's now line would sit at
  /// whatever minute the last unrelated rebuild happened to catch.
  GuideClock? _tickingSource;

  /// Moves [_onTick] onto whichever clock is authoritative right now.
  ///
  /// Runs more than once by design: [ProviderSession] re-anchors its clock
  /// when the calendar day moves, so this detaches from the previous instance
  /// and attaches to the new one. It never disposes what it detaches from,
  /// because the session owns that instance; [clock] is the only one this
  /// controller may own and [onClose] is the only place it is disposed.
  void _followSessionClock() {
    final GuideClock next = _session.clock ?? clock;
    if (identical(next, _tickingSource)) return;

    _tickingSource?.removeListener(_onTick);
    _tickingSource = next;
    next.addListener(_onTick);
  }

  /// Drops every cache below when [_session]'s channel list has moved since
  /// it was last observed. See [_lastSeenChannels].
  void _syncWithSession() {
    if (!_session.hasCredentials) return;

    _followSessionClock();

    final List<Channel> current = _session.channels;
    if (identical(current, _lastSeenChannels)) return;

    _lastSeenChannels = current;
    _invalidate();
    _groupsCache = null;
  }

  /// The line-up, in provider order. Mutable only through [toggleFavourite].
  ///
  /// [ProviderSession.channels] while a credential is configured, the fixture
  /// otherwise: a session with nothing in `Vault` is not a fault, it is the
  /// state the fixture fallback reads.
  List<Channel> get channels {
    _syncWithSession();

    return _session.hasCredentials ? _session.channels : _fixtureChannels;
  }

  /// Why the user's provider is not delivering a working catalogue, or null
  /// when the last handshake was healthy, none has run, or the fixture path
  /// is in use.
  ProviderFault? get fault => _session.fault;

  GuideMode _mode = GuideMode.now;
  String _group = 'Tümü';
  String _query = '';

  /// The channel the billboard and the preview are showing, or null when
  /// nothing has ever been explicitly selected and [channels] is empty.
  Channel? _channel;

  /// The programme the guide is pointed at. See [programme].
  Programme? _programme;

  /// Drops everything derived from [now] and repaints.
  ///
  /// Every cache below is time-dependent, including the two that do not look
  /// it: `matches` searches the programme currently on air, and `sections` is
  /// built over `matches`.
  void _onTick() {
    _programme = channel?.programmeAt(now);
    _invalidate();
    refreshUI();
  }

  @override
  void onClose() {
    // Detach from whichever clock [_followSessionClock] left us on, which is
    // not necessarily [clock]. Only [clock] is disposed, and only when this
    // controller made it: the session's own instance outlives this controller
    // and disposing it would take the guide down for whoever else reads it.
    _tickingSource?.removeListener(_onTick);
    if (_ownsClock) clock.dispose();
    super.onClose();
  }

  /// Cached until a mutation drops it. `matches` walks the whole line-up and one build asks
  /// for it several times: in the toolbar, through [scheduled], and in the body.
  /// At twenty three channels that is invisible; at ten thousand it is several
  /// full scans per frame.
  List<Channel>? _matchCache;
  List<Channel>? _scheduledCache;
  List<(String, List<Channel>)>? _sectionCache;
  List<GuideRail>? _railCache;
  List<String>? _groupsCache;

  /// Which of the two views is on show.
  GuideMode get mode => _mode;

  /// The selected category, `Tümü` or `Favoriler` included.
  String get group => _group;

  /// The current search term, unnormalised.
  String get query => _query;

  /// The channel the billboard and the preview are showing, or null when the
  /// catalogue is empty (the normal state during a provider's first
  /// refresh).
  ///
  /// Falls back to the first entry in [channels] until an explicit
  /// [selectChannel] or [selectProgramme] has run, which is what let
  /// [_channel] start out unset instead of throwing the moment a `late`
  /// initialiser read an empty list.
  Channel? get channel => _channel ?? (channels.isEmpty ? null : channels.first);

  /// The programme the guide is pointed at, null when the channel has no EPG.
  ///
  /// Falls back to what [channel] is airing right now until an explicit
  /// selection has run; every path that writes [_programme] afterwards
  /// (`_onTick`, [selectChannel]) sets exactly the value this fallback would
  /// have computed for a channel with no schedule, so the two never disagree.
  Programme? get programme => _programme ?? channel?.programmeAt(now);

  /// Everything matching the current group and query, in line-up order.
  List<Channel> get matches {
    _syncWithSession();

    final List<Channel>? cached = _matchCache;
    if (cached != null) return cached;

    final String needle = _query.trim().toLowerCase();

    final List<Channel> result = channels.where((Channel channel) {
      if (_group == 'Favoriler' && !channel.favourite) return false;
      if (_group != 'Favoriler' && _group != 'Tümü' && channel.group != _group) {
        return false;
      }
      if (needle.isEmpty) return true;

      // Search covers the channel name, its number and, where the provider
      // sent one, the programme on now. Searching titles matters more than it
      // looks: people look for the match, not for the sports channel.
      if (channel.name.toLowerCase().contains(needle)) return true;
      if (channel.numberLabel.contains(needle)) return true;

      return channel.programmeAt(now)?.title.toLowerCase().contains(needle) ?? false;
    }).toList();

    _matchCache = result;

    return result;
  }

  /// The subset of [matches] that carries a schedule.
  ///
  /// Not "what the time axis can draw" any more: the grid view draws every
  /// match, and gives a channel with no EPG a full-window block saying so. This
  /// exists for [withoutSchedule], which is the count both toolbars state.
  List<Channel> get scheduled {
    _syncWithSession();

    return _scheduledCache ??= matches.where((Channel c) => c.hasSchedule).toList();
  }

  /// [matches] cut into runs of the same `group-title`, in line-up order.
  ///
  /// Runs, not first-appearance groups: a new section starts wherever the group
  /// changes, so a provider that interleaves its groups yields two sections
  /// with the same name. That is deliberate here and it is the opposite of
  /// `LibraryController.sections`, which coalesces. A channel line-up arrives
  /// in an order that means something (related channels adjacent, numbered in
  /// blocks) and coalescing would reorder it; a VOD catalogue does not.
  ///
  /// The sections are `group-title` values rather than initial letters. Apple's
  /// vocabulary for a long list is an index, and for a music library the index
  /// is alphabetical because the library is sorted that way. A provider line-up
  /// is not: it arrives in the provider's order, which groups related channels
  /// together, and re-sorting it alphabetically destroys the one piece of
  /// structure the provider actually sent.
  List<(String, List<Channel>)> get sections {
    _syncWithSession();

    final List<(String, List<Channel>)>? cached = _sectionCache;
    if (cached != null) return cached;

    final List<(String, List<Channel>)> result = <(String, List<Channel>)>[];

    for (final Channel channel in matches) {
      if (result.isEmpty || result.last.$1 != channel.group) {
        result.add((channel.group, <Channel>[channel]));
      } else {
        result.last.$2.add(channel);
      }
    }

    _sectionCache = result;

    return result;
  }

  /// How many of [matches] carry no schedule. Every toolbar states it so
  /// a viewer meets the gap as a fact about their subscription rather than one
  /// blank card at a time.
  int get withoutSchedule => matches.length - scheduled.length;

  /// How soon a programme has to start to count as "about to".
  ///
  /// Forty five minutes rather than thirty. A Turkish evening schedule turns
  /// over on the hour and the half hour, so a thirty minute horizon at 20:12
  /// catches the 20:30 slot and nothing else; forty five reaches 21:00 and the
  /// row stops emptying out for a third of every hour.
  static const int _soonMinutes = 45;

  /// How far into a programme still counts as worth joining.
  static const double _freshFraction = 0.25;

  /// The editorial rails, filtered by the current group and query.
  ///
  /// The first two rows are the ones no catalogue product can offer, and they
  /// are the reason this view exists: "you have not missed much" and
  /// "starts shortly" are questions only a live schedule can answer, and a
  /// static channel grid answers neither. Everything below them is the
  /// provider's own grouping, which is the only structure a real playlist
  /// actually ships with.
  ///
  /// A rail with nothing in it is dropped rather than rendered empty. That is
  /// the one place this departs from "missing data occupies its slot": an empty
  /// SLOT inside a row is a hole and has to be designed, but an empty ROW is a
  /// claim about the schedule that is simply not true right now.
  List<GuideRail> get rails {
    _syncWithSession();

    final List<GuideRail>? cached = _railCache;
    if (cached != null) return cached;

    final List<Channel> fresh = <Channel>[];
    final List<Channel> soon = <Channel>[];
    final List<Channel> starred = <Channel>[];
    final List<Channel> blind = <Channel>[];

    for (final Channel channel in matches) {
      // Starred first, and above the no-schedule branch rather than below it.
      // Under it, a channel the user had starred and the provider sent no EPG
      // for reached the blind rail and nothing else, so the one list a viewer
      // curates by hand silently dropped exactly the channels they are most
      // likely to have curated: a music or a regional channel with no guide.
      if (channel.favourite) starred.add(channel);

      if (!channel.hasSchedule) {
        blind.add(channel);
        continue;
      }

      final Programme? live = channel.programmeAt(now);
      if (live != null && live.progressAt(now) <= _freshFraction) fresh.add(channel);

      final Programme? next = channel.nextAfter(now);
      if (next != null && next.startMinute - now <= _soonMinutes) soon.add(channel);
    }

    final List<GuideRail> result = <GuideRail>[
      if (fresh.isNotEmpty) GuideRail(title: 'Daha yeni başladı', source: 'Şu an yayında', channels: fresh),
      // Named for the horizon it actually uses. `_soonMinutes` is 45, so at
      // 20:12 this row holds a 20:55 programme and a title saying half an hour
      // was a title the row could contradict on its own first card.
      if (soon.isNotEmpty) GuideRail(title: 'Birazdan başlıyor', source: 'Yayın akışından', channels: soon),
      if (starred.isNotEmpty) GuideRail(title: 'Favorilerin', channels: starred),
      // Scheduled members only. `sections` is built over `matches`, so without
      // this filter every no-EPG channel appeared twice on the screen: once in
      // its provider group and once in the rail that exists to name it.
      for (final (String group, List<Channel> members) in sections)
        if (group != 'Favoriler')
          if (members.where((Channel c) => c.hasSchedule).toList() case final List<Channel> scheduled
              when scheduled.isNotEmpty)
            GuideRail(title: group, source: 'Sağlayıcı grubu', channels: scheduled),
      if (blind.isNotEmpty)
        GuideRail(
          title: 'Akış bilgisi olmayan kanallar',
          source: 'Sağlayıcı bu kanallar için EPG göndermedi',
          channels: blind,
        ),
    ];

    _railCache = result;

    return result;
  }

  /// How many channels the current filter left, worded for whether a search is
  /// active.
  ///
  /// On the controller rather than per view: while four layouts competed, two
  /// of them said `N kanal` whatever the query, so a search that had narrowed
  /// the list to two still reported the whole line-up. Same number, four
  /// spellings, is how a count stops being trusted.
  String get countLabel {
    final int total = matches.length;

    return query.trim().isEmpty ? '$total kanal' : '$total sonuç';
  }

  /// The one-line statement both views make about missing guide data, or null
  /// when the provider covered the whole selection.
  ///
  /// It is on screen without scrolling, in both views, on purpose. A
  /// large share of a real line-up arrives with no EPG, and a user who meets
  /// that one channel at a time reads it as the app failing rather than as the
  /// provider not sending it. Stating the count once turns a recurring glitch
  /// into a fact about their subscription.
  String? get noGuideNote {
    final int count = withoutSchedule;

    return count == 0 ? null : '$count kanalda akış yok';
  }

  /// The categories on the strip. `Tümü` and `Favoriler` are ours; the rest
  /// come from the provider's `group-title` values.
  ///
  /// On the fixture path this stays [FixtureScale.groupList], which is a
  /// hand-curated subset rather than every group [channels] actually carries
  /// (`guide_fixture.dart:25` omits `Müzik`, `Sinema` and four more): that
  /// mismatch is deliberate fixture data, not something this getter corrects.
  /// On the provider path there is no such curated list, so it is derived
  /// from whatever [channels] actually holds.
  List<String> get groups {
    _syncWithSession();

    return _groupsCache ??= _session.hasCredentials ? _providerGroups(channels) : FixtureScale.groupList;
  }

  /// `Tümü` and `Favoriler`, then every distinct [Channel.group] in
  /// [channels], in first-appearance order.
  static List<String> _providerGroups(List<Channel> channels) {
    final List<String> seen = <String>[];
    for (final Channel channel in channels) {
      if (!seen.contains(channel.group)) seen.add(channel.group);
    }

    return <String>['Tümü', 'Favoriler', ...seen];
  }

  /// Switches view. The query, the category and the selection all survive it,
  /// which is the whole reason both views read one controller: a viewer who has
  /// narrowed to Spor and then wants to see it on a time axis has not changed
  /// their mind about Spor.
  void showMode(GuideMode mode) {
    _mode = mode;
    refreshUI();
  }

  /// Applies a category from the strip.
  void selectGroup(String group) {
    _group = group;
    _invalidate();
    refreshUI();
  }

  /// Applies a search term.
  void search(String query) {
    _query = query;
    _invalidate();
    refreshUI();
  }

  /// Points the screen at [channel] and at whatever it is showing now.
  void selectChannel(Channel channel) {
    _channel = channel;
    _programme = channel.programmeAt(now);
    refreshUI();
  }

  /// Points the screen at one specific programme, which the time axis needs
  /// and the row list does not.
  void selectProgramme(Channel channel, Programme programme) {
    _channel = channel;
    _programme = programme;
    refreshUI();
  }

  /// Stars or unstars [channel], keeping the selection pointed at the new
  /// instance so the billboard does not fall back to the first channel.
  ///
  /// Routes through [ProviderSession.setChannelFavourite] while a credential
  /// is configured, which is what makes the star survive a restart; a fixture
  /// channel carries no `streamId` (`channel.dart:67`) for that call to key
  /// on, so the fixture path keeps mutating [_fixtureChannels] in place, same
  /// as before this controller read a session at all.
  void toggleFavourite(Channel channel) {
    final int index = channels.indexOf(channel);

    if (_session.hasCredentials) {
      final int? streamId = channel.streamId;
      if (streamId != null) _session.setChannelFavourite(streamId: streamId, favourite: !channel.favourite);
    } else {
      _fixtureChannels[index] = channel.toggleFavourite();
    }

    if (identical(_channel, channel)) _channel = channels[index];
    _invalidate();
    refreshUI();
  }

  /// Drops both frame caches. Every mutation that changes what is visible has
  /// to call this, or the list keeps showing the previous filter.
  void _invalidate() {
    _matchCache = null;
    _scheduledCache = null;
    _sectionCache = null;
    _railCache = null;
  }

  /// Asks the provider for a fresh catalogue, then repaints.
  ///
  /// What `ProviderNotice`'s retry button calls, and the reason it lives here
  /// rather than being reached from a layout: the screens read their state
  /// from this controller, and a widget calling [ProviderSession] directly
  /// would give the same screen two sources of truth.
  ///
  /// Deliberately not a no-op on the fixture path: with no credentials the
  /// session's own [ProviderSession.refresh] returns without sending anything,
  /// so the button is harmless there rather than needing a guard here. The
  /// same is true during playback, which is the session's rule to keep because
  /// the connection limit is its concern.
  ///
  /// Awaiting rather than firing: this is a user-initiated retry with a button
  /// behind it, unlike the boot-time refresh that must not delay the first
  /// frame.
  Future<void> reload() async {
    await _session.refresh();

    _invalidate();
    _groupsCache = null;
    refreshUI();
  }
}
