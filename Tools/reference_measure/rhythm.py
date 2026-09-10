"""Rhythm string from low-band envelope peaks — a HEURISTIC read of a drum
passage: 40-400 Hz band, 5 ms RMS, scipy find_peaks (prominence >= 4 dB,
>= 90 ms apart, level >= -40 dB); prints onset times, inter-onset intervals
and 'S' (< 0.16 s) / 'L' (>= 0.16 s). usage: rhythm.py WAV T0 T1"""
import sys
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfiltfilt, find_peaks
wav, t0, t1 = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
rate, data = wavfile.read(wav)
if data.ndim > 1: data = data.mean(axis=1)
data = data.astype(np.float32) / 32768.0
seg = data[int(t0 * rate): int(t1 * rate)]
low = sosfiltfilt(butter(4, [40, 400], btype="band", fs=rate, output="sos"), seg)
hop = int(0.005 * rate)
env = 20 * np.log10(np.array([np.sqrt(np.mean(low[i:i + hop] ** 2)) + 1e-9 for i in range(0, len(low) - hop, hop)]))
peaks, props = find_peaks(env, prominence=4, distance=int(0.09 / (hop / rate)), height=-40)
times = t0 + peaks * hop / rate
ioi = np.diff(times)
print(f"{t0}-{t1}: {len(times)} peaks")
print("  onsets: " + " ".join(f"{t:.2f}" for t in times))
print("  ioi:    " + " ".join(f"{d:.2f}" for d in ioi))
print("  rhythm: " + "".join("L" if d >= 0.16 else "S" for d in ioi))
