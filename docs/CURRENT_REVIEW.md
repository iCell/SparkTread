# Current implementation review

Date: 2026-09-09. Two independent agents (PI: gpt-6-astra, Claude: Fable
5.1) cross-reviewed the tree in seven written rounds; PI verified findings
with compiled check programs, Claude applied every change both agreed on.
This document is the state after that pass (seven rounds, closed in round
7). It is not a claim of product completion, physical-device acceptance, or
audio-content acceptance.

## Scope and authority

This is a one-stage development prototype (VS-01), not a completed V1
campaign. Accepted ADRs override the product plan; reference-game behavior
and older SVG/styleboard assets do not override those decisions. Runtime art
is the `Vendor/SparkTreadPixel` submodule; no new artwork was generated.
ADR-0010 is PROPOSED: it records owner-requested rules that were previously
implicit and needs the owner's acceptance before it carries authority.

## Corrections made in the joint review

Core (GameCore):

- Projectile contacts of a tick resolve from one global time-ordered queue
  (world contacts and projectile-versus-projectile, exact rational times,
  category/ID tie order). Crossing shots that pass at different times no
  longer cancel; an interception earlier in the tick prevents a later base
  hit in the same tick. Blasts still resolve after the queue (documented
  approximation in `Combat`).
- Negative-direction shots (left/up) meet walls at the same distance as
  their mirrors (entered-quadrant sampling).
- Penetrating shells (AP) damage each distinct tank once
  (`ProjectileState.hitTankIDs`) and keep their remaining travel; surviving
  contacts emit `projectileHit`, never a false destruction; mines disarmed
  by shots emit `mineRemoved`.
- Enemy flame patches release their active-count slot on the emitter
  (`FireHazardState.ownerEntityID`); expiry by lifetime releases slots;
  flame volleys are admitted whole or refused (dry-fire + cooldown);
  active counts are checked for exact equality by `WorldInvariants`.
- Every dry-fire path applies the channel cooldown (held special against an
  illegal placement dry-fires at cadence, not per tick).
- Protection policy centralized: spawn protection and invincibility deflect
  projectiles, blasts, flames and the bomb alike; dead tanks and a base at
  zero take nothing and emit nothing.
- Flames burn the base: one contact patch per column on the structure,
  once per fire-damage interval, through the ADR-0005 allied flag and the
  shield; the column stops at the base.
- Fort ring (base shield): occupied cells (tank/mine/pickup) are never
  rebuilt — no entombment; damaged steel hardens whole; expiry restores from
  a per-activation record (`BaseState.fortRingRestore`; steel/water
  preservation via `PickupRuleset.fortRingRestoresRecordedKinds`, default
  on since the owner's decision B of 2026-09-10; off = rebuild as brick).
- Hidden treasures reveal only when the covering cell can hold a pickup;
  the record survives a failed placement.
- Score pickups award points; `max_armor_ammo` fills the current special to
  its cap (distinct from `ammo_crate`).
- `PickupRuleset` (lifetime, grace, armor-up, invincibility floor/refresh/
  extend, base shield extend/floor, freeze, bomb damage) replaces hard-coded
  constants with identical tuning constants; validated at the loading
  boundary (`StageLoader`) and by sessions; timer sums saturate. One
  behavioural difference is deliberate and documented on the rule: a
  longer running invincibility timer is no longer shortened to 600 ticks by
  a pickup. The reference 25-second rule is available as
  `.referenceInvincibility`, NOT applied.
- Domain events carry owner identity, positions (anchors documented on
  `DomainEvent`), facing, and structured impact kinds; `baseDamaged.allied`
  distinguishes own fire (ADR-0005).

Application / adapters:

- `ReplayRecording` v2 embeds the initial world and all three rulesets;
  playback validates, before stepping: format; every embedded ruleset
  (`MovementRuleset`, `WeaponRuleset`, `PickupRuleset`) against documented
  value domains, each field range-checked before the arithmetic that
  depends on it; the world's structure (bounded arena, matching terrain
  storage) and invariants (positions inside the arena, timers/counts/armor
  inside their domains, signed bounds compared directly, incremented
  counters admitted with headroom);
  the start checksum; command envelopes (none before the initial tick, no
  duplicate tick — envelopes are mapped by tick, chronological storage is
  not required); the tick count (0…10 h) and its sum with the initial tick.
  Invalid data within those checks is a `ReplayError`; the maintained tests
  cover emptied weapon arrays, invalid pickup rules, negative initial tick,
  mismatched terrain storage, duplicate envelopes, extreme integers in the
  movement inset, a tank position, the projectile extent, the arena size,
  Int.min slide momentum, Int.max spawn cursors / telegraph index / tick /
  next entity id. Debug mutations rebase the recording. A VS-01 session started at a
  nonzero tick replays through encode/decode.
- `TickAccumulator` (ADR-0007): raw gaps longer than six ticks (with a
  floating-point tolerance valid at any uptime) are dropped as stalls
  (implicit pause, no burst); fractional remainders carry; duplicate,
  backward and non-finite timestamps never move the accepted baseline.
- Application lifecycle: `MovementLabController.start/suspend/stop` driven
  by `scenePhase`; a controller is constructed INACTIVE (audio and haptics
  suspended, input refused) until the view reports the active phase;
  suspension is a complete barrier — audio and haptics suspended, held
  inputs released, new presses refused, queued presentation events
  discarded; `start` advances the input reset watermark so a physical
  callback observed while inactive is dropped even when delivered after
  resume; bottom system gestures deferred (ADR-0004).
- Input: `HeldDirectionStore` accounts per source — each key, each CONTROL
  of each controller (object identity, not an enumeration index), touch —
  for directions AND fire (normal edge per source, special hold); key repeat
  keeps its priority slot; keyboard J/U normal, K/I special (reference
  defaults, provisional); controller A / B / X; a disconnect releases only
  that device (held inputs and its pending pulse) and invalidates the
  callbacks it queued (`DeviceGenerations`); a restart/suspension reset
  drops earlier callbacks globally.
- Audio structure: injectable backend and monotonic clock; suspend/resume/
  mute lifecycle (a new world stops one-shots too); wanted loops are
  reconciled against actual playback with a one-second retry backoff;
  exact impact voices from event payloads; player-only, throttled dry fire
  whose throttle commits only when a click actually played; base-hit
  priority per drained batch; allied own-fire voice (`sfx_base_own_hit`,
  provisional placeholder). Sound CONTENT was replaced on 2026-09-10 by the
  candidate reference-derived set — see "Reference audio and transitions".
- Presentation: impact/pickup/shield/spawn effects from event payloads;
  muzzle flashes anchored to the event's footprint and facing (the live rig
  contributes only its muzzle offset); the ADR-0005 own-fire base cue is an
  adapter-owned tinted silhouette overlay (teal for allied, red for enemy)
  — an SKAction on the vendor base node would not tint its private sprites;
  spawn-protection ring, invincibility ring, freeze overlay, equipment
  attachments; mines through `PixelMineNode` (badge, level, arming); pickup
  expiry blink; base shield appearing/warning phases; bounded effect and
  scorch pools; `PixelArt` retained across restarts; explicit surface
  change; ground strip clipped to the arena; liquids reconciled through
  terrain changes (water → steel → water).
- Debug overlay, collision box and the weapon cheat panel exist only in lab
  mode (`MOVEMENT_LAB=1`); the playable stage shows a provisional HUD with
  lives, armor, weapon/ammo, power/speed, equipment, status, enemies, base
  and score.

## Validation evidence (latest tree, 2026-09-10)

Recorded separately from the 2026-09-09 evidence below, which describes
the tree as it was then and is not rerun here. After the owner's
decisions of 2026-09-10 evening and the ADR-0012 results/bonus work:
`Scripts/ci.sh` passes end to end (Claude's run; PI was unavailable) —
architecture check, content validator, `Scripts/check-audio.sh` selftest
and check (18 synthesized files match the generator, 8 excerpts match the
manifest and the re-run extractor), `swift test` 329 tests / 82 suites (after M4 items 1–5, the arena, ADR-0017 and the follow-ups),
xcodegen, the simulator `xcodebuild test` on iPhone 17, the smoke render
selftest and the smoke render itself; `git diff --check` is clean. This
paragraph is the one current count; the handoff repeats it with the same
date.

## Validation evidence (2026-09-09)

- `swift test`: 193 tests / 45 suites at the round-7 closure (Claude;
  PI's independent run matched), 204 / 48 after the same-day
  owner-directed changes (round 8). Historical counts; the current one is
  in the section above.
- `xcodebuild test … 'platform=iOS Simulator,name=iPhone 17'`: succeeded
  (run by Claude after batch 3, after the round-4 fixes, and after the
  round-5 fixes; PI did not run the simulator gate).
- `sh Scripts/check-architecture.sh`: passed. `swift run content-validator
  Content`: passed. `git diff --check`: clean.
- Audio regeneration is deterministic (at the time: every existing WAV
  byte-identical by sha256, only `sfx_base_own_hit.wav` new). The
  2026-09-10 candidate set replaced most voices; PI regenerated that set
  twice outside the repository and matched all 28 files.
- The M1 movement golden was regenerated once with a stated reason: the
  checksum surface gained `BaseState` fields; the run fires no shot.

## Reference audio and transitions (owner direction 2026-09-09/10; ADR-0011 proposed)

The owner wants the reference game's (决战坦克) sound effects and transitions
replicated and supplied a complete gameplay recording (public video, 32
stages, ~50 min). Policy (plan §12.7, manifest §M): extracted reference
audio is research-only until the owner records a rights decision, and
RE-SYNTHESIS IS A CANDIDATE PRODUCTION METHOD, NOT CLEARANCE — the
candidate set in the working tree (`Tools/build_audio_assets.py`, rendered
at 8363 Hz with zero-order-hold upsampling as an audition hypothesis) is
provisional until the owner's audition and a recorded provenance/rights
review. Nothing extracted is in the repository. The research clips,
spectrograms and scripts were LOST with the machine restart of 2026-09-10
(≈10:17); what follows are Claude's reported measurements, not
independently re-verified by PI. The reproducible record is
`Tools/reference_measure/` (README with source id, timebase check, the
per-sound and per-transition windows, and the scripts; no media): rerunning
it on the public recording regenerates every number below.

Attribution status: CONFIRMED against frames — enemy destroyed (rumble),
pickup collected (arpeggio). UNCERTAIN — the glide taken as the shot, the
burst taken as the engine (and the engine's trigger: bursts while the
player stood still at 17.9 s, silence while an enemy kept moving at 52 s).
DERIVED — every other voice (launch variants, heavy explosion, base
collapse, pickup appearance, steel/brick/deflect, tally tick, stage card,
win stinger); INVENTED — the loss stinger (no loss in the recording;
removed 2026-09-10 late evening: the owner wants the reference passage at
every stage end).
Native-rate hypothesis: two mirror pairs sum to 8377 and 8355 Hz; a third
pair quoted earlier (2692 ↔ 5017 = 7709 Hz) does not fit and is withdrawn.
Per-file peak normalisation makes the envelope points relative shapes, not
calibrated dBFS.

Measured (STFT, 2.5–5 ms hops; times are positions in the recording):

| Sound | Where | Measurement → synthesis |
| --- | --- | --- |
| shot (assumed: the most frequent tonal event, runs at 0.2 s) | 43.17 s ×8, 87.8, 89.1, 90.2 s | pulse wave, exponential glide 3.1 kHz → 0.5 kHz, ≈0.26 s, flat then 30 ms release |
| engine burst (assumed: held direction) | 17.9–19.3 s, 47–52 s | 300 ms noise, broad, peak 2–2.5 kHz, roll-off above 3 kHz, V-chirp 2.3→3.0→2.2 kHz in the last 120 ms; 0.3 s on / 0.1 s off |
| enemy destroyed (confirmed: kill + score roll at 21.87 s) | 21.9 s, 63–67 s | 0.2 s low crunch (≤900 Hz) then a 260→170 Hz tone, −13 dBFS for 0.3 s, −40 dB by 0.7 s |
| heavy explosion (kill at 98.62 s) | 98.6, 100.3, 103.5 s | 0.2 s hiss (tread spectrum) then 0.6 s rumble ≤350 Hz |
| pickup collected (confirmed: score +2000 at 104.76 s; "Flag On Guard!" at 38.12 s) | 38.12, 104.76, 105.52 s | triangle notes C6 110 ms, C5 70, G6 30, C6 30, G5 90, C5 20, G6 30, E5 30, G5 70, C5 20, G6 20, C6 70, G5 20, C5 40; envelope −2 dB → −40 dB over 650 ms |
| steel click | 102.28 s | 2.69 kHz tone, 130 ms, −6 → −20 dB by 100 ms, over a 40 ms 150 Hz thump |
| tally blips | 77.4–77.7 s | 3.14 kHz and 1.85 kHz blips during the results table |
| stage card slide | 79.2–79.8 s | 1.2 → 0.86 kHz tonal slide under the title |
| results drum riff (reacquired audio; owner: "dong ×6, dong ×6, dong, dong ×4") | 73.9–78.3 s | ≈37 low-band hits (`hits.py`) in groups of 5–7, ≈0.12 s between hits, ≈0.24 s between group onsets; one hit: body ≈150–195 Hz, broadband stroke, −10 dB by ≈120 ms (0–250 Hz 0 dB, 250–500 −6, ≈−16 flat above 500 Hz). The first cut read this as an amplitude-modulated bed — wrong |
| stage-card drum riff (reacquired audio) | 78.3–79.6 s | the same riff (8 hits, rest, 2, rest, 1 …) until play; the first card (8.54–9.13 s) opens with six hits |

Transitions (frame-accurate, seeks verified against the audio):

- Intro: card 8.9 s; title slides in from the left 9.4–10.4 s and holds;
  cross-shaped strip reveal of the playfield 11.2–11.6 s; title flips away
  11.6–12.0 s; HUD and player spawn at 12.0 s.
- Outro: last sound 70.8 s; "Mission Complete" appears at the centre
  72.73 s and rises to the top by 73.07 s; playfield darkens 75.5–76.0 s;
  the results table (kills by enemy type, total, reward) slides in from the
  left 76.0–76.5 s and counts up with ticks; next stage card 78.27 s;
  reveal 79.5 s; play 80.0 s. The video has no loss, so the loss variant
  (same motion, restart button) is ours.

Implemented (2026-09-10): `StageFlow` (GameApplication, pure tick
timeline gating the simulation, cues for sounds; results capacity derived
from the tally, hold stretched to fit), `KillTally` (results rows from
events), the scene's per-cell curtain lifted in growing-cross order,
SwiftUI card/outcome/fade/panel animations with the measured durations
(touch controls hidden over the card and the results), the candidate set and its
mapping (`GameAudio.soundNames`); outcome stingers moved from the decisive
event to the transition. Round-11 corrections (PI): transient effects age
on the scene's presentation clock so the decisive tick's explosion plays
out during the outro; ONE input-admission policy (clock running AND flow in
play; every transition releases held/pending input and advances the reset
watermark, so cutscene presses never reach the first gameplay tick); the
completed recording is kept on the controller before the automatic
continue. Not implemented: the reference's stage-clear "Reward" bonus (a
scoring rule; owner decision), tank icons in the results rows, a title
screen. The automatic continue replays the same stage (provisional
prototype loop, not campaign progression).

Owner's CREATIVE decision of 2026-09-10 (later the same day, verbatim; not
a rights decision — the distribution-rights review stays PENDING for the
excerpts and the synthesized voices alike, `ASSET_PRODUCTION_MANIFEST.md`): "我不是让你重做，是让你采用
决战坦克原版的开场音效，我要求音效是复刻原版的" — the sounds are to be the ORIGINAL
game's sounds. Applied: `Tools/extract_reference_audio.py` extracts the
cleanest isolated instances from the pinned recording (isolation score:
silent margins), deterministically resampled; eight files are now
EXCERPTS of the recording (processed cuts, not the game's asset files) — `sfx_stage_win` (end-of-stage loop
74.00–78.20 s, the results screen from its rise to the card; the owner
identified it as the end sound), `sfx_fire_normal`/`_rapid`/`_special` (the one isolated
shot instance at 185.29 s; whether the reference has other launch sounds
is not established), `sfx_tank_explode`
(21.86 s), `sfx_player_explode` (heavy, 100.20 s), `sfx_pickup_collect`
(104.74 s), `sfx_hit_steel` (click, 102.26 s). The manifest marks them
`excerpt` with window, processing, file hash and the extractor's hash; `Scripts/check-audio.sh`
verifies hashes and re-extracts when `SPARKTREAD_REFERENCE_WAV` is set.
Cue table for the audition (source vs. attribution confidence are
separate columns):

| Cue | Source | Event assignment | Audition |
| --- | --- | --- | --- |
| stage card | ORIGINAL composition (`inspired`): NES-style jingle following Battle City's stage start (Namco) in key, tempo, rhythmic skeleton, instrumentation and length — own melody; no excerpt, not a transcription | owner chose this over a near-copy | ACCEPTED by the owner 2026-09-10 ("开场曲子我觉得可以") |
| stage won | excerpt (end-of-stage loop 74.00–78.20 s) | the results-screen loop the owner identified as the end sound | ACCEPTED by the owner 2026-09-10 ("结束曲还是用决战坦克的那个"); rights review pending |
| normal / rapid / special launch | excerpt (shot 185.29 s, one clip, three names) | glide = shot: assumed, uncontradicted | pending |
| enemy destroyed | excerpt (21.86 s) | confirmed (score roll) | pending |
| player destroyed | excerpt (heavy explosion 100.20 s) | assigned by sound design | pending |
| pickup collected | excerpt (104.74 s) | confirmed (score +2000) | pending |
| steel / boundary | excerpt (click 102.26 s) | assigned; cause not observed | pending |
| everything else | synthesized, provisional | derived / invented | pending |

Still synthesized (no isolated instance in the recording): brick hit,
deflect, pickup appear, tally tick, stage lose, base hit/own-hit/collapse/
shield, ap/explosion/flame/mine launches, flame loop, spawn warp, dry
fire, hit tank, explosion blast. The re-synthesized riff of the same day
is superseded.

Owner's opening-sound correction (2026-09-10, later still): the opening
reference is the first seven seconds of the NES Battle City sound-effects
video (Namco's stage-start jingle, 2.63–7.2 s of that video: two pulse
voices, triangle bass, noise drums on a 0.15 s grid, ≈100 bpm, 4.6 s), and
the owner asked whether it can be used without the copyright problem.
Recorded answer: it is Namco's composition and recording; an excerpt or a
note-for-note re-creation would reproduce it. Applied: `sfx_stage_card` is
an ORIGINAL NES-style jingle (generated, attribution `inspired` with the
second reference on its manifest entry). The owner then asked for a
near-copy of the melody with slight changes; Claude declined (slight
changes do not avoid copyright) and offered three paths; the owner chose
to keep the original and follow the reference's direction as far as
possible — the jingle now shares the reference's key/mode (C minor),
tempo (≈103 bpm), rhythmic skeleton, register, instrumentation and length
(≈4.66 s) with its own note sequences and contours (no note run of the
reference reproduced), no Battle City audio in the repository, the
provisional 决战坦克 card excerpt withdrawn (eight excerpts remain). Not a
legal clearance; the rights review for the whole set stays pending.

Earlier owner decisions after the device session (2026-09-10, applied): NO
engine/tread sound (voice, retrigger and tests removed; the attribution
question is moot); a LONGER sound on entering and on finishing a stage,
like the reference — `sfx_stage_card` is the 6-6-1-4 drum riff
(≈2.6 s; the owner corrected the first cut's throbbing bed the same day:
"开场音效错了", then sang the pattern) and `sfx_stage_win` the riff twice
(≈5.2 s) through the results, both from the reacquired recording's hit
measurements above and played at the card cue and at the outcome text;
`sfx_stage_lose` was an invented slower, falling variant (removed later
that day on the owner's instruction). The owner also
reported the tank's movement stuttering while firing rapid rounds: three
mitigations landed — the simulation driver's PREFERRED callback rate
is the tick rate (60 Hz; a preference, not a guarantee, and SpriteKit
renders on its own schedule — the hypothesis is that a 120 Hz callback
cadence alternated 0/1 ticks and turned into 0,1,1 under load), audio
voice pools are warmed at construction and playback never allocates or
restarts a playing voice (a short or busy pool drops the launch), and
own-recoil haptics are throttled to one impact per 0.12 s
(`RapidFireAudioTests`, `RecoilThrottleTests`). These are PLAUSIBLE
main-thread costs at twelve shots a second, not a profiled cause: the
symptom is undiagnosed until the owner's next device session compares
sustained movement with and without rapid fire (frame intervals and ticks
per rendered frame); if it persists, profile the per-hit effect-node
construction and `syncProjectiles`. Cue timing is adapted: the results bed
starts 0.45 s after the outcome text, the reference's about a second after
its text (historical pairing). The bed's band spectrum was tuned against
the reference bed with `bands.py` (a rough comparison: up to about 4 dB
off in one 250 Hz band, 0–4 kHz; PI reproduced the vector).

Owner check still open: is the synthesized set close enough — and in
either case the provenance/rights review has to be recorded before the
set is shipped.

## Owner-directed changes after the first device session (2026-09-09, after round 7)

Applied by Claude on the owner's feedback from the iPhone 17 Pro; PI
re-verified them in rounds 8–9 (R8-01 goal-cost convention, R8-02 fallback
placement legality, R8-03 replay boundary — all closed; see "Joint review
status"):

- Drops (carrier items and kill rolls) appear at a random interior cell
  anywhere on the map, never under the base or a tank — the fallback around
  the death cell keeps the same constraints, and an item with no legal cell
  anywhere near is lost rather than placed under a tank (`PickupRuleset.
  dropsSpawnAtRandomCells`, default true; ADR-0010 item 7, proposed).
  `spawnPickup` now excludes the base box for every placement.
- Enemy navigation (§10.4): a deterministic cost field over footprint
  anchors (`Navigation`), Dijkstra from the target — the four aligned
  firing positions beside the base (corner cells only as a fallback) or the
  player's neighbourhood — with steel/water/base impassable and brick
  passable at a cost for families whose weapon breaks brick (flame routes
  around it); the cost convention prices the goal cell too, so a cheap
  clear approach beats digging into an expensive one. At a goal the enemy
  faces the target and holds; the free-direction probe is snap-aware like
  the movement system, so a tank a few subunits off a dug opening still
  takes it. Base focus raised (normal 80 %, rapid 50 %, AP/explosion 90 %).
  Tests: field shape, mixed-cost goals, flame routing around brick, an
  enemy crosses the open arena and digs through a brick band to the fort
  (base shielded, approach only), an unobstructed enemy actually damages
  the base, and the first VS-01 wave reaches the fort ring within a minute.
  Observed in the fixtures: an enemy aligned with an unshielded base fires
  along the row and can destroy it from thirty cells away — reference
  behaviour, worth a device look.
- Replay format is now 3: earlier recordings embed a rules shape and an
  AI this build no longer reproduces and are rejected as
  `unsupportedFormat` at the DECODING boundary (header-first check, so a
  real format-2 file never surfaces as a key-not-found error). Policy, not
  an enforced build identity: a behaviour-changing simulation change must
  bump the number; an un-bumped one is undetectable except as a checksum
  mismatch (R8-03 / R9 closeout).

## Joint review status

Closed in round 7 (2026-09-09): PI independently re-verified every item it
had raised (R3-01…05, R4-01…06, R5-01…04, R6-01/02) against the current
tree with its own check programs and package test run, and reported no
further implementation correction in this scoped pass. Rounds 8–9
(2026-09-10) covered the owner-directed drops/navigation changes and the
replay boundary: R8-01/02 closed by PI's exact reproducers, R8-03 accepted
with the header-first decoding correction applied. Round 11 (reference
set + transitions) returned five findings — R11-01 outro effect clock,
R11-02 cutscene input leak, R11-03 engine attribution policy, R11-04
provenance/evidence wording, R11-05 results capacity — all applied with
integration tests (`StageFlowIntegrationTests`, 15 tests driving the
controller callback, the scene drain and the audio backend). Round 12: PI
closed R11-02…05 with its own reproducers and raised R12-01 (the scene's
presentation clock kept aging effects through a controller suspension) —
applied: `MovementLabScene.update` ages nothing while the controller is
not running and rebases on the first active frame, the SCENE is paused
while the scene phase is inactive (parking SKActions), two regressions
use the production update loop. The first cut passed `isPaused:` to the
`SpriteView` itself; that left the SKView blank on device and simulator
(owner report of 2026-09-10: flat gray after the intro, reproduced in the
simulator in the lab world too) and was replaced the same day. PI verified
the replacement on a separate, freshly created simulator (stage card,
post-intro playfield, lab, and rendering again after Settings and back) —
simulator evidence, not device acceptance. `Scripts/smoke-render.sh`
(in CI, needs ffmpeg) now cold-launches the stage and the lab and requires
real luminance spread in the playfield region with a bounded retry; the
HUD cannot serve as the assertion because it kept updating over the blank
SKView. Round 13: PI showed the remaining case — a
suspension with no frame in between still counted the clamped 0.1 s on
resume — fixed with `MovementLabController.activityGeneration`, which the
scene clock compares before computing elapsed time (control-compared
regression at the 0.70 s lifetime boundary with an observable clock
value); two README statements corrected (source sample rate not assumed,
61 ms ≈ two frames, pairing settled only by the alignment check). Round 14
(2026-09-10): PI reran every R11/R12 reproducer against the current
objects (suspended callbacks, no-inactive-frame resume at the 0.70 s
boundary, active-outro expiry, final-intro-tick presses, steel-blocked
engine, nine-archetype results) and recorded the R11/R12 findings as
independently reverified and CLOSED at this scope.

Round 15 (whole-tree pre-commit pass, 2026-09-10) raised nine items; all
applied:
- R15-01 (High) decoded out-of-domain entity ids trapped in AI cadence
  arithmetic → `WorldInvariants` checks every entity id and id reference
  (owners, hit lists) against `1..<nextEntityID`; −1 stays the documented
  no-owner sentinel; `EntityIDDomainTests` cover every entity kind, the
  exact boundary and PI's negative-enemy-id replay reproduction.
- R15-02 (High) a single `Int.max` enemy count passed validation →
  `StageValidator.maxEnemiesPerStage` (500) per entry and in total, timer
  and cap domains from `WorldInvariants`, and `StageBuilder` validates
  before it allocates (`StageBudgetTests`).
- R15-03 (Medium) open-edge worlds moved the nominal footprint outside the
  arena → movement bounds the NOMINAL footprint; the inset applies to
  obstacles only (`ArenaBoundaryTests`, four edges, approach, turn assist).
- R15-04 (Medium) session validated pickups only → all three rulesets are
  preconditioned; `MovementLabSession.make` throws for data
  (`SessionConfigurationTests`).
- R15-05 (Medium) every loss read "基地失守" → the loss reason travels with
  `StageFlow`, titles are truthful (`OutcomeTitleTests`); results rows
  scroll inside a panel bounded to half the surface, restart outside it —
  a layout policy, not device-verified for large tallies.
- R15-06 (Medium) README now states the Foundation exception at the
  content-loading boundary, matching the architecture check.
- R15-07 (Low) handoff consolidated (current counts, candidate status,
  round-14 closure), stale source comments fixed, event-anchor doc attached
  to `DomainEvent`; this document keeps dated evidence sections.
- R15-08 (Low) integration-test time is an explicit input advanced once per
  frame.
- R15-09 (Medium) `Tools/audio_manifest.json` (per-file sha256, length,
  attribution, generator hash, pending shipping review) and
  `Scripts/check-audio.sh` (regenerate outside the tree; compare files and
  manifest), wired into `Scripts/ci.sh`.
PI's suggested commit split (core/content contracts; adapter lifecycle and
presentation; stage orchestration + candidate audio + ADR; tooling + docs)
is recorded in the handoff for the owner. Rounds 16–17 closed R15
(R16-01 results hit testing, R16-02 evidence counts). Rounds 18–19
(owner-directed changes after the device session: no engine sound, longer
stage stingers from the reacquired audio, rapid-fire stutter mitigations):
PI closed R18-01 (playback never allocates), R18-02 (recoil boundary),
R18-03 (hypothesis wording) and requested no further synthesis change
before the owner's audition. Round 20 (owner: blank playfield on the
phone): cause was round 13's `SpriteView(isPaused:)` binding; replaced by
pausing the scene on inactivity; PI verified the replacement on a fresh
simulator; its recommended presentation smoke test is
`Scripts/smoke-render.sh` in CI (round 21). Round 21 (PI): the first
classifier accepted the intro card (contrast alone) and a failed launch
could pass — replaced by a gameplay-surface predicate (≥ 20 % frontier
ground pixels and ≥ 2 % brick pixels in the central crop), strict failure
propagation for launch/capture/classification, a simulator-free
`selftest` (synthetic positive; intro-card, flat and results-overlay
negatives; mock launch and capture failures must fail the gate), and
ffmpeg required under CI (`brew install ffmpeg` in the workflow) while a
local miss still skips with a notice. Round 22 (PI): the decoder's status
was masked by the pipeline and the results negative was whitened instead
of darkened — the crop is now decoded to a file with a checked ffmpeg
status (a decoder that fails after plausible output is rejected; self-
tested with a late-failing wrapper), and the results fixture uses output
maxima plus title/table blocks and is asserted darker than its source
before the classifier must reject it. Round 23: PI reran its decoder
injection and the real smoke on a fresh simulator (stage 61.4 % / 23.6 %,
lab 82.0 % / 10.6 %) and CLOSED rounds 20–22; the guard is a smoke check
for the frontier fixtures, not a general visual test, and
background/foreground automation stays deferred. Engineering review is closed
at every scope reviewed. Round 24 (drum riff): PI accepted the owner's
6-6-1-4 phrasing for the synthesized riff and raised R24-01 (docs still
described the removed bed) and R24-02 (`hits.py` timebase) — R24-02
applied (frame times from hop/rate, detector labelled heuristic); R24-01
is superseded by the owner's originals decision, and the builder's riff
comments were corrected for the one synthesized use left (the loss
stinger). Round 25 (excerpts): PI closed R25-01 (creative decision separated from the
PENDING rights review; "excerpt" terminology), R25-02 (extractor hash and
full excerpt-metadata comparison, self-tested), R25-03 (protected names
refused before any write) and R25-04 (mapping rewritten) in round 26,
which raised R26-01 (metadata wording: provisional endpoint, one
selected launch instance, 15–80 ms fades, the silent-margin exception)
and R26-02 (preserve the rhythm-analysis scripts and windows in the
record) — both applied. The opening-sound excerpt stays PROVISIONAL until
the owner pinpoints it; no further blind re-cut. Round 27 (original jingle): PI accepted `inspired` as a provenance class
(not a legal conclusion), kept the intro duration (the jingle's tail
overlaps ≈1.8 s of play; duck rather than delay control if cues suffer),
and raised R27-01 (the excerpt self-tests mutated the now-generated card)
and R27-02 (comment/README/provenance migration) — both applied: the
self-tests target `sfx_stage_win.wav` after asserting it is an excerpt,
generated entries have their own corruption cases, the card's manifest
entry carries its inspiration provenance, durations are stated as phrase
vs file, and the README's withdrawn windows are marked historical. The standing limits (audition, provenance/rights, device
performance/layout, video re-alignment, ADR acceptance, commit) are the
owner's. Standing limits stay
explicit and pending: owner audition, reconstructed measurement evidence
(a rerun of `Tools/reference_measure/`), provenance/rights review,
large-results-panel layout, device readability/mix/performance, broader
product acceptance. (ADR-0010 and ADR-0011 were accepted by the owner
later on 2026-09-10 — see the decisions below; the review itself never
accepted them on the owner's behalf.) Round 28 (R27-01/02 applied, the
jingle revised toward the reference's direction and accepted by the
owner) reached PI, which began verifying (`check-audio.sh selftest` in
both modes, `git diff --check`) and then hit its ChatGPT usage limit
("Try again in ~7167 min", ≈5 days); the round has no PI reply. The
changes after round 27 (jingle revision, the owner's decisions B/3/4/6/7,
the reward rule) are therefore Claude-only until PI is back. This is a scoped
review sign-off, not a claim that every possible malformed recording is
safe, that the product is complete, or that device/audio acceptance has
passed — see the gaps below.

## Owner decisions of 2026-09-10 (evening)

Recorded verbatim: "应该是 B 恢复为加固前记录的材质；3 正确；4 正确；5，按照原作来；6 消失了；7 提交；9 不用".

- ADR-0010 accepted; fort-ring restoration = B (recorded materials):
  `PickupRuleset.fortRingRestoresRecordedKinds` now defaults to `true`.
- ADR-0011 accepted; the shot attribution (the glide) confirmed.
- Rights: the owner reviewed and accepts the use of the eight recording
  excerpts, the synthesized voices and the original jingle with no
  third-party licence held; recorded in `Tools/audio_manifest.json`
  (`rights_review`) — the decision and its responsibility are the owner's.
- Stage-clear reward: to follow the reference ("按照原作来") — measured
  from the reference's results screens and implemented the same evening
  (ADR-0012, proposed; section below).
- Rapid-fire stutter: gone on the device ("消失了").
- Commit the tree ("提交"); no CLAUDE.md ("不用").
- Invincibility duration: decided later the same evening — A, keep 10 s
  ("保持 10 秒"); the ruleset default stands, the reference's 25 s rule
  stays expressible data.

Second batch, 2026-09-10 late evening (on ADR-0012's questions and the
first device look at the results panel): invincibility "保持 10 秒"; the
bonus bracket rule "我不知道原作怎么算的，你可以用一种最合理的方式来决定" (delegated —
the stage-number brackets stay, see ADR-0012); MaxHits/MaxCombos "不要";
table icons "坦克图标". Two complaints: the results panel "很难看" (the
first cut stretched across the whole landscape surface with the subtotals
far from the counts) and the stage-end music "时好时坏，需要用决战坦克的那个音效"
— a lost stage played the invented falling stinger, a won one the
reference excerpt. Applied: the panel is a compact reference-style card
on the left (title band, "icon count icon count ×k = subtotal" rows with
the tank icons composed from the rig sprites, rule, 总计, the reward text
rising over the title, score and restart in the footer; width 44 % of the
surface, at most 400 pt); the reference's results passage plays at every
stage end and the invented loss stinger is removed from the generator,
the bundle and the manifest (26 files).

## Stage-clear results table and bonuses (owner decision 5, 2026-09-10 evening; ADR-0012 proposed)

Survey (`Tools/reference_measure/results_screens.py`, media-free) of the
first 30 results screens of the owner's recording (the video's last 9 %
would not download; 30 of 32 stages). Read by eye from the crops:

- The table is FOUR rows of two tank icons with kill counts, "×k =" and a
  subtotal (k = 1…4), then "总计" = Σ subtotals; a "MaxHits N / MaxCombos
  N" line sits above. Every screen obeys subtotal = (left + right) × k
  (stage 3: (2+2)×1, (3+0)×2, (2+0)×3, (1+0)×4 → 20). The eight icons are
  the eight §8.2 reward categories in row-major order (rows 1 and 4 pair
  two colour variants of one chassis: the Normal pairs, the AP pairs) —
  inferred from the icons, not from attributing kills in the footage.
- Two constant bonuses per cleared stage, read from the score counter
  before/after the panel and the rising "Reward +N" text: stages 1–10
  tally +200 / reward +330; 11–25 +600 / +660; 26–30 +1000 / +1000.
  Independent of kills, total, MaxHits and MaxCombos (stage 1: 6 kills →
  200/330; stage 7: 25 kills, hits 7, combos 5 → 200/330). The score
  counter animates; a treasure still counting in at the first panel
  frame explains the few larger differences (e.g. +1600 at stage 17).
- Ambiguity recorded: the recording's two continues (score resets at
  stages 11 and 26) coincide with the bracket changes, so a rule based on
  continues or lives cannot be excluded; the stage-number bracket is the
  implemented default. Owner decision attached in ADR-0012.

Implemented: `EnemyArchetypes.Attributes.rewardCategory` (the §8.2
column, now verified as the table category); `ScoreRules` (GameCore data:
tiers by stage number, `rewardMultiplier`); `StageState.clearBonus` set
by the builder from the required content field `stageNumber` (validator
1…999; VS-01 states 1); the bonus is paid to every active player on the
deciding tick after `stageWon` with a `stageClearBonus(tally:reward:)`
event, checksummed and bounded, decoding as `.none` when absent; a lost
stage pays nothing. `KillTally` groups kills by category with row counts,
subtotals and the weighted total; `StageFlow` adds the `.reward` cue 18
ticks after the total line on a won stage with a bonus (hold stretched);
the controller withholds the tally bonus from the HUD score until the
total line and the reward until the reward line, so the shown score
counts in as the reference does while the world's score is final at the
decision; the panel shows the four category rows, "总计", "奖励 +N" and
the score. Not implemented (owner decisions in ADR-0012): MaxHits /
MaxCombos (semantics unknown), tank icons, a reward sound.

Icons (owner: "坦克图标"): `PixelTankIcons` composes one up-facing enemy
tank per category from the rig's tread, hull and turret sprites (the same
mapping the scene uses, now shared as `PixelTankNode.appearance`), cropped
to the rig body bounds (32×26 px) and drawn nearest-neighbour; the view
builds the eight icons once from the scene's art when the panel is about
to show and falls back to the category label if the art is unavailable.

Tests: `ResultsIconsTests` (every category renders an opaque 32×26 icon;
the mapping), `ScoreRulesTests` (tiers, categories, payment on the deciding tick,
no double payment, loss pays nothing, checksum/invariants, legacy decode),
`StageFlowTests` (reward cue timing and gating, category grouping),
`StageContentTests` (stage number required, tier selection),
`StageFlowIntegrationTests` (HUD payout pacing, five tally ticks, reset
with the world). Claude-only: PI was unavailable (usage limit).

## Designed outro and the centred results card (owner feedback 2026-09-10 late evening)

Owner, on the device with the first icon panel (verbatim): "结束了不管是全军覆没还是
胜利了或者输了，可以设计一个好一些的转场。转场完了播放类似这样的总结页面，但这个起码得居中，并确保
不同数字的时候也是能够对齐的". Applied:

- The outro is now a DESIGNED transition (the intro keeps the reference's
  measured timings): 0.8 s freeze while the decisive effect plays out; the
  outcome title stamps into the centre (scale 2.6 → 1 spring) with a
  screen flash (white on a win, red on a loss) and, on a loss, a decaying
  shake, over a one-line reason ("敌军全部歼灭" / "基地被摧毁" / "所有坦克损失");
  1.4 s hold; 0.7 s in which the title glides to the top at 60 % size
  while the scene drops black tiles over the arena from the edges to the
  centre (`StageFlow.coverStep`, a closing box iris — the reverse of the
  intro's growing cross); then the results card pops in centred (scale
  0.85 → 1 spring) and the tally runs as before. The HUD hides once the
  curtain is down; the card carries the score. `StageFlow.Durations`:
  outroDelay 48, outroText 24, outroHold 84, outroFade 42, panelIn 21.
- The card is centred (46 % of the width, at most 420 pt), and every
  number sits in a fixed right-aligned monospaced column with plain
  digits (no grouping separators): counts three digits, subtotals four,
  the total five — different values keep the columns aligned.
- Tests: `StageFlowTests` (outro length 329 ticks; the cover advances
  monotonically during the fade and stays closed), `OutcomeTitleTests`
  (subtitles). The sequence was captured frame by frame in the simulator
  on a loss; the owner accepted the transition and the card on the device
  ("我觉得挺好", 2026-09-10 late evening).

## M4 item 1 — campaign progression (2026-09-10 late evening; ADR-0013 proposed)

Owner: "把前 5 项给做完吧" and, for the maps, "按照原来地图，但是适配新的屏幕比例，允许你在
原版基础上按照你认为最合适的方式自由发挥". Landed:

- Content: `frontier_02_hidden_in_grass` (water channels, foliage cover,
  brick blocks, steel plates; 22 enemies: Normal A/C, Rapid A/B, Fire A)
  and `frontier_03_desert_stairs` (steel staircases on open sand; 24
  enemies incl. Explosion A, AP A/C), both read from the reference
  recording's play-start frames and re-drawn for 56×27 with the owner's
  latitude; `Content/campaigns/campaign_v1.json`; the registry's seeded
  placeholder ids replaced; the content validator checks campaigns
  against stages (existence, number = position).
- `SessionState` (carried lives/score/ammo/retained upgrades; armor
  resets), `CampaignRun` (stage index + checkpoint), builder/loader
  `session:` parameter with domain checks, replay format 4 with the
  campaign header and `ReplayPlayer.replayCampaign` (chain check,
  outcome required), controller campaign walk (automatic advance with
  the exit state, retry from the checkpoint, "战役完成 / 再来一局" after the
  last stage, completed recordings kept as the run's campaign replay).
- Tests (272 / 67): `SessionStateTests`, `CampaignRunTests`,
  `CampaignReplayTests` (three real stages chained; tampered header and
  undecided stage refused), the controller campaign test (advance, carry,
  retry from checkpoint, completion, restart), every shipped stage
  validated/built/numbered, replay format 4 boundary.

## M4 item 2 — screen flow (2026-09-10 late evening)

Plan §12.1 "Title → Campaign / Stage Select → Stage Intro → Gameplay →
Pause (overlay) → Stage Results → Next Stage / Retry / Exit", provisional
text treatment (no Phase 1 art):

- `AppRootView` renders `AppFlowModel` (pure state: title, campaign
  select, playing; stage unlock = first or predecessor completed;
  suggested stage = first not completed; completed stages recorded per
  app run until the checkpoint save lands). Title: 开始战役 / 训练场.
  Campaign select: one card per stage (number/subtitle from the id,
  已通关 / 可进入 / 未解锁, suggested card highlighted), 返回. The game screen
  gets an exit callback (返回标题 on the pause overlay, on a loss and after
  the campaign completes). Launch environment: `SPARKTREAD_AUTOSTART=1`
  skips the title into the campaign (the render smoke test uses it),
  `MOVEMENT_LAB=1` into the lab.
- Pause is an explicit controller state (ADR-0007): `pause()` stops the
  clock and closes the input gate, `resume()` restarts with a fresh
  clock; activations do not lift a pause. Losing the active state
  MID-PLAY becomes a player-visible pause (the overlay waits for 继续);
  during an intro, outro or results it just suspends and resumes as
  before. The pause/back action (§6.3) is keyboard Escape/P and the
  gamepad Menu button (provisional bindings) plus a HUD button; the
  press is an edge outside the activity gate (the same key resumes) and
  is polled by the view's flow timer, not the tick. Overlay: 继续 /
  重新开始本关 / 返回标题.
- Tests (279 / 70): `AppFlowModelTests`, `PauseBindingTests`,
  `PauseLifecycleTests` (clock stopped, input refused, activation keeps
  the pause, inactivity mid-play pauses, intro just suspends, restart
  clears the pause).
- Not in this item: settings, input-selection screen, accessibility
  options (M4 "settings, accessibility baseline, controller support" is
  the owner's item 6).

## M4 item 3 — checkpoint save and suspended session (2026-09-10 late evening; ADR-0014 proposed)

- Documents: `CampaignProgress` and `SuspendedSession` (versioned,
  self-validating), `SaveSchema` version gate (migration table empty at
  version 1), `CampaignPersistence` protocol, `InMemorySaveStore`,
  `FileSaveStore` (Application Support/SparkTread, atomic sorted JSON,
  version read first, errors not crashes).
- Controller: the snapshot is written on inactivity mid-play (before the
  clock stops), cleared on decision and abandonment; progress is
  checkpointed after each won stage (next run as checkpoint, best
  score); `init(resuming:)` continues the snapshot's recording, skips
  the intro and opens paused; failures land on `persistenceFailure`.
- Title: 继续上次战斗 (snapshot) / 继续战役 (checkpoint) / 新的战役 / 训练场,
  store notices; declining the snapshot discards it; stage cards start
  the checkpoint run when it is that stage.
- Tests (290 / 74): documents and version gate, snapshot → resume equals
  an uninterrupted run (session and controller), the resumed recording
  replays as one recording, write/clear/checkpoint timing, a failing
  store reported not fatal, file store round trip / foreign version /
  corrupt file.

## M4 item 4 — difficulty profiles and director phases (2026-09-10 late evening; ADR-0015 proposed)

- `EnemyBehaviorProfile` in `StageState` (decision interval, base-focus
  scale, wander, fire-window scale, mine roll, course commitment;
  checksummed, range-checked; `.standard` = the previous constants);
  the enemy brain reads it. `DirectorPhase` list + cursor in
  `StageState`; the director fires phases once in order (reinforcements
  jump the queue, cap change, base repair) with events, a HUD notice and
  cues. VS-03 authors the elite mine-layer wave after 16 spawns.
- `DifficultyDefinition` content (casual/standard/veteran; behaviour,
  telegraph percent with the 45-tick floor, composition variant,
  allied base damage Off/On/On, enemy ammo percent recorded only), the
  loader/validator, the tool requiring the three presets; the builder
  applies it; `CampaignRun.difficultyID`; replay format 5 with the
  difficulty in the header; the stage provider hands the session the
  difficulty's weapon rules; the stage-select difficulty picker.
- Tests (304 / 77): profile validation and effect (closed window never
  fires, wide fires more, interval paces decisions), phases (once, in
  order, cap, repair, paired carriers), presets load and differ as the
  plan intends, variants and the floor, builder application, run and
  header naming, notice raise/expiry, app-flow difficulty choice.

## M4 item 5 — deferred mechanics (2026-09-10 late evening; ADR-0016 proposed)

- Traversal profiles: `TraversalProfile` from equipment; water blocks all
  but AmphiTank through `TerrainKind/TerrainGrid.blocksTank(profile:)`,
  `Simulation.ObstacleField` (the mover's profile; a tank that loses
  AmphiTank over water may leave, never re-enter) and `Navigation`
  (profile beside `canDig`; the brain passes its own).
- Ice inertia: `MovementRuleset.iceSlideDistanceSubunits` 1536; centre
  cell on ice + no AntiSkid → release or direction change slides the
  distance along the last travel direction at normal speed; input turns
  the facing only, the slide direction cancels; blocks/leaving ice end
  it. Enemies too. The M1 movement golden was regenerated (note in the
  test: the script crosses the lab's ice patch and turns on it).
- Foliage: scene overlay at z 520 (tanks 500 < foliage < mines 600),
  47-joint textures with a slow frame cycle, 45 % fade over the player's
  footprint; presentation only (AI perception §24 Q8 open).
- Mine launch: `WeaponRuleset` launch distance/airborne/slow per level
  and the enable switch, `MovementRuleset.slowedSpeedPercent`;
  `TankState.landingSubunits` (checksummed, invariant-bound); the
  triggering survivor (Memory of Sea exempt) flies along its travel
  direction, suspended from movement, fire, targeting, blasts, flames,
  mines, pickups and blocking; lands by ring scan when the status
  expires; slowed after. Scene: a scale bump on launch, reset on landing.
- Replay format 6. Tests (319 / 81): `TraversalProfileTests`,
  `IceInertiaTests`, `MineLaunchTests`, the foliage presentation test.
- Not done (recorded in the ADR): the §15.3 per-archetype reachability
  waiver, foliage flammability and AI perception, wake/skid decals and
  a landing effect, a wake for amphibious tanks.

## Training Arena (owner direction 2026-09-10 late evening)

Owner (verbatim): "训练场应该有各种地形，所有类型的坦克，所有类型的砖墙，并且可以自由选择掉落不同的
装备，选择不同的子弹。所有类型的坦克也可以活动并且发出它们该有的导弹，只是我死亡之后可以无限复活，
以及自己的老家无法被摧毁。敌方坦克死亡会立即复活。另外，现在的武器和暂停按钮重叠在一起无法点击选择".

- `TrainingArenaFixture` (GameApplication): every terrain kind, all eight
  damaged-brick and four damaged-steel quadrant states, a water pool with
  a foliage shore, an ice rink, a foliage patch, a mixed fortress, the
  base with its brick U; all 24 enemy archetypes on a parade ground with
  the director's attributes and their family weapons; a stage (phase
  playing, empty queue) so the brain and the player lifecycle run; the
  base at 999/999 and the player at 999 lives.
- Arena rules (`MovementLabSession.trainingArena()`, lab only, outside
  the command stream — each intervention rebases the recording): a
  destroyed enemy respawns at once (same archetype, round-robin spawn
  cells, nearest free footprint), the base is repaired to full every
  tick, lives are topped up when low. `debugSpawnPickup` drops any of
  the 25 known pickups one cell ahead of the player.
- UI: the pause button moved to the top-LEFT; the top-right "训练面板"
  (collapsible, scrolling) has the weapon and power selectors, the
  pickup spawner grid and 重置训练场. The M1 movement fixture and its
  golden are untouched (the arena is a separate fixture).
- Tests: `TrainingArenaTests` (contents, enemies drive and fire several
  families, respawn/repair/lives, pickup spawner, the flag).
- Owner, on the device (verbatim): "一种类型的坦克一个就可以了；另外带红圈的坦克是什么，
  红圈位置也不对啊". Applied: the parade is one tank per weapon family (the
  A tiers; 6 tanks); the "red circle" is the §10.6 danger telegraph of
  the AP/Explosion/Fire/Mine families (a dashed ring with a warning
  triangle, tinted per family, bright when ready to fire) — it was
  drawn floating above the tank at 0.7 scale, which read as a misplaced
  circle; it now encircles the tank on its ground pivot at full scale.

## Owner rules of 2026-09-10 late evening (ADR-0017, accepted)

Verbatim: "训练场还是改成我点击一个按钮增加一个类型的坦克吧，不同类型的坦克按照抵抗力从低到高排序
让我选择"; "火焰弹打到草坪的时候，应该需要把相邻的草坪都点着"; "移除掉红圈这个设计，不需要警告".
Applied: the arena starts empty and the panel adds one archetype per
tap (24 buttons, resistance ascending, "清空敌人"); flames on foliage
spread to the neighbouring foliage after 20 ticks and burn it to ground
(ruleset data; ownerless spread patches; burned-grass decal; replay
format 7); the §10.6 danger telegraph is removed. Tests 331 / 82.

## Owner follow-ups (2026-09-10 late evening, second device look)

- "带月牙的坦克，月牙的位置错了": the vendor's four `px_equipment_moon_*`
  sprites all draw the crescent on the tank's RIGHT (the plow belongs at
  the front); `PixelTankNode.setEquipment` now uses the right-facing
  sprite rotated to the facing (`frontRotation`). Amphi/AntiSkid skirts
  and the Memory of Sea sensor keep their per-facing sprites (they were
  drawn correctly).
- "每种坦克一个按钮，点击这个按钮之后让我选择这个坦克的火力等级以及它可以搭配的装备": the
  training panel offers six family buttons; choosing one shows 火力 P0–P3
  and 装备 (无 / 两栖 / 防滑 / 月牙 / 海忆) and an 添加 button; the tank is the
  family's A archetype with those overrides, and respawns with them.
- "你是不是缺少能在冰面上走的装备": 防滑 (`anti_skid`) is that equipment — the
  traction profile never slides (ADR-0016); it is in the pickup spawner
  and the enemy equipment picker.

## Reference rules reverse-engineering (owner direction 2026-09-11, in progress)

The owner replaced rule-by-rule decisions with: derive the original's rules
from the reference video (all 31 stages) — shells, terrain, equipment,
brick × shell, tank × equipment × terrain, and their combination — into one
document, reach consensus with PI, have the owner review it, and only then
delegate implementation to Opus-class agents. State:

- `docs/REFERENCE_GAMEPLAY_RULES_ZH.md` (draft v0.1): evidence tags
  【V】video / 【B】【C】decompile / 【M】modern / 【?】owner; matrices for
  shell × terrain, shell × tank, terrain × equipment, equipment × mine,
  pickups, enemy slots; §9 deviation list D-01…D-23. Weapon facts are in
  `GAME_MECHANICS_SPEC.md` §5.4, world facts (enemy catalogue and speeds,
  hits-to-kill anchors, terrain, pickups/HUD, equipment, base ring,
  spawning, death/continue persistence) in §7.1/§8.4/§10.4. PI's
  round-32 frame check rejected the world half's high-impact claims
  (hits-to-kill anchors, Armor Up +1, kill-site drops, death resets,
  "steel U" base ring, Explosion-only steel damage): they are recorded as
  observations with unresolved attribution, and D-16…D-23 are framed as
  design choices for the owner (keep accepted policy unless the owner
  chooses otherwise), not as restoration fixes.
- Notable corrections to earlier assumptions (after PI's round-30
  cross-check): the reference base cell is 12 px in the 480×360 encode
  (tank = 2×2 cells), so Normal is 15.75 cells/s and the current code's
  11.25 cells/s (LV0–1) is 29 % slower than that unclassified-level
  sample; Fire is a visible delivery round that leaves persistent fire
  where it stops (rendered footprint 2×2 / 2×1 base cells, visible burn
  ≈5.5–5.8 s in the inspected samples, no attributable autonomous spread
  in the inspected non-foliage samples); AP/Explosion accelerate (caps
  unmeasured); the player's Rapid speed could not be attributed (the fast
  rounds at t=2465 belong to an enemy); mines were not identified in the
  recording. PI's round-31 wording review (video observations must not be
  promoted to immunity/absence/cap claims) is applied.
- PI's round-29 inventory (R29-01…25, verified with probes against
  `30af2b9`) is the "current code" column; R29-17 (Bomb damages airborne
  tanks) is a plain consistency defect to fix without a decision.
- Nothing in the code changed for this work; no implementation before the
  owner confirms §9.

## Remaining gaps / follow-up review

Do not interpret green tests as product completion:

- Physical-device legibility, touch occlusion, audio mix and sustained
  performance are unverified (ADR-0006 gate still pending).
- VS-01 keeps the owner-directed reference layout; the plan's "one visible
  Speed or Power pickup" teaching goal is served by carriers and hidden
  treasures, which is a recorded deviation, not equivalence.
- Still deferred: settings, tutorials, accessibility options, the
  input-selection screen (the rest of the former M4 deferral list —
  traversal, ice, foliage, difficulty, mine launch, persistence, pause,
  title — landed on 2026-09-10 late evening).
- Explosions resolve after the contact queue (documented approximation).
- The ground tile family is fixed to the frontier theme until stage data
  selects it.
- Reachability validation is a cell flood approximation.
- Owner decisions: none open after 2026-09-10 late evening (invincibility
  A; ADR-0012 answered — brackets by delegation, no MaxHits/MaxCombos,
  icons; the designed outro and the centred card accepted on the device).
  M3's slice is complete at the owner's acceptance level; M4 (plan §19)
  items 1–5 landed on 2026-09-10 late evening (ADR-0013…0016 proposed):
  campaign progression, screen flow, checkpoint save, difficulty
  profiles and director phases, the deferred mechanics. Remaining M4
  deliverables: settings/accessibility/controller support (owner's item
  6), the external playtest build, the "final replacement visual
  language", performance/export targets, and a played three-stage golden.
