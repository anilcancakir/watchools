import 'package:flutter_test/flutter_test.dart';
import 'package:watchools/app/models/channel.dart';
import 'package:watchools/app/models/programme.dart';
import 'package:watchools/app/support/guide_clock.dart';

void main() {
  group('Channel.fromXtream', () {
    test('maps num, name, the resolved category and the stream id', () {
      final Channel channel = Channel.fromXtream(
        const <String, dynamic>{
          'num': 7,
          'name': 'Kanal D',
          'stream_id': 1042,
          'stream_icon': 'http://host/logo/1042.svg',
          'category_id': '3',
        },
        categoryName: 'Ulusal',
        clock: FixedGuideClock(0),
      );

      expect(channel.number, 7);
      expect(channel.name, 'Kanal D');
      expect(channel.group, 'Ulusal');
      expect(channel.streamId, 1042);
      expect(channel.logoUrl, 'http://host/logo/1042.svg');
    });

    test('turns an empty stream_icon into a null logoUrl', () {
      final Channel channel = Channel.fromXtream(
        const <String, dynamic>{'num': 1, 'name': 'X', 'stream_id': 1, 'stream_icon': ''},
        categoryName: 'Ulusal',
        clock: FixedGuideClock(0),
      );

      expect(channel.logoUrl, isNull);
    });

    test('folds the two archive fields into one window in days', () {
      final Channel withArchive = Channel.fromXtream(
        const <String, dynamic>{'num': 1, 'name': 'X', 'stream_id': 1, 'tv_archive': 1, 'tv_archive_duration': 7},
        categoryName: 'Ulusal',
        clock: FixedGuideClock(0),
      );

      expect(withArchive.catchupDays, 7);
    });

    test('reads tv_archive as the authority, not the duration', () {
      // A panel can send a non-zero duration beside a zero flag, and then
      // there is no archive: the flag is what says one exists.
      final Channel flagOff = Channel.fromXtream(
        const <String, dynamic>{'num': 1, 'name': 'X', 'stream_id': 1, 'tv_archive': 0, 'tv_archive_duration': 7},
        categoryName: 'Ulusal',
        clock: FixedGuideClock(0),
      );
      final Channel noFields = Channel.fromXtream(
        const <String, dynamic>{'num': 2, 'name': 'Y', 'stream_id': 2},
        categoryName: 'Ulusal',
        clock: FixedGuideClock(0),
      );

      expect(flagOff.catchupDays, isNull);
      expect(noFields.catchupDays, isNull);
    });

    test('carries the archive window and the stream id through a favourite toggle', () {
      // Both are provider identity rather than user state, so dropping either
      // here would silently orphan the channel from its own provider.
      final Channel channel = Channel.fromXtream(
        const <String, dynamic>{'num': 1, 'name': 'X', 'stream_id': 99, 'tv_archive': 1, 'tv_archive_duration': 3},
        categoryName: 'Ulusal',
        clock: FixedGuideClock(0),
      );

      final Channel starred = channel.toggleFavourite();

      expect(starred.favourite, isTrue);
      expect(starred.streamId, 99);
      expect(starred.catchupDays, 3);
    });

    test('yields an empty schedule and hasSchedule false when the provider sent no EPG', () {
      final Channel channel = Channel.fromXtream(
        const <String, dynamic>{'num': 14, 'name': 'Haber Global', 'stream_id': 14},
        categoryName: 'Haber',
        clock: FixedGuideClock(0),
      );

      expect(channel.schedule, isEmpty);
      expect(channel.hasSchedule, isFalse);
    });

    test('computes live against a clock inside a programme and idle against one outside every programme', () {
      const Programme programme = Programme(startMinute: 20 * 60, endMinute: 20 * 60 + 30, title: 'Haber');
      final Channel live = Channel.fromXtream(
        const <String, dynamic>{'num': 1, 'name': 'X', 'stream_id': 1},
        categoryName: 'Ulusal',
        clock: FixedGuideClock(20 * 60 + 5),
        schedule: const <Programme>[programme],
      );
      final Channel idle = Channel.fromXtream(
        const <String, dynamic>{'num': 1, 'name': 'X', 'stream_id': 1},
        categoryName: 'Ulusal',
        clock: FixedGuideClock(22 * 60),
        schedule: const <Programme>[programme],
      );

      expect(live.status, ChannelStatus.live);
      expect(idle.status, ChannelStatus.idle);
    });
  });

  group('Programme.fromXtream', () {
    test('never wraps a programme that runs past midnight', () {
      final DateTime referenceMidnight = DateTime(2026);
      final Programme? programme = Programme.fromXtream(const <String, dynamic>{
        // Base64 for "Gece Filmi", the shape `get_short_epg` actually sends.
        'title': 'R2VjZSBGaWxtaQ==',
        'start': '2026-01-01 23:50:00',
        'end': '2026-01-02 00:30:00',
      }, referenceMidnight: referenceMidnight);

      expect(programme, isNotNull);
      expect(programme!.title, 'Gece Filmi');
      expect(programme.startMinute, 23 * 60 + 50);
      // Per CLAUDE.md: a block running to 00:30 ends at 1470, never wrapped to 30.
      expect(programme.endMinute, 24 * 60 + 30);
      expect(programme.endMinute, greaterThan(24 * 60));
    });

    test('labels a negative minute as the previous evening, not as after midnight', () {
      // The unit is allowed to go negative: `get_short_epg`'s first listing is
      // the programme already on air, which began the previous evening, so
      // after a post-midnight re-anchor a window legitimately starts at -30.
      // Dart's `~/` truncates toward zero, so the naive formatter printed
      // `00:30` for half past eleven the night before. Block placement was
      // never affected, only the label, which is why every layout test passed.
      const Programme spanning = Programme(startMinute: -30, endMinute: 20, title: 'Gece Kuşağı');

      expect(spanning.startLabel, '23:30');
      expect(spanning.endLabel, '00:20');
    });

    test('still labels a past-midnight minute without wrapping the unit', () {
      const Programme late = Programme(startMinute: 1470, endMinute: 1500, title: 'Kapanış');

      expect(late.startLabel, '00:30');
      expect(late.endLabel, '01:00');
    });

    test('returns null when the listing has no parsable start or end', () {
      final Programme? programme = Programme.fromXtream(const <String, dynamic>{
        'title': 'x',
      }, referenceMidnight: DateTime(2026));

      expect(programme, isNull);
    });
  });
}
