"""
Generate WHEREDNGN sound effects.

Produces 16-bit mono 44.1kHz WAV samples with numpy then transcodes to
OGG Vorbis via ffmpeg (smaller files, WoW-supported). All cues are
synthesized from sine + filtered noise primitives so the results are
deterministic, royalty-free, and tonally consistent.

Output (in sounds/):
    card_play.ogg    short white-noise slap, ~110ms
    card_swish.ogg   high-to-low filtered noise sweep, ~180ms
    turn_ping.ogg    soft bell at A5 (880Hz), ~220ms
    contract.ogg     ascending two-note chime (C5 → G5), ~360ms
    trick_won.ogg    short major-triad arpeggio, ~360ms
    baloot.ogg       four-note ascending fanfare, ~720ms
"""
import os
import subprocess
import sys
import wave

import numpy as np

SR = 44100
DST = os.path.dirname(os.path.abspath(__file__))


# ---- Primitives ------------------------------------------------------

def silence(seconds):
    return np.zeros(int(seconds * SR), dtype=np.float32)


def sine(freq, seconds, amp=0.6, phase=0.0):
    t = np.arange(int(seconds * SR), dtype=np.float32) / SR
    return (amp * np.sin(2 * np.pi * freq * t + phase)).astype(np.float32)


def noise(seconds, amp=0.6):
    n = int(seconds * SR)
    return (amp * (np.random.RandomState(0xBA1007).rand(n).astype(np.float32) * 2 - 1))


def envelope(buf, attack_ms=5, decay_ms=80):
    """ADSR-ish: fast attack, exp decay."""
    n = len(buf)
    out = buf.copy()
    a = max(1, int(attack_ms * SR / 1000))
    d = max(1, int(decay_ms * SR / 1000))
    if a < n:
        out[:a] *= np.linspace(0, 1, a, dtype=np.float32)
    if d < n - a:
        # exponential tail from start of decay through end
        tail_n = n - a
        # exp falling from 1 to ~0 over decay window
        k = -np.log(1e-3) / d
        decay = np.exp(-k * np.arange(tail_n, dtype=np.float32))
        out[a:a + tail_n] *= decay
    return out


def lowpass_simple(buf, cutoff_hz):
    """Single-pole IIR low-pass (good enough for sweetening synthetic
    noise; we're not after audiophile filters)."""
    rc = 1.0 / (2 * np.pi * cutoff_hz)
    dt = 1.0 / SR
    alpha = dt / (rc + dt)
    out = np.zeros_like(buf)
    prev = 0.0
    for i, x in enumerate(buf):
        prev = prev + alpha * (x - prev)
        out[i] = prev
    return out


def normalize(buf, peak=0.85):
    m = np.max(np.abs(buf)) or 1.0
    return (buf * (peak / m)).astype(np.float32)


def write_wav(path, buf):
    pcm = np.clip(buf, -1.0, 1.0)
    pcm = (pcm * 32767).astype(np.int16)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(pcm.tobytes())


def to_ogg(wav_path, ogg_path, quality=4):
    """libvorbis -q 4 ≈ ~128 kbps; small files, no audible loss for
    short SFX. Re-encoding is intentional: we never ship the wav."""
    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-i", wav_path,
        "-c:a", "libvorbis", "-q:a", str(quality),
        ogg_path,
    ]
    subprocess.run(cmd, check=True)


# ---- Cues ------------------------------------------------------------

def make_card_play():
    """Quick noise burst — the slap of a card hitting felt."""
    n = noise(0.11, amp=0.9)
    n = lowpass_simple(n, 4500)
    n = envelope(n, attack_ms=2, decay_ms=90)
    return normalize(n, peak=0.7)


def make_card_swish():
    """Sweeping filter on noise — card sliding across the table."""
    n = noise(0.18, amp=0.9)
    # Two stages of low-pass with descending cutoff
    a = lowpass_simple(n, 7000)
    b = lowpass_simple(a, 1800)
    out = 0.6 * a + 0.4 * b
    out = envelope(out, attack_ms=10, decay_ms=140)
    return normalize(out, peak=0.65)


def bell(freq, seconds, amp=0.7):
    """Sine + a 2nd partial, percussive envelope."""
    fund = sine(freq, seconds, amp)
    over = sine(freq * 2.01, seconds, amp * 0.35)
    return envelope(fund + over, attack_ms=5, decay_ms=int(seconds * 1000 * 0.8))


def make_turn_ping():
    return normalize(bell(880, 0.22), peak=0.55)


def make_contract():
    """Two-note rising chime — C5 then G5."""
    a = bell(523.25, 0.20, amp=0.7)
    b = bell(783.99, 0.22, amp=0.7)
    out = np.concatenate([a, silence(0.02), b])
    return normalize(out, peak=0.65)


def make_trick_won():
    """Three-note major-triad arpeggio — C5 E5 G5."""
    notes = [(523.25, 0.10), (659.25, 0.10), (783.99, 0.18)]
    parts = []
    for f, d in notes:
        parts.append(bell(f, d, amp=0.7))
        parts.append(silence(0.015))
    return normalize(np.concatenate(parts), peak=0.65)


def make_baloot():
    """Four-note rising fanfare — C E G C2."""
    notes = [(523.25, 0.14), (659.25, 0.14), (783.99, 0.14), (1046.5, 0.30)]
    parts = []
    for f, d in notes:
        parts.append(bell(f, d, amp=0.8))
        parts.append(silence(0.02))
    out = np.concatenate(parts)
    return normalize(out, peak=0.75)


def main():
    cues = {
        "card_play":  make_card_play(),
        "card_swish": make_card_swish(),
        "turn_ping":  make_turn_ping(),
        "contract":   make_contract(),
        "trick_won":  make_trick_won(),
        "baloot":     make_baloot(),
    }
    for name, buf in cues.items():
        wav = os.path.join(DST, f"{name}.wav")
        ogg = os.path.join(DST, f"{name}.ogg")
        write_wav(wav, buf)
        to_ogg(wav, ogg)
        os.remove(wav)
        size = os.path.getsize(ogg)
        print(f"  {name:12s} {size:6d} bytes")
    print("done.")


if __name__ == "__main__":
    main()
