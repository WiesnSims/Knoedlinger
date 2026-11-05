"""Enemy voice lines: every line is spoken by eSpeak NG and run through a filter per voice, the way
Berghittn's "Gredn" did it (tools/audio/voices.py there; dsp.py is copied from it). The Tourist, the
Perchte and the Oberkrampus keep the filters the owner approved in Berghittn; the others are new.

eSpeak NG (GPL-3) is only a tool on the dev machine, never shipped; the audio it makes is ours.
    winget install --id eSpeak-NG.eSpeak-NG -e      (or set ESPEAK to the espeak-ng executable)
    pip install numpy scipy soundfile

    python tools/audio/voices/voices.py --samples   # a few lines per voice to build/voice_samples/
"""
import html
import os
import shutil
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal

import dsp as d

SR = d.SR
ROOT = Path(__file__).resolve().parents[3]
PEAK = 0.85
QUALITY = 0.45


def espeak() -> str:
    """The espeak-ng executable, or "" when it is not installed."""
    for path in (os.environ.get("ESPEAK", ""), shutil.which("espeak-ng") or "",
                 "C:/Program Files/eSpeak NG/espeak-ng.exe", "C:/Program Files (x86)/eSpeak NG/espeak-ng.exe"):
        if path and os.path.isfile(path):
            return path
    return ""


def speak(text, voice, speed, pitch, extra=()):
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        path = f.name
    try:
        subprocess.run([espeak(), "-v", voice, "-s", str(speed), "-p", str(pitch), *extra, "-w", path, text],
                       check=True, capture_output=True)
        x, sr = sf.read(path)
    finally:
        os.remove(path)
    if x.ndim > 1:
        x = x.mean(axis=1)
    return x, sr


def at_pitch(x, sr, factor):
    """Resampled to SR so it plays `factor` x higher (and faster)."""
    return signal.resample(x, int(round(len(x) * SR / sr / factor)))


def envelope(x, cutoff=30.0):
    return d.lowpass(np.abs(x), cutoff)


def vocode(mod, carrier, bands=24, lo=80.0, hi=7000.0):
    """Channel vocoder: the speech's spectrum shape on our own carrier."""
    edges = np.geomspace(lo, hi, bands + 1)
    out = np.zeros_like(mod)
    for a, b in zip(edges[:-1], edges[1:]):
        env = envelope(d.bandpass(mod, a, b, 2), 40.0)
        out += d.bandpass(carrier, a, b, 2) * np.maximum(env, 0)
    return out


def rasp(x, amount):
    """Breath noise riding on the voice's loudness."""
    env = np.maximum(envelope(x, 25.0), 0)
    return x + d.bandpass(d.noise(len(x) / SR), 900, 5000) * env * amount


def growl(seconds, f0, path, breath, jitter, rough, drv):
    """A buzzy vowel source with vocal fry (Berghittn's sfx.voice)."""
    src = d.glottal(f0, seconds, jitter=jitter, shimmer=0.25)
    if rough > 0:
        src *= 1.0 + rough * d.square(f0 * 0.5, seconds)
    src = src + d.noise(seconds) * breath
    return d.drive(d.normalize(d.vowel_morph(src, path)), drv)


def finish(x, room=0.18, seconds=0.9):
    x = d.reverb(d.normalize(x), seconds, room)
    return d.fade(d.normalize(d.trim(x), 0.85), 0.005, 0.05)


# --- one filter per voice --------------------------------------------------------------------------

def tourist(text):
    """Quick, a bit higher, thin like a phone speaker; no hiss (Berghittn, approved)."""
    x, sr = speak(text, "de+m1", 175, 60)
    x = at_pitch(x, sr, 0.92)
    x = d.bandpass(d.drive(d.normalize(x), 1.3), 250, 4500)
    return finish(x, 0.12)


def akten(text):
    """A hollow paper ghost: two slightly detuned copies, thin, echoing down an office corridor."""
    x, sr = speak(text, "de+f2", 140, 45)
    a = at_pitch(x, sr, 0.97)
    b = at_pitch(x, sr, 1.02)
    n = min(len(a), len(b))
    x = d.normalize(a[:n]) + 0.7 * d.normalize(b[:n])
    t = np.arange(n) / SR
    x = d.bandpass(x, 300, 3500) * (1.0 + 0.25 * np.sin(2 * np.pi * 4.0 * t))
    return finish(d.echo(x, 0.16, 0.35, 3, 2500), 0.32, 1.4)


def radler(text):
    """Quick and out of breath: pumping loudness, panting hiss, a gust of wind."""
    x, sr = speak(text, "de+m4", 190, 55)
    x = at_pitch(x, sr, 1.0)
    t = np.arange(len(x)) / SR
    x = rasp(d.normalize(x), 0.9) * (1.0 + 0.3 * np.sin(2 * np.pi * 3.2 * t))
    wind = d.lowpass(d.noise(len(x) / SR), 600) * 0.08
    return finish(d.bandpass(d.drive(d.normalize(x), 1.4), 180, 6000) + wind, 0.06, 0.4)


def roboter(text):
    """A flat robot: the words on a fixed-pitch buzz, a little bitcrushed, no room."""
    x, sr = speak(text, "de+m1", 150, 50, ("-k", "0"))
    x = at_pitch(x, sr, 1.0)
    s = len(x) / SR
    carrier = d.saw(110.0, s) + 0.5 * d.square(220.0, s, 0.3)
    x = vocode(d.normalize(x), carrier[:len(x)], 20)
    steps = 24.0
    x = np.round(d.normalize(x) * steps) / steps
    return finish(d.bandpass(x, 200, 5000), 0.04, 0.3)


def perchte(text):
    """A whisper over a trembling growl (Berghittn, approved)."""
    x, sr = speak(text, "de+whisper", 140, 50)
    x = at_pitch(x, sr, 0.85)
    t = np.arange(len(x)) / SR
    s = len(x) / SR
    g = growl(s, 55.0, [(0, "a"), (s, "o")], 0.8, 0.3, 0.06, 0.6)
    x = d.normalize(x) + 0.5 * vocode(d.normalize(x), g[:len(x)])
    x = x * (1.0 + 0.4 * np.sin(2 * np.pi * 31 * t))
    return finish(d.drive(d.normalize(x), 2.2), 0.2)


def kontrolleur(text):
    """A nasal official: a narrow, honking middle, measured, dry little office."""
    x, sr = speak(text, "de+m2", 135, 58)
    x = at_pitch(x, sr, 0.95)
    x = d.normalize(x)
    x = d.bandpass(x, 400, 3200) + 1.2 * d.resonator(x, 1150.0, 6.0) + 0.6 * d.resonator(x, 2400.0, 8.0)
    return finish(d.drive(d.normalize(x), 1.3), 0.08, 0.5)


def oberkrampus(text):
    """Very deep, on a growl, in a big room (Berghittn's Krampus, approved)."""
    x, sr = speak(text, "de+m3", 150, 10)
    x = at_pitch(x, sr, 0.62)
    s = len(x) / SR
    carrier = growl(s, 48.0, [(0, "o"), (s, "a")], 0.7, 0.25, 0.04, 0.9)
    x = 0.55 * d.normalize(x) + vocode(d.normalize(x), carrier[:len(x)])
    x = d.lowpass(d.drive(d.normalize(x), 3.0), 3000)
    return finish(x, 0.3, 1.8)


def hofrat(text):
    """Dry and bored: low, slow, a touch of grit, a long marble hall."""
    x, sr = speak(text, "de+m5", 115, 30)
    x = at_pitch(x, sr, 0.86)
    x = d.lowpass(d.drive(d.normalize(rasp(x, 0.25)), 1.4), 3800) + 0.2 * d.lowpass(x, 250)
    return finish(d.echo(x, 0.33, 0.18, 2, 2200), 0.24, 2.2)


# --- the samples the owner listens to before every line is made -----------------------------------

SAMPLES = {
    "tourist": ["Nur no a Selfie!", "Is des do ois inklusive?", "Des gibt a schlechte Bewertung!"],
    "akten": ["Formular B sieben fehlt!", "Bitte ziehen Sie eine Nummer."],
    "radler": ["Radweg! Weg do!", "Mei Bestzeit."],
    "roboter": ["Rasen wird gemäht. Bitte Abstand halten.", "Fehler. Knödl im Mähbereich."],
    "perchte": ["Hö! Hö! Hö!", "Jetzt kimmst!"],
    "kontrolleur": ["Ohne Stempel ka Eintritt!", "Behinderung einer Amtshandlung!"],
    "oberkrampus": ["Wer war heit ned brav?", "I kimm wieder. Nächsts Joahr!"],
    "hofrat": ["Sie san ned zuständig.", "Abgelehnt!", "Des geht an die nächste Instanz."],
}
FILTERS = {"tourist": tourist, "akten": akten, "radler": radler, "roboter": roboter, "perchte": perchte,
           "kontrolleur": kontrolleur, "oberkrampus": oberkrampus, "hofrat": hofrat}


def write(path: Path, name: str, fn, text: str) -> float:
    # Same name, same sound: rebuilding never changes files nobody touched.
    d.seed(zlib.crc32(name.encode()))
    x = np.asarray(fn(text), dtype=np.float64)
    if not np.all(np.isfinite(x)):
        raise ValueError("%s is not finite" % name)
    x = x - np.mean(x)
    x = d.fade(x, 0.0005, min(0.03, len(x) / SR * 0.2))
    x = np.clip(x * min(1.0, PEAK / (np.max(np.abs(x)) + 1e-9)), -1.0, 1.0).astype(np.float32)
    path.parent.mkdir(parents=True, exist_ok=True)
    # In blocks: libsndfile's Vorbis encoder overflows the stack on one long write.
    with sf.SoundFile(str(path), "w", SR, 1, format="OGG", subtype="VORBIS", compression_level=QUALITY) as f:
        for i in range(0, len(x), 8192):
            f.write(x[i:i + 8192])
    return len(x) / SR


def samples() -> None:
    """Renders SAMPLES and a page to listen to them (build/voice_samples/index.html)."""
    out = ROOT / "build" / "voice_samples"
    rows = []
    for voice, lines in SAMPLES.items():
        rows.append("<h2>%s</h2><p>%s</p>" % (voice.capitalize(), html.escape((FILTERS[voice].__doc__ or "").strip())))
        for i, text in enumerate(lines):
            path = out / ("%s_%d.ogg" % (voice, i + 1))
            seconds = write(path, path.stem, FILTERS[voice], text)
            print("%-28s %5.2f s  %s" % (path.name, seconds, text))
            rows.append('<div><audio controls src="%s"></audio> %s</div>' % (path.name, html.escape(text)))
    (out / "index.html").write_text(
        "<!doctype html><meta charset=utf-8><title>Voice samples</title><style>body{font:16px sans-serif;"
        "max-width:760px;margin:24px auto;padding:0 16px}h2{margin:24px 0 4px}p{margin:0 0 8px;color:#555}"
        "div{display:flex;gap:12px;align-items:center;margin:4px 0}</style>"
        "<h1>Knödlinger enemy voice samples</h1>" + "".join(rows), encoding="utf-8")


if __name__ == "__main__":
    if not espeak():
        sys.exit("eSpeak NG not found (winget install --id eSpeak-NG.eSpeak-NG -e, or set ESPEAK)")
    if "--samples" in sys.argv:
        samples()
    else:
        sys.exit("usage: voices.py --samples")
