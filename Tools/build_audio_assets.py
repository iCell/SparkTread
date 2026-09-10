#!/usr/bin/env python3
"""Deterministic 8-bit style SFX synthesis for SparkTread (M3 provisional
audio). Reference: the original game ships game SFX and win/loss stingers
only — no built-in music — so this generates exactly that set.

Pure stdlib (wave/struct/math): square + triangle voices and an NES-style
15-bit LFSR noise channel, fixed seeds, so re-running the script reproduces
byte-identical WAVs. Output: Sources/AppleAdapters/Resources/Audio/*.wav
(22050 Hz, mono, 16-bit).

Run: python3 Tools/build_audio_assets.py
"""
import contextlib
import hashlib
import json
import math
import os
import random
import struct
import wave

OUTPUT_RATE = 22050
# AUDITION HYPOTHESIS (ADR-0011): the reference appears to render its
# samples near 8.36 kHz — two mirror pairs measured in the gameplay
# recording sum to 8377 and 8355 Hz (3058 ↔ 5319, 2433 ↔ 5922). Voices in
# the "reference-derived" block are generated at this rate and upsampled by
# zero-order hold so a similar aliased sheen appears. The source's true
# rate, bit depth and reconstruction filter are not established; the
# measurements are Claude's (2026-09-10, docs/CURRENT_REVIEW.md) and the
# research files were lost with a machine restart the same day.
NATIVE_RATE = 8363
RATE = OUTPUT_RATE  # generators read this at call time; see native()
OUT = os.environ.get("SPARKTREAD_AUDIO_OUT") or os.path.join(
    os.path.dirname(__file__), "..", "Sources", "AppleAdapters", "Resources", "Audio")
# Durable inventory (R15-09): every generated file with its hash, length and
# attribution status, plus the generator's own hash, so a generator edit
# that was not regenerated is caught by Scripts/check-audio.sh.
MANIFEST = os.environ.get("SPARKTREAD_AUDIO_MANIFEST") or os.path.join(
    os.path.dirname(__file__), "audio_manifest.json")

# Attribution per voice (ADR-0011): confirmed = onset matched to an on-screen
# event in the reference recording; uncertain = the most plausible pairing,
# unconfirmed; derived = a variant built from measured material; invented =
# no reference at all; provisional = the 2026-09-09 synthesized set, not
# reference-derived. Shipping review (audition + provenance/rights) is
# pending for the whole set.
# Per-cue inspiration provenance for "inspired" voices: the second
# reference the composition is modelled on, without any of its audio.
INSPIRATION = {
    "sfx_stage_card": {
        "modelled_on": "NES Battle City (Namco, 1985) stage-start jingle",
        "reference": "https://www.youtube.com/watch?v=_vgaq3LmVak at 2.63-7.2 s (Tools/reference_measure/README.md, second reference)",
        "relationship": "original composition following the reference's direction: same key/mode (C minor), tempo (~103 bpm), rhythmic skeleton, register, instrumentation and length; its own note sequences and contours; no note run of the reference reproduced; no audio of the reference used (owner's choice 2026-09-10 after declining a near-copy)",
        "rights_note": "independence of every musical element is for the pending rights review, not asserted here",
    },
}

ATTRIBUTION = {
    "sfx_stage_card": "inspired",
    "sfx_base_destroyed": "derived", "sfx_pickup_spawn": "derived", "sfx_deflect": "derived",
    "sfx_hit_brick": "derived", "sfx_tally_tick": "derived", "sfx_stage_lose": "invented",
}
SOURCE_NOTE = ("measurements of the public reference gameplay recording BV14b411K7bv, "
               "2026-09-10; procedure in Tools/reference_measure/")
_written = []
# Names owned by Tools/extract_reference_audio.py (manifest attribution
# "excerpt"): PROTECTED before any file is written (R25-03), not merely
# refused at manifest time after an overwrite.
PROTECTED = set()


def load_protected():
    if not os.path.exists(MANIFEST):
        return set()
    with open(MANIFEST) as f:
        return {name for name, entry in json.load(f).get("files", {}).items()
                if entry.get("attribution") == "excerpt"}


# ---------------------------------------------------------------- voices

def square(freqs, duty=0.5):
    """freqs: per-sample frequency list. Phase-continuous square wave."""
    out, phase = [], 0.0
    for f in freqs:
        phase = (phase + f / RATE) % 1.0
        out.append(1.0 if phase < duty else -1.0)
    return out


def triangle(freqs):
    out, phase = [], 0.0
    for f in freqs:
        phase = (phase + f / RATE) % 1.0
        out.append(4.0 * abs(phase - 0.5) - 1.0)
    return out


class LFSR:
    """NES-style 15-bit noise. Deterministic per seed."""

    def __init__(self, seed=0x4A55):
        self.reg = seed & 0x7FFF or 1

    def next(self):
        bit = (self.reg ^ (self.reg >> 1)) & 1
        self.reg = (self.reg >> 1) | (bit << 14)
        return 1.0 if self.reg & 1 else -1.0


def noise(n, rate_hz=11025, seed=0x4A55):
    """Sample-and-hold LFSR noise clocked at rate_hz."""
    gen, out, hold, acc = LFSR(seed), [], 0.0, 1.0
    step = rate_hz / RATE
    for _ in range(n):
        acc += step
        while acc >= 1.0:
            hold = gen.next()
            acc -= 1.0
        out.append(hold)
    return out


def noise_sweep(n, start_hz, end_hz, seed=0x4A55):
    gen, out, hold, acc = LFSR(seed), [], 0.0, 1.0
    for i in range(n):
        rate = start_hz + (end_hz - start_hz) * i / max(1, n - 1)
        acc += rate / RATE
        while acc >= 1.0:
            hold = gen.next()
            acc -= 1.0
        out.append(hold)
    return out


# ---------------------------------------------------------------- helpers

def samples(ms):
    return int(RATE * ms / 1000)


@contextlib.contextmanager
def native():
    """Generate inside this block at NATIVE_RATE; pair with write_native()."""
    global RATE
    saved, RATE = RATE, NATIVE_RATE
    try:
        yield
    finally:
        RATE = saved


def zoh(sig, src_rate, dst_rate):
    """Zero-order-hold resample (sample repeat): images at k*src_rate ± f
    survive, which is the point."""
    n = int(len(sig) * dst_rate / src_rate)
    last = len(sig) - 1
    return [sig[min(last, (i * src_rate) // dst_rate)] for i in range(n)]


def expo_sweep(start, end, n):
    """Exponential frequency glide start→end (constant rate in octaves/s)."""
    ratio = end / start
    return [start * ratio ** (i / max(1, n - 1)) for i in range(n)]


def env_db(n, points):
    """Piecewise-linear envelope in dB over time: points = [(ms, dB), ...],
    linear gain out. Matches measured 20 ms RMS tracks directly."""
    out = []
    for i in range(n):
        t = i * 1000.0 / RATE
        if t <= points[0][0]:
            db = points[0][1]
        elif t >= points[-1][0]:
            db = points[-1][1]
        else:
            for (t0, d0), (t1, d1) in zip(points, points[1:]):
                if t0 <= t <= t1:
                    db = d0 + (d1 - d0) * (t - t0) / max(1e-9, t1 - t0)
                    break
        out.append(10 ** (db / 20))
    return out


def lowpass(sig, cutoff, passes=1):
    """One-pole lowpass, `passes` times (6 dB/oct per pass)."""
    out = sig
    a = math.exp(-2 * math.pi * cutoff / RATE)
    for _ in range(passes):
        y, res = 0.0, []
        for s in out:
            y = a * y + (1 - a) * s
            res.append(y)
        out = res
    return out


def dc_block(sig, cutoff=20.0):
    """One-pole DC blocker (highpass at `cutoff`): removes the offset a
    gliding pulse accumulates without touching its audible band."""
    a = math.exp(-2 * math.pi * cutoff / RATE)
    out, x1, y1 = [], 0.0, 0.0
    for x in sig:
        y1 = x - x1 + a * y1
        x1 = x
        out.append(y1)
    return out


def bandpass(sig, center, q):
    """Biquad bandpass (constant skirt gain)."""
    w0 = 2 * math.pi * center / RATE
    alpha = math.sin(w0) / (2 * q)
    a0 = 1 + alpha
    b0, b2 = alpha / a0, -alpha / a0
    a1, a2 = -2 * math.cos(w0) / a0, (1 - alpha) / a0
    x1 = x2 = y1 = y2 = 0.0
    out = []
    for x in sig:
        y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, x, y1, y
        out.append(y)
    return out


def sweep(start, end, n, curve=1.0):
    """Frequency ramp start→end over n samples (curve>1 = fast early drop)."""
    return [start + (end - start) * ((i / max(1, n - 1)) ** curve) for i in range(n)]


def flat(freq, n):
    return [freq] * n


def env_decay(n, attack_ms=2, power=2.5):
    a = samples(attack_ms)
    out = []
    for i in range(n):
        if i < a:
            out.append(i / max(1, a))
        else:
            t = (i - a) / max(1, n - a)
            out.append((1.0 - t) ** power)
    return out


def env_hold(n, attack_ms=2, release_frac=0.25):
    a, r = samples(attack_ms), int(n * release_frac)
    out = []
    for i in range(n):
        if i < a:
            out.append(i / max(1, a))
        elif i >= n - r:
            out.append((n - i) / max(1, r))
        else:
            out.append(1.0)
    return out


def mix(*layers):
    n = max(len(sig) for sig, _ in layers)
    out = [0.0] * n
    for sig, gain in layers:
        for i, s in enumerate(sig):
            out[i] += s * gain
    return out


def apply(sig, env):
    return [s * e for s, e in zip(sig, env)]


def concat(*parts):
    out = []
    for p in parts:
        out += p
    return out


def silence(ms):
    return [0.0] * samples(ms)


def write(name, sig, peak=0.72):
    """Writes a signal generated at OUTPUT_RATE. Refuses a protected name
    BEFORE touching the file."""
    if name + ".wav" in PROTECTED:
        raise SystemExit(f"{name}.wav is a reference excerpt owned by the extractor: not generated")
    top = max(1e-9, max(abs(s) for s in sig))
    scale = peak / top
    frames = b"".join(
        struct.pack("<h", max(-32767, min(32767, int(s * scale * 32767))))
        for s in sig)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(OUTPUT_RATE)
        f.writeframes(frames)
    with open(path, "rb") as f:
        digest = hashlib.sha256(f.read()).hexdigest()
    _written.append((name, len(sig) / OUTPUT_RATE * 1000, digest))
    print(f"{name}.wav  {len(sig) / OUTPUT_RATE * 1000:.0f} ms")


def write_manifest():
    with open(os.path.abspath(__file__), "rb") as f:
        generator = hashlib.sha256(f.read()).hexdigest()
    entries = {}
    # Excerpt files are owned by Tools/extract_reference_audio.py; their
    # entries and the extractor's own record survive a regeneration untouched.
    extractor_record = {}
    if os.path.exists(MANIFEST):
        with open(MANIFEST) as f:
            previous = json.load(f)
        for name, entry in previous.get("files", {}).items():
            if entry.get("attribution") == "excerpt":
                entries[name] = entry
        for key in ("extractor", "extractor_sha256", "rights_review"):
            if key in previous:
                extractor_record[key] = previous[key]
    for name, ms, digest in sorted(_written):
        if entries.get(name + ".wav", {}).get("attribution") == "excerpt":
            raise SystemExit(f"{name} is a reference excerpt: not generated")
        entries[name + ".wav"] = {
            "sha256": digest,
            "milliseconds": round(ms),
            "attribution": ATTRIBUTION.get(name, "provisional"),
        }
        if name in INSPIRATION:
            entries[name + ".wav"]["inspiration"] = INSPIRATION[name]
    manifest = {
        "generator": "Tools/build_audio_assets.py",
        "generator_sha256": generator,
        "output_rate_hz": OUTPUT_RATE,
        "native_rate_hz": NATIVE_RATE,
        "source": SOURCE_NOTE,
        "creative_decision": "owner, 2026-09-10: the game's sounds are to be the original 决战坦克 sounds; excerpts of the public recording are used wherever it holds an isolated instance (attribution 'excerpt'); the rest is synthesized and provisional (ADR-0011, accepted by the owner 2026-09-10)",
        "rights_review": extractor_record.get("rights_review", "owner decision 2026-09-10 (recorded): the owner reviewed and accepts the use of the recording excerpts, the synthesized voices and the original jingle in the product; no third-party licence is held — the decision and its responsibility are the owner's (ASSET_PRODUCTION_MANIFEST.md)"),
        "files": dict(sorted(entries.items())),
    }
    for key in ("extractor", "extractor_sha256"):
        if key in extractor_record:
            manifest[key] = extractor_record[key]
    with open(MANIFEST, "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")
    print(f"manifest: {os.path.normpath(MANIFEST)} ({len(entries)} files)")


def write_native(name, sig, peak=0.72):
    """Writes a signal generated inside native(): ZOH-upsampled to OUTPUT_RATE."""
    write(name, zoh(sig, NATIVE_RATE, OUTPUT_RATE), peak)


def note(freq, ms, duty=0.5, attack_ms=2, release_frac=0.3, gain=1.0):
    n = samples(ms)
    return [s * gain for s in apply(square(flat(freq, n), duty),
                                    env_hold(n, attack_ms, release_frac))]


def crackle_bed(n, rng, pops, base_gain):
    """Fire crackle: a low steady noise bed plus short random pop bursts.
    Deterministic via the caller's seeded rng."""
    bed = [v * base_gain for v in noise(n, 4200, 0x77)]
    for _ in range(pops):
        start = rng.randrange(0, max(1, n - samples(24)))
        length = samples(rng.uniform(6, 22))
        gain = rng.uniform(0.45, 1.0)
        burst = noise(length, 9500, rng.randrange(1, 0x7FFF))
        env = env_decay(length, 1, 3.0)
        for i in range(length):
            if start + i < n:
                bed[start + i] += burst[i] * env[i] * gain
    return bed


# ---------------------------------------------------------------- sounds

def build():


    n = samples(35)
    write("sfx_dry_fire", apply(noise(n, 5500, 0x11), env_decay(n, 1, 4)), peak=0.25)


    # Missile launch: ignition crack, then a receding exhaust roar over a
    # low rumble — no melodic sweep (owner: it must sound serious).
    n = samples(380)
    ign = samples(45)
    write("sfx_fire_ap",
          mix((apply(noise(ign, 11000, 0xC7), env_decay(ign, 1, 2.0)), 0.9),
              (apply(noise_sweep(n, 7200, 1600, 0x9E1), env_hold(n, 30, 0.6)), 1.0),
              (apply(triangle(sweep(78, 36, n, 1.2)), env_hold(n, 25, 0.55)), 0.6)),
          peak=0.62)

    n = samples(210)
    write("sfx_fire_explosion",
          mix((apply(square(sweep(160, 65, n, 1.5), 0.5), env_decay(n, 3, 2.2)), 1.0),
              (apply(noise_sweep(n, 5000, 1500, 0xD9), env_decay(n, 2, 2.6)), 0.7)),
          peak=0.6)

    # Flame-thrower whoosh: rising air noise igniting into crackle + rumble.
    n = samples(380)
    rng = random.Random(0xF1AE)
    whoosh = apply(noise_sweep(n, 2200, 7500, 0xE3), env_hold(n, 40, 0.45))
    crackle = crackle_bed(n, rng, pops=9, base_gain=0.0)
    rumble = apply(triangle(sweep(70, 45, n)), env_hold(n, 30, 0.4))
    write("sfx_fire_flame",
          mix((whoosh, 0.9), (crackle, 0.8), (rumble, 0.5)), peak=0.55)

    # Seamless burning loop while flame patches are alive: constant-level
    # crackle bed, no global envelope, so the loop seam disappears.
    n = samples(1200)
    rng = random.Random(0xB0A9)
    write("sfx_flame_loop",
          mix((crackle_bed(n, rng, pops=30, base_gain=0.32), 1.0),
              (triangle(flat(52, n)), 0.14)),
          peak=0.4)


    n = samples(130)
    write("sfx_hit_tank",
          mix((apply(square(sweep(220, 110, n, 1.8), 0.5), env_decay(n, 2, 3)), 1.0),
              (apply(noise(n, 6000, 0x71), env_decay(n, 1, 4)), 0.6)),
          peak=0.6)


    n = samples(380)
    write("sfx_explosion_blast",
          mix((apply(noise_sweep(n, 8000, 2200, 0x6D), env_decay(n, 3, 2.4)), 1.0),
              (apply(square(sweep(130, 55, n, 1.5), 0.5), env_decay(n, 3, 2.4)), 0.6)),
          peak=0.8)

    # Base.
    alarm = concat(note(620, 110, 0.5, 1, 0.15), note(470, 110, 0.5, 1, 0.15),
                   note(620, 110, 0.5, 1, 0.15), note(470, 110, 0.5, 1, 0.15))
    boomn = samples(220)
    write("sfx_base_hit",
          mix((alarm, 0.8),
              (apply(noise(boomn, 7000, 0x91), env_decay(boomn, 2, 3)), 0.9)),
          peak=0.75)

    # Own-fire hit (ADR-0005 distinct cue): a dull, short thud with no
    # alarm figure, clearly unlike the enemy breakthrough. Provisional
    # placeholder until the reference-derived set lands.
    n = samples(200)
    write("sfx_base_own_hit",
          mix((apply(triangle(sweep(140, 60, n, 1.8)), env_decay(n, 2, 3.0)), 1.0),
              (apply(noise(n, 3000, 0xB7), env_decay(n, 1, 5)), 0.35)),
          peak=0.5)


    n = samples(320)
    write("sfx_base_shield_on",
          apply(square(sweep(300, 640, n, 0.8), 0.25), env_hold(n, 10, 0.35)), peak=0.5)


    click = samples(30)
    thunk = samples(110)
    write("sfx_mine_place",
          concat(apply(noise(click, 8000, 0xB5), env_decay(click, 1, 4)),
                 apply(square(sweep(150, 80, thunk, 1.5), 0.5), env_decay(thunk, 2, 3))),
          peak=0.5)

    n = samples(160)
    write("sfx_spawn_warp",
          apply(square(concat(sweep(1200, 600, n // 2, 1.0),
                              sweep(600, 1200, n - n // 2, 1.0)), 0.25),
                env_hold(n, 4, 0.3)), peak=0.35)

    # ---------------------------------------------- stage-start jingle
    # The owner's opening reference is the NES Battle City stage-start
    # jingle (Namco, 1985; 2.63–7.2 s of the video they pointed at: two
    # pulse voices, a triangle bass, a noise hit on every note, ≈0.146 s
    # sixteenths ≈ 103 bpm, 32 sixteenths ≈ 4.66 s, C minor, a march-like
    # fanfare that climbs and ends on repeated tonics). That music is
    # Namco's. The owner chose an ORIGINAL composition that follows the
    # reference's DIRECTION — same key and mode, tempo, rhythmic skeleton
    # (short-short-long motif twice, a zigzag phrase, a climb, a rest, a
    # repeated-tonic ending), register, instrumentation and length — with
    # its own note sequences and contours (a leaping triad motif where the
    # reference steps, a descending zigzag where it ascends, a turning
    # climb, a different closing figure). No note run of the reference is
    # reproduced and no audio of it is used. Attribution "inspired": a
    # style imitation, not a transcription; the rights review still judges
    # it.
    sixteenth_ms = 145.6  # ≈103 bpm
    def bc_pulse(freq, sixteenths, duty, gain=1.0, cut=0.92):
        n = int(RATE * sixteenth_ms * sixteenths / 1000)
        sounding = int(n * cut)
        env = [1.0] * sounding + [0.0] * (n - sounding)
        return [v * gain for v in apply(square(flat(freq, n), duty), env)]

    def bc_rest(sixteenths):
        return [0.0] * int(RATE * sixteenth_ms * sixteenths / 1000)

    def bc_voice(notes, duty, gain=1.0):
        return concat(*[bc_rest(d) if f == 0 else bc_pulse(f, d, duty, gain) for f, d in notes])

    G4, C5, D5, Eb5, F5, G5, Ab5, Bb5, C6 = 392.0, 523.25, 587.33, 622.25, 698.46, 783.99, 830.61, 932.33, 1046.5
    C3, G3, Eb3, F3, Bb3, C4, Ab3 = 130.81, 196.0, 155.56, 174.61, 233.08, 261.63, 207.65
    # Rhythm skeleton (sixteenths): [1 1 1][1 1 2] | [1 1 1][1 1 1 1 1] | [1 1 1 1 1 1] | [1 1 1 1] | rest 2 | [1 1 1 2]
    melody = [(G4, 1), (C5, 1), (Eb5, 1), (G4, 1), (C5, 1), (Eb5, 2),           # leaping minor-triad motif, twice
              (F5, 1), (Eb5, 1), (D5, 1), (Eb5, 1), (D5, 1), (C5, 1), (D5, 1), (Eb5, 1),   # descending zigzag
              (G5, 1), (F5, 1), (Eb5, 1), (F5, 1), (G5, 1), (Ab5, 1),             # turning climb
              (Bb5, 1), (Ab5, 1), (G5, 1), (Bb5, 1),                              # crest
              (0, 2), (C6, 1), (Bb5, 1), (C6, 1), (C6, 2)]                        # closing figure on the tonic
    bass = [(C3, 2), (G3, 2), (C3, 3), (F3, 2), (G3, 2), (Ab3, 2), (G3, 2),
            (Eb3, 2), (Bb3, 2), (F3, 2), (G3, 2), (Bb3, 2),
            (0, 2), (C4, 5)]
    total16 = sum(d for _, d in melody)
    assert total16 == 32 and sum(d for _, d in bass) == total16
    lead = bc_voice(melody, 0.25)
    double = bc_voice([(f / 2 if f else 0, d) for f, d in melody], 0.5, 0.45)   # NES-style octave doubling
    low = concat(*[bc_rest(d) if f == 0
                   else apply(triangle(flat(f, int(RATE * sixteenth_ms * d / 1000))),
                              env_hold(int(RATE * sixteenth_ms * d / 1000), 2, 0.08))
                   for f, d in bass])
    # A noise hit on every note onset (as heard in the reference), heavier on the beats.
    hit_n, beat_n = samples(60), samples(90)
    hit = apply(noise(hit_n, 11025, 0xB1), env_decay(hit_n, 1, 2.8))
    beat = apply(mix((noise(beat_n, 11025, 0xB2), 1.0), (triangle(sweep(140, 60, beat_n, 1.4)), 0.8)), env_decay(beat_n, 1, 2.2))
    drums = [0.0] * int(RATE * sixteenth_ms * total16 / 1000)
    pos = 0
    for f, d in melody:
        if f:
            at = int(RATE * sixteenth_ms * pos / 1000)
            src = beat if pos % 4 == 0 else hit
            for k, v in enumerate(src):
                if at + k < len(drums):
                    drums[at + k] += v * (1.0 if pos % 4 == 0 else 0.6)
        pos += d
    write("sfx_stage_card", mix((lead, 0.6), (double, 0.3), (low, 0.55), (drums, 0.45)), peak=0.8)

    # ------------------------------------------------ reference-derived set
    # CANDIDATE set (ADR-0011, accepted 2026-09-10): re-synthesised from Claude's
    # measurements of the gameplay recording (2026-09-10; numbers in
    # docs/CURRENT_REVIEW.md "Reference audio and transitions"). Sweep
    # endpoints, band shapes, envelope SHAPES and note lists follow the
    # measurements; the waveforms are ours. Every `write_native` peak-
    # normalises, so envelope points are relative shapes, not calibrated
    # dBFS. Provenance/rights review and the owner's audition are pending;
    # reproducibility is not acceptance. Attribution per voice:
    #   excerpt    — processed cut of the public recording, owned by
    #                Tools/extract_reference_audio.py (owner's creative
    #                decision 2026-09-10); NOT generated here
    #   inspired   — an original composition in the reference's idiom (the
    #                stage-start jingle), not a copy of any recording
    #   derived    — every other voice here: a variant built from measured
    #                material, not a measured event
    # Everything in this block is generated at NATIVE_RATE and ZOH-upsampled.
    with native():
        # Base destroyed (derived: the recording has no base loss): a hiss
        # into a steep rumble, twice, the second lower and later.
        n = samples(800)
        hiss_n = samples(200)
        hw = noise(hiss_n, NATIVE_RATE, 0x91)
        hiss = apply(mix((lowpass(hw, 3300), 0.8), (bandpass(hw, 2200, 1.0), 1.4)), env_hold(hiss_n, 5, 0.1))
        rumble = apply(lowpass(noise(n, NATIVE_RATE, 0x93), 350, 3),
                       env_db(n, [(0, -60), (180, -60), (220, -2), (500, -3), (800, -30)]))
        tone = apply(triangle(expo_sweep(200, 150, n)),
                     env_db(n, [(0, -60), (200, -60), (230, -6), (600, -8), (800, -36)]))
        heavy = mix((hiss, 1.0), (rumble, 1.0), (tone, 0.6))
        later = [0.0] * samples(350) + apply(lowpass(noise(n, NATIVE_RATE, 0x94), 220, 3),
                                             env_db(n, [(0, -60), (30, -2), (500, -4), (800, -40)]))
        write_native("sfx_base_destroyed", mix((heavy, 1.0), (later, 0.9)), peak=0.95)

        def jnote(freq, ms):
            # Triangle: the reference's notes carry only weak odd harmonics.
            return triangle(flat(freq, samples(ms)))
        # Pickup appears (derived variant, not a measured event): a rising
        # C6 G6 C7 G6 figure in the arpeggio's voice.
        appear = concat(jnote(1047, 60), jnote(1568, 60), jnote(2093, 60), jnote(1568, 120))
        write_native("sfx_pickup_spawn",
                     apply(appear, env_db(len(appear), [(0, -4), (200, -6), (300, -30)])), peak=0.5)

        n = samples(70)
        write_native("sfx_deflect",
                     apply(square(expo_sweep(2690, 2100, n), 0.5), env_decay(n, 1, 4)), peak=0.4)

        # Brick (derived): the first 120 ms of the enemy-explosion crunch.
        n = samples(120)
        write_native("sfx_hit_brick",
                     mix((apply(lowpass(noise(n, NATIVE_RATE, 0x2F), 900, 2), env_decay(n, 1, 3)), 1.0),
                         (apply(triangle(expo_sweep(240, 120, n)), env_decay(n, 1, 3)), 0.5)),
                     peak=0.6)

        # Results tally tick (derived from 3.14 kHz / 1.85 kHz blips heard
        # while the reference's kill table counts up).
        n = samples(45)
        write_native("sfx_tally_tick",
                     concat(apply(square(flat(3144, n), 0.5), env_hold(n, 1, 0.4)),
                            apply(square(flat(1852, n), 0.5), env_hold(n, 1, 0.5))), peak=0.45)

        # The 决战坦克 recording closes a stage with a DRUM RIFF the owner
        # described as "dong ×6, ×6, ×1, ×4"; the results asset is an excerpt
        # of that passage (Tools/extract_reference_audio.py). The stage card
        # is the original NES-style jingle above (a different reference).
        # What remains here is the synthesized `dong`/`riff` used only for
        # the invented loss stinger. Measured (hits.py, heuristic, 40–400 Hz onsets, window
        # 73.5–78.4 s): ≈37 hits in groups of 5–7, ≈0.12 s between hits,
        # ≈0.24 s from a group's last hit to the next group's first; one hit
        # (76.20–76.31 s): body ≈150–195 Hz, broadband stroke, ≈120 ms to
        # −10 dB (bands: 0–250 Hz 0 dB, 250–500 −6, ≈ −16 flat above 500 Hz).
        # The earlier "throbbing bed" was an interpretation error: band
        # averages and 20 ms envelopes discard the rhythm's structure.
        def dong(seed):
            # Body: a 30 % pulse gliding 195 -> 140 Hz (second harmonic
            # carries the measured -6 dB at 250-500 Hz); stroke: broadband
            # noise decaying with the body, so the spectrum stays a shelf
            # (≈ -16 dB above 500 Hz) instead of a dark thud.
            n = samples(150)
            body = apply(square(expo_sweep(195, 140, n), 0.3), env_db(n, [(0, 0), (30, -3), (120, -18), (150, -40)]))
            stroke = apply(lowpass(noise(n, NATIVE_RATE, seed), 5000, 1),
                           env_db(n, [(0, -3), (20, -6), (100, -24), (150, -45)]))
            return mix((body, 0.8), (stroke, 0.7))

        def riff(hit_ms=120, gap_ms=120, groups=(6, 6, 1, 4), tempo=1.0, seed=0xD0):
            """The 6-6-1-4 phrase on a `hit_ms` grid; `gap_ms` is the extra
            rest after a group, so the spacing from a group's LAST hit to the
            next group's FIRST hit is hit_ms + gap_ms (measured ≈0.24 s)."""
            hits = []
            t = 0
            for group in groups:
                for _ in range(group):
                    hits.append(t); t += int(hit_ms * tempo)
                t += int(gap_ms * tempo)
            total = samples(t + 200)
            out = [0.0] * total
            for k, start in enumerate(hits):
                d = dong(seed + k)
                offset = samples(start)
                for i, v in enumerate(d):
                    if offset + i < total: out[offset + i] += v
            return out

        # Stage lost (invented: the recording has no loss): the riff phrase
        # at three-quarter tempo over a falling 120 -> 45 Hz tone. (The
        # results passage itself is an excerpt of the recording; the stage
        # card is the original jingle above — neither is generated here.)
        lose = riff(tempo=1.35, seed=0xF0)
        n = len(lose)
        write_native("sfx_stage_lose",
                     mix((lose, 1.0),
                         (apply(triangle(expo_sweep(120, 45, n)), env_db(n, [(0, -14), (2500, -16), (n * 1000 // RATE, -45)])), 0.5)),
                     peak=0.7)


if __name__ == "__main__":
    PROTECTED = load_protected()
    build()
    write_manifest()
    print(f"\nWrote to {os.path.normpath(OUT)}")
