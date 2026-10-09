#!/usr/bin/env python3
"""App Store media from the raw captures (owner 2026-10-09): designed
screenshots and the preview video, in every store language.

    python3 Tools/StoreMedia/compose.py candidates   # rank gameplay frames, contact sheets
    python3 Tools/StoreMedia/compose.py screens      # designed screenshots (iPhone 6.9", iPad 13")
    python3 Tools/StoreMedia/compose.py video        # preview videos (iPhone 6.9", 1920x886)

Reads .build/store/raw (capture.py), Tools/StoreMedia/captions.json and
Tools/StoreMedia/selection.json (which frame and which clip window each
store slot uses); writes AppStoreMedia/<lang>/... (gitignored: large binaries, rebuilt from the captures) Needs ffmpeg.
"""
import glob
import json
import os
import shutil
import struct
import subprocess
import sys
import wave
from array import array

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RAW = os.path.join(ROOT, ".build", "store", "raw")
WORK = os.path.join(ROOT, ".build", "store", "work")
FINAL = os.path.join(ROOT, "AppStoreMedia")
HERE = os.path.dirname(os.path.abspath(__file__))
AUDIO = os.path.join(ROOT, "Sources", "AppleAdapters", "Resources", "Audio")
LANGS = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "es"]
CAPTIONS = json.load(open(os.path.join(HERE, "captions.json")))

# What makes a frame worth showing: something exploding, hit or collected
# in the second before it, and the special weapons' launches.
WEIGHTS = {"sfx_tank_explode": 6, "sfx_player_explode": 1, "sfx_explosion_blast": 4, "sfx_hit_tank": 2,
           "sfx_pickup_collect": 3, "sfx_pickup_spawn": 2, "sfx_fire_flame": 2, "sfx_fire_ap": 2,
           "sfx_fire_explosion": 2, "sfx_fire_rapid": 1, "sfx_hit_brick": 0.5, "sfx_base_shield_on": 3,
           "sfx_life_up": 3, "sfx_spawn_warp": 1}


def sh(*args):
    subprocess.run(list(args), check=True, capture_output=True)


def cues(folder, name):
    path = os.path.join(folder, name + "_cues.txt")
    out = []
    if os.path.exists(path):
        for line in open(path):
            parts = line.split()
            if len(parts) == 4:
                out.append((float(parts[0]), parts[1], parts[2], float(parts[3])))
    return out


def start_of(folder, name):
    return float(open(os.path.join(folder, name + "_start.txt")).read())


def score_at(events, t, before=1.2, after=0.3):
    return sum(WEIGHTS.get(name, 0) for (when, kind, name, _) in events
               if kind == "play" and t - before <= when <= t + after)


def candidates():
    os.makedirs(WORK, exist_ok=True)
    for folder in sorted(glob.glob(os.path.join(RAW, "iphone", "stage*"))):
        events = cues(folder, "play")
        shots = sorted(glob.glob(os.path.join(folder, "shot_*.png")))
        ranked = sorted(((score_at(events, os.path.getmtime(s)), s) for s in shots), reverse=True)[:8]
        name = os.path.basename(folder)
        print(name, [(round(sc, 1), os.path.basename(s)) for sc, s in ranked])
        # Contact sheet of the top eight, labelled by their index in `ranked`.
        inputs = []
        for _, s in ranked:
            inputs += ["-i", s]
        if not inputs:
            continue
        n = len(ranked)
        filters = "".join(f"[{i}:v]scale=716:-1[s{i}];" for i in range(n))
        filters += "".join(f"[s{i}]" for i in range(n)) + f"xstack=inputs={n}:layout=" + \
            "|".join(f"{(i % 4) * 716}_{(i // 4) * 330}" for i in range(n)) + ":fill=black"
        sh("ffmpeg", "-loglevel", "error", "-y", *inputs, "-filter_complex", filters,
           "-frames:v", "1", "-update", "1", os.path.join(WORK, f"sheet_{name}.jpg"))
        with open(os.path.join(WORK, f"ranked_{name}.json"), "w") as f:
            json.dump([s for _, s in ranked], f, indent=1)


SELECTION = json.load(open(os.path.join(HERE, "selection.json")))
SIZES = {"iphone": (2868, 1320, "side"), "ipad": (2752, 2064, "top")}
# The iPad simulator stays portrait; the landscape-only app is letterboxed
# into this band of its 2064x2752 frame (its real landscape layout at 75 %).
IPAD_BAND = "crop=2064:1548:0:602"


def renderer(frames, name):
    path = os.path.join(WORK, name)
    with open(path, "w") as f:
        json.dump({"frames": frames}, f, ensure_ascii=False, indent=1)
    subprocess.run(["swift", "run", "-c", "release", "store-art-renderer", path], cwd=ROOT, check=True,
                   stdin=subprocess.DEVNULL, capture_output=True)


def source_for(kind, entry, lang):
    src = os.path.join(RAW, entry["source"].replace("{lang}", lang))
    if kind != "ipad":
        return src
    band = os.path.join(WORK, "ipad_band", entry["source"].replace("{lang}", lang).replace("/", "_"))
    if not os.path.exists(band):
        os.makedirs(os.path.dirname(band), exist_ok=True)
        sh("ffmpeg", "-loglevel", "error", "-y", "-i", src, "-vf", IPAD_BAND, band)
    return band


def screens(langs=LANGS):
    os.makedirs(WORK, exist_ok=True)
    frames = []
    for kind, (w, h, layout) in SIZES.items():
        for lang in langs:
            for i, entry in enumerate(SELECTION[kind], start=1):
                headline, subline = CAPTIONS["screens"][entry["slot"]][lang]
                if kind == "ipad":
                    # The iPad caption runs the full width: one line each.
                    joiner = "" if lang in ("zh-Hans", "zh-Hant", "ja") else " "
                    headline = joiner.join(headline.split("\n"))
                    subline = joiner.join(subline.split("\n"))
                frames.append({"out": os.path.join(FINAL, lang, kind, f"{i:02d}_{entry['slot']}.png"),
                               "width": w, "height": h, "layout": layout, "lang": lang,
                               "shot": source_for(kind, entry, lang), "headline": headline, "subline": subline,
                               "icons": entry.get("icons"), "zoom": entry.get("zoom"),
                               "hero": entry["slot"] == "hero"})
    renderer(frames, "screens.json")
    print(f"{len(frames)} screenshots in {FINAL}")


# ---------------------------------------------------------------- video

PREVIEW = (1920, 886)                 # iPhone 6.5"/6.9" landscape preview
# The recording is the device's portrait framebuffer with the Dynamic
# Island; screenshots have neither. Rotate, then crop the island off the
# left edge keeping 1920:886.
FRAME = "transpose=2,crop=2700:1246:168:37"
FPS = 30
CROSSFADE = 0.4
TITLE_LENGTH = 4.6
CLIP_LENGTH = 4.5
END_LENGTH = 3.6
# Preview order: what each clip shows and the lower third it carries.
CLIPS = [("defend", "stage04"), ("terrain", "stage10"), ("weapons", "stage02"), ("enemies", "stage12")]
# Sounds that never go in the preview: the empty-cap click is noise.
MUTED = {"sfx_dry_fire"}


def best_window(folder):
    """The CLIP_LENGTH window with the most going on, after the stage card
    and before the stage is decided."""
    events = cues(folder, "play")
    start = start_of(folder, "play")
    times = [(when - start, name) for (when, kind, name, _) in events if kind == "play"]
    end = max([t for t, n in times if n == "sfx_stage_win"] or [1e9])
    duration = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0",
                                     os.path.join(folder, "play.mp4")], capture_output=True, text=True).stdout)
    best, best_score = 6.0, -1
    s = 6.0
    while s + CLIP_LENGTH < min(duration, end - 1.0):
        score = sum(WEIGHTS.get(n, 0) for t, n in times if s + 0.3 <= t <= s + CLIP_LENGTH - 0.4)
        if score > best_score:
            best, best_score = s, score
        s += 0.25
    return round(best, 2), best_score


CROPPED = (2700, 1246)                # the frame after FRAME
PUSH_FROM, PUSH_TO = 1.15, 1.45       # the clips' slow push-in


def focus(folder, at):
    """Where the action is in a clip window: the centroid of frame-to-frame
    motion (the HUD band excluded), in the cropped frame's pixels."""
    sw, sh_ = 270, 124
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-ss", str(at), "-t", str(CLIP_LENGTH),
                          "-noautorotate", "-i", os.path.join(folder, "play.mp4"),
                          "-vf", f"{FRAME},scale={sw}:{sh_},fps=8,format=gray", "-f", "rawvideo", "-"],
                         capture_output=True, check=True).stdout
    frames = [raw[i:i + sw * sh_] for i in range(0, len(raw) - sw * sh_ + 1, sw * sh_)]
    sx = sy = total = 0
    for a, b in zip(frames, frames[1:]):
        for y in range(int(sh_ * 0.14), sh_):
            row = y * sw
            for x in range(sw):
                d = abs(a[row + x] - b[row + x])
                if d > 18:
                    sx += x * d; sy += y * d; total += d
    if total == 0:
        return CROPPED[0] / 2, CROPPED[1] / 2
    return sx / total * CROPPED[0] / sw, sy / total * CROPPED[1] / sh_


def push_in(fx, fy, length):
    """zoompan from the full frame's PUSH_FROM to PUSH_TO, toward (fx, fy)."""
    frames = int(length * FPS)
    w, h = PREVIEW
    z = f"{PUSH_FROM}+{PUSH_TO - PUSH_FROM}*on/{frames}"
    x = f"max(0,min(iw-iw/zoom,{fx:.0f}-iw/zoom/2))"
    y = f"max(0,min(ih-ih/zoom,{fy:.0f}-ih/zoom/2))"
    return f"zoompan=z='{z}':x='{x}':y='{y}':d=1:s={w}x{h}:fps={FPS}"


def pcm(name, cache={}):
    """A cue as 48 kHz stereo 16-bit samples."""
    if name not in cache:
        raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", os.path.join(AUDIO, name + ".wav"),
                              "-f", "s16le", "-ac", "2", "-ar", "48000", "-"], capture_output=True, check=True).stdout
        cache[name] = array("h", raw)
    return cache[name]


def soundtrack(placements, length, path, fade_out=0.8):
    """Mix (timeline seconds, cue, volume, max seconds) into a WAV."""
    rate = 48000
    total = int(length * rate) * 2
    mix = array("i", bytes(4 * total))
    for at, name, volume, limit in placements:
        if at < 0 or name in MUTED:
            continue
        samples = pcm(name)
        begin = int(at * rate) * 2
        count = min(len(samples), total - begin, int(limit * rate) * 2 if limit else len(samples))
        gain = int(volume * 1024)
        for i in range(max(0, count)):
            mix[begin + i] += samples[i] * gain >> 10
    peak = max(1, max(abs(v) for v in mix))
    scale = min(1.0, 29000 / peak)
    fade = int(fade_out * rate) * 2
    out = array("h", bytes(2 * total))
    for i in range(total):
        v = mix[i] * scale
        if i >= total - fade:
            v *= (total - i) / fade
        out[i] = int(max(-32768, min(32767, v)))
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(out.tobytes())


def placements_for(folder, name, window_start, length, timeline_at):
    """The logged sounds that started inside the window, moved onto the
    preview's timeline; a loop plays while it was running."""
    events = cues(folder, name)
    start = start_of(folder, name)
    out, open_loops = [], {}
    for when, kind, cue, volume in events:
        t = when - start - window_start
        if kind == "play" and 0 <= t < length:
            out.append((timeline_at + t, cue, volume, None))
        elif kind == "loop-start":
            open_loops[cue] = (t, volume)
        elif kind == "loop-stop" and cue in open_loops:
            began, vol = open_loops.pop(cue)
            out += loop_span(cue, vol, began, t, length, timeline_at)
    for cue, (began, vol) in open_loops.items():
        out += loop_span(cue, vol, began, length, length, timeline_at)
    return out


def loop_span(cue, volume, began, ended, length, timeline_at):
    a, b = max(0.0, began), min(length, ended)
    if b <= a:
        return []
    seg = len(pcm(cue)) / 2 / 48000
    spans, t = [], a
    while t < b:
        spans.append((timeline_at + t, cue, volume, min(seg, b - t)))
        t += seg
    return spans


def video(langs=LANGS):
    os.makedirs(WORK, exist_ok=True)
    windows, focuses = {}, {}
    for slot, stage in CLIPS:
        folder = os.path.join(RAW, "iphone", stage)
        windows[stage] = best_window(folder)
        focuses[stage] = focus(folder, windows[stage][0])
        print(f"{slot}: {stage} from {windows[stage][0]}s (score {windows[stage][1]}), "
              f"focus {focuses[stage][0]:.0f},{focuses[stage][1]:.0f}")
    w, h = PREVIEW
    cards = []
    for lang in langs:
        for slot, _ in CLIPS:
            headline, subline = CAPTIONS["video"][slot][lang]
            cards.append({"out": os.path.join(WORK, "video", lang, f"lower_{slot}.png"), "width": w, "height": h,
                          "layout": "lowerThird", "lang": lang, "headline": headline, "subline": subline})
        headline, subline = CAPTIONS["video"]["end"][lang]
        cards.append({"out": os.path.join(WORK, "video", lang, "end.png"), "width": w, "height": h,
                      "layout": "endCard", "lang": lang, "headline": headline, "subline": subline,
                      "icons": ["player", "normal_d", "rapid_d", "fire_d", "ap_d", "explosion_d"]})
    renderer(cards, "video_cards.json")

    for lang in langs:
        title_folder = os.path.join(RAW, "iphone", lang)
        title_cues = cues(title_folder, "title")
        tread = next(when for when, kind, name, _ in title_cues if name == "sfx_title_tread")
        title_start = round(tread - start_of(title_folder, "title") - 0.05, 3)

        # Timeline: title, four clips, the end card, crossfaded.
        lengths = [TITLE_LENGTH] + [CLIP_LENGTH] * len(CLIPS) + [END_LENGTH]
        starts = [0.0]
        for L in lengths[:-1]:
            starts.append(starts[-1] + L - CROSSFADE)
        total = starts[-1] + END_LENGTH

        # Some recordings carry a rotation tag and some do not; reading
        # every one untagged keeps FRAME's rotation right for all of them.
        inputs = ["-noautorotate", "-i", os.path.join(title_folder, "title.mp4")]
        for _, stage in CLIPS:
            inputs += ["-noautorotate", "-i", os.path.join(RAW, "iphone", stage, "play.mp4")]
        for slot, _ in CLIPS:
            inputs += ["-loop", "1", "-t", str(CLIP_LENGTH), "-i", os.path.join(WORK, "video", lang, f"lower_{slot}.png")]
        inputs += ["-loop", "1", "-t", str(END_LENGTH), "-i", os.path.join(WORK, "video", lang, "end.png")]

        def cut(i, at, length, push=None):
            head = f"[{i}:v]trim=start={at}:duration={length},setpts=PTS-STARTPTS,{FRAME},fps={FPS},"
            body = push_in(*push, length) if push else f"scale={w}:{h}:flags=lanczos"
            return head + body + ",format=yuv420p,setsar=1"
        graph = [cut(0, title_start, TITLE_LENGTH) + "[v0]"]
        n = len(CLIPS)
        for k, (slot, stage) in enumerate(CLIPS, start=1):
            graph.append(cut(k, windows[stage][0], CLIP_LENGTH, push=focuses[stage]) + f"[c{k}]")
            graph.append(f"[{n + k}:v]format=rgba,fade=t=in:st=0.35:d=0.35:alpha=1,"
                         f"fade=t=out:st={CLIP_LENGTH - 0.75}:d=0.35:alpha=1[o{k}]")
            graph.append(f"[c{k}][o{k}]overlay=0:0:shortest=1,format=yuv420p[v{k}]")
        graph.append(f"[{2 * n + 1}:v]fps={FPS},format=yuv420p,setsar=1,"
                     f"fade=t=out:st={END_LENGTH - 0.6}:d=0.6[v{n + 1}]")
        last = "v0"
        for k in range(1, n + 2):
            out = f"x{k}" if k < n + 1 else "vjoined"
            graph.append(f"[{last}][v{k}]xfade=transition=fade:duration={CROSSFADE}:offset={starts[k]:.3f}[{out}]")
            last = out
        # The title recordings of some languages carry a 90-degree display
        # matrix; it rides the frames through the graph and would turn the
        # finished preview sideways in every player.
        graph.append("[vjoined]sidedata=mode=delete:type=DISPLAYMATRIX[vout]")
        silent = os.path.join(WORK, "video", lang, "picture.mp4")
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", *inputs, "-filter_complex", ";".join(graph),
                        "-map", "[vout]", "-c:v", "libx264", "-profile:v", "high", "-pix_fmt", "yuv420p",
                        "-b:v", "11M", "-maxrate", "12M", "-bufsize", "24M", "-r", str(FPS), "-an", silent],
                       check=True)

        placements = placements_for(title_folder, "title", title_start, TITLE_LENGTH, 0.0)
        for k, (slot, stage) in enumerate(CLIPS, start=1):
            placements += placements_for(os.path.join(RAW, "iphone", stage), "play",
                                         windows[stage][0], CLIP_LENGTH, starts[k])
        # The end card carries the results music the owner chose for every
        # stage's end (sfx_stage_win, a fixed asset).
        placements.append((starts[-1], "sfx_stage_win", 0.9, END_LENGTH))
        audio = os.path.join(WORK, "video", lang, "sound.wav")
        soundtrack(placements, total, audio)

        final = os.path.join(FINAL, lang, "preview_iphone.mp4")
        os.makedirs(os.path.dirname(final), exist_ok=True)
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", silent, "-i", audio, "-map", "0:v", "-map", "1:a",
                        "-c:v", "copy", "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2",
                        "-movflags", "+faststart", "-shortest", final], check=True)
        print(f"{final}  {total:.1f}s")


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "candidates":
        candidates()
    elif command == "screens":
        screens(sys.argv[2:] or LANGS)
    elif command == "video":
        video(sys.argv[2:] or LANGS)
    else:
        sys.exit(__doc__)
