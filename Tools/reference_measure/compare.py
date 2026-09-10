"""Side-by-side spectrograms: reference clip vs builder output.
usage: compare.py OUT.png ref.wav=synth.wav ..."""
import sys
import numpy as np
from scipy.signal import stft
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from measure import load

pairs = [a.split("=") for a in sys.argv[2:]]
fig, axes = plt.subplots(len(pairs), 2, figsize=(16, 2.6 * len(pairs)), dpi=70, squeeze=False)

def spec(ax, path, title):
    rate, data = load(path, 0, 1e9)
    f, t, Z = stft(data, fs=rate, nperseg=512, noverlap=512 - 55)
    db = 20 * np.log10(np.abs(Z) + 1e-6)
    ax.imshow(db[:200], aspect="auto", origin="lower", cmap="magma", vmin=-90, vmax=-10,
              extent=[0, t[-1], 0, f[199]])
    ax.set_title(title, fontsize=9); ax.set_xlim(0, max(0.6, t[-1]))

for row, (ref, synth) in enumerate(pairs):
    spec(axes[row][0], ref, "reference " + ref.split("/")[-1])
    spec(axes[row][1], synth, "synth " + synth.split("/")[-1])
plt.tight_layout(); plt.savefig(sys.argv[1])
