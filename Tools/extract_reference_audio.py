#!/usr/bin/env python3
"""Reference EXCERPTS (owner's creative decision 2026-09-10: "我要求音效是复刻原版的"
— the game's sounds are to be the original 决战坦克 sounds). What this
produces are processed excerpts of the public gameplay recording, not the
game's original asset files: the cleanest isolated instance of each sound
(silent 60 ms margins — except the two stage-transition excerpts, which
are cut out of a continuously sounding passage) is cut from the
reacquired reference WAV, mixed to mono, resampled to
22 050 Hz with a deterministic windowed-sinc polyphase filter, DC-removed,
edge-faded, peak-normalised and written as 16-bit WAV next to the
synthesized voices. Every file is recorded in Tools/audio_manifest.json
with attribution "excerpt", its source window, processing and hash, and
the extractor's own hash; Scripts/check-audio.sh verifies all of that
(re-extracting when the source WAV is available).

RIGHTS: the owner's creative instruction and, separately, the owner's
recorded review decision of 2026-09-10 (accepting the use of these
excerpts with no third-party licence held) are in the manifest
(ASSET_PRODUCTION_MANIFEST.md, audio/provenance sections). The agents
record the decision; they do not vet it.

Pure stdlib, deterministic: the same source file gives byte-identical
output. Source: format 30216 of BV14b411K7bv decoded to WAV (48 kHz, 2 ch,
sha256 below); never committed.

    SPARKTREAD_REFERENCE_WAV=/path/tank_reference.wav python3 Tools/extract_reference_audio.py
"""
import hashlib
import json
import math
import os
import struct
import sys
import wave

SOURCE_SHA256 = "df9ad4771af3c7d6fa4cdddf30b4a1cab92d3ca7a031a3853dc67cf0cf7eb723"
SOURCE_NOTE = "public gameplay recording BV14b411K7bv, audio format 30216 decoded to 48 kHz stereo WAV"
OUTPUT_RATE = 22050
OUT = os.environ.get("SPARKTREAD_AUDIO_OUT") or os.path.join(
    os.path.dirname(__file__), "..", "Sources", "AppleAdapters", "Resources", "Audio")
MANIFEST = os.environ.get("SPARKTREAD_AUDIO_MANIFEST") or os.path.join(
    os.path.dirname(__file__), "audio_manifest.json")

# name: (start s, end s, fade-in ms, fade-out ms, what it is / why this instance)
CUTS = {
    # The owner identified the results-screen riff (74.0 s on) as the END-of-stage
    # sound, and the stage-START sound they want is NOT in this recording at
    # all (it is the NES Battle City stage-start jingle, whose rights belong
    # to Namco — the game ships an ORIGINAL jingle in that style instead, see
    # Tools/build_audio_assets.py). The results passage below is cut out of a
    # continuously sounding loop and faded: the exception to the silent-margin
    # rule.
    "sfx_stage_win": (74.000, 78.200, 5, 60,
                      "end-of-stage passage: the results-screen drum loop from its rise to the next card (continuous; faded)"),
    "sfx_fire_normal": (185.290, 185.630, 2, 20, "shot glide: isolated instance, silence before and after"),
    "sfx_fire_rapid": (185.290, 185.630, 2, 20, "the same isolated shot instance; whether the reference has other launch sounds is not established"),
    "sfx_fire_special": (185.290, 185.630, 2, 20, "the same isolated shot instance; whether the reference has other launch sounds is not established"),
    "sfx_tank_explode": (21.860, 22.720, 2, 20, "enemy destroyed: the kill with the score roll (confirmed), isolated"),
    "sfx_player_explode": (100.200, 101.000, 2, 20, "heavy explosion: isolated instance, silence before and after"),
    "sfx_pickup_collect": (104.740, 105.480, 2, 30, "pickup jingle: isolated instance (cut before its repeat)"),
    "sfx_hit_steel": (102.260, 102.480, 2, 15, "click: isolated instance, assigned to steel/boundary"),
}


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def read_window(path, t0, t1):
    with wave.open(path, "rb") as w:
        rate, channels, width = w.getframerate(), w.getnchannels(), w.getsampwidth()
        if width != 2:
            raise SystemExit("expected 16-bit source")
        start, end = int(t0 * rate), int(t1 * rate)
        w.setpos(start)
        raw = w.readframes(end - start)
    count = (end - start) * channels
    ints = struct.unpack("<%dh" % count, raw)
    mono = [sum(ints[i:i + channels]) / (channels * 32768.0) for i in range(0, count, channels)]
    return rate, mono


def polyphase_table(up, down, taps, cutoff):
    """taps input samples per output sample; one kernel per output phase."""
    table = []
    half = taps / 2.0
    for phase in range(up):
        frac = phase / up
        kernel = []
        for m in range(taps):
            x = m - half + 1 - frac  # position of tap m relative to the output sample
            arg = cutoff * x
            s = 1.0 if arg == 0 else math.sin(math.pi * arg) / (math.pi * arg)
            wnd = 0.5 - 0.5 * math.cos(2 * math.pi * (m + 1) / (taps + 1))  # Hann
            kernel.append(cutoff * s * wnd)
        table.append(kernel)
    return table


def resample(signal, src_rate, dst_rate):
    if src_rate == dst_rate:
        return list(signal)
    g = math.gcd(src_rate, dst_rate)
    up, down = dst_rate // g, src_rate // g          # 22050/48000 → 147/320
    taps = 64
    cutoff = min(1.0, dst_rate / src_rate) * 0.92     # relative to the input Nyquist
    table = polyphase_table(up, down, taps, cutoff)
    out_len = len(signal) * up // down
    out = []
    half = taps // 2
    for n in range(out_len):
        num = n * down
        pos, phase = divmod(num, up)                  # input index and phase (fractional part = phase/up)
        kernel = table[phase]
        base = pos - half + 1
        acc = 0.0
        for m in range(taps):
            i = base + m
            if 0 <= i < len(signal):
                acc += signal[i] * kernel[m]
        out.append(acc)
    return out


def process(mono, rate, fade_in_ms, fade_out_ms):
    y = resample(mono, rate, OUTPUT_RATE)
    mean = sum(y) / len(y)
    y = [v - mean for v in y]
    fi, fo = int(OUTPUT_RATE * fade_in_ms / 1000), int(OUTPUT_RATE * fade_out_ms / 1000)
    for i in range(min(fi, len(y))):
        y[i] *= i / max(1, fi)
    for i in range(min(fo, len(y))):
        y[len(y) - 1 - i] *= i / max(1, fo)
    peak = max(1e-9, max(abs(v) for v in y))
    return [v * 0.8 / peak for v in y]


def write(name, sig):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".wav")
    frames = b"".join(struct.pack("<h", max(-32767, min(32767, int(round(v * 32767))))) for v in sig)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(OUTPUT_RATE)
        f.writeframes(frames)
    return path


def self_sha256():
    with open(os.path.abspath(__file__), "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def main():
    src = os.environ.get("SPARKTREAD_REFERENCE_WAV")
    if not src or not os.path.isfile(src):
        raise SystemExit("set SPARKTREAD_REFERENCE_WAV to the decoded reference recording")
    digest = sha256(src)
    if digest != SOURCE_SHA256:
        raise SystemExit(f"source sha256 {digest[:16]}… is not the pinned recording {SOURCE_SHA256[:16]}…")
    manifest = {"files": {}}
    if os.path.exists(MANIFEST):
        with open(MANIFEST) as f:
            manifest = json.load(f)
    # An excerpt no longer in CUTS is no longer an excerpt: drop its entry so
    # the generator may take the name back.
    for name in [n for n, e in manifest["files"].items()
                 if e.get("attribution") == "excerpt" and n[:-4] not in CUTS]:
        del manifest["files"][name]
    for name, (t0, t1, fade_in, fade_out, note) in CUTS.items():
        rate, mono = read_window(src, t0, t1)
        path = write(name, process(mono, rate, fade_in, fade_out))
        manifest["files"][name + ".wav"] = {
            "attribution": "excerpt",
            "source": SOURCE_NOTE,
            "source_sha256": SOURCE_SHA256,
            "window_seconds": [t0, t1],
            "processing": f"mono mix, windowed-sinc resample 48000→22050 (64 taps, Hann, 0.92 Nyquist), DC removed, fades {fade_in}/{fade_out} ms, peak 0.8",
            "note": note,
            "milliseconds": round((t1 - t0) * 1000),
            "sha256": sha256(path),
        }
        print(f"{name}.wav  {round((t1 - t0) * 1000)} ms  ← {t0:.3f}–{t1:.3f} s")
    manifest["files"] = dict(sorted(manifest["files"].items()))
    manifest["extractor"] = "Tools/extract_reference_audio.py"
    manifest["extractor_sha256"] = self_sha256()
    manifest["rights_review"] = ("owner decision 2026-09-10 (recorded): the owner reviewed and accepts the use of "
                                 "the recording excerpts, the synthesized voices and the original jingle in the "
                                 "product; no third-party licence is held — the decision and its responsibility "
                                 "are the owner's (ASSET_PRODUCTION_MANIFEST.md)")
    with open(MANIFEST, "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")
    print(f"manifest: {os.path.normpath(MANIFEST)} ({len(CUTS)} excerpt files)")


if __name__ == "__main__":
    main()
