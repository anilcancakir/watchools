import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchools/app/protocol/xtream/xtream_json.dart';

void main() {
  group('readInt', () {
    test('reads a bare integer', () {
      expect(readInt(<String, dynamic>{'auth': 1}, 'auth'), 1);
    });

    test('reads a quoted integer', () {
      expect(readInt(<String, dynamic>{'max_connections': '1'}, 'max_connections'), 1);
    });

    test('reads a fractional num without an "as int" throw', () {
      expect(readInt(<String, dynamic>{'n': 3.0}, 'n'), 3);
    });

    test('returns null on a missing key', () {
      expect(readInt(<String, dynamic>{}, 'missing'), null);
    });

    test('returns null on an unparsable value', () {
      expect(readInt(<String, dynamic>{'n': 'garbage'}, 'n'), null);
    });
  });

  group('readNullableString', () {
    test('reads a string', () {
      expect(readNullableString(<String, dynamic>{'epg_channel_id': 'abc'}, 'epg_channel_id'), 'abc');
    });

    test('reads a null as null', () {
      expect(readNullableString(<String, dynamic>{'epg_channel_id': null}, 'epg_channel_id'), null);
    });

    test('reads a missing key as null', () {
      expect(readNullableString(<String, dynamic>{}, 'exp_date'), null);
    });
  });

  group('readBool', () {
    test('reads a bare 1 as true', () {
      expect(readBool(<String, dynamic>{'tv_archive': 1}, 'tv_archive'), true);
    });

    test('reads a bare 0 as false', () {
      expect(readBool(<String, dynamic>{'now_playing': 0}, 'now_playing'), false);
    });

    test('reads a quoted 1 as true', () {
      expect(readBool(<String, dynamic>{'tv_archive': '1'}, 'tv_archive'), true);
    });

    test('returns null on a missing key', () {
      expect(readBool(<String, dynamic>{}, 'tv_archive'), null);
    });
  });

  group('readDouble', () {
    test('reads a quoted rating', () {
      expect(readDouble(<String, dynamic>{'rating': '7.5'}, 'rating'), 7.5);
    });

    test('reads a bare rating_5based', () {
      expect(readDouble(<String, dynamic>{'rating_5based': 7.5}, 'rating_5based'), 7.5);
    });

    test('returns null on a missing key', () {
      expect(readDouble(<String, dynamic>{}, 'rating'), null);
    });
  });

  group('readExpiryEpoch', () {
    test('reads a missing key as null (no expiry)', () {
      expect(readExpiryEpoch(<String, dynamic>{}, 'exp_date'), null);
    });

    test('reads a quoted zero as null (no expiry)', () {
      expect(readExpiryEpoch(<String, dynamic>{'exp_date': '0'}, 'exp_date'), null);
    });

    test('reads a quoted negative as null (no expiry)', () {
      expect(readExpiryEpoch(<String, dynamic>{'exp_date': '-1'}, 'exp_date'), null);
    });

    test('reads an unparsable value as null (no expiry)', () {
      expect(readExpiryEpoch(<String, dynamic>{'exp_date': 'garbage'}, 'exp_date'), null);
    });

    test('reads a real quoted epoch', () {
      expect(readExpiryEpoch(<String, dynamic>{'exp_date': '1700000000'}, 'exp_date'), 1700000000);
    });
  });

  group('readBase64Text', () {
    test('decodes a base64 title', () {
      final String encoded = base64.encode(utf8.encode('Tonight'));

      expect(readBase64Text(<String, dynamic>{'title': encoded}, 'title'), 'Tonight');
    });

    test('falls back to the raw string when it is not base64', () {
      expect(readBase64Text(<String, dynamic>{'title': 'Not Encoded At All!'}, 'title'), 'Not Encoded At All!');
    });

    test('returns null on a missing key', () {
      expect(readBase64Text(<String, dynamic>{}, 'title'), null);
    });
  });

  group('decodeBody', () {
    test('passes an already-decoded map through', () {
      final Map<String, dynamic> body = <String, dynamic>{'auth': 1};

      expect(decodeBody(body), body);
    });

    test('decodes a raw JSON string', () {
      expect(decodeBody('{"auth":1}'), <String, dynamic>{'auth': 1});
    });

    test('returns null on an unreadable body', () {
      expect(decodeBody('not json'), null);
    });

    test('returns null on a list body, which decodeEntries owns', () {
      expect(decodeBody('[{"num":1}]'), null);
    });
  });

  group('decodeEntries', () {
    test('passes an already-decoded list through', () {
      expect(
        decodeEntries(<Object?>[
          <String, dynamic>{'num': 1},
        ]),
        <Map<String, dynamic>>[
          <String, dynamic>{'num': 1},
        ],
      );
    });

    test('decodes a raw JSON array string', () {
      expect(decodeEntries('[{"category_id":"1"}]'), <Map<String, dynamic>>[
        <String, dynamic>{'category_id': '1'},
      ]);
    });

    test('reads an empty array as an empty list, not as unreadable', () {
      expect(decodeEntries('[]'), <Map<String, dynamic>>[]);
    });

    test('skips a non-map element rather than throwing', () {
      expect(decodeEntries('[{"num":1},"stray",7]'), <Map<String, dynamic>>[
        <String, dynamic>{'num': 1},
      ]);
    });

    test('returns null on an object body, which decodeBody owns', () {
      expect(decodeEntries('{"auth":1}'), null);
    });

    test('returns null on an unreadable body', () {
      expect(decodeEntries('not json'), null);
    });
  });
}
