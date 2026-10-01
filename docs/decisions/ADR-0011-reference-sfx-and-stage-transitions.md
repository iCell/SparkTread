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

## Stage-start cue restyled to match the stage end (2026-09-15)

The owner found the opening and the stage-end music mismatched and asked for
a new opening in the stage-end music's style ("开场音乐和结束音乐感觉风格对不上，
你生成一个和结束音乐风格类似的开场音乐"). The stage end is the 决战坦克 results
excerpt: a sampled drum loop with no clear melody. The NES-style jingle was
square-wave chiptune and about 9 dB louder, so both timbre and level clashed.

Measured on the bundled excerpt: hits on a ≈0.118 s sixteenth grid (≈127
bpm), in groups of 4–7 with one empty step between groups; kick ≈55–75 Hz,
toms ≈140–230 Hz ringing 250–400 ms, broadband snare strokes, a cymbal wash,
a room that never falls silent, a few faint harmonic stabs near C5/G5/B♭5,
≈−21 dBFS RMS. Applied: `sfx_stage_card` is now an ORIGINAL drum-led
composition in that idiom, generated by `Tools/build_audio_assets.py` at the
native 8363 Hz with 8-bit quantisation and ZOH upsampling. It has its own
two-bar pattern with a closing hit (≈4.88 s with the cymbal tail,
≈−19 dBFS RMS) and a C-minor stab arpeggio (C, E♭, G, B♭ → C). No hit
pattern of the excerpt is reproduced and none of its audio is used;
attribution stays `inspired`, with the new model recorded on the manifest
entry. The NES-style jingle and its Battle City direction are retired; the
rule against Battle City audio or copies of its melody stands. The owner's
device audition is pending; the rights review for the whole set stays
pending.

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
   drum-led cue in the idiom of the results passage (≈4.88 s; attribution
   `inspired`; see the 2026-09-15 section above — not an excerpt, not a
   transcription) at the card cue; stage won →
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

## Amendment 2026-09-16: one style — the reference recording's

The owner reviewed the cue set and found the stage-entry cue clearly
inconsistent with the rest ("进入关卡的音效明显不一致"), keeping every
reference-excerpt sound, and asked for inconsistent cues to be changed and
unneeded ones removed. Three changes, all regenerated through
`Tools/build_audio_assets.py` and verified by `Scripts/check-audio.sh`:

1. **`sfx_stage_card` is now derived from the stage-end excerpt's own
   strokes.** The 2026-09-15 original drum composition is replaced — first
   (briefly, same day) by a plain 3.6 s slice of the `sfx_stage_win`
   results-passage excerpt, then, on the owner's follow-up ("开场曲不要和
   结束的一样的，设计一个和结束曲风格一致且很有动感的节奏"), by an
   ORIGINAL two-bar pattern re-sequenced from that excerpt's own drum
   strokes: the excerpt is grid-sliced at its measured ≈0.118 s sixteenth,
   kick/snare/tom/tick/wash slices are chosen by deterministic band-energy
   analysis, and re-arranged as four-on-the-floor kick, backbeat snares,
   off-beat ticks, tom fills and a final accent with the excerpt's own
   wash (4.26 s, ≈45 % denser in actual strokes than the source). Same
   tempo, room and one-step-rest idiom as the stage end — but not the
   same audio. Attribution moves "inspired" → "derived".
2. **Every synthesized cue now uses the native 8363 Hz pipeline.** Eleven
   provisional cues (`fire_ap/explosion/flame`, `flame_loop`, `hit_tank`,
   `dry_fire`, `explosion_blast`, `base_hit/own_hit/shield_on`,
   `spawn_warp`) were plain 22050 Hz synthesis while the derived set went
   through `native()`; the recipes are unchanged but now carry the same
   ZOH sample sheen as the reference excerpts. The flame loop's seam was
   measured before keeping it native (discontinuity below the bed's own
   p90 transitions).
3. **`sfx_mine_place` removed** — the mine mechanic left with R5
   (ADR-0018); the cue was unreachable.

The excerpt set (8 files) is byte-identical to before. Standing rules
unchanged: no Battle City audio; the stage-end excerpt serves both
outcomes.

## Amendment 2026-09-10 (late evening): the outro is a designed transition

The owner asked for a better stage-end transition for every outcome
("可以设计一个好一些的转场") and a centred results page. The intro keeps the
measured reference timeline above; the outro no longer copies the
reference's rise/darken/slide: it freezes 0.8 s, stamps the outcome title
into the centre with a flash (and a shake on a loss) over a one-line
reason, holds 1.4 s, closes the playfield under a box-iris curtain from
the edges to the centre while the title glides to the top (0.7 s), and
pops the results card in at the centre (0.35 s). The tally, reward and
automatic continue are unchanged (ADR-0012). `docs/CURRENT_REVIEW.md`
"Designed outro" records the details.

## Amendment 2026-09-25: the card matched to the stage end, and one mix pass

The owner asked for a review of all art and audio and, for the audio, to
"align the opening style with the ending audio style". The 2026-09-16 card
already used the stage end's OWN strokes, so its timbre and tempo could not
drift — but measured side by side with `sfx_stage_win` it still did not sit
with it, on three counts that the ear reads as "a different kind of sound":

1. **It was gated.** Ten of its thirty-six 118 ms steps were digital
   silence, while no step of the excerpt falls more than 9 dB under its
   loudest and no 5 ms pocket inside it drops below ≈−36 dBFS: a sampled
   room never stops. The pattern now plays over a room bed made from the
   excerpt's own band above 2 kHz — grains half-overlapped under a Bartlett
   window, read from positions advancing five eighths of a step so no grain
   lands on the source's grid, every other grain reversed, so neither a
   transient nor a groove survives; the bed sits 11 dB under the pattern.
   Measured floor after the change: −28.2 dBFS against the excerpt's −27.3.
2. **It was 2.7 dB quieter** (−23.5 against −20.8 dBFS RMS). The card is
   now levelled to the excerpt's own measured RMS instead of a constant, so
   a re-extraction re-levels it; the peak is capped at 0.9, which costs
   0.4 dB of that parity and keeps headroom for the stage change, where the
   results passage is still ringing when the next card starts.
3. **It crescendoed** from ≈−28 dBFS to ≈−18 at the accent where the
   ending drives flat from its first stroke. The 0.85 gain on bar one is
   gone; only fills and the closing accent lift.

The phrase is also two bars of TWELVE sixteenths rather than sixteen. At
the measured tempo that puts the closing accent at 2.83 s, where the intro
hands over to play (card 2.3 s + reveal 0.45 s + title-out 0.4 s = 3.13 s,
`StageFlow.Durations`), so the last stroke lands with the playfield instead
of ≈0.9 s inside gameplay; only the accent's wash rings past, to 3.32 s.
Everything else holds: same samples on the same measured grid, an original
pattern and never the stage end's own passage, no synthesized instruments
in this cue, no Battle City material, the stage-end excerpt unchanged for
both outcomes, and the 8 excerpts byte-identical.

Separately, the whole set's levels were measured together for the first
time. `write_native` peak-normalises each voice on its own, never against
the others, and three cues had ended up contradicting their importance: a
shield raise / base repair was the loudest sound in the product at
−7.3 dBFS RMS (over the player's own death at −10.2 and a base
breakthrough at −9.2), the results tally tick at −8.6 stabbed 12 dB over
the music it counts against, and the wave-spawn warp at −10.2 out-shouted
every weapon launch while firing on every wave and every director phase.
Their generator peaks alone were changed: `sfx_base_shield_on` → −16.2,
`sfx_tally_tick` → −18.1, `sfx_spawn_warp` → −16.4 dBFS RMS. No recipe,
envelope or frequency moved, and no excerpt can move by construction.
`sfx_fire_ap` stays 6 dB above the other launches (the owner asked for a
missile that sounds serious) — recorded for the device listen rather than
changed. The audio mix is still unverified on hardware; these are measured
corrections to a hierarchy, not an acceptance.

## Amendment 2026-10-01: three cues reworked on the owner's listen

The owner auditioned the whole bundled set and named three: `sfx_fire_explosion`
"有点闷，和别的音效感觉不太符合", `sfx_explosion_blast` "也有点闷",
`sfx_base_shield_on` "觉得很滑稽，有点奇怪". Each had a measurable cause, and
each is reworked rather than merely re-levelled. Band figures below are
each band's RMS relative to the whole cue (a tilt profile), in the split
<150 / 150-400 / 0.4-1k / 1-2.5k / >2.5k Hz.

**`sfx_fire_explosion` (demolition launch).** It was led by a 160→65 Hz
square glide, and measured −7.8/−5.5/−7.7/−9.4/−8.8 against the reference
shot excerpt it plays beside (−16.6/−15.8/−8.7/−5.3/−4.5): 9 dB heavier in
the bass and 4 dB weaker on top — a sub-bass boop among bright launches,
which is exactly "doesn't belong with the others". Now the bite leads: a
full-rate crack through a 2.6 kHz bandpass, the charge leaving as a
4200→1500 Hz hold-rate sweep across the cue, and the low push cut to 90 ms
at 0.40 gain. New profile −12.4/−12.0/−9.6/−7.2/−3.7 — still 4 dB heavier
in the bass than the normal shot, which is the weapon being heavier, no
longer the cue being muddy.

**`sfx_explosion_blast` (the shell's blast).** The reference's own
explosions centre their energy between 150 Hz and 1 kHz
(`sfx_tank_explode` −10.1/−5.7/−5.9/−8.6/−10.8). The old recipe was a
noise sweep over a 130→55 Hz square glide and sat 3.4 dB thin through
400 Hz–1 kHz, the band that carries an explosion's body, with 6 dB more
mud under 150 Hz — a dull "pff" with a boop beneath it. Now: a full-rate
crack opens it, a 700 Hz bandpassed body fills the band it was missing, a
5200→1300 Hz layer at 0.35 keeps definition, and the low end is two
shorter layers (260→90 Hz, 120→62 Hz) instead of one long glide. New
profile −15.7/−11.2/−7.1/−5.7/−5.9: tighter and brighter than the
reference's own explosions, deliberately, so a shell blast is never
mistaken for a tank dying.

**`sfx_base_shield_on` (flag guard raised, §11.2; also base repaired).** It
was a 300→640 Hz square GLIDE under a hold envelope — a rising cartoon
whoop, and the glide is what read as 滑稽. The event is the fort ring
hardening to steel, so the cue is now two metal plates locking into place,
struck rather than glided: each plate is a tone, a bandpassed noise edge
for the metal and a two-octaves-down body for the weight of plate rather
than sheet, the second strike a fifth above the first so the gesture still
reads as something good for the player, and a 1320 Hz ring that settles
instead of climbing. No glide anywhere in it.

Two mechanisms were added to the generator for this, both because the
rework exposed them:

1. **`write_native_rms(name, sig, target_dbfs)`.** `write_native`'s `peak`
   is a shape control that says nothing about how loud a cue lands — which
   is how the three cues of the 2026-09-25 pass drifted into out-shouting
   the game. Rebuilding a recipe moves its crest factor, and these three
   came out 5, 5 and 13 dB quieter than the mix pass had set them. A
   reworked cue now declares the RMS it is supposed to land at, so a
   redesign cannot quietly re-level it; the cues untouched since
   2026-09-25 keep their measured `peak` constants. A capped peak is
   printed, never silently accepted.
2. **`saturate(sig, drive)`.** All three new recipes are crack-led, and a
   lone transient set the peak with the body 16 dB under it, so none could
   reach its target loudness inside the 0.9 headroom ceiling. Soft tanh
   saturation rounds that transient and lifts the body against the peak
   instead of trading bite for loudness, and the harmonics it adds belong
   to the same 8363 Hz palette as everything else here.

All three land on the loudness the 2026-09-25 pass set (−14.9, −12.3,
−16.2 dBFS RMS against targets −14.8, −12.3, −16.2), so the owner's
comparison is timbre only. The other 14 synthesized cues and all 8
excerpts are byte-identical; `check-audio`, its selftest and the full gate
pass. The owner's listen on these three is pending.

## Amendment 2026-10-01 (later): the whole set reviewed, and the card made a gesture

The owner asked for the same standard to be applied to every cue — "确保他们
符合当前使用场景，需要的话做出更改" — and settled the two stage cues:
`sfx_stage_win` "是不用修改的很不错的音效", while `sfx_stage_card` "作为开场
音乐非常不合适，必须更改出一个配套的".

**The card is now a gesture, not a loop.** Three attempts had all been
grooves: an original drum composition (2026-09-15), a slice of the results
passage (2026-09-16, withdrawn the same day), and a two-bar pattern
re-sequenced from the passage's own strokes (2026-09-16, aligned to the
stage end's room, level and flat drive on 2026-09-25). The 2026-09-25 pass
made the card measurably match the stage end on every axis — RMS, noise
floor, band tilt, stroke density — and the owner still rejected it, which
locates the fault somewhere the measurements were not looking: FORM. The
stage end is a groove because a results screen keeps rolling; a stage card
has to announce and then hand over. A loop built from the groove's own
samples is the same music arriving in the wrong place, and no amount of
matching its texture can fix that.

So the card keeps everything that makes it a set with the stage end — the
same kit, the same room bed, the measured ≈127 bpm sixteenth grid, the same
≈−21 dBFS level, all of it still the excerpt's own strokes — and changes
only its shape: a run-up that tightens BELOW the grid (which a groove never
does, and which is most of what makes this read as an opening), a struck
statement, a short drive split by a second accent, a tom fill, and a crash
that lands at 3.12 s where the intro hands over to play, ringing 0.47 s
into it. Measured against the stage end: −20.9 against −20.8 dBFS RMS,
band tilt −7.6/−7.5/−8.6/−8.6/−6.2 against −7.0/−7.6/−8.7/−8.7/−6.4, and a
250 ms envelope that now RISES (−27 to −17) where the ending's is flat —
which is the intended difference, not a defect.

Two further shapes were built from the same strokes and sent for audition,
since this is the fourth attempt and the choice is the owner's:
`three_strikes` (four heavy strikes with a beat of room between them, the
least groove-like) and `crescendo` (one continuous accelerando from
near-silence). `SHAPE` in the generator's stage-card block selects which
one ships; `roll_hit` does, because its texture matches the stage end
closest (noise floor −27.7 against −27.3, where `three_strikes` drops to
−35.8) while still having an arc.

**The rest of the set, by the same standard.** Every cue was measured for
duration against its event's cadence, level against its importance, and
band tilt against the reference excerpts. Seven changes:

| cue | was | now | why |
|---|---|---|---|
| `sfx_fire_ap` | −10.1 dBFS | −12.8 | second-loudest cue in the product, over a tank exploding (−12.4); a launch is not a destruction |
| `sfx_base_own_hit` | −20.0 | −15.0 | under every impact cue and barely over the dry-fire click; shooting your own base has to register |
| `sfx_pickup_spawn` | −13.2 | −16.5 | 3 dB LOUDER than collecting (−16.3) — the announcement was over the reward |
| `sfx_base_hit` | <150 Hz at −20.5 | −15.8 | the loudest cue in the game had no body; figure and pitches kept, the notes gained a bandpassed edge and the shell's impact arrives under the first stroke |
| `sfx_spawn_warp` | crest 1.0 dB | 8.5 dB | a constant-amplitude bare square, the same signature as the shield whoop the owner called 滑稽 and the last one in the set; now struck and decaying, tonality 0.48 → 0.13 |
| `sfx_hit_brick` | <150 Hz at −4.3 | −13.4 | the most frequent impact in the game piled its energy below the crack; brick breaking is a dry clack |
| `sfx_base_destroyed` | >2.5 kHz at −2.8, <150 at −15.2 | −4.4 / −8.1 | the biggest explosion was almost all hiss where the reference's own carry weight |

**`sfx_fire_special` is removed.** It was a third byte-identical copy of the
shot excerpt, kept for a special-channel weapon id outside the five R5
defines. `WeaponRules` is code rather than content, so no such id can
appear without a code change that would bring its own voice: the cue could
never play. Dropped from the extractor, the manifest and the bundle (the
extractor's recorded hash is updated with it), and `GameAudio`'s fallback
now points at the normal launch. The bundled set is 24 cues, 7 of them
excerpts.

`GameAudio.poolSize` also documented a cadence that no longer exists:
rapid fire launched every 83 ms when its cooldown was five ticks, so six
voices were warmed for five overlapping clips, and R5.6 scaled that cooldown
to 20/18/15/13 ticks — a launch every 217 ms at LV3, two overlapping clips.
The six voices are KEPT as headroom (R18-01: a pool that comes up short
stays short, and two spare preloaded voices cost less than that risk); only
the comment, and the test comment that repeated it, were corrected.

Nothing here is an acceptance: the owner's listen on all of it is pending,
and the audio mix is still unverified on hardware. The 7 excerpts are
byte-identical, `check-audio` and its selftest pass, and so does the full
gate.

## Amendment 2026-10-01 (third): the card carries a tune, played on the kit

The owner, having auditioned the three drum-only shapes, asked for a melodic
opening and linked the Battle City NES "Game Start" theme as the model:
"模仿这个旋律…做一个和胜利之后的音乐配套的".

**Its melody is not copied, and not paraphrased either.** This is the third
time the question has come up — the owner raised it on 2026-09-10 asking
for a near-copy with slight changes "to avoid copyright", that was declined
then, and the standing rule against Battle City audio or a note-for-note
copy of its melody came out of it. Asking again does not change the answer,
and a slightly-altered copy is worse than a copy because it writes the risk
into the product while pretending not to. What IS taken from the reference
is its function, which nobody owns: short, rising, announcing, resolving as
play begins.

**What ships instead.** The card now carries an original twelve-note figure
in C minor pentatonic across C3–E♭4, rising through the first bar and
answering itself in the second, over quarter-note kicks and off-beat ticks,
a tom run-up, and the crash at the hand-off. The key is not borrowed
either: ADR-0011's own 2026-09-15 measurements found this excerpt's faint
harmonic stabs near C5/G5/B♭5, so C minor comes from our own material.

The interesting part is the instrument. A tune normally needs a pitched
voice, and composing the card from synthesized instruments is itself
forbidden (owner 2026-09-16). Both rules hold at once by playing the melody
on the excerpt's OWN pitched drum: the generator autocorrelates the tom band
of every grid slice, takes the most cleanly pitched one (110.8 Hz ≈ A2,
clarity 0.57 — a drum in a dense mix is never a pure tone, but enough for
resampling to read as pitch) and resamples it per note, which shortens each
note exactly as a faster replay does. Register C3–E♭4 keeps the ratios
between 1.2 and 2.8, where a pitched tom still sounds like a drum. So the
tune is in the stage end's own kit and room, with no synthesized instrument
anywhere in the cue, and the pitch is measured rather than assumed — a
re-extraction of the excerpt re-tunes the melody instead of detuning it.

Two mechanics were added: `resample`/`tom_pitch` in the generator, and a
per-shape saturation drive. Twelve short pitched hits against one closing
crash give the melodic shape a 22.7 dB crest factor where the drum shapes
have 19, and the peak cap then cost it 2.8 dB of level against the stage
end; saturating only this shape recovers it. The three drum-only shapes are
byte-identical after the change (`sfx_stage_card` under `roll_hit` hashes
the same before and after), so the audition the owner already did still
stands. Measured against `sfx_stage_win`: −20.8 dBFS RMS against −20.8,
peak −3.4 against −1.9, band tilt −10.2/−9.4/−8.4/−7.9/−4.9 against
−7.0/−7.6/−8.7/−8.7/−6.4 (resampling a tom upward naturally lightens the
bottom), and a flat drive with the crash lifting at the end. `SHAPE` selects
which of the four ships; `melodic` does. Owner listen pending.
