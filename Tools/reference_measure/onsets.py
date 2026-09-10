"""Onsets of the tonal 2.6-3.4 kHz glide (the candidate shot).
usage: onsets.py WAV T0 T1"""
import sys
import numpy as np
from scipy.signal import stft
from measure import load

src, t0, t1 = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
rate, seg = load(src, t0, t1)
f, t, Z = stft(seg, fs=rate, nperseg=512, noverlap=512 - 55)
mag = np.abs(Z)
ratio = mag[(f >= 2600) & (f <= 3400)].sum(axis=0) / (mag[f >= 150].sum(axis=0) + 1e-9)
env = 20 * np.log10(np.sqrt((mag ** 2).sum(axis=0)) + 1e-6)
last = -1.0
for i in range(len(t)):
    if ratio[i] > 0.35 and env[i] > -45 and (t[i] - last) > 0.12:
        print(f"glide onset {t0 + t[i]:7.3f}s  band ratio {ratio[i]:.2f}")
        last = t[i]
