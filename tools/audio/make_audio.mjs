// Generates the game's music and sound effects as OGG files (GAME-DESIGN.md "Art, audio and UI":
// Volksmusik-Techno with accordion, tuba and zither over a kick, a slowed Schunkel waltz for
// Sperrstund', a jodel sting on level-up, a cash-register ka-ching on Einkehren ...). Everything is
// synthesised here, deterministic, no samples, so the files can be rebuilt and tuned any time:
//   cd tools/audio && npm install && node make_audio.mjs [--only=kirtag,coin]
// Writes ../../assets/audio/music/<id>.ogg (stereo) and ../../assets/audio/sfx/<id>.ogg (mono).
// Voice barks are separate (tools/audio/make_barks.ps1, Windows text-to-speech).
import { createOggEncoder } from 'wasm-media-encoders';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const SR = 44100;
const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const MUSIC_DIR = join(ROOT, 'assets', 'audio', 'music');
const SFX_DIR = join(ROOT, 'assets', 'audio', 'sfx');
const only = (process.argv.find((a) => a.startsWith('--only=')) || '').slice(7).split(',').filter(Boolean);

// ---------------------------------------------------------------------------------------------
// Basics

let seed = 1848;
function rand() {
	// mulberry32: the same noise every build.
	seed |= 0;
	seed = (seed + 0x6d2b79f5) | 0;
	let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
	t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
	return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const noise = () => rand() * 2 - 1;

const NOTES = { C: 0, 'C#': 1, Db: 1, D: 2, 'D#': 3, Eb: 3, E: 4, F: 5, 'F#': 6, Gb: 6, G: 7, 'G#': 8, Ab: 8, A: 9, 'A#': 10, Bb: 10, B: 11 };
function freq(name) {
	const m = /^([A-G][#b]?)(-?\d)$/.exec(name);
	const midi = 12 * (Number(m[2]) + 1) + NOTES[m[1]];
	return 440 * Math.pow(2, (midi - 69) / 12);
}

// A track: two channels that wrap around, so note tails fall into the start and the loop is seamless.
class Track {
	constructor(seconds) {
		this.n = Math.round(seconds * SR);
		this.l = new Float32Array(this.n);
		this.r = new Float32Array(this.n);
	}
	add(i, v, pan = 0) {
		const k = ((i % this.n) + this.n) % this.n;
		this.l[k] += v * Math.min(1, 1 - pan);
		this.r[k] += v * Math.min(1, 1 + pan);
	}
}

// One-pole low-pass state helper.
function lowpass(cutoff) {
	const a = Math.exp((-2 * Math.PI * cutoff) / SR);
	let y = 0;
	return (x) => (y = (1 - a) * x + a * y);
}

// RBJ band-pass biquad (constant peak gain), for the yodel's vowel formants and filtered noise.
function bandpass(f0, q) {
	const w = (2 * Math.PI * f0) / SR;
	const alpha = Math.sin(w) / (2 * q);
	const a0 = 1 + alpha;
	const b0 = alpha / a0, b2 = -alpha / a0, a1 = (-2 * Math.cos(w)) / a0, a2 = (1 - alpha) / a0;
	let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
	return (x) => {
		const y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2;
		x2 = x1; x1 = x; y2 = y1; y1 = y;
		return y;
	};
}

function env(t, attack, dur, release) {
	if (t < 0) return 0;
	if (t < attack) return t / attack;
	if (t < dur) return 1;
	return Math.max(0, 1 - (t - dur) / release);
}

// ---------------------------------------------------------------------------------------------
// Instruments (write into a Track at a time in seconds)

function kick(tr, t, amp = 0.9) {
	const start = Math.round(t * SR);
	let phase = 0;
	for (let i = 0; i < SR * 0.35; i++) {
		const s = i / SR;
		const f = 45 + 110 * Math.exp(-s * 28);
		phase += (2 * Math.PI * f) / SR;
		const v = Math.sin(phase) * Math.exp(-s * 9) + (i < 90 ? noise() * 0.3 * (1 - i / 90) : 0);
		tr.add(start + i, v * amp);
	}
}

function snare(tr, t, amp = 0.35) {
	const start = Math.round(t * SR);
	const lp = lowpass(5000);
	for (let i = 0; i < SR * 0.2; i++) {
		const s = i / SR;
		const v = lp(noise()) * Math.exp(-s * 18) + Math.sin(2 * Math.PI * 190 * s) * Math.exp(-s * 30) * 0.5;
		tr.add(start + i, v * amp, 0.1);
	}
}

function hat(tr, t, amp = 0.12, open = false) {
	const start = Math.round(t * SR);
	const bp = bandpass(8000, 0.8);
	const decay = open ? 12 : 45;
	for (let i = 0; i < SR * (open ? 0.25 : 0.06); i++) {
		tr.add(start + i, bp(noise()) * Math.exp(-(i / SR) * decay) * amp * 2.2, 0.25);
	}
}

function tuba(tr, t, f, dur, amp = 0.32) {
	const start = Math.round(t * SR);
	const lp = lowpass(Math.min(700, f * 5));
	let phase = 0;
	const len = (dur + 0.08) * SR;
	for (let i = 0; i < len; i++) {
		const s = i / SR;
		phase += (2 * Math.PI * f) / SR;
		// Brassy: a soft saw-ish blend, a little brighter at the attack.
		const bright = 0.35 + 0.4 * Math.exp(-s * 12);
		const raw = Math.sin(phase) + bright * Math.sin(2 * phase) + bright * 0.5 * Math.sin(3 * phase);
		tr.add(start + i, lp(raw) * env(s, 0.02, dur, 0.07) * amp, -0.05);
	}
}

// The accordion: two reeds a few cents apart (the musette beat), a pulse wave each, gently filtered.
function accordion(tr, t, f, dur, amp = 0.16, pan = -0.25) {
	const start = Math.round(t * SR);
	const lp = lowpass(2600);
	let p1 = 0, p2 = 0, p3 = 0;
	const f2 = f * Math.pow(2, 6 / 1200);
	const len = (dur + 0.1) * SR;
	for (let i = 0; i < len; i++) {
		const s = i / SR;
		p1 = (p1 + f / SR) % 1;
		p2 = (p2 + f2 / SR) % 1;
		p3 = (p3 + (f * 0.5) / SR) % 1;
		const reed = (p1 < 0.38 ? 1 : -1) + (p2 < 0.38 ? 1 : -1) + 0.4 * (p3 < 0.5 ? 1 : -1);
		const tremolo = 1 + 0.06 * Math.sin(2 * Math.PI * 5.5 * s);
		tr.add(start + i, lp(reed) * 0.33 * env(s, 0.015, dur, 0.06) * tremolo * amp, pan);
	}
}

// The zither: Karplus-Strong plucked string.
function zither(tr, t, f, amp = 0.22, pan = 0.35, seconds = 1.2) {
	const start = Math.round(t * SR);
	const period = Math.max(2, Math.round(SR / f));
	const line = new Float32Array(period);
	for (let i = 0; i < period; i++) line[i] = noise();
	let k = 0;
	for (let i = 0; i < seconds * SR; i++) {
		const next = (k + 1) % period;
		const v = line[k];
		line[k] = 0.4985 * (line[k] + line[next]);
		k = next;
		tr.add(start + i, v * amp * (i < 40 ? i / 40 : 1), pan);
	}
}

// A bell: inharmonic partials with long decays (church bell, Krampus bells, ka-ching).
function bell(tr, t, f, amp = 0.2, decay = 2.5, pan = 0) {
	const start = Math.round(t * SR);
	const partials = [[1, 1], [2.0, 0.6], [2.76, 0.45], [5.4, 0.25], [8.93, 0.12]];
	for (let i = 0; i < SR * decay * 1.5; i++) {
		const s = i / SR;
		let v = 0;
		for (const [ratio, gain] of partials) {
			v += Math.sin(2 * Math.PI * f * ratio * s) * gain * Math.exp((-s * ratio) / decay);
		}
		tr.add(start + i, v * amp * Math.min(1, i / 30), pan);
	}
}

// ---------------------------------------------------------------------------------------------
// Music

const CHORDS = {
	G: ['G', 'B', 'D'], C: ['C', 'E', 'G'], D: ['D', 'F#', 'A'], D7: ['D', 'F#', 'C'], Em: ['E', 'G', 'B'],
	Am: ['A', 'C', 'E'], B7: ['B', 'D#', 'A'], A: ['A', 'C#', 'E'], A7: ['A', 'C#', 'G'],
};

// Melody bars as eighth notes (polka) or quarter notes (waltz); '_' holds, '.' rests.
function playLine(tr, bars, t0, barLen, steps, play) {
	bars.forEach((bar, b) => {
		const notes = bar.split(' ');
		for (let k = 0; k < notes.length; k++) {
			const name = notes[k];
			if (name === '_' || name === '.') continue;
			let len = 1;
			while (k + len < notes.length && notes[k + len] === '_') len++;
			play(t0 + b * barLen + (k * barLen) / steps, freq(name), (len * barLen) / steps);
		}
	});
}

function kirtag() {
	// G major Volksmusik-Techno, 128 BPM, 32 bars: verse with the accordion tune, a zither break,
	// then both together.
	const bpm = 128;
	const beat = 60 / bpm;
	const bar = beat * 4;
	const chords = ['G', 'G', 'D', 'D', 'D', 'D', 'G', 'G', 'G', 'G', 'C', 'C', 'D', 'D', 'G', 'G'];
	const tune = [
		'D5 _ B4 D5 G5 _ D5 B4', 'C5 B4 A4 B4 G4 _ _ .', 'A4 _ F#4 A4 D5 _ C5 A4', 'B4 A4 G4 A4 F#4 _ _ .',
		'A4 B4 C5 A4 F#4 G4 A4 F#4', 'D5 C5 B4 A4 C5 _ A4 .', 'B4 D5 G5 D5 B4 G4 A4 B4', 'G4 _ D4 _ G4 _ _ .',
		'G5 _ F#5 G5 E5 _ D5 B4', 'D5 _ B4 G4 B4 _ D5 .', 'E5 _ C5 E5 G5 _ E5 C5', 'D5 C5 B4 A4 G4 _ E4 .',
		'F#4 A4 D5 F#5 E5 D5 C5 A4', 'B4 C5 D5 _ A4 _ F#4 .', 'G4 B4 D5 G5 F#5 D5 E5 F#5', 'G5 _ _ _ G4 _ _ .',
	];
	const bars = 32;
	const tr = new Track(bars * bar);
	for (let b = 0; b < bars; b++) {
		const t = b * bar;
		const chord = CHORDS[chords[b % 16]];
		const breakdown = b >= 16 && b < 24;
		for (let q = 0; q < 4; q++) {
			if (!(breakdown && b % 4 === 0 && q === 0 && b === 16)) kick(tr, t + q * beat, breakdown ? 0.6 : 0.9);
			hat(tr, t + q * beat + beat / 2, 0.1, q === 3 && b % 4 === 3);
			if (q % 2 === 1) snare(tr, t + q * beat, breakdown ? 0.18 : 0.3);
		}
		// Oom-pah: tuba on 1 and 3 (root, fifth), accordion chord on the offbeats.
		tuba(tr, t, freq(chord[0] + '2'), beat * 0.8);
		tuba(tr, t + 2 * beat, freq(chord[0] + '2') * 1.5, beat * 0.8);
		for (let q = 0; q < 4; q++) {
			for (const n of chord) accordion(tr, t + q * beat + beat / 2, freq(n + '4'), beat * 0.32, 0.07, -0.35);
		}
		if (b >= 16) {
			// Zither arpeggios in sixteenths.
			const pattern = [0, 1, 2, 1];
			for (let s = 0; s < 16; s++) {
				const n = chord[pattern[s % 4]] + (s % 8 < 4 ? '5' : '4');
				zither(tr, t + (s * beat) / 4, freq(n), breakdown ? 0.16 : 0.1, 0.4, 0.8);
			}
		}
	}
	const lead = (t, f, d) => accordion(tr, t, f, d * 0.92, 0.19, -0.15);
	playLine(tr, tune, 0, bar, 8, lead);
	playLine(tr, tune, 24 * bar, bar, 8, lead);
	// The break: the tune an octave down on the zither, half the bars.
	playLine(tr, tune.slice(0, 8), 16 * bar, bar, 8, (t, f) => zither(tr, t, f, 0.3, -0.1, 1.4));
	return tr;
}

function boss() {
	// E minor, 140 BPM, 16 bars: driving tuba eighths, staccato accordion, Krampus bells.
	const bpm = 140;
	const beat = 60 / bpm;
	const bar = beat * 4;
	const chords = ['Em', 'Em', 'C', 'D', 'Em', 'Em', 'B7', 'B7', 'Am', 'Am', 'Em', 'Em', 'C', 'D', 'B7', 'B7'];
	const riff = [
		'E5 . G5 E5 B4 . E5 .', 'D5 E5 G5 . F#5 E5 D5 B4', 'C5 . E5 C5 G4 . C5 .', 'D5 . F#5 D5 A4 . D5 .',
		'E5 . G5 E5 B5 . G5 .', 'F#5 G5 A5 G5 F#5 E5 D5 B4', 'B4 . D#5 B4 F#5 . D#5 .', 'A5 G5 F#5 E5 D#5 . B4 .',
		'A4 . C5 A4 E5 . C5 .', 'A4 B4 C5 E5 D5 C5 B4 A4', 'G4 . B4 G4 E5 . B4 .', 'E5 F#5 G5 A5 B5 . E5 .',
		'C5 . E5 G5 E5 . C5 .', 'D5 . F#5 A5 F#5 . D5 .', 'B4 D#5 F#5 A5 F#5 D#5 B4 .', 'B4 _ _ . E5 . . .',
	];
	const bars = 16;
	const tr = new Track(bars * bar);
	for (let b = 0; b < bars; b++) {
		const t = b * bar;
		const chord = CHORDS[chords[b]];
		for (let q = 0; q < 4; q++) {
			kick(tr, t + q * beat, 1.0);
			if (q % 2 === 1) snare(tr, t + q * beat, 0.36);
			for (let s = 0; s < 4; s++) hat(tr, t + q * beat + (s * beat) / 4, s % 2 ? 0.06 : 0.1);
		}
		for (let e = 0; e < 8; e++) {
			const root = freq(chord[0] + '2') * (e % 2 ? 2 : 1);
			tuba(tr, t + (e * beat) / 2, root, beat * 0.35, 0.28);
		}
		for (let q = 0; q < 4; q++) {
			for (const n of chord) accordion(tr, t + q * beat + beat / 2, freq(n + '4'), beat * 0.2, 0.07, 0.3);
		}
		if (b % 2 === 0) {
			bell(tr, t, freq('B5'), 0.07, 0.6, -0.5);
			bell(tr, t + beat * 0.5, freq('E6'), 0.05, 0.5, 0.5);
		}
	}
	playLine(tr, riff, 0, bar, 8, (t, f, d) => accordion(tr, t, f, d * 0.75, 0.2, -0.1));
	return tr;
}

function sperrstund() {
	// A slowed Schunkel waltz in D, 3/4 at 80 BPM: tuba on one, accordion on two and three.
	const bpm = 80;
	const beat = 60 / bpm;
	const bar = beat * 3;
	const chords = ['D', 'D', 'A7', 'A7', 'A7', 'A7', 'D', 'D', 'G', 'G', 'D', 'D', 'A7', 'A7', 'D', 'D'];
	const tune = [
		'F#5 _ E5', 'D5 F#5 A5', 'G5 _ E5', 'C#5 _ _', 'E5 _ D5', 'C#5 E5 G5', 'F#5 _ E5', 'D5 _ _',
		'B5 _ A5', 'G5 _ B4', 'A5 _ F#5', 'D5 _ _', 'E5 F#5 G5', 'E5 _ C#5', 'D5 _ _', 'D5 _ .',
	];
	const bars = 32;
	const tr = new Track(bars * bar);
	for (let b = 0; b < bars; b++) {
		const t = b * bar;
		const chord = CHORDS[chords[b % 16]];
		tuba(tr, t, freq(chord[0] + '2'), beat * 0.9, 0.3);
		for (const q of [1, 2]) {
			for (const n of chord) accordion(tr, t + q * beat, freq(n + '4'), beat * 0.5, 0.06, -0.3);
		}
		if (b >= 16) zither(tr, t + beat * 2.5, freq(chord[1] + '5'), 0.12, 0.45, 1.2);
	}
	playLine(tr, tune, 0, bar, 3, (t, f, d) => accordion(tr, t, f, d * 0.95, 0.2, -0.1));
	playLine(tr, tune, 16 * bar, bar, 3, (t, f, d) => {
		accordion(tr, t, f, d * 0.95, 0.15, -0.1);
		zither(tr, t, f / 2, 0.16, 0.3, 1.6);
	});
	// The closing bell every eight bars.
	for (let b = 0; b < bars; b += 8) bell(tr, b * bar, freq('D4'), 0.12, 3.0, 0.2);
	return tr;
}

// ---------------------------------------------------------------------------------------------
// Sound effects (mono)

class Sfx {
	constructor(seconds) {
		this.data = new Float32Array(Math.round(seconds * SR));
	}
	add(i, v) {
		if (i >= 0 && i < this.data.length) this.data[i] += v;
	}
	// The Track interface, so the instruments work here too (pan ignored).
	get l() { return this.data; }
}
// Instruments call tr.add(i, v, pan); a Sfx ignores the pan.

function sweep(out, t, f0, f1, dur, amp, shape = 'sine') {
	const start = Math.round(t * SR);
	let phase = 0;
	for (let i = 0; i < dur * SR; i++) {
		const s = i / SR;
		const f = f0 * Math.pow(f1 / f0, s / dur);
		phase += f / SR;
		const p = phase % 1;
		let v = Math.sin(2 * Math.PI * p);
		if (shape === 'square') v = p < 0.5 ? 1 : -1;
		if (shape === 'saw') v = 2 * p - 1;
		out.add(start + i, v * amp * env(s, 0.005, dur * 0.6, dur * 0.4));
	}
}

function noiseBurst(out, t, dur, amp, center, q = 1, decay = 20) {
	const start = Math.round(t * SR);
	const bp = bandpass(center, q);
	for (let i = 0; i < dur * SR; i++) {
		out.add(start + i, bp(noise()) * amp * Math.exp(-(i / SR) * decay) * 2);
	}
}

function whoosh(out, t, dur, amp, f0, f1) {
	const start = Math.round(t * SR);
	for (let i = 0; i < dur * SR; i++) {
		const s = i / SR;
		const f = f0 * Math.pow(f1 / f0, s / dur);
		// A fresh filter per block is enough for a sweep this slow.
		if (i % 256 === 0) out._bp = bandpass(f, 1.2);
		out.add(start + i, out._bp(noise()) * amp * Math.sin((Math.PI * s) / dur) * 2.5);
	}
}

// A sung syllable: a glottal pulse train through two vowel formants (for the jodel).
const VOWELS = { o: [480, 840], u: [350, 700], i: [300, 2300], e: [420, 2000], a: [750, 1200] };
function sing(out, t, f, dur, vowel, amp, vibrato = 0) {
	const [f1, f2] = VOWELS[vowel];
	const b1 = bandpass(f1, 6), b2 = bandpass(f2, 8);
	const start = Math.round(t * SR);
	let phase = 0;
	for (let i = 0; i < (dur + 0.05) * SR; i++) {
		const s = i / SR;
		phase += (f * (1 + vibrato * Math.sin(2 * Math.PI * 5.5 * s))) / SR;
		const p = phase % 1;
		const pulse = p < 0.12 ? Math.sin((Math.PI * p) / 0.12) : 0;
		const v = b1(pulse) * 1.4 + b2(pulse) * 0.7;
		out.add(start + i, v * amp * env(s, 0.012, dur, 0.04));
	}
}

const SFX = {
	hit: () => { const o = new Sfx(0.08); noiseBurst(o, 0, 0.08, 0.5, 1800, 1.5, 45); sweep(o, 0, 220, 120, 0.05, 0.3); return o; },
	kill: () => { const o = new Sfx(0.14); sweep(o, 0, 600, 140, 0.12, 0.45); noiseBurst(o, 0, 0.06, 0.3, 3000, 1, 50); return o; },
	brosel: () => { const o = new Sfx(0.06); sweep(o, 0, 1800, 2600, 0.04, 0.25); return o; },
	knodl_hit: () => { const o = new Sfx(0.2); sweep(o, 0, 110, 55, 0.18, 0.6); noiseBurst(o, 0, 0.12, 0.35, 400, 0.8, 25); return o; },
	schupfn: () => { const o = new Sfx(0.4); whoosh(o, 0, 0.38, 0.6, 300, 1600); sweep(o, 0, 200, 90, 0.15, 0.3); return o; },
	reel: () => { const o = new Sfx(0.5); for (let k = 0; k < 10; k++) noiseBurst(o, k * 0.045, 0.03, 0.25, 2500 + k * 120, 4, 80); sweep(o, 0, 300, 700, 0.45, 0.12, 'square'); return o; },
	jump: () => { const o = new Sfx(0.15); sweep(o, 0, 260, 520, 0.12, 0.3, 'square'); return o; },
	swing: () => { const o = new Sfx(0.16); whoosh(o, 0, 0.15, 0.4, 600, 2400); return o; },
	hurt: () => { const o = new Sfx(0.22); sweep(o, 0, 330, 140, 0.2, 0.45, 'square'); noiseBurst(o, 0, 0.1, 0.3, 900, 1, 30); return o; },
	downed: () => {
		const o = new Sfx(1.0);
		['G4', 'E4', 'C4', 'G3'].forEach((n, k) => sweep(o, k * 0.18, freq(n), freq(n) * 0.97, 0.22, 0.4, 'square'));
		return o;
	},
	level_up: () => {
		// The jodel sting: chest and head voice flipping, "Jo-di-o-di-ri!"
		const o = new Sfx(1.2);
		const line = [['G4', 'o', 0.12], ['D5', 'i', 0.12], ['B4', 'o', 0.11], ['G5', 'i', 0.13], ['D5', 'u', 0.11], ['B5', 'i', 0.42]];
		let t = 0;
		for (const [n, v, d] of line) { sing(o, t, freq(n), d, v, 0.55, d > 0.3 ? 0.02 : 0); t += d; }
		bell(o, 0, freq('G6'), 0.05, 0.6);
		return o;
	},
	card: () => { const o = new Sfx(0.08); noiseBurst(o, 0, 0.05, 0.4, 2500, 2, 70); sweep(o, 0, 900, 1200, 0.04, 0.15); return o; },
	menu_open: () => { const o = new Sfx(0.6); whoosh(o, 0, 0.2, 0.25, 800, 3000); bell(o, 0.12, freq('E6'), 0.12, 0.4); bell(o, 0.2, freq('B6'), 0.08, 0.4); return o; },
	cash_in: () => {
		// Ka-ching: the drawer, the bell, the coins.
		const o = new Sfx(1.2);
		noiseBurst(o, 0, 0.12, 0.6, 300, 0.7, 25);
		sweep(o, 0, 90, 50, 0.1, 0.4);
		bell(o, 0.1, 2400, 0.25, 0.9);
		bell(o, 0.1, 3150, 0.16, 0.9);
		for (let k = 0; k < 7; k++) bell(o, 0.18 + k * 0.05 + rand() * 0.03, 4000 + rand() * 2500, 0.05, 0.2);
		return o;
	},
	coin: () => { const o = new Sfx(0.35); bell(o, 0, 2600, 0.15, 0.25); bell(o, 0.06, 3900, 0.12, 0.3); return o; },
	chest: () => {
		const o = new Sfx(1.1);
		sweep(o, 0, 180, 140, 0.25, 0.2, 'saw');
		noiseBurst(o, 0.2, 0.08, 0.5, 500, 0.8, 30);
		['C6', 'E6', 'G6', 'C7'].forEach((n, k) => bell(o, 0.3 + k * 0.07, freq(n), 0.09, 0.5));
		return o;
	},
	no_gold: () => { const o = new Sfx(0.35); sweep(o, 0, 160, 150, 0.12, 0.35, 'square'); sweep(o, 0.16, 120, 110, 0.15, 0.35, 'square'); return o; },
	heal: () => { const o = new Sfx(0.6); ['C5', 'E5', 'G5'].forEach((n, k) => sweep(o, k * 0.09, freq(n), freq(n), 0.25, 0.22)); return o; },
	stempel: () => {
		// The rubber stamp: a heavy thud and the paper slap.
		const o = new Sfx(0.6);
		sweep(o, 0, 120, 45, 0.3, 0.8);
		noiseBurst(o, 0, 0.12, 0.6, 1200, 0.7, 35);
		bell(o, 0.05, freq('G5'), 0.06, 0.4);
		return o;
	},
	gate_open: () => {
		const o = new Sfx(2.0);
		['G3', 'D4', 'G4', 'B4', 'D5', 'G5'].forEach((n, k) => sweep(o, k * 0.1, freq(n), freq(n) * 1.01, 1.4 - k * 0.1, 0.12));
		whoosh(o, 0, 1.5, 0.15, 200, 4000);
		return o;
	},
	warn: () => { const o = new Sfx(0.12); sweep(o, 0, 1400, 1300, 0.09, 0.25, 'square'); return o; },
	slam: () => { const o = new Sfx(0.6); sweep(o, 0, 90, 35, 0.5, 0.9); noiseBurst(o, 0, 0.25, 0.5, 250, 0.6, 12); return o; },
	boss_arrive: () => {
		const o = new Sfx(2.5);
		tuba(o, 0, freq('E1'), 1.2, 0.6);
		tuba(o, 0, freq('B1'), 1.2, 0.4);
		for (let k = 0; k < 6; k++) bell(o, 0.1 + k * 0.18, k % 2 ? freq('B5') : freq('E6'), 0.12, 0.6);
		whoosh(o, 0, 1.5, 0.3, 120, 600);
		return o;
	},
	boss_beaten: () => {
		const o = new Sfx(2.2);
		['G4', 'B4', 'D5', 'G5'].forEach((n, k) => accordion(o, k * 0.12, freq(n), k === 3 ? 0.8 : 0.1, 0.5, 0));
		['G4', 'B4', 'D5'].forEach((n) => accordion(o, 0.48, freq(n), 0.8, 0.25, 0));
		bell(o, 0.48, freq('G6'), 0.08, 1.2);
		return o;
	},
	bus_horn: () => {
		const o = new Sfx(1.1);
		for (const [t, a, b] of [[0, 'C4', 'G4'], [0.4, 'D4', 'A4']]) {
			sweep(o, t, freq(a), freq(a), 0.32, 0.22, 'square');
			sweep(o, t, freq(b), freq(b), 0.32, 0.18, 'square');
		}
		return o;
	},
	sperrstund: () => { const o = new Sfx(4.0); bell(o, 0, freq('D3'), 0.35, 3.0); bell(o, 1.2, freq('A2'), 0.3, 3.0); return o; },
	victory: () => {
		const o = new Sfx(3.0);
		const line = [['D5', 0.15], ['F#5', 0.15], ['A5', 0.15], ['D6', 0.6], ['A5', 0.2], ['D6', 1.0]];
		let t = 0;
		for (const [n, d] of line) { accordion(o, t, freq(n), d * 0.95, 0.5, 0); t += d; }
		tuba(o, 0, freq('D2'), 0.5, 0.4);
		tuba(o, 1.05, freq('D2'), 1.0, 0.4);
		bell(o, 1.05, freq('D6'), 0.1, 1.5);
		return o;
	},
	defeat: () => {
		const o = new Sfx(2.6);
		['G3', 'F#3', 'F3', 'E3'].forEach((n, k) => tuba(o, k * 0.45, freq(n), k === 3 ? 1.2 : 0.38, 0.55));
		return o;
	},
};

// ---------------------------------------------------------------------------------------------
// Output

function normalise(channels, peak) {
	let max = 0;
	for (const ch of channels) for (const v of ch) max = Math.max(max, Math.abs(v));
	// A gentle soft clip, then scale to the peak.
	const drive = max > 0 ? 1.4 / max : 1;
	for (const ch of channels) {
		for (let i = 0; i < ch.length; i++) ch[i] = Math.tanh(ch[i] * drive);
	}
	let after = 0;
	for (const ch of channels) for (const v of ch) after = Math.max(after, Math.abs(v));
	for (const ch of channels) for (let i = 0; i < ch.length; i++) ch[i] *= after > 0 ? peak / after : 1;
}

async function writeOgg(path, channels, quality) {
	const encoder = await createOggEncoder();
	encoder.configure({ channels: channels.length, sampleRate: SR, vbrQuality: quality });
	const parts = [];
	const block = 4096;
	for (let i = 0; i < channels[0].length; i += block) {
		parts.push(encoder.encode(channels.map((ch) => ch.subarray(i, Math.min(i + block, ch.length)))).slice());
	}
	parts.push(encoder.finalize().slice());
	const total = parts.reduce((n, p) => n + p.length, 0);
	const out = new Uint8Array(total);
	let o = 0;
	for (const p of parts) { out.set(p, o); o += p.length; }
	mkdirSync(dirname(path), { recursive: true });
	writeFileSync(path, out);
	return total;
}

const music = { kirtag, boss, sperrstund };
for (const [id, make] of Object.entries(music)) {
	if (only.length && !only.includes(id)) continue;
	const tr = make();
	normalise([tr.l, tr.r], 0.8);
	const bytes = await writeOgg(join(MUSIC_DIR, `${id}.ogg`), [tr.l, tr.r], 2);
	console.log(`music/${id}.ogg  ${(tr.n / SR).toFixed(1)} s  ${(bytes / 1024).toFixed(0)} KiB`);
}
for (const [id, make] of Object.entries(SFX)) {
	if (only.length && !only.includes(id)) continue;
	const o = make();
	normalise([o.data], 0.85);
	const bytes = await writeOgg(join(SFX_DIR, `${id}.ogg`), [o.data], 3);
	console.log(`sfx/${id}.ogg  ${(o.data.length / SR).toFixed(2)} s  ${(bytes / 1024).toFixed(0)} KiB`);
}
