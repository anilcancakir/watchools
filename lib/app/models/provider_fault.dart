/// Why a user's IPTV provider is not answering.
///
/// Five values rather than one error, because over HTTP these look nearly
/// identical and from where the user sits they are opposite. A provider
/// refusing because it has too many open connections and a provider refusing
/// because the subscription lapsed both come back as a rejection; one wants a
/// minute and the other wants a new password. Collapsing them into a single
/// "bir şeyler ters gitti" is what makes someone re-type a working credential,
/// which is the failure this enum exists to prevent.
///
/// Two of the five withhold the retry, and they are the two the user has to
/// act on: [expired] and [wrongAddress]. The other three offer it, because for
/// those three the same request may well succeed on its own.
///
/// It is a fault about the PROVIDER, not about a screen, so the same value
/// reaches the line-up, the catalogue and a title page and says the same thing
/// on each. That is the opposite of an empty result, which means something
/// different on every surface and is why `GuideEmpty` and `LibraryEmpty` are
/// two components while this is one.
///
/// Loading is deliberately not a member. It is not a fault, and it is drawn as
/// a skeleton of the layout it replaces rather than as a message, so it shares
/// nothing with these but the branch it sits in.
///
/// `classifyProviderFault` (`lib/app/protocol/xtream/xtream_account.dart`) is
/// what produces one, from a parsed `XtreamAccount` plus the response that
/// followed it, and `ProviderNotice` renders all five.
enum ProviderFault {
  /// The host never answered: DNS failure, a timeout, a refused connection.
  ///
  /// The most common of the four in practice and the least alarming, because
  /// a residential connection and a reseller's host both drop out routinely. A
  /// retry is a real fix here rather than a hopeful one.
  unreachable,

  /// The provider answered and rejected the credentials.
  ///
  /// The only one of the four a retry cannot fix, which is why it is the only
  /// one that does not offer one. Usually a lapsed subscription rather than a
  /// mistyped password, because the credential worked until it did not.
  expired,

  /// The provider answered and refused for now: a rate limit, or a denial
  /// shape the panel does not disambiguate any further.
  ///
  /// Distinct from [expired] because the credential is fine, distinct from
  /// [unreachable] because the host is fine, and distinct from [evicted]
  /// because a retry here is free: nothing else has to give up a connection
  /// for this one to succeed.
  throttled,

  /// Something at that address answered, but it is not an Xtream panel.
  ///
  /// A redirect or a "no such thing here" against `player_api.php`, with a
  /// body that is not Xtream JSON. In practice: a port that is not the panel's,
  /// a host that puts a CDN or an https upgrade in front of it, or an address
  /// that was never a panel.
  ///
  /// The second of the two members that withhold the retry, and it exists
  /// because the first launch is now the case that produces it. Before a user
  /// could type an address, the base URL came from a define a developer had
  /// verified, and every denial the app could see was about the credential or
  /// the connection. Now a mistyped port is an ordinary first-run outcome, and
  /// [throttled] is what it used to report: copy stating a rate limit and
  /// asking the user to wait a few seconds, forever, for an address that will
  /// never answer.
  ///
  /// Distinct from [unreachable], which is nothing answering at all and where
  /// waiting genuinely helps. Distinct from [throttled] and [evicted], which
  /// are the panel refusing this request; here nothing refused anything,
  /// because whatever answered was never asked a question it understood.
  wrongAddress,

  /// The provider answered and refused because the subscription is already
  /// at its connection limit: alive, and fully booked on another device.
  ///
  /// The one member where a retry is not free: succeeding takes the slot
  /// another device is using right now, which is why it is not folded into
  /// [throttled]. An account's connection limit, not the wire response, is
  /// what earns this classification instead of the generic one.
  evicted,
}

/// Which faults are about what the user typed.
extension ProviderFaultRecovery on ProviderFault {
  /// Whether the recovery is to go and correct the stored credential, rather
  /// than to repeat the request.
  ///
  /// A predicate rather than an `==` at each call site, because there are
  /// three of those and adding [wrongAddress] to the enum silently left two of
  /// them offering a retry that could only ever fail the same way. A member
  /// added later answers this question here, once.
  bool get needsCredentials => this == ProviderFault.expired || this == ProviderFault.wrongAddress;
}
