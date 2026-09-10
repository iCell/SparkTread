"""Isolation score for candidate excerpt windows: RMS (dBFS) in the 60 ms
before the window, the loudest 20 ms inside it, its last 30 ms, and the
60 ms after — a clean instance has silent margins (≈ -60 dB or below).
usage: clean.py WAV name:t0:t1 ..."""
import sys
import numpy as np
from scipy.io import wavfile
rate, data = wavfile.read(sys.argv[1])
if data.ndim > 1: data = data.mean(axis=1)
data = data.astype(np.float32) / 32768.0
def lvl(a, b):
    seg = data[int(a * rate): int(b * rate)]
    return 20 * np.log10(np.sqrt(np.mean(seg ** 2)) + 1e-9) if len(seg) else -999
def peak20(a, b):
    step = int(0.02 * rate); seg = data[int(a * rate): int(b * rate)]
    return max(20 * np.log10(np.sqrt(np.mean(seg[i:i + step] ** 2)) + 1e-9) for i in range(0, len(seg) - step, step))
for spec in sys.argv[2:]:
    name, t0, t1 = spec.split(":"); t0, t1 = float(t0), float(t1)
    print(f"{name:14s} {t0:8.3f}-{t1:8.3f}  pre {lvl(t0 - 0.06, t0 - 0.005):6.1f}  peak {peak20(t0, t1):6.1f}  tail {lvl(t1 - 0.03, t1):6.1f}  post {lvl(t1 + 0.005, t1 + 0.06):6.1f}")
