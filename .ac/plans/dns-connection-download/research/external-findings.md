# External findings

Ten `ac:librarian` briefs ran on this exact topic immediately before this plan, across ten angles:
Dart-side resolver control, FFmpeg and libmpv DNS options, Android, Apple platforms, the Turkish
network reality, connection racing, peak-hour congestion, what competing IPTV clients ship, HTTP
layer wins, and download under a one-connection cap.

Everything below that is marked VERIFIED was re-read at source by the main thread before it was
allowed to move a decision. Everything marked REPORTED comes from a single agent and has not been
independently checked; the plan must not rest a step on one of those without checking it first.

## The measurements taken on the owner's own connection

Taken 2026-09-11 from a Turkish connection. The owner then stated the caveat himself: that line is
1 Gbit symmetric TurkNet with AdGuard on OpenWRT, so these numbers are the optimistic end and the
general audience is a plain TTNet or Superonline subscriber.

| What | Reading |
|---|---|
| Panel host A records | exactly one, TTL 300, no AAAA |
| Same lookup, ISP path versus 1.1.1.1 | identical answer, no hijack |
| Resolver latency | local 14 to 26 ms, 1.1.1.1 11 to 13 ms |
| A domain blocked in Turkey (`discord.com`) | real address from both, no block page |
| Round trip to the panel origin | 86 ms, 0% loss, stddev 0.2 ms |
| Path | Türk Telekom, then Telia, then NTT, terminating in the Netherlands |
| DoH to `cloudflare-dns.com` | reachable, 71 to 108 ms on a cold connection |

Three consequences the plan rests on:

- **Address racing buys nothing for this provider.** One A record means there is no second address
  to race. Happy Eyeballs work would be building a mechanism with no input.
- **Naive DoH is slower than the resolver it replaces**, 71 to 108 ms cold against 13 ms over UDP.
  DoH earns its place as a fallback for the failing case, never as the default path.
- **86 ms to the origin means four to five round trips before the first byte.** That is where the
  tap-to-first-frame budget actually goes, and it is not a DNS problem.

## VERIFIED: FFmpeg opens a second connection by default on HLS

`libavformat/hls.c` at SHA `38b88335f99e76ed89ff3c93f877fdefce736c13`:

```c
{"http_multiple", "Use multiple HTTP connections for fetching segments",
    OFFSET(http_multiple), AV_OPT_TYPE_BOOL, {.i64 = -1}, -1, 1, FLAGS},   // :2840
```

`-1` means auto, and auto resolves to on for any HTTP/1.1 or HTTP/2 server:

```c
if (c->http_multiple == -1) { ...
    c->http_multiple = (!strncmp(http_version_opt, "1.1", 3) || !strncmp(http_version_opt, "2.0", 3));
}                                                                          // :1710-1716
if (c->http_multiple == 1 && !v->input_next_requested && seg && ...)
    ret = open_input(c, v, seg, &v->input_next);                           // :1720-1722
```

On an account whose `max_connections` is 1, that second connection is the one this repository has
already measured as fatal: opening a second stream killed the first at 5.79 s
(`.ac/research/player-layer.md:218-231`). The player evicts itself.

Latent rather than live today, because `XtreamStreamUrl` builds a `.ts` URL and `hls.c` is not on
that path. It fires on the first panel that serves m3u8.

`http_persistent` is separately confirmed to default to 1 at `hls.c:2838-2839`, so segment and
playlist fetches already share one connection after the redirect resolves. Nothing to do there.

## VERIFIED: an address can be pinned on HTTP, and cannot on HTTPS

`libavformat/http.c:1617-1618` at the same SHA:

```c
if (!has_header(s->headers, "\r\nHost: "))
    av_bprintf(&request, "Host: %s\r\n", hoststr);
```

FFmpeg emits its own `Host` header only when the caller did not supply one. mpv feeds
`--http-header-fields` into that same `headers` AVOption, so a URL carrying a resolved IP plus a
`Host:` header naming the real host is supported behaviour rather than a trick.

HTTPS is the opposite, and it fails silently. `libavformat/tls.c:66-68` sets `numerichost` whenever
the connecting host parses as a literal address, and `libavformat/tls_openssl.c:869-880` gates the
entire verification block on it:

```c
if (!s->listen && !s->numerichost) {
    SSL_set_hostflags(c->ssl, X509_CHECK_FLAG_NO_PARTIAL_WILDCARDS);
    SSL_set1_host(c->ssl, s->host);            // hostname verification
    SSL_set_tlsext_host_name(c->ssl, s->host); // SNI
}
```

Pinning an HTTPS URL therefore drops SNI and hostname verification together, leaving only chain
validation. The `verifyhost` AVOption exists (`tls.h:86`) but is unreachable for a numeric host.

**So address pinning ships for `http://` and is refused for `https://`, with the refusal visible to
the user rather than silent.**

## VERIFIED: `--network-timeout` does not bound a resolver hang

FFmpeg's `getaddrinfo` call is a plain blocking libc call with no interrupt callback wired to it,
so mpv's `--network-timeout` cannot cut a resolver that never answers. REPORTED, with the source
read by the librarian at `libavformat/tcp.c:186` and `network.h:210-217`; the main thread verified
the surrounding option table but not this specific claim, so treat it as strong but unchecked.

The consequence is what matters and it does not depend on the line number: resolving in Dart, where
we own the timeout, converts an unbounded hang into a bounded failure we can classify.

## VERIFIED: our own documentation is wrong about the competition

`CLAUDE.md:184` and `.ac/research/stack-decisions.md:130-138` state that no app in this category
ships an in-app DNS setting. OwnTV's README line 94, read at source:

> App-wide **custom DNS** — System, Google, Cloudflare, Quad9, custom DNS or DNS-over-HTTPS; the
> selected resolver persists across restarts

OwnTV is the closest comparable: Android TV, libmpv-based (`MpvVideoSurface.kt`), and it ships a
mini player too. How it wires the resolver into mpv's byte fetch is not visible in the public tree.

Separately: the "Multi DNS" feature XCIPTV and IBO Player advertise is portal-address failover, not
name resolution. Marketing vocabulary, not evidence.

## REPORTED: the Turkish network reality

OONI's Turkey data confirms DNS tampering as the primary blocking channel, with Vodafone returning
`127.0.0.1` for Twitter in 2023 and Türk Telekom historically returning the block-page address
`195.175.254.2`. Superonline redirected 1.1.1.1 to an RFC1918 address in January 2024 and later
reversed it. So the failure the owner describes is real and its mechanism is documented.

The match-night slowdown is a different matter: no measurement study isolates it, and the evidence
that does exist points at structural congestion (thin international peering, shared last mile)
rather than at anything a client can route around. **Do not build football-aware logic.**

## REPORTED: platform ceilings for a DNS feature

| Platform | System-wide | Our own sockets |
|---|---|---|
| Android | `VpnService` only, and Play policy refuses it for a media app | OkHttp `Dns` or Cronet `HostResolverRules`, neither of which libmpv uses |
| iOS, macOS | `NEDNSSettingsManager`, needs the user to approve it in Settings | resolve ourselves and connect |
| tvOS | nothing at all | nothing that reaches libmpv |

Android can *read* `LinkProperties.getPrivateDnsServerName()`, which is enough to detect a device
whose strict-mode Private DNS points at a broken host and say so. That is a diagnostic, not a fix.

## REPORTED: peak-hour classification, and what is placebo

A throughput collapse shows as the input rate falling below the stream's bitrate while `underrun`
and `idle` are both false. That is distinguishable from the two freezes this repository has already
catalogued. Variant switching is placebo here: a switch is a full reopen, and all three of the
measured provider's variants are 1080p anyway.

A large forward buffer is largely theatre on live. hls.js targets 30 s and Shaka fetches one
segment ahead; the origin cannot serve a segment it has not published, so the playlist window is
the limit rather than our byte budget.

Confirmed placebo for this shape: raising `--stream-buffer-size`, setting `recv_buffer_size`,
HTTP/2 (FFmpeg's `http.c` cannot negotiate it), writing our own Happy Eyeballs (FFmpeg already
implements RFC 8305 at `network.c:298`), TCP Fast Open and TLS 0-RTT (not exposed), parallel
segment fetching, and a pre-warmed second mpv handle.

## VERIFIED: Apple TV cannot hold a downloaded film

Apple's own App Programming Guide for tvOS:

> The maximum size for a tvOS app bundle 4 GB. Moreover, your app can only access 500 KB of
> persistent storage that is local to the device (using the NSUserDefaults class). Outside of this
> limited local storage, all other data must be purgeable by the operating system when space is low.

A 3.44 GB film is not safe there. Download ships for iOS, Android, Android TV and macOS, and tvOS
is a stated platform stop rather than a later task.

## REPORTED: download mechanics under one connection

Single connection, `Range` plus `If-Range` against an `ETag` or `Last-Modified`, and on a `416`
drop the `Range` header entirely rather than resending it, which is a live bug in yt-dlp. Cheap
panel servers break resumption two ways: answering `200` with the whole body instead of `206`, and
serving a different body across attempts with no validator to detect it. Background transfer is
`URLSession` with a background configuration on Apple platforms and WorkManager on Android.

Multi-connection download is forbidden by the account rather than by the server: the server answers
`206` with a `Content-Range` over a 3.69 GB body. Even where allowed, the gain flattens fast,
modelled as `1 - 1/(1+cN)`.
