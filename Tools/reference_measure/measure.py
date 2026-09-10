"""5 ms peak/level/band/flatness track plus a spectrogram for one window.
usage: measure.py WAV OUT.png T0 T1"""
import sys
import numpy as np
from scipy.io import wavfile
from scipy.signal import resample_poly, stft
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

def load(path, t0, t1, rate_out=22050):
    rate, data = wavfile.read(path)
    if data.ndim > 1:
        data = data.mean(axis=1)
    data = data.astype(np.float32)
    if np.abs(data).max() > 1.5:
        data /= 32768.0
    seg = data[int(t0 * rate): int(t1 * rate)]
    if rate != rate_out:
        seg = resample_poly(seg, rate_out, rate).astype(np.float32)
    return rate_out, seg

if __name__ == "__main__":
    src, out, t0, t1 = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
    rate, seg = load(src, t0, t1)
    f, t, Z = stft(seg, fs=rate, nperseg=512, noverlap=512 - 110)
    mag = np.abs(Z)
    db = 20 * np.log10(mag + 1e-6)
    peak = f[np.argmax(mag[4:], axis=0) + 4]
    env = 20 * np.log10(np.sqrt((mag ** 2).sum(axis=0)) + 1e-6)
    low = (mag[f < 500] ** 2).sum(axis=0)
    mid = (mag[(f >= 500) & (f < 2500)] ** 2).sum(axis=0)
    high = (mag[f >= 2500] ** 2).sum(axis=0)
    flat = np.exp(np.log(mag + 1e-9).mean(axis=0)) / (mag.mean(axis=0) + 1e-9)
    print(f"window {t0}-{t1}s, {len(t)} frames of 5 ms")
    print(" t(s)   env(dB)  peak(Hz)  low/mid/high(%)  flatness")
    for i in range(0, len(t), 4):
        tot = low[i] + mid[i] + high[i] + 1e-12
        print(f"{t0 + t[i]:6.3f} {env[i]:7.1f} {peak[i]:8.0f}   "
              f"{100 * low[i] / tot:3.0f}/{100 * mid[i] / tot:3.0f}/{100 * high[i] / tot:3.0f}   {flat[i]:.2f}")
    fig, ax = plt.subplots(figsize=(18, 5), dpi=80)
    ax.imshow(db[:200], aspect="auto", origin="lower", cmap="magma", vmin=-90, vmax=-10,
              extent=[t0, t1, 0, f[199]])
    ax.set_xticks(np.arange(t0, t1 + 0.001, 0.5))
    ax.grid(True, axis="x", color="white", alpha=0.3, linewidth=0.5)
    ax.set_ylabel("Hz"); ax.set_xlabel("s")
    plt.tight_layout(); plt.savefig(out)
