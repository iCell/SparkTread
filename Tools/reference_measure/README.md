# Reference measurement record (ADR-0011)

The minimal reproducible record behind the numbers in
`docs/CURRENT_REVIEW.md` "Reference audio and transitions". No media is
committed: anyone with the public recording regenerates the measurements
with these scripts. The original 2026-09-10 artifacts were lost with a
machine restart; the numbers in the docs are the reported results of this
procedure and are not independently re-verified until someone reruns it.

## Source

- Public gameplay video of the reference game (决战坦克), Bilibili id
  `BV14b411K7bv` (≈50 min, 32 stages, no loss shown).
- Audio: format `30216` (AAC 67 kbps) extracted to WAV; video: format
  `30011` (480×360, HEVC, 30 fps). Both start at t = 0.061 s; the
  timestamps below are positions in these files.

```sh
python3 -m venv .venv && .venv/bin/pip install numpy scipy matplotlib
yt-dlp -f 30216 --no-playlist -x --audio-format wav -o "tank_reference.%(ext)s" "https://www.bilibili.com/video/BV14b411K7bv/"
yt-dlp -f 30011 --no-playlist -o "tank_reference_video.%(ext)s" "https://www.bilibili.com/video/BV14b411K7bv/"
```

Bilibili rate-limits repeated fetches (HTTP 412); wait and retry.

Environment used for the 2026-09-10 measurements: macOS 15 (Darwin 25.6),
yt-dlp 2026.08.19, ffmpeg 9.0.1, Python 3.14.7, numpy 2.5.3, scipy 1.18.1,
matplotlib 3.11.1. Keep downloaded media and generated clips in a research
directory OUTSIDE the repository (this directory holds code only).

## Decoding and amplitude treatment

- `yt-dlp -x --audio-format wav` decodes the AAC track with ffmpeg to
  16-bit 2-channel PCM AT THE SOURCE'S SAMPLE RATE (48 kHz was observed on
  the 2026-09-10 file before it was lost; do not assume 44.1 kHz — record
  the reacquired WAV's `ffprobe` metadata here). Every script reads the
  file's own rate, averages the two channels to mono, converts int16 to
  float by dividing by 32768, and (except `bands.py`, which works at the
  file rate) resamples to 22 050 Hz with `scipy.signal.resample_poly`.
- Levels are dBFS of that float signal (0 dB = full scale of the decoded
  file). They describe the recording's mix, not the game's output level;
  relative shapes are what the synthesis reproduces, because the builder
  peak-normalises every file.
- Media hashes: record `shasum -a 256` of the downloaded `.m4a`/`.mp4` and
  of the decoded `.wav` here when the media is reacquired (the 2026-09-10
  files were lost before their hashes were recorded).

## Timebase

- Both streams carry the same container `start_time = 0.061 s` (about two
  video frames at 30 fps, 33.3 ms each). ffmpeg's `-ss` seeks on container
  PTS; the WAV's sample zero is the first decoded audio sample. All table
  times are seconds from the WAV's sample zero / the first decoded video
  frame, i.e. both tracks rebased the same way. Whether that rebasing
  pairs audio and video correctly is NOT settled by arithmetic on the
  offset (it is not applied or subtracted anywhere) — it is settled only by
  the alignment check below, which found audio and frame times agreeing
  within one video frame on the 2026-09-10 files. Any rerun must repeat
  the check before trusting the tables, and must re-validate it if the
  extraction commands or the seek method change.

## Analysis parameters

| Script | STFT | Window | Hop | Bin width |
| --- | --- | --- | --- | --- |
| `measure.py`, `onsets.py`, `compare.py` | 512 samples at 22 050 Hz (23.2 ms) | Hann (scipy default) | 110 samples (5.0 ms) | 43.1 Hz |
| `fine.py` | 1024 samples (46.4 ms) | Hann | 55 samples (2.5 ms) | 21.5 Hz |
| `bands.py` | one FFT of the whole window | Hann | — | 250 Hz bands, 20 ms RMS envelope |

Peak frequencies are the STFT bin with the largest magnitude, so they are
quantised to the bin width; note pitches were rounded to the nearest
equal-tempered note within that uncertainty. Overlapping sources (an
engine burst under a glide, two explosions) contaminate band shares and
envelopes; the windows in the tables were chosen where the target sound
dominates, and readings taken where it does not are marked uncertain in
the docs.

Example: `python3 fine.py tank_reference.wav 43.14 43.52` prints one line
per 2.5 ms — time, level in dB, the three strongest peaks below 4.1 kHz,
the strongest peak above 4.3 kHz and their sum. For the shot glide the
first column of peaks descends from ≈3.06 kHz to ≈0.6 kHz over ≈0.19 s; the
sum column is what the native-rate hypothesis reads.

## Status

The numbers in `docs/CURRENT_REVIEW.md` were produced with this procedure
on 2026-09-10; the media and outputs were lost the same day. Later that
day the AUDIO was reacquired (format 30216 → `tank_reference.wav`,
48 kHz, 2 channels, sha256 prefix `df9ad4771af3c7d6`) and three
representative measurements were regenerated with these scripts and
matched the documented numbers: enemy destroyed (band spectrum and
envelope at 21.87–22.70 s identical), pickup collected (note track at
104.74–105.10 s: 1012, 517, 1615, 1012, 797 Hz…), shot glide (3058 Hz at
43.17 s to 668 Hz at 43.35 s). The VIDEO was not reacquired, so the
alignment check was NOT rerun; the audio record is re-established, the
audio↔frame pairing still rests on the 2026-09-10 check. The stage-
transition measurements (results bed, stage-card bed, first-card thump)
were made on the reacquired file.

## Timebase alignment (do this first)

Seek the video with output-side seeking (`-i file -ss T`, frame-accurate)
or input-side seeking (`-ss T -i file`, accurate on this file); the
`fps=1,tile` contact-sheet method drifted by ≈5 s on this file and must
not be used for timing. Check: the enemy kill at the top of the map whose
score roll runs 000012 → 000024 → 000048 → 000056 over 21.85–22.05 s
coincides with the rumble onset at 21.87 s in the audio.

## Sound windows (seconds)

| Sound | Window(s) | Script |
| --- | --- | --- |
| shot glide (uncertain) | 43.14–43.52, 43.1–44.8 (run at 0.2 s), 87.5–91.0 | `fine.py`, `measure.py`, `onsets.py` |
| tread burst (uncertain) | 17.7–19.3, 46.5–53.5 | `measure.py`, `bands.py` (18.50–18.78, chirp 18.66–18.78) |
| enemy destroyed (confirmed) | 21.8–22.8 | `bands.py` (21.87–22.30 crunch, 22.30–22.70 tail), `frames.sh 21.85` |
| heavy explosion | 98.5–99.5, 100.2–101.0, 103.5–104.2 | `bands.py` (98.50–98.68 hiss, 98.70–99.30 rumble) |
| pickup collected (confirmed) | 38.08–38.56, 104.70–106.40 | `fine.py` (note list), `frames.sh 38.08`, `frames.sh 104.72` |
| steel click | 102.24–102.50 | `fine.py`, `bands.py` (102.30–102.42) |
| tally blips | 77.3–77.8 | `measure.py` |
| stage card slide | 79.1–79.9 | `measure.py` |
| results drum riff | 73.9–78.4 (`hits.py 73.5 78.4`: ≈37 low hits in groups of 5–7, ≈0.12 s apart, ≈0.24 s between groups) | `hits.py`, `measure.py` |
| stage-card drum riff | 78.2–80.9 (`hits.py 78.2 80.9`; single hit timbre `fine.py 76.19 76.33`, `bands.py hit:76.195:76.31`) | `hits.py`, `fine.py`, `bands.py` |
| first-card thump | 8.4–9.6 (`bands.py` first_card:8.55:9.25) | `measure.py`, `bands.py` |

Native-rate hypothesis: `fine.py` prints the strongest peak below 4.1 kHz
and above 4.3 kHz per frame; pairs that sum consistently (3058+5319,
2433+5922) suggest ≈8.36 kHz sample-repeat playback. Pairs that do not sum
consistently (2692+5017 = 7709) are harmonics or unrelated and must not be
counted.

## Transition windows

| Moment | Window | Script |
| --- | --- | --- |
| stage card, title slide, reveal, title flip | 8.9–12.4 | `frames.sh 9.4 3.0 5` (strip), `frames.sh 10.9 1.5 20` |
| mission complete text rise | 71.8–76.0 | `yellowtext.py` (centre of yellow pixels per frame) |
| results panel, next card, reveal | 74.0–84.0 | `frames.sh 74.0 10.0 2` |
| scene changes (all cards) | whole video | `ffmpeg -vf "select='gt(scene,0.35)',showinfo"` |

## Scripts

- `measure.py WAV OUT.png T0 T1` — 5 ms peak-frequency / level /
  band-share / flatness table and a spectrogram of the window.
- `fine.py WAV T0 T1` — 2.5 ms tracks with three strongest low peaks and
  the strongest high peak (mirror pairs).
- `bands.py WAV name:T0:T1 …` — 250 Hz band spectrum (dB rel. max) and a
  20 ms RMS envelope per window (envelopes are relative shapes).
- `onsets.py WAV T0 T1` — onsets of the 2.6–3.4 kHz tonal glide.
- `hits.py WAV T0 T1` — low-band (40–400 Hz) drum-hit onsets with levels
  and inter-onset gaps (the stage riff).
- `rhythm.py WAV T0 T1` — heuristic rhythm string (short/long inter-onset
  intervals) from low-band envelope peaks; used on the six stage
  transitions below.
- `clean.py WAV name:t0:t1 …` — isolation score for excerpt candidates
  (levels before/inside/after the window).
- `envplot.py WAV OUT.png t0:t1 …` — stacked low-band/full-band envelopes.
- `frames.sh VIDEO T [DURATION FPS]` — frame strip or single frame with
  accurate seeking.
- `blobs.py FRAMEDIR T0 [MIN MAX]` — moving-object blobs between
  consecutive frames (bullets, tanks, spawn flashes).
- `yellowtext.py FRAMEDIR T0` — position of yellow UI text per frame.
- `results_screens.py VIDEO OUTDIR` — results-screen survey: reward text,
  finished table, score counter and next stage card per screen (ADR-0012).
- `compare.py OUT.png ref.wav=synth.wav …` — side-by-side spectrograms of
  reference clips and the builder's output (`SPARKTREAD_AUDIO_OUT=… python3
  Tools/build_audio_assets.py`).

## Stage-transition rhythm analysis (2026-09-10, heuristic; HISTORICAL — the opening sound turned out to be a different reference, see below)

`rhythm.py` on six transitions of the reacquired recording — 77.3–80.4,
8.4–9.4, 152.5–156.0, 255.4–259.0, 391.0–394.2, 497.4–500.4 s (and
78.1–80.8, 497.3–500.8 s at the two card starts); `envplot.py` on
73.6–80.4, 152.4–156.2, 255.3–259.2, 390.6–394.4 s; `hits.py` grouping at
a 0.18 s gap around the scene changes at 8.9, 78.27, 153.6, 256.5, 391.73,
497.73, 576.3, 659.63, 748.5 and 842.8 s. Findings: one continuous
low-band drum texture runs from the results screen through the stage card
into the first second of play, with a recurring ≈0.30 s gap (e.g. 79.62 →
79.91 s, 499.24 → 499.54 s) that may be a loop boundary; the first stage
card (8.54–9.13 s) carries six hits then silence. The analysis did NOT
isolate a distinct stage-start phrase or the owner's 6-6-1-4 figure. The
owner then identified the opening reference as the NES Battle City jingle
(second reference below); the 决战坦克 riff is the END-of-stage sound only.

## Extraction (owner's creative decision 2026-09-10: use the original sounds; rights review pending)

`Tools/extract_reference_audio.py` (repo root, stdlib) cuts the isolated
instances listed in its `CUTS` table from the pinned recording and writes
the assets; `clean.py` isolation (silent 60 ms margins) chose the
instances: shot 185.290–185.630 s, enemy destroyed 21.860–22.720 s, heavy
explosion 100.200–101.000 s, pickup 104.740–105.480 s, click 102.260–
102.480 s; the end-of-stage passage 74.000–78.200 s is the exception (a
continuous loop, faded). The `CUTS` table is the authority; earlier card
windows (74.000–76.620, 78.220–80.450 s) are withdrawn — the stage card is
not an excerpt. Run with `SPARKTREAD_REFERENCE_WAV` pointing at the
decoded source; the script refuses any file whose sha256 is not the
pinned one.

## Second reference: NES Battle City stage-start jingle (not extracted)

The owner's opening-sound reference is `https://www.youtube.com/watch?v=_vgaq3LmVak`
(“任天堂坦克90全音效 Battle City 90 Namco”, 36 s, 44.1 kHz stereo). The
jingle occupies 2.63–7.2 s (the first 2.6 s are silent). Measured with
`measure.py 0 8`, `fine.py 0 7.5` (pulse melody ≈ 517–1055 Hz with a
triangle bass ≈ 194–345 Hz) and `hits.py 0 7.5` (noise drums on a ≈0.15 s
sixteenth grid, ≈100 bpm). Namco's music: no excerpt is committed or
shipped; the game's stage-start jingle is an original composition in the
same idiom (`Tools/build_audio_assets.py`, attribution `inspired`).

## Results screens and stage-clear bonuses (2026-09-10, ADR-0012)

`results_screens.py VIDEO OUTDIR` surveys every "Mission Complete" screen
of the first recording (30 of 32 stages were decodable from a 91 %
download; scan the top 480×70 strip at 1 fps for the yellow title, runs of
≥ 3 s). Per screen it crops, for reading by eye (no OCR): the rising
"Reward +N" text (yellow, text-shaped, above the panel border), the
finished table (run end + 0.7 s), the score counter at the run's start
and end, and the next stage card (+3.0 s). Findings and readings are in
ADR-0012 and `docs/CURRENT_REVIEW.md`: four rows × two categories with
×1…×4 multipliers and a weighted total; a constant tally bonus and reward
per stage bracket (200/330, 600/660, 1000/1000 at stages 1–10, 11–25,
26–30); the recording's two continues coincide with the bracket changes
(ambiguity recorded). Frame geometry assumes the 480×360 encode; the
yellow mask is `r > .75, g > .65, b < .35, r − b > .5` as in
`yellowtext.py`.
