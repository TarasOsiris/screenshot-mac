// Synthesizes public/audio/soundtrack.wav: a 120 BPM beat whose cuts land on the
// scene boundaries in src/theme.ts (one beat = 15 frames at 30 fps), plus whooshes
// into every cut and hits on the logo. License-free by construction. To use real
// music instead, drop a file at public/audio/ and point Promo.tsx at it.
import { writeFileSync, mkdirSync, readFileSync } from "node:fs";

const SR = 48000;
const FPS = 30;
const src = readFileSync(new URL("../src/theme.ts", import.meta.url), "utf8");
const TOTAL = Number(src.match(/TOTAL = (\d+)/)[1]);
const cuts = [...src.matchAll(/^\s+\w+: \[(\d+), (\d+)\]/gm)].map((m) => Number(m[1])).filter((c) => c > 0);
const DUR = TOTAL / FPS;
const N = Math.ceil(DUR * SR);
const L = new Float32Array(N);
const R = new Float32Array(N);
const verbL = new Float32Array(N);
const verbR = new Float32Array(N);

let seed = 7;
const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647) * 2 - 1;
const add = (i, l, r, send = 0) => {
  if (i < 0 || i >= N) return;
  L[i] += l;
  R[i] += r;
  verbL[i] += l * send;
  verbR[i] += r * send;
};
const S = (t) => Math.floor(t * SR);
const beat = 0.5;
const f2s = (fr) => fr / FPS;

function kick(t0, amp = 0.9, len = 0.45, decay = 7) {
  let ph = 0;
  for (let i = 0; i < S(len); i++) {
    const t = i / SR;
    ph += (2 * Math.PI * (44 + 120 * Math.exp(-t * 32))) / SR;
    const v = Math.sin(ph) * Math.exp(-t * decay) * amp + (t < 0.004 ? rnd() * 0.3 * amp : 0);
    add(S(t0) + i, v, v);
  }
}
function snare(t0, amp = 0.38) {
  let lp = 0;
  for (let i = 0; i < S(0.25); i++) {
    const t = i / SR;
    const n = rnd();
    lp += 0.25 * (n - lp);
    const v = ((n - lp) * Math.exp(-t * 16) + Math.sin(2 * Math.PI * 190 * t) * Math.exp(-t * 30) * 0.5) * amp;
    add(S(t0) + i, v * 0.9, v, 0.35);
  }
}
function hat(t0, amp = 0.09, pan = 0.2) {
  let lp = 0;
  for (let i = 0; i < S(0.06); i++) {
    const n = rnd();
    lp += 0.5 * (n - lp);
    const v = (n - lp) * Math.exp(-(i / SR) * 70) * amp;
    add(S(t0) + i, v * (1 - pan), v * (1 + pan));
  }
}
function bass(t0, freq, len, amp = 0.28) {
  let lp = 0;
  for (let i = 0; i < S(len); i++) {
    const t = i / SR;
    let saw = 0;
    for (let h = 1; h <= 6; h++) saw += Math.sin(2 * Math.PI * freq * h * t) / h;
    lp += 0.08 * (saw - lp);
    const env = Math.min(1, t / 0.006) * Math.exp(-t * 3.5) * Math.min(1, (len - t) / 0.01);
    const v = lp * env * amp;
    add(S(t0) + i, v, v);
  }
}
function pad(t0, len, freqs, amp = 0.035) {
  for (let i = 0; i < S(len); i++) {
    const t = i / SR;
    const env = Math.min(1, t / 0.35) * Math.min(1, (len - t) / 0.4);
    let l = 0;
    let r = 0;
    for (const fq of freqs) {
      l += Math.sin(2 * Math.PI * fq * 0.997 * t) + 0.3 * Math.sin(2 * Math.PI * fq * 2.004 * t);
      r += Math.sin(2 * Math.PI * fq * 1.003 * t) + 0.3 * Math.sin(2 * Math.PI * fq * 1.996 * t);
    }
    add(S(t0) + i, l * env * amp, r * env * amp, 0.4);
  }
}
// Resonant band-pass noise sweeping up into the cut at tc.
function whoosh(tc, len = 0.45, amp = 0.32) {
  let low = 0;
  let band = 0;
  const tail = 0.18;
  for (let i = 0; i < S(len + tail); i++) {
    const t = i / SR;
    const p = Math.min(1, t / len);
    const fc = 250 + 5000 * p * p;
    const fF = 2 * Math.sin((Math.PI * fc) / SR);
    const n = rnd();
    const high = n - low - 0.5 * band;
    band += fF * high;
    low += fF * band;
    const env = t < len ? p * p : Math.exp(-(t - len) * 25);
    const v = band * env * amp;
    add(S(tc - len) + i, v * (0.8 + 0.2 * p), v * (1 - 0.2 * p), 0.3);
  }
}
function impact(t0, amp = 1) {
  kick(t0, amp, 1.2, 3.2);
  let lp = 0;
  for (let i = 0; i < S(0.6); i++) {
    const t = i / SR;
    lp += 0.05 * (rnd() - lp);
    const v = lp * Math.exp(-t * 6) * amp * 1.4;
    add(S(t0) + i, v, v, 0.5);
  }
}
function chime(t0, amp = 0.16) {
  for (let i = 0; i < S(1.2); i++) {
    const t = i / SR;
    const v = (Math.sin(2 * Math.PI * 1318.5 * t) + 0.6 * Math.sin(2 * Math.PI * 1975.5 * t) + 0.3 * Math.sin(2 * Math.PI * 2637 * t)) * Math.exp(-t * 4) * amp;
    add(S(t0) + i, v, v, 0.6);
  }
}
function riser(t0, len, amp = 0.12) {
  let ph = 0;
  for (let i = 0; i < S(len); i++) {
    const t = i / SR;
    const p = t / len;
    ph += (2 * Math.PI * (200 + 1400 * p * p)) / SR;
    const v = (Math.sin(ph) * 0.4 + rnd() * 0.25) * p * p * amp;
    add(S(t0) + i, v, v, 0.3);
  }
}

// Am – F – C – G, one chord per bar.
const ROOTS = [55, 43.65, 65.41, 49.0];
const CHORDS = [
  [220, 261.63, 329.63],
  [174.61, 220, 261.63],
  [196, 261.63, 329.63],
  [196, 246.94, 293.66],
];

const introEnd = f2s(cuts[0]);
const outroStart = f2s(cuts[cuts.length - 1]);

// Intro: dot pop, letters slam, pad swell.
kick(0.02, 0.5, 0.3, 12);
impact(f2s(22), 0.95);
pad(0, introEnd + 0.3, CHORDS[0], 0.03);
riser(0.9, introEnd - 0.9, 0.14);

// Groove from the first cut to the outro.
for (let t = introEnd; t < outroStart - 1e-6; t += beat) {
  const b = Math.round((t - introEnd) / beat);
  const bar = Math.floor(b / 4);
  kick(t);
  if (b % 2 === 1) snare(t);
  hat(t + beat / 2, 0.1, 0.25);
  hat(t + beat / 4, 0.04, -0.3);
  hat(t + (3 * beat) / 4, 0.04, -0.3);
  const root = ROOTS[bar % 4];
  bass(t + beat / 2, root, beat / 2 - 0.01);
  bass(t + beat * 0.75, root * 2, beat / 4 - 0.01, 0.16);
  if (b % 4 === 0) pad(t, beat * 4, CHORDS[bar % 4]);
}

for (const c of cuts) whoosh(f2s(c));

// Export completes (export scene starts at the second-to-last cut, finishes ~66 frames in).
chime(f2s(cuts[cuts.length - 2] + 66));

// Outro: logo slam, then a long chord tail.
impact(outroStart + f2s(24), 1);
pad(outroStart, DUR - outroStart, [220, 261.63, 329.63, 440], 0.04);
for (let i = 0; i < 3; i++) hat(outroStart + f2s(40 + i * 10), 0.12);

// Two combs per side as a cheap room.
function comb(src, dst, delay, fb, gain) {
  const d = S(delay);
  const buf = new Float32Array(N);
  for (let i = 0; i < N; i++) {
    buf[i] = src[i] + (i >= d ? buf[i - d] * fb : 0);
    dst[i] += buf[i] * gain;
  }
}
comb(verbL, L, 0.0297, 0.72, 0.28);
comb(verbL, L, 0.0371, 0.7, 0.24);
comb(verbR, R, 0.0331, 0.72, 0.28);
comb(verbR, R, 0.0411, 0.7, 0.24);

// Fade the last half second, soft-clip, normalize.
for (let i = S(DUR - 0.6); i < N; i++) {
  const g = Math.max(0, (N - i) / S(0.6));
  L[i] *= g;
  R[i] *= g;
}
let peak = 0;
for (let i = 0; i < N; i++) {
  L[i] = Math.tanh(L[i] * 1.1);
  R[i] = Math.tanh(R[i] * 1.1);
  peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i]));
}
const gain = 0.89 / peak;
const buf = Buffer.alloc(44 + N * 4);
buf.write("RIFF", 0);
buf.writeUInt32LE(36 + N * 4, 4);
buf.write("WAVEfmt ", 8);
buf.writeUInt32LE(16, 16);
buf.writeUInt16LE(1, 20);
buf.writeUInt16LE(2, 22);
buf.writeUInt32LE(SR, 24);
buf.writeUInt32LE(SR * 4, 28);
buf.writeUInt16LE(4, 32);
buf.writeUInt16LE(16, 34);
buf.write("data", 36);
buf.writeUInt32LE(N * 4, 40);
for (let i = 0; i < N; i++) {
  buf.writeInt16LE(Math.round(L[i] * gain * 32767), 44 + i * 4);
  buf.writeInt16LE(Math.round(R[i] * gain * 32767), 46 + i * 4);
}
mkdirSync(new URL("../public/audio/", import.meta.url), { recursive: true });
writeFileSync(new URL("../public/audio/soundtrack.wav", import.meta.url), buf);
console.log(`soundtrack.wav ${DUR.toFixed(2)}s, cuts at ${cuts.map((c) => (c / FPS).toFixed(2)).join(", ")}`);
