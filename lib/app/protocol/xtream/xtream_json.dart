import 'dart:convert';

/// Field-level readers over a decoded Xtream Codes JSON map.
///
/// Every function here reads one field out of a `Map<String, dynamic>` and
/// absorbs the type drift the wire actually sends: the same handshake carries
/// `auth` as a bare integer beside `max_connections` as a quoted string, and
/// `get_vod_streams` carries `rating` quoted beside `rating_5based` bare. None
/// of these throw on a shape the protocol is known to send: an unreadable
/// field returns `null` and the caller decides, because a throw here would be
/// read as a provider fault by the caller that classifies one from the
/// handshake rather than from a parse exception.
///
/// Every numeric field is read through [num] first and converted after:
/// on web, `int` and `double` share one 64-bit float, so a direct integer
/// cast fails the moment the provider sends a fraction and a direct double
/// cast fails the moment it sends a bare integer.

/// Reads [key] out of [json] as an integer, accepting a bare number or a
/// quoted string.
///
/// `auth` arrives bare while `max_connections` arrives quoted, in the same
/// handshake object. A fractional [num] truncates via [num.toInt] rather than
/// throwing, because the wire is not known to send one for an integer field
/// but a throw here is worse than a lossy read.
///
/// Returns `null` when [key] is missing, `null`, or unparsable.
int? readInt(Map<String, dynamic> json, String key) {
  final Object? value = json[key];

  if (value is num) {
    return value.toInt();
  }

  if (value is String) {
    return num.tryParse(value)?.toInt();
  }

  return null;
}

/// Reads [key] out of [json] as a string, or `null`.
///
/// Covers `epg_channel_id` and `exp_date`, both of which the wire sends as
/// either a string or a JSON `null`. Any non-string value (a stray number, a
/// bool) also reads as `null` rather than throwing, since neither field's
/// contract promises anything else.
String? readNullableString(Map<String, dynamic> json, String key) {
  final Object? value = json[key];

  return value is String ? value : null;
}

/// Reads [key] out of [json] as a bool, from the bare `0` / `1` integers the
/// wire actually sends for `tv_archive` and `now_playing`.
///
/// Also accepts a quoted `"0"` / `"1"`, since other integer fields in the same
/// responses drift that way and this reader has no reason to be stricter than
/// [readInt] about it. Any other value, or a missing key, reads as `null`.
bool? readBool(Map<String, dynamic> json, String key) {
  final int? value = readInt(json, key);

  if (value == null) {
    return null;
  }

  return value != 0;
}

/// Reads [key] out of [json] as a double, accepting a bare number or a quoted
/// string.
///
/// `rating` arrives quoted beside `rating_5based` bare, in the same
/// `get_vod_streams` entry. Goes through [num] first per the web/native
/// numeric-decode rule: a bare integer cast directly to a double type fails
/// on native.
///
/// Returns `null` when [key] is missing, `null`, or unparsable.
double? readDouble(Map<String, dynamic> json, String key) {
  final Object? value = json[key];

  if (value is num) {
    return value.toDouble();
  }

  if (value is String) {
    return num.tryParse(value)?.toDouble();
  }

  return null;
}

/// Reads [key] out of [json] as a Unix epoch, folding every no-expiry shape
/// into `null`.
///
/// `exp_date` is the field this exists for: `0`, a negative value, a missing
/// key and an unparsable string all mean "no expiry" on real panels (trial
/// and reseller accounts included), not a malformed response, per two
/// independent clients (`tvarr`, `iptvnator`). A caller must not read `0` as
/// "1970" or treat "unparsable" as a fault; both are the same no-expiry state
/// as a genuine `null`.
///
/// Returns the epoch seconds for any positive, parsable value.
int? readExpiryEpoch(Map<String, dynamic> json, String key) {
  final int? epoch = readInt(json, key);

  if (epoch == null || epoch <= 0) {
    return null;
  }

  return epoch;
}

/// Reads [key] out of [json] as base64-decoded text, falling back to the raw
/// string when it does not decode.
///
/// Covers `get_short_epg` / `get_simple_data_table`'s `title` and
/// `description`: the mock always base64-encodes them, but real panels
/// disagree about whether EPG text is encoded at all, and `iptvnator`'s
/// `decodeBase64Unicode` hedges exactly this way rather than trusting the
/// field's own contract.
///
/// Returns `null` when [key] is missing or not a string.
String? readBase64Text(Map<String, dynamic> json, String key) {
  final Object? value = json[key];

  if (value is! String) {
    return null;
  }

  try {
    return utf8.decode(base64.decode(value));
  } on FormatException {
    return value;
  }
}

/// Decodes an Xtream response body into a JSON map, accepting either shape
/// Dio hands back.
///
/// The panel answers `text/html` on some paths even for a JSON payload, which
/// makes Dio skip its JSON fast path and hand back the raw [String] instead of
/// an already-decoded [Map]. This reader accepts either.
///
/// Returns `null` when [body] is neither a map nor a decodable JSON string,
/// or when the decoded JSON is not itself an object.
Map<String, dynamic>? decodeBody(Object? body) {
  if (body is Map<String, dynamic>) {
    return body;
  }

  if (body is! String) {
    return null;
  }

  final Object? decoded;

  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return null;
  }

  return decoded is Map<String, dynamic> ? decoded : null;
}

/// Decodes an Xtream response body into a list of entries, accepting either
/// shape Dio hands back.
///
/// Seven of the ten actions answer with a JSON array rather than an object
/// (`tool/xtream-mock/server.mjs:255-280`): the three category actions, the
/// series list, the two stream lists and the EPG table. [decodeBody] returns
/// `null` for every one of them, so a list body needs its own reader rather
/// than a cast at the call site, and it needs the same `text/html` hedge:
/// a panel answering with the wrong content type makes Dio skip its JSON fast
/// path and hand back the raw [String].
///
/// A non-map element is skipped rather than throwing, and an element whose
/// keys are not strings is skipped too, because a caller reading fields by
/// name has nothing to do with either.
///
/// Returns `null` when [body] is neither a list nor a decodable JSON string,
/// or when the decoded JSON is not itself an array. That is distinct from an
/// empty list, which is what an unknown action and an empty category both
/// legitimately return.
List<Map<String, dynamic>>? decodeEntries(Object? body) {
  final Object? source;

  if (body is List) {
    source = body;
  } else if (body is String) {
    try {
      source = jsonDecode(body);
    } on FormatException {
      return null;
    }
  } else {
    return null;
  }

  if (source is! List) {
    return null;
  }

  return source.whereType<Map<String, dynamic>>().toList();
}
