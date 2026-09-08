#!/usr/bin/env node
/**
 * Generates the mock panel's media with FFmpeg. Run once before the first
 * `server.mjs` start, and again after changing the codec matrix.
 *
 *   node tool/xtream-mock/encode.mjs [--force]
 *
 * Everything is synthetic: a `testsrc2` colour pattern with a frame counter and
 * a sine tone. No provider media, no network fetch, nothing licensed. The
 * generated tree is gitignored, because committing a codec matrix would put
 * tens of megabytes of binary into a Flutter repository for no gain when a
 * regeneration is one command.
 *
 * Each channel is encoded once into a master file and then remuxed with
 * `-c copy` into HLS segments, so the progressive and segmented forms of a
 * channel are the same bytes rather than two encodes that could differ.
 */

import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { CHANNELS, SEGMENT_COUNT, SEGMENT_SECONDS, VOD_ITEMS } from './catalogue.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const MEDIA = join(HERE, 'media');
const FORCE = process.argv.includes('--force');

/** Frames per second of the generated pattern. Segment keyframes are forced, so this only sets smoothness. */
const FPS = 25;

/** Generated frame size. Small enough to encode a nine-item matrix in under a minute, large enough to look real. */
const SIZE = '640x360';

/** Seconds of media per channel. One full loop of the HLS window. */
const DURATION = SEGMENT_COUNT * SEGMENT_SECONDS;

/**
 * Per-encoder quality flags. Every encoder needs its own, and the defaults are
 * either far too slow (libsvtav1, libx265) or not rate controlled at all
 * (mpeg2video, which ignores CRF).
 *
 * @type {Record<string, string[]>}
 */
const VIDEO_FLAGS = {
    libx264: ['-preset', 'ultrafast', '-crf', '28', '-pix_fmt', 'yuv420p'],
    libx265: ['-preset', 'ultrafast', '-crf', '30', '-pix_fmt', 'yuv420p'],
    libsvtav1: ['-preset', '12', '-crf', '40', '-pix_fmt', 'yuv420p'],
    mpeg2video: ['-q:v', '5', '-pix_fmt', 'yuv420p'],
};

/** @type {Record<string, string[]>} */
const AUDIO_FLAGS = {
    aac: ['-b:a', '128k'],
    ac3: ['-b:a', '192k'],
    eac3: ['-b:a', '192k'],
    libmp3lame: ['-b:a', '128k'],
    mp2: ['-b:a', '192k'],
    libopus: ['-b:a', '96k'],
};

/**
 * Runs FFmpeg and rejects on a non-zero exit, carrying its stderr. FFmpeg
 * reports every real problem there and says nothing on stdout, so swallowing it
 * would turn a codec that is not built into this binary into an empty file.
 *
 * @param {string[]} args
 * @param {string} label What is being produced, for the failure message.
 * @returns {Promise<void>}
 */
function ffmpeg(args, label) {
    return new Promise((resolve, reject) => {
        const child = spawn('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', ...args], {
            stdio: ['ignore', 'ignore', 'pipe'],
        });

        let stderr = '';
        child.stderr.on('data', (chunk) => {
            stderr += chunk.toString();
        });

        child.on('error', (error) => reject(new Error(`ffmpeg could not start: ${error.message}`)));
        child.on('close', (code) => {
            if (code === 0) {
                resolve();
                return;
            }
            reject(new Error(`ffmpeg failed on ${label} (exit ${code}):\n${stderr.trim()}`));
        });
    });
}

/** Source arguments shared by every encode: a counting colour pattern and a tone. */
function sourceArgs() {
    return [
        '-f', 'lavfi', '-i', `testsrc2=size=${SIZE}:rate=${FPS}`,
        '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000',
        '-t', String(DURATION),
        // Forced keyframes rather than -g, because the interval has to be exact
        // for `-c copy` segmentation and every encoder spells -g differently.
        '-force_key_frames', `expr:gte(t,n_forced*${SEGMENT_SECONDS})`,
    ];
}

/**
 * Encodes one channel's master file and both of its playable forms.
 *
 * @param {import('./catalogue.mjs').Channel} channel
 * @returns {Promise<void>}
 */
async function encodeChannel(channel) {
    const dir = join(MEDIA, String(channel.id));
    const servesTs = channel.formats.includes('ts');

    // 1. The master carries the only encode. MPEG-TS when the channel serves a
    //    progressive form, MP4 otherwise: AV1 has no MPEG-TS mapping at all,
    //    which is why channel 07 is HLS only rather than an oversight.
    const master = join(dir, servesTs ? 'raw.ts' : 'master.mp4');
    mkdirSync(dir, { recursive: true });

    await ffmpeg(
        [
            ...sourceArgs(),
            '-c:v', channel.video,
            ...(VIDEO_FLAGS[channel.video] ?? []),
            '-c:a', channel.audio,
            ...(AUDIO_FLAGS[channel.audio] ?? []),
            '-f', servesTs ? 'mpegts' : 'mp4',
            master,
        ],
        `${channel.name} master`,
    );

    // 2. Segments are a remux, never a second encode, so the progressive and
    //    segmented forms of a channel cannot drift apart.
    const fmp4 = channel.segment === 'fmp4';
    const segmentArgs = fmp4
        ? ['-hls_segment_type', 'fmp4', '-hls_fmp4_init_filename', 'init.mp4', '-hls_segment_filename', join(dir, 'seg-%03d.m4s')]
        : ['-hls_segment_type', 'mpegts', '-hls_segment_filename', join(dir, 'seg-%03d.ts')];

    await ffmpeg(
        [
            '-i', master,
            '-c', 'copy',
            // HEVC in an fMP4 needs the hvc1 brand or Safari refuses the track.
            ...(fmp4 && channel.video === 'libx265' ? ['-tag:v', 'hvc1'] : []),
            // AAC arrives from the MPEG-TS master in ADTS framing, which MP4
            // cannot carry: the remux fails outright rather than degrading.
            ...(fmp4 && channel.audio === 'aac' ? ['-bsf:a', 'aac_adtstoasc'] : []),
            '-f', 'hls',
            '-hls_time', String(SEGMENT_SECONDS),
            '-hls_list_size', '0',
            ...segmentArgs,
            join(dir, 'source.m3u8'),
        ],
        `${channel.name} segments`,
    );
}

/**
 * Encodes the three VOD container samples. VOD is where this protocol actually
 * carries codec metadata, so these exist to exercise `get_vod_info` and the
 * `container_extension` that decides a movie URL.
 *
 * @param {{id: number, name: string, ext: string, video: string, audio: string}} item
 * @returns {Promise<void>}
 */
async function encodeVod(item) {
    const dir = join(MEDIA, String(item.id));
    mkdirSync(dir, { recursive: true });

    const video = item.video === 'hevc' ? 'libx265' : item.video === 'h264' ? 'libx264' : 'mpeg2video';

    await ffmpeg(
        [
            ...sourceArgs(),
            '-c:v', video,
            ...(VIDEO_FLAGS[video] ?? []),
            '-c:a', item.audio,
            ...(AUDIO_FLAGS[item.audio] ?? []),
            join(dir, `movie.${item.ext}`),
        ],
        `${item.name}`,
    );
}

async function main() {
    if (FORCE && existsSync(MEDIA)) {
        rmSync(MEDIA, { recursive: true });
    }
    if (existsSync(MEDIA) && !FORCE) {
        console.log('media/ exists. Pass --force to regenerate.');
        return;
    }

    mkdirSync(MEDIA, { recursive: true });
    console.log(`Encoding ${CHANNELS.length} channels and ${VOD_ITEMS.length} VOD samples at ${SIZE}...`);

    for (const channel of CHANNELS) {
        const started = Date.now();
        await encodeChannel(channel);
        console.log(`  ${channel.name}  (${Date.now() - started} ms)`);
    }

    for (const item of VOD_ITEMS) {
        await encodeVod(item);
        console.log(`  ${item.name}`);
    }

    console.log('Done. Start the panel with: node tool/xtream-mock/server.mjs');
}

main().catch((error) => {
    console.error(`\n${error.message}`);
    process.exit(1);
});
