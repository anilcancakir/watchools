#!/usr/bin/env node
/**
 * Checks the mock panel against the claims its README makes.
 *
 *   node tool/xtream-mock/verify.mjs
 *
 * Starts a panel on its own port, asserts, exits non-zero on the first failure.
 * The load-bearing case is the codec one: it probes every channel through its
 * live HLS playlist over real HTTP and fails unless FFmpeg reports the pair the
 * channel's name claims. A mock whose channel 05 quietly serves AC-3 instead of
 * E-AC-3 is worse than no mock, because the client is then developed against a
 * codec matrix that does not exist.
 */

import { spawn } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { CHANNELS } from './catalogue.mjs';

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
        const child = spawn('ffprobe', [
            '-v', 'error',
            '-show_entries', 'stream=codec_name',
            '-of', 'csv=p=0',
            url,
        ]);

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
    check('unknown credentials answer auth 0', (await json(`${API}?username=x&password=y`)).user_info.auth === 0);

    // 3. Throttling has no status code and no JSON field: a client keying on
    //    the status code sees a success here.
    const throttled = await fetch(`${API}?username=throttled&password=throttled`);
    const body = await throttled.text();
    check('throttled answers HTTP 200', throttled.status === 200, String(throttled.status));
    check('throttled body is not JSON', body.trim() === 'blocked', body.slice(0, 40));

    // 4. A dead account still lists its catalogue and only fails at the stream.
    const stale = await json(`${API}?username=expired&password=expired&action=get_live_streams`);
    check('a dead account still lists channels', Array.isArray(stale) && stale.length === CHANNELS.length);
    const denied = await fetch(`${BASE}/live/expired/expired/10001.m3u8`);
    check('a dead account cannot stream', denied.status === 403, String(denied.status));

    // 5. The catalogue's own drift.
    const live = await json(`${API}?username=demo&password=demo&action=get_live_streams`);
    check('category_id is a string', typeof live[0].category_id === 'string');
    check('tv_archive is an integer', typeof live[0].tv_archive === 'number');
    check('one channel has a null epg id', live.some((/** @type {any} */ e) => e.epg_channel_id === null));

    // 6. EPG is base64 in JSON and plain text in XMLTV.
    const epg = await json(`${API}?username=demo&password=demo&action=get_short_epg&stream_id=10001&limit=2`);
    const title = Buffer.from(epg.epg_listings[0].title, 'base64').toString('utf8');
    check('EPG titles are base64', title.includes('H.264'), title);
    const guide = await (await fetch(`${BASE}/xmltv.php?username=demo&password=demo`)).text();
    check('XMLTV titles are plain text', guide.includes('<title lang="tr">01 H.264'));
    check('XMLTV keeps the offset space', /start="\d{14} \+0300"/.test(guide));

    // 7. The claim the whole tool exists for.
    for (const channel of CHANNELS) {
        const found = await probe(`${BASE}/live/demo/demo/${channel.id}.m3u8`);
        const want = [PROBED_AS[channel.video], PROBED_AS[channel.audio]];
        check(
            `${channel.name} decodes as ${want.join(' + ')}`,
            want.every((codec) => found.includes(codec)),
            `probed ${found.join(', ') || 'nothing'}`,
        );
    }

    // 8. AV1 has no MPEG-TS mapping, and the mock says so rather than serving
    //    an empty body the client blames its own player for.
    const av1 = await fetch(`${BASE}/live/demo/demo/10007.ts`);
    check('AV1 refuses .ts with a reason', av1.status === 404 && (await av1.text()).includes('MPEG-TS'));

    // 9. Catch-up: both conventions parse, and a channel without an archive
    //    fails loudly instead of serving the live edge.
    const shift = await fetch(`${BASE}/timeshift/demo/demo/60/2026-09-09:01-30/10001.ts`);
    check('timeshift echoes the duration', shift.headers.get('x-timeshift-duration') === '60');
    await shift.body?.cancel();
    const viaPhp = await fetch(`${BASE}/streaming/timeshift.php?username=demo&password=demo&stream=10001&start=1&duration=90`);
    check('timeshift.php echoes the duration', viaPhp.headers.get('x-timeshift-duration') === '90');
    await viaPhp.body?.cancel();
    const noArchive = await fetch(`${BASE}/timeshift/demo/demo/60/2026-09-09:01-30/10003.ts`);
    check('a channel without an archive refuses catch-up', noArchive.status === 404);

    // 10. VOD is where this protocol carries codec metadata.
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
