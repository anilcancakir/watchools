import 'package:flutter/foundation.dart';
import 'package:magic/magic.dart';

import '../models/channel.dart';
import '../models/programme.dart';
import '../support/guide_fixture.dart';

/// The three directions on offer while the design language is being chosen.
///
/// Each one is descended from a different reference, and they disagree about
/// what the screen is for rather than about how it looks. That is the choice
/// being put to the user; the styling follows from it.
enum GuideDirection {
  /// Netflix's television screen, rebuilt around a subject that changes every
  /// forty minutes. A live hero that ticks, over editorial rails.
  now,

  /// Plex's web library. A labelled sidebar, a dense virtualised list and one
  /// sticky panel that is the only thing that moves. Built for the line-up
  /// sizes a real provider ships.
  tower,

  /// A real broadcast grid: channels down, time across, a now line, and past
  /// blocks that are reachable because catch-up makes them playable. The only
  /// direction where 20:55 and 21:30 are visible at the same moment.
  time,
}

/// One editorial rail on the [GuideDirection.now] screen.
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
/// selection, and which layout is on show.
///
/// A [SimpleMagicController] rather than a [MagicController] with a state
/// mixin: the data is a fixture, so there is no request to be loading or
/// failing. It becomes a loading controller when the Xtream client lands.
class GuideController extends SimpleMagicController {
  /// Resolved once and shared by every layout, so switching between them keeps
  /// the query, the category and the favourites the user just set.
  static GuideController get instance => Magic.findOrPut(GuideController.new);

  /// 20:12, fixed so the mockup renders the same every time.
  static const int now = 20 * 60 + 12;

  /// The axis starts on the half hour before now, which is what a guide does:
  /// you want to see what you just missed, not what already ended an hour ago.
  static const int windowStart = 19 * 60 + 30;

  /// Five hours, 19:30 to 00:30.
  ///
  /// It was three and a half while the axis had to fit a laptop without
  /// scrolling, which capped the window at whatever left a block wide enough to
  /// carry a title. The grid scrolls now, so the cap is gone and the window
  /// becomes a question about the evening rather than about the viewport: five
  /// hours covers prime time end to end, which is the span someone opens a
  /// guide to plan.
  static const int windowMinutes = 300;

  /// The line-up, in provider order. Mutable only through [toggleFavourite].
  final List<Channel> channels = List<Channel>.of(guideFixture);

  GuideDirection _direction = GuideDirection.now;
  String _group = 'Tümü';
  String _query = '';
  late Channel _channel = channels.first;
  late Programme? _programme = channels.first.programmeAt(now);

  /// Cached until a mutation drops it. `matches` walks the whole line-up and one build asks
  /// for it several times: in the toolbar, through [scheduled], and in the body.
  /// At twenty three channels that is invisible; at ten thousand it is several
  /// full scans per frame.
  List<Channel>? _matchCache;
  List<Channel>? _scheduledCache;
  List<(String, List<Channel>)>? _sectionCache;
  List<GuideRail>? _railCache;

  /// Which direction is on show.
  GuideDirection get direction => _direction;

  /// The selected category, `Tümü` or `Favoriler` included.
  String get group => _group;

  /// The current search term, unnormalised.
  String get query => _query;

  /// The channel the billboard and the preview are showing.
  Channel get channel => _channel;

  /// The programme the guide is pointed at, null when the channel has no EPG.
  Programme? get programme => _programme;

  /// Everything matching the current group and query, in line-up order.
  List<Channel> get matches {
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
  /// Not "what the time axis can draw" any more: the grid direction draws every
  /// match, and gives a channel with no EPG a full-window block saying so. This
  /// exists for [withoutSchedule], which is the count the toolbars state.
  List<Channel> get scheduled => _scheduledCache ??= matches.where((Channel c) => c.hasSchedule).toList();

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
  /// are the reason this direction exists: "you have not missed much" and
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
  /// On the controller rather than per layout: two of the four said `N kanal`
  /// whatever the query, so a search that had narrowed the list to two still
  /// reported the whole line-up. Same number, four spellings, is how a count
  /// stops being trusted.
  String get countLabel {
    final int total = matches.length;

    return query.trim().isEmpty ? '$total kanal' : '$total sonuç';
  }

  /// The one-line statement every layout makes about missing guide data, or
  /// null when the provider covered the whole selection.
  ///
  /// It is on screen without scrolling, in all four layouts, on purpose. A
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
  List<String> get groups => guideGroups;

  /// Switches direction. Filters and favourites survive the switch on purpose:
  /// comparing two directions on different data compares the data.
  void showDirection(GuideDirection direction) {
    _direction = direction;
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
  void toggleFavourite(Channel channel) {
    final int index = channels.indexOf(channel);
    channels[index] = channel.toggleFavourite();
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
}
