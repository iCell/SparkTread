"""Results-screen survey of the reference recording (ADR-0012), media-free
procedure. usage: results_screens.py VIDEO OUTDIR

1. Samples the top strip at 1 fps and flags seconds whose yellow "Mission
   Complete" title is present (results screens); runs shorter than 3 s
   are dropped (title flashes elsewhere).
2. Per run: extracts 10 fps frames, finds the rising "Reward +N" text by
   its yellow pixels above the panel (text-shaped: >= 8 rows with >= 3
   pixels and > 150 pixels, which excludes the panel border), crops it;
   crops the finished panel (run end + 0.7 s); crops the score counter at
   the run's start (+0.2 s) and end (+0.7 s); crops the next stage card
   (+3.0 s) for the stage number.
3. Writes tiles for reading by eye (no OCR): tile_reward.png,
   tile_panel_N.png, tile_sc_N.png, tile_cards.png and runs.json.

Needs ffmpeg, numpy and matplotlib. Frame geometry assumes the 480x360
encode of the source (Tools/reference_measure/README.md, "Source").
"""
import glob, json, os, subprocess, sys
import numpy as np
import matplotlib.image as mpimg

V, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
os.chdir(OUT)


def ff(*args):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *args], check=True)


def yellow(img):
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    return (r > 0.75) & (g > 0.65) & (b < 0.35) & (r - b > 0.5)


def tile(files, cols, out, w, h):
    args = []
    for f in files:
        args += ["-i", f]
    n = len(files)
    layout = "|".join(f"{(i % cols) * w}_{(i // cols) * h}" for i in range(n))
    ff(*args, "-filter_complex",
       "".join(f"[{i}:v]" for i in range(n)) + f"xstack=inputs={n}:layout={layout}:fill=black", out)


# 1. Results-screen runs.
os.makedirs("top", exist_ok=True)
ff("-i", V, "-vf", "fps=1,crop=480:70:0:0", "top/top_%05d.png")
flag = []
for fn in sorted(glob.glob("top/top_*.png")):
    flag.append(int(yellow(mpimg.imread(fn)[:, :, :3])[36:62, 130:350].sum()))
runs, start = [], None
for i, n in enumerate(flag + [0]):
    on = n > 400
    if on and start is None:
        start = i
    if not on and start is not None:
        if i - start >= 3:
            runs.append((start, i - 1))
        start = None
json.dump(runs, open("runs.json", "w"))
print(len(runs), "results screens")

# 2. Per-run crops.
reward_files, panel_files, sc_files, card_files = [], [], [], []
for k, (a, b) in enumerate(runs, 1):
    d = f"runs/r{k:02d}"
    os.makedirs(d, exist_ok=True)
    for f in glob.glob(d + "/f_*.png"):
        os.remove(f)
    t0 = a - 1.5
    ff("-ss", str(t0), "-t", str(b - a + 3.5), "-i", V, "-vf", "fps=10,crop=240:320:0:0", d + "/f_%04d.png")
    frames = sorted(glob.glob(d + "/f_*.png"))
    cands = []
    for i, fn in enumerate(frames):
        m = yellow(mpimg.imread(fn)[:, :, :3])[0:132, 45:120]
        if (m.sum(axis=1) >= 3).sum() >= 8 and m.sum() > 150:
            cands.append((int(m.sum()), i, float(np.where(m)[0].mean())))
    if cands:
        n, i, cy = max(cands)
        first = min(c[1] for c in cands)
        ff("-i", frames[i], "-vf", f"crop=200:28:38:{max(0, int(cy) - 14)},scale=600:84:flags=neighbor", f"{d}/reward.png")
        reward_files.append(f"{d}/reward.png")
        print(k, a, b, "reward text first at", round(t0 + first / 10, 1), "s")
    else:
        print(k, a, b, "no reward text found")
    ff("-ss", str(b + 0.7), "-i", V, "-frames:v", "1", "-vf", "crop=190:215:28:92,scale=380:430:flags=neighbor", f"{d}/panel.png")
    panel_files.append(f"{d}/panel.png")
    for tag, t in (("s", a + 0.2), ("e", b + 0.7)):
        ff("-ss", str(t), "-i", V, "-frames:v", "1", "-vf", "crop=160:30:0:0,scale=480:90:flags=neighbor", f"{d}/sc_{tag}.png")
        sc_files.append(f"{d}/sc_{tag}.png")
    ff("-ss", str(b + 3.0), "-i", V, "-frames:v", "1", "-vf", "crop=480:120:0:60", f"{d}/card.png")
    card_files.append(f"{d}/card.png")

# 3. Tiles.
if reward_files:
    tile(reward_files, 3, "tile_reward.png", 600, 84)
for j in range(0, len(panel_files), 10):
    tile(panel_files[j:j + 10], 5, f"tile_panel_{j // 10 + 1}.png", 380, 430)
for j in range(0, len(sc_files), 30):
    tile(sc_files[j:j + 30], 2, f"tile_sc_{j // 30 + 1}.png", 480, 90)
tile(card_files, 2, "tile_cards.png", 480, 120)
print("tiles written to", OUT)
