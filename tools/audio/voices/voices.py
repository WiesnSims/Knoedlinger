"""Enemy voice lines: every line is spoken by eSpeak NG and run through a filter per voice, the way
Berghittn's "Gredn" did it (tools/audio/voices.py there; dsp.py is copied from it). The Tourist, the
Perchte and the Oberkrampus keep the filters the owner approved in Berghittn; the others are new.

eSpeak NG (GPL-3) is only a tool on the dev machine, never shipped; the audio it makes is ours.
    winget install --id eSpeak-NG.eSpeak-NG -e      (or set ESPEAK to the espeak-ng executable)
    pip install numpy scipy soundfile

    python tools/audio/voices/voices.py             # every line to assets/audio/sfx/voice_*.ogg
    python tools/audio/voices/voices.py voice_hofrat_abgelehnt   # only these
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


def hungrig(text):
    """The Tourist, slower and lower with his mouth full."""
    x, sr = speak(text, "de+m1", 150, 40)
    x = at_pitch(x, sr, 0.84)
    x = d.bandpass(d.drive(d.normalize(x), 1.4), 200, 3800) + 0.3 * d.lowpass(x, 300)
    return finish(x, 0.12)


def schneemann(text):
    """Low, slow and muffled (Berghittn's Wanderer), with a cold shiver on it."""
    x, sr = speak(text, "de+m3", 125, 35)
    x = at_pitch(x, sr, 0.9)
    t = np.arange(len(x)) / SR
    x = d.lowpass(d.drive(d.normalize(x), 1.3), 2800) + 0.25 * d.lowpass(x, 300)
    return finish(x * (1.0 + 0.18 * np.sin(2 * np.pi * 9.0 * t)), 0.15)


def zwerg(text, factor=1.2, cutoff=7500.0):
    """Quick and high with a giggly wobble (Berghittn's Venedigermandl), a small dry room."""
    x, sr = speak(text, "de+m4", 185, 80)
    x = at_pitch(x, sr, factor)
    t = np.arange(len(x)) / SR
    x = d.normalize(x) * (1.0 + 0.22 * np.sin(2 * np.pi * 6.5 * t))
    x = d.bandpass(d.drive(x, 1.2), 200, cutoff)
    return finish(x, 0.1, 0.6)


def wuehlmaus(text):
    """Even higher than the Gartenzwerg, muffled from under the lawn."""
    return zwerg(text, 1.45, 3000.0)


def dackel(text):
    """A small, yappy dog: a quick high bark, a little gritty."""
    x, sr = speak(text, "de+m4", 210, 90)
    x = at_pitch(x, sr, 1.35)
    x = d.bandpass(d.drive(d.normalize(x), 2.0), 300, 6000)
    return finish(x, 0.08, 0.4)


def taube(text):
    """A coo: low, round, rolling."""
    x, sr = speak(text, "de+m3", 120, 45)
    x = at_pitch(x, sr, 0.95)
    t = np.arange(len(x)) / SR
    x = d.lowpass(d.normalize(x), 1400) * (1.0 + 0.5 * np.sin(2 * np.pi * 22.0 * t))
    return finish(x, 0.1, 0.5)


def wildschwein(text):
    """A grunt: very low and rough on a growl."""
    x, sr = speak(text, "de+m3", 140, 15)
    x = at_pitch(x, sr, 0.6)
    s = len(x) / SR
    carrier = growl(s, 70.0, [(0, "o"), (s, "u")], 0.5, 0.2, 0.08, 1.2)
    x = 0.5 * d.normalize(rasp(x, 0.8)) + vocode(d.normalize(x), carrier[:len(x)])
    return finish(d.lowpass(d.drive(d.normalize(x), 2.4), 2500), 0.1, 0.5)


def wirt(text):
    """The Riesen-Wirt: big, warm and booming, in the whole Wirtshaus."""
    x, sr = speak(text, "de+m3", 135, 25)
    x = at_pitch(x, sr, 0.74)
    x = d.lowpass(d.drive(d.normalize(x), 1.6), 3500) + 0.35 * d.lowpass(x, 220)
    return finish(x, 0.3, 2.0)


def geist(text):
    """A Stammgast-Geist: slow, airy and wavering, a breath under it, far down an empty Gaststube."""
    x, sr = speak(text, "de+m2", 120, 70)
    x = at_pitch(x, sr, 1.06)
    t = np.arange(len(x)) / SR
    x = d.bandpass(d.normalize(x), 260, 4200) * (1.0 + 0.35 * np.sin(2 * np.pi * 5.5 * t))
    x = d.normalize(x) + 0.35 * d.normalize(rasp(x, 0.9))
    return finish(d.echo(x, 0.22, 0.4, 4, 3000), 0.4, 2.0)


def geist_grantig(text):
    """The grantige Stammgast: the same ghost lower, rougher and shaking with anger."""
    x, sr = speak(text, "de+m3", 150, 35)
    x = at_pitch(x, sr, 0.86)
    t = np.arange(len(x)) / SR
    x = d.bandpass(d.drive(d.normalize(x), 2.2), 180, 3800) * (1.0 + 0.3 * np.sin(2 * np.pi * 8.0 * t))
    x = d.normalize(x) + 0.25 * d.normalize(rasp(x, 1.0))
    return finish(d.echo(x, 0.18, 0.35, 3, 2500), 0.35, 1.6)


# --- the samples the owner listens to before every line is made -----------------------------------

def schnecke(text):
    """A vineyard snail: very slow, low and gooey, a lazy wobble."""
    x, sr = speak(text, "de+m3", 95, 30)
    x = at_pitch(x, sr, 0.82)
    t = np.arange(len(x)) / SR
    x = d.lowpass(d.normalize(x), 2200) * (1.0 + 0.25 * np.sin(2 * np.pi * 3.0 * t))
    return finish(x, 0.15, 0.8)


def star(text):
    """A starling: quick, high and chirpy, a flutter on top."""
    x, sr = speak(text, "de+f2", 200, 95)
    x = at_pitch(x, sr, 1.5)
    t = np.arange(len(x)) / SR
    x = d.bandpass(d.normalize(x), 600, 8000) * (1.0 + 0.35 * np.sin(2 * np.pi * 14.0 * t))
    return finish(x, 0.08, 0.4)


def wespe(text):
    """A wasp: high and nasal on a buzz."""
    x, sr = speak(text, "de+m4", 175, 85)
    x = at_pitch(x, sr, 1.3)
    t = np.arange(len(x)) / SR
    x = d.normalize(x) * (0.7 + 0.3 * np.sign(np.sin(2 * np.pi * 110.0 * t)))
    x = d.bandpass(d.drive(x, 1.6), 500, 6000) + 0.8 * d.resonator(x, 1800.0, 6.0)
    return finish(d.normalize(x), 0.08, 0.4)


def sturm(text):
    """Der Sturm: a big, tipsy whirlwind, breathy and swirling in a wide space."""
    x, sr = speak(text, "de+m1", 120, 40)
    x = at_pitch(x, sr, 0.8)
    t = np.arange(len(x)) / SR
    x = d.normalize(x) * (1.0 + 0.3 * np.sin(2 * np.pi * 1.5 * t))
    x = 0.8 * x + 0.25 * d.lowpass(rasp(x, 1.0), 4000)
    return finish(d.echo(x, 0.28, 0.35, 3, 2600), 0.35, 2.0)


def hausmeisterin(text):
    """Die Hausmeisterin: a sharp, nasal older woman who has said it a thousand times, in a stairwell."""
    x, sr = speak(text, "de+f4", 150, 62)
    x = at_pitch(x, sr, 1.05)
    x = d.normalize(x)
    x = d.bandpass(x, 300, 4200) + 0.9 * d.resonator(x, 1350.0, 7.0)
    x = d.drive(d.normalize(rasp(x, 0.3)), 1.5)
    return finish(d.echo(x, 0.12, 0.3, 3, 3000), 0.2, 1.2)


SAMPLES = {
    "tourist": ["Nur no a Selfie!", "Is des do ois inklusive?", "Des gibt a schlechte Bewertung!"],
    "akten": ["Formular B sieben fehlt!", "Bitte ziehen Sie eine Nummer."],
    "radler": ["Radweg! Weg do!", "Mei Bestzeit."],
    "roboter": ["Rasen wird gemäht. Bitte Abstand halten.", "Fehler. Knödl im Mähbereich."],
    "perchte": ["Hö! Hö! Hö!", "Jetzt kimmst!"],
    "kontrolleur": ["Ohne Stempel ka Eintritt!", "Behinderung einer Amtshandlung!"],
    "oberkrampus": ["Wer war heit ned brav?", "I kimm wieder. Nächsts Joahr!"],
    "hofrat": ["Sie san ned zuständig.", "Abgelehnt!", "Des geht an die nächste Instanz."],
    "schnecke": ["Nur ned hudln.", "I hob Zeit. Vü Zeit."],
    "star": ["Brösel! Brösel!", "Mia san vü mehr!"],
    "wespe": ["Is des wos Süßes?", "Mmh, Marille!"],
    "sturm": ["Heuer is a guater Johrgang!", "Jetzt wirds lustig!"],
    "hausmeisterin": ["Do wird jetzt zammkehrt!", "Um zehne wird zuagsperrt!"],
}
FILTERS = {"tourist": tourist, "akten": akten, "radler": radler, "roboter": roboter, "perchte": perchte,
           "kontrolleur": kontrolleur, "oberkrampus": oberkrampus, "hofrat": hofrat, "hungrig": hungrig,
           "schneemann": schneemann, "zwerg": zwerg, "wuehlmaus": wuehlmaus, "dackel": dackel, "taube": taube,
           "wildschwein": wildschwein, "wirt": wirt, "geist": geist,
           "geist_grantig": geist_grantig, "schnecke": schnecke, "star": star, "wespe": wespe, "sturm": sturm,
           "hausmeisterin": hausmeisterin}

# --- every line --------------------------------------------------------------------------------------
# (enemy id, moment, line, text shown, how eSpeak says it, voice). The game's side is data:
# data/voice_lines/<enemy>.tres (moment, text key VOICE_<ENEMY>_<LINE>, sound voice_<enemy>_<line>)
# and the text in i18n/strings.csv. A new line goes into all three. Lines may share a sound
# (the same enemy saying it at two moments): the first one makes it.
LINES = [
    ("tourist", "IDLE", "selfie", "Nur no a Selfie!", "Nur no a Selfie!", "tourist"),
    ("tourist", "IDLE", "inklusive", "Is des do ois inklusive?", "Is des do ois inklusive?", "tourist"),
    ("tourist", "IDLE", "wlan", "Wo is do des WLAN?", "Wo is do des W-LAN?", "tourist"),
    ("tourist", "IDLE", "speck", "Gibt's des a ohne Speck?", "Gibts des a ohne Speck?", "tourist"),
    ("tourist", "DEATH", "tschuess", "Tschüss!", "Tschüss!", "tourist"),
    ("tourist", "DEATH", "bewertung", "Des gibt a schlechte Bewertung!", "Des gibt a schlechte Bewertung!", "tourist"),
    ("tourist", "CRUSHED", "knoedl", "Na geh, a Knödl!", "Na geh, a Knödl!", "tourist"),
    ("hungriger_tourist", "IDLE", "nachspeis", "Und wo is die Nachspeis?", "Und wo is die Nachspeis?", "hungrig"),
    ("hungriger_tourist", "IDLE", "buffet", "Is des Buffet scho offen?", "Is des Buffet scho offen?", "hungrig"),
    ("hungriger_tourist", "EAT", "mmh", "Mmh, a Knödl!", "Mmmh. A Knödl!", "hungrig"),
    ("hungriger_tourist", "EAT", "nachschlag", "I nimm an Nachschlag!", "I nimm an Nachschlag!", "hungrig"),
    ("hungriger_tourist", "DEATH", "zoit", "I hob no gar ned zoit!", "I hob no gar ned zoit!", "hungrig"),
    ("akten_geist", "IDLE", "b7", "Formular B7 fehlt!", "Formular B sieben fehlt!", "akten"),
    ("akten_geist", "IDLE", "nummer", "Bitte ziehen Sie eine Nummer.", "Bitte ziehen Sie eine Nummer.", "akten"),
    ("akten_geist", "IDLE", "abteilung", "Des is ned mei Abteilung.", "Des is ned mei Abteilung.", "akten"),
    ("akten_geist", "DEATH", "dreifach", "In dreifacher Ausfertigung!", "In dreifacher Ausfertigung!", "akten"),
    ("formular", "IDLE", "ausfuellen", "Bitte vollständig ausfüllen!", "Bitte vollständig ausfüllen!", "akten"),
    ("formular", "DEATH", "zerknittert", "Zerknittert …", "Zerknittert.", "akten"),
    ("radler", "ATTACK", "radweg", "Radweg! Weg do!", "Radweg! Weg do!", "radler"),
    ("radler", "ATTACK", "klingel", "Klingel, klingel!", "Kling kling!", "radler"),
    ("radler", "IDLE", "vorrang", "I hob Vorrang!", "I hob Vorrang!", "radler"),
    ("radler", "DEATH", "bestzeit", "Mei Bestzeit …", "Mei Bestzeit.", "radler"),
    ("radler", "CRUSHED", "radl", "Mei Carbonradl!", "Mei Carbonradl!", "radler"),
    ("rasenmaeher", "IDLE", "abstand", "Rasen wird gemäht. Bitte Abstand halten.",
     "Rasen wird gemäht. Bitte Abstand halten.", "roboter"),
    ("rasenmaeher", "IDLE", "maehbereich", "Fehler: Knödl im Mähbereich.", "Fehler. Knödl im Mähbereich.", "roboter"),
    ("rasenmaeher", "IDLE", "akku", "Akku bei 10 %.", "Akku bei zehn Prozent.", "roboter"),
    ("rasenmaeher", "DEATH", "ladestation", "Zurück … zur … Ladestation …", "Zurück. Zur. Ladestation.", "roboter"),
    ("perchte", "IDLE", "hoe", "Hö-hö-hö!", "Hö! Hö! Hö!", "perchte"),
    ("perchte", "ATTACK", "kimmst", "Jetzt kimmst!", "Jetzt kimmst!", "perchte"),
    ("perchte", "DEATH", "schelln", "Mei Schelln …", "Mei Schelln.", "perchte"),
    ("schneemann", "ATTACK", "fang", "Fang!", "Fang!", "schneemann"),
    ("schneemann", "ATTACK", "schneeballschlacht", "Schneeballschlacht!", "Schneeballschlacht!", "schneemann"),
    ("schneemann", "IDLE", "hitz", "Is des a Hitz heit.", "Is des a Hitz heit.", "schneemann"),
    ("schneemann", "DEATH", "schmilz", "I schmilz …", "I schmilz.", "schneemann"),
    ("gartenzwerg", "IDLE", "beet", "Runter von mein Beet!", "Runter von mein Beet!", "zwerg"),
    ("gartenzwerg", "IDLE", "gartenzaun", "Do is mei Gartenzaun!", "Do is mei Gartenzaun!", "zwerg"),
    ("gartenzwerg", "DEATH", "tuscht", "Obacht, gleich tuscht's!", "Obacht, gleich tuschts!", "zwerg"),
    ("gartenzwerg", "DEATH", "bumm", "Bumm!", "Bumm!", "zwerg"),
    ("kontrolleur", "ARRIVE", "gesellschaft", "Heit is gschlossene Gesellschaft!", "Heit is gschlossene Gesellschaft!",
     "kontrolleur"),
    ("kontrolleur", "IDLE", "stempel", "Ohne Stempel ka Eintritt!", "Ohne Stempel ka Eintritt!", "kontrolleur"),
    ("kontrolleur", "IDLE", "ausweis", "Ausweis, bitte.", "Ausweis, bitte.", "kontrolleur"),
    ("kontrolleur", "DEATH", "nachspiel", "Des hat a Nachspiel …", "Des hat a Nachspiel.", "kontrolleur"),
    ("kontrolleur", "CRUSHED", "amtshandlung", "Behinderung einer Amtshandlung!", "Behinderung einer Amtshandlung!",
     "kontrolleur"),
    ("wuehlmaus", "IDLE", "rasen", "Mei Rasen!", "Mei Rasen!", "wuehlmaus"),
    ("wuehlmaus", "IDLE", "kuckuck", "Kuckuck!", "Kuckuck!", "wuehlmaus"),
    ("wuehlmaus", "DEATH", "loch", "Zruck ins Loch …", "Zruck ins Loch.", "wuehlmaus"),
    ("dackel", "IDLE", "wuff", "Wuff!", "Wuff!", "dackel"),
    ("dackel", "IDLE", "grr", "Grrr … wuff!", "Grrrr. Wuff!", "dackel"),
    ("taube", "IDLE", "gurr", "Gurr.", "Gurrr.", "taube"),
    ("taube", "EAT", "gurr_gurr", "Gurr, gurr!", "Gurrr, gurrr!", "taube"),
    ("wildschwein", "IDLE", "grunz", "Grunz!", "Grunz!", "wildschwein"),
    ("wildschwein", "EAT", "grunz", "Grunz!", "Grunz!", "wildschwein"),
    ("oberkrampus", "ARRIVE", "brav", "Wer war heit ned brav?", "Wer war heit ned brav?", "oberkrampus"),
    ("oberkrampus", "ATTACK", "sackl", "In mei Sackl mit dir!", "In mei Sackl mit dir!", "oberkrampus"),
    ("oberkrampus", "ATTACK", "ruatn", "Glei gibt's de Ruatn!", "Glei gibts de Ruatn!", "oberkrampus"),
    ("oberkrampus", "HALF", "buessn", "Des wirst ma büßn!", "Des wirst ma büßn!", "oberkrampus"),
    ("oberkrampus", "BEATEN", "joahr", "I kimm wieder … nächsts Joahr!", "I kimm wieder. Nächsts Joahr!", "oberkrampus"),
    ("hofrat", "ARRIVE", "zustaendig", "Sie san ned zuständig.", "Sie san ned zuständig.", "hofrat"),
    ("hofrat", "ATTACK", "abgelehnt", "Abgelehnt!", "Abgelehnt!", "hofrat"),
    ("hofrat", "ATTACK", "anstellen", "Hinten anstellen, bitte!", "Hinten anstellen, bitte!", "hofrat"),
    ("hofrat", "ATTACK", "dienstweg", "Des geht nur übern Dienstweg.", "Des geht nur übern Dienstweg.", "hofrat"),
    ("hofrat", "HALF", "beschwerde", "Des is a Dienstaufsichtsbeschwerde wert!", "Des is a Dienstaufsichtsbeschwerde wert!",
     "hofrat"),
    ("hofrat", "BEATEN", "instanz", "Des geht an die nächste Instanz …", "Des geht an die nächste Instanz.", "hofrat"),
    ("riesen_wirt", "ARRIVE", "sperrstund", "Sperrstund'! Zahln, bitte!", "Sperrstund! Zahln, bitte!", "wirt"),
    ("riesen_wirt", "ARRIVE", "ham", "Und jetzt olle ham!", "Und jetzt olle ham!", "wirt"),
    ("geist", "IDLE", "stammplatz", "Mei Stammplatzl …", "Mei Stammplatzl.", "geist"),
    ("geist", "IDLE", "kruegerl", "Oa Krügerl geht no!", "Oa Krügerl geht no!", "geist"),
    ("geist", "IDLE", "ham", "Wer geht'n do scho ham?", "Wer gehtn do scho ham?", "geist"),
    ("geist", "DEATH", "morgen", "I kumm morgen wieder …", "I kumm morgen wieder.", "geist"),
    ("geist_grantig", "IDLE", "platz", "Wer sitzt auf mein Platz?!", "Wer sitzt auf mein Platz?", "geist_grantig"),
    ("geist_grantig", "IDLE", "sperrstund", "Sperrstund' gibt's ned!", "Sperrstund gibts ned!", "geist_grantig"),
    ("geist_grantig", "DEATH", "zahln", "Zahln tu i nächste Wochn …", "Zahln tu i nächste Wochn.", "geist_grantig"),
    ("weinbergschnecke", "IDLE", "hudln", "Nur ned hudln.", "Nur ned hudln.", "schnecke"),
    ("weinbergschnecke", "IDLE", "zeit", "I hob Zeit. Vü Zeit.", "I hob Zeit. Vü Zeit.", "schnecke"),
    ("weinbergschnecke", "DEATH", "haeusl", "Mei Häusl …", "Mei Häusl.", "schnecke"),
    ("star", "IDLE", "vue", "Mia san vü mehr!", "Mia san vü mehr!", "star"),
    ("star", "EAT", "broesel", "Brösel! Brösel!", "Brösel! Brösel!", "star"),
    ("wespe", "IDLE", "suess", "Is des wos Süßes?", "Is des wos Süßes?", "wespe"),
    ("wespe", "EAT", "marille", "Mmh, Marille!", "Mmh, Marille!", "wespe"),
    ("wespe", "DEATH", "bsss", "Bsss …", "Bsssss.", "wespe"),
    ("sturm", "ARRIVE", "johrgang", "Heuer is a guater Johrgang!", "Heuer is a guater Johrgang!", "sturm"),
    ("sturm", "ATTACK", "lustig", "Jetzt wird's lustig!", "Jetzt wirds lustig!", "sturm"),
    ("sturm", "ATTACK", "drahn", "Olle a Runde drahn!", "Olle a Runde drahn!", "sturm"),
    ("sturm", "HALF", "trueb", "I bin no ganz trüb!", "I bin no ganz trüb!", "sturm"),
    ("sturm", "BEATEN", "vergoren", "I bin … vergoren …", "I bin. Vergoren.", "sturm"),
    ("hausmeisterin", "ARRIVE", "hausordnung", "Hausordnung, Paragraph eins: Ruhe im Hof!", "Hausordnung, Paragraf eins. Ruhe im Hof!", "hausmeisterin"),
    ("hausmeisterin", "ATTACK", "zammkehrn", "Do wird jetzt zammkehrt!", "Do wird jetzt zammkehrt!", "hausmeisterin"),
    ("hausmeisterin", "ATTACK", "stiagn", "Ned auf die frisch gwischte Stiagn!", "Ned auf die frisch gwischte Stiagn!", "hausmeisterin"),
    ("hausmeisterin", "ATTACK", "zehne", "Um zehne wird zuagsperrt!", "Um zehne wird zuagsperrt!", "hausmeisterin"),
    ("hausmeisterin", "HALF", "hausverwaltung", "I sog's da Hausverwaltung!", "I sogs da Hausverwaltung!", "hausmeisterin"),
    ("hausmeisterin", "BEATEN", "mist", "Und wer trogt jetzt in Mist owe …", "Und wer trogt jetzt in Mist owe.", "hausmeisterin"),
]


def sound_id(enemy: str, line: str) -> str:
    return "voice_%s_%s" % (enemy, line)


def build(only) -> None:
    out = ROOT / "assets" / "audio" / "sfx"
    done = set()
    total = 0
    for enemy, _moment, line, _shown, spoken, voice in LINES:
        name = sound_id(enemy, line)
        if name in done or (only and name not in only):
            continue
        done.add(name)
        path = out / (name + ".ogg")
        seconds = write(path, name, FILTERS[voice], spoken)
        total += path.stat().st_size
        print("%-40s %5.2f s %6.1f KB" % (path.name, seconds, path.stat().st_size / 1024))
    print("%d voices, %.2f MB" % (len(done), total / 1024 / 1024))


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
        build({a for a in sys.argv[1:] if not a.startswith("-")})
