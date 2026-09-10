# ADR-0011: Reference-Derived Sound Set and Stage Transitions

Status: Accepted by the owner on 2026-09-10 ("3 正确"), including the shot attribution and the rights decision ("4 正确"): the owner accepts the use of the excerpts, the synthesized voices and the original jingle with no third-party licence held  
Date: 2026-09-10  
Related: plan §12.4, §12.6, §12.7; manifest §M; ADR-0005; `docs/CURRENT_REVIEW.md` "Reference audio and transitions"

## Context

The owner is not satisfied with the provisional 8-bit sound set and asked,
on 2026-09-09/10, to replicate the reference game's sound effects and its
transitions ("复刻它的音效，过场"), supplying a complete gameplay recording
(a public video of the reference, 32 stages, ~50 min). Repository policy
(plan §12.7, manifest §M) allows extracted reference audio for research only
until the owner records a rights decision; nothing extracted ships.

We measured the recording instead of copying it: STFT peak/level tracks at
2.5–5 ms hops, band spectra, note lists, and frame-accurate video reads to
tie each sound to what happens on screen. The numbers live in
`docs/CURRENT_REVIEW.md`. They are Claude's reported measurements, not
independently re-verified: the research clips, spectrograms and scripts
were lost with a machine restart on 2026-09-10. The reproducible record —
source id, timebase alignment check, per-sound and per-transition windows,
and the measurement scripts, without media — is `Tools/reference_measure/`;
a fidelity sign-off needs someone to rerun it on the public recording.

Findings that shape the decision:

- Audition hypothesis: the reference appears to render its samples near
  8.36 kHz — two measured mirror pairs sum to 8377 and 8355 Hz
  (3058 ↔ 5319, 2433 ↔ 5922). A third pair quoted earlier (2692 ↔ 5017,
  sum 7709) does not fit and is withdrawn. The source's true rate, bit
  depth and reconstruction filter are not established.
- Confirmed pairings (audio onset within one frame of the on-screen
  event): enemy destroyed → 0.8 s low rumble; pickup collected → a 650 ms
  arpeggio (C6 C5 G6 C6 G5 C5 G6 E5 G5 C5 G6 C6 G5 C5) with a decaying
  envelope; a second, heavier explosion (0.2 s hiss + 0.6 s rumble) on some
  kills.
- Unconfirmed pairings (the video's resolution does not show bullets
  reliably): the most frequent tonal event — a pulse wave gliding
  3.1 kHz → 0.5 kHz over ≈0.26 s, fired in runs at 0.2 s — is taken as the
  shot; a 300 ms noise burst with a 2.3→3.0→2.2 kHz chirp, retriggered
  every 400 ms, is taken as the engine. What triggers the reference's
  engine is unknown: bursts were heard while the player stood still and
  silence while an enemy kept moving, which fits neither "held input" nor
  "any moving tank". Both pairings are owner-checkable in one sentence.
- Everything else in the set (rapid/special launch variants, heavy
  explosion, base collapse, pickup appearance, steel/brick/deflect, tally
  tick, stage card, win/loss stingers) is DERIVED material — variants built
  in the same voice from the measured sounds, or invented where the
  recording has nothing (there is no loss in it).
- Transitions (frame-accurate): stage card with the title sliding in from
  the left (1.0 s) and holding (≈1.3 s); the playfield revealed as a cross
  of cell strips growing from the centre (≈0.45 s); the title flips away
  (≈0.4 s); the HUD appears and play starts. On the last kill nothing plays
  for ≈1.7 s, then "Mission Complete" rises from the centre to the top
  (0.35 s) and holds ≈2.4 s, the playfield darkens (0.5 s), a results table
  of kills by enemy type slides in from the left (0.5 s) and counts up with
  ticks, then the next stage card follows automatically. The video contains
  no loss, so the loss variant was ours — until the owner (2026-09-10 late
  evening, "过关之后的音乐怎么时好时坏，需要用决战坦克的那个音效") had the invented
  loss stinger removed: the results passage plays at every stage end.

## Owner's creative decision of 2026-09-10 (recorded; NOT a rights decision)

After hearing the re-synthesized candidates on the device the owner
directed, verbatim: "我不是让你重做，是让你采用决战坦克原版的开场音效，我要求音效是复刻原版的"
— the sounds are to BE the original 决战坦克 sounds, not re-creations.

What that changes: `Tools/extract_reference_audio.py` cuts the cleanest
isolated instance of each sound the public recording contains (silent
60 ms margins, checked with the isolation score in the measurement record;
the two stage-transition excerpts are the exception — cut from a
continuously sounding passage and faded)
from the pinned source (sha256 df9ad477…), resamples it deterministically
to 22 050 Hz mono, and writes it as the asset; `Tools/audio_manifest.json`
marks these files `"attribution": "excerpt"` with their source window,
processing, file hash and the extractor's hash, and `Scripts/check-audio.sh`
verifies all of it (re-extracting and comparing bytes and metadata when
the source is at hand). These are PROCESSED EXCERPTS OF A GAMEPLAY
RECORDING, not the game's original asset files. Excerpts today: the end-of-stage
loop (results, 4.2 s), the shot (one 340 ms clip under the
normal, rapid and special names — one isolated launch instance was
selected; whether the reference has other launch sounds is not
established), enemy
destroyed, the heavy explosion, the pickup jingle, the click (assigned to
steel/boundary by sound design, not by an observed cause). Every other
voice has no isolated instance in the recording and stays synthesized
(derived or invented), listed as such in the manifest, until the owner
points at one.

What it does NOT change: the distribution-rights review for these
excerpts — and for the synthesized voices — is PENDING
(`ASSET_PRODUCTION_MANIFEST.md`, audio and provenance sections). The
owner's instruction is a creative decision; it is recorded separately
from, and does not substitute for, that review. The manifest carries both
statements (`creative_decision`, `rights_review`). Nothing in this ADR
promotes the excerpts to approved shipping resources; local technical
evaluation and audition are what they are cleared for.

## Owner's opening-sound reference and the rights workaround (2026-09-10, later)

The owner then corrected the opening reference: not the 决战坦克 riff at all,
but the first seven seconds of a second video, the NES Battle City
(坦克 1990) sound-effects compilation — Namco's stage-start jingle (two
pulse voices, a triangle bass, noise drums on a 0.15 s sixteenth grid at
≈100 bpm, 4.6 s, a march-like fanfare rising to a cadence; measured at
2.63–7.2 s of that video). The owner asked whether it involves copyright
and whether it can be avoided ("但是不是涉及到版权，可以规避一下吗"). Answer
recorded: yes — the composition and the recording are Namco's; playing an
excerpt or re-creating the melody note for note would reproduce it.
Workaround chosen: an ORIGINAL composition in the same idiom. The owner
heard the first cut and asked for a near-copy of the melody with slight
changes "to avoid copyright"; Claude declined to build that (slight
changes do not avoid copyright — they would write the risk into the
product) and offered three paths; the owner chose to keep the original
composition and push it in the reference's DIRECTION ("选择 1 吧，尽可能按
照原版的方向走就好"). Applied: `sfx_stage_card` follows the reference's
key and mode (C minor), tempo (≈103 bpm), rhythmic skeleton
(short-short-long motif twice, a zigzag phrase, a climb, a rest, a
repeated-tonic ending), register, instrumentation (25 % pulse lead,
octave doubling, triangle bass, a noise hit per note) and length
(≈4.66 s), with its own note sequences and contours — a leaping triad
motif where the reference steps, a descending zigzag where it ascends, a
turning climb, a different closing figure; no note run of the reference
is reproduced. The owner auditioned it on the device and accepted it
("开场曲子我觉得可以"), and confirmed the end-of-stage music stays the
决战坦克 results excerpt ("结束曲还是用决战坦克的那个"); the rights review for
the excerpt stays pending. `sfx_stage_card` is generated by `Tools/build_audio_assets.py`
with attribution `inspired` and the second reference recorded on its manifest
entry (4.8 s phrase, ≈4.95 s file with the closing crash's tail;
it overlaps the first ≈1.8 s of play, as reference context suggests the
NES original does — reduce or duck it if launch/spawn cues suffer, rather
than delaying control); no excerpt of the Battle City jingle enters the
repository, and the provisional 决战坦克 card excerpt is withdrawn. This is
the owner's decision on approach, not a legal clearance; the rights review
for the whole set stays pending. The end-of-stage excerpt (the 决战坦克
results passage) is unchanged.

## Decision (proposed)

1. **Re-synthesis as the candidate production method for voices without an excerpt — not clearance.**
   The candidate set is generated by `Tools/build_audio_assets.py` from
   the measured parameters (glide endpoints and rates, band shapes,
   envelope shapes, note lists), rendered at `NATIVE_RATE = 8363` and
   upsampled by zero-order hold. Deterministic and byte-reproducible like
   the rest of the builder (PI regenerated it twice outside the repository
   and matched all 28 files). It is PROVISIONAL: reproducibility is not
   acoustic acceptance, and re-synthesis of a recognisable melodic figure
   or effect is not automatically free of rights questions. Shipping it
   requires the owner's audition AND a recorded provenance/rights review,
   the same review the extracted originals would need. If that review
   later permits the originals, swapping WAVs is a content change, not an
   architecture one. Per-file peak normalisation means the measured dBFS
   envelopes are relative shapes, not calibrated levels; the mix and
   headroom are unverified.
2. **Event mapping (current).** Launches `normal`, `rapid`, `special` →
   the same 340 ms excerpt of the isolated shot (185.29 s); `ap`,
   `explosion`, `fire`, `mine` launches → synthesized (no excerpt); enemy
   destroyed → the 0.86 s kill excerpt (21.86 s); player destroyed → the
   0.80 s heavy-explosion excerpt (100.20 s); base destroyed → synthesized
   (derived from the heavy explosion's shape); pickup collected → the
   0.74 s jingle excerpt (104.74 s); pickup appears → synthesized (derived
   figure); steel and boundary → the 0.22 s click excerpt (102.26 s, an
   assignment, not an observed cause); brick, deflect → synthesized;
   results tally → synthesized 3.14/1.85 kHz blips; stage card → the ORIGINAL
   NES-style stage-start jingle in the reference's direction (≈4.66 s;
   attribution `inspired`; see the opening-sound section above — not an
   excerpt, not a transcription) at the card cue; stage won →
   the end-of-stage loop excerpt (74.00–78.20 s, the results screen from its
   rise to the card) at the outcome-text cue; stage lost → the same
   excerpt (owner, 2026-09-10 late evening; the invented falling variant
   was removed). Excerpt processing: mono mix, 147/320 polyphase
   windowed-sinc resample (64 taps, Hann, cutoff 0.92 of the output
   Nyquist), DC removal, 2–5 ms fade-in, 15–80 ms fade-out, peak 0.8. Cue
   anchors are adapted: the riff excerpts start at t = 0 of their cue;
   the recording's own riff runs continuously from the results into the
   next card. The excerpts are not a transcription of the owner's 6-6-1-4
   phrasing; they are the recording's riff as recorded. HISTORICAL (no
   longer shipped): the first cut's tonal slide, the throbbing bed, the
   synthesized 6-6-1-4 riff and their spectral comparisons.
3. **No engine sound (owner decision, 2026-09-10).** The reference's
   300 ms burst was never attributed with confidence; after hearing the
   candidate on the device the owner decided the game does not need a
   tread/engine sound. The voice, the retrigger and their tests are
   removed; the measurement stays in the record.
4. **Stage flow.** `GameApplication.StageFlow` is a pure tick timeline —
   card 138, reveal 26, title-out 24; outro delay 100, text 21, hold 145,
   fade 30, panel-in 30, panel-hold ≥110 ticks (stretched to fit every
   results row plus a settle) — that gates the simulation
   (`allowsSimulation` only in `playing`) and emits cues the controller
   maps to sounds. A won stage continues by itself into the same stage
   again (a provisional prototype loop, not campaign progression; lives and
   score reset with the world, and the completed recording is kept on the
   controller for export); a lost stage holds the results with the restart
   button. The scene lifts a per-cell curtain in the growing-cross order;
   SwiftUI animates the title, outcome text, fade and panel with the
   measured durations. Input admission is ONE policy: input is accepted
   only while the clock runs and the flow is in play; every transition
   releases everything held or pending and advances the reset watermark,
   so cutscene presses and callbacks queued across the boundary never reach
   the first gameplay tick. Transient presentation effects age on the
   scene's presentation clock, not the world tick, so the decisive tick's
   explosion plays out during the outro. Core replay is unaffected: the
   flow never touches world state, the session is not stepped while it
   holds, and playback lengths are simulation ticks; a transition itself is
   presentation state and is not reconstructed from a recording.
5. **Results table.** `KillTally` derives kills by archetype from
   `tankDestroyed` events (pre-step archetype snapshot), presentation-side;
   GameCore gains no counters. The reference's stage-clear "Reward" bonus is
   NOT implemented: it is a scoring rule and needs its own owner decision.

## Consequences

- Golden replays, checksums and the content validator are untouched.
- Two acceptance checks belong to the owner on the device: whether the
  glide is indeed the shot and the burst the engine (assumptions above), and
  whether the synthesized set is close enough to the reference. Either way
  a provenance/rights review must be recorded before the set counts as
  shipped; choosing synthesis over extraction does not substitute for it.
- The lab world skips the intro (flow starts in `playing`); injected test
  worlds without a stage do the same, so existing controller tests hold.
- Follow-ups: sprite icons in the results rows (the reference shows tank
  icons), a stage-clear reward rule, and a title screen — none are in this
  ADR.
