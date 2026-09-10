"""Moving-object blobs between consecutive frames of a 30 fps PNG sequence
(ffmpeg -ss T0 -t D -i VIDEO -vf fps=30 dir/f_%03d.png).
usage: blobs.py FRAMEDIR T0 [MINPIX MAXPIX]"""
import sys, glob
import numpy as np
import matplotlib.image as mpimg
from scipy import ndimage

files = sorted(glob.glob(sys.argv[1] + "/f_*.png"))
t0 = float(sys.argv[2])
lo, hi = (int(sys.argv[3]), int(sys.argv[4])) if len(sys.argv) > 4 else (2, 60)
prev = None
for i, fn in enumerate(files):
    img = mpimg.imread(fn)[:, :, :3].astype(np.float32)
    if prev is not None:
        d = np.abs(img - prev).sum(axis=2) > 0.35
        lab, n = ndimage.label(d, structure=np.ones((3, 3)))
        blobs = []
        for k in range(1, n + 1):
            ys, xs = np.where(lab == k)
            if lo <= len(ys) <= hi:
                blobs.append((int(xs.mean()), int(ys.mean()), len(ys)))
        blobs.sort(key=lambda b: -b[2])
        print(f"{t0 + i / 30:6.2f} changed={int(d.sum()):5d} "
              + " ".join(f"({x},{y},n{s})" for x, y, s in blobs[:8]))
    prev = img
