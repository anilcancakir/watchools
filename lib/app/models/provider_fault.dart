/// Why a user's IPTV provider is not answering.
///
/// Three values rather than one error, because over HTTP these look nearly
/// identical and from where the user sits they are opposite. A provider
/// refusing because it has too many open connections and a provider refusing
/// because the subscription lapsed both come back as a rejection; one wants a
/// minute and the other wants a new password. Collapsing them into a single
/// "bir şeyler ters gitti" is what makes someone re-type a working credential,
/// which is the failure this enum exists to prevent.
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
/// Nothing produces one yet. There is no protocol layer, so the values below
/// are the vocabulary the Xtream client will report in and the panel that
/// renders them is reviewable at `/preview` until it does.
enum ProviderFault {
  /// The host never answered: DNS failure, a timeout, a refused connection.
  ///
  /// The most common of the three in practice and the least alarming, because
  /// a residential connection and a reseller's host both drop out routinely. A
  /// retry is a real fix here rather than a hopeful one.
  unreachable,

  /// The provider answered and rejected the credentials.
  ///
  /// The only one of the three a retry cannot fix, which is why it is the only
  /// one that does not offer one. Usually a lapsed subscription rather than a
  /// mistyped password, because the credential worked until it did not.
  expired,

  /// The provider answered and refused for now: a connection limit, or a rate
  /// limit after too many requests.
  ///
  /// Distinct from [expired] because the credential is fine, and distinct from
  /// [unreachable] because the host is fine. A shared subscription being used
  /// on another device is the everyday cause, and saying so is what stops the
  /// user going to their credentials to fix something that is not broken.
  throttled,
}
