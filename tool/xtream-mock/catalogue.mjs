/**
 * The mock panel's data: accounts, the codec matrix, categories and EPG.
 *
 * Every wire shape here was taken from real captured panel responses in
 * `tellytv/go.xtream-codes` `testData/` (four panels, MIT) rather than from a
 * description of the protocol, because the types drift: in one and the same
 * object `category_id` is a string while `parent_id` is an integer, `auth` is a
 * bare integer while `max_connections` is a string, and `epg_channel_id` is
 * nullable. A client that assumes a fixed JSON type for a numeric field breaks
 * on a real provider, so the mock reproduces the drift instead of tidying it.
 */

/** Seconds a single HLS segment covers. Fixed so the live window needs no playlist parsing. */
export const SEGMENT_SECONDS = 4;

/** Segments `encode.mjs` writes per channel. The loop is SEGMENT_COUNT * SEGMENT_SECONDS long. */
export const SEGMENT_COUNT = 4;

/**
 * What a panel does when the credentials are not the happy path.
 *
 * The three product faults do not map one to one onto three wire shapes. An
 * expired subscription arrives two incompatible ways (see `lapsed` below), and
 * throttling has no shape of its own at all: it is inferred from a body that is
 * not JSON. `unreachable` needs no account, a dead port produces it, but `hang`
 * is the more interesting half of it because a provider that accepts the
 * connection and never answers is what actually strands a client.
 *
 * @typedef {'active' | 'status' | 'lapsed' | 'blocked' | 'hang' | 'rejected'} AccountKind
 */

/**
 * @typedef {object} Account
 * @property {AccountKind} kind      How the panel answers this credential pair.
 * @property {string} [status]       `user_info.status` when kind is 'status'.
 * @property {string} note           Why the account exists, echoed by the README and the index page.
 */

/** @type {Record<string, Account>} */
export const ACCOUNTS = {
    'demo:demo': {
        kind: 'active',
        note: 'The working account. Every channel below plays.',
    },
    'expired:expired': {
        kind: 'status',
        status: 'Expired',
        note: 'auth 1 with status Expired. The variant sharktie/lg-iptv branches on.',
    },
    'lapsed:lapsed': {
        kind: 'lapsed',
        note: 'auth 1, status Active, exp_date in the past. Expiry that only a date comparison catches.',
    },
    'banned:banned': {
        kind: 'status',
        status: 'Banned',
        note: 'auth 1 with status Banned.',
    },
    'disabled:disabled': {
        kind: 'status',
        status: 'Disabled',
        note: 'auth 1 with status Disabled.',
    },
    'throttled:throttled': {
        kind: 'blocked',
        note: 'HTTP 200 carrying the bare word blocked. Not JSON, which is the only throttling signal there is.',
    },
    'hang:hang': {
        kind: 'hang',
        note: 'Accepts the connection and never answers. Unreachable without a refused connection.',
    },
};

/** Any credential pair that is not in ACCOUNTS answers `auth: 0` with HTTP 200, as a real panel does. */
export const UNKNOWN_ACCOUNT = /** @type {Account} */ ({
    kind: 'rejected',
    note: 'Unknown credentials. HTTP 200 with auth 0, never a 401.',
});

/**
 * @typedef {object} Channel
 * @property {number} id             Xtream `stream_id`. Live ids start at 10001 by panel convention.
 * @property {string} name           Carries the codec pair, because live entries have no codec field.
 * @property {number} categoryId     Owning category. Grouped by container, not by genre.
 * @property {'ts' | 'fmp4'} segment HLS segment container.
 * @property {string[]} formats      Extensions this channel really serves. AV1 has no MPEG-TS form.
 * @property {string|null} epgId     `epg_channel_id`. Null on one channel on purpose: the field is nullable.
 * @property {number} archive        `tv_archive`, 1 where catch-up should be derivable.
 * @property {string} video          FFmpeg video encoder, read by encode.mjs.
 * @property {string} audio          FFmpeg audio encoder, read by encode.mjs.
 */

/**
 * The codec matrix. One channel per combination worth developing against, named
 * so the combination is readable off the screen while the app is running.
 *
 * @type {Channel[]}
 */
export const CHANNELS = [
    {
        id: 10001,
        name: '01 H.264 AAC | HLS/TS',
        categoryId: 101,
        segment: 'ts',
        formats: ['m3u8', 'ts'],
        epgId: 'codec01.mock',
        archive: 1,
        video: 'libx264',
        audio: 'aac',
    },
    {
        id: 10002,
        name: '02 H.264 AAC | RAW TS',
        categoryId: 103,
        segment: 'ts',
        formats: ['m3u8', 'ts'],
        epgId: 'codec02.mock',
        archive: 1,
        video: 'libx264',
        audio: 'aac',
    },
    {
        id: 10003,
        name: '03 H.264 AC-3 | HLS/TS',
        categoryId: 101,
        segment: 'ts',
        formats: ['m3u8', 'ts'],
        epgId: 'codec03.mock',
        archive: 0,
        video: 'libx264',
        audio: 'ac3',
    },
    {
        id: 10004,
        name: '04 H.265 AAC | HLS/fMP4',
        categoryId: 102,
        segment: 'fmp4',
        formats: ['m3u8', 'ts'],
        epgId: 'codec04.mock',
        archive: 0,
        video: 'libx265',
        audio: 'aac',
    },
    {
        id: 10005,
        name: '05 H.265 E-AC-3 | HLS/TS',
        categoryId: 101,
        segment: 'ts',
        formats: ['m3u8', 'ts'],
        epgId: 'codec05.mock',
        archive: 0,
        video: 'libx265',
        audio: 'eac3',
    },
    {
        id: 10006,
        name: '06 MPEG-2 MP2 | RAW TS',
        categoryId: 103,
        segment: 'ts',
        formats: ['m3u8', 'ts'],
        epgId: null,
        archive: 0,
        video: 'mpeg2video',
        audio: 'mp2',
    },
    {
        id: 10007,
        name: '07 AV1 Opus | HLS/fMP4',
        categoryId: 102,
        segment: 'fmp4',
        formats: ['m3u8'],
        epgId: 'codec07.mock',
        archive: 0,
        video: 'libsvtav1',
        audio: 'libopus',
    },
    {
        id: 10008,
        name: '08 H.264 MP3 | HLS/TS',
        categoryId: 101,
        segment: 'ts',
        formats: ['m3u8', 'ts'],
        epgId: 'codec08.mock',
        archive: 0,
        video: 'libx264',
        audio: 'libmp3lame',
    },
];

/** Grouped by container rather than genre, so the category strip separates the cases that break differently. */
export const LIVE_CATEGORIES = [
    { id: 101, name: 'HLS, MPEG-TS segments' },
    { id: 102, name: 'HLS, fMP4 segments' },
    { id: 103, name: 'Progressive MPEG-TS' },
];

/**
 * VOD is a stub: three titles differing only in `container_extension`, which is
 * the field that decides the movie URL. `get_vod_info` is where codec metadata
 * genuinely lives in this protocol, unlike live, so the three carry it.
 */
export const VOD_CATEGORIES = [{ id: 201, name: 'Container samples' }];

/** @type {{id: number, name: string, ext: string, video: string, audio: string}[]} */
export const VOD_ITEMS = [
    { id: 20001, name: 'Container Sample (MP4, H.264 + AAC)', ext: 'mp4', video: 'h264', audio: 'aac' },
    { id: 20002, name: 'Container Sample (MKV, H.265 + AC-3)', ext: 'mkv', video: 'hevc', audio: 'ac3' },
    { id: 20003, name: 'Container Sample (AVI, MPEG-2 + MP2)', ext: 'avi', video: 'mpeg2video', audio: 'mp2' },
];

/**
 * Formats an epoch as a panel does: local wall clock, space separated, no zone
 * suffix. `time_now` and every EPG `start` / `end` use this shape.
 *
 * @param {number} epochSeconds
 * @param {number} offsetMinutes Panel timezone offset from UTC.
 * @returns {string} `YYYY-MM-DD HH:MM:SS`
 */
export function panelTime(epochSeconds, offsetMinutes) {
    return new Date((epochSeconds + offsetMinutes * 60) * 1000)
        .toISOString()
        .replace('T', ' ')
        .replace('.000Z', '');
}

/**
 * Builds a deterministic EPG window for one channel, anchored to the real half
 * hour so the guide has something live in it whenever the mock is started.
 *
 * Titles and descriptions are base64 in the JSON actions and plain text in
 * `xmltv.php`. That asymmetry is real and it is the reason this returns the raw
 * strings and leaves the encoding to the caller.
 *
 * @param {Channel} channel
 * @param {number} nowSeconds
 * @param {number} count Programmes to emit, starting one slot before now.
 * @returns {{title: string, description: string, start: number, stop: number}[]}
 */
export function epgWindow(channel, nowSeconds, count) {
    const slot = 30 * 60;
    const anchor = Math.floor(nowSeconds / slot) * slot - slot;

    return Array.from({ length: count }, (_unused, index) => {
        const start = anchor + index * slot;

        return {
            title: `${channel.name} block ${index + 1}`,
            description:
                `Synthetic programme ${index + 1} on ${channel.name}. Generated by the watchools mock panel, ` +
                'no real schedule data.',
            start,
            stop: start + slot,
        };
    });
}
