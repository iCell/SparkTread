"""Low-band drum-hit onsets (the reference stage riff), a HEURISTIC: ≈5 ms RMS of the
40-400 Hz band; an onset is a rise of more than 6 dB over 40 ms, at
least 60 ms after the previous one, reported at its local peak.
usage: hits.py WAV T0 T1"""
import sys
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfiltfilt
src, t0, t1 = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
rate, data = wavfile.read(src)
if data.ndim > 1: data = data.mean(axis=1)
data = data.astype(np.float32) / 32768.0
seg = data[int(t0 * rate): int(t1 * rate)]
sos = butter(4, [40, 400], btype="band", fs=rate, output="sos")
low = sosfiltfilt(sos, seg)
hop = int(0.005 * rate)
frame = hop / rate  # the real hop in seconds (R24-02: 110 samples at 22 050 Hz is 4.989 ms, not 5)
rms = np.array([np.sqrt(np.mean(low[i:i + hop] ** 2)) + 1e-9 for i in range(0, len(low) - hop, hop)])
db = 20 * np.log10(rms)
onsets = []
last = -1
for i in range(8, len(db)):
    if db[i] > -60 and db[i] - db[i - 8] > 6 and (i - last) * frame > 0.06 and db[i] >= db[i - 1]:
        # local peak within the next 30 ms
        peak = i + int(np.argmax(db[i:i + 6]))
        onsets.append((t0 + peak * frame, db[peak])); last = peak
print(f"{len(onsets)} hits in {t0}-{t1}s")
prev = None
for t, level in onsets:
    gap = "" if prev is None else f"+{t - prev:.3f}"
    print(f"  {t:7.3f}s  {level:6.1f} dB  {gap}")
    prev = t
