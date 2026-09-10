"""2.5 ms track: level, three strongest peaks below 4.1 kHz, strongest peak
above 4.3 kHz (mirror-pair candidate). usage: fine.py WAV T0 T1"""
import sys
import numpy as np
from scipy.signal import stft
from measure import load

src, t0, t1 = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
rate, seg = load(src, t0, t1)
f, t, Z = stft(seg, fs=rate, nperseg=1024, noverlap=1024 - 55)
mag = np.abs(Z)
low = (f >= 150) & (f <= 4100)
high = (f >= 4300) & (f <= 9000)
env = 20 * np.log10(np.sqrt((mag ** 2).sum(axis=0)) + 1e-6)
print(" t(s)     env(dB)  f1(Hz)  f2(Hz)  f3(Hz)  high(Hz)  f1+high")
for i in range(0, len(t), 2):
    col = mag[:, i]
    order = np.argsort(col * low)[::-1][:3]
    hi = f[np.argmax(col * high)]
    print(f"{t0 + t[i]:8.4f} {env[i]:7.1f} {f[order[0]]:7.0f} {f[order[1]]:7.0f} {f[order[2]]:7.0f}"
          f"  {hi:8.0f}  {f[order[0]] + hi:7.0f}")
