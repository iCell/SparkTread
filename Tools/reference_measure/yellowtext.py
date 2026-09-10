"""Centre and box of yellow UI text per frame (stage title, outcome text).
usage: yellowtext.py FRAMEDIR T0"""
import sys, glob
import numpy as np
import matplotlib.image as mpimg

files = sorted(glob.glob(sys.argv[1] + "/f_*.png"))
t0 = float(sys.argv[2])
for i, fn in enumerate(files):
    img = mpimg.imread(fn)[:, :, :3]
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    m = (r > 0.75) & (g > 0.65) & (b < 0.35) & (r - b > 0.5)
    m[330:, :] = False  # HUD row
    ys, xs = np.where(m)
    if len(xs) > 40:
        print(f"{t0 + i / 30:6.2f} n={len(xs):5d} centre=({xs.mean():5.1f},{ys.mean():5.1f})"
              f" box x{xs.min()}-{xs.max()} y{ys.min()}-{ys.max()}")
    else:
        print(f"{t0 + i / 30:6.2f} n={len(xs):5d}")
