import 'package:flutter_test/flutter_test.dart';
import 'package:watchools/ui/components/channel_mark/index.dart';

void main() {
  group('ChannelMark.initialsOf', () {
    test('takes the first letter of the first two words', () {
      expect(ChannelMark.initialsOf('Show TV'), 'ST');
      expect(ChannelMark.initialsOf('Haber Global'), 'HG');
    });

    test('takes two letters when there is only one meaningful word', () {
      expect(ChannelMark.initialsOf('NTV'), 'NT');
      expect(ChannelMark.initialsOf('A'), 'A');
    });

    test('skips the prefixes and suffixes a provider bolts onto a name', () {
      // The case this method exists for. Every channel in a Turkish line-up is
      // prefixed `TR:` and a large share is suffixed `HD`, so the naive first
      // two initials give `TR` for hundreds of rows in a row.
      expect(ChannelMark.initialsOf('TR: BEIN SPORTS 1 HD'), 'BS');
      expect(ChannelMark.initialsOf('TR | Kanal D FHD'), 'KD');
    });

    test('falls back to the noise words when the name is nothing else', () {
      // Better a wrong-looking `HD` than an empty box: the provider really did
      // send a channel called that, and hiding it makes the row look broken.
      expect(ChannelMark.initialsOf('HD'), 'HD');
    });

    test('drops punctuation and digits-only separators', () {
      expect(ChannelMark.initialsOf('Spor_Ekstra-2'), 'SE');
      expect(ChannelMark.initialsOf('*** 4K ***'), '4K');
    });

    test('keeps TV, which is part of the name rather than noise', () {
      expect(ChannelMark.initialsOf('Doğa TV'), 'DT');
      expect(ChannelMark.initialsOf('Diyanet TV'), 'DT');
    });

    test('uppercases the Turkish way, both dotted and dotless', () {
      // The reason `_upper` exists. Dart's locale-independent `toUpperCase`
      // maps the dotted `i` to `I`, so without it "istanbul" reads `IS`.
      expect(ChannelMark.initialsOf('istanbul tv'), 'İT');
      expect(ChannelMark.initialsOf('ışık tv'), 'IT');
      expect(ChannelMark.initialsOf('çocuk kanalı'), 'ÇK');
    });
  });
}
