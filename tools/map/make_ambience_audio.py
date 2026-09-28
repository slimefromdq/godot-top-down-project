"""Writes the placeholder ambience loops in audio/ambience/ (standard library only).

    python3 tools/map/make_ambience_audio.py

Each loop is 8 s, mono, 22050 Hz, and wraps seamlessly (the tail is
crossfaded into the head). Replace any file with real recordings of the same
name whenever you have them.
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
SECONDS = 8.0
N = int(RATE * SECONDS)
FADE = int(RATE * 0.5)
OUT = Path(__file__).resolve().parents[2] / "audio" / "ambience"


def lowpass(xs, k):
    y, out = 0.0, []
    for x in xs:
        y += k * (x - y)
        out.append(y)
    return out


def noise(rng, n):
    return [rng.uniform(-1, 1) for _ in range(n)]


def wind(rng, k=0.02, gust=0.25):
    base = lowpass(noise(rng, N + FADE), k)
    peak = max(abs(v) for v in base) or 1.0
    return [v / peak * (0.6 + gust * math.sin(2 * math.pi * i / (N + FADE) * 3)) for i, v in enumerate(base)]


def add_tone(buf, rng, start, dur, f0, f1, amp, decay=6.0):
    for j in range(int(dur * RATE)):
        i = start + j
        if i >= len(buf):
            break
        t = j / RATE
        f = f0 + (f1 - f0) * (t / dur)
        buf[i] += amp * math.sin(2 * math.pi * f * t) * math.exp(-decay * t) * min(1.0, t * 200)


def chirps(rng, buf, count, amp):
    for _ in range(count):
        start = rng.randrange(0, N)
        base = rng.uniform(2200, 3600)
        for k in range(rng.randint(2, 4)):
            add_tone(buf, rng, start + k * int(RATE * 0.09), 0.07, base, base * rng.uniform(1.1, 1.4), amp, 20)


def chimes(rng, buf, count, amp):
    scale = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5]
    for _ in range(count):
        f = rng.choice(scale)
        start = rng.randrange(0, N)
        add_tone(buf, rng, start, 2.5, f, f, amp, 1.6)
        add_tone(buf, rng, start, 2.5, f * 2.01, f * 2.01, amp * 0.3, 2.4)


def crickets(rng, buf, amp):
    f = 4200.0
    t = 0
    while t < N:
        for k in range(3):
            add_tone(buf, rng, t + k * int(RATE * 0.03), 0.02, f, f, amp, 60)
        t += int(RATE * rng.uniform(0.35, 0.6))


def burble(rng, buf, count, amp):
    for _ in range(count):
        f = rng.uniform(300, 900)
        add_tone(buf, rng, rng.randrange(0, N), 0.06, f, f * 1.8, amp, 35)


def finish(name, buf, gain):
    # Loop seam: crossfade the tail (past N) into the head.
    out = buf[:N]
    for j in range(FADE):
        w = j / FADE
        out[j] = out[j] * w + buf[N + j] * (1 - w) if N + j < len(buf) else out[j]
    peak = max(abs(v) for v in out) or 1.0
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(v / peak * gain * 32767)) for v in out))


def main():
    rng = random.Random(1234)
    size = N + FADE

    b = [v * 0.25 for v in wind(rng, 0.01)]
    chirps(rng, b, 7, 0.5)
    finish("glade", b, 0.6)

    finish("ridge", wind(rng, 0.03, 0.4), 0.7)

    b = [v * 0.15 for v in lowpass(noise(rng, size), 0.2)]
    crickets(rng, b, 0.35)
    finish("tangle", b, 0.5)

    b = [v * 0.15 for v in wind(rng, 0.008)]
    chimes(rng, b, 5, 0.4)
    finish("ruins", b, 0.6)

    b = [v * 0.3 for v in lowpass(noise(rng, size), 0.35)]
    burble(rng, b, 90, 0.5)
    finish("driftfield", b, 0.55)

    b = [v * 0.3 for v in wind(rng, 0.015)]
    chirps(rng, b, 3, 0.35)
    finish("orchard", b, 0.55)


if __name__ == "__main__":
    main()
