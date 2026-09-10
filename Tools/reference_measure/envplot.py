"""Low-band (40-400 Hz) and full-band 5 ms RMS envelopes for several windows,
stacked with a 100 ms grid, to read a drum passage by eye.
usage: envplot.py WAV OUT.png t0:t1 ..."""
import sys
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfiltfilt
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
wav, out = sys.argv[1], sys.argv[2]
windows = [tuple(map(float, w.split(":"))) for w in sys.argv[3:]]
rate, data = wavfile.read(wav)
if data.ndim > 1: data = data.mean(axis=1)
data = data.astype(np.float32) / 32768.0
sos = butter(4, [40, 400], btype="band", fs=rate, output="sos")
fig, axes = plt.subplots(len(windows), 1, figsize=(18, 2.6 * len(windows)), dpi=80)
for ax, (t0, t1) in zip(np.atleast_1d(axes), windows):
    seg = data[int(t0 * rate): int(t1 * rate)]
    low = sosfiltfilt(sos, seg)
    hop = int(0.005 * rate)
    t = t0 + np.arange(0, len(seg) - hop, hop) / rate
    def env(x): return 20 * np.log10(np.array([np.sqrt(np.mean(x[i:i + hop] ** 2)) + 1e-9 for i in range(0, len(x) - hop, hop)]))
    ax.plot(t, env(seg), color="0.6", lw=0.8, label="full")
    ax.plot(t, env(low), color="C3", lw=1.2, label="40-400 Hz")
    ax.set_ylim(-60, 0); ax.set_xlim(t0, t1)
    ax.set_xticks(np.arange(np.ceil(t0 * 10) / 10, t1, 0.1), minor=True); ax.set_xticks(np.arange(np.ceil(t0 * 2) / 2, t1, 0.5))
    ax.grid(True, which="both", axis="x", alpha=0.4); ax.set_title(f"{t0}-{t1} s", fontsize=9); ax.legend(loc="upper right", fontsize=7)
plt.tight_layout(); plt.savefig(out)
