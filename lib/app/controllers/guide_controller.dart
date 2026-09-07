import 'package:magic/magic.dart';

import '../models/channel.dart';
import '../models/programme.dart';
import '../support/guide_fixture.dart';

/// The four browse layouts on offer while the design language is being chosen.
///
/// They are genuinely different answers to the same question rather than four
/// skins, because the thing being decided is what the screen is FOR: a control
/// surface, a shop window, a stage, or an index.
enum BrowseLayout {
  /// Dense rows plus a time axis. Reads the line-up as data.
  signal,

  /// Full-bleed hero over horizontal rails. Reads the line-up as a catalogue.
  marquee,

  /// A quiet list beside one large preview that follows the pointer. Reads the
  /// line-up as a single object you move through.
  stage,

  /// A grid of channel marks with a now-playing strip. Reads the line-up as an
  /// index, and the only one that stays usable with no artwork and no EPG.
  mosaic,
}

/// Whether a [BrowseLayout.signal] body draws a time axis or a row per channel.
enum GuideMode {
  /// Time axis. Only channels that carry a schedule can appear.
  guide,

  /// One row per channel. Works for the whole line-up and is the only view
  /// that survives ten thousand of them.
  list,
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

  /// Three and a half hours, the widest window that still leaves a programme
  /// block wide enough to carry a title on a laptop.
  static const int windowMinutes = 210;

  /// The line-up, in provider order. Mutable only through [toggleFavourite].
  final List<Channel> channels = List<Channel>.of(guideFixture);

  BrowseLayout _layout = BrowseLayout.signal;
  GuideMode _mode = GuideMode.guide;
  String _group = 'Tümü';
  String _query = '';
  late Channel _channel = channels.first;
  late Programme? _programme = channels.first.programmeAt(now);

  /// Cached for the frame. [matches] walks the whole line-up and one build asks
  /// for it several times: in the toolbar, through [scheduled], and in the body.
  /// At twenty three channels that is invisible; at ten thousand it is several
  /// full scans per frame.
  List<Channel>? _matchCache;
  List<Channel>? _scheduledCache;
  List<(String, List<Channel>)>? _sectionCache;

  /// Which layout is on show.
  BrowseLayout get layout => _layout;

  /// Whether the signal layout is drawing the time axis or the row list.
  GuideMode get mode => _mode;

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

  /// The subset of [matches] the time axis can draw.
  List<Channel> get scheduled => _scheduledCache ??= matches.where((Channel c) => c.hasSchedule).toList();

  /// [matches] cut into the provider's own sections, in first-appearance order.
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

  /// How many of [matches] the time axis has to leave out. The guide says so
  /// rather than quietly showing a shorter list than the count above it.
  int get withoutSchedule => matches.length - scheduled.length;

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

  /// Switches layout. Filters and favourites survive the switch on purpose:
  /// comparing two layouts on different data compares the data.
  void showLayout(BrowseLayout layout) {
    _layout = layout;
    refreshUI();
  }

  /// Switches the signal layout between the time axis and the row list.
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
  }
}
