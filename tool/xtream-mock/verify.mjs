#!/usr/bin/env node
/**
 * Checks the mock panel against the claims its README makes.
 *
 *   node tool/xtream-mock/verify.mjs
 *
 * Starts a panel on its own port, runs every case, and exits non-zero if any of
 * them failed.
 *
 * The load-bearing case is the codec one: it probes every channel through its
 * live HLS playlist over real HTTP and fails unless FFmpeg reports the pair the
 * channel's name claims. A mock whose channel 05 quietly serves AC-3 instead of
 * E-AC-3 is worse than no mock, because the client is then developed against a
 * codec matrix that does not exist.
 */

import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { CHANNELS, SHORT_TOKEN_SECONDS } from './catalogue.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const PORT = 3399;
const BASE = `http://127.0.0.1:${PORT}`;
const API = `${BASE}/player_api.php`;

/** FFmpeg encoder name to the codec name FFprobe reports back. */
const PROBED_AS = {
    libx264: 'h264',
    libx265: 'hevc',
    libsvtav1: 'av1',
    mpeg2video: 'mpeg2video',
    aac: 'aac',
    ac3: 'ac3',
    eac3: 'eac3',
    libmp3lame: 'mp3',
    mp2: 'mp2',
    libopus: 'opus',
};

let failures = 0;

/**
 * @param {string} what
 * @param {boolean} passed
 * @param {string} [detail]
 */
function check(what, passed, detail = '') {
    console.log(`${passed ? '  ok  ' : '  FAIL'}  ${what}${detail && !passed ? `  (${detail})` : ''}`);
    if (!passed) failures += 1;
}

/**
 * @param {string} url
 * @returns {Promise<any>}
 */
async function json(url) {
    const response = await fetch(url);
    return response.json();
}

/**
 * Reads the codec names FFprobe finds at a URL.
 *
 * @param {string} url
 * @returns {Promise<string[]>}
 */
function probe(url) {
    return new Promise((resolve) => {
        // stderr is discarded rather than piped: nothing drains it here, so a
        // verbose ffprobe failure would fill the pipe buffer and hang the run
        // instead of failing it.
        const child = spawn(
            'ffprobe',
            ['-v', 'error', '-show_entries', 'stream=codec_name', '-of', 'csv=p=0', url],
            { stdio: ['ignore', 'pipe', 'ignore'] },
        );

        let out = '';
        child.stdout.on('data', (chunk) => {
            out += chunk.toString();
        });
        child.on('close', () => resolve(out.split('\n').map((line) => line.replace(/,$/, '').trim()).filter(Boolean)));
    });
}

async function run() {
    // 1. The handshake's field types, which are the drift a tidy mock loses.
    const handshake = await json(`${API}?username=demo&password=demo`);
    const info = handshake.user_info;
    check('handshake authenticates', info.auth === 1);
    check('auth is a bare integer', typeof info.auth === 'number', typeof info.auth);
    check('max_connections is a string', typeof info.max_connections === 'string', typeof info.max_connections);
    check('exp_date is a string', typeof info.exp_date === 'string', typeof info.exp_date);
    check('server_info carries the clock pair', typeof handshake.server_info.timestamp_now === 'number');

    // 2. The two incompatible ways a dead subscription arrives. Each has to be
    //    invisible to the check that catches the other, or the disjunction the
    //    client implements is untested.
    const now = Math.floor(Date.now() / 1000);
    const expired = (await json(`${API}?username=expired&password=expired`)).user_info;
    const lapsed = (await json(`${API}?username=lapsed&password=lapsed`)).user_info;
    check('expired flags status', expired.status === 'Expired');
    check('expired hides behind a future date', Number(expired.exp_date) > now);
    check('lapsed keeps status Active', lapsed.status === 'Active');
    check('lapsed only shows in the date', Number(lapsed.exp_date) < now);

    // A lifetime account is the third expiry state, and the only one the
    // capture corpus proves outright. A date comparison without a null check
    // reads it as expired, so `Number(null)` being 0 is the trap.
    const lifetime = (await json(`${API}?username=lifetime&password=lifetime`)).user_info;
    check('lifetime carries a null exp_date', lifetime.exp_date === null, JSON.stringify(lifetime.exp_date));
    check('lifetime is otherwise active', lifetime.auth === 1 && lifetime.status === 'Active');

    // The rejected shape is one key. A Dart model with a non-nullable status or
    // exp_date has to survive it, and padding the shape out here would hide
    // that until a provider produced it.
    const rejected = (await json(`${API}?username=x&password=y`)).user_info;
    check('unknown credentials answer auth 0', rejected.auth === 0);
    check('the rejected shape carries only auth', Object.keys(rejected).length === 1, Object.keys(rejected).join());

    // 3. Throttling has no status code and no JSON field: a client keying on
    //    the status code sees a success here.
    const throttled = await fetch(`${API}?username=throttled&password=throttled`);
    const body = await throttled.text();
    check('throttled answers HTTP 200', throttled.status === 200, String(throttled.status));
    check('throttled body is not JSON', body.trim() === 'blocked', body.slice(0, 40));

    // 4. A dead account still lists its catalogue and only fails at the stream,
    //    and the refusal is HTTP 200 with a short text body rather than a
    //    status code. This mock's first answer was a 403, which was backwards:
    //    a client keying on the status code has to see success here and decide
    //    from the bytes, which is the lesson.
    const stale = await json(`${API}?username=expired&password=expired&action=get_live_streams`);
    check('a dead account still lists channels', Array.isArray(stale) && stale.length === CHANNELS.length);
    const denied = await fetch(`${BASE}/live/expired/expired/10001.m3u8`);
    const deniedBody = await denied.text();
    check('a stream refusal is HTTP 200, not a status code', denied.status === 200, String(denied.status));
    check('a stream refusal names the status in the body', deniedBody.trim() === 'Expired', deniedBody.slice(0, 40));
    const blockedStream = await fetch(`${BASE}/live/throttled/throttled/10001.m3u8`);
    check(
        'a throttled stream answers 200 and blocked',
        blockedStream.status === 200 && (await blockedStream.text()).trim() === 'blocked',
    );
    // The account exists to reproduce a provider that never answers, so the
    // stream is the one surface it must not answer on.
    const hung = await fetch(`${BASE}/live/hang/hang/10001.m3u8`, {
        signal: AbortSignal.timeout(1200),
    }).catch(() => null);
    check('a hanging provider never answers a stream', hung === null);

    // 5. Both playlist surfaces authenticate before they answer. Unguarded they
    //    handed the catalogue to a wrong password, so the app showed a working
    //    provider whose every channel then failed.
    const stolenM3u = await (await fetch(`${BASE}/get.php?username=nope&password=wrong`)).text();
    check('get.php refuses unknown credentials', !stolenM3u.includes('EXTINF'), stolenM3u.slice(0, 40));
    const stolenGuide = await (await fetch(`${BASE}/xmltv.php?username=nope&password=wrong`)).text();
    check('xmltv.php refuses unknown credentials', !stolenGuide.includes('<channel'), stolenGuide.slice(0, 40));

    // 6. The catalogue's own drift.
    const live = await json(`${API}?username=demo&password=demo&action=get_live_streams`);
    check('category_id is a string', typeof live[0].category_id === 'string');
    check('tv_archive is an integer', typeof live[0].tv_archive === 'number');
    check('one channel has a null epg id', live.some((/** @type {any} */ e) => e.epg_channel_id === null));

    // 7. EPG is base64 in JSON and plain text in XMLTV.
    const epg = await json(`${API}?username=demo&password=demo&action=get_short_epg&stream_id=10001&limit=2`);
    const title = Buffer.from(epg.epg_listings[0].title, 'base64').toString('utf8');
    check('EPG titles are base64', title.includes('H.264'), title);
    const guide = await (await fetch(`${BASE}/xmltv.php?username=demo&password=demo`)).text();
    check('XMLTV titles are plain text', guide.includes('<title lang="tr">01 H.264'));
    check('XMLTV keeps the offset space', /start="\d{14} \+0300"/.test(guide));

    // The two EPG surfaces have to agree about the channel with no guide. They
    // did not: the JSON one returned a full schedule for channel 06 while the
    // XMLTV one had never heard of it, and the JSON one is read first.
    const noGuide = await json(`${API}?username=demo&password=demo&action=get_short_epg&stream_id=10006`);
    check('a channel with no epg id has no listings', noGuide.epg_listings.length === 0);
    check('and XMLTV agrees', !guide.includes('06 MPEG-2'));

    // The declared segment durations have to match what FFmpeg produced.
    // Hardcoding 4.000 under-declared the 4.120 s final segment on two of eight
    // channels, drifting about 27 s an hour and reading as a codec-specific
    // player bug.
    const playlist = await (await fetch(`${BASE}/live/demo/demo/10005.m3u8`)).text();
    const source = readFileSync(join(HERE, 'media', '10005', 'source.m3u8'), 'utf8');
    const declared = [...playlist.matchAll(/#EXTINF:([\d.]+)/g)].map((m) => Number.parseFloat(m[1]));
    const encoded = [...source.matchAll(/#EXTINF:([\d.]+)/g)].map((m) => Number.parseFloat(m[1]));
    // To a millisecond, not exactly: the playlist declares three decimals, so
    // an 8.005333 s segment is served as 8.005 and an exact-membership test
    // fails on a value that is correct. What this has to catch is a declared
    // duration that does not correspond to any encoded one at all, which is
    // what the flat SEGMENT_SECONDS did.
    check(
        'declared segment durations match the encode',
        declared.every((d) => encoded.some((e) => Math.abs(e - d) < 0.001)),
        `declared ${declared.join()} against encoded ${[...new Set(encoded)].join()}`,
    );
    check('the playlist carries a discontinuity sequence', /#EXT-X-DISCONTINUITY-SEQUENCE:\d+/.test(playlist));

    // Segment URIs carry the absolute sequence rather than the loop index, so a
    // client never sees the same URI twice. They also have to resolve, which is
    // the half a regex on the playlist cannot tell you: the server maps the
    // sequence back to a file on disk modulo that channel's own segment count,
    // and an off-by-one there would serve the wrong segment with a 200.
    const uris = [...playlist.matchAll(/^\/segments\/\d+\/s-(\d+)\.ts$/gm)].map((m) => Number(m[1]));
    check('segment URIs carry the absolute sequence', uris.length === 3, `found ${uris.length}`);
    check(
        'and increase by one across the window',
        uris.length === 3 && uris[1] === uris[0] + 1 && uris[2] === uris[1] + 1,
        uris.join(),
    );
    const slidingUri = playlist.match(/^\/segments\/\d+\/s-\d+\.ts$/m)?.[0] ?? '';
    const sliding = await fetch(`${BASE}${slidingUri}`);
    const slidingBytes = Buffer.from(await sliding.arrayBuffer());
    const onDisk = readFileSync(
        join(HERE, 'media', '10005', `seg-${String(uris[0] % encoded.length).padStart(3, '0')}.ts`),
    );
    check('a sliding URI resolves', sliding.status === 200, `${sliding.status} for ${slidingUri}`);
    check('to the loop position it names', slidingBytes.equals(onDisk), `${slidingBytes.length} bytes`);

    // 8. The claim the whole tool exists for.
    for (const channel of CHANNELS) {
        const found = await probe(`${BASE}/live/demo/demo/${channel.id}.m3u8`);
        const want = [PROBED_AS[channel.video], PROBED_AS[channel.audio]];
        check(
            `${channel.name} decodes as ${want.join(' + ')}`,
            want.every((codec) => found.includes(codec)),
            `probed ${found.join(', ') || 'nothing'}`,
        );
    }

    // 9. AV1 has no MPEG-TS mapping, and the mock says so rather than serving
    //    an empty body the client blames its own player for.
    const av1 = await fetch(`${BASE}/live/demo/demo/10007.ts`);
    check('AV1 refuses .ts with a reason', av1.status === 404 && (await av1.text()).includes('MPEG-TS'));

    // 10. Catch-up: both conventions parse, and a channel without an archive
    //    fails loudly instead of serving the live edge.
    const shift = await fetch(`${BASE}/timeshift/demo/demo/60/2026-09-09:01-30/10001.ts`);
    check('timeshift echoes the duration', shift.headers.get('x-timeshift-duration') === '60');
    await shift.body?.cancel();
    const viaPhp = await fetch(`${BASE}/streaming/timeshift.php?username=demo&password=demo&stream=10001&start=1&duration=90`);
    check('timeshift.php echoes the duration', viaPhp.headers.get('x-timeshift-duration') === '90');
    await viaPhp.body?.cancel();
    const noArchive = await fetch(`${BASE}/timeshift/demo/demo/60/2026-09-09:01-30/10003.ts`);
    check('a channel without an archive refuses catch-up', noArchive.status === 404);

    // 11. The redirect hop. The real panel is a load balancer and never serves
    //     a stream from the URL the client built: it answers 302 to a tokenised
    //     path. Without this nothing here exercises redirect handling at all.
    const hop = await fetch(`${BASE}/live/demo/demo/10001.m3u8`, { redirect: 'manual' });
    check('a stream URL answers 302', hop.status === 302, String(hop.status));
    const location = hop.headers.get('location') ?? '';
    check('the redirect carries a tokenised path', /\/live\/play\/[A-Za-z0-9_-]+\/10001\.m3u8$/.test(location), location);
    // Worth pinning: a client that reads the content type of the FIRST response
    // rather than the last sees HTML where it expected a playlist.
    check('the redirect itself is text/html', (hop.headers.get('content-type') ?? '').startsWith('text/html'));

    const followed = await (await fetch(`${BASE}/live/demo/demo/10001.m3u8`)).text();
    check('following the redirect reaches the playlist', followed.startsWith('#EXTM3U'), followed.slice(0, 30));

    const badToken = await fetch(`${BASE}/live/play/not-a-real-token/10001.m3u8`);
    check('an unreadable token is 404, not 403', badToken.status === 404, String(badToken.status));

    // 12. Token expiry mid-playback, which is the case FFmpeg's defaults get
    //     wrong: mpv sets `reconnect=1` but leaves `reconnect_on_http_error`
    //     empty, so a 403 ends playback instead of reconnecting.
    const shortHop = await fetch(`${BASE}/live/expiring/expiring/10001.m3u8`, { redirect: 'manual' });
    const shortUrl = shortHop.headers.get('location') ?? '';
    check('the expiring account also gets a token', shortUrl.includes('/live/play/'), shortUrl);

    const beforeExpiry = await fetch(shortUrl);
    check('its token works at first', beforeExpiry.status === 200, String(beforeExpiry.status));
    await beforeExpiry.body?.cancel();

    // The account's TTL is SHORT_TOKEN_SECONDS; wait past it.
    await new Promise((resolve) => setTimeout(resolve, (SHORT_TOKEN_SECONDS + 2) * 1000));

    const afterExpiry = await fetch(shortUrl);
    const afterBody = await afterExpiry.text();
    // 509, measured on the real panel rather than assumed. It is a 5xx, so a
    // client reads "server error, retry" where the only action that helps is
    // re-resolving through the API, and there is no body to sniff either.
    check('a lapsed token answers 509', afterExpiry.status === 509, String(afterExpiry.status));
    check('and its body is empty', afterBody.length === 0, `${afterBody.length} bytes`);
    check('and it closes the connection', (afterExpiry.headers.get('connection') ?? '') === 'close');

    // The client's recovery is to go back to the API for a fresh URL, so that
    // has to work while the old token is dead.
    const reminted = await fetch(`${BASE}/live/expiring/expiring/10001.m3u8`, { redirect: 'manual' });
    const freshUrl = reminted.headers.get('location') ?? '';
    check('a fresh redirect mints a new token', freshUrl !== shortUrl, 'the token did not change');
    const freshPlay = await fetch(freshUrl);
    check('and the new token plays', freshPlay.status === 200, String(freshPlay.status));
    await freshPlay.body?.cancel();

    // 13. Byte ranges, which decide seeking, resume and download, and which
    //     this fixture answered with a chunked 200 until it was measured
    //     against the real panel. FFmpeg then reads a 3 GB film as an
    //     unseekable stream, and Media3 seeks by discarding bytes forward.
    const ranged = await fetch(`${BASE}/movie/demo/demo/20001.mp4`, {
        headers: { Range: 'bytes=1000-2047' },
    });
    const rangedBody = await ranged.arrayBuffer();
    check('a Range request answers 206', ranged.status === 206, String(ranged.status));
    check('with the exact slice asked for', rangedBody.byteLength === 1048, `${rangedBody.byteLength} bytes`);
    const contentRange = ranged.headers.get('content-range') ?? '';
    check('and a Content-Range naming the total', /^bytes 1000-2047\/\d+$/.test(contentRange), contentRange);

    const whole = await fetch(`${BASE}/movie/demo/demo/20001.mp4`);
    await whole.body?.cancel();
    check('an unranged request carries a Content-Length', (whole.headers.get('content-length') ?? '') !== '');
    // The real panel spells this `0-<total>` rather than `bytes`, so FFmpeg's
    // prefix match fails and it falls back to Content-Range. A hand-rolled
    // check for the literal string `bytes` is the code this catches.
    check(
        'and the panel-shaped Accept-Ranges',
        /^0-\d+$/.test(whole.headers.get('accept-ranges') ?? ''),
        whole.headers.get('accept-ranges') ?? 'absent',
    );

    // A tail range is how a client reads an MP4's trailing moov atom.
    const tail = await fetch(`${BASE}/movie/demo/demo/20001.mp4`, { headers: { Range: 'bytes=-512' } });
    check('a tail range answers 206', tail.status === 206, String(tail.status));
    check('with 512 bytes', (await tail.arrayBuffer()).byteLength === 512);

    const silly = await fetch(`${BASE}/movie/demo/demo/20001.mp4`, {
        headers: { Range: 'bytes=999999999-' },
    });
    check('an unsatisfiable range answers 416', silly.status === 416, String(silly.status));

    // 14. VOD is where this protocol carries codec metadata.
    const vod = await json(`${API}?username=demo&password=demo&action=get_vod_info&vod_id=20002`);
    check('VOD reports its video codec', vod.info.video.codec_name === 'hevc');
    check('VOD reports its container', vod.movie_data.container_extension === 'mkv');

    // 15. Real panels disagree on whether EPG text is base64: iptvnator's
    //     `decodeBase64Unicode` falls back to the raw string on a decode
    //     failure. `demo` always encodes, so this account is the other half.
    const plainEpg = await json(
        `${API}?username=plaintext&password=plaintext&action=get_short_epg&stream_id=10001&limit=1`,
    );
    check(
        'a plain-text EPG account sends title as-is',
        plainEpg.epg_listings[0].title.includes('H.264'),
        plainEpg.epg_listings[0].title,
    );

    // 16. `exp_date: "0"` is a real no-expiry spelling next to null, and a
    //     naive date comparison reads it as 1970 rather than never expiring.
    const zeroExpiry = (await json(`${API}?username=zeroexpiry&password=zeroexpiry`)).user_info;
    check('exp_date 0 means no expiry, not 1970', zeroExpiry.exp_date === '0', zeroExpiry.exp_date);
    check('and the account is otherwise active', zeroExpiry.auth === 1 && zeroExpiry.status === 'Active');

    // 17. Some panels implement only the typo'd `get_simple_date_table`
    //     ("date", not "data"). The documented spelling has to look like an
    //     unimplemented action, empty rather than an error, or a client has
    //     no signal to retry on.
    const typoWrong = await json(
        `${API}?username=datetypo&password=datetypo&action=get_simple_data_table&stream_id=10001`,
    );
    check('the documented spelling answers empty on a typo-only panel', typoWrong.epg_listings.length === 0);
    const typoRight = await json(
        `${API}?username=datetypo&password=datetypo&action=get_simple_date_table&stream_id=10001`,
    );
    check('the typo\'d spelling answers for real', typoRight.epg_listings.length > 0, JSON.stringify(typoRight));

    // 18. A panel that refuses the bare handshake, so a client has to try
    //     `get_account_info` instead. `xtream_client.dart` does not implement
    //     that fallback yet, so this only records the wire shape it would
    //     need: the bare call answers nothing usable and the named action
    //     carries the real payload.
    const bareRefused = await json(`${API}?username=accountinfo&password=accountinfo`);
    check(
        'a refusing panel answers nothing useful on the bare handshake',
        bareRefused.user_info === undefined,
        JSON.stringify(bareRefused),
    );
    const viaAccountInfo = await json(
        `${API}?username=accountinfo&password=accountinfo&action=get_account_info`,
    );
    check('and answers get_account_info instead', viaAccountInfo.user_info?.auth === 1, JSON.stringify(viaAccountInfo));
}

const panel = spawn('node', [join(HERE, 'server.mjs')], {
    env: { ...process.env, PORT: String(PORT), HOST: '127.0.0.1' },
    stdio: ['ignore', 'ignore', 'inherit'],
});

// The panel exits non-zero when media/ is missing, which is the common first
// run, and when its port is taken, which is the common second one. Naming only
// the first was wrong: a leftover server from an interrupted run reported itself
// as a missing encode. The child's stderr is inherited, so it has already said
// which it was; do not guess over the top of it.
panel.on('exit', (code) => {
    if (code !== 0) {
        console.error(`\nThe panel exited with code ${code} before the checks could run.`);
        console.error('Its own error is above. Two usual causes: media/ is missing');
        console.error(`(run node tool/xtream-mock/encode.mjs) or port ${PORT} is still held`);
        console.error('by an earlier run (lsof -ti :' + PORT + ' | xargs kill).');
        process.exit(1);
    }
});

setTimeout(() => {
    run()
        .then(() => {
            console.log(failures === 0 ? '\nAll checks passed.' : `\n${failures} check(s) failed.`);
            panel.kill('SIGKILL');
            process.exit(failures === 0 ? 0 : 1);
        })
        .catch((error) => {
            console.error(`\n${error.stack}`);
            panel.kill('SIGKILL');
            process.exit(1);
        });
}, 400);
