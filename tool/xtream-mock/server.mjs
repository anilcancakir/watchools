#!/usr/bin/env node
/**
 * A mock Xtream Codes panel for developing the watchools client against.
 *
 *   node tool/xtream-mock/encode.mjs      # once, generates the media
 *   node tool/xtream-mock/server.mjs      # then this, on 127.0.0.1:3300
 *
 * Zero dependencies on purpose. Express would buy routing worth about forty
 * lines here and cost a package.json, a lockfile and a node_modules tree in a
 * repository that has none of the three.
 *
 * Serves `player_api.php`, `get.php`, `xmltv.php`, the three stream URL shapes
 * and two spellings of the `xc` timeshift convention. Bound to loopback by
 * default because it authenticates only against a fixture table; set
 * HOST=0.0.0.0 deliberately when pointing a phone or a TV box at it.
 */

import { spawn, spawnSync } from 'node:child_process';
import { createServer } from 'node:http';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
    ACCOUNTS,
    CHANNELS,
    LIVE_CATEGORIES,
    SEGMENT_COUNT,
    SEGMENT_SECONDS,
    SHORT_TOKEN_SECONDS,
    TOKEN_SECONDS,
    UNKNOWN_ACCOUNT,
    VOD_CATEGORIES,
    VOD_ITEMS,
    epgWindow,
    panelTime,
} from './catalogue.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const MEDIA = join(HERE, 'media');
const PORT = Number(process.env['PORT'] ?? 3300);
const HOST = process.env['HOST'] ?? '127.0.0.1';

/** Panel timezone offset in minutes. Istanbul, so a client that ignores the offset is visibly wrong. */
const OFFSET_MINUTES = 180;
const TIMEZONE = 'Europe/Istanbul';

/** How many segments the live window advertises. Three is what a real panel typically exposes. */
const WINDOW_SEGMENTS = 3;

/** @type {Record<string, string>} */
const CONTENT_TYPES = {
    m3u8: 'application/vnd.apple.mpegurl',
    ts: 'video/mp2t',
    m4s: 'video/iso.segment',
    mp4: 'video/mp4',
    mkv: 'video/x-matroska',
    avi: 'video/x-msvideo',
};

/**
 * Resolves a credential pair to the account that decides how the panel answers.
 *
 * @param {string} username
 * @param {string} password
 * @returns {import('./catalogue.mjs').Account}
 */
function resolveAccount(username, password) {
    return ACCOUNTS[`${username}:${password}`] ?? UNKNOWN_ACCOUNT;
}

/**
 * Mints an opaque stream token, the way the real panel's load balancer does.
 *
 * Not signed and not secret: this is a fixture, and the only property that
 * matters is that it is opaque to the client and that it expires. Base64url so
 * it survives a URL path, which is where the real one lives.
 *
 * @param {string} username
 * @param {string} password
 * @param {number} now
 * @returns {string}
 */
function mintToken(username, password, now) {
    const account = resolveAccount(username, password);
    const ttl = account.kind === 'expiring' ? SHORT_TOKEN_SECONDS : TOKEN_SECONDS;

    return Buffer.from(`${username}:${password}:${now + ttl}`, 'utf8').toString('base64url');
}

/**
 * @typedef {object} TokenState
 * @property {string} username
 * @property {string} password
 * @property {boolean} expired
 */

/**
 * Reads a stream token back. A token that does not decode is treated as expired
 * rather than as a distinct case, because from the client's side both mean the
 * same thing: go back to the API and get a fresh URL.
 *
 * @param {string} token
 * @param {number} now
 * @returns {TokenState|null} Null when the token is not ours at all.
 */
function readToken(token, now) {
    let decoded = '';
    try {
        decoded = Buffer.from(token, 'base64url').toString('utf8');
    } catch {
        return null;
    }

    const parts = decoded.split(':');
    if (parts.length !== 3) return null;

    const expiry = Number(parts[2]);
    if (!Number.isFinite(expiry)) return null;

    return { username: parts[0], password: parts[1], expired: now >= expiry };
}

/**
 * Builds `user_info` in the shape real panels send, drift included: `auth` is a
 * bare integer while every other numeric field is a quoted string, which is
 * what the four captured panels agree on.
 *
 * @param {import('./catalogue.mjs').Account} account
 * @param {string} username
 * @param {string} password
 * @param {number} now
 * @returns {object}
 */
function userInfo(account, username, password, now) {
    // Exactly one key, which is what the real panel sends and what
    // `.ac/research/stack-decisions.md:264` records. A Dart model with a
    // non-nullable `status` or `exp_date` has to survive this, so padding the
    // shape out would hide the failure until a provider produced it.
    if (account.kind === 'rejected') {
        return { auth: 0 };
    }

    // A lapsed account is the reason a client cannot read `status` alone: the
    // panel still says Active and only the date betrays the dead subscription.
    const expired = account.kind === 'lapsed';

    return {
        username,
        password,
        message: '',
        auth: 1,
        status: account.kind === 'status' ? account.status : 'Active',
        // Null means lifetime, and it is the one expiry state the capture
        // corpus proves outright: testData/eternal/auth.json carries
        // "exp_date": null. A client comparing it as a date without a null
        // check reports the account that never expires as expired.
        exp_date: account.kind === 'lifetime' ? null : String(now + (expired ? -14 * 86400 : 365 * 86400)),
        is_trial: '0',
        active_cons: '1',
        created_at: String(now - 365 * 86400),
        max_connections: '2',
        allowed_output_formats: ['m3u8', 'ts'],
    };
}

/**
 * `server_info`, with `url` taken from the Host header rather than hardcoded:
 * a client that rebuilds stream URLs out of this block has to keep working when
 * the panel is reached from a phone instead of from loopback.
 *
 * @param {string} host
 * @param {number} now
 * @returns {object}
 */
function serverInfo(host, now) {
    const [hostname, port] = host.split(':');

    return {
        url: hostname,
        port: port ?? String(PORT),
        https_port: '',
        server_protocol: 'http',
        rtmp_port: '',
        timezone: TIMEZONE,
        timestamp_now: now,
        time_now: panelTime(now, OFFSET_MINUTES),
    };
}

/**
 * A live entry as `get_live_streams` sends it. `epg_channel_id` stays null on
 * the channel whose catalogue entry says null, and `category_id` is a string
 * next to an integer `tv_archive` in the same object, both on purpose.
 *
 * @param {import('./catalogue.mjs').Channel} channel
 * @param {number} index
 * @param {string} host
 * @returns {object}
 */
function liveEntry(channel, index, host) {
    return {
        num: index + 1,
        name: channel.name,
        stream_type: 'live',
        stream_id: channel.id,
        stream_icon: `http://${host}/logo/${channel.id}.svg`,
        epg_channel_id: channel.epgId,
        added: '1700000000',
        category_id: String(channel.categoryId),
        custom_sid: '',
        tv_archive: channel.archive,
        direct_source: '',
        tv_archive_duration: channel.archive === 1 ? 7 : 0,
    };
}

/**
 * @param {{id: number, name: string, ext: string}} item
 * @param {number} index
 * @param {string} host
 * @returns {object}
 */
function vodEntry(item, index, host) {
    return {
        num: index + 1,
        name: item.name,
        stream_type: 'movie',
        stream_id: item.id,
        stream_icon: `http://${host}/logo/${item.id}.svg`,
        rating: '7.5',
        rating_5based: 3.8,
        added: '1700000000',
        category_id: String(VOD_CATEGORIES[0].id),
        container_extension: item.ext,
        custom_sid: '',
        direct_source: '',
    };
}

/**
 * Answers one `player_api.php` action.
 *
 * @param {string} action
 * @param {URLSearchParams} query
 * @param {string} host
 * @param {number} now
 * @returns {object|null} Null when the action is unknown, which a real panel answers with an empty array.
 */
function dispatch(action, query, host, now) {
    const categoryFilter = query.get('category_id');
    const inCategory = (/** @type {number} */ id) => !categoryFilter || String(id) === categoryFilter;

    switch (action) {
        case 'get_live_categories':
            return LIVE_CATEGORIES.map((c) => ({
                category_id: String(c.id),
                category_name: c.name,
                parent_id: 0,
            }));

        case 'get_vod_categories':
            return VOD_CATEGORIES.map((c) => ({
                category_id: String(c.id),
                category_name: c.name,
                parent_id: 0,
            }));

        // An empty series list is not a gap in the mock: one of the four
        // captured panels answers `get_series` with exactly `[]`.
        case 'get_series_categories':
        case 'get_series':
            return [];

        case 'get_live_streams':
            return CHANNELS.filter((c) => inCategory(c.categoryId)).map((c, i) => liveEntry(c, i, host));

        case 'get_vod_streams':
            return VOD_ITEMS.filter(() => inCategory(VOD_CATEGORIES[0].id)).map((v, i) => vodEntry(v, i, host));

        case 'get_vod_info': {
            const item = VOD_ITEMS.find((v) => String(v.id) === query.get('vod_id'));
            if (!item) return { info: {}, movie_data: {} };

            return {
                // Unlike live, VOD is where this protocol really carries codec
                // metadata, so these are the fields a player can plan from.
                info: {
                    name: item.name,
                    o_name: item.name,
                    movie_image: `http://${host}/logo/${item.id}.svg`,
                    duration_secs: SEGMENT_COUNT * SEGMENT_SECONDS,
                    duration: '00:00:16',
                    video: { codec_name: item.video, width: 640, height: 360 },
                    audio: { codec_name: item.audio, channels: 2, sample_rate: '48000' },
                    bitrate: 800,
                },
                movie_data: {
                    stream_id: item.id,
                    name: item.name,
                    added: '1700000000',
                    category_id: String(VOD_CATEGORIES[0].id),
                    container_extension: item.ext,
                    custom_sid: '',
                    direct_source: '',
                },
            };
        }

        case 'get_short_epg': {
            const channel = CHANNELS.find((c) => String(c.id) === query.get('stream_id'));
            // A channel with no `epg_channel_id` has no guide, and this has to
            // agree with `xmltv.php`, which omits it. It did not: the JSON
            // surface returned a full schedule for channel 06 while the XMLTV
            // one had never heard of it, and the JSON surface is the one the
            // client reads first.
            if (!channel || !channel.epgId) return { epg_listings: [] };
            const limit = Number(query.get('limit') ?? 4);

            return { epg_listings: epgWindow(channel, now, limit).map((p, i) => epgListing(channel, p, i)) };
        }

        case 'get_simple_data_table': {
            const channel = CHANNELS.find((c) => String(c.id) === query.get('stream_id'));
            if (!channel || !channel.epgId) return { epg_listings: [] };

            return {
                epg_listings: epgWindow(channel, now, 12).map((p, i) => ({
                    ...epgListing(channel, p, i),
                    now_playing: p.start <= now && now < p.stop ? 1 : 0,
                    has_archive: channel.archive,
                })),
            };
        }

        default:
            return null;
    }
}

/**
 * One EPG listing. Title and description are base64 here and plain text in
 * `xmltv.php`, which is a real asymmetry rather than an inconsistency.
 *
 * @param {import('./catalogue.mjs').Channel} channel
 * @param {{title: string, description: string, start: number, stop: number}} programme
 * @param {number} index
 * @returns {object}
 */
function epgListing(channel, programme, index) {
    return {
        id: String(channel.id * 100 + index),
        epg_id: '1',
        title: Buffer.from(programme.title, 'utf8').toString('base64'),
        lang: 'tr',
        start: panelTime(programme.start, OFFSET_MINUTES),
        end: panelTime(programme.stop, OFFSET_MINUTES),
        description: Buffer.from(programme.description, 'utf8').toString('base64'),
        channel_id: channel.epgId ?? '',
        start_timestamp: String(programme.start),
        stop_timestamp: String(programme.stop),
    };
}

/** @type {Map<number, number[]>} Per channel, the real duration of each encoded segment. */
const durationCache = new Map();

/**
 * Reads the segment durations FFmpeg actually produced, from the playlist it
 * wrote beside them.
 *
 * Declaring a flat `SEGMENT_SECONDS` instead was wrong and expensively so:
 * forced keyframes land a 4.120 s final segment on channels 04 and 05, so the
 * playlist under-declared 120 ms per 16 s loop, about 27 s an hour, on two of
 * eight channels. That reads as a codec-specific player bug, which is the most
 * costly kind of false lead.
 *
 * @param {import('./catalogue.mjs').Channel} channel
 * @returns {number[]}
 */
function segmentDurations(channel) {
    const cached = durationCache.get(channel.id);
    if (cached) {
        return cached;
    }

    const source = join(MEDIA, String(channel.id), 'source.m3u8');
    const durations = readFileSync(source, 'utf8')
        .split('\n')
        .filter((line) => line.startsWith('#EXTINF:'))
        .map((line) => Number.parseFloat(line.slice('#EXTINF:'.length)));

    if (durations.length !== SEGMENT_COUNT) {
        throw new Error(
            `${channel.name} has ${durations.length} segments, expected ${SEGMENT_COUNT}. ` +
                'Regenerate with: node tool/xtream-mock/encode.mjs --force',
        );
    }

    durationCache.set(channel.id, durations);

    return durations;
}

/**
 * Synthesises a live HLS playlist over the pre-encoded loop.
 *
 * The media sequence advances with the wall clock and there is no ENDLIST, so a
 * player treats it as live rather than as a sixteen second VOD. Where the
 * window wraps past the last segment a DISCONTINUITY is emitted, because the
 * loop really does reset the timeline and a player told otherwise stalls.
 *
 * @param {import('./catalogue.mjs').Channel} channel
 * @param {number} now
 * @returns {string}
 */
function livePlaylist(channel, now) {
    const fmp4 = channel.segment === 'fmp4';
    const extension = fmp4 ? 'm4s' : 'ts';
    const sequence = Math.floor(now / SEGMENT_SECONDS);
    const first = sequence - (WINDOW_SEGMENTS - 1);
    const durations = segmentDurations(channel);

    const lines = [
        '#EXTM3U',
        `#EXT-X-VERSION:${fmp4 ? 7 : 3}`,
        `#EXT-X-TARGETDURATION:${Math.ceil(Math.max(...durations))}`,
        `#EXT-X-MEDIA-SEQUENCE:${first}`,
        // RFC 8216 section 6.2.1 derives a segment's discontinuity sequence
        // number from this tag plus the DISCONTINUITY tags above it. Without
        // the tag the same segment carried DSN 1 in one reload and DSN 0 in the
        // next, which is the mismatch hls.js reports as
        // "discontinuity sequence mismatch". The count is how many times the
        // loop has wrapped before this window.
        `#EXT-X-DISCONTINUITY-SEQUENCE:${Math.ceil(Math.max(first, 0) / SEGMENT_COUNT)}`,
    ];
    // Absolute segment paths, not relative names: the playlist is served from a
    // URL carrying the credentials, so a relative URI would both lose the
    // channel id and repeat the password on every segment request.
    const base = `/segments/${channel.id}`;
    if (fmp4) {
        lines.push(`#EXT-X-MAP:URI="${base}/init.mp4"`);
    }

    for (let offset = 0; offset < WINDOW_SEGMENTS; offset += 1) {
        const index = (((first + offset) % SEGMENT_COUNT) + SEGMENT_COUNT) % SEGMENT_COUNT;
        if (index === 0) {
            lines.push('#EXT-X-DISCONTINUITY');
        }
        lines.push(`#EXTINF:${durations[index].toFixed(3)},`);
        lines.push(`${base}/seg-${String(index).padStart(3, '0')}.${extension}`);
    }

    return `${lines.join('\n')}\n`;
}

/**
 * Streams a channel's progressive MPEG-TS endlessly.
 *
 * FFmpeg does the looping rather than this process re-sending the file, because
 * concatenating the same MPEG-TS bytes repeats their timestamps and a player
 * either stalls or jumps. `-stream_loop -1` rewrites them into one continuous
 * timeline and `-re` paces the output at playback rate, which is what makes the
 * endpoint behave like a real live channel instead of a download.
 *
 * @param {string} file
 * @param {import('node:http').ServerResponse} response
 */
function streamEndless(file, response) {
    // Guarded like sendFile, because a half finished encode leaves the tree
    // looking complete: encode.mjs refuses to re-run without --force once
    // media/ exists. Unguarded this answered 200 with zero bytes, which is
    // exactly the empty body channel 07's explicit 404 exists to avoid.
    if (!existsSync(file)) {
        response.writeHead(404, { 'Content-Type': 'text/plain' });
        response.end(`Not generated: ${file}\nRun: node tool/xtream-mock/encode.mjs --force\n`);
        return;
    }

    response.writeHead(200, { 'Content-Type': CONTENT_TYPES['ts'], 'Cache-Control': 'no-store' });

    const child = spawn(
        'ffmpeg',
        ['-hide_banner', '-loglevel', 'error', '-re', '-stream_loop', '-1', '-i', file, '-c', 'copy', '-f', 'mpegts', 'pipe:1'],
        { stdio: ['ignore', 'pipe', 'ignore'] },
    );

    // Without this the panel dies outright on the first progressive request
    // when ffmpeg is not on PATH: spawn emits 'error', nothing handles it, and
    // an unhandled 'error' event takes the process with it.
    child.on('error', (error) => {
        console.error(`ffmpeg could not start: ${error.message}`);
        response.destroy();
    });

    child.stdout.pipe(response);
    response.on('close', () => child.kill('SIGKILL'));
}

/**
 * Serves a file from the media tree.
 *
 * @param {string} file
 * @param {import('node:http').ServerResponse} response
 */
function sendFile(file, response) {
    if (!existsSync(file)) {
        response.writeHead(404, { 'Content-Type': 'text/plain' });
        response.end(`Not generated: ${file}\nRun: node tool/xtream-mock/encode.mjs\n`);
        return;
    }

    const extension = file.split('.').pop() ?? '';
    response.writeHead(200, {
        'Content-Type': CONTENT_TYPES[extension] ?? 'application/octet-stream',
        'Cache-Control': 'no-store',
    });
    response.end(readFileSync(file));
}

/**
 * Builds the `get.php` playlist. `m3u_plus` carries the per-entry attributes a
 * client maps EPG with; plain `m3u` carries none, which is the older shape.
 *
 * @param {string} username
 * @param {string} password
 * @param {string} host
 * @param {string} type
 * @param {string} output
 * @returns {string}
 */
function m3uPlaylist(username, password, host, type, output) {
    const plus = type === 'm3u_plus';
    const lines = ['#EXTM3U'];

    for (const channel of CHANNELS) {
        const category = LIVE_CATEGORIES.find((c) => c.id === channel.categoryId);
        const extension = channel.formats.includes(output) ? output : channel.formats[0];
        const attributes = plus
            ? ` tvg-id="${channel.epgId ?? ''}" tvg-name="${channel.name}"` +
              ` tvg-logo="http://${host}/logo/${channel.id}.svg" group-title="${category?.name ?? ''}"`
            : '';

        lines.push(`#EXTINF:-1${attributes},${channel.name}`);
        lines.push(`http://${host}/live/${username}/${password}/${channel.id}.${extension}`);
    }

    return `${lines.join('\n')}\n`;
}

/**
 * Builds the XMLTV guide. Titles here are plain text, unlike the base64 the
 * JSON EPG actions carry, and the offset keeps the space the DTD mandates: a
 * parser that only ever sees the spaceless form panels also emit will read
 * every one of these as UTC.
 *
 * @param {number} now
 * @returns {string}
 */
function xmltvGuide(now) {
    const stamp = (/** @type {number} */ seconds) =>
        `${panelTime(seconds, OFFSET_MINUTES).replace(/[-: ]/g, '')} +0300`;

    const lines = ['<?xml version="1.0" encoding="UTF-8"?>', '<tv generator-info-name="watchools-xtream-mock">'];

    for (const channel of CHANNELS) {
        if (!channel.epgId) continue;
        lines.push(`  <channel id="${channel.epgId}">`);
        lines.push(`    <display-name>${channel.name}</display-name>`);
        lines.push('  </channel>');
    }

    for (const channel of CHANNELS) {
        if (!channel.epgId) continue;
        for (const programme of epgWindow(channel, now, 12)) {
            lines.push(
                `  <programme start="${stamp(programme.start)}" stop="${stamp(programme.stop)}"` +
                    ` channel="${channel.epgId}">`,
            );
            lines.push(`    <title lang="tr">${programme.title}</title>`);
            lines.push(`    <desc lang="tr">${programme.description}</desc>`);
            lines.push('  </programme>');
        }
    }

    lines.push('</tv>');

    return `${lines.join('\n')}\n`;
}

/**
 * A local channel logo. Generated rather than fetched: the guide fixture once
 * pointed at picsum.photos and every session then raced hundreds of live
 * requests against the frames it was timing.
 *
 * @param {string} id
 * @returns {string}
 */
function logoSvg(id) {
    const hue = (Number(id) * 47) % 360;

    return (
        `<svg xmlns="http://www.w3.org/2000/svg" width="160" height="160">` +
        `<rect width="160" height="160" fill="hsl(${hue},45%,32%)"/>` +
        `<text x="80" y="98" font-family="sans-serif" font-size="52" fill="white"` +
        ` text-anchor="middle">${String(id).slice(-2)}</text></svg>`
    );
}

/** The landing page, so `open http://127.0.0.1:3300` explains the panel without opening this file. */
function indexPage(host) {
    const rows = Object.entries(ACCOUNTS)
        .map(([pair, account]) => `  ${pair.padEnd(22)} ${account.note}`)
        .join('\n');
    const channels = CHANNELS.map(
        (c) => `  ${String(c.id)}  ${c.name.padEnd(28)} formats: ${c.formats.join(', ')}`,
    ).join('\n');

    return (
        `watchools mock Xtream panel on http://${host}\n\n` +
        `Accounts\n${rows}\n  <anything else>       Unknown credentials, HTTP 200 with auth 0.\n\n` +
        `Channels\n${channels}\n\n` +
        `Try\n` +
        `  curl "http://${host}/player_api.php?username=demo&password=demo"\n` +
        `  curl "http://${host}/player_api.php?username=demo&password=demo&action=get_live_streams"\n` +
        `  ffplay "http://${host}/live/demo/demo/10001.m3u8"\n`
    );
}

/**
 * Answers a request whose credentials are not the happy path, if that is what
 * the account calls for.
 *
 * @param {import('./catalogue.mjs').Account} account
 * @param {import('node:http').ServerResponse} response
 * @returns {boolean} True when the request has been answered and must not continue.
 */
function handleFault(account, response) {
    // A panel's denial shape is a short plain-text body under HTTP 200, not a
    // status code. `.ac/research/stack-decisions.md:264` records the same:
    // "Plan for 200 with an empty body, 200 with the bare word blocked, 200
    // with HTML, and only occasionally a real 401." So a client keying on the
    // status code sees success, and the body is all it has to go on. That is
    // also why one body cannot tell throttled from blocked from expired.
    if (account.kind === 'blocked') {
        response.writeHead(200, { 'Content-Type': 'text/plain' });
        response.end('blocked');
        return true;
    }

    // Deliberately no response and no timeout: a provider that accepts the
    // connection and never answers is the half of unreachable that a dead port
    // cannot reproduce.
    if (account.kind === 'hang') {
        return true;
    }

    return false;
}

/**
 * Refuses a stream the way a panel really does: HTTP 200 with a short
 * plain-text body. Never a 403, which was this mock's own first answer and was
 * backwards. A client cannot tell this from a real stream by status code, so it
 * has to look at the first bytes, and learning that here is the point.
 *
 * @param {import('./catalogue.mjs').Account} account
 * @param {import('node:http').ServerResponse} response
 * @returns {boolean} True when the request has been refused and must not continue.
 */
function refuseStream(account, response) {
    // `expiring` is a playable account: its fault arrives later, when the
    // stream token it was given lapses.
    if (account.kind === 'active' || account.kind === 'lifetime' || account.kind === 'expiring') {
        return false;
    }

    // A provider that never answers does not answer here either, on the very
    // surface where that strands a viewer.
    if (account.kind === 'hang') {
        return true;
    }

    /** @type {Record<string, string>} */
    const bodies = {
        blocked: 'blocked',
        lapsed: 'Expired',
        rejected: 'No User Found',
    };

    response.writeHead(200, { 'Content-Type': 'text/plain' });
    response.end(bodies[account.kind] ?? account.status ?? 'Expired');

    return true;
}

/**
 * Answers either catch-up shape. The stream is the channel's ordinary loop; the
 * X-Timeshift-* headers carry what the panel understood, so a walk can assert
 * the client's derivation rather than only that something played.
 *
 * @param {import('./catalogue.mjs').Account} account
 * @param {string} channelId
 * @param {string} duration Minutes, in every Xtream catch-up convention.
 * @param {string} start
 * @param {import('node:http').ServerResponse} response
 */
function answerTimeshift(account, channelId, duration, start, response) {
    const channel = CHANNELS.find((c) => String(c.id) === channelId);

    if (refuseStream(account, response)) {
        return;
    }

    if (!channel || channel.archive !== 1) {
        // A channel without tv_archive has no catch-up, and a panel says so
        // rather than serving the live edge and letting the user believe the
        // seek worked.
        response.writeHead(404, { 'Content-Type': 'text/plain' });
        response.end(`No archive for channel ${channelId}\n`);
        return;
    }

    response.setHeader('X-Timeshift-Duration', duration);
    response.setHeader('X-Timeshift-Start', start);
    streamEndless(join(MEDIA, String(channel.id), 'raw.ts'), response);
}

/**
 * Serves the media itself, once a request has been through the redirect and its
 * token has been accepted. Reached only from the tokenised path, so nothing
 * here has to think about credentials or expiry.
 *
 * @param {string} kind `live`, `movie` or `series`.
 * @param {string} file
 * @param {number} now
 * @param {import('node:http').ServerResponse} response
 */
function serveStream(kind, file, now, response) {
    if (kind === 'movie') {
        const item = VOD_ITEMS.find((v) => file.startsWith(String(v.id)));
        if (!item) {
            response.writeHead(404, { 'Content-Type': 'text/plain' });
            response.end('No such movie\n');
            return;
        }
        sendFile(join(MEDIA, String(item.id), `movie.${item.ext}`), response);
        return;
    }

    // Everything below is live: either the channel's playlist or its
    // progressive stream. Segments are served from /segments/<id>/.
    const channel = CHANNELS.find((c) => String(c.id) === file.split('.')[0]);

    if (!channel) {
        response.writeHead(404, { 'Content-Type': 'text/plain' });
        response.end('No such channel\n');
        return;
    }

    const extension = file.split('.').pop() ?? '';
    if (!channel.formats.includes(extension)) {
        // AV1 has no MPEG-TS mapping, so channel 07 genuinely cannot serve a
        // `.ts`. Saying so beats an empty body a client reads as a decode
        // failure in its own player.
        response.writeHead(404, { 'Content-Type': 'text/plain' });
        response.end(
            `${channel.name} serves ${channel.formats.join(', ')} only.\n` +
                `AV1 has no MPEG-TS mapping; use the .m3u8 form.\n`,
        );
        return;
    }

    if (extension === 'm3u8') {
        response.writeHead(200, { 'Content-Type': CONTENT_TYPES['m3u8'], 'Cache-Control': 'no-store' });
        response.end(livePlaylist(channel, now));
        return;
    }

    streamEndless(join(MEDIA, String(channel.id), 'raw.ts'), response);
}

const server = createServer((request, response) => {
    const host = request.headers.host ?? `${HOST}:${PORT}`;
    const url = new URL(request.url ?? '/', `http://${host}`);
    const query = url.searchParams;
    const now = Math.floor(Date.now() / 1000);
    const path = url.pathname;

    console.log(`${request.method} ${path}${url.search}`);

    if (path === '/health') {
        response.writeHead(200, { 'Content-Type': 'application/json' });
        response.end(JSON.stringify({ status: 'ok', channels: CHANNELS.length }));
        return;
    }

    if (path === '/') {
        response.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
        response.end(indexPage(host));
        return;
    }

    if (path.startsWith('/logo/')) {
        response.writeHead(200, { 'Content-Type': 'image/svg+xml' });
        response.end(logoSvg(path.slice('/logo/'.length).replace('.svg', '')));
        return;
    }

    // The three API surfaces all authenticate the same query parameters.
    if (path === '/player_api.php' || path === '/get.php' || path === '/xmltv.php') {
        const username = query.get('username') ?? '';
        const password = query.get('password') ?? '';
        const account = resolveAccount(username, password);

        if (handleFault(account, response)) {
            return;
        }

        // Both playlist surfaces authenticate BEFORE they answer. Unguarded
        // they handed the whole catalogue to a wrong password, with the bad
        // credentials baked into every URL, so the app showed a working
        // provider whose every channel then failed. The real panel's playlist
        // generator refuses outright on a lapsed account.
        if (path === '/get.php' || path === '/xmltv.php') {
            if (account.kind === 'rejected') {
                response.writeHead(200, { 'Content-Type': 'text/plain' });
                response.end('');
                return;
            }

            if (path === '/get.php') {
                response.writeHead(200, { 'Content-Type': 'application/vnd.apple.mpegurl' });
                response.end(
                    m3uPlaylist(username, password, host, query.get('type') ?? 'm3u_plus', query.get('output') ?? 'ts'),
                );
                return;
            }

            response.writeHead(200, { 'Content-Type': 'application/xml' });
            response.end(xmltvGuide(now));
            return;
        }

        const action = query.get('action') ?? '';
        response.writeHead(200, { 'Content-Type': 'application/json' });

        // The handshake is the no-action call, and it is the only response a
        // rejected account gets: every listing action on bad credentials
        // answers an empty array, not an error.
        if (!action) {
            response.end(
                JSON.stringify({
                    user_info: userInfo(account, username, password, now),
                    server_info: serverInfo(host, now),
                }),
            );
            return;
        }

        if (account.kind === 'rejected') {
            response.end(JSON.stringify([]));
            return;
        }

        response.end(JSON.stringify(dispatch(action, query, host, now) ?? []));
        return;
    }

    // The tokenised path a redirect lands on. Everything past the redirect
    // reaches the stream handler through here, so token expiry is checked once.
    const played = path.match(/^\/(live|movie|series)\/play\/([^/]+)\/(.+)$/);
    if (played) {
        const [, kind, token, file] = played;
        const state = readToken(token, now);

        if (!state) {
            response.writeHead(404, { 'Content-Type': 'text/plain' });
            response.end('Not a stream token\n');
            return;
        }

        // A lapsed token is a 403 with a short body, which is the shape that
        // matters: mpv sets `reconnect=1` but leaves `reconnect_on_http_error`
        // empty, so FFmpeg refuses to reconnect on any 4xx and playback simply
        // ends. A client wanting to survive this has to pass
        // `reconnect_on_http_error=4xx,5xx` or go back to the API for a fresh
        // URL. The real panel does this after about forty minutes.
        if (state.expired) {
            console.log(`  token expired for ${kind}/${file}`);
            response.writeHead(403, { 'Content-Type': 'text/plain' });
            response.end('Token expired\n');
            return;
        }

        // The streaming host checks the account again rather than trusting the
        // token, because a subscription can lapse between the redirect and the
        // play, and because the token is not signed. A real load balancer does
        // the same for the same reason.
        if (refuseStream(resolveAccount(state.username, state.password), response)) {
            return;
        }

        serveStream(kind, file, now, response);
        return;
    }

    // Stream URLs: /live/:user/:pass/:file, /movie/..., /series/...
    // The real panel is a load balancer and never serves from here: it answers
    // 302 to a tokenised path, with `text/html` on the redirect itself. Without
    // that hop nothing in this repository exercises redirect handling, token
    // expiry, or a client that follows a redirect to a different origin.
    const stream = path.match(/^\/(live|movie|series)\/([^/]+)\/([^/]+)\/(.+)$/);
    if (stream) {
        const [, kind, username, password, file] = stream;
        const account = resolveAccount(username, password);

        // A dead subscription still lists its catalogue on a real panel and
        // only fails at the stream. Reproducing that is the point: it is the
        // shape where the app looks healthy and nothing plays. Checked before
        // the redirect, because a real panel refuses at the first hop.
        if (refuseStream(account, response)) {
            return;
        }

        const token = mintToken(username, password, now);
        response.writeHead(302, {
            // `text/html` on the redirect is what the real panel sends, and it
            // is worth reproducing: a client that sniffs the content type of
            // the first response rather than the last sees HTML where it
            // expected a playlist.
            'Content-Type': 'text/html; charset=UTF-8',
            Location: `http://${host}/${kind}/play/${token}/${file}`,
            'Cache-Control': 'no-store',
        });
        response.end('');
        return;
    }

    const segment = path.match(/^\/segments\/(\d+)\/(.+)$/);
    if (segment) {
        sendFile(join(MEDIA, segment[1], segment[2]), response);
        return;
    }

    // The two spellings of the `xc` catch-up convention. There are five in
    // total per stack-decisions.md:270 and the other three are not here. The
    // content is not really time shifted and the start is echoed rather than
    // validated, so a client's derivation is readable but a start in the wrong
    // timezone or format still gets a 200.
    const timeshift = path.match(/^\/timeshift\/([^/]+)\/([^/]+)\/(\d+)\/([^/]+)\/(\d+)\.ts$/);
    if (timeshift) {
        const [, username, password, duration, start, channelId] = timeshift;
        answerTimeshift(resolveAccount(username, password), channelId, duration, start, response);
        return;
    }

    if (path === '/streaming/timeshift.php') {
        answerTimeshift(
            resolveAccount(query.get('username') ?? '', query.get('password') ?? ''),
            query.get('stream') ?? '',
            query.get('duration') ?? '',
            query.get('start') ?? '',
            response,
        );
        return;
    }

    response.writeHead(404, { 'Content-Type': 'text/plain' });
    response.end('Not a panel endpoint\n');
});

if (!existsSync(MEDIA)) {
    console.error('media/ is missing. Run: node tool/xtream-mock/encode.mjs');
    process.exit(1);
}

// Probed at startup rather than discovered mid-session, because the
// progressive endpoint needs ffmpeg at request time and not only at encode
// time. A message here beats a dead panel on the first channel zap.
if (spawnSync('ffmpeg', ['-version'], { stdio: 'ignore' }).error) {
    console.error('ffmpeg is not on PATH. The progressive .ts endpoints will refuse; HLS still works.');
}

server.listen(PORT, HOST, () => {
    console.log(`Mock Xtream panel on http://${HOST}:${PORT}  (${CHANNELS.length} channels)`);
    console.log(`Open that URL for the account list, or curl the handshake:`);
    console.log(`  curl "http://${HOST}:${PORT}/player_api.php?username=demo&password=demo"`);
});
