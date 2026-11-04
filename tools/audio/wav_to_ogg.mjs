// Converts a 16-bit PCM WAV (mono or stereo) to a mono OGG, trimmed and normalised.
//   node wav_to_ogg.mjs <in.wav> <out.ogg>
import { createOggEncoder } from 'wasm-media-encoders';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';

const [input, output] = process.argv.slice(2);
const wav = readFileSync(input);
let o = 12;
let rate = 0;
let channels = 1;
let bits = 16;
let samples = null;
while (o + 8 <= wav.length) {
	const id = wav.toString('ascii', o, o + 4);
	const size = wav.readUInt32LE(o + 4);
	if (id === 'fmt ') {
		channels = wav.readUInt16LE(o + 10);
		rate = wav.readUInt32LE(o + 12);
		bits = wav.readUInt16LE(o + 22);
	} else if (id === 'data') {
		samples = wav.subarray(o + 8, o + 8 + size);
	}
	o += 8 + size + (size % 2);
}
if (!samples || bits !== 16 || !rate) {
	console.error(`${input}: not a 16-bit PCM WAV`);
	process.exit(1);
}
const frames = samples.length / 2 / channels;
let mono = new Float32Array(frames);
for (let i = 0; i < frames; i++) {
	let v = 0;
	for (let c = 0; c < channels; c++) v += samples.readInt16LE((i * channels + c) * 2) / 32768;
	mono[i] = v / channels;
}
// Trim silence at both ends (keep 20 ms), then normalise to -1 dB.
let first = 0;
let last = frames - 1;
while (first < last && Math.abs(mono[first]) < 0.01) first++;
while (last > first && Math.abs(mono[last]) < 0.01) last--;
mono = mono.slice(Math.max(0, first - rate * 0.02), Math.min(frames, last + rate * 0.02));
let peak = 0;
for (const v of mono) peak = Math.max(peak, Math.abs(v));
for (let i = 0; i < mono.length; i++) mono[i] *= peak > 0 ? 0.89 / peak : 1;
const encoder = await createOggEncoder();
encoder.configure({ channels: 1, sampleRate: rate, vbrQuality: 4 });
const parts = [encoder.encode([mono]).slice(), encoder.finalize().slice()];
mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, Buffer.concat(parts.map((p) => Buffer.from(p))));
console.log(`${output}: ${(mono.length / rate).toFixed(2)} s at ${rate} Hz`);
