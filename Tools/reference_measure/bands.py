"""250 Hz band spectrum (dB rel. max, 0-4.25 kHz) and 20 ms RMS envelope
per window. usage: bands.py WAV name:T0:T1 ..."""
import sys
import numpy as np
from scipy.io import wavfile

rate, data = wavfile.read(sys.argv[1])
if data.ndim > 1:
    data = data.mean(axis=1)
data = data.astype(np.float32)
if np.abs(data).max() > 1.5:
    data /= 32768.0
for spec in sys.argv[2:]:
    name, t0, t1 = spec.split(":")
    seg = data[int(float(t0) * rate): int(float(t1) * rate)]
    spectrum = np.abs(np.fft.rfft(seg * np.hanning(len(seg)))) ** 2
    freqs = np.fft.rfftfreq(len(seg), 1 / rate)
    bands = np.array([10 * np.log10(spectrum[(freqs >= lo) & (freqs < lo + 250)].mean() + 1e-12)
                      for lo in range(0, 4250, 250)])
    bands -= bands.max()
    step = int(0.02 * rate)
    env = [20 * np.log10(np.sqrt(np.mean(seg[i:i + step] ** 2)) + 1e-9)
           for i in range(0, len(seg) - step + 1, step)]
    print(f"== {name} {t0}-{t1}s")
    print("  bands(dB rel. max) " + " ".join(f"{b:4.0f}" for b in bands))
    print("  env(dBFS per 20 ms) " + " ".join(f"{e:4.0f}" for e in env))
