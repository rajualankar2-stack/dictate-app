#!/usr/bin/env python3
"""Synthesize the five premium start/stop sound packs (17-21) into Resources/Sounds.

Design rules: short (110-320 ms), soft attack (no click), tuned notes (start rises, stop falls and
resolves), a touch of room reverb, the same peak level in every pack so switching packs never jumps.
Run: python3 scripts/make_premium_sounds.py
"""
import wave
from pathlib import Path

import numpy as np
from scipy.signal import butter, sosfilt, fftconvolve

SR = 44100
PEAK = 0.42          # about -7.5 dBFS: audible, never loud
OUT = Path(__file__).resolve().parent.parent / "Resources" / "Sounds"
RNG = np.random.default_rng(17)


def t(dur): return np.arange(int(SR * dur)) / SR
def hz(note): return 440.0 * 2 ** ((note - 69) / 12)   # MIDI note -> Hz


def env(n, attack, decay_tau, release=0.012):
    x = np.arange(n) / SR
    e = np.minimum(1.0, x / max(attack, 1e-4)) * np.exp(-x / decay_tau)
    rel = int(SR * release)
    e[-rel:] *= np.linspace(1, 0, rel)
    return e


def lowpass(x, fc): return sosfilt(butter(2, fc, "low", fs=SR, output="sos"), x)
def highpass(x, fc): return sosfilt(butter(2, fc, "high", fs=SR, output="sos"), x)


def reverb(x, tail=0.28, mix=0.16):
    n = int(SR * tail)
    ir = RNG.standard_normal(n) * np.exp(-np.arange(n) / SR / (tail / 5))
    ir = lowpass(ir, 5000); ir[0] = 0
    wet = fftconvolve(x, ir / np.sqrt(np.sum(ir ** 2)))[: len(x) + n]
    dry = np.concatenate([x, np.zeros(len(wet) - len(x))])
    return dry * (1 - mix) + wet * mix


def place(buf, sig, at):
    i = int(SR * at)
    if i + len(sig) > len(buf): buf = np.concatenate([buf, np.zeros(i + len(sig) - len(buf))])
    buf[i:i + len(sig)] += sig
    return buf


def bell(freq, dur=0.5, tau=0.11, bright=1.0):
    """Glass/bell tone: a pure fundamental plus soft inharmonic partials."""
    x = t(dur); y = np.zeros_like(x)
    for ratio, amp, k in [(1, 1.0, 1.0), (2.76, 0.28, 2.2), (5.4, 0.10, 3.5)]:
        y += amp * bright ** (ratio > 1) * np.sin(2 * np.pi * freq * ratio * x) * np.exp(-x * k / tau * 0.4)
    return y * env(len(x), 0.004, tau * 2.4)


def marimba(freq, dur=0.4, tau=0.09):
    """Warm wooden mallet: FM with a quickly fading modulator."""
    x = t(dur)
    mod = 1.6 * np.exp(-x / 0.03) * np.sin(2 * np.pi * freq * 4.0 * x)
    return np.sin(2 * np.pi * freq * x + mod) * env(len(x), 0.003, tau)


def drop(f0, f1, dur=0.2, tau=0.06):
    """Water drop: a sine that glides from f0 to f1."""
    x = t(dur)
    f = f1 + (f0 - f1) * np.exp(-x / 0.045)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * env(len(x), 0.005, tau)


def halo(freqs, dur=0.34, swell=0.12):
    """Airy pad: detuned sines with a slow swell and a breath of filtered noise."""
    x = t(dur); y = np.zeros_like(x)
    for f in freqs:
        for d in (-0.004, 0.0, 0.004):
            y += np.sin(2 * np.pi * f * (1 + d) * x)
    y /= 3 * len(freqs)
    y += 0.05 * lowpass(highpass(RNG.standard_normal(len(x)), 2500), 7000)
    e = np.minimum(1, x / swell) * np.exp(-np.maximum(0, x - swell) / 0.09)
    e[-int(SR * 0.03):] *= np.linspace(1, 0, int(SR * 0.03))
    return y * e


def tick(freq=1900, dur=0.03):
    x = t(dur)
    return highpass(RNG.standard_normal(len(x)), 1500) * np.exp(-x / 0.004) * 0.35 + np.sin(2 * np.pi * freq * x) * np.exp(-x / 0.006) * 0.4


def thump(freq, dur=0.18, tau=0.05):
    x = t(dur)
    f = freq * (1 + 0.5 * np.exp(-x / 0.02))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(x), 0.003, tau)


def finish(sig, mix=0.16, tail=0.28, maxlen=0.4):
    sig = reverb(sig, tail, mix)
    sig = highpass(sig, 60)
    n = int(SR * 0.02); sig[:n] *= np.linspace(0, 1, n)
    end = np.max(np.nonzero(np.abs(sig) > 1e-4)[0]) + 1 if np.any(np.abs(sig) > 1e-4) else len(sig)
    sig = sig[:min(end, int(SR * maxlen))]; f = int(SR * 0.05); sig[-f:] *= np.linspace(1, 0, f)
    return sig * (PEAK / np.max(np.abs(sig)))


def write(pack, kind, sig):
    pcm = (np.clip(sig, -1, 1) * 32767).astype("<i2")
    with wave.open(str(OUT / f"sound_{pack}_{kind}.wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())


def build():
    z = lambda: np.zeros(0)
    # 17 Glass: two bell notes, a fifth apart. Start rises E6 -> B6, stop falls B6 -> E6 and settles.
    s = place(place(z(), bell(hz(88)), 0.0), bell(hz(95), tau=0.13), 0.075); write(17, "start", finish(s, 0.2, 0.3, 0.46))
    s = place(place(z(), bell(hz(95), tau=0.09), 0.0), bell(hz(88), tau=0.16), 0.07);  write(17, "stop", finish(s, 0.2, 0.3, 0.46))
    # 18 Velvet: warm marimba, major third. Start C5 -> E5, stop E5 -> C5.
    s = place(place(z(), marimba(hz(72)), 0.0), marimba(hz(76)), 0.085);  write(18, "start", finish(s, 0.14, 0.2, 0.34))
    s = place(place(z(), marimba(hz(76), tau=0.07), 0.0), marimba(hz(72), tau=0.12), 0.085); write(18, "stop", finish(s, 0.14, 0.2, 0.34))
    # 19 Droplet: one water drop. Start glides up, stop glides down and is softer.
    write(19, "start", finish(drop(520, 1250, 0.22), 0.16, 0.2, 0.3))
    write(19, "stop", finish(drop(1250, 480, 0.2) * 0.8, 0.16, 0.2, 0.28))
    # 20 Halo: airy swell on a major chord. Start swells up (A4, C#5, E5), stop is a short fall (E5, C#5, A4).
    write(20, "start", finish(halo([hz(69), hz(73), hz(76)], 0.36, 0.14), 0.2, 0.25, 0.44))
    write(20, "stop", finish(halo([hz(76), hz(73), hz(69)], 0.26, 0.04), 0.2, 0.25, 0.34))
    # 21 Pulse: haptic tick and a low thump, like a quality key press. Start high-ish, stop lower and shorter.
    s = place(place(z(), tick(2100), 0.0), thump(210), 0.004);  write(21, "start", finish(s, 0.08, 0.12, 0.2))
    s = place(place(z(), tick(1500), 0.0), thump(150, 0.15), 0.004);  write(21, "stop", finish(s, 0.08, 0.12, 0.18))


if __name__ == "__main__":
    build()
    for p in range(17, 22):
        for k in ("start", "stop"):
            with wave.open(str(OUT / f"sound_{p}_{k}.wav")) as w:
                print(f"sound_{p}_{k}: {w.getnframes() / SR * 1000:.0f} ms")
