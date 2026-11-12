"""Synthesize the game's sound effects and music loop into game/data/audio/*.wav.

Everything is generated from sine waves and filtered noise, so the files carry no third-party rights.
Run: pipeline/.venv/Scripts/python pipeline/tools/make_audio.py
"""

from pathlib import Path
import wave

import numpy as np

RATE = 22050
OUT = Path(__file__).resolve().parents[2] / "game" / "data" / "audio"
RNG = np.random.default_rng(7)


def t_axis(seconds: float) -> np.ndarray:
    return np.arange(int(seconds * RATE)) / RATE


def envelope(n: int, attack: float, release: float) -> np.ndarray:
    env = np.ones(n)
    a = max(1, int(attack * RATE))
    r = max(1, int(release * RATE))
    env[:a] = np.linspace(0.0, 1.0, a)
    env[-r:] *= np.linspace(1.0, 0.0, r)
    return env


def lowpass(x: np.ndarray, alpha: float) -> np.ndarray:
    """One-pole low-pass filter; smaller alpha means a lower cutoff."""
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc)
        y[i] = acc
    return y


def save(name: str, x: np.ndarray, peak: float = 0.8) -> None:
    x = x / max(1e-9, np.max(np.abs(x))) * peak
    data = (x * 32767).astype("<i2").tobytes()
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data)
    print(f"{name}.wav  {len(x) / RATE:.2f} s")


def click() -> np.ndarray:
    t = t_axis(0.06)
    return np.sin(2 * np.pi * 1400 * t) * np.exp(-t * 90)


def remove() -> np.ndarray:
    t = t_axis(0.09)
    f = 900 - 4000 * t
    return np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t * 45)


def tack() -> np.ndarray:
    """Sail swish: band-limited noise that rises and falls."""
    t = t_axis(0.7)
    noise = RNG.standard_normal(len(t))
    swish = lowpass(noise, 0.25) - lowpass(noise, 0.03)
    return swish * np.sin(np.pi * t / t[-1]) ** 2


def waypoint() -> np.ndarray:
    t = t_axis(0.6)
    out = np.zeros_like(t)
    for start, freq in [(0.0, 880.0), (0.12, 1318.5)]:
        tt = np.clip(t - start, 0, None)
        out += np.where(t >= start, np.sin(2 * np.pi * freq * tt) * np.exp(-tt * 7), 0.0)
    return out


def finish() -> np.ndarray:
    """Air horn: two long blasts of a buzzy chord."""
    t = t_axis(2.2)
    tone = sum(np.sign(np.sin(2 * np.pi * f * t)) * 0.3 for f in (233.1, 293.7, 349.2))
    tone = lowpass(tone, 0.2)
    gate = ((t < 0.9) | ((t > 1.15) & (t < 2.1))).astype(float)
    return tone * lowpass(gate, 0.004)


def ground() -> np.ndarray:
    """Hull on rock: low thud plus a grinding scrape."""
    t = t_axis(1.2)
    thud = np.sin(2 * np.pi * (70 - 25 * t) * t) * np.exp(-t * 6)
    scrape = lowpass(RNG.standard_normal(len(t)), 0.08) * np.exp(-t * 2.5) * 0.6
    return thud + scrape


def music() -> np.ndarray:
    """32 s ambient loop: four soft chords with slow swells over a quiet sea wash."""
    seconds = 32.0
    t = t_axis(seconds)
    chords = [  # A minor, F major, C major, G major
        (110.0, 220.0, 261.6, 329.6),
        (87.3, 174.6, 220.0, 261.6),
        (130.8, 196.0, 261.6, 329.6),
        (98.0, 196.0, 246.9, 293.7),
    ]
    out = np.zeros_like(t)
    span = seconds / len(chords)
    for i, chord in enumerate(chords):
        start = i * span
        local = t - start
        # Each chord swells in over 3 s and fades over 3 s past its slot, overlapping the next one.
        env = np.clip(local / 3.0, 0, 1) * np.clip((span + 3.0 - local) / 3.0, 0, 1)
        env[(local < 0) | (local > span + 3.0)] = 0.0
        for j, f in enumerate(chord):
            vib = 1.0 + 0.002 * np.sin(2 * np.pi * 0.2 * t + j)
            out += env * (np.sin(2 * np.pi * f * vib * t) + 0.25 * np.sin(4 * np.pi * f * t)) / (1 + j * 0.4)
    wash = lowpass(RNG.standard_normal(len(t)), 0.02)
    wash *= 0.5 + 0.5 * np.sin(2 * np.pi * t / 8.0) ** 2
    fade = int(0.05 * RATE)
    mix = out / np.max(np.abs(out)) + 0.25 * wash / np.max(np.abs(wash))
    mix[:fade] *= np.linspace(0, 1, fade)
    mix[-fade:] *= np.linspace(1, 0, fade)
    return mix


if __name__ == "__main__":
    save("click", click(), 0.5)
    save("remove", remove(), 0.5)
    save("tack", tack(), 0.6)
    save("waypoint", waypoint(), 0.6)
    save("finish", finish(), 0.7)
    save("ground", ground(), 0.8)
    save("music", music(), 0.5)
