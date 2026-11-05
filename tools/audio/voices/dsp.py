"""Small synthesis kit for Berghittn's sounds (M6 part 2). Everything is made from oscillators,
noise, filters and envelopes; no samples. Signals are mono float64 numpy arrays at SR."""
import numpy as np
from scipy import signal

SR = 44100
rng = np.random.default_rng(1704)


def seed(n: int) -> None:
    global rng
    rng = np.random.default_rng(n)


def n_of(seconds: float) -> int:
    return max(1, int(round(seconds * SR)))


def t_of(seconds: float) -> np.ndarray:
    return np.arange(n_of(seconds)) / SR


# --- sources ---------------------------------------------------------------------------------------

def noise(seconds: float) -> np.ndarray:
    return rng.standard_normal(n_of(seconds))


def pink(seconds: float) -> np.ndarray:
    # Voss-ish: white noise through a -3 dB/oct filter (Paul Kellet's economy coefficients).
    b = [0.049922035, -0.095993537, 0.050612699, -0.004408786]
    a = [1, -2.494956002, 2.017265875, -0.522189400]
    return normalize(signal.lfilter(b, a, noise(seconds)))


def brown(seconds: float) -> np.ndarray:
    return normalize(signal.lfilter([1.0], [1.0, -0.995], noise(seconds)))


def phase(freq, seconds: float) -> np.ndarray:
    """Running phase (cycles) for a constant or per-sample frequency."""
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n_of(seconds),))
    return np.cumsum(f) / SR


def sine(freq, seconds: float, ph: float = 0.0) -> np.ndarray:
    return np.sin(2 * np.pi * (phase(freq, seconds) + ph))


def saw(freq, seconds: float) -> np.ndarray:
    p = phase(freq, seconds)
    return 2.0 * (p - np.floor(p + 0.5))


def square(freq, seconds: float, duty: float = 0.5) -> np.ndarray:
    p = phase(freq, seconds) % 1.0
    return np.where(p < duty, 1.0, -1.0)


def harmonics(freq, seconds: float, amps, bright=None) -> np.ndarray:
    """Additive tone: amps[k] for harmonic k+1, each scaled by bright**k (bright may vary in time),
    skipping partials above Nyquist."""
    p = phase(freq, seconds)
    f0 = float(np.max(np.asarray(freq)))
    out = np.zeros_like(p)
    for k, a in enumerate(amps):
        if f0 * (k + 1) > SR * 0.45:
            break
        g = a if bright is None else a * np.power(bright, k)
        out += g * np.sin(2 * np.pi * (k + 1) * p)
    return out


def partials(seconds: float, parts) -> np.ndarray:
    """Inharmonic bell/metal partials: (freq, amp, decay seconds)."""
    t = t_of(seconds)
    out = np.zeros_like(t)
    for f, a, d in parts:
        if f < SR * 0.45:
            out += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / d)
    return out


def glottal(freq, seconds: float, jitter: float = 0.01, shimmer: float = 0.1) -> np.ndarray:
    """Buzzy voice source: a band-limited saw with wandering pitch and loudness."""
    n = n_of(seconds)
    wander = smooth_noise(seconds, 18.0) * jitter
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,)) * (1.0 + wander)
    src = harmonics(f, seconds, [1.0 / (k + 1) for k in range(40)])
    return src * (1.0 + shimmer * smooth_noise(seconds, 25.0))


def smooth_noise(seconds: float, rate: float) -> np.ndarray:
    """Random wobble in -1..1 that changes about `rate` times a second."""
    n = n_of(seconds)
    pts = max(4, int(seconds * rate) + 4)
    knots = rng.uniform(-1, 1, pts)
    x = np.linspace(0, pts - 3, n)
    return np.interp(x, np.arange(pts), knots)


# --- envelopes -------------------------------------------------------------------------------------

def env_exp(seconds: float, decay: float, attack: float = 0.001) -> np.ndarray:
    t = t_of(seconds)
    e = np.exp(-t / decay)
    if attack > 0:
        e *= np.clip(t / attack, 0, 1)
    return e


def env_adsr(seconds: float, a: float, d: float, s: float, r: float) -> np.ndarray:
    n = n_of(seconds)
    t = np.arange(n) / SR
    e = np.full(n, s, dtype=float)
    e[t < a] = t[t < a] / max(a, 1e-6)
    m = (t >= a) & (t < a + d)
    e[m] = 1.0 - (1.0 - s) * (t[m] - a) / max(d, 1e-6)
    rel = t > seconds - r
    e[rel] *= np.clip((seconds - t[rel]) / max(r, 1e-6), 0, 1)
    return e


def env_points(seconds: float, points) -> np.ndarray:
    """Piecewise-linear envelope through (time, value) points."""
    pts = np.array(points, dtype=float)
    return np.interp(t_of(seconds), pts[:, 0], pts[:, 1])


def glide(seconds: float, start: float, end: float, curve: float = 1.0) -> np.ndarray:
    x = np.linspace(0, 1, n_of(seconds)) ** curve
    return start * (end / start) ** x


# --- filters ---------------------------------------------------------------------------------------

def _sos(kind: str, freq, order: int = 2):
    nyq = SR / 2
    if isinstance(freq, (tuple, list)):
        wn = [min(max(f / nyq, 1e-4), 0.999) for f in freq]
    else:
        wn = min(max(freq / nyq, 1e-4), 0.999)
    return signal.butter(order, wn, btype=kind, output="sos")


def lowpass(x, freq, order=2):
    return signal.sosfilt(_sos("lowpass", freq, order), x)


def highpass(x, freq, order=2):
    return signal.sosfilt(_sos("highpass", freq, order), x)


def bandpass(x, lo, hi, order=2):
    return signal.sosfilt(_sos("bandpass", (lo, hi), order), x)


def resonator(x, freq: float, q: float):
    """Peaky band-pass (a formant or a body resonance)."""
    w = 2 * np.pi * freq / SR
    alpha = np.sin(w) / (2 * q)
    b = [alpha, 0, -alpha]
    a = [1 + alpha, -2 * np.cos(w), 1 - alpha]
    return signal.lfilter(b, a, x)


def sweep_lowpass(x, cutoff) -> np.ndarray:
    """One-pole low-pass whose cutoff (Hz, per sample) moves; done in short blocks."""
    cutoff = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    out = np.empty_like(x)
    zi = np.zeros((1, 2))
    block = 256
    for i in range(0, len(x), block):
        f = float(np.mean(cutoff[i:i + block]))
        sos = _sos("lowpass", min(max(f, 20.0), SR * 0.45), 2)
        out[i:i + block], zi = signal.sosfilt(sos, x[i:i + block], zi=zi)
    return out


VOWELS = {
    # (formant Hz, bandwidth Q, gain)
    "a": [(800, 6, 1.0), (1150, 8, 0.6), (2900, 12, 0.25)],
    "o": [(450, 6, 1.0), (800, 8, 0.45), (2830, 12, 0.12)],
    "u": [(325, 6, 1.0), (700, 8, 0.25), (2530, 12, 0.08)],
    "e": [(400, 6, 1.0), (1700, 10, 0.4), (2600, 12, 0.3)],
    "i": [(270, 6, 1.0), (2100, 12, 0.35), (3000, 14, 0.3)],
    "ae": [(660, 6, 1.0), (1700, 10, 0.5), (2400, 12, 0.3)],
    "m": [(250, 5, 1.0), (1000, 6, 0.05), (2500, 8, 0.02)],
}


def vowel(x, v: str, shift: float = 1.0):
    out = np.zeros_like(x)
    for f, q, g in VOWELS[v]:
        out += g * resonator(x, f * shift, q)
    return out


def vowel_morph(x, path, shift: float = 1.0):
    """Moves through vowels: path = [(time, vowel), ...]; crossfades the filtered copies."""
    copies = {v: vowel(x, v, shift) for _, v in path}
    t = np.arange(len(x)) / SR
    out = np.zeros_like(x)
    times = [p[0] for p in path]
    for i, (ti, v) in enumerate(path):
        w = np.zeros_like(t)
        prev_t = times[i - 1] if i > 0 else None
        next_t = times[i + 1] if i + 1 < len(path) else None
        if prev_t is None:
            w[t <= ti] = 1.0
        else:
            m = (t > prev_t) & (t <= ti)
            w[m] = (t[m] - prev_t) / (ti - prev_t)
        if next_t is None:
            w[t > ti] = 1.0
        else:
            m = (t > ti) & (t < next_t)
            w[m] = 1.0 - (t[m] - ti) / (next_t - ti)
        out += w * copies[v]
    return out


# --- effects ---------------------------------------------------------------------------------------

def drive(x, amount: float):
    return np.tanh(x * amount) / np.tanh(amount)


def reverb(x, seconds: float = 1.2, wet: float = 0.25, damp: float = 4000.0, pre: float = 0.01):
    """Convolution with a decaying noise burst (a room or the open alm)."""
    ir_t = t_of(seconds)
    ir = noise(seconds) * np.exp(-ir_t * 6.9 / seconds)
    ir = lowpass(ir, damp)
    ir[: n_of(pre)] = 0
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    tail = signal.fftconvolve(x, ir)[: len(x) + len(ir)]
    dry = np.concatenate([x, np.zeros(len(tail) - len(x))])
    return dry * (1 - wet) + tail * wet


def echo(x, delay: float, feedback: float, repeats: int, damp: float = 3000.0):
    d = n_of(delay)
    out = np.concatenate([x, np.zeros(d * repeats)])
    tap = x.copy()
    for i in range(1, repeats + 1):
        tap = lowpass(tap, damp) * feedback
        out[i * d: i * d + len(tap)] += tap
    return out


def pad(x, seconds: float):
    return np.concatenate([x, np.zeros(n_of(seconds))])


def mix(*parts):
    """Sum of (offset seconds, signal) pairs or plain signals."""
    items = [(0.0, p) if isinstance(p, np.ndarray) else p for p in parts]
    length = max(n_of(o) + len(s) for o, s in items)
    out = np.zeros(length)
    for o, s in items:
        i = n_of(o) if o > 0 else 0
        out[i:i + len(s)] += s
    return out


def normalize(x, peak: float = 0.9):
    m = np.max(np.abs(x)) + 1e-12
    return x * (peak / m)


def fade(x, fin: float = 0.002, fout: float = 0.01):
    x = x.copy()
    a, b = n_of(fin), n_of(fout)
    x[:a] *= np.linspace(0, 1, a)
    x[-b:] *= np.linspace(1, 0, b)
    return x


def trim(x, threshold: float = 0.0015):
    """Cuts the silent end."""
    idx = np.nonzero(np.abs(x) > threshold * np.max(np.abs(x)))[0]
    return x[: idx[-1] + n_of(0.02)] if len(idx) else x


def loopable(x, overlap: float):
    """Crossfades the end into the start so the clip loops without a seam."""
    k = n_of(overlap)
    body = x[: len(x) - k].copy()
    w = np.linspace(0, 1, k)
    body[:k] = body[:k] * w + x[len(x) - k:] * (1 - w)
    return body
