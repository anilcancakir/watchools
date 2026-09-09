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
    check(
        'declared segment durations match the encode',
        declared.every((d) => encoded.includes(d)),
        `declared ${declared.join()} against encoded ${[...new Set(encoded)].join()}`,
    );
    check('the playlist carries a discontinuity sequence', /#EXT-X-DISCONTINUITY-SEQUENCE:\d+/.test(playlist));

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
    check('a lapsed token answers 403', afterExpiry.status === 403, String(afterExpiry.status));
    check('and says so in a short body', afterBody.trim() === 'Token expired', afterBody.slice(0, 40));

    // The client's recovery is to go back to the API for a fresh URL, so that
    // has to work while the old token is dead.
    const reminted = await fetch(`${BASE}/live/expiring/expiring/10001.m3u8`, { redirect: 'manual' });
    const freshUrl = reminted.headers.get('location') ?? '';
    check('a fresh redirect mints a new token', freshUrl !== shortUrl, 'the token did not change');
    const freshPlay = await fetch(freshUrl);
    check('and the new token plays', freshPlay.status === 200, String(freshPlay.status));
    await freshPlay.body?.cancel();

    // 13. VOD is where this protocol carries codec metadata.
    const vod = await json(`${API}?username=demo&password=demo&action=get_vod_info&vod_id=20002`);
    check('VOD reports its video codec', vod.info.video.codec_name === 'hevc');
    check('VOD reports its container', vod.movie_data.container_extension === 'mkv');
}

const panel = spawn('node', [join(HERE, 'server.mjs')], {
    env: { ...process.env, PORT: String(PORT), HOST: '127.0.0.1' },
    stdio: ['ignore', 'ignore', 'inherit'],
});

// The panel exits non-zero when media/ is missing, which is the common first
// run. Waiting on a fixed delay would report that as a wall of failed checks.
panel.on('exit', (code) => {
    if (code !== 0) {
        console.error('The panel could not start. Run: node tool/xtream-mock/encode.mjs');
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
