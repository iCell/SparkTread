#!/usr/bin/env python3
"""Deterministic 8-bit style SFX synthesis for SparkTread (M3 provisional
audio). Reference: the original game ships game SFX and win/loss stingers
only — no built-in music — so this generates exactly that set.

Pure stdlib (wave/struct/math): square + triangle voices and an NES-style
15-bit LFSR noise channel, fixed seeds, so re-running the script reproduces
byte-identical WAVs. One cue is not synthesized at all — the stage card is
re-sequenced out of the bundled results excerpt's own drum strokes (read
from the repository and checked against its committed hash).
Output: Sources/AppleAdapters/Resources/Audio/*.wav
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
# The committed locations, independent of the environment: a cue derived
# from a bundled excerpt reads the COMMITTED bytes and their committed hash,
# never the scratch directory a check writes into.
BUNDLED_AUDIO = os.path.join(
    os.path.dirname(__file__), "..", "Sources", "AppleAdapters", "Resources", "Audio")
COMMITTED_MANIFEST = os.path.join(os.path.dirname(__file__), "audio_manifest.json")
OUT = os.environ.get("SPARKTREAD_AUDIO_OUT") or BUNDLED_AUDIO
# Durable inventory (R15-09): every generated file with its hash, length and
# attribution status, plus the generator's own hash, so a generator edit
# that was not regenerated is caught by Scripts/check-audio.sh.
MANIFEST = os.environ.get("SPARKTREAD_AUDIO_MANIFEST") or COMMITTED_MANIFEST

# Attribution per voice (ADR-0011): confirmed = onset matched to an on-screen
# event in the reference recording; uncertain = the most plausible pairing,
# unconfirmed; derived = a variant built from measured material; invented =
# no reference at all; provisional = the 2026-09-09 synthesized set, not
# reference-derived. Shipping review (audition + provenance/rights) is
# pending for the whole set.
# Per-cue manifest note, in the same "note" field the excerpt entries carry:
# how a voice was built, where that is not obvious from its attribution.
NOTES = {
    "sfx_stage_card": "an original opening figure played on the stage-end excerpt's own pitched drum, re-sequenced from that excerpt and nothing else (owner 2026-10-01: the opening must carry a tune and be a set with the victory cue; the owner's reference for the FUNCTION was the Battle City NES start theme, whose melody is deliberately not copied or paraphrased — standing rule, and ADR-0011 records the owner settling the same question on 2026-09-10). The passage is grid-sliced at its measured ≈0.118 s sixteenth; the most cleanly pitched slice (autocorrelation of its tom band, 110.8 Hz) is resampled per note to play a twelve-note figure in C minor pentatonic across C3-E♭4 — the key taken from this excerpt's own faint harmonic stabs — over quarter-note kicks and off-beat ticks, with a tom run-up and a crash landing where the intro hands over to play. A room bed grain-built from the excerpt's band above 2 kHz keeps any step from being silent; the cue is levelled to the excerpt's own RMS and soft-saturated so twelve short pitched hits do not lose level to one crash. Same kit, room, tempo and level as the stage end by construction; no synthesized instrument anywhere in it. Three drum-only shapes (roll_hit, three_strikes, crescendo) were built from the same strokes and auditioned first — SHAPE in the generator selects",
}

ATTRIBUTION = {
    "sfx_stage_card": "derived",
    "sfx_base_destroyed": "derived", "sfx_pickup_spawn": "derived", "sfx_deflect": "derived",
    "sfx_hit_brick": "derived", "sfx_tally_tick": "derived",
}
SOURCE_NOTE = ("measurements of the public reference gameplay recording BV14b411K7bv, "
               "2026-09-10; procedure in Tools/reference_measure/")
_written = []
# Names owned by Tools/extract_reference_audio.py (manifest attribution
# "excerpt"): PROTECTED before any file is written (R25-03), not merely
# refused at manifest time after an overwrite.
PROTECTED = set()


# Attributions this generator must never produce or overwrite: an excerpt is
# owned by Tools/extract_reference_audio.py, and an "owner" asset is a file the
# owner supplied as-is (the stage card, 2026-10-01) which nothing here can
# reproduce. Both are verified by hash instead of by regeneration.
NOT_GENERATED = ("excerpt", "owner")


def load_protected():
    if not os.path.exists(MANIFEST):
        return set()
    with open(MANIFEST) as f:
        return {name for name, entry in json.load(f).get("files", {}).items()
                if entry.get("attribution") in NOT_GENERATED}


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





def saturate(sig, drive):
    """Soft tanh saturation, scaled so the loudest sample stays where it was.

    A crack-led recipe otherwise has to choose between its bite and its
    loudness: one transient sets the peak, the body sits 16 dB under it, and
    peak normalisation leaves the cue 4 dB quieter than the mix pass set it
    (ADR-0011 amendment 2026-10-01). Rounding that transient lifts the body
    against the peak instead of trading one for the other, and the harmonics
    it adds belong to the same 8363 Hz palette as everything else here.
    `drive` is in tanh units: ~1 is gentle, ~3 is firm."""
    top = max(1e-9, max(abs(s) for s in sig))
    knee = math.tanh(drive)
    return [math.tanh(drive * v / top) / knee * top for v in sig]


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
        raise SystemExit(f"{name}.wav is not this generator's to write "
                         f"(a reference excerpt, or an asset the owner supplied): not generated")
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
    # Files this generator does not produce — the extractor's excerpts and the
    # owner's own assets — keep their entries, and the extractor's record, from
    # the previous manifest untouched.
    extractor_record = {}
    if os.path.exists(MANIFEST):
        with open(MANIFEST) as f:
            previous = json.load(f)
        for name, entry in previous.get("files", {}).items():
            if entry.get("attribution") in NOT_GENERATED:
                entries[name] = entry
        for key in ("extractor", "extractor_sha256", "rights_review"):
            if key in previous:
                extractor_record[key] = previous[key]
    for name, ms, digest in sorted(_written):
        if entries.get(name + ".wav", {}).get("attribution") in NOT_GENERATED:
            raise SystemExit(f"{name} is not a generated cue (attribution "
                             f"{entries[name + '.wav']['attribution']}): refusing to claim it")
        entries[name + ".wav"] = {
            "sha256": digest,
            "milliseconds": round(ms),
            "attribution": ATTRIBUTION.get(name, "provisional"),
        }
        if name in NOTES:
            entries[name + ".wav"]["note"] = NOTES[name]
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


def write_native_rms(name, sig, target_dbfs, ceiling=0.9):
    """Writes a native-rate cue at a target LOUDNESS instead of a target peak.

    `write_native`'s `peak` is a shape control: it says nothing about how
    loud a cue lands next to the others, which is how three cues drifted
    into out-shouting the game (ADR-0011 amendment 2026-09-25 — a shield
    raise was louder than the player's own death). A cue whose recipe is
    reworked therefore declares the RMS the mix pass gave it, so a redesign
    cannot quietly re-level it. The cues not touched since that pass keep
    their measured `peak` constants. `ceiling` is voice headroom; a cap that
    binds is printed rather than silently accepted."""
    top, level = max(abs(s) for s in sig), rms(sig)
    peak = 10 ** (target_dbfs / 20.0) * top / max(1e-9, level)
    if peak > ceiling:
        print(f"  {name}: peak capped at {ceiling}, "
              f"{20 * math.log10(ceiling * level / top):.1f} dBFS RMS "
              f"instead of {target_dbfs}")
    write_native(name, sig, peak=min(ceiling, peak))



def fade_out(sig, ms):
    """Linear fade over the last `ms` of a signal already at OUTPUT_RATE."""
    out, r = list(sig), min(len(sig), samples(ms))
    for i in range(r):
        out[len(sig) - r + i] *= 1.0 - (i + 1) / r
    return out


def fade_in(sig, ms):
    """Linear fade over the first `ms` of a signal already at OUTPUT_RATE."""
    out, r = list(sig), min(len(sig), samples(ms))
    for i in range(r):
        out[i] *= (i + 1) / r
    return out


def rms(sig):
    """Root-mean-square level of a signal (0 for an empty one)."""
    return math.sqrt(sum(s * s for s in sig) / len(sig)) if sig else 0.0


def percentile(values, p):
    """Nearest-rank percentile: no interpolation and no third-party numerics,
    so a slice classification is exactly reproducible across machines."""
    ordered = sorted(values)
    rank = int(math.ceil(p / 100.0 * len(ordered))) - 1
    return ordered[max(0, min(len(ordered) - 1, rank))]


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


def sine(freqs):
    out, phase = [], 0.0
    for f in freqs:
        phase = (phase + f / RATE) % 1.0
        out.append(math.sin(2 * math.pi * phase))
    return out


def glide(start, end, glide_ms, n):
    """Exponential pitch drop start→end over glide_ms, then held (drum heads)."""
    g = min(n, samples(glide_ms))
    return expo_sweep(start, end, g) + [end] * (n - g)


def room(sig):
    """Small deterministic Schroeder room: four damped combs into two
    allpasses. Returns the wet signal only."""
    wet = [0.0] * len(sig)
    for ms, feedback in ((29.7, 0.74), (37.1, 0.72), (41.1, 0.70), (43.7, 0.68)):
        d = samples(ms)
        buf, damp, k = [0.0] * d, 0.0, 0
        for i, x in enumerate(sig):
            y = buf[k]
            damp = 0.55 * damp + 0.45 * y
            buf[k] = x + feedback * damp
            k = (k + 1) % d
            wet[i] += y * 0.25
    for ms, g in ((5.0, 0.7), (1.7, 0.7)):
        d = samples(ms)
        buf, k, out = [0.0] * d, 0, []
        for x in wet:
            y = -g * x + buf[k]
            buf[k] = x + g * y
            k = (k + 1) % d
            out.append(y)
        wet = out
    return wet


# ---------------------------------------------------------------- sounds

def build():

    # ------------------------------------------------ provisional set
    # Owner 2026-09-16: one style for everything that is synthesized. These
    # recipes are unchanged from the 2026-09-09 set (same frequencies,
    # envelope shapes, seeds, mix weights and peaks) but are now generated
    # inside native() and ZOH-upsampled like the reference-derived block
    # below, so they carry the same ≈8.36 kHz aliased sheen as the
    # recording's own voices instead of sounding cleanly 22 kHz next to
    # them. The mine cue is gone with the mechanic (R5/ADR-0018).
    with native():
        n = samples(35)
        write_native("sfx_dry_fire", apply(noise(n, 5500, 0x11), env_decay(n, 1, 4)), peak=0.25)

        # Missile launch: ignition crack, then a receding exhaust roar over a
        # low rumble — no melodic sweep (owner: it must sound serious).
        n = samples(380)
        ign = samples(45)
        write_native_rms("sfx_fire_ap",
                     mix((apply(noise(ign, 11000, 0xC7), env_decay(ign, 1, 2.0)), 0.9),
                         (apply(noise_sweep(n, 7200, 1600, 0x9E1), env_hold(n, 30, 0.6)), 1.0),
                         (apply(triangle(sweep(78, 36, n, 1.2)), env_hold(n, 25, 0.55)), 0.6)),
                     # 2026-10-01 review: at −10.1 dBFS RMS this launch was the
                     # second-loudest cue in the product, over a tank exploding
                     # (−12.4) and over the blast of the shell it does not even
                     # fire. Still the loudest launch, no longer louder than a
                     # destruction.
                     -12.8)

        # Demolition launch. Owner 2026-10-01: "有点闷，和别的音效感觉不太
        # 符合". Measured against the launch it plays beside (the reference's
        # own shot excerpt: almost nothing under 150 Hz, most of its energy
        # above 1 kHz), the old recipe was led by a 160→65 Hz square glide
        # and sat 9 dB heavier in the bass and 4 dB weaker on top — a
        # sub-bass boop among bright launches. Now the BITE leads: a
        # full-rate crack, the charge leaving over the whole cue, and a low
        # push that is short and clearly secondary, so the weapon still
        # feels heavy without owning the bottom of the mix.
        n = samples(210)
        crack, push = samples(40), samples(90)
        write_native_rms("sfx_fire_explosion",
                     saturate(mix((apply(bandpass(noise(crack, 11025, 0xD9), 2600, 0.9),
                                env_decay(crack, 1, 2.2)), 3.0),
                         (apply(noise_sweep(n, 4200, 1500, 0x5C), env_decay(n, 2, 2.4)), 0.75),
                         (apply(triangle(sweep(190, 110, push, 1.4)),
                                env_decay(push, 2, 2.4)), 0.40)), 1.6),
                     -14.8)

        # Flame-thrower whoosh: rising air noise igniting into crackle + rumble.
        n = samples(380)
        rng = random.Random(0xF1AE)
        whoosh = apply(noise_sweep(n, 2200, 7500, 0xE3), env_hold(n, 40, 0.45))
        crackle = crackle_bed(n, rng, pops=9, base_gain=0.0)
        rumble = apply(triangle(sweep(70, 45, n)), env_hold(n, 30, 0.4))
        write_native("sfx_fire_flame",
                     mix((whoosh, 0.9), (crackle, 0.8), (rumble, 0.5)), peak=0.55)

        # Seamless burning loop while flame patches are alive: constant-level
        # crackle bed, no global envelope, so the loop seam disappears. The
        # ZOH upsample keeps that: it emits a whole number of output samples
        # and the last one is the last native sample, so the seam is one
        # shortened hold inside an unpitched bed — no level step.
        n = samples(1200)
        rng = random.Random(0xB0A9)
        write_native("sfx_flame_loop",
                     mix((crackle_bed(n, rng, pops=30, base_gain=0.32), 1.0),
                         (triangle(flat(52, n)), 0.14)),
                     peak=0.4)

        n = samples(130)
        write_native("sfx_hit_tank",
                     mix((apply(square(sweep(220, 110, n, 1.8), 0.5), env_decay(n, 2, 3)), 1.0),
                         (apply(noise(n, 6000, 0x71), env_decay(n, 1, 4)), 0.6)),
                     peak=0.6)

        # The demolition shell's blast. Owner 2026-10-01: "也有点闷". The
        # reference's own explosions (`sfx_tank_explode`, `sfx_player_explode`)
        # centre their energy between 150 Hz and 1 kHz; the old recipe was a
        # noise sweep over a 130→55 Hz square glide and measured 3.4 dB THIN
        # through 400 Hz–1 kHz — the band that carries an explosion's body —
        # so it read as a dull "pff" with a boop under it. A bandpassed body
        # around 700 Hz now fills that band, a full-rate crack opens it, and
        # the low layer is a shorter thump at half gain. Kept clearly
        # shorter and tighter than the reference's own explosions so a shell
        # blast is never mistaken for a tank dying.
        n = samples(380)
        crack, thump, sub = samples(35), samples(240), samples(200)
        write_native_rms("sfx_explosion_blast",
                     saturate(mix((apply(noise(crack, 11025, 0x6D), env_decay(crack, 1, 2.0)), 1.0),
                         (apply(bandpass(noise(n, 8000, 0x6E), 700, 0.7),
                                env_decay(n, 2, 2.2)), 2.4),
                         (apply(noise_sweep(n, 5200, 1300, 0x6F), env_decay(n, 3, 2.6)), 0.35),
                         (apply(triangle(sweep(260, 90, thump, 1.5)),
                                env_decay(thump, 3, 2.4)), 0.70),
                         # The 260→90 Hz layer spends its time in 150-400 Hz,
                         # so the weight under 150 — which the reference's own
                         # explosions do carry — is its own shorter layer.
                         (apply(triangle(sweep(120, 62, sub, 1.2)),
                                env_decay(sub, 3, 2.2)), 0.60)), 2.4),
                     -12.3)

        # Base taken by the enemy (§12.4 gives it priority over every weapon
        # voice, and it is the loudest cue in the product). The two-tone
        # four-stroke alarm figure and its pitches are kept exactly — an
        # alternating two-tone alarm is the clearest "this is the emergency"
        # signal there is — but it measured −20.5 dB in the band under 150 Hz,
        # i.e. the loudest sound in the game had no body at all and would go
        # shrill on a phone speaker (2026-10-01 review). The notes now carry a
        # bandpassed edge instead of being bare squares, and the shell's own
        # impact arrives under the first stroke.
        alarm = concat(note(620, 110, 0.5, 1, 0.15), note(470, 110, 0.5, 1, 0.15),
                       note(620, 110, 0.5, 1, 0.15), note(470, 110, 0.5, 1, 0.15))
        edge = apply(bandpass(noise(len(alarm), 9000, 0xA4), 1900, 0.8),
                     env_db(len(alarm), [(0, -3), (110, -9), (440, -14)]))
        boomn, impact = samples(220), samples(220)
        write_native_rms("sfx_base_hit",
                         # The impact raises the crest factor past what 0.9 of
                         # headroom allows at this loudness, and this cue has to
                         # stay the most urgent in the game — above the player's
                         # own death at −10.2 — so the transient is rounded
                         # rather than the alarm made quieter.
                         saturate(mix((alarm, 0.80),
                             (edge, 0.55),
                             (apply(noise(boomn, 7000, 0x91), env_decay(boomn, 2, 3)), 0.9),
                             (apply(triangle(sweep(180, 70, impact, 1.4)),
                                    env_decay(impact, 2, 2.2)), 1.60)), 1.7),
                         -9.2)

        # Own-fire hit (ADR-0005 distinct cue): a dull, short thud with no
        # alarm figure, clearly unlike the enemy breakthrough. Provisional
        # placeholder until the reference-derived set lands.
        n = samples(200)
        write_native_rms("sfx_base_own_hit",
                     mix((apply(triangle(sweep(140, 60, n, 1.8)), env_decay(n, 2, 3.0)), 1.0),
                         (apply(noise(n, 3000, 0xB7), env_decay(n, 1, 5)), 0.35)),
                     # 2026-10-01 review: at −20.0 dBFS RMS this sat under every
                     # impact cue and barely over the dry-fire click, and
                     # "you just shot your own base" has to register. The
                     # timbre is untouched, so ADR-0005's separation holds.
                     -15.0)

        # Flag guard raised (§11.2) and base repaired. Owner 2026-10-01:
        # "觉得很滑稽，有点奇怪". The old cue was a 300→640 Hz square GLIDE
        # under a hold envelope, and the glide is exactly what read as
        # cartoonish. The event is the fort ring hardening to steel, so the
        # cue is now two metal plates locking into place — STRUCK, never
        # glided — the second a fifth above the first so the gesture still
        # reads as something good for the player, and a short ring that
        # settles instead of climbing. Each plate is a tone for its pitch
        # plus a bandpassed noise edge for the metal. The peak lands the
        # same −16 dBFS RMS as the 2026-09-25 mix pass set for this cue.
        def plate(freq, edge_hz, ms, seed):
            m = samples(ms)
            return mix((apply(triangle(flat(freq, m)), env_decay(m, 1, 3.0)), 1.0),
                       (apply(bandpass(noise(m, 9000, seed), edge_hz, 1.1),
                              env_decay(m, 1, 4.0)), 1.6),
                       # Two octaves down, so the strike has the weight of
                       # plate instead of the thinness of sheet metal; it
                       # tracks the pitch, so both strikes are the same metal.
                       (apply(triangle(flat(freq / 4, m)), env_decay(m, 1, 2.6)), 0.55))

        ring = samples(170)
        write_native_rms("sfx_base_shield_on",
                     saturate(mix((plate(440, 2400, 90, 0x3B), 1.0),
                         ([0.0] * samples(110) + plate(660, 3100, 110, 0x3C), 1.0),
                         ([0.0] * samples(150) + apply(triangle(flat(1320, ring)),
                                                       env_decay(ring, 2, 2.6)), 0.30)), 2.2),
                     -16.2)

        # Enemy wave appears, and the director's elite phase. The old cue
        # measured a crest factor of 1.0 dB — a constant-amplitude bare square
        # under a hold envelope, the same signature as the shield whoop the
        # owner called 滑稽, and the last one left in the set (2026-10-01
        # review). The gesture is kept (something arriving, down then up) but
        # it is now struck and decays: a rising materialise hiss, a blip that
        # falls away instead of being held, and a bandpassed tick marking the
        # arrival. Same loudness as the mix pass set.
        n, blip, tick = samples(160), samples(110), samples(45)
        write_native_rms("sfx_spawn_warp",
                         mix((apply(noise_sweep(n, 1500, 7000, 0x2D),
                                    env_hold(n, 8, 0.55)), 0.55),
                             (apply(square(concat(sweep(1200, 600, blip // 2, 1.0),
                                                  sweep(600, 1400, blip - blip // 2, 1.0)), 0.25),
                                    env_decay(blip, 4, 1.8)), 1.0),
                             ([0.0] * samples(115) + apply(bandpass(noise(tick, 9000, 0x2E), 2800, 1.0),
                                                           env_decay(tick, 1, 3.0)), 1.8)),
                         -16.4)

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
    #   derived    — every voice here: a variant built from measured
    #                material, not a measured event (the stage-start cue
    #                is derived too, but by re-sequencing the bundled
    #                excerpt's own strokes — see its own block above)
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
        # The band above 2.5 kHz measured −2.8 dB against −15.2 under 150 Hz:
        # the biggest explosion in the game was almost all hiss, where the
        # reference's own explosions carry real weight (−11.3/−6.2 for the
        # player's death). The hiss steps back, the rumble and tone come up,
        # and a sub layer carries the collapse (2026-10-01 review).
        sub_n = samples(500)
        weight = apply(triangle(sweep(90, 45, sub_n, 1.3)),
                       env_db(sub_n, [(0, -60), (150, -60), (200, -3), (500, -26)]))
        heavy = mix((hiss, 0.5), (rumble, 1.6), (tone, 0.8), (weight, 0.8))
        later = [0.0] * samples(350) + apply(lowpass(noise(n, NATIVE_RATE, 0x94), 220, 3),
                                             env_db(n, [(0, -60), (30, -2), (500, -4), (800, -40)]))
        write_native_rms("sfx_base_destroyed", mix((heavy, 1.0), (later, 0.9)), -12.6, ceiling=0.95)

        def jnote(freq, ms):
            # Triangle: the reference's notes carry only weak odd harmonics.
            return triangle(flat(freq, samples(ms)))
        # Pickup appears (derived variant, not a measured event): a rising
        # C6 G6 C7 G6 figure in the arpeggio's voice.
        appear = concat(jnote(1047, 60), jnote(1568, 60), jnote(2093, 60), jnote(1568, 120))
        # 2026-10-01 review: appearing was 3 dB LOUDER than collecting
        # (−13.2 against the reference jingle's −16.3), which puts the
        # announcement over the reward; it now sits under it.
        write_native_rms("sfx_pickup_spawn",
                         apply(appear, env_db(len(appear), [(0, -4), (200, -6), (300, -30)])),
                         -16.5)

        n = samples(70)
        write_native("sfx_deflect",
                     apply(square(expo_sweep(2690, 2100, n), 0.5), env_decay(n, 1, 4)), peak=0.4)

        # Brick (derived): the first 120 ms of the enemy-explosion crunch.
        # This is the most frequent impact in the game, so its character
        # carries further than its level. It measured −4.3 dB in the band
        # under 150 Hz — energy piled below the crack — which is the same
        # muddiness the owner heard in the explosion cues (2026-10-01 review).
        # Brick breaking is a dry clack, so the crack band leads and the low
        # thud is halved; it stays the quietest impact in the set.
        n = samples(120)
        write_native_rms("sfx_hit_brick",
                         mix((apply(bandpass(noise(n, NATIVE_RATE, 0x2F), 1400, 0.7),
                                    env_decay(n, 1, 3)), 2.2),
                             (apply(lowpass(noise(n, NATIVE_RATE, 0x30), 2200, 1),
                                    env_decay(n, 1, 3.4)), 0.7),
                             (apply(triangle(expo_sweep(240, 120, n)), env_decay(n, 1, 3)), 0.25)),
                         -19.3)

        # Results tally tick (derived from 3.14 kHz / 1.85 kHz blips heard
        # while the reference's kill table counts up).
        n = samples(45)
        write_native("sfx_tally_tick",
                     concat(apply(square(flat(3144, n), 0.5), env_hold(n, 1, 0.4)),
                            apply(square(flat(1852, n), 0.5), env_hold(n, 1, 0.5))), peak=0.15)

        # The 决战坦克 recording closes a stage with a DRUM RIFF the owner
        # described as "dong ×6, ×6, ×1, ×4"; the results asset is an excerpt
        # of that passage (Tools/extract_reference_audio.py), and since
        # 2026-09-16 the stage card is a new pattern re-sequenced from that
        # same excerpt's strokes.
        # What remains here is the analysis of the passage, kept because no
        # synthesized `dong`/`riff` survives it. Measured (hits.py, heuristic, 40–400 Hz onsets, window
        # 73.5–78.4 s): ≈37 hits in groups of 5–7, ≈0.12 s between hits,
        # ≈0.24 s from a group's last hit to the next group's first; one hit
        # (76.20–76.31 s): body ≈150–195 Hz, broadband stroke, ≈120 ms to
        # −10 dB (bands: 0–250 Hz 0 dB, 250–500 −6, ≈ −16 flat above 500 Hz).
        # The earlier "throbbing bed" was an interpretation error: band
        # averages and 20 ms envelopes discard the rhythm's structure.
        # Stage lost: no separate stinger — the owner (2026-09-10 evening)
        # wants the reference's results passage (the `sfx_stage_win`
        # excerpt) at every stage end; the invented falling variant and
        # the 6-6-1-4 riff helper it used were removed (the riff analysis
        # stays in Tools/reference_measure/README.md as history).


if __name__ == "__main__":
    PROTECTED = load_protected()
    build()
    write_manifest()
    print(f"\nWrote to {os.path.normpath(OUT)}")
